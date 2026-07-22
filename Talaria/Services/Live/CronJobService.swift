import Foundation
import os

/// #156a — client over the Hermes gateway's eight `/api/jobs` endpoints
/// (verified hermes-agent 0.19.0). Same `:8642` base + Bearer
/// `API_SERVER_KEY` the chat path uses; no relay, no connector, no new
/// services (#161).
@MainActor
protocol CronJobServiceProtocol {
    func listJobs() async throws -> [CronJob]
    func job(id: String) async throws -> CronJob
    func createJob(_ body: CronJobCreateBody) async throws -> CronJob
    func updateJob(id: String, patch: CronJobPatchBody) async throws -> CronJob
    func deleteJob(id: String) async throws
    func pauseJob(id: String) async throws -> CronJob
    func resumeJob(id: String) async throws -> CronJob
    func runJob(id: String) async throws -> CronJob
    /// Connected platform names from `/health/detailed` — the server-driven
    /// half of the deliver picker (D5). nil = unavailable (the picker
    /// degrades to free text); never throws.
    func deliverPlatforms() async -> [String]?
}

/// Typed, user-renderable failures (D1). `serverRejected` carries the
/// server's `{"error": ...}` message VERBATIM — the server is the only cron
/// validator that exists, so its text is what the create/edit sheet renders.
enum CronJobServiceError: LocalizedError, Equatable {
    case notConfigured(String)
    case unreachable(String)
    case timeout
    case unauthorized(String)
    case notFound
    case serverRejected(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message),
             .unreachable(let message),
             .unauthorized(let message),
             .serverRejected(let message),
             .invalidResponse(let message):
            return message
        case .timeout:
            return "The Hermes host took too long to respond."
        case .notFound:
            return "This job no longer exists on the Hermes host."
        }
    }
}

/// `POST /api/jobs` — the create surface accepts exactly these (verified):
/// name (required), schedule (required), prompt, deliver, skills, repeat.
/// `script`/`no_agent`/`workdir`/model are CLI/tool-only — deliberately no
/// fields for them here.
struct CronJobCreateBody: Encodable, Equatable {
    var name: String
    var schedule: String
    var prompt: String
    var deliver: String?
    var skills: [String]?
    var repeatCount: Int?

    private enum CodingKeys: String, CodingKey {
        case name, schedule, prompt, deliver, skills
        case repeatCount = "repeat"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(deliver, forKey: .deliver)
        try container.encodeIfPresent(skills, forKey: .skills)
        try container.encodeIfPresent(repeatCount, forKey: .repeatCount)
    }
}

/// `PATCH /api/jobs/{id}` — built to the verified whitelist (`name`,
/// `schedule`, `prompt`, `deliver`, `skills`, `skill`, `repeat`, `enabled`);
/// anything else the server silently drops. Only fields the user actually
/// changed are encoded, so an edit never clobbers what it didn't touch.
struct CronJobPatchBody: Encodable, Equatable {
    var name: String?
    var schedule: String?
    var prompt: String?
    var deliver: String?
    var skills: [String]?
    /// Sent in the record's `{times, completed}` dict form: upstream's
    /// update is `{**job, **updates}` with no repeat normalization, so a
    /// bare int would replace the stored dict and break the scheduler's
    /// `repeat.get("times")` read. `completed` is preserved from the record
    /// being edited.
    var repeatTimes: Int?
    var repeatCompleted: Int?
    var includeRepeat = false
    var enabled: Bool?

    var isEmpty: Bool {
        name == nil && schedule == nil && prompt == nil && deliver == nil
            && skills == nil && !includeRepeat && enabled == nil
    }

    private enum CodingKeys: String, CodingKey {
        case name, schedule, prompt, deliver, skills, enabled
        case repeatPolicy = "repeat"
    }

    private enum RepeatKeys: String, CodingKey {
        case times, completed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(schedule, forKey: .schedule)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(deliver, forKey: .deliver)
        try container.encodeIfPresent(skills, forKey: .skills)
        if includeRepeat {
            var repeatContainer = container.nestedContainer(keyedBy: RepeatKeys.self, forKey: .repeatPolicy)
            // times nil = run forever — encoded as an explicit null so the
            // server's dict actually loses the old limit.
            try repeatContainer.encode(repeatTimes, forKey: .times)
            try repeatContainer.encode(repeatCompleted ?? 0, forKey: .completed)
        }
        try container.encodeIfPresent(enabled, forKey: .enabled)
    }
}

@MainActor
final class CronJobService: CronJobServiceProtocol {
    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "CronJobService")
    private static let jobsPath = "/api/jobs"

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let baseURLProvider: @MainActor () -> String?
    private let apiKeyProvider: @MainActor () -> String?

    init(
        baseURLProvider: @escaping @MainActor () -> String?,
        apiKeyProvider: @escaping @MainActor () -> String?,
        session: URLSession = .shared
    ) {
        self.baseURLProvider = baseURLProvider
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    // MARK: - Endpoints

    func listJobs() async throws -> [CronJob] {
        // The server hides disabled jobs by default — a truthful Tasks list
        // must show them (off / needsAttention are the point of D2).
        let response: CronJobListResponse = try await request(
            method: "GET",
            path: "\(Self.jobsPath)?include_disabled=true"
        )
        if response.skippedRowCount > 0 {
            Self.logger.error("listJobs: skipped \(response.skippedRowCount, privacy: .public) unparseable job row(s), kept \(response.jobs.count, privacy: .public)")
        }
        return response.jobs
    }

    func job(id: String) async throws -> CronJob {
        let envelope: CronJobEnvelope = try await request(method: "GET", path: jobPath(id))
        return envelope.job
    }

    func createJob(_ body: CronJobCreateBody) async throws -> CronJob {
        let envelope: CronJobEnvelope = try await request(method: "POST", path: Self.jobsPath, body: body)
        return envelope.job
    }

    func updateJob(id: String, patch: CronJobPatchBody) async throws -> CronJob {
        let envelope: CronJobEnvelope = try await request(method: "PATCH", path: jobPath(id), body: patch)
        return envelope.job
    }

    func deleteJob(id: String) async throws {
        let _: CronOKResponse = try await request(method: "DELETE", path: jobPath(id))
    }

    func pauseJob(id: String) async throws -> CronJob {
        let envelope: CronJobEnvelope = try await request(method: "POST", path: "\(jobPath(id))/pause")
        return envelope.job
    }

    func resumeJob(id: String) async throws -> CronJob {
        let envelope: CronJobEnvelope = try await request(method: "POST", path: "\(jobPath(id))/resume")
        return envelope.job
    }

    func runJob(id: String) async throws -> CronJob {
        let envelope: CronJobEnvelope = try await request(method: "POST", path: "\(jobPath(id))/run")
        return envelope.job
    }

    func deliverPlatforms() async -> [String]? {
        struct DetailedHealth: Decodable {
            let platforms: [String: LenientPlatformValue]?
        }
        // Values in the platforms dict vary by version — only the keys
        // (platform names) matter here.
        struct LenientPlatformValue: Decodable {
            init(from decoder: any Decoder) throws {}
        }
        do {
            let health: DetailedHealth = try await request(method: "GET", path: "/health/detailed")
            return health.platforms.map { $0.keys.sorted() }
        } catch {
            Self.logger.notice("deliverPlatforms: unavailable (\(error.localizedDescription, privacy: .public)) — deliver picker degrades to free text")
            return nil
        }
    }

    private func jobPath(_ id: String) -> String {
        "\(Self.jobsPath)/\(id)"
    }

    // MARK: - HTTP plumbing

    private struct NoBody: Encodable {}

    private func request<T: Decodable>(method: String, path: String) async throws -> T {
        try await request(method: method, path: path, body: Optional<NoBody>.none)
    }

    private func request<Body: Encodable, T: Decodable>(
        method: String,
        path: String,
        body: Body?
    ) async throws -> T {
        let request = try makeRequest(method: method, path: path, body: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.transportError(error)
        }
        try Self.ensureSuccess(response: response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CronJobServiceError.invalidResponse(
                "The Hermes host answered in a shape this build can't read."
            )
        }
    }

    private func makeRequest<Body: Encodable>(
        method: String,
        path: String,
        body: Body?
    ) throws -> URLRequest {
        guard let baseURL = baseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            throw CronJobServiceError.notConfigured("Hermes API base URL is not set.")
        }
        guard let apiKey = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw CronJobServiceError.notConfigured("Hermes API key is not set.")
        }
        var normalized = baseURL
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized + path) else {
            throw CronJobServiceError.notConfigured("Hermes API base URL is not a valid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Job ops are quick metadata writes (run-now only re-arms the
        // scheduler) — fail fast instead of riding the chat path's 300s.
        request.timeoutInterval = 15
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private nonisolated static func transportError(_ error: Error) -> CronJobServiceError {
        guard let urlError = error as? URLError else {
            return .unreachable(error.localizedDescription)
        }
        if urlError.code == .timedOut { return .timeout }
        return .unreachable(urlError.localizedDescription)
    }

    private nonisolated static func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CronJobServiceError.invalidResponse("The Hermes host returned an invalid response.")
        }
        let status = httpResponse.statusCode
        guard !(200 ..< 300).contains(status) else { return }
        let serverMessage = (try? JSONDecoder().decode(CronErrorBody.self, from: data))?.error
        switch status {
        case 401, 403:
            throw CronJobServiceError.unauthorized(
                serverMessage ?? "The Hermes host rejected this device's API key."
            )
        case 404:
            throw CronJobServiceError.notFound
        default:
            // 400 validation, 500 schedule-parse errors (including the
            // croniter-missing message), 501 cron-module-absent — all carry
            // their message in `error`; surface it untranslated.
            if let serverMessage, !serverMessage.isEmpty {
                throw CronJobServiceError.serverRejected(serverMessage)
            }
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw CronJobServiceError.serverRejected("The Hermes host returned status \(status). \(snippet)")
        }
    }
}
