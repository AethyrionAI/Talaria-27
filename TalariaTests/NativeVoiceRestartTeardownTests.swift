@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import Talaria

/// #428 — the restart-vs-teardown bars (428-A and 428-C).
///
/// **The defect.** `restartCapture()` rebuilds the capture stack on a route
/// change. `teardownSessionResources()` tears it down. Nothing joined them:
/// teardown cancelled `captureTask` and called `capture.stop()`, then returned
/// — while a restart parked inside `capture.start(muted:)` went on to build a
/// live capture chain on the far side of a finished shutdown, and then painted
/// `.failed` + "Audio capture could not resume." over an already-idle session.
///
/// **The fix under test, in three parts.**
/// 1. `teardownSessionResources()` STOPS FIRST: it cancels the in-flight
///    restart and JOINS it — bounded at 3 s (Owen's decision 1), never with
///    `Task.value` (a non-throwing `Task.value` cannot be timeout-raced).
/// 2. The restart itself respects the ending session: guards after
///    `capture.stop()`, a belt after `beginCapture()` returns, and a guard in
///    front of the `.failed` paint.
/// 3. A start abandoned by the capture generation (Task 2's ticket) throws
///    `CaptureError.superseded`, and the restart catches it TYPED and SILENT —
///    a bare catch would paint a failure banner over a restart that was
///    correctly abandoned.
///
/// **Why the fixture cannot use `startSession()`.** #428 Task 0(b) probe 1
/// measured it PARKING indefinitely inside `SFSpeechRecognizer
/// .requestAuthorization` in 4 of 5 simulator runs — there is no
/// `simctl privacy` service for speech recognition and `grant all` does not
/// stand in for one — and in the single run that returned it landed on
/// `.failed`, never `.connected`. Every test here reaches `.connected` through
/// the `// harness-visible` `beginConnectedCaptureForHarness()` door instead.
///
/// **Why the 800 ms wait before every posted route change is required, not
/// decorative.** `beginCapture()` arms `isConfiguringAudioSession` and holds it
/// for the 750 ms `audioSessionConfigurationCooldown`; `handleRouteChange`
/// guards on that flag. Task 0(b) probe 3-B proved the gate swallows a post
/// silently while it is closed. Without the wait these tests would be vacuous
/// rather than red, which is why each one also asserts that the fixture reached
/// its parked start before believing anything below it.
///
/// `.serialized`: `registerAudioSessionObservers()` runs in `init` on
/// `NotificationCenter.default` and the observers are never removed, so a
/// posted route change reaches EVERY live `NativeVoicePipelineService` in the
/// process. One service per test, ended before the test returns, and no two
/// tests in flight at once. (The one other suite that posted route changes,
/// `NativeVoiceCaptureProbeTests`, was Task 0's temporary scaffolding and was
/// deleted in Task 4 — so this suite is now the only poster in the process.
/// Run it alone anyway when it is the evidence: `.serialized` orders tests
/// WITHIN a suite, not across suites, and any future poster reintroduces the
/// hazard silently.)
@Suite("428-A/C restart vs teardown", .serialized)
@MainActor
struct NativeVoiceRestartTeardownTests {

    // MARK: - Fixture

    /// A capture whose Nth `start` PARKS until the test releases it, recording
    /// every call in order.
    ///
    /// Polling, not a `CheckedContinuation` — the
    /// `TalkStoreBackgroundRevokeTests.ParkedStartVoiceService` rule: a
    /// stranded continuation hangs the whole suite with no message.
    ///
    /// **The park has to survive CANCELLATION, and that is not incidental.**
    /// `joinRestart` cancels the restart task, and this `start` runs inside it —
    /// so a bare `try? await Task.sleep` would throw instantly, spin the loop to
    /// its end and release the fixture as a side effect of the very fix under
    /// test. A detached child's non-throwing `value` is not cancellable, so the
    /// park holds until the TEST releases it (or its own 400-tick bound
    /// expires). Each tick is 10 ms, so nothing can strand.
    actor FakeCapture: NativeVoiceCapturing {
        /// What the parked start does when it is finally let go.
        enum ParkedOutcome: Sendable {
            /// Returns a stream, as a healthy restart would.
            case returnsStream
            /// Throws the capture generation's abandonment signal (bar 428-C).
            case throwsSuperseded
            /// Throws an ordinary device failure — the arm that isolates the
            /// `isEndingSession` guard in front of the `.failed` paint.
            case throwsGeneric
        }

        struct GenericCaptureFailure: Error {}

        private(set) var calls: [String] = []
        /// True from the moment the Nth `start` enters its park until it leaves.
        private(set) var isParked = false
        /// #436: every origin this fake was stopped with, in order. `calls`
        /// deliberately still records a bare `"stop"` — the 428 ledger
        /// assertions are pinned to those exact strings, and an origin baked
        /// into them would have made a #436 change read as a #428 regression.
        private(set) var stopOrigins: [CaptureStopOrigin] = []
        /// #436: mirrors the REAL controller's `lastStopOrigin` — same
        /// last-writer-wins rule, same fail-safe initial value — so a
        /// `.throwsSuperseded` park throws the origin production would have
        /// thrown rather than one the test chose. `NativeVoiceCaptureGeneration
        /// Tests` is what proves that mirror is faithful.
        private(set) var lastStopOrigin: CaptureStopOrigin = .bareStop

        private let parkOnStart: Int
        private let parkedOutcome: ParkedOutcome
        /// #436: the Nth start fails outright (no park). Drives the repair's
        /// honest-end arm — the re-arm attempt that cannot get a chain back.
        private let failOnStart: Int?
        private var released = false
        private var startCount = 0

        init(
            parkOnStart: Int,
            parkedOutcome: ParkedOutcome = .returnsStream,
            failOnStart: Int? = nil
        ) {
            self.parkOnStart = parkOnStart
            self.parkedOutcome = parkedOutcome
            self.failOnStart = failOnStart
        }

        func release() { released = true }

        // MARK: NativeVoiceCapturing

        func isTranscriptionSupported() async -> Bool { true }

        func setMuted(_ muted: Bool) {}

        func start(muted: Bool) async throws -> AsyncStream<NativeVoiceCaptureEvent> {
            calls.append("start")
            startCount += 1
            if startCount == failOnStart {
                calls.append("start-threw")
                throw GenericCaptureFailure()
            }
            if startCount == parkOnStart {
                isParked = true
                // Bounded: 400 × 10 ms ≈ 4 s, then it gives up rather than
                // parking forever.
                for _ in 0..<400 where !released { await Self.cancellationImmuneTick() }
                isParked = false
                switch parkedOutcome {
                case .returnsStream:
                    break
                case .throwsSuperseded:
                    calls.append("start-threw")
                    // #436: the origin is READ AT THROW TIME, from whatever
                    // stop last ran — not chosen by the test. That is the
                    // controller's own rule, and it is what lets the 428 rows
                    // keep asserting exactly what they asserted before while
                    // getting a truthful origin for free.
                    throw NativeVoiceCaptureController.CaptureError.superseded(
                        point: "assembled",
                        origin: lastStopOrigin
                    )
                case .throwsGeneric:
                    calls.append("start-threw")
                    throw GenericCaptureFailure()
                }
            }
            calls.append("start-returned")
            return AsyncStream { _ in }
        }

        func stop(origin: CaptureStopOrigin) {
            calls.append("stop")
            stopOrigins.append(origin)
            lastStopOrigin = origin
        }

        /// A 10 ms suspension that a cancelled parent cannot collapse.
        private static func cancellationImmuneTick() async {
            await Task.detached { try? await Task.sleep(for: .milliseconds(10)) }.value
        }
    }

    // MARK: - Drivers

    private func connectedService(_ capture: FakeCapture) async throws -> NativeVoicePipelineService {
        let speech = SpeechOutputService()
        speech.managesAudioSession = false
        let service = NativeVoicePipelineService(
            backendProvider: { nil },
            speechOutput: speech,
            capture: capture
        )
        try await service.beginConnectedCaptureForHarness()
        return service
    }

    private func postRouteChange() {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
            ]
        )
    }

    /// Waits past the configuration cooldown, posts a route change, and reports
    /// whether the restart actually reached the fake's parked start. A restart
    /// that never parked makes every assertion after it vacuous.
    private func driveToParkedRestart(_ capture: FakeCapture) async -> Bool {
        try? await Task.sleep(for: .milliseconds(800))
        postRouteChange()
        return await waitUntil(3.0) { await capture.isParked }
    }

    private func waitUntil(_ seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    // MARK: - 428-A: teardown cancels AND joins

    /// The whole bar in one ledger: teardown must not finish while a restart is
    /// still parked inside `capture.start`, and the LAST word must be a `stop`
    /// that runs after the abandoned start returned.
    @Test func endSessionJoinsAParkedRestartAndTheLastWordIsStop() async throws {
        let capture = FakeCapture(parkOnStart: 2)
        let service = try await connectedService(capture)
        #expect(service.connectionState == .connected, "the harness door must reach .connected")

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        let ended = Task { @MainActor in
            await service.endSession()
            return ContinuousClock.now
        }
        try? await Task.sleep(for: .milliseconds(200))
        let releasedAt = ContinuousClock.now
        await capture.release()
        let endedAt = await ended.value

        #expect(endedAt > releasedAt,
                "teardown must JOIN the in-flight restart — endSession returned while the start was still parked")

        let calls = await capture.calls
        // start / start-returned  : the harness door's connect
        // stop / start            : the restart tears down, then parks
        // start-returned          : the park released
        // stop                    : beginCapture's belt hands the stack straight
        //                           back, because the session is ending
        // stop                    : teardown's own stop, AFTER the join
        #expect(
            calls == ["start", "start-returned", "stop", "start", "start-returned", "stop", "stop"],
            "the abandoned start must be followed by a stop, not left owning a live capture: \(calls)"
        )
        #expect(calls.last == "stop", "teardown's stop must be the last word: \(calls)")
        #expect(service.connectionState == .idle)
        #expect(service.voiceState == .idle)
    }

    // MARK: - 428-C: a superseded restart is silent

    /// The brief's 428-C arm. **Defended in depth on purpose** — the join, the
    /// `isEndingSession` guard and the typed `.superseded` catch each suffice on
    /// their own, so this test cannot isolate any one of them. The two arms
    /// below do that; this one pins the user-visible promise.
    @Test func aSupersededRestartNeverRepaintsAnEndedSession() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsSuperseded)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        let ended = Task { @MainActor in await service.endSession() }
        try? await Task.sleep(for: .milliseconds(200))
        await capture.release()
        await ended.value

        let threw = await waitUntil(3.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the parked start never threw .superseded — nothing below is evidence")
        // Give a straggler every chance to repaint before believing it did not.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(service.blockedReason == nil)
        #expect(service.statusMessage != "Audio capture could not resume.",
                "a correctly abandoned restart must not raise a device-failure banner")
        #expect(service.connectionState == .idle)
        #expect(service.voiceState == .idle)
    }

    /// Isolates the TYPED `.superseded` catch. The supersession here comes from
    /// a newer start rather than a teardown (Task 2 §9.1: a second `start`'s own
    /// leading `stop()` bumps the generation too), so `isEndingSession` is false
    /// and the typed catch is the only thing standing between a correctly
    /// abandoned restart and a `.failed` banner on a LIVE session.
    @Test func aSupersededRestartIsSilentWhenNoSessionIsEnding() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsSuperseded)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        await capture.release()
        let threw = await waitUntil(3.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the parked start never threw .superseded — nothing below is evidence")
        try? await Task.sleep(for: .milliseconds(200))

        #expect(service.connectionState == .connected,
                "a superseded restart must not take a live session down")
        #expect(service.voiceState == .listening)
        #expect(service.statusMessage != "Audio capture could not resume.")
        #expect(service.blockedReason == nil)

        await service.endSession()
    }

    /// Isolates the `guard !isEndingSession` in front of the `.failed` paint,
    /// and witnesses the 3 s join bound at the same time.
    ///
    /// The fake is never released, so its park outlives the bound: teardown
    /// waits ~3 s, logs the straggler notice, and proceeds. The straggler then
    /// resumes on the far side of a finished shutdown and throws an ORDINARY
    /// device error — which reaches the generic catch, where only that guard
    /// stops it repainting an idle session.
    @Test func aStragglerPastTheJoinBoundNeverRepaintsAnEndedSession() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsGeneric)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        let endRequestedAt = ContinuousClock.now
        await service.endSession()
        let joinElapsed = ContinuousClock.now - endRequestedAt

        #expect(joinElapsed > .seconds(2.5),
                "teardown must actually WAIT for the in-flight restart, not sail past it: \(joinElapsed)")
        #expect(joinElapsed < .seconds(4.5),
                "the wait the user feels is BOUNDED at 3 s (#428 decision 1): \(joinElapsed)")
        #expect(service.connectionState == .idle)

        let threw = await waitUntil(8.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the straggler never resumed — nothing below is evidence")
        try? await Task.sleep(for: .milliseconds(300))

        #expect(service.connectionState == .idle,
                "a straggler resuming after teardown must not repaint an ended session")
        #expect(service.voiceState == .idle)
        #expect(service.statusMessage == nil)
        #expect(service.blockedReason == nil)
    }

    // MARK: - Critical 1: the join yields to a cancelled caller

    /// **The join's poll is reachable under caller cancellation, and it is on
    /// the MainActor.** `endSession()` is called from stored, cancellable
    /// tasks: `TalkStore.coverWatchTask` (`TalkStore.swift:238-244`) runs
    /// `coverArmedMidFlight` → `discardAbandonedStart()` →
    /// `voiceService.endSession()`, and that task is cancelled by
    /// `beginCoverWatch`, `TalkStore.endSession()`, `abandonSession()` and
    /// `reset()`. `VoiceOverlayScreen`'s `.task` is a weaker second path
    /// (SwiftUI auto-cancels it on disappear).
    ///
    /// A cancelled `Task.sleep` throws IMMEDIATELY and `joinRestart`'s `try?`
    /// swallows it — so without the `if Task.isCancelled { break }` the loop
    /// stops sleeping and starts spinning at executor rate for the whole 3 s
    /// bound, on the actor that draws the UI. This test drives exactly that
    /// chain: the phone-lock cover park's `endSession()` arriving as a task
    /// someone then cancels, with a restart still parked.
    ///
    /// The bar is the ELAPSED time after the cancel, because the outcome is
    /// correct either way — the busy-wait is invisible to state assertions.
    @Test func aCancelledCallerDoesNotBusyWaitOutTheJoinBound() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsGeneric)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        // Never released: the restart is genuinely still in flight, so the join
        // is inside its poll rather than past it.
        let ended = Task { @MainActor in
            await service.endSession()
            return ContinuousClock.now
        }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await capture.isParked, "the start left its park before the cancel — the join was not polling")

        let cancelledAt = ContinuousClock.now
        ended.cancel()
        let endedAt = await ended.value
        let afterCancel = endedAt - cancelledAt

        #expect(
            afterCancel < .seconds(1),
            "a cancelled caller must leave the join at once, not spin the MainActor out to the 3 s bound: \(afterCancel)"
        )
        #expect(service.connectionState == .idle, "the shutdown must still complete")
        #expect(service.voiceState == .idle)

        // The straggler resumes ~4 s later and must find an ended session it
        // cannot repaint — the same cover the bound-elapsed exit relies on.
        let threw = await waitUntil(8.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the straggler never resumed — the arm below is not evidence")
        try? await Task.sleep(for: .milliseconds(300))
        #expect(service.connectionState == .idle)
        #expect(service.statusMessage == nil)
    }

    // MARK: - Critical 2: a superseded INITIAL connect is silent too

    /// The other lifecycle. #415's cover park (and a plain End) can land while
    /// the INITIAL connect is suspended inside `assemble`: teardown's
    /// `capture.stop()` bumps the capture generation, the resumed start throws
    /// `.superseded`, and before this fix `startSession()`'s catch painted
    /// `.failed` + `blockedReason` + "Local voice couldn't start: Voice
    /// capture start was superseded by a session teardown." — an internal
    /// mechanism sentence on a user surface, on a designed-correct shutdown.
    /// Each of those `didSet`s publishes a snapshot `TalkStore` adopts.
    ///
    /// Driven through `connectSessionForHarness()` because `startSession()`
    /// parks on the speech TCC prompt in this test host (Task 0(b) probe 1).
    /// The door adds no copy of the catch — it calls the same
    /// `connectSession()` production method `startSession()` calls.
    @Test func aSupersededInitialConnectNeverPaintsAFailure() async throws {
        let capture = FakeCapture(parkOnStart: 1, parkedOutcome: .throwsSuperseded)
        let speech = SpeechOutputService()
        speech.managesAudioSession = false
        let service = NativeVoicePipelineService(
            backendProvider: { nil },
            speechOutput: speech,
            capture: capture
        )

        let connect = Task { @MainActor in await service.connectSessionForHarness() }
        let parked = await waitUntil(3.0) { await capture.isParked }
        #expect(parked, "the initial connect never parked — nothing below is evidence")

        await service.endSession()
        await capture.release()
        let threw = await waitUntil(3.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the parked start never threw .superseded — nothing below is evidence")
        await connect.value
        // Give the resumed catch every chance to paint before believing it did not.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(service.blockedReason == nil,
                "a superseded initial connect must not leave a blocked reason: \(String(describing: service.blockedReason))")
        #expect(service.connectionState == .idle,
                "End left this session idle; the abandoned start must not repaint it .failed")
        #expect(service.voiceState == .idle)
        #expect(service.statusMessage == nil,
                "\(String(describing: service.statusMessage))")
        #expect(
            service.statusMessage?.contains("superseded") != true,
            "an internal mechanism sentence reached a user surface: \(String(describing: service.statusMessage))"
        )
    }

    // MARK: - 436-A (the service half): a stop that wins the race is repaired

    /// **436-A, part 2 of 2 — the bar.** A bare `stop()` on a session that is
    /// still LIVE races the restart's parked start. Before #436 the typed
    /// `.superseded` arm returned silently and the session was left
    /// `.connected` ∧ `.listening` ∧ no capture chain: a HUD that says
    /// "listening" over a dead microphone. The end state must not be that
    /// triple — either a chain is back, or the session says it ended.
    ///
    /// **How "no chain" is read.** The fake's ledger, not a private field.
    /// `captureTask != nil` is NOT an honest reading — `beginCapture()` cancels
    /// the old handle without nilling it, so a failed re-arm leaves a non-nil
    /// dead task. A `start-returned` AFTER the supersession is the service
    /// adopting a stream, which is the chain.
    ///
    /// **The origin is what makes it a bare stop.** `capture.stop(origin:
    /// .bareStop)` here stands in for the production trace's own caller: the
    /// old analyzer's failure path, whose `.failed` event is dropped into a
    /// finished continuation and therefore paints nothing.
    @Test func aBareStopRacingARestartOnALiveSessionReArmsTheChain() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsSuperseded)
        let service = try await connectedService(capture)
        #expect(service.connectionState == .connected, "the harness door must reach .connected")

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        // The race: a stop lands on a LIVE session while the restart's start is
        // still in its startup stretch.
        await capture.stop(origin: .bareStop)
        await capture.release()

        let threw = await waitUntil(3.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the parked start never threw .superseded — nothing below is evidence")
        let reArmed = await waitUntil(3.0) { Self.chainReArmed(await capture.calls) }

        let calls = await capture.calls
        let origins = await capture.stopOrigins
        #expect(origins.last == .bareStop,
                "the fixture did not actually stage a bare stop: \(origins)")
        #expect(
            calls == ["start", "start-returned", "stop", "start", "stop", "start-threw", "start", "start-returned"],
            "the supersession must be followed by exactly ONE re-arm that returns a stream: \(calls)"
        )
        #expect(reArmed, "no chain came back after the supersession: \(calls)")

        // The bar itself, stated as the triple it forbids.
        let strandedListening =
            service.connectionState == .connected
            && service.voiceState == .listening
            && !Self.chainReArmed(calls)
        #expect(
            !strandedListening,
            "a live session was left saying LISTENING with no capture chain (#436): \(calls)"
        )
        #expect(service.statusMessage != "Audio capture could not resume.",
                "a re-arm that SUCCEEDED must not raise a device-failure banner")

        await service.endSession()
    }

    /// The other honest disposition of the same bar. Same race, but the one
    /// re-arm cannot get a chain back (the third `start` fails outright). The
    /// session must then say so — never sit at `.listening` over nothing — and
    /// it must not try again: the bound is ONE attempt, and the ledger is what
    /// proves there was no loop.
    @Test func aBareStopRaceWhoseReArmFailsEndsTheSessionHonestly() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsSuperseded, failOnStart: 3)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        await capture.stop(origin: .bareStop)
        await capture.release()

        let failed = await waitUntil(3.0) { await service.connectionState == .failed }
        let calls = await capture.calls
        #expect(failed, "the failed re-arm left the session unpainted: \(calls)")
        #expect(service.voiceState == .disconnected)
        #expect(service.statusMessage == "Audio capture could not resume.")
        #expect(
            calls == ["start", "start-returned", "stop", "start", "stop", "start-threw", "start", "start-threw"],
            "the re-arm is bounded to ONE attempt — a second start here would be the loop the ruling forbids: \(calls)"
        )
        #expect(service.voiceState != .listening,
                "a session with no capture chain must never read LISTENING (#436)")
    }

    // MARK: - 436-B: the origins that must stay SILENT

    /// **436-B, the bar as written: a TEARDOWN-caused supersession stays
    /// silent, byte-for-byte (#428 ruling 2).** The fake is never released, so
    /// its park outlives the 3 s join bound; teardown proceeds and its own
    /// `capture.stop(origin: .teardown)` is the stop that moves the generation.
    /// The straggler then resumes with a `.teardown` origin and must do exactly
    /// nothing: no re-arm, no paint.
    ///
    /// **This row cannot isolate the origin gate, and saying so is the point.**
    /// On this path `isEndingSession` is true and `connectionState` is `.idle`,
    /// so the repair's belts would refuse it even with the origin check
    /// deleted — the same defence-in-depth shape #428's own 428-C hit. The
    /// isolating row is the LIVE-session one below.
    @Test func aTeardownCausedSupersessionNeitherReArmsNorPaints() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsSuperseded)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        await service.endSession()   // never released: the join waits out its bound

        let threw = await waitUntil(8.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the straggler never resumed — nothing below is evidence")
        // Give a re-arm every chance to happen before believing it did not.
        try? await Task.sleep(for: .milliseconds(400))

        let calls = await capture.calls
        let origins = await capture.stopOrigins
        #expect(origins.last == .teardown,
                "the fixture did not actually stage a teardown-origin supersession: \(origins)")
        #expect(
            !Self.chainReArmed(calls),
            "a teardown-caused supersession must not re-arm — the session is gone (#428 ruling 2): \(calls)"
        )
        #expect(service.connectionState == .idle)
        #expect(service.voiceState == .idle)
        #expect(service.statusMessage == nil)
        #expect(service.blockedReason == nil)
    }

    /// **436-B's isolating row.** A LIVE session, and the supersession came
    /// from a newer start/restart rather than a bare stop — the `.restart`
    /// origin. Re-arming behind a rebuild is the #82 thrash the breaker exists
    /// to stop, so the correct behaviour here is the SAME silence a teardown
    /// gets, for a completely different reason.
    ///
    /// This is the row the "treat every supersession as a bare stop" mutation
    /// reds: every belt in the repair's guard (`isEndingSession`,
    /// `connectionState`) is satisfied here, so the ORIGIN is the only thing
    /// standing between this session and an extra `capture.start`.
    @Test func aRestartCausedSupersessionOnALiveSessionDoesNotReArm() async throws {
        let capture = FakeCapture(parkOnStart: 2, parkedOutcome: .throwsSuperseded)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        // No interleaved stop of our own: the last stop is the restart's own
        // leading one, so the origin the straggler resumes with is `.restart`.
        await capture.release()
        let threw = await waitUntil(3.0) { await capture.calls.contains("start-threw") }
        #expect(threw, "the parked start never threw .superseded — nothing below is evidence")
        try? await Task.sleep(for: .milliseconds(400))

        let calls = await capture.calls
        let origins = await capture.stopOrigins
        #expect(origins.last == .restart,
                "the fixture did not actually stage a restart-origin supersession: \(origins)")
        #expect(
            !Self.chainReArmed(calls),
            "a supersession by a newer start must not be re-armed behind — that is the #82 thrash (#436): \(calls)"
        )
        #expect(service.connectionState == .connected,
                "a superseded restart must not take a live session down")
        #expect(service.voiceState == .listening)
        #expect(service.statusMessage != "Audio capture could not resume.")

        await service.endSession()
    }

    /// The ledger reading of "a capture chain came back": a start that RETURNED
    /// after the supersession. One definition, used by every #436 row, so a
    /// change of mind about what counts cannot leave two rows disagreeing.
    private static func chainReArmed(_ calls: [String]) -> Bool {
        guard let threwAt = calls.firstIndex(of: "start-threw") else { return false }
        return calls[calls.index(after: threwAt)...].contains("start-returned")
    }

    // MARK: - Negative control

    /// Without an `endSession`, the restart is an ordinary restart: it completes
    /// and the session goes back to listening. If this ever reds, the guards
    /// above have stopped discriminating and started refusing.
    @Test func withoutAnEndTheRestartCompletesAndListens() async throws {
        let capture = FakeCapture(parkOnStart: 2)
        let service = try await connectedService(capture)

        let parked = await driveToParkedRestart(capture)
        #expect(parked, "the restart never reached the parked start — nothing below is evidence")

        await capture.release()
        let resumed = await waitUntil(3.0) { await capture.calls.last == "start-returned" }
        #expect(resumed, "the released start never returned — nothing below is evidence")
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await capture.calls == ["start", "start-returned", "stop", "start", "start-returned"],
                "a restart with no teardown must end on start-returned, with no stop after it")
        #expect(service.connectionState == .connected)
        #expect(service.voiceState == .listening)
        #expect(service.statusMessage != "Audio capture could not resume.")
        #expect(service.blockedReason == nil)

        await service.endSession()
    }
}
