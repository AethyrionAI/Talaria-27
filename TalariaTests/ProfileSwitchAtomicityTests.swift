import Foundation
import Testing
@testable import Talaria

/// #285 — is a backend-profile switch an ATOMIC transport boundary?
///
/// `TalariaPlatformLink` is a `@MainActor final class`, not an actor, and it
/// is constructed ONCE for the app's lifetime. Every profile-scoped input is
/// a CLOSURE re-evaluated at call time (`AppContainer.swift` ~:971 —
/// `gatewayBaseURL`, `apiKey`, `credentialScopeID` all read
/// `profilesStore.activeProfile` live). That is deliberate: the link must
/// follow the active profile rather than pin the host it was built on. The
/// question this suite answers is whether "follow the active profile" is
/// scoped to a TURN or leaks INSIDE one.
///
/// Because everything here is `@MainActor` there is no true parallelism —
/// interleaving is possible only at `await` suspension points, which is
/// exactly what makes these repros deterministic rather than flaky.
///
/// **The blocker these tests had to clear first.** `SecureStoreProtocol`'s
/// methods are `async`, but BOTH shipping conformers (`KeychainSecureStore`,
/// `MockSecureStore`) are synchronous underneath — awaiting them never yields
/// to the scheduler, so with either of them no interleaving can be expressed
/// at all and every "race" test would pass vacuously. `GatedSecureStore`
/// below genuinely parks on a `CheckedContinuation` (the `GatedCronJobService`
/// idiom from `CronJobsStoreTests`) and RECORDS every (operation, key) pair in
/// call order. That recorded trace is the evidence, not the assertions'
/// wording.
///
/// Serialized: the URL stub's handler is a `nonisolated(unsafe) static`.
@Suite(.serialized)
@MainActor
struct ProfileSwitchAtomicityTests {

    // MARK: - Fixtures

    /// Two profiles, fixed UUIDs so a failure message names which host a key
    /// belongs to instead of printing a fresh random one.
    private static let scopeA = UUID(uuidString: "AAAAAAAA-0000-4000-8000-0000000000AA")!
    private static let scopeB = UUID(uuidString: "BBBBBBBB-0000-4000-8000-0000000000BB")!

    private static let tokenKeyA = BackendProfileScopedKeys.talariaDeviceToken(scopeA)
    private static let deviceIDKeyA = BackendProfileScopedKeys.talariaDeviceID(scopeA)
    private static let apiKeyKeyA = BackendProfileScopedKeys.gatewayAPIKey(scopeA)
    private static let tokenKeyB = BackendProfileScopedKeys.talariaDeviceToken(scopeB)
    private static let deviceIDKeyB = BackendProfileScopedKeys.talariaDeviceID(scopeB)
    private static let apiKeyKeyB = BackendProfileScopedKeys.gatewayAPIKey(scopeB)

    private static let gatewayA = "http://gateway-a.local:8642"
    private static let gatewayB = "http://gateway-b.local:8642"

    /// Short labels so a recorded trace is readable at a glance; the raw keys
    /// are still what the code actually saw.
    private static let keyLabels: [String: String] = [
        tokenKeyA: "A.deviceToken", deviceIDKeyA: "A.deviceID", apiKeyKeyA: "A.apiKey",
        tokenKeyB: "B.deviceToken", deviceIDKeyB: "B.deviceID", apiKeyKeyB: "B.apiKey",
    ]

    /// Stands in for `profilesStore.activeProfile` — the ONE mutable thing
    /// every one of the link's closures re-resolves through, exactly as
    /// production does. Flipping this box is a profile switch.
    @MainActor
    private final class ActiveProfileBox {
        private(set) var scope: UUID
        private(set) var gatewayBaseURL: String

        init(scope: UUID, gatewayBaseURL: String) {
            self.scope = scope
            self.gatewayBaseURL = gatewayBaseURL
        }

        func switchTo(scope: UUID, gatewayBaseURL: String) {
            self.scope = scope
            self.gatewayBaseURL = gatewayBaseURL
        }
    }

    // MARK: - The gate

    /// A `SecureStoreProtocol` that ACTUALLY suspends, and records what it saw.
    ///
    /// `shouldPark` decides per call whether to park on a continuation; the
    /// test then flips the active profile while the caller is parked and
    /// `release()`s. Every call is logged at ENTRY, before any parking, because
    /// the KEY was computed by the caller before the call — so entry order is
    /// the order in which the caller resolved its credential scope.
    @MainActor
    private final class GatedSecureStore: SecureStoreProtocol {
        enum Operation: String, Equatable { case retrieve, store, delete }

        struct Call: Equatable {
            let operation: Operation
            let key: String
            /// 1-based index among ALL calls.
            let callIndex: Int
            /// 1-based index among calls sharing this (operation, key).
            let occurrence: Int
        }

        private var values: [String: String] = [:]
        private(set) var log: [Call] = []
        private var continuations: [CheckedContinuation<Void, Never>] = []

        var keyLabels: [String: String] = [:]
        var shouldPark: @MainActor (Call) -> Bool = { _ in false }

        var pendingCount: Int { continuations.count }

        /// Arrange, not act: seeding does not appear in the trace.
        func seed(key: String, value: String) { values[key] = value }
        /// Reads final state without polluting the trace.
        func peek(key: String) -> String? { values[key] }

        func release() {
            let held = continuations
            continuations = []
            for continuation in held { continuation.resume() }
        }

        /// The evidence, in call order: `retrieve(A.deviceToken)`, …
        var trace: [String] {
            log.map { "\($0.operation.rawValue)(\(keyLabels[$0.key] ?? $0.key))" }
        }

        private func record(_ operation: Operation, _ key: String) -> Call {
            let occurrence = log.filter { $0.operation == operation && $0.key == key }.count + 1
            let call = Call(operation: operation, key: key, callIndex: log.count + 1, occurrence: occurrence)
            log.append(call)
            return call
        }

        func store(key: String, value: String) async {
            let call = record(.store, key)
            if shouldPark(call) { await withCheckedContinuation { continuations.append($0) } }
            values[key] = value
        }

        func retrieve(key: String) async -> String? {
            let call = record(.retrieve, key)
            if shouldPark(call) { await withCheckedContinuation { continuations.append($0) } }
            return values[key]
        }

        func delete(key: String) async {
            let call = record(.delete, key)
            if shouldPark(call) { await withCheckedContinuation { continuations.append($0) } }
            values.removeValue(forKey: key)
        }
    }

    /// Records the URL each POST actually went to, alongside its body. Runs
    /// off the MainActor (URLProtocol's thread), hence the lock.
    private final class WireRecorder: @unchecked Sendable {
        struct Call: Sendable {
            let host: String
            let body: String
        }

        private let lock = NSLock()
        private var calls: [Call] = []

        func record(_ call: Call) {
            lock.lock()
            defer { lock.unlock() }
            calls.append(call)
        }

        var all: [Call] {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }

        var trace: [String] { all.map { "POST \($0.host) \($0.body)" } }
    }

    // MARK: - Harness

    private func makeLink(
        box: ActiveProfileBox,
        secure: GatedSecureStore,
        onItems: @escaping @MainActor ([TalariaPlatformItem]) -> Void = { _ in },
        handler: @escaping @Sendable (URLRequest) -> (Int, Data)
    ) -> TalariaPlatformLink {
        AtomicityStubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AtomicityStubURLProtocol.self]
        // Closure shapes copied from AppContainer.swift ~:971 — including
        // `apiKey` reading the Keychain through the SAME secure store, which
        // is what production does (the in-memory box "lags a profile switch").
        return TalariaPlatformLink(
            gatewayBaseURL: { box.gatewayBaseURL },
            apiKey: { await secure.retrieve(key: BackendProfileScopedKeys.gatewayAPIKey(box.scope)) },
            installID: { "install-abc" },
            deviceName: { "TestPhone" },
            credentialScopeID: { box.scope },
            secureStore: secure,
            responder: nil,
            onItemsReceived: onItems,
            session: URLSession(configuration: configuration)
        )
    }

    /// Spins until the gate has actually parked someone. The `#expect` on
    /// `pendingCount` at every call site is the anti-vacuous-pass guard: a
    /// repro that never parked would prove nothing at all.
    ///
    /// Yields first (the `CronJobsStoreTests` idiom — enough when the parked
    /// call is reached purely on the MainActor), then falls back to a
    /// real-time poll, because some repros park only AFTER a URLSession round
    /// trip that completes off the MainActor.
    private func waitForPark(_ secure: GatedSecureStore) async {
        var spins = 0
        while secure.pendingCount == 0, spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        await waitUntil { secure.pendingCount > 0 }
    }

    /// Real-time bounded wait — needed after a release, because the work that
    /// follows includes a URLSession round trip that completes off-MainActor.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor
    private final class ItemsBox {
        var items: [TalariaPlatformItem] = []
    }

    @MainActor
    private final class FlagBox {
        var value = false
    }

    // MARK: - Provenance: when does the scope actually move?

    /// The premise every repro below rests on, pinned against the REAL store.
    ///
    /// `BackendProfilesStore.setActiveProfile` assigns `state.activeProfileID`
    /// SYNCHRONOUSLY and only then fires `Task { await onActiveProfileChanged }`.
    /// So on a real switch the credential scope has already moved by the time
    /// `AppContainer.handleActiveProfileChanged` — and its
    /// `talariaPlatformLink?.stop()` — gets a turn to run. That ordering is
    /// what makes "flip the box while a turn is parked" a faithful model of a
    /// user tapping a different profile, not a contrivance.
    ///
    /// It also falsifies the comment above that `stop()` call, which claims it
    /// "park[s] the drain before the scope moves". The scope moves first.
    @Test func activeProfileMovesSynchronouslyBeforeTheSwitchHandlerRuns() async throws {
        let suiteName = "profile-atomicity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = BackendProfilesStore(
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults),
            migrationSeeds: BackendProfilesStore.MigrationSeeds(
                gatewayBaseURL: Self.gatewayA,
                relayBaseURL: "http://a.local:8000/v1",
                shimBaseURL: nil
            )
        )
        let profileB = BackendProfile(
            name: "B",
            gatewayBaseURL: Self.gatewayB,
            relayBaseURL: "http://b.local:8000/v1"
        )
        store.upsert(profileB)

        let handlerFired = FlagBox()
        store.onActiveProfileChanged = { _ in handlerFired.value = true }

        let before = store.activeProfile?.id
        store.setActiveProfile(profileB.id)

        // Synchronously, in the SAME turn as the tap: the scope is already B…
        #expect(store.activeProfile?.id == profileB.id)
        #expect(before != profileB.id)
        // …while the handler that would call `talariaPlatformLink?.stop()`
        // has not run yet.
        #expect(handlerFired.value == false)

        await waitUntil { handlerFired.value }
        #expect(handlerFired.value == true)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Repro 1 — one `ensurePaired()` straddling two profiles

    /// `ensurePaired()` reads:
    ///
    /// ```swift
    /// let tokenKey = tokenKey                                  // scope resolved once
    /// if await secureStore.retrieve(key: tokenKey) != nil,     // ← suspends here
    ///    await secureStore.retrieve(key: deviceIDKey) != nil { // ← scope resolved AGAIN
    /// ```
    ///
    /// `deviceIDKey` is a computed var that calls `credentialScopeID()` fresh.
    /// It is read AFTER the first retrieve has already suspended, so a switch
    /// landing in that window splits one logical pairing check across two
    /// profiles — and the `pair()` that follows writes the two halves of ONE
    /// credential into two different profiles' slots.
    @Test func ensurePairedStraddlesTwoProfilesAcrossItsFirstAwait() async {
        defer { AtomicityStubURLProtocol.handler = nil }
        let box = ActiveProfileBox(scope: Self.scopeA, gatewayBaseURL: Self.gatewayA)
        let secure = GatedSecureStore()
        secure.keyLabels = Self.keyLabels
        // Profile A is fully, validly paired. Profile B is not paired at all.
        secure.seed(key: Self.tokenKeyA, value: "tok-A")
        secure.seed(key: Self.deviceIDKeyA, value: "dev-A")
        secure.seed(key: Self.apiKeyKeyA, value: "apikey-A")
        secure.seed(key: Self.apiKeyKeyB, value: "apikey-B")
        // Park the very first read — profile A's device-token slot.
        secure.shouldPark = { $0.operation == .retrieve && $0.key == Self.tokenKeyA && $0.occurrence == 1 }

        let wire = WireRecorder()
        let link = makeLink(box: box, secure: secure) { request in
            wire.record(WireRecorder.Call(
                host: request.url?.host ?? "?",
                body: AtomicityStubURLProtocol.bodyString(request)
            ))
            return (200, Data(#"{"device_id":"dev-fromB","device_token":"tok-fromB"}"#.utf8))
        }

        let turn = Task { await link.ensurePaired() }
        await waitForPark(secure)
        // Anti-vacuous-pass guard: the turn really is suspended mid-flight.
        #expect(secure.pendingCount == 1)
        #expect(secure.trace == ["retrieve(A.deviceToken)"])

        // The profile switch, landing inside the turn.
        box.switchTo(scope: Self.scopeB, gatewayBaseURL: Self.gatewayB)
        #expect(box.scope == Self.scopeB)  // the flip really happened, before the second read

        secure.release()
        let paired = await turn.value

        print("#285 repro1 keychain trace: \(secure.trace)")
        print("#285 repro1 wire trace: \(wire.trace)")

        // ── The recorded interleaving ──────────────────────────────────────
        // One `ensurePaired()` call, two profiles: it read A's token slot,
        // then B's device-id slot, minted with B's API key against B's
        // gateway, and wrote the result into A's token slot and B's
        // device-id slot.
        #expect(secure.trace == [
            "retrieve(A.deviceToken)",
            "retrieve(B.deviceID)",
            "retrieve(B.apiKey)",
            "store(A.deviceToken)",
            "store(B.deviceID)",
        ])
        #expect(paired == true)

        // The resulting Keychain state is cross-contaminated in BOTH
        // directions from this single turn:
        // • profile A's device token was overwritten by one minted by
        //   profile B's host, while A keeps its old device id — A now looks
        //   "paired" to `ensurePaired` but its two halves come from
        //   different servers.
        #expect(secure.peek(key: Self.tokenKeyA) == "tok-fromB")
        #expect(secure.peek(key: Self.deviceIDKeyA) == "dev-A")
        // • profile B got a device id but no token — half-paired, the exact
        //   state `ensurePaired`'s doc comment says must never persist
        //   ("a half-written pair is unusable").
        #expect(secure.peek(key: Self.deviceIDKeyB) == "dev-fromB")
        #expect(secure.peek(key: Self.tokenKeyB) == nil)

        // And the pair call itself went to B's gateway with B's API key.
        #expect(wire.all.count == 1)
        #expect(wire.all.first?.host == "gateway-b.local")
        #expect(wire.all.first?.body.contains("apikey-B") == true)
    }

    /// The control for Repro 1: same gate, same park, same release — but no
    /// profile switch. If this one ALSO showed mixed keys the harness would be
    /// manufacturing the defect rather than exposing it.
    @Test func withoutASwitchTheSameGatedTurnStaysOnOneProfile() async {
        defer { AtomicityStubURLProtocol.handler = nil }
        let box = ActiveProfileBox(scope: Self.scopeA, gatewayBaseURL: Self.gatewayA)
        let secure = GatedSecureStore()
        secure.keyLabels = Self.keyLabels
        secure.seed(key: Self.tokenKeyA, value: "tok-A")
        secure.seed(key: Self.apiKeyKeyA, value: "apikey-A")
        // Note: A's device id deliberately absent, so this turn takes the same
        // pair() path as Repro 1 rather than short-circuiting.
        secure.shouldPark = { $0.operation == .retrieve && $0.key == Self.tokenKeyA && $0.occurrence == 1 }

        let wire = WireRecorder()
        let link = makeLink(box: box, secure: secure) { request in
            wire.record(WireRecorder.Call(
                host: request.url?.host ?? "?",
                body: AtomicityStubURLProtocol.bodyString(request)
            ))
            return (200, Data(#"{"device_id":"dev-fromA","device_token":"tok-fromA"}"#.utf8))
        }

        let turn = Task { await link.ensurePaired() }
        await waitForPark(secure)
        #expect(secure.pendingCount == 1)
        secure.release()
        #expect(await turn.value == true)

        print("#285 control trace: \(secure.trace)")
        #expect(secure.trace == [
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
            "retrieve(A.apiKey)",
            "store(A.deviceToken)",
            "store(A.deviceID)",
        ])
        #expect(secure.peek(key: Self.tokenKeyB) == nil)
        #expect(secure.peek(key: Self.deviceIDKeyB) == nil)
        #expect(wire.all.allSatisfy { $0.host == "gateway-a.local" })
    }

    // MARK: - Repro 2 — profile A's credentials against profile B's endpoint

    /// `post()` calls `endpointURL()`, which calls `gatewayBaseURL()`, on EVERY
    /// request — while the token and device id it is carrying were read from
    /// the Keychain earlier in the same turn. Park the last credential read,
    /// switch, release, and the drain presents profile A's device token to
    /// profile B's gateway.
    @Test func profileACredentialsArePostedToProfileBsGateway() async {
        defer { AtomicityStubURLProtocol.handler = nil }
        let box = ActiveProfileBox(scope: Self.scopeA, gatewayBaseURL: Self.gatewayA)
        let secure = GatedSecureStore()
        secure.keyLabels = Self.keyLabels
        secure.seed(key: Self.tokenKeyA, value: "tok-A")
        secure.seed(key: Self.deviceIDKeyA, value: "dev-A")
        secure.seed(key: Self.apiKeyKeyA, value: "apikey-A")
        secure.seed(key: Self.apiKeyKeyB, value: "apikey-B")
        // A fully-paired drain reads A's device id TWICE (once inside
        // `ensurePaired`, once in `drain` itself). Park the second — the last
        // credential read before the POST.
        secure.shouldPark = { $0.operation == .retrieve && $0.key == Self.deviceIDKeyA && $0.occurrence == 2 }

        let wire = WireRecorder()
        let link = makeLink(box: box, secure: secure) { request in
            wire.record(WireRecorder.Call(
                host: request.url?.host ?? "?",
                body: AtomicityStubURLProtocol.bodyString(request)
            ))
            return (200, Data(#"{"items":[],"queries":[]}"#.utf8))
        }

        let turn = Task { await link.drainOnce(wait: false) }
        await waitForPark(secure)
        #expect(secure.pendingCount == 1)
        // Nothing has gone out on the wire yet — the switch genuinely precedes
        // the POST rather than racing it.
        #expect(wire.all.isEmpty)
        #expect(secure.trace == [
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
        ])

        box.switchTo(scope: Self.scopeB, gatewayBaseURL: Self.gatewayB)
        #expect(box.scope == Self.scopeB)

        secure.release()
        let outcome = await turn.value

        print("#285 repro2 keychain trace: \(secure.trace)")
        print("#285 repro2 wire trace: \(wire.trace)")

        let posted = wire.all
        #expect(posted.count == 1)
        // Profile A's credentials, profile B's host.
        #expect(posted.first?.host == "gateway-b.local")
        #expect(posted.first?.body.contains("\"auth\":\"tok-A\"") == true)
        #expect(posted.first?.body.contains("\"device_id\":\"dev-A\"") == true)
        #expect(outcome == .idle)
    }

    // MARK: - Repro 3 — `stop()` does not unwind an in-flight turn

    /// `stop()` sets `isRunning = false` and cancels `loopTask`, but the loop
    /// only consults `isRunning` at the TOP of an iteration, and a
    /// `CheckedContinuation` is not cancellation-aware. So a turn parked in a
    /// Keychain call when the profile switch fires resumes afterwards and
    /// keeps going — and everything it re-resolves from then on belongs to the
    /// NEW profile.
    ///
    /// This is the load-bearing repro, because `handleActiveProfileChanged`'s
    /// `stop()` is the app's ONLY defence against a cross-profile turn ("park
    /// the drain before the scope moves").
    @Test func stopDoesNotUnwindOrContainAnInFlightTurn() async {
        defer { AtomicityStubURLProtocol.handler = nil }
        let box = ActiveProfileBox(scope: Self.scopeA, gatewayBaseURL: Self.gatewayA)
        let secure = GatedSecureStore()
        secure.keyLabels = Self.keyLabels
        secure.seed(key: Self.tokenKeyA, value: "tok-A")
        secure.seed(key: Self.deviceIDKeyA, value: "dev-A")
        secure.seed(key: Self.apiKeyKeyA, value: "apikey-A")
        secure.seed(key: Self.apiKeyKeyB, value: "apikey-B")
        // Park the drain's OWN token read (the second read of A's token slot),
        // i.e. one step earlier than Repro 2. What follows the release is then
        // a KEYCHAIN read, not a network call — and keychain work is the half
        // of the turn that no cancellation can touch, which is what makes this
        // repro deterministic. (Parking one step later instead makes the next
        // action the POST, and whether that POST wins its race with
        // `loopTask.cancel()` is genuinely non-deterministic — measured, see
        // RED-REPORT.md.)
        secure.shouldPark = { $0.operation == .retrieve && $0.key == Self.tokenKeyA && $0.occurrence == 2 }

        let wire = WireRecorder()
        let received = ItemsBox()
        let link = makeLink(box: box, secure: secure, onItems: { received.items = $0 }) { request in
            let body = AtomicityStubURLProtocol.bodyString(request)
            wire.record(WireRecorder.Call(host: request.url?.host ?? "?", body: body))
            if body.contains("\"drain\"") {
                return (200, Data(#"""
                {"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-07T10:00:00+00:00"}],"queries":[]}
                """#.utf8))
            }
            return (200, Data(#"{"acked":["i1"]}"#.utf8))
        }

        // The production entry point: the polling loop, not a hand-rolled Task.
        link.start()
        await waitForPark(secure)
        #expect(secure.pendingCount == 1)
        #expect(link.isRunning == true)

        // The switch, in the real order: the scope moves first (see the
        // provenance test above), then the handler's stop() lands.
        box.switchTo(scope: Self.scopeB, gatewayBaseURL: Self.gatewayB)
        link.stop()

        // stop() returned, the link reports itself stopped — and the turn is
        // still sitting there, parked, entirely unaffected.
        #expect(link.isRunning == false)
        #expect(secure.pendingCount == 1)
        let traceAtStop = secure.trace

        secure.release()
        // Wait on the post-release keychain read, then settle, so a
        // "nothing happened" reading would be a finding and not a early look.
        await waitUntil { secure.trace.count > traceAtStop.count }
        try? await Task.sleep(for: .milliseconds(250))

        print("#285 repro3 trace at stop(): \(traceAtStop)")
        print("#285 repro3 keychain trace after release: \(secure.trace)")
        print("#285 repro3 wire trace after release: \(wire.trace)")
        print("#285 repro3 items delivered after stop(): \(received.items.map(\.id))")

        // ── Pinned facts ───────────────────────────────────────────────────
        // 1. stop() did not unwind the parked turn — asserted above: it was
        //    still parked, and `isRunning` already false, when stop() returned.
        #expect(traceAtStop == [
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
            "retrieve(A.deviceToken)",
        ])
        // 2. The stopped turn RESUMED and issued a fresh credential read — and
        //    resolved it under the NEW profile. One `drain` call read profile
        //    A's device token and profile B's device id, after stop().
        #expect(secure.trace == [
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
            "retrieve(A.deviceToken)",
            "retrieve(B.deviceID)",
        ])
        // 3. Here that mis-scoped read misses (B is unpaired), so the turn
        //    bails before its POST — which is why this repro is deterministic.
        //    Repro 2 is the same interleaving one step later, where the read
        //    HITS and the turn posts A's credentials at B's gateway.
        #expect(wire.all.isEmpty)
        #expect(received.items.isEmpty)
    }

    /// Repro 3b — the side effect `stop()`'s task cancellation CANNOT suppress.
    ///
    /// Same shape, but the turn is parked AFTER its network round trip has
    /// already completed with a 401, i.e. inside the self-repair path that
    /// deletes both halves of the stored pair. `drain` captured `tokenKey`
    /// under profile A but re-resolves `deviceIDKey` fresh — so after the
    /// switch, a turn belonging to profile A deletes profile B's device id.
    @Test func aStoppedTurnStillDeletesTheNewProfilesCredential() async {
        defer { AtomicityStubURLProtocol.handler = nil }
        let box = ActiveProfileBox(scope: Self.scopeA, gatewayBaseURL: Self.gatewayA)
        let secure = GatedSecureStore()
        secure.keyLabels = Self.keyLabels
        // Profile A: stale pair (the host will 401 it). Profile B: a perfectly
        // good pair that has nothing to do with this turn.
        secure.seed(key: Self.tokenKeyA, value: "stale-A")
        secure.seed(key: Self.deviceIDKeyA, value: "dev-A")
        secure.seed(key: Self.apiKeyKeyA, value: "apikey-A")
        secure.seed(key: Self.tokenKeyB, value: "tok-B")
        secure.seed(key: Self.deviceIDKeyB, value: "dev-B")
        secure.seed(key: Self.apiKeyKeyB, value: "apikey-B")
        // Park the FIRST of the two self-repair deletes — reached only after
        // the 401 came back, so the network exchange is real and already done.
        // Keyed precisely: a bare "first delete" predicate would also park the
        // second delete (a different key, so also occurrence 1) and wedge the
        // turn instead of releasing it.
        secure.shouldPark = { $0.operation == .delete && $0.key == Self.tokenKeyA && $0.occurrence == 1 }

        let wire = WireRecorder()
        let link = makeLink(box: box, secure: secure) { request in
            let body = AtomicityStubURLProtocol.bodyString(request)
            wire.record(WireRecorder.Call(host: request.url?.host ?? "?", body: body))
            // The re-pair that follows the deletes is REFUSED (500), on
            // purpose: whether that post-stop() request survives its race with
            // `loopTask.cancel()` is non-deterministic, and a 200 there would
            // let a winning request re-write the very slots this test inspects.
            // Refusing it makes the final Keychain state a function of the
            // deletes alone — which are not cancellable and not racy.
            if body.contains("\"pair\"") { return (500, Data(#"{"error":"nope"}"#.utf8)) }
            return (401, Data(#"{"error":"bad token","code":"invalid_talaria_auth"}"#.utf8))
        }

        link.start()
        await waitForPark(secure)
        #expect(secure.pendingCount == 1)
        // The 401 really happened before the park.
        #expect(wire.all.count == 1)
        #expect(wire.all.first?.host == "gateway-a.local")

        box.switchTo(scope: Self.scopeB, gatewayBaseURL: Self.gatewayB)
        link.stop()
        #expect(link.isRunning == false)
        #expect(secure.pendingCount == 1)

        secure.release()
        // Wait on the TRACE, not on the value: a value-based wait would be
        // satisfied by a transient nil and could look past a later re-write.
        await waitUntil { secure.trace.contains("delete(B.deviceID)") }
        try? await Task.sleep(for: .milliseconds(250))

        print("#285 repro3b keychain trace: \(secure.trace)")
        print("#285 repro3b wire trace: \(wire.trace)")

        // A stopped turn belonging to profile A deleted profile B's device id.
        #expect(secure.trace.contains("delete(A.deviceToken)"))
        #expect(secure.trace.contains("delete(B.deviceID)"))
        #expect(secure.trace.contains("delete(A.deviceID)") == false)
        #expect(secure.peek(key: Self.deviceIDKeyB) == nil)
        // Profile B is left half-paired: token intact, device id destroyed.
        #expect(secure.peek(key: Self.tokenKeyB) == "tok-B")
        // Profile A is left with an orphaned device id and no token.
        #expect(secure.peek(key: Self.tokenKeyA) == nil)
        #expect(secure.peek(key: Self.deviceIDKeyA) == "dev-A")
    }
}

/// This suite's own stub — `TalariaPlatformLinkTests`' is `private` to that
/// file, and a shared static handler across two suites would be a race.
private final class AtomicityStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession moves `httpBody` into `httpBodyStream` before a protocol
    /// ever sees the request, so reading only `httpBody` returns nothing.
    static func bodyString(_ request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let capacity = 4096
        var buffer = [UInt8](repeating: 0, count: capacity)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: capacity)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
