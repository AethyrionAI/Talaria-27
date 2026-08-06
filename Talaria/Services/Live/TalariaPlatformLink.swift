import Foundation
import os

/// #251-2A: the phone side of the talaria platform transport — auto-pair with
/// the profile's gateway API key, then drain the durable outbox and answer
/// phone queries. Foreground-only by design (spec §2.1); the durable outbox
/// upstream is what makes closed-app time safe.
///
/// This type owns ONE drain. The polling loop (`start()`/`stop()`) arrives in
/// Task 8 — everything here is callable a single turn at a time.
@MainActor
final class TalariaPlatformLink {
    /// The result of a single drain. Task 8's loop reads these to decide
    /// cadence, which is why "no profile yet" and "the call failed" are
    /// separate cases rather than one `.failed`.
    enum DrainOutcome: Equatable {
        case delivered      // got items and/or queries, all handled
        case idle           // clean empty response
        case unauthorized   // 401 that survived the one re-pair attempt
        case failed         // transport / decoding error
        case notConfigured  // no gateway URL or no API key to pair with
    }

    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "TalariaPlatformLink")

    /// The single endpoint this whole plane speaks; the envelope's `type`
    /// field carries the verb.
    private static let eventsPath = "/api/platforms/talaria/events"

    /// Generous because a `wait: true` drain long-polls server-side.
    private static let requestTimeout: TimeInterval = 40

    private let gatewayBaseURL: @MainActor () -> String?
    private let apiKey: @MainActor () async -> String?
    private let installID: @MainActor () -> String
    private let deviceName: @MainActor () -> String
    private let credentialScopeID: @MainActor () -> UUID?
    private let secureStore: any SecureStoreProtocol
    private let responder: PhoneQueryResponding?
    private let onItemsReceived: @MainActor ([TalariaPlatformItem]) -> Void
    private let session: URLSession

    init(
        gatewayBaseURL: @escaping @MainActor () -> String?,
        apiKey: @escaping @MainActor () async -> String?,
        installID: @escaping @MainActor () -> String,
        deviceName: @escaping @MainActor () -> String,
        credentialScopeID: @escaping @MainActor () -> UUID?,
        secureStore: any SecureStoreProtocol,
        responder: PhoneQueryResponding?,
        onItemsReceived: @escaping @MainActor ([TalariaPlatformItem]) -> Void,
        session: URLSession = .shared
    ) {
        self.gatewayBaseURL = gatewayBaseURL
        self.apiKey = apiKey
        self.installID = installID
        self.deviceName = deviceName
        self.credentialScopeID = credentialScopeID
        self.secureStore = secureStore
        self.responder = responder
        self.onItemsReceived = onItemsReceived
        self.session = session
    }

    // MARK: - Pairing

    /// The Keychain slot holding the minted device token, scoped to the
    /// active profile exactly like every other credential (a nil scope is the
    /// migrated legacy profile, whose keys are unscoped by design).
    private var tokenKey: String {
        BackendProfileScopedKeys.talariaDeviceToken(credentialScopeID())
    }

    /// The device id rides in the same slot family — it is half of one
    /// credential and must be dropped with the token on a re-pair.
    private func deviceIDKey(_ tokenKey: String) -> String { tokenKey + ".deviceID" }

    /// True once a token AND a device id are stored — both halves, because a
    /// half-written pair is unusable and should be re-minted rather than
    /// wedging every later drain.
    func ensurePaired() async -> Bool {  // harness-visible
        let tokenKey = tokenKey
        if await secureStore.retrieve(key: tokenKey) != nil,
           await secureStore.retrieve(key: deviceIDKey(tokenKey)) != nil {
            return true
        }
        return await pair(tokenKey: tokenKey)
    }

    private func pair(tokenKey: String) async -> Bool {
        guard let key = await apiKey(), !key.isEmpty else { return false }
        let body: [String: Any] = [
            "type": "pair",
            "auth": key,
            "install_id": installID(),
            "device_name": deviceName(),
        ]
        guard let (status, data) = await post(body, bearer: key) else {
            Self.logger.error("talaria pair failed — no response")
            return false
        }
        guard status == 200,
              let paired = try? JSONDecoder().decode(TalariaPairResponse.self, from: data)
        else {
            logEnvelopeError(status: status, data: data, verb: "pair")
            return false
        }
        await secureStore.store(key: tokenKey, value: paired.deviceToken)
        await secureStore.store(key: deviceIDKey(tokenKey), value: paired.deviceID)
        Self.logger.notice("talaria paired as device \(paired.deviceID, privacy: .public)")
        return true
    }

    // MARK: - Drain

    /// One drain turn: pair if needed, pull the outbox, ack what arrived and
    /// answer any queries. A 401 buys exactly one re-pair, then gives up.
    func drainOnce(wait: Bool) async -> DrainOutcome {
        await drain(wait: wait, allowRepair: true)
    }

    private func drain(wait: Bool, allowRepair: Bool) async -> DrainOutcome {
        guard endpointURL() != nil else { return .notConfigured }
        let tokenKey = tokenKey

        guard await ensurePaired() else {
            // No usable token. Separate "there is no API key to pair with"
            // from "the pair call itself failed" so the loop can back off on
            // the latter without hot-looping on the former.
            let key = await apiKey()
            return (key?.isEmpty == false) ? .failed : .notConfigured
        }
        guard let token = await secureStore.retrieve(key: tokenKey),
              let deviceID = await secureStore.retrieve(key: deviceIDKey(tokenKey))
        else { return .failed }

        let body: [String: Any] = [
            "type": "drain",
            "auth": token,
            "device_id": deviceID,
            "wait": wait,
        ]
        guard let (status, data) = await post(body, bearer: token) else { return .failed }

        if status == 401 {
            logEnvelopeError(status: status, data: data, verb: "drain")
            guard allowRepair else { return .unauthorized }
            // The stored pair is stale (server DB reset, profile re-keyed).
            // Drop BOTH halves and mint a new one, exactly once per turn.
            await secureStore.delete(key: tokenKey)
            await secureStore.delete(key: deviceIDKey(tokenKey))
            guard await ensurePaired() else { return .unauthorized }
            return await drain(wait: wait, allowRepair: false)
        }
        guard status == 200,
              let drained = try? JSONDecoder().decode(TalariaDrainResponse.self, from: data)
        else {
            logEnvelopeError(status: status, data: data, verb: "drain")
            return .failed
        }

        var didWork = false
        if !drained.items.isEmpty {
            onItemsReceived(drained.items)
            await ack(itemIDs: drained.items.map(\.id), token: token, deviceID: deviceID)
            didWork = true
        }
        for query in drained.queries {
            await answer(query, token: token, deviceID: deviceID)
            didWork = true
        }
        return didWork ? .delivered : .idle
    }

    private func ack(itemIDs: [String], token: String, deviceID: String) async {
        let body: [String: Any] = [
            "type": "ack",
            "auth": token,
            "device_id": deviceID,
            "item_ids": itemIDs,
        ]
        _ = await post(body, bearer: token)
    }

    private func answer(_ query: TalariaPlatformQuery, token: String, deviceID: String) async {
        var body: [String: Any] = [
            "type": "query_result",
            "auth": token,
            "device_id": deviceID,
            "query_id": query.id,
        ]
        if let responder {
            switch await responder.answer(kind: query.kind, params: query.params ?? [:]) {
            case .success(let text): body["result"] = ["text": text]
            case .denied: body["error"] = "permission_denied"
            case .unavailable(let reason): body["error"] = reason
            }
        } else {
            body["error"] = "responder_unavailable"
        }
        _ = await post(body, bearer: token)
    }

    // MARK: - Transport

    private func endpointURL() -> URL? {
        guard var base = gatewayBaseURL(), !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + Self.eventsPath)
    }

    private func post(_ body: [String: Any], bearer: String) async -> (status: Int, data: Data)? {
        guard let url = endpointURL(),
              let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        return (http.statusCode, data)
    }

    private func logEnvelopeError(status: Int, data: Data, verb: String) {
        if let envelope = try? JSONDecoder().decode(TalariaEnvelopeError.self, from: data) {
            Self.logger.error(
                "talaria \(verb, privacy: .public) HTTP \(status, privacy: .public) code=\(envelope.code, privacy: .public)"
            )
        } else {
            Self.logger.error("talaria \(verb, privacy: .public) HTTP \(status, privacy: .public)")
        }
    }
}

/// The seam the link answers phone queries through. Task 9 implements the
/// live conformer; MainActor-isolated because every real answer reads
/// app state (stores, HealthKit, location) that already lives there.
@MainActor
protocol PhoneQueryResponding {
    func answer(kind: String, params: [String: String]) async -> PhoneQueryAnswer
}

enum PhoneQueryAnswer: Equatable {
    case success(text: String)
    case denied
    case unavailable(reason: String)
}
