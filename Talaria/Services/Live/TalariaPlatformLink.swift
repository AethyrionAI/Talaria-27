import Foundation
import os

/// #251-2A: the phone side of the talaria platform transport — auto-pair with
/// the profile's gateway API key, then drain the durable outbox and answer
/// phone queries. Foreground-only by design (spec §2.1); the durable outbox
/// upstream is what makes closed-app time safe.
///
/// This type owns ONE drain (`drainOnce`) plus the polling loop around it
/// (`start()`/`stop()`, Task 8). Healthy loop = back-to-back long-polls
/// (`wait: true`) — the server's hold provides the pacing; degraded loop =
/// `wait: false` polls paced by `nextDelay`'s bounded backoff ladder.
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
        case superseded     // #285: stop() landed mid-turn — abandoned, no side effects
    }

    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "TalariaPlatformLink")

    /// The single endpoint this whole plane speaks; the envelope's `type`
    /// field carries the verb.
    private static let eventsPath = "/api/platforms/talaria/events"

    /// Generous because a `wait: true` drain long-polls server-side.
    private static let requestTimeout: TimeInterval = 40

    private let gatewayBaseURL: @MainActor () -> String?
    private let installID: @MainActor () -> String
    private let deviceName: @MainActor () -> String
    private let credentialScopeID: @MainActor () -> UUID?
    private let secureStore: any SecureStoreProtocol
    private let responder: PhoneQueryResponding?
    private let onItemsReceived: @MainActor ([TalariaPlatformItem]) -> Void
    private let session: URLSession

    // #285: there is deliberately NO injected api-key closure. A closure
    // resolving the ACTIVE profile's key internally is exactly the live
    // re-resolution class this type had to shed; the link reads the Keychain
    // itself through the turn's frozen `apiKeyKey` instead — which is
    // byte-what the old production closure did, minus the liveness.
    init(
        gatewayBaseURL: @escaping @MainActor () -> String?,
        installID: @escaping @MainActor () -> String,
        deviceName: @escaping @MainActor () -> String,
        credentialScopeID: @escaping @MainActor () -> UUID?,
        secureStore: any SecureStoreProtocol,
        responder: PhoneQueryResponding?,
        onItemsReceived: @escaping @MainActor ([TalariaPlatformItem]) -> Void,
        session: URLSession = .shared
    ) {
        self.gatewayBaseURL = gatewayBaseURL
        self.installID = installID
        self.deviceName = deviceName
        self.credentialScopeID = credentialScopeID
        self.secureStore = secureStore
        self.responder = responder
        self.onItemsReceived = onItemsReceived
        self.session = session
    }

    // MARK: - The turn boundary (#285)

    /// Everything profile-scoped one logical turn needs, resolved ONCE —
    /// synchronously, so no suspension can split the resolution — at turn
    /// start. A turn carries this context to completion or abandonment and
    /// NEVER re-resolves live profile state after its first await; that
    /// re-resolution is exactly how one pair/drain used to mix profile A's
    /// keys with profile B's endpoint and slots (RED-REPORT.md on the #285
    /// branch preserves the traces).
    ///
    /// A nil credential scope is the migrated legacy profile, whose keys are
    /// unscoped by design — frozen here like any other scope.
    private struct TurnContext {
        let scopeID: UUID?
        /// Trailing-slash-normalized; `post` appends `eventsPath` directly.
        let gatewayBaseURL: String
        let tokenKey: String
        /// The device id rides in the same slot family — it is half of one
        /// credential and must be dropped with the token on a re-pair. Named
        /// in `BackendProfileScopedKeys` rather than derived inline so a
        /// purge can enumerate it directly.
        let deviceIDKey: String
        let apiKeyKey: String
        /// The link epoch at turn start. `stop()` bumps the epoch, so a
        /// mismatch means this turn was superseded: it must not POST,
        /// deliver, ack, answer, or start a new Keychain step. Finishing the
        /// atomic Keychain step it is already INSIDE is allowed — a
        /// credential pair is written or dropped whole, never half.
        let epoch: Int
    }

    /// Bumped by every `stop()`. A turn that outlives its epoch abandons at
    /// its next side-effect checkpoint instead of completing cross-profile.
    private var epoch = 0

    /// nil when no gateway URL is configured (the `.notConfigured` case).
    /// Both closure reads are synchronous @MainActor calls with no await
    /// between them — the resolution is atomic on the actor by construction.
    private func makeTurnContext() -> TurnContext? {
        guard var base = gatewayBaseURL(), !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        let scope = credentialScopeID()
        return TurnContext(
            scopeID: scope,
            gatewayBaseURL: base,
            tokenKey: BackendProfileScopedKeys.talariaDeviceToken(scope),
            deviceIDKey: BackendProfileScopedKeys.talariaDeviceID(scope),
            apiKeyKey: BackendProfileScopedKeys.gatewayAPIKey(scope),
            epoch: epoch
        )
    }

    private func isCurrent(_ context: TurnContext) -> Bool { epoch == context.epoch }

    // MARK: - Pairing

    /// True once a token AND a device id are stored — both halves, because a
    /// half-written pair is unusable and should be re-minted rather than
    /// wedging every later drain.
    func ensurePaired() async -> Bool {  // harness-visible
        guard let context = makeTurnContext() else { return false }
        return await ensurePaired(context: context)
    }

    private func ensurePaired(context: TurnContext) async -> Bool {
        if await secureStore.retrieve(key: context.tokenKey) != nil,
           await secureStore.retrieve(key: context.deviceIDKey) != nil {
            return true
        }
        return await pair(context: context)
    }

    private func pair(context: TurnContext) async -> Bool {
        guard let key = await secureStore.retrieve(key: context.apiKeyKey), !key.isEmpty else { return false }
        // #285 checkpoint: a superseded turn must not mint. The gateway
        // creates a device row on a pair call; minting one whose response
        // this client will discard is how host-side orphan rows are born
        // (#288), so the request itself is what gets abandoned.
        guard isCurrent(context) else { return false }
        let body: [String: Any] = [
            "type": "pair",
            "auth": key,
            "install_id": installID(),
            "device_name": deviceName(),
        ]
        guard let (status, data) = await post(body, context: context, bearer: key) else {
            Self.logger.error("talaria pair failed — no response")
            return false
        }
        guard status == 200,
              let paired = try? JSONDecoder().decode(TalariaPairResponse.self, from: data)
        else {
            logEnvelopeError(status: status, data: data, verb: "pair")
            return false
        }
        // #285 checkpoint, then the pair is written WHOLE — no checkpoint
        // between the halves, because a half-written pair is the state the
        // doc comment above promises never persists.
        guard isCurrent(context) else { return false }
        await secureStore.store(key: context.tokenKey, value: paired.deviceToken)
        await secureStore.store(key: context.deviceIDKey, value: paired.deviceID)
        Self.logger.notice("talaria paired as device \(paired.deviceID, privacy: .public)")
        return true
    }

    // MARK: - Drain

    /// One drain turn: pair if needed, pull the outbox, ack what arrived and
    /// answer any queries. A 401 buys exactly one re-pair, then gives up.
    /// The whole turn rides ONE frozen `TurnContext` (#285).
    func drainOnce(wait: Bool) async -> DrainOutcome {
        guard let context = makeTurnContext() else { return .notConfigured }
        return await drain(context: context, wait: wait, allowRepair: true)
    }

    private func drain(context: TurnContext, wait: Bool, allowRepair: Bool) async -> DrainOutcome {
        guard await ensurePaired(context: context) else {
            // No usable token. Separate "there is no API key to pair with"
            // from "the pair call itself failed" so the loop can back off on
            // the latter without hot-looping on the former.
            let key = await secureStore.retrieve(key: context.apiKeyKey)
            return (key?.isEmpty == false) ? .failed : .notConfigured
        }
        guard let token = await secureStore.retrieve(key: context.tokenKey),
              let deviceID = await secureStore.retrieve(key: context.deviceIDKey)
        else { return .failed }

        // #285 checkpoint: superseded turns fall silent before the wire.
        guard isCurrent(context) else { return .superseded }
        let body: [String: Any] = [
            "type": "drain",
            "auth": token,
            "device_id": deviceID,
            "wait": wait,
        ]
        guard let (status, data) = await post(body, context: context, bearer: token) else { return .failed }

        if status == 401 {
            logEnvelopeError(status: status, data: data, verb: "drain")
            guard allowRepair else { return .unauthorized }
            // #285 checkpoint: a superseded turn does not START the repair —
            // its stale pair is the NEXT activation's problem, repaired the
            // next time this profile drains.
            guard isCurrent(context) else { return .superseded }
            // The stored pair is stale (server DB reset, profile re-keyed).
            // Drop BOTH halves and mint a new one, exactly once per turn.
            // No checkpoint between the deletes: the pair drops whole, under
            // this turn's own frozen keys, even if a stop lands mid-step.
            await secureStore.delete(key: context.tokenKey)
            await secureStore.delete(key: context.deviceIDKey)
            // #285 checkpoint: dropping OUR stale pair was owed cleanup;
            // minting a new one is new work a superseded turn must not do.
            guard isCurrent(context) else { return .superseded }
            guard await ensurePaired(context: context) else { return .unauthorized }
            guard isCurrent(context) else { return .superseded }
            return await drain(context: context, wait: wait, allowRepair: false)
        }
        guard status == 200,
              let drained = try? JSONDecoder().decode(TalariaDrainResponse.self, from: data)
        else {
            logEnvelopeError(status: status, data: data, verb: "drain")
            return .failed
        }

        // #285 checkpoint: a superseded turn delivers nothing and acks
        // nothing — the un-acked items stay in the durable outbox and
        // redeliver on the next current turn (dedup by `platformID` upstream
        // keeps that invisible).
        guard isCurrent(context) else { return .superseded }
        var didWork = false
        if !drained.items.isEmpty {
            onItemsReceived(drained.items)
            await ack(itemIDs: drained.items.map(\.id), context: context, token: token, deviceID: deviceID)
            didWork = true
        }
        for query in drained.queries {
            // Per-query checkpoint: each answer is its own POST.
            guard isCurrent(context) else { return .superseded }
            await answer(query, context: context, token: token, deviceID: deviceID)
            didWork = true
        }
        return didWork ? .delivered : .idle
    }

    private func ack(itemIDs: [String], context: TurnContext, token: String, deviceID: String) async {
        let body: [String: Any] = [
            "type": "ack",
            "auth": token,
            "device_id": deviceID,
            "item_ids": itemIDs,
        ]
        _ = await post(body, context: context, bearer: token)
    }

    private func answer(_ query: TalariaPlatformQuery, context: TurnContext, token: String, deviceID: String) async {
        var body: [String: Any] = [
            "type": "query_result",
            "auth": token,
            "device_id": deviceID,
            "query_id": query.id,
        ]
        if let responder {
            switch await responder.answer(kind: query.kind, params: query.params ?? [:]) {
            case .success(let text): body["result"] = ["text": text]
            case .denied:
                body["error"] = "permission_denied"
                // #260(B): additive gate metadata so the plugin's prose can
                // name the actual blocker. A responder that classifies nil
                // (or predates the classifier) keeps the bare pre-#260 body,
                // which the plugin maps to its generic declined prose —
                // graceful in both skew directions.
                switch responder.deniedGate(kind: query.kind) {
                case .master:
                    body["denied_gate"] = "master"
                case .stream(let sensor):
                    body["denied_gate"] = "stream"
                    body["denied_stream"] = sensor
                case nil:
                    break
                }
            case .unavailable(let reason): body["error"] = reason
            }
        } else {
            body["error"] = "responder_unavailable"
        }
        _ = await post(body, context: context, bearer: token)
    }

    // MARK: - Loop

    private var loopTask: Task<Void, Never>?

    /// True between `start()` and `stop()`. Not "a drain is currently
    /// in-flight" — the loop can be `isRunning` while parked in a backoff
    /// sleep between turns.
    private(set) var isRunning = false

    /// Pure bounded-exponential ladder: 1, 2, 4, 8, 16, 30, 30, … — no
    /// randomization, no state, so it's trivially testable and trivially
    /// reasoned about from a failure count alone. `harness-visible` per
    /// repo convention: internal (not private) purely so tests can call it
    /// directly, not part of any real external interface.
    func nextDelay(afterFailureCount count: Int) -> Double {  // harness-visible
        min(30, pow(2, Double(max(0, count - 1))))
    }

    /// Starts the drain loop. Idempotent — a second call while already
    /// running is a no-op rather than spawning a competing loop.
    ///
    /// Healthy loop: back-to-back `wait: true` drains — the server's own
    /// long-poll hold (≤25s) paces the requests, so no client-side sleep is
    /// needed between them. Degraded loop: any non-clean outcome switches to
    /// `wait: false` polling on the `nextDelay` backoff ladder until a
    /// `.delivered`/`.idle` turn resets it. `.notConfigured` and
    /// `.unauthorized` are floored at failure count 3 rather than
    /// incrementing from 1 — both are "nothing will change until something
    /// external does" states (missing config, dead pairing), so there is no
    /// value in the fast early rungs of the ladder the way there is for a
    /// possibly-transient `.failed`.
    func start() {
        guard loopTask == nil else { return }
        isRunning = true
        loopTask = Task { [weak self] in
            var failures = 0
            while let self, self.isRunning, !Task.isCancelled {
                let outcome = await self.drainOnce(wait: failures == 0)
                switch outcome {
                case .delivered, .idle:
                    failures = 0
                case .notConfigured, .unauthorized:
                    failures = max(failures, 3)
                case .failed:
                    failures += 1
                case .superseded:
                    // #285: only stop() supersedes, and stop() also cleared
                    // `isRunning` — the while condition exits next check.
                    break
                }
                if failures > 0 {
                    let delay = self.nextDelay(afterFailureCount: failures)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    /// Stops the loop AND supersedes the in-flight turn (#285): the epoch
    /// bump means a turn parked in a non-cancellable await (a Keychain call)
    /// abandons at its next side-effect checkpoint when it resumes, instead
    /// of completing against whatever profile is active by then. Cancellation
    /// alone cannot do that — a `CheckedContinuation` is not
    /// cancellation-aware, and Keychain work must not be torn mid-step.
    func stop() {
        epoch += 1
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Transport

    /// #285: the URL comes from the TURN's frozen base, never a live re-read.
    private func post(_ body: [String: Any], context: TurnContext, bearer: String) async -> (status: Int, data: Data)? {
        guard let url = URL(string: context.gatewayBaseURL + Self.eventsPath),
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

    /// #260(B): which settings gate WOULD refuse this kind right now, so a
    /// serialized denial can name the switch that actually unblocks it.
    /// Diagnostic metadata only — `answer` alone decides denied-vs-not, and
    /// the default keeps every pre-#260 conformer compiling with the exact
    /// pre-#260 wire body (bare `permission_denied`).
    func deniedGate(kind: String) -> PhoneQueryDeniedGate?
}

extension PhoneQueryResponding {
    func deniedGate(kind: String) -> PhoneQueryDeniedGate? { nil }
}

enum PhoneQueryAnswer: Equatable {
    case success(text: String)
    case denied
    case unavailable(reason: String)
}

/// #260(B): the two settings gates a denial can come from. iOS-ungranted is
/// deliberately NOT a case — permission prose comes back from the read as a
/// `.success` (the belt's honest strings), never as a settings denial.
enum PhoneQueryDeniedGate: Equatable {
    case master
    /// The named per-sensor stream toggle ("health" / "location" / "motion")
    /// — for weather that is LOCATION, the toggle a user must actually flip.
    case stream(sensor: String)
}
