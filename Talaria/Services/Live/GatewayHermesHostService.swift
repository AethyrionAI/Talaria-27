import Foundation
import os

/// #309 row 7's ADAPT, executed by Lane C (bar 309-C2): **host presence is a
/// GATEWAY fact now.**
///
/// What it replaces: `LiveHermesHostService`, which asked the relay
/// `GET hosts/current` for a record the relay's connector kept about an
/// ENROLLED host — a second machine's liveness, reported by a third party. The
/// relay is retired on both hosts (#346 OJAMD, #375 Mac), so that question has
/// had no answerer since the retirement and the app has been rendering
/// "unreachable" for a service nobody runs.
///
/// What it asks instead: **the host itself, on the plane chat already uses.**
/// The gateway IS the host under #251/#269 — there is no enrollment, no
/// connector record and no third party left — so "is the host online" reduces
/// to "does `:8642` answer". One `GET /health` on the profile's gateway base
/// URL, the profile's bearer attached, on the #136 probe budget.
///
/// **What this deliberately does NOT measure, stated so nobody reads more into
/// a green pip than it carries:** `/health` is unauthenticated on the Hermes
/// api_server, so a 2xx says the host is REACHABLE, not that this profile's key
/// is valid. Credential validity has its own honest surfaces — the Server
/// screen's `/v1/models` probe classifies 401/403 as "answering but unkeyed",
/// and the chat plane fails loudly on a bad key. Lane B's Connect Host screen
/// builds the full probe ladder (spec §3.1); this lane wants the one honest
/// reachability read that row 7 was always a proxy for.
@MainActor
final class GatewayHermesHostService: HermesHostServiceProtocol {
    private static let logger = Logger(
        subsystem: TalariaLog.subsystem, category: "GatewayHermesHostService")
    private static let healthPath = "/health"

    /// Tolerant by construction — the same posture as `Skill`. Hermes does not
    /// treat `/health`'s body as contractual, and a shape this build cannot
    /// read must never turn a REACHABLE host into an unreachable one: the
    /// status code is the measurement, the body is decoration.
    private struct HealthResponse: Decodable {
        let status: String?
        let version: String?
        let model: String?
    }

    private let baseURLProvider: @MainActor () -> String?
    private let apiKeyProvider: @MainActor () -> String?
    /// The host's name comes from the PROFILE, because the profile is where
    /// the user typed it. The gateway has no display name to report — the
    /// relay's `displayName` was the connector's enrollment label, and that
    /// record no longer exists.
    private let displayNameProvider: @MainActor () -> String?
    private let identityProvider: @MainActor () -> UUID?
    private let session: URLSession

    init(
        baseURLProvider: @escaping @MainActor () -> String?,
        apiKeyProvider: @escaping @MainActor () -> String?,
        displayNameProvider: @escaping @MainActor () -> String? = { nil },
        identityProvider: @escaping @MainActor () -> UUID? = { nil },
        session: URLSession = BootstrapProbeSession.make()
    ) {
        self.baseURLProvider = baseURLProvider
        self.apiKeyProvider = apiKeyProvider
        self.displayNameProvider = displayNameProvider
        self.identityProvider = identityProvider
        self.session = session
    }

    func fetchCurrentHost() async throws -> HermesHostStatus? {
        // Nothing configured is NOT an error — it is the honest "no host"
        // answer, and `HermesHostStore` renders it as `.notConnected` rather
        // than as a failure. Throwing here would paint an unconfigured install
        // as a broken one.
        guard let base = normalizedBaseURL(), let url = URL(string: base + Self.healthPath) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        // URLSession errors propagate raw: `error.localizedDescription` is
        // what the store shows, and the system's text ("The request timed
        // out.") beats anything this file could invent.
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.requestFailed("The Hermes host returned an invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403:
                throw APIClientError.unauthorized("The Hermes host rejected this device's API key.")
            default:
                throw APIClientError.requestFailed(
                    "The Hermes host returned status \(http.statusCode)."
                )
            }
        }

        let health = try? JSONDecoder().decode(HealthResponse.self, from: data)
        if health == nil {
            Self.logger.notice("fetchCurrentHost: 2xx with an unreadable /health body — reporting reachable anyway")
        }

        let now = Date()
        return HermesHostStatus(
            id: identityProvider() ?? Self.stableIdentity(for: base),
            displayName: displayNameProvider(),
            hostname: URL(string: base)?.host,
            // Real data only (#45): the gateway reports neither a platform nor
            // a connector version, and the connector is retired anyway. `nil`
            // renders as "—" rather than as an invented value.
            platform: nil,
            connectorVersion: nil,
            hermesCommand: nil,
            hermesVersion: health?.version,
            hermesModel: health?.model,
            // We just reached it — that is what "last seen" means here, and it
            // is measured rather than reported.
            lastSeenAt: now,
            lastConnectedAt: now,
            isOnline: true
        )
    }

    private func normalizedBaseURL() -> String? {
        guard var base = baseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return base.isEmpty ? nil : base
    }

    /// A deterministic id for the host record when no profile id is supplied
    /// (the default provider's case, and the unit harnesses'). `HermesHostStatus`
    /// is `Hashable` and the store compares records, so a fresh `UUID()` per
    /// refresh would report a host CHANGE on every poll — the exact defect
    /// `HermesHostStore.refresh()`'s transition guard exists to stop.
    ///
    /// FNV-1a rather than `Hasher`, deliberately: Swift's hashing is seeded
    /// per PROCESS, so a `Hasher`-derived id would be stable within one launch
    /// and different on the next — a durability property that reads as present
    /// in every test and is absent in the field.
    // harness-visible
    static func stableIdentity(for baseURL: String) -> UUID {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(baseURL.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0 ..< 8 {
            bytes[index] = UInt8(truncatingIfNeeded: hash >> (8 * UInt64(index)))
            bytes[index + 8] = bytes[index] ^ 0x5a
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
