import Foundation
import Testing
@testable import Talaria

/// **#302 / #323 — the App Lock gate.** Bars 302-D…G and 323-A…E, all nine
/// against one object, exactly as they were pre-registered on 2026-08-20
/// before any of this code existed.
///
/// **What was measured on device (build 2484, 2026-08-10), which is what
/// these bars are defending against:** the microphone ran hot for 34.9 s
/// behind the cover and went hot 3.87 s *before* the user cancelled Face ID;
/// a complete inference turn routed, ran and committed to the transcript; the
/// sensor pipeline collected GPS (±9.7 m) and health and tried to upload
/// them, failing only because the host happened to be off. App Lock was an
/// opaque `UIWindow` and nothing else — `cover=locked` and "the app is
/// active" were simultaneously true.
///
/// **Two of these nine bars are negative controls, and they are the reason
/// the other seven mean anything.** 302-G and 323-E assert that a build with
/// the lock OFF behaves exactly as it did before this lane. Without them the
/// whole set is satisfiable by a gate that defers everything forever — which
/// would trade a privacy defect for an availability defect and score green on
/// every "did it get blocked?" assertion.
@MainActor
struct AppLockGateTests {

    // MARK: - Harness

    /// Bounded settle. Everything here is `@MainActor`, so a spawned task
    /// only makes progress when this one yields — and a parked caller makes
    /// no progress at all, which is the state most of these bars assert.
    ///
    /// Bounded rather than `await task.value` on purpose: a bar that FAILS by
    /// hanging the suite reports nothing at all, and this project has already
    /// lost 47 minutes once to a test that stalled instead of failing.
    private func settle(
        until condition: @MainActor () -> Bool,
        ticks: Int = 400
    ) async -> Bool {
        for _ in 0..<ticks {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// Lets any pending work run without waiting for a condition — used where
    /// the assertion is that something DID NOT happen, so there is no
    /// positive edge to wait for.
    private func quiesce(ticks: Int = 200) async {
        for _ in 0..<ticks { await Task.yield() }
    }

    private final class StubAuthenticator: AppLockAuthenticating {
        var stubbedCapability: AppLockCapability = .faceID
        var nextResult = false
        func capability() -> AppLockCapability { stubbedCapability }
        func authenticate(reason: String) async -> Bool { nextResult }
    }

    /// Counts starts. The bars need "was `startSession()` reached?", not what
    /// it did — the whole claim is that the capture chain is never entered.
    private final class CountingVoiceService: VoiceSessionServiceProtocol {
        private(set) var startCallCount = 0
        private(set) var endCallCount = 0

        var voiceState: VoiceState = .idle
        var connectionState: TalkConnectionState = .idle
        var transcriptItems: [TranscriptItem] = []
        var sessionDuration: TimeInterval = 0
        var isMuted = false
        var blockedReason: String?
        var statusMessage: String?
        var canStartSession = true
        var latencyMetrics = TalkLatencyMetrics()

        var snapshot: TalkSessionSnapshot {
            TalkSessionSnapshot(
                voiceState: voiceState,
                connectionState: connectionState,
                transcriptItems: transcriptItems,
                sessionDuration: sessionDuration,
                isMuted: isMuted,
                blockedReason: blockedReason,
                statusMessage: statusMessage,
                canStartSession: canStartSession,
                latencyMetrics: latencyMetrics,
                voiceSessionID: nil
            )
        }

        func events() -> AsyncStream<TalkSessionEvent> {
            AsyncStream { continuation in
                continuation.yield(.snapshot(snapshot))
                continuation.finish()
            }
        }

        func refreshReadiness() async {}
        func startSession() async { startCallCount += 1 }
        func endSession() async { endCallCount += 1 }
        func toggleMute() async {}
        func manuallyInterruptAssistantOutput() {}
        @discardableResult
        func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool { false }
    }

    private final class CountingChatClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        private(set) var sendStreamingCallCount = 0

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            sendStreamingCallCount += 1
            return AsyncStream { continuation in
                continuation.yield(.finished(
                    Message(sender: .hermes, content: "Done.", status: .delivered),
                    nil,
                    nil
                ))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            if let currentConversation { return currentConversation }
            let fresh = Conversation(title: "Hermes")
            currentConversation = fresh
            return fresh
        }

        func clearConversation() async throws -> Conversation {
            let fresh = Conversation(title: "Hermes")
            currentConversation = fresh
            return fresh
        }
    }

    private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "app-lock-gate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    // MARK: - 302-D — the gate exists as ONE state, and the cover drives it

    /// The gate tracks `cover == .locked` across a full episode — and
    /// `.obscured` does NOT lock it.
    ///
    /// **The `.obscured` assertion is the load-bearing one.** The
    /// app-switcher snapshot, a pulled notification shade, an incoming call
    /// and the Face ID sheet's own inactivity blip all produce `.obscured`.
    /// A gate that locked on those would defer the user's work every time
    /// they glanced at Control Center.
    @Test func gateTracksTheCoverAndObscuredDoesNotLockIt() async {
        let gate = AppLockGate()
        let auth = StubAuthenticator()
        let controller = AppLockController(
            configuration: { AppLockConfiguration(isEnabled: true, gracePeriod: .immediate) },
            authenticator: auth,
            now: { Date(timeIntervalSince1970: 2_000_000) },
            gate: gate
        )

        // Cold launch with the feature on locks immediately (#124).
        #expect(controller.cover == .locked)
        #expect(gate.isLocked)

        auth.nextResult = true
        controller.scenePhaseChanged(to: .active)
        await controller.requestUnlock()
        #expect(controller.cover == .none)
        #expect(!gate.isLocked)

        // Unlocked + not active ⇒ `.obscured`, which must NOT lock the gate.
        auth.nextResult = false
        controller.scenePhaseChanged(to: .inactive)
        #expect(controller.cover == .obscured)
        #expect(!gate.isLocked, "`.obscured` is a privacy shield, not a lock — gating on it defers work every time the user pulls the notification shade")

        // Background then foreground past the grace period re-locks. Asserted
        // synchronously, before yielding: `.active` schedules an auto-prompt
        // Task, and `nextResult` is false so it cannot unlock anyway.
        controller.scenePhaseChanged(to: .background)
        controller.scenePhaseChanged(to: .active)
        #expect(controller.cover == .locked)
        #expect(gate.isLocked)
    }

    /// Disabling the feature releases the lock, and the gate follows.
    @Test func disablingTheLockReleasesTheGate() {
        let gate = AppLockGate()
        var enabled = true
        let controller = AppLockController(
            configuration: { AppLockConfiguration(isEnabled: enabled, gracePeriod: .immediate) },
            authenticator: StubAuthenticator(),
            now: { Date(timeIntervalSince1970: 2_000_000) },
            gate: gate
        )
        #expect(gate.isLocked)

        enabled = false
        controller.configurationChanged()
        #expect(controller.cover == .none)
        #expect(!gate.isLocked)
    }

    // MARK: - 302-E — a voice start behind the cover leaves the mic COLD

    /// `startSession()` — the overlay/TalkMode door.
    @Test func voiceStartDefersUntilUnlock() async {
        let gate = AppLockGate(isLocked: true)
        let voice = CountingVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        let start = Task { await store.startSession() }
        #expect(await settle(until: { gate.parkedWaiterCount == 1 }))

        // The half that matters. Asserting only the post-unlock start would
        // pass on a build with no gate at all.
        #expect(voice.startCallCount == 0, "the capture chain must be COLD while the cover is locked — this is bar 302-B's device finding, inverted")
        // The DURABLE half. `statusMessage` alone flaked under full-suite
        // scheduling — a snapshot delivered by the event task overwrote it —
        // and that flake was a real defect, not test noise: the honest status
        // was a one-shot write in a field every snapshot clobbers.
        #expect(store.isWaitingForUnlock)
        #expect(store.statusMessage == TalkStore.lockedWaitingMessage)

        gate.setLocked(false)
        #expect(await settle(until: { voice.startCallCount == 1 }))
        _ = await start.value
    }

    /// `startSessionDirectly()` — the Control Center / CarPlay door.
    ///
    /// Scored SEPARATELY from `startSession()` because a fix that guards one
    /// door and not the other is the #323 class ("a subsystem nobody wired")
    /// arriving inside its own fix. This is also the door the device
    /// reproduction came through: Control Center → "Talk to Hermes".
    @Test func voiceDirectStartDefersUntilUnlock() async {
        let gate = AppLockGate(isLocked: true)
        let voice = CountingVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        let start = Task { await store.startSessionDirectly() }
        #expect(await settle(until: { gate.parkedWaiterCount == 1 }))

        #expect(voice.startCallCount == 0)
        // A parked start must not claim to be connecting. Saying "Connecting…"
        // for the whole locked interval is the silent-wrong-answer shape #180
        // forbids, and #310's `markRelayUnavailable()` is the precedent for
        // stating a refusal honestly instead.
        #expect(store.connectionState != .connecting)
        #expect(store.isWaitingForUnlock)
        #expect(store.statusMessage == TalkStore.lockedWaitingMessage)

        gate.setLocked(false)
        #expect(await settle(until: { voice.startCallCount == 1 }))
        // The parked status does not stick: `applySnapshot` publishes the
        // service's own state once the start returns. Deliberately NOT
        // asserting `.connecting` here — the store sets it before the await
        // and then adopts the snapshot after it, so `.connecting` is a
        // transient the test cannot observe without racing the thing it
        // measures.
        #expect(!store.isWaitingForUnlock)
        _ = await start.value
    }

    // MARK: - 302-F — an ABANDONED parked start never opens the microphone

    /// #139's defect arriving by the new door: park a start on the lock, let
    /// the user dismiss it, and a naive resume opens a local microphone for a
    /// session nobody is in.
    ///
    /// This is the bar most likely to catch a plausible implementation —
    /// "await the gate, then start" passes 302-E perfectly and fails here.
    @Test func abandonedStartParkedOnTheLockNeverOpensTheMicrophone() async {
        let gate = AppLockGate(isLocked: true)
        let voice = CountingVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        let start = Task { await store.startSessionDirectly() }
        #expect(await settle(until: { gate.parkedWaiterCount == 1 }))
        #expect(voice.startCallCount == 0)

        // The user dismissed while the start was parked behind the cover.
        await store.abandonSession()

        gate.setLocked(false)
        await quiesce()
        #expect(voice.startCallCount == 0, "the session was abandoned while parked — resuming into a start opens a microphone for nobody (#139)")
        _ = await start.value
    }

    // MARK: - 302-G — App Lock OFF is a NO-OP on the voice path

    /// The negative control. **Without this, 302-E and 302-F are both
    /// satisfied by a build that never starts voice at all** — the failure
    /// mode that makes a deferral gate indistinguishable from a broken one.
    @Test func voiceStartsImmediatelyWhenTheGateIsUnlocked() async {
        let gate = AppLockGate(isLocked: false)
        let voice = CountingVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        await store.startSession()
        #expect(voice.startCallCount == 1)
        #expect(gate.parkedWaiterCount == 0)
        #expect(!store.isWaitingForUnlock)

        await store.startSessionDirectly()
        #expect(voice.startCallCount == 2)
        #expect(gate.parkedWaiterCount == 0)
    }

    /// A store with NO gate in its graph — previews, tests, and any wiring
    /// that predates this lane — behaves exactly as it did before.
    @Test func voiceStartIsUnchangedWithNoGateWired() async {
        let voice = CountingVoiceService()
        let store = TalkStore(voiceService: voice)
        await store.startSession()
        #expect(voice.startCallCount == 1)
    }

    // MARK: - 323-A — a new inference turn defers, transcript included

    /// The gate must block the TRANSCRIPT WRITE as well as the network.
    ///
    /// #323's finding was not merely that a turn ran behind the cover: it is
    /// that *"the transcript kept it"* and Owen found the whole conversation
    /// waiting when he unlocked. A gate that blocks the network but still
    /// appends the user's turn has not fixed what was reported — which is why
    /// the park is at the very top of `sendMessage`, ahead of every mutation.
    @Test func inferenceTurnDefersUntilUnlockAndWritesNothingMeanwhile() async {
        let gate = AppLockGate(isLocked: true)
        let client = CountingChatClient()
        let store = ChatStore(hermesClient: client, persistence: makePersistence(), appLockGate: gate)

        let send = Task { await store.sendMessage("what is on my calendar") }
        #expect(await settle(until: { gate.parkedWaiterCount == 1 }))

        #expect(client.sendStreamingCallCount == 0)
        #expect(store.conversation?.messages.isEmpty ?? true, "no optimistic row may land behind the cover — the transcript keeping the turn IS the reported defect")

        gate.setLocked(false)
        #expect(await settle(until: { client.sendStreamingCallCount == 1 }))
        #expect(store.conversation?.messages.contains { $0.sender == .user } == true)
        _ = await send.value
    }

    // MARK: - 323-B — the App Intent path is EXEMPT, explicitly

    /// #124's recorded decision, preserved on purpose: App Intents (Ask
    /// Hermes from Siri/Shortcuts) BYPASS this lock — the intent path has no
    /// UI, so a locked phone can still ask Hermes headlessly, exactly like a
    /// lock-screen Siri query. The same principle the 2026-08-18 ruling
    /// applies to `talaria_phone_query`.
    ///
    /// **Honest limit, stated rather than implied.** This scores the POLICY:
    /// `.bypassLock` dispatches while locked. That `AskHermesIntent` actually
    /// passes it is a CODE READ (`Talaria/Intents/AskHermesIntent.swift`, the
    /// `sendMessage(trimmedQuestion, lockPolicy: .bypassLock)` call) — driving
    /// the intent itself needs the App Intents runtime, which this suite does
    /// not host. The bar still earns its place: a later lane that "simplifies
    /// away" the parameter cannot compile the call site without deciding
    /// again.
    @Test func appIntentPolicyDispatchesWhileLocked() async {
        let gate = AppLockGate(isLocked: true)
        let client = CountingChatClient()
        let store = ChatStore(hermesClient: client, persistence: makePersistence(), appLockGate: gate)

        await store.sendMessage("hey hermes", lockPolicy: .bypassLock)

        #expect(client.sendStreamingCallCount == 1, "#124 rules the intent path headless — deferring it burns the Siri budget and answers 'still working'")
        #expect(gate.parkedWaiterCount == 0)
        #expect(gate.isLocked, "the exemption must not release the lock for everyone else")
    }

    // MARK: - 323-C — `talaria_phone_query` KEEPS ANSWERING while covered

    /// Per the ruling: the agent is the owner's, and the cover hides the
    /// answer from whoever is holding the phone either way.
    ///
    /// **This is a TRIPWIRE and is green by construction today** —
    /// `PhoneQueryResponder` holds no reference to the gate, so it cannot be
    /// affected. That is exactly the property being pinned. It goes red the
    /// day a lane "tightens" the lock by wiring the gate in here, which would
    /// take the owner's own agent offline whenever their phone happened to be
    /// locked. Stated plainly rather than dressed up as a behavioural result.
    @Test func phoneQueryStillAnswersWhileTheGateIsLocked() async {
        let gate = AppLockGate(isLocked: true)
        var settings = UserSettings()
        settings.sensorStreamingEnabled = true
        settings.locationCollectionEnabled = true

        let reader = GateProbeReader()
        let responder = PhoneQueryResponder(settings: { settings }, reader: reader)

        let locked = await responder.answer(kind: "location", params: [:])
        gate.setLocked(false)
        let unlocked = await responder.answer(kind: "location", params: [:])

        #expect(locked == .success(text: "Current location: Home"))
        #expect(locked == unlocked, "the covered answer must be byte-identical to the uncovered one")
    }

    // MARK: - 323-D — the lock OUTRANKS the approval mode

    /// With the cover locked, `requestConfirmation` stages the card WITHOUT
    /// consulting `modeProvider`.
    ///
    /// **Scored on the spy, not the outcome, and that choice is the bar.**
    /// `.manual` is the only mode the settings layer can produce in this
    /// build, so an outcome assertion ("it didn't auto-approve") would pass
    /// for the wrong reason and keep passing after someone deleted the gate.
    /// Watching the provider makes it mutation-testable NOW against a mode
    /// (#224 Phase 1's `.autoApprove`) that does not yet ship — which is the
    /// ruling's *"a subsystem nobody wired becomes structurally impossible"*
    /// applied before the subsystem exists, the only time it is cheap.
    @Test func lockedApprovalNeverConsultsTheMode() async {
        let center = ToolConfirmationCenter()
        let probe = ModeProbe()
        center.modeProvider = { probe.record() }
        center.lockStateProvider = { true }

        let decision = Task {
            await center.requestConfirmation(
                title: "Create this reminder?",
                fields: [.init(key: "title", label: "Title", value: "Milk")]
            )
        }
        #expect(await settle(until: { center.pending != nil }))

        #expect(probe.callCount == 0, "the lock outranks the mode — a covered app must not even ask what it would rather do")
        #expect(center.pending?.title == "Create this reminder?")

        center.decline()
        let outcome = await decision.value
        if case .declined = outcome {} else { Issue.record("the staged card resolved as \(outcome)") }
    }

    /// The same call with the cover DOWN consults the mode exactly as before.
    /// This is what makes the assertion above a measurement rather than a
    /// tautology: the spy is reachable, and only the lock stops it.
    @Test func unlockedApprovalStillConsultsTheMode() async {
        let center = ToolConfirmationCenter()
        let probe = ModeProbe()
        center.modeProvider = { probe.record() }
        center.lockStateProvider = { false }

        let decision = Task {
            await center.requestConfirmation(
                title: "Create this reminder?",
                fields: [.init(key: "title", label: "Title", value: "Milk")]
            )
        }
        #expect(await settle(until: { center.pending != nil }))

        #expect(probe.callCount == 1)
        center.decline()
        let outcome = await decision.value
        if case .declined = outcome {} else { Issue.record("the staged card resolved as \(outcome)") }
    }

    // MARK: - 323-E — App Lock OFF is a NO-OP across every consumer

    /// The global negative control, and the bar that makes the other four
    /// mean anything: **without it the entire lane is satisfiable by a build
    /// that defers everything forever**, which would pass 323-A, 302-E and
    /// 302-F simultaneously while making the app unusable.
    @Test func nothingDefersWhenTheLockIsOff() async {
        let gate = AppLockGate(isLocked: false)

        // Chat dispatches immediately, no park.
        let client = CountingChatClient()
        let store = ChatStore(hermesClient: client, persistence: makePersistence(), appLockGate: gate)
        await store.sendMessage("hello")
        #expect(client.sendStreamingCallCount == 1)
        #expect(gate.parkedWaiterCount == 0)

        // Voice starts immediately.
        let voice = CountingVoiceService()
        let talk = TalkStore(voiceService: voice, appLockGate: gate)
        await talk.startSession()
        #expect(voice.startCallCount == 1)

        // Approvals consult the mode exactly as they did before this lane.
        let center = ToolConfirmationCenter()
        let probe = ModeProbe()
        center.modeProvider = { probe.record() }
        center.lockStateProvider = { gate.isLocked }
        let decision = Task {
            await center.requestConfirmation(title: "Create?", fields: [])
        }
        #expect(await settle(until: { center.pending != nil }))
        #expect(probe.callCount == 1)
        center.decline()
        _ = await decision.value
    }

    // MARK: - The gate's own mechanics

    /// A wait that is CANCELLED resumes rather than stranding its caller.
    ///
    /// A non-cancellable await is how a parked caller outlives the reason it
    /// was waiting — the shape this project has already been bitten by, and
    /// the reason `waitUntilUnlocked()` carries a cancellation handler at all.
    @Test func aCancelledWaitResumesInsteadOfStranding() async {
        let gate = AppLockGate(isLocked: true)
        let finished = Flag()

        let waiter = Task {
            await gate.waitUntilUnlocked()
            finished.value = true
        }
        #expect(await settle(until: { gate.parkedWaiterCount == 1 }))

        waiter.cancel()
        #expect(await settle(until: { finished.value }))
        #expect(gate.parkedWaiterCount == 0)
        #expect(gate.isLocked, "cancelling a wait must not unlock the app")
    }

    /// Several parked callers all resume on one unlock, and the release does
    /// not lose any of them.
    @Test func everyParkedWaiterResumesOnUnlock() async {
        let gate = AppLockGate(isLocked: true)
        let counter = Counter()

        for _ in 0..<5 {
            Task {
                await gate.waitUntilUnlocked()
                counter.value += 1
            }
        }
        #expect(await settle(until: { gate.parkedWaiterCount == 5 }))

        gate.setLocked(false)
        #expect(await settle(until: { counter.value == 5 }))
        #expect(gate.parkedWaiterCount == 0)
    }
}

// MARK: - Probes

/// Records whether `modeProvider` was consulted (bar 323-D).
@MainActor
private final class ModeProbe {
    private(set) var callCount = 0
    func record() -> ApprovalMode {
        callCount += 1
        return .manual
    }
}

@MainActor private final class Flag { var value = false }
@MainActor private final class Counter { var value = 0 }

/// Minimal `PhoneQueryReader` for the 323-C tripwire — only the one read the
/// bar exercises is meaningful; the rest satisfy the protocol.
private final class GateProbeReader: PhoneQueryReader {
    func location(relay: ToolEventRelay) async throws -> String { "Current location: Home" }
    func health(metric: String?, relay: ToolEventRelay) async throws -> String { "Steps today: 1200" }
    func motion(relay: ToolEventRelay) async throws -> String { "Current activity: walking" }
    func weather(relay: ToolEventRelay) async throws -> String { "Clear, 22C" }
    func calendar(daysAhead: Int, relay: ToolEventRelay) async throws -> String { "Standup" }
    func reminders(relay: ToolEventRelay) async throws -> String { "• Buy milk" }
    func deviceStatus() async -> String { "Battery: 80% (not charging)" }
}
