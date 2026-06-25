import Foundation

// MARK: - Talaria Models Shim client
//
// Talks to the tailnet-bound "models shim" on OJAMD (see tools/models-shim/).
// The shim exposes Hermes's real model list and a persistent set-default without
// the privileged dashboard plane:
//   GET  /models?refresh=0|1   → ShimModelOptions
//   POST /models/default        → ShimSetDefaultResponse
// Auth is a bearer token (Keychain on device; DEBUG launch-env fallback for tests).
//
// Notes baked in from the live contract:
//  • `compiled_at` / `ttl_seconds` / `refreshed` exist only on the LIVE shim — the
//    captured fixture lacks them, so they are OPTIONAL here.
//  • Model ids are bare for some providers (kimi-k2.7-code) and slashed for others
//    (anthropic/claude-opus-4.8). Both are valid; we pass them through verbatim.
//  • The active model is the row whose id == top-level `model`, inside the provider
//    with is_current == true. Provider slug != top-level `provider` for kimi
//    (slug "kimi-coding" vs provider "kimi-for-coding"); the shim normalizes the
//    POST body, so we send the provider ROW's slug.

// MARK: DTOs

/// `GET /models` payload. snake_case is mapped via `.convertFromSnakeCase`.
struct ShimModelOptions: Decodable, Sendable {
    let providers: [ShimProviderRow]
    /// Current persistent default model id (e.g. "kimi-k2.7-code"). Optional for
    /// safety against a freshly-reset config.
    let model: String?
    /// Top-level config provider string (e.g. "kimi-for-coding"). NOTE: this does
    /// NOT necessarily equal any row's `slug` — do not match active state on it.
    let provider: String?
    /// LIVE-only freshness fields — absent on the fixture, hence optional.
    let compiledAt: String?
    let ttlSeconds: Int?
    let refreshed: Bool?
}

/// One provider row from the shim. `id` == `slug` for SwiftUI identity.
struct ShimProviderRow: Decodable, Identifiable, Hashable, Sendable {
    let slug: String
    let name: String?
    let isCurrent: Bool?
    let isUserDefined: Bool?
    let authenticated: Bool?
    let models: [String]?
    let totalModels: Int?
    let source: String?

    var id: String { slug }

    var displayName: String { (name?.isEmpty == false ? name! : slug) }
    var isAuthenticated: Bool { authenticated ?? false }
    var current: Bool { isCurrent ?? false }
    var modelIDs: [String] { models ?? [] }
}

/// `POST /models/default` response. Three shapes collapse into this:
///  • success:        { ok:true,  scope, provider, model, ... }
///  • confirm guard:  { ok:false, confirm_required:true, confirm_message, ... }
///  • error:          { ok:false, error }  (may arrive with a 4xx/5xx)
struct ShimSetDefaultResponse: Decodable, Sendable {
    let ok: Bool?
    let scope: String?
    let provider: String?
    let model: String?
    let confirmRequired: Bool?
    let confirmMessage: String?
    let error: String?
}

// MARK: Outcome / errors

enum ShimSetDefaultOutcome: Sendable {
    case success(provider: String?, model: String?)
    /// The shim guards expensive models; re-POST with `confirmExpensive: true`.
    case confirmRequired(message: String)
}

enum ModelsShimError: LocalizedError {
    case notConfigured(String)
    case unauthorized
    case http(status: Int, body: String?)
    case server(message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let why): return why
        case .unauthorized: return "Shim rejected the token (401/403). Check the bearer token in Settings → Models."
        case .http(let status, let body):
            if let body, !body.isEmpty { return "Shim returned HTTP \(status): \(body)" }
            return "Shim returned HTTP \(status)."
        case .server(let message): return message
        case .decoding(let detail): return "Couldn't read the shim response: \(detail)"
        }
    }
}

// MARK: Token box

/// Reference holder so the client's @MainActor token closure reads the latest
/// token without recreating the client. AppContainer rewrites `value` on save.
@MainActor
final class MutableShimTokenBox {
    var value: String = ""
}

// MARK: Client

@MainActor
final class ModelsShimClient {
    private let baseURLProvider: @MainActor () -> String?
    private let tokenProvider: @MainActor () -> String?
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    init(
        baseURLProvider: @escaping @MainActor () -> String?,
        tokenProvider: @escaping @MainActor () -> String?,
        session: URLSession = .shared
    ) {
        self.baseURLProvider = baseURLProvider
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// `GET /models?refresh=0|1`. `refresh=true` busts the per-provider disk cache
    /// and re-hits every provider's live `/v1/models` — genuinely slow (~20–60s),
    /// so callers MUST run this off the UI's critical path with a spinner.
    func fetchModels(refresh: Bool) async throws -> ShimModelOptions {
        let path = "/models?refresh=\(refresh ? 1 : 0)"
        let request = try makeRequest(path: path, method: "GET", body: nil, timeout: refresh ? 120 : 30)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        do {
            return try decoder.decode(ShimModelOptions.self, from: data)
        } catch {
            throw ModelsShimError.decoding(String(describing: error))
        }
    }

    /// `POST /models/default` — sets the persistent main default (new-session scope).
    /// `provider` MUST be the provider ROW's `slug` (the shim normalizes it to the
    /// config provider). Returns `.confirmRequired` for the expensive-model guard.
    func setDefault(provider: String, model: String, confirmExpensive: Bool = false) async throws -> ShimSetDefaultOutcome {
        struct Body: Encodable {
            let provider: String
            let model: String
            let confirmExpensive: Bool?
        }
        let body = Body(provider: provider, model: model, confirmExpensive: confirmExpensive ? true : nil)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(path: "/models/default", method: "POST", body: encoded, timeout: 60)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw ModelsShimError.unauthorized }

        // The confirm-guard and validation errors can ride on a non-2xx, so decode
        // the body before deciding — only fall back to a raw HTTP error if that fails.
        let decoded = try? decoder.decode(ShimSetDefaultResponse.self, from: data)
        if let decoded {
            if decoded.confirmRequired == true {
                let msg = decoded.confirmMessage ?? "This model may be expensive. Confirm to set it as the default?"
                return .confirmRequired(message: msg)
            }
            if decoded.ok == true {
                return .success(provider: decoded.provider, model: decoded.model)
            }
            if let err = decoded.error, !err.isEmpty {
                throw ModelsShimError.server(message: err)
            }
        }
        // No usable body — surface the HTTP status.
        guard (200...299).contains(status) else {
            throw ModelsShimError.http(status: status, body: String(data: data, encoding: .utf8))
        }
        // 2xx but unparseable / ok:false with no error — treat as success defensively.
        return .success(provider: provider, model: model)
    }

    // MARK: - HTTP plumbing

    private func makeRequest(path: String, method: String, body: Data?, timeout: TimeInterval) throws -> URLRequest {
        guard let rawBase = baseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawBase.isEmpty,
              let url = URL(string: normalizedBase(rawBase) + path) else {
            throw ModelsShimError.notConfigured("Models shim URL is not set (Settings → Models).")
        }
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ModelsShimError.notConfigured("Models shim token is not set (Settings → Models).")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = timeout
        return request
    }

    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 { throw ModelsShimError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw ModelsShimError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    /// Trims a trailing slash so `base + "/models"` never doubles up.
    private func normalizedBase(_ base: String) -> String {
        base.hasSuffix("/") ? String(base.dropLast()) : base
    }
}
