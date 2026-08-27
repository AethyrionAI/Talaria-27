import Foundation
import Testing
@testable import Talaria

/// **#415 — the App Lock cover arming MID-FLIGHT.** Bars 415-A and 415-B,
/// pre-registered in `OPEN_ITEMS.md` before this file existed.
///
/// **What was measured on device (build 3108, 2026-08-26,
/// `whoGoesThere-415.logarchive`), and what these bars defend against:** a
/// Control Center tap on a WARM process runs its intent in the app process
/// during the `background → inactive` window that PRECEDES the transition
/// where App Lock computes `cover == .locked`. The gate was measurably open
/// for **1.2 s** after the tap and the start cleared it in **23–25 ms**, so
/// the cover came down on top of an in-flight start. The microphone went hot
/// **272 ms** and **2.4 s AFTER `locked=true`** and stayed hot for 27.4 s and
/// 13.4 s across two consecutive launches — a full realtime conversation
/// under an opaque cover, with no voice UI on screen.
///
/// **This is #302's own headline ordering surviving #302's fix.**
/// `TalkStore.deferUntilUnlocked` samples `AppLockGate.isLocked` exactly once,
/// at the instant of start, and never re-checks; bars 302-D…G every one place
/// the lock BEFORE the start (302-E's evidence shape is literally "gate locked
/// ⇒ start count stays 0"). Not one of them scores "gate open at start, lock
/// arms mid-flight" — which is why the gate is real and the race was not
/// covered.
///
/// **The park semantics here are #302's, extended rather than invented.** A
/// session that becomes covered is treated exactly as a start that arrived one
/// second later would have been: capture stops, the store parks on the same
/// `isWaitingForUnlock` + `lockedWaitingMessage` state, and on unlock it
/// resumes exactly once — unless it was abandoned while parked, which is
/// 302-F's rule arriving through the new door.
@MainActor
struct AppLockMidFlightCoverTests {

    // MARK: - Harness

    /// Bounded settle, borrowed from `AppLockGateTests` deliberately: a bar
    /// that FAILS by hanging the suite reports nothing at all, and this
    /// project has already lost 47 minutes once to a test that stalled
    /// instead of failing. Nothing in this file ever awaits a `Task.value`
    /// that a mutation could strand.
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

    /// Lets pending work run where the assertion is that something did NOT
    /// happen, so there is no positive edge to wait for.
    private func quiesce(ticks: Int = 200) async {
        for _ in 0..<ticks { await Task.yield() }
    }

    private final class StubAuthenticator: AppLockAuthenticating {
        var stubbedCapability: AppLockCapability = .faceID
        var nextResult = false
        func capability() -> AppLockCapability { stubbedCapability }
        func authenticate(reason: String) async -> Bool { nextResult }
    }

    /// A voice service that can be **suspended inside `startSession()`** —
    /// which is the whole point, because the defect lives in that window.
    ///
    /// `isCapturing` is the stand-in for the capture chain: true from the
    /// moment a start completes until an end runs. The device evidence for
    /// it is `Starting/Stopping AURemoteIO`; here it is a flag, so the bar
    /// can ask "was the mic up while the cover was down?" without an audio
    /// engine.
    private final class GatedVoiceService: VoiceSessionServiceProtocol {
        private(set) var startCallCount = 0
        private(set) var endCallCount = 0
        /// True between a completed start and the next end.
        private(set) var isCapturing = false
        /// Set while `startSession()` is parked on `holdStart`.
        private(set) var isStartSuspended = false

        /// When true, `startSession()` suspends until `releaseStart()`. This
        /// is the in-flight window the cover arms in.
        var holdStart = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []

        func releaseStart() {
            let waiting = startWaiters
            startWaiters.removeAll()
            for continuation in waiting { continuation.resume() }
        }

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

        func startSession() async {
            startCallCount += 1
            if holdStart {
                isStartSuspended = true
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    startWaiters.append(continuation)
                }
                isStartSuspended = false
            }
            isCapturing = true
            connectionState = .connected
            voiceState = .listening
        }

        func endSession() async {
            endCallCount += 1
            isCapturing = false
            connectionState = .idle
            voiceState = .idle
        }

        func toggleMute() async {}
        func manuallyInterruptAssistantOutput() {}
        @discardableResult
        func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool { false }
    }

    // MARK: - 415-A-1 — the cover arms while the start is IN FLIGHT

    /// **The measured ordering, and the bar that discriminates this defect
    /// from #302's fixed one.** Gate OPEN at start (a warm Control Center
    /// tap), cover arms 23 ms–1.2 s later while `startSession()` has not yet
    /// returned. The capture chain must not survive that, and the start must
    /// park exactly as a pre-start lock would have.
    ///
    /// Witnessed RED on the unmodified tree before the fix existed: at HEAD
    /// the lock arming does nothing at all, the held start returns, and the
    /// store adopts a live session under the cover.
    @Test func aCoverArmingDuringAnInFlightStartParksItAndStopsCapture() async {
        let gate = AppLockGate(isLocked: false)
        let voice = GatedVoiceService()
        voice.holdStart = true
        let store = TalkStore(voiceService: voice, appLockGate: gate)
        let finished = Flag()

        // The Control Center door — the one the device reproduction came
        // through, and the one #302's own bars scored while locked.
        let start = Task { @MainActor in
            await store.startSessionDirectly()
            finished.value = true
        }
        #expect(await settle(until: { voice.isStartSuspended }))
        #expect(voice.startCallCount == 1)
        #expect(!gate.isLocked, "the gate was OPEN when this start cleared it — that is the whole premise")

        // The cover comes down ON TOP of the in-flight start.
        gate.setLocked(true)

        #expect(
            await settle(until: { !voice.isCapturing && voice.endCallCount >= 1 }),
            "the cover armed mid-start: capture must be stopped, not left to come up underneath it"
        )
        #expect(await settle(until: { store.isWaitingForUnlock }))
        #expect(store.statusMessage == TalkStore.lockedWaitingMessage)

        // The held start returns AFTER the cover armed — the 272 ms / 2.4 s
        // window in the device log. It must not land live.
        voice.holdStart = false
        voice.releaseStart()
        await quiesce()
        #expect(!voice.isCapturing, "a start that resolves under the cover must not open the microphone")
        #expect(!store.isSessionActive)

        // Unlock resumes the session the user actually asked for — the same
        // contract a pre-start park honours (#302-C).
        gate.setLocked(false)
        #expect(
            await settle(until: { voice.startCallCount == 2 }),
            "on unlock the parked session resumes"
        )
        await quiesce()
        #expect(voice.startCallCount == 2, "exactly once — a resume that fires twice opens two microphones")
        #expect(!store.isWaitingForUnlock)
        #expect(await settle(until: { finished.value }))
    }

    // MARK: - 415-A-2 — the cover arms while the session is ACTIVE

    /// The defensive ordering, scored SEPARATELY because a fix that only
    /// re-checks after `startSession()` returns closes the measured half and
    /// leaves this one open. Same rule as 302-E's two doors.
    ///
    /// Driven through `startSession()` (the overlay door) so both doors are
    /// covered across 415-A.
    @Test func aCoverArmingOverALiveSessionStopsCaptureAndParksIt() async {
        let gate = AppLockGate(isLocked: false)
        let voice = GatedVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        await store.startSession()
        #expect(voice.startCallCount == 1)
        #expect(voice.isCapturing)
        #expect(store.isSessionActive)

        gate.setLocked(true)
        #expect(
            await settle(until: { !voice.isCapturing }),
            "a live session does not get to keep the microphone when the cover comes down"
        )
        #expect(voice.endCallCount >= 1)
        #expect(await settle(until: { store.isWaitingForUnlock }))
        #expect(store.statusMessage == TalkStore.lockedWaitingMessage)

        gate.setLocked(false)
        #expect(await settle(until: { voice.startCallCount == 2 }))
        await quiesce()
        #expect(voice.startCallCount == 2, "exactly once")
        #expect(!store.isWaitingForUnlock)
    }

    // MARK: - 415-A-3 — abandoned while parked on the cover

    /// #139's defect arriving through the new door: park a covered session,
    /// let the user dismiss it (or #254's background observer revoke it), and
    /// a naive resume opens a microphone for a session nobody is in.
    ///
    /// The park half of this bar is RED at HEAD (nothing parks). The
    /// no-resume half is green at HEAD **by construction** — HEAD has no
    /// resume to suppress — and is proven by its own mutation instead:
    /// dropping the post-unlock generation re-check turns exactly this test
    /// red and leaves the other two green. That is 302-F's shape, and 302-F
    /// is the bar that earned its place.
    @Test func aSessionAbandonedWhileParkedOnTheCoverNeverResumes() async {
        let gate = AppLockGate(isLocked: false)
        let voice = GatedVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        await store.startSessionDirectly()
        #expect(voice.startCallCount == 1)
        #expect(voice.isCapturing)

        gate.setLocked(true)
        #expect(await settle(until: { !voice.isCapturing }))
        #expect(await settle(until: { store.isWaitingForUnlock }))

        // The user dismissed the overlay, or the app backgrounded and #254's
        // observer revoked the session, while it sat parked behind the cover.
        await store.abandonSession()

        gate.setLocked(false)
        await quiesce()
        #expect(
            voice.startCallCount == 1,
            "the session was abandoned while parked — resuming into a start opens a microphone for nobody (#139)"
        )
        #expect(!store.isWaitingForUnlock)
    }

    /// **The arm that isolates the post-unlock generation re-check**, and it
    /// took a second look to find one that does.
    ///
    /// `abandonSession()` above revokes through `endSession()`, which also
    /// CANCELS the cover watch — so two belts defend that path and the
    /// generation mutation would not show. `endSessionIfNeeded()` is the
    /// honest isolator: while parked the session is not active, so it bumps
    /// the generation and returns without ending anything and without
    /// touching the watch. Only the post-unlock re-read stands between that
    /// and a microphone opened for nobody.
    @Test func aParkedSessionSupersededWithoutCancellationNeverResumes() async {
        let gate = AppLockGate(isLocked: false)
        let voice = GatedVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        await store.startSessionDirectly()
        gate.setLocked(true)
        #expect(await settle(until: { store.isWaitingForUnlock }))
        #expect(!voice.isCapturing)

        // Dismissal through the door that does NOT tear down (the session is
        // not active while parked) — the generation bump is all it leaves.
        await store.endSessionIfNeeded()

        gate.setLocked(false)
        await quiesce()
        #expect(
            voice.startCallCount == 1,
            "the parked start was superseded — only the post-unlock generation re-read stops it resuming (#139)"
        )
    }

    // MARK: - 415-A hygiene — the watch must not outlive its session

    /// A cover watch that survives the session it was armed for is a stranded
    /// waiter: the next lock would park — and then RESUME — a session the
    /// user ended minutes ago. Green at HEAD by construction (there is no
    /// watch), and a tripwire from the fix forward.
    @Test func aCoverArmingAfterTheSessionEndedParksNothing() async {
        let gate = AppLockGate(isLocked: false)
        let voice = GatedVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        await store.startSession()
        await store.endSession()
        let endsAfterTeardown = voice.endCallCount

        gate.setLocked(true)
        await quiesce()
        #expect(voice.endCallCount == endsAfterTeardown, "there is nothing left to tear down")
        #expect(!store.isWaitingForUnlock, "an ended session must not park")

        gate.setLocked(false)
        await quiesce()
        #expect(voice.startCallCount == 1, "and it must never resume one either")
    }

    /// The same hygiene, measured on the gate rather than inferred from
    /// behaviour — and it pins the other half of the decision: a cover watch
    /// is NOT an unlock waiter, so #302's `parkedWaiterCount` bars still mean
    /// exactly what they meant before this lane.
    @Test func theCoverWatchIsReleasedWithItsSession() async {
        let gate = AppLockGate(isLocked: false)
        let voice = GatedVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)

        await store.startSession()
        #expect(await settle(until: { gate.armedCoverWatchCount == 1 }), "a running session arms exactly one watch")
        #expect(gate.parkedWaiterCount == 0, "a cover watch is not a parked caller — 302-E and 302-G score that number")

        await store.endSession()
        #expect(
            await settle(until: { gate.armedCoverWatchCount == 0 }),
            "a watch that outlives its session is a stranded waiter"
        )
    }

    // MARK: - 415-B — App Lock OFF is a NO-OP on the mid-flight path

    /// The negative control, and the bar that makes 415-A mean anything:
    /// **without it, 415-A is satisfied by a build that never starts voice,
    /// or by one that parks every session forever** — an availability defect
    /// traded for a privacy one.
    ///
    /// Driven through a real `AppLockController` with the feature OFF, across
    /// the `background → active` transition that arms the lock when it is on.
    @Test func appLockOffIsANoOpOnALiveVoiceSession() async {
        let gate = AppLockGate()
        let controller = AppLockController(
            configuration: { AppLockConfiguration(isEnabled: false, gracePeriod: .immediate) },
            authenticator: StubAuthenticator(),
            now: { Date(timeIntervalSince1970: 2_000_000) },
            gate: gate
        )
        #expect(controller.cover == .none)
        #expect(!gate.isLocked)

        let voice = GatedVoiceService()
        let store = TalkStore(voiceService: voice, appLockGate: gate)
        await store.startSession()
        #expect(voice.startCallCount == 1)
        #expect(voice.isCapturing)

        // The exact transition that arms the lock when the feature is ON.
        controller.scenePhaseChanged(to: .background)
        controller.scenePhaseChanged(to: .active)
        await quiesce()

        #expect(!gate.isLocked)
        #expect(voice.isCapturing, "App Lock is OFF — nothing may stop this session")
        #expect(voice.endCallCount == 0)
        #expect(!store.isWaitingForUnlock)
        #expect(voice.startCallCount == 1, "and nothing may restart it either")
    }

    /// A store with NO gate in its graph — previews, tests, and any wiring
    /// that predates this lane — is untouched by the cover watch.
    @Test func noGateWiredMeansNoCoverWatchAtAll() async {
        let voice = GatedVoiceService()
        let store = TalkStore(voiceService: voice)

        await store.startSession()
        #expect(voice.startCallCount == 1)
        #expect(voice.isCapturing)
        #expect(voice.endCallCount == 0)
        #expect(!store.isWaitingForUnlock)
    }

    // MARK: - 415-C — the capture instrument reads BOTH engines

    /// **The realtime engine grows the `#302-A` capture instrument.**
    ///
    /// The device forensics could not answer "was the mic hot?" from the
    /// app's own log on the realtime engine, because the `#302-A` lines
    /// existed only in `NativeVoicePipelineService` — so #415 had to fall
    /// back to framework CoreAudio `Df` rows a later `log collect` may not
    /// retain, and #302's 2026-08-20 device pass scored the one engine that
    /// carried the instrument.
    ///
    /// A log line has no return value, so this bar is **structural** and says
    /// so: the same three phrases, the same `(#302-A)` marker, at `.notice`
    /// with `privacy: .public`, in BOTH engine files — which is what makes a
    /// single Console predicate read both forever after. The pattern (and the
    /// "fails loudly if the source cannot be read" stance) is
    /// `SpeakerRouteOverrideTests`', over the very same file.
    @Test func bothVoiceEnginesCarryTheCaptureInstrument() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root

        for engine in ["NativeVoicePipelineService", "LiveVoiceSessionService"] {
            let url = root.appendingPathComponent("Talaria/Services/Live/\(engine).swift")
            let source = try #require(
                try? String(contentsOf: url, encoding: .utf8),
                "cannot read \(engine).swift — this check did not run"
            )
            for phrase in [
                "audio session activated for capture (#302-A)",
                "capture chain HOT",
                "capture chain COLD"
            ] {
                #expect(
                    source.contains(phrase),
                    "\(engine) lost the #302-A instrument line \"\(phrase)\" — one predicate must read both engines"
                )
            }
            #expect(
                source.components(separatedBy: "(#302-A)").count - 1 >= 3,
                "\(engine): all three instrument lines carry the #302-A marker, or the Console predicate misses one"
            )
        }
    }

    /// The park itself is announced, so 415-D can be scored from the app's
    /// own log instead of framework rows. Same reasoning as the engine lines:
    /// always-on `.notice`, `privacy: .public`, marker in the text.
    @Test func theMidFlightParkAnnouncesItself() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Stores/TalkStore.swift")
        let source = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "cannot read TalkStore.swift — this check did not run"
        )
        #expect(source.contains("voice session parked — App Lock cover armed mid-flight (#415)"))
        #expect(source.contains("(#415)"))
    }
}

@MainActor private final class Flag { var value = false }
