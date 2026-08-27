import Foundation
import os

/// Metadata captured when a voice session completes, used to trigger transcript injection.
/// Carries the finalized transcript itself (#1): the relay inject endpoint is out of the
/// chat path, so the hand-off into the conversation is composed entirely from this
/// on-device snapshot — it must be captured before the voice service resets its state.
struct CompletedVoiceSession: Sendable {
    let voiceSessionId: UUID
    let duration: TimeInterval
    let turnCount: Int
    let transcript: [TranscriptItem]
    /// Which engine ran the session (#18). Native-engine turns already rode
    /// the chat backend, so the post-to-Hermes context turn is skipped for
    /// them — only the local transcript rendering applies.
    ///
    /// #180 lane 180-L: optional, because the store's `voiceEngine` now is.
    /// The one consumer (`ContentView`) already tests `== .realtime`, so an
    /// unknown engine falls to the conservative side — no duplicate context
    /// turn posted for a session whose engine nobody published.
    let engine: VoiceEngine?
}

@MainActor
@Observable
final class TalkStore {
    var voiceState: VoiceState = .idle
    var connectionState: TalkConnectionState = .idle
    var transcriptItems: [TranscriptItem] = []
    var sessionDuration: TimeInterval = 0
    var isMuted = false
    var isSessionActive = false
    /// #254: **a start is in flight.** Published because `isSessionActive`
    /// cannot answer the question the background observer needs to ask.
    ///
    /// `isSessionActive` is derived in `applySnapshot` from the *engine's*
    /// published `connectionState`, so it stays false through the whole
    /// prologue of a start — the brain gate, the pairing check, the #82 mic
    /// preflight (which can sit on a permission dialog indefinitely) — and it
    /// goes false AGAIN during the realtime→native fallback, where a start
    /// that landed `.failed` opens a LOCAL microphone from a not-active state.
    /// Backgrounding in either window used to revoke nothing, and the session
    /// then landed live, speaking, with no UI and no owner.
    ///
    /// **Not `sessionGeneration`.** That counter is private and monotonic — it
    /// records how many intents have been claimed, not whether one is
    /// outstanding, and no external reader can compare it against anything.
    /// This is the state; that is the tally.
    private(set) var isStartingSession = false
    var blockedReason: String?
    var statusMessage: String?
    var canStartSession = true
    var latencyMetrics = TalkLatencyMetrics()
    var voiceSessionID: UUID?
    var readiness = TalkReadinessInfo()
    /// The engine driving (or last driving) the voice session (#18) — feeds
    /// the overlay's LOCAL VOICE badge and the Voice settings engine row.
    ///
    /// #180 lane 180-L: **nil until a snapshot publishes one.** It defaulted to
    /// `.realtime`, which meant every surface reading it named an engine before
    /// anything had selected one (bar 180-C).
    var voiceEngine: VoiceEngine?
    /// #84: flatline-tripwire hint — connected but no mic signal evidence.
    var micHealthHint: String?
    /// #84: current audio route summary while a session is (or was) live.
    var audioRouteSummary: String?

    /// Set after a voice session ends; consumed by MainTabView to trigger transcript injection.
    var lastCompletedSession: CompletedVoiceSession?

    /// Called when voice session state changes (start/end/state transition).
    var onSessionStateChanged: (@MainActor () -> Void)?

    private let voiceService: any VoiceSessionServiceProtocol
    private let liveActivity = LiveActivityService()
    private var eventTask: Task<Void, Never>?

    /// #415 — the cover watch: one task per session, cancelled with it.
    ///
    /// It exists because the pre-start gate check is a SAMPLE. See
    /// `beginCoverWatch(generation:door:)`.
    private var coverWatchTask: Task<Void, Never>?

    /// #415 — always on, `.notice`, `privacy: .public`, and NOT behind
    /// Verbose Logging, for the same reason the `#302-A` capture instrument
    /// is not: the event is rare, cheap, and only useful if it is already
    /// recording when it happens. Bar 415-D is scored by intersecting these
    /// lines with AppLock's own `cover=locked` rows — the app answering for
    /// itself instead of a framework CoreAudio row a later `log collect` may
    /// not retain.
    private static let log = Logger(subsystem: TalariaLog.subsystem, category: "Voice")

    /// #415 — which door a session came through, so a park resumes into the
    /// same one. `startSessionDirectly()` publishes its own connecting state
    /// and `startSession()` does not; resuming through the wrong one would
    /// quietly change what the overlay says.
    private enum VoiceStartDoor {
        case overlay
        case controlCenter
    }
    /// #139: monotonic session intent. Dismissal bumps it, so a connect that
    /// returns afterwards is recognised as belonging to a session the user
    /// already left, and is discarded instead of being flipped live.
    private var sessionGeneration = 0

    /// #302: the App Lock gate. Optional so tests and previews can build a
    /// store with no lock in the graph — a nil gate is an unlocked one.
    private let appLockGate: AppLockGate?

    /// #302 — TRUE while a voice start is parked behind App Lock.
    ///
    /// **A flag rather than just a string, because the string is not
    /// durable.** `statusMessage` is overwritten wholesale by every
    /// `applySnapshot`, and snapshots keep arriving during a locked interval
    /// (the engines publish on their own schedule). A one-shot write of
    /// "Waiting for unlock…" therefore survives only until the next event —
    /// which is how the honest status silently becomes the engine's stale
    /// one. Found when bar 302-E failed under FULL-SUITE scheduling while
    /// passing in isolation: the initial snapshot's event-task delivery
    /// landed after the park in one ordering and before it in the other.
    /// An assertion that flakes on scheduling was measuring something real.
    private(set) var isWaitingForUnlock = false

    init(voiceService: any VoiceSessionServiceProtocol, appLockGate: AppLockGate? = nil) {
        self.voiceService = voiceService
        self.appLockGate = appLockGate
        applySnapshot(voiceService.snapshot)
        subscribeToEvents()
    }

    func refreshReadiness() async {
        await voiceService.refreshReadiness()
        applySnapshot(voiceService.snapshot)
    }

    // #383-H: `markRelayUnavailable()` DELETED here.
    //
    // #310 added it so a relayless profile would state realtime voice
    // unavailable rather than sit showing the previous profile's "Ready".
    // That requirement is unchanged; its premise is not. #383 moved the
    // bootstrap off the relay onto the talaria plugin, so the honest answer
    // now comes from ASKING (`refreshReadiness()` degrades on its own — an
    // absent link resolves to `UnavailableVoiceTransport`, and a host whose
    // plugin predates #383 answers `unsupported`).
    //
    // Its blocked message — "Realtime voice needs a relay, and this profile
    // doesn't have one" — named a component retired on both hosts and stated
    // a requirement this app no longer has.

    /// Re-sync Live Activity state when returning from background.
    func handleAppDidBecomeActive() {
        liveActivity.handleAppDidBecomeActive()
    }

    /// Start without a prior readiness check — goes straight to session create.
    func startSessionDirectly() async {
        // #302: the generation and the intent flag are claimed BEFORE the
        // lock wait, not after. Both have to be live while parked — the
        // generation so an abandon can revoke the parked start, and
        // `isStartingSession` so #254's background revoke still sees it.
        let generation = beginSessionGeneration()
        isStartingSession = true
        // #415: a door that returns while the store is PARKED must not clear
        // the flag the park owns. The parked interval is exactly when #254's
        // background revoke needs to see a start outstanding, and on the
        // mid-flight path this door returns in the middle of it.
        defer { if !isWaitingForUnlock { isStartingSession = false } }
        guard await deferUntilUnlocked(generation: generation) else { return }
        // Deliberately AFTER the wait: a parked start must not claim to be
        // "Connecting..." for the whole locked interval. Saying so would be
        // the silent-wrong-answer shape #180 forbids, and the honest state is
        // published by `deferUntilUnlocked` instead.
        canStartSession = true
        connectionState = .connecting
        voiceState = .thinking
        statusMessage = "Connecting..."
        await runStart(generation: generation, door: .controlCenter)
    }

    func startSession() async {
        let generation = beginSessionGeneration()
        // #254: same publication as `startSessionDirectly` — both start doors
        // must be visible to the background observer, not just the overlay's.
        isStartingSession = true
        defer { if !isWaitingForUnlock { isStartingSession = false } }
        // #302: and both doors defer identically. Bar 302-E scores them
        // SEPARATELY because a fix that guards one door and not the other is
        // the #323 class arriving inside its own fix.
        guard await deferUntilUnlocked(generation: generation) else { return }
        await runStart(generation: generation, door: .overlay)
    }

    /// The body both doors share once the pre-start gate has cleared.
    ///
    /// #415: the cover watch is armed BEFORE the engine call, because that is
    /// the window the device evidence lives in — the microphone went hot
    /// **272 ms** and **2.4 s after `locked=true`**, inside this await.
    private func runStart(generation: Int, door: VoiceStartDoor) async {
        beginCoverWatch(generation: generation, door: door)
        await voiceService.startSession()
        guard generation == sessionGeneration else {
            await discardAbandonedStart()
            return
        }
        applySnapshot(voiceService.snapshot)
        if isSessionActive {
            liveActivity.startVoiceSession()
        }
    }

    /// #415 — RE-EVALUATE THE COVER FOR THE LIFETIME OF THE SESSION, not just
    /// at the instant of start.
    ///
    /// **The defect this closes is #302's own headline ordering surviving
    /// #302's fix.** `deferUntilUnlocked` samples `AppLockGate.isLocked`
    /// once; `AppLockStateMachine` computes `cover == .locked` only on the
    /// transition INTO `.active`; and a Control Center tap runs its intent in
    /// the app process during the `background → inactive` window that
    /// PRECEDES that transition. Measured on device
    /// (`whoGoesThere-415.logarchive`, 2026-08-26): the gate stayed open for
    /// **1.2 s** after the tap, the start cleared it in 23–25 ms, and the
    /// cover then armed on top of an in-flight start — mic hot 27.4 s and
    /// 13.4 s, most of it behind `cover=locked`, with a full realtime
    /// conversation under an opaque cover and no voice UI on screen. Bars
    /// 302-D…G every one place the lock BEFORE the start, so not one of them
    /// could see it.
    ///
    /// **The seam is the gate, not a new mechanism.**
    /// `AppLockController.refreshCover()` is still its only writer; this
    /// waits on `waitUntilLocked()`, the mirror of the suspension point the
    /// pre-start park already uses. No second observer, no notification, no
    /// poll — which is the #323-class discipline applied to the fix for
    /// #302's recurrence.
    private func beginCoverWatch(generation: Int, door: VoiceStartDoor) {
        coverWatchTask?.cancel()
        coverWatchTask = nil
        guard let appLockGate else { return }
        coverWatchTask = Task { @MainActor [weak self] in
            await appLockGate.waitUntilLocked()
            guard !Task.isCancelled, let self else { return }
            await self.coverArmedMidFlight(generation: generation, door: door)
        }
    }

    /// The cover came down on a session that had already started (or was
    /// still starting). Stop capture, park, and resume on unlock — the
    /// semantics `deferUntilUnlocked` already implements for a start that
    /// arrives while locked, extended to the start that was already running.
    private func coverArmedMidFlight(generation: Int, door: VoiceStartDoor) async {
        // Not ours: a dismissal, #254's background revoke, or a newer start
        // has already superseded the session this watch was armed for.
        guard generation == sessionGeneration, let appLockGate else { return }
        Self.log.notice("voice session parked — App Lock cover armed mid-flight (#415)")
        // #139's revoke, reused rather than re-invented: a start still inside
        // `voiceService.startSession()` must not land live when it returns.
        // The door's own generation re-check then routes it into
        // `discardAbandonedStart()`, so both orderings end the same way.
        sessionGeneration &+= 1
        let parkedGeneration = sessionGeneration
        // STOP FIRST, PARK SECOND — the order is the bar. A park that leaves
        // the capture chain up is this defect wearing the fix's clothes.
        //
        // `discardAbandonedStart()` and not `endSession()`, deliberately: the
        // full path publishes `lastCompletedSession`, which `MainTabView`
        // injects into the chat transcript — a transcript write behind the
        // cover, which is precisely what #323 forbids ("the transcript kept
        // it" IS the reported defect there). A covered session's turns are
        // dropped instead. In the ordering actually measured this costs
        // nothing: the cover arms 0.27–2.4 s into a start that has no turns
        // yet.
        await discardAbandonedStart()
        // #254: the park owns this flag for its duration, so a backgrounding
        // during the locked interval still revokes (`abandonSession()` bumps
        // the generation, which the resume below re-reads).
        isStartingSession = true
        isWaitingForUnlock = true
        statusMessage = Self.lockedWaitingMessage
        await appLockGate.waitUntilUnlocked()
        isWaitingForUnlock = false
        isStartingSession = false
        guard !Task.isCancelled, parkedGeneration == sessionGeneration else {
            // #139 / bar 302-F through the new door: the session was
            // abandoned while parked. Nothing to resume and nothing to tear
            // down — the stop above already ran. A naive park-and-resume
            // opens a microphone for a session nobody is in.
            Self.log.notice("parked voice session NOT resumed — abandoned under the cover (#415)")
            return
        }
        Self.log.notice("parked voice session resuming after unlock (#415)")
        // A FRESH task: the resumed start calls `beginCoverWatch`, which
        // cancels THIS one, and a start that ran inside a cancelled task
        // would fail its first network call.
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch door {
            case .overlay: await self.startSession()
            case .controlCenter: await self.startSessionDirectly()
            }
        }
    }

    /// #302 — DEFER-UNTIL-UNLOCK, the contract Owen ruled on 2026-08-10 and
    /// the design he ruled on 2026-08-18.
    ///
    /// Returns `true` when the caller may proceed, `false` when the start was
    /// abandoned while parked.
    ///
    /// **The `false` return is the whole reason this is a function and not an
    /// inline `await`.** #139's defect — a local microphone opened for a
    /// session the user already left — has a new door here: park a start on
    /// the lock, let the user dismiss it or the app background-revoke it, and
    /// a naive resume opens the mic for nobody. The generation is re-read
    /// AFTER the wait for exactly that reason, and bar 302-F is that case.
    ///
    /// **What this fixes, measured not theorised:** on device (build 2484)
    /// the capture chain went hot 3.87 s before the user cancelled Face ID
    /// and stayed hot 34.9 s behind the cover, and the arm that "passed" did
    /// so because Face ID won a 470 ms footrace. There was no gate to be
    /// late — there was no gate. This is it.
    private func deferUntilUnlocked(generation: Int) async -> Bool {
        guard let appLockGate, appLockGate.isLocked else { return true }
        // Say it, rather than sitting silent behind the cover. The user
        // cannot see this while locked — but the overlay's dismissal and the
        // Live Activity can, and an unexplained dead voice button is what
        // #310's `markRelayUnavailable()` precedent exists to prevent.
        isWaitingForUnlock = true
        defer { isWaitingForUnlock = false }
        statusMessage = Self.lockedWaitingMessage
        await appLockGate.waitUntilUnlocked()
        guard generation == sessionGeneration else {
            // Nothing to tear down: we never called into the service, so
            // there is no snapshot to discard — unlike `discardAbandonedStart`,
            // which exists for a start that DID reach the engine.
            return false
        }
        return true
    }

    /// Public so the overlay and bar 302-E can name the same string.
    static let lockedWaitingMessage = "Waiting for unlock…"

    /// #139: the dismissal path.
    ///
    /// Unlike `endSessionIfNeeded()` this does NOT guard on `isSessionActive` —
    /// and that guard is the whole reason the defect survived overlay teardown.
    /// A start that has not yet published `.connecting` is invisible to the
    /// flag, and a session that IS still connecting is exactly the one that
    /// must be revoked. Bumping the generation first means a connect already in
    /// flight is discarded on return even if its RPC cannot be cancelled.
    func abandonSession() async {
        sessionGeneration &+= 1
        await endSession()
    }

    /// Belt for a start that resolved after its session was abandoned. The
    /// engines guard their own late connects (#139), so this should find
    /// nothing live — but adopting such a snapshot is precisely the bug, so
    /// end rather than apply.
    private func discardAbandonedStart() async {
        await voiceService.endSession()
        applySnapshot(voiceService.snapshot)
    }

    private func beginSessionGeneration() -> Int {
        sessionGeneration &+= 1
        return sessionGeneration
    }

    func endSession() async {
        // #139: an explicit end revokes any connect still in flight, so a slow
        // start cannot land live after the user hung up.
        sessionGeneration &+= 1
        // #254: the start is no longer wanted. Clearing here as well as in the
        // start's own `defer` means a second background event during the same
        // (possibly 12-second, #247 B1) connect does not re-fire the revoke.
        isStartingSession = false
        // #415: the cover watch dies with the session it was armed for. A
        // watch that outlives its session is a stranded waiter — it would
        // park, and then RESUME, a session the user ended minutes ago. The
        // generation guard at the top of `coverArmedMidFlight` is the second
        // belt; this one is what keeps the gate's waiter set from growing one
        // entry per session for the life of the process.
        coverWatchTask?.cancel()
        coverWatchTask = nil
        isWaitingForUnlock = false
        // Capture session metadata before the service resets
        let sessionId = voiceSessionID
        let duration = sessionDuration
        let finalizedTranscript = transcriptItems.filter { !$0.isPartial }
        let turnCount = finalizedTranscript.count
        let engine = voiceEngine

        // End Live Activity
        liveActivity.endActivity()

        await voiceService.endSession()
        applySnapshot(voiceService.snapshot)

        // Publish completed session for injection
        if let sessionId, turnCount > 0 {
            lastCompletedSession = CompletedVoiceSession(
                voiceSessionId: sessionId,
                duration: duration,
                turnCount: turnCount,
                transcript: finalizedTranscript,
                engine: engine
            )
        }
    }

    func toggleMute() async {
        await voiceService.toggleMute()
        applySnapshot(voiceService.snapshot)
    }

    /// Manually interrupt assistant speech (e.g., from a stop button).
    /// Unlike VAD-triggered interruption, this sends cancel + clear + truncate.
    func interruptAssistant() {
        voiceService.manuallyInterruptAssistantOutput()
        applySnapshot(voiceService.snapshot)
    }

    /// Send an image to the Realtime model during an active voice session.
    @discardableResult
    func sendImage(_ imageData: Data, triggerResponse: Bool = true) -> Bool {
        guard isSessionActive else { return false }
        return voiceService.sendImage(imageData, mimeType: "image/jpeg", triggerResponse: triggerResponse)
    }

    func endSessionIfNeeded() async {
        // #139: revoke first, THEN decide whether there is a live session to
        // tear down — an in-flight connect is not `isSessionActive` yet, and it
        // is the one that must not survive this call.
        sessionGeneration &+= 1
        guard isSessionActive else { return }
        await endSession()
    }

    func clearLastCompletedSession() {
        lastCompletedSession = nil
    }

    func reset() {
        // #415: a reset store keeps no watch. Same reasoning as `endSession`
        // — the watch belongs to a session, and this one no longer has one.
        coverWatchTask?.cancel()
        coverWatchTask = nil
        isWaitingForUnlock = false
        voiceState = .idle
        connectionState = .idle
        transcriptItems = []
        sessionDuration = 0
        isMuted = false
        isSessionActive = false
        isStartingSession = false
        blockedReason = nil
        statusMessage = nil
        canStartSession = true
        latencyMetrics = TalkLatencyMetrics()
        voiceSessionID = nil
        readiness = TalkReadinessInfo()
        // #180 lane 180-L: reset returns this to UNKNOWN, not to the
        // historical engine — a reset store has not selected anything.
        voiceEngine = nil
        micHealthHint = nil
        audioRouteSummary = nil
        lastCompletedSession = nil
    }

    private func subscribeToEvents() {
        eventTask?.cancel()
        let stream = voiceService.events()
        eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .snapshot(let snapshot):
                    self.applySnapshot(snapshot)
                }
            }
        }
    }

    private func applySnapshot(_ snapshot: TalkSessionSnapshot) {
        voiceState = snapshot.voiceState
        connectionState = snapshot.connectionState
        transcriptItems = snapshot.transcriptItems
        sessionDuration = snapshot.sessionDuration
        isMuted = snapshot.isMuted
        blockedReason = snapshot.blockedReason
        // #302: a start parked behind the lock keeps saying so. Every other
        // field still adopts the snapshot — the engine's view of itself is
        // not wrong, it simply has nothing to say about why we are not
        // asking it yet.
        statusMessage = isWaitingForUnlock ? Self.lockedWaitingMessage : snapshot.statusMessage
        canStartSession = snapshot.canStartSession
        latencyMetrics = snapshot.latencyMetrics
        voiceSessionID = snapshot.voiceSessionID
        readiness = snapshot.readiness
        voiceEngine = snapshot.engine
        micHealthHint = snapshot.micHealthHint
        audioRouteSummary = snapshot.audioRouteSummary
        isSessionActive = connectionState == .connecting || connectionState == .connected

        // Update Live Activity on voice state changes
        if isSessionActive {
            let status: String
            switch snapshot.voiceState {
            case .listening: status = "Listening"
            case .thinking:  status = snapshot.statusMessage ?? "Thinking..."
            case .speaking:  status = "Speaking"
            default:         status = snapshot.statusMessage ?? "Connected"
            }
            // Extract tool name from status message if it mentions a tool
            let toolName = snapshot.statusMessage?.contains("working") == true
                ? snapshot.statusMessage : nil
            liveActivity.updateVoiceState(status, toolName: toolName)
        }

        onSessionStateChanged?()
    }
}
