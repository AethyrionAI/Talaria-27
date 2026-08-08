import Foundation
import Testing
@testable import Talaria

/// #285 — a backend-profile switch IS an atomic transport boundary.
///
/// These tests began life as the RED reproduction suite (branch history +
/// `RED-REPORT.md` preserve the pre-fix traces verbatim: one `ensurePaired()`
/// straddling two profiles' Keychain slots, profile A's credentials POSTed to
/// profile B's gateway, a stopped turn deleting the NEW profile's device id).
/// After the fix they were INVERTED IN PLACE, not deleted — same
/// choreography, same gates, same parks, opposite assertions. What they pin
/// now is the invariant: a turn resolves its profile context ONCE
/// (`TurnContext` — scope, endpoint, all three key slots, epoch) and a turn
/// superseded by `stop()` abandons at its next side-effect checkpoint instead
/// of completing cross-profile.
///
/// Because everything here is `@MainActor` there is no true parallelism —
/// interleaving is possible only at `await` suspension points, which is
/// exactly what makes these tests deterministic rather than flaky.
///
/// **The blocker the RED suite had to clear first, still load-bearing.**
/// `SecureStoreProtocol`'s methods are `async`, but BOTH shipping conformers
/// (`KeychainSecureStore`, `MockSecureStore`) are synchronous underneath —
/// awaiting them never yields to the scheduler, so with either of them no
/// interleaving can be expressed at all and every "race" test would pass
/// vacuously. `GatedSecureStore` below genuinely parks on a
/// `CheckedContinuation` (the `GatedCronJobService` idiom from
/// `CronJobsStoreTests`) and RECORDS every (operation, key) pair in call
/// order. That recorded trace is the evidence, not the assertions' wording.
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
        // Closure shapes copied from AppContainer.swift ~:971. #285 removed
        // the injected `apiKey` closure — the link reads the key from the
        // SAME secure store itself, under its turn's frozen scope.
        return TalariaPlatformLink(
            gatewayBaseURL: { box.gatewayBaseURL },
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

    /// The premise every test below rests on, pinned against the REAL store.
    ///
    /// `BackendProfilesStore.setActiveProfile` assigns `state.activeProfileID`
    /// SYNCHRONOUSLY and only then dispatches `onActiveProfileChanged`. So on
    /// a real switch the credential scope has already moved by the time
    /// `AppContainer.handleActiveProfileChanged` — and its
    /// `talariaPlatformLink?.stop()` — gets a turn to run. That ordering is
    /// what makes "flip the box while a turn is parked" a faithful model of a
    /// user tapping a different profile, not a contrivance.
    ///
    /// It is also WHY the link's containment lives in the turn epoch rather
    /// than in `stop()`'s timing: `stop()` structurally cannot run before the
    /// scope moves, so it can never be a barrier ahead of it — it can only
    /// supersede whatever is already in flight. (The RED-era comment claiming
    /// stop() "parks the drain before the scope moves" was corrected by this
    /// lane; this test is the pin that keeps it corrected.)
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

    // MARK: - Inverted repro 1 — one `ensurePaired()` stays on ONE profile

    /// RED history: `ensurePaired()` captured `tokenKey` once but re-resolved
    /// `deviceIDKey` after its first suspension, so a switch landing in that
    /// window split one pairing check across two profiles and `pair()` wrote
    /// the two halves of ONE credential into two different profiles' slots
    /// (trace preserved in `RED-REPORT.md`).
    ///
    /// Now: the whole turn rides an immutable `TurnContext` resolved before
    /// the first await, so the mid-turn switch changes NOTHING — the trace is
    /// byte-identical to the no-switch control's, every write lands in A's
    /// slots, and the mint happens at A's gateway with A's key.
    @Test func ensurePairedCompletesEntirelyOnItsBirthProfileAcrossASwitch() async {
        defer { AtomicityStubURLProtocol.handler = nil }
        let box = ActiveProfileBox(scope: Self.scopeA, gatewayBaseURL: Self.gatewayA)
        let secure = GatedSecureStore()
        secure.keyLabels = Self.keyLabels
        // Profile A holds a token but no device id (the control's arrangement,
        // so this turn takes the same `pair()` path the RED repro took instead
        // of short-circuiting on a complete pair). Profile B is not paired.
        secure.seed(key: Self.tokenKeyA, value: "tok-A")
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
            return (200, Data(#"{"device_id":"dev-fromA","device_token":"tok-fromA"}"#.utf8))
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

        print("#285 inverted repro1 keychain trace: \(secure.trace)")
        print("#285 inverted repro1 wire trace: \(wire.trace)")

        // ── The invariant ──────────────────────────────────────────────────
        // Same shape as the control: every key resolved under A, both halves
        // of the minted credential written to A's slots. The switch that
        // landed mid-turn is invisible to this turn.
        #expect(secure.trace == [
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
            "retrieve(A.apiKey)",
            "store(A.deviceToken)",
            "store(A.deviceID)",
        ])
        #expect(paired == true)

        // A holds a complete, same-server pair; B is untouched.
        #expect(secure.peek(key: Self.tokenKeyA) == "tok-fromA")
        #expect(secure.peek(key: Self.deviceIDKeyA) == "dev-fromA")
        #expect(secure.peek(key: Self.tokenKeyB) == nil)
        #expect(secure.peek(key: Self.deviceIDKeyB) == nil)

        // And the pair call went to A's gateway with A's API key.
        #expect(wire.all.count == 1)
        #expect(wire.all.first?.host == "gateway-a.local")
        #expect(wire.all.first?.body.contains("apikey-A") == true)
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

    // MARK: - Inverted repro 2 — a drain speaks only to its birth gateway

    /// RED history: `post()` re-resolved `gatewayBaseURL()` on EVERY request,
    /// so a switch parked between the last credential read and the POST sent
    /// profile A's device token to profile B's gateway (wire trace preserved
    /// in `RED-REPORT.md`).
    ///
    /// Now: the endpoint is frozen in the `TurnContext` alongside the keys —
    /// the same park + switch releases into a POST at A's OWN gateway.
    @Test func aDrainTurnSpeaksOnlyToItsBirthProfilesGateway() async {
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

        print("#285 inverted repro2 keychain trace: \(secure.trace)")
        print("#285 inverted repro2 wire trace: \(wire.trace)")

        let posted = wire.all
        #expect(posted.count == 1)
        // Profile A's credentials, profile A's host — the frozen endpoint.
        #expect(posted.first?.host == "gateway-a.local")
        #expect(posted.first?.body.contains("\"auth\":\"tok-A\"") == true)
        #expect(posted.first?.body.contains("\"device_id\":\"dev-A\"") == true)
        #expect(outcome == .idle)
    }

    // MARK: - Inverted repro 3 — `stop()` CONTAINS an in-flight turn

    /// Still true, and still worth pinning: `stop()` cannot UNWIND a turn
    /// parked on a `CheckedContinuation` — the park survives `stop()`
    /// returning, exactly as in the RED run. What changed is what the resumed
    /// turn may do: `stop()` bumps the link's epoch, the turn's next key
    /// resolution rides its FROZEN context (no new-profile keys, ever), and
    /// the first side-effect checkpoint sees the supersession and abandons —
    /// no POST, no delivery.
    @Test func stopContainsAnInFlightTurnNoCrossProfileReadsNoSideEffects() async {
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

        print("#285 inverted repro3 trace at stop(): \(traceAtStop)")
        print("#285 inverted repro3 keychain trace after release: \(secure.trace)")
        print("#285 inverted repro3 wire trace after release: \(wire.trace)")
        print("#285 inverted repro3 items delivered after stop(): \(received.items.map(\.id))")

        // ── Pinned facts ───────────────────────────────────────────────────
        // 1. stop() still does not UNWIND the parked turn — asserted above: it
        //    was still parked, and `isRunning` already false, when stop()
        //    returned. Containment, not unwinding, is the mechanism.
        #expect(traceAtStop == [
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
            "retrieve(A.deviceToken)",
        ])
        // 2. The stopped turn resumed and finished its in-flight credential
        //    read under its FROZEN context — profile A's device id, never the
        //    new profile's. No B-scoped key is ever touched.
        #expect(secure.trace == [
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
            "retrieve(A.deviceToken)",
            "retrieve(A.deviceID)",
        ])
        // 3. The superseded turn abandoned at the pre-POST checkpoint: nothing
        //    went out on the wire and nothing was delivered into the app.
        #expect(wire.all.isEmpty)
        #expect(received.items.isEmpty)
    }

    /// Inverted repro 3b — the Keychain step a stop cannot suppress stays
    /// SELF-scoped, and the superseded turn mints nothing.
    ///
    /// RED history: the 401 self-repair deleted a captured token key and a
    /// live-resolved device-id key, so a stopped turn belonging to A deleted
    /// PROFILE B'S device id, then re-paired against B's gateway (minting the
    /// #288 orphan row). Now: the turn was already inside its delete-pair
    /// when the stop landed, so it FINISHES that one atomic step — both
    /// halves, both under its own frozen profile-A keys (a pair is dropped
    /// whole; a half-dropped pair is the state `ensurePaired`'s doc says must
    /// never persist) — and then abandons at the pre-re-pair checkpoint:
    /// no pair POST, no orphan mint, profile B byte-untouched.
    @Test func aStoppedTurnFinishesItsOwnCredentialDropAndNeverTouchesTheNewProfile() async {
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
        await waitUntil { secure.trace.contains("delete(A.deviceID)") }
        try? await Task.sleep(for: .milliseconds(250))

        print("#285 inverted repro3b keychain trace: \(secure.trace)")
        print("#285 inverted repro3b wire trace: \(wire.trace)")

        // The stopped turn finished its own pair-drop — BOTH halves, both A's.
        #expect(secure.trace.contains("delete(A.deviceToken)"))
        #expect(secure.trace.contains("delete(A.deviceID)"))
        #expect(secure.trace.contains("delete(B.deviceID)") == false)
        // Profile A is cleanly unpaired (the next A-activation re-mints).
        #expect(secure.peek(key: Self.tokenKeyA) == nil)
        #expect(secure.peek(key: Self.deviceIDKeyA) == nil)
        // Profile B's perfectly good pair is byte-untouched.
        #expect(secure.peek(key: Self.tokenKeyB) == "tok-B")
        #expect(secure.peek(key: Self.deviceIDKeyB) == "dev-B")
        // And the superseded turn abandoned before re-pairing: the only wire
        // call is the original 401'd drain — no pair POST, no orphan device
        // row minted on ANY host (#288's leak, closed at the source).
        #expect(wire.all.count == 1)
        #expect(wire.all.first?.host == "gateway-a.local")
        #expect(wire.trace.filter { $0.contains("\"pair\"") }.isEmpty)
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
