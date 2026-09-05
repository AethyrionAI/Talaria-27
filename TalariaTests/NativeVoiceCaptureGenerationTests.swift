@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import Testing
@testable import Talaria

/// #428 — the capture-generation bar (428-B).
///
/// **The defect.** `NativeVoiceCaptureController.start(muted:)` suspends once
/// (Task 1 collapsed four awaits into `SpeechAnalysisAssembling.assemble`), and
/// actor serialization does not survive a suspension: a `stop()` that arrives
/// while a start is parked in `assemble` returns having torn down *nothing the
/// start had not yet built*, and the start then resumes and installs a tap on an
/// engine the session shutdown already finished with.
///
/// **The fix under test.** A monotonic `captureGeneration` ticket: `stop()`
/// bumps it, `start` captures it after its own leading `stop()`, and the resumed
/// start refuses to touch the engine when the two no longer match.
///
/// **Why the two arms differ only in WHICH error they throw.** `CC-lane-*`'s
/// `AVAudioEngine.inputNode` reports 0 Hz before and after voice processing
/// (#428 Task 0(b) probe 2), so `audioEngine.start()` is unreachable on this
/// host and the #82 guard adjacent to the install (check 2) refuses every
/// un-superseded start. `isEngineRunning` is therefore `false` in BOTH arms and
/// proves nothing on its own. The discriminator is the error:
/// `.superseded(point: "assembled")` when a stop interleaved, `.noAudioInput`
/// when it did not — a contrast that needs no working microphone, which is what
/// makes it survivable in the gate.
///
/// `.serialized`: every arm configures the process-wide `AVAudioSession` and
/// drives its own `AVAudioEngine`; running them concurrently would let one arm's
/// session configuration land inside the other's.
@Suite("428-B capture generation", .serialized)
struct NativeVoiceCaptureGenerationTests {

    /// Parks inside `assemble` until the test releases it, so a test can hold a
    /// capture start at its one remaining suspension point.
    ///
    /// Polling, not a `CheckedContinuation`, and deliberately BOUNDED — the
    /// `TalkStoreBackgroundRevokeTests.ParkedStartVoiceService` rule: a
    /// stranded continuation hangs the whole suite with no message, which is
    /// exactly the failure this lane is trying to make visible rather than
    /// suffer.
    ///
    /// The fake also skips the assembler's own #82 format check (check 1),
    /// which is the only reason a start can park at all on a 0 Hz host.
    final class ParkedAssembler: SpeechAnalysisAssembling, @unchecked Sendable {
        private let lock = NSLock()
        private var entered = false
        private var released = false
        private var resourcesReleased = false

        /// True from the moment `assemble` is entered until `release()`.
        var isParked: Bool { lock.withLock { entered && !released } }
        var didEnter: Bool { lock.withLock { entered } }
        /// Flipped by the assembly's OWN release hook — the single mechanism
        /// the actor uses both for a superseded start (which never adopts the
        /// assembly) and for `stop()` (which releases the one it adopted).
        var didReleaseResources: Bool { lock.withLock { resourcesReleased } }

        func release() { lock.withLock { released = true } }

        func assemble(inputFormat: AVAudioFormat) async throws -> SpeechAnalysisAssembly {
            lock.withLock { entered = true }
            // Bounded: 400 × 10 ms ≈ 4 s, then it gives up and returns rather
            // than parking forever.
            for _ in 0..<400 where !(lock.withLock { released }) {
                try? await Task.sleep(for: .milliseconds(10))
            }
            let transcriber = SpeechTranscriber(locale: .current, preset: .progressiveTranscription)
            return SpeechAnalysisAssembly(
                analyzer: SpeechAnalyzer(modules: [transcriber]),
                analyzerFormat: inputFormat,
                reservedLocale: nil,
                transcriber: .speech(transcriber),
                releaseResources: { [weak self] in self?.markResourcesReleased() }
            )
        }

        private func markResourcesReleased() { lock.withLock { resourcesReleased = true } }
    }

    /// Drives the fixture to its suspension point and reports whether it got
    /// there. A start that never parked makes every assertion below it vacuous,
    /// so each arm checks this before doing anything else.
    private func parkedStart(
        _ controller: NativeVoiceCaptureController,
        _ assembler: ParkedAssembler
    ) async -> Task<AsyncStream<NativeVoiceCaptureEvent>, any Error> {
        let start = Task { try await controller.start(muted: false) }
        for _ in 0..<200 where !assembler.isParked {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return start
    }

    /// The seam exists and constructing the controller is inert: no assembly is
    /// built, and the audio engine is never touched — which is what makes this
    /// safe on a simulator whose input node reports 0 Hz (#428 Task 0(b),
    /// probe 2).
    @Test func theControllerAcceptsAnInjectedAssembler() async {
        let assembler = ParkedAssembler()
        let controller = NativeVoiceCaptureController(assembler: assembler)
        #expect(assembler.didEnter == false, "constructing a controller must not assemble anything")
        #expect(await controller.isEngineRunning == false, "constructing a controller must not start the engine")
    }

    /// **The bar.** A `stop()` that interleaves with a parked assembly must
    /// supersede the start: no tap installed, no engine started, and no
    /// orphaned analyzer or locale reservation left behind.
    @Test func aStopDuringAssemblySupersedesTheStartAndInstallsNothing() async throws {
        let assembler = ParkedAssembler()
        let controller = NativeVoiceCaptureController(assembler: assembler)
        let start = await parkedStart(controller, assembler)
        #expect(assembler.isParked, "fixture never reached the suspension point — the assertions below would be vacuous")

        await controller.stop(origin: .teardown)      // the interleaved teardown
        assembler.release()

        do {
            _ = try await start.value
            Issue.record("a start whose generation moved must not return a stream")
        } catch NativeVoiceCaptureController.CaptureError.superseded(let point, _) {
            #expect(point == "assembled")
        } catch NativeVoiceCaptureController.CaptureError.noAudioInput {
            Issue.record("the start ran on into the install stretch — the capture generation did not supersede it")
        } catch {
            // A legible red for the mutation run: an unhandled throw out of a
            // `throws` test reports as a harness failure, not as this bar.
            Issue.record("expected .superseded(point: \"assembled\"), got \(error)")
        }

        #expect(await controller.isEngineRunning == false)
        // 428-B2: the assembly returned, so the assembler's own catch cannot
        // clean it up, and the actor never adopted it — the superseded path
        // owns the release.
        #expect(
            assembler.didReleaseResources,
            "a superseded start must release the assembly it will never adopt (#428 428-B2)"
        )
    }

    /// **The control arm.** Same fixture, same park, NO interleaved stop — so
    /// the generation never moves and the start runs on into the install
    /// stretch, where this host's 0 Hz input node fails it with `.noAudioInput`
    /// (#428 Task 0(b) probe 2). Without this arm the bar above would pass on a
    /// controller that refused every start.
    @Test func aStartWithNoInterleavedStopIsNotSuperseded() async throws {
        let assembler = ParkedAssembler()
        let controller = NativeVoiceCaptureController(assembler: assembler)
        let start = await parkedStart(controller, assembler)
        #expect(assembler.isParked, "fixture never reached the suspension point — the assertions below would be vacuous")

        assembler.release()                            // no stop(): the ticket still matches

        do {
            _ = try await start.value
            Issue.record("the sim cannot start the engine; a stream here means the format gate moved")
        } catch NativeVoiceCaptureController.CaptureError.noAudioInput {
            // Expected on CC-lane-*: inputNode reports 0 Hz (#428 Task 0(b) probe 2).
        } catch NativeVoiceCaptureController.CaptureError.superseded(let point, _) {
            Issue.record("nothing stopped this start, yet it was superseded at \(point)")
        } catch {
            Issue.record("expected .noAudioInput, got \(error)")
        }

        #expect(await controller.isEngineRunning == false)
        // The actor ADOPTED this assembly (`startEngine` takes it over before
        // anything in it can throw), so the release hook belongs to `stop()`
        // now — firing it here would tear down resources a live capture owns.
        #expect(
            assembler.didReleaseResources == false,
            "an adopted assembly must not be released by the start that adopted it"
        )

        // …and it IS the same hook: one release mechanism, not two copies.
        await controller.stop(origin: .teardown)
        for _ in 0..<200 where !assembler.didReleaseResources {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            assembler.didReleaseResources,
            "stop() must release through the same hook the superseded path calls"
        )
    }

    // MARK: - 436-A (the controller half): the supersession carries its ORIGIN

    /// **436-A, part 1 of 2.** #428's ticket said THAT the generation moved;
    /// #436 needs it to say WHO moved it, because the two ends of that fact are
    /// opposite instructions — a teardown buys silence (#428 ruling 2) and a
    /// bare stop on a live session owes a repair.
    ///
    /// This is the provenance half, measured on the REAL
    /// `NativeVoiceCaptureController` through the same parking-assembler seam
    /// as the bar above. The SERVICE half (does a live session actually get
    /// repaired?) is `NativeVoiceRestartTeardownTests`, and it cannot be run
    /// against this controller: on `CC-lane-*` the input node reports 0 Hz, so
    /// a start that is NOT superseded dies with `.noAudioInput` and the
    /// pipeline can never reach `.connected` behind a real controller (#428
    /// Task 0(b) probe 2). Two halves, two fixtures, and this one is what makes
    /// the other's fake faithful rather than convenient.
    ///
    /// The isolating mutation for both halves is the same: make `checkTicket`
    /// throw a constant `.teardown` (drop the origin) and this row reds here,
    /// where the fake cannot flatter it.
    @Test func aBareStopSupersedesTheStartWithTheBareStopOrigin() async throws {
        let assembler = ParkedAssembler()
        let controller = NativeVoiceCaptureController(assembler: assembler)
        let start = await parkedStart(controller, assembler)
        #expect(assembler.isParked, "fixture never reached the suspension point — the assertions below would be vacuous")

        // The #436 trace's own stop: the analyzer's failure path calls
        // `stop(origin: .bareStop)` on a session nobody is tearing down.
        await controller.stop(origin: .bareStop)
        assembler.release()

        do {
            _ = try await start.value
            Issue.record("a start whose generation moved must not return a stream")
        } catch NativeVoiceCaptureController.CaptureError.superseded(let point, let origin) {
            #expect(point == "assembled")
            #expect(
                origin == .bareStop,
                "the supersession must carry the origin of the stop that caused it, or the restart path cannot tell a live-session stop from a teardown (#436)"
            )
        } catch {
            Issue.record("expected .superseded(point: \"assembled\", origin: .bareStop), got \(error)")
        }
    }

    /// The discriminating twin. Same fixture, same park, a TEARDOWN-origin stop
    /// — and the origin that comes back must differ. Without this arm the row
    /// above would pass on a controller that hardcoded `.bareStop`, which is
    /// the mirror image of the mutation it is defended against.
    @Test func aTeardownStopSupersedesTheStartWithTheTeardownOrigin() async throws {
        let assembler = ParkedAssembler()
        let controller = NativeVoiceCaptureController(assembler: assembler)
        let start = await parkedStart(controller, assembler)
        #expect(assembler.isParked, "fixture never reached the suspension point — the assertions below would be vacuous")

        await controller.stop(origin: .teardown)
        assembler.release()

        do {
            _ = try await start.value
            Issue.record("a start whose generation moved must not return a stream")
        } catch NativeVoiceCaptureController.CaptureError.superseded(_, let origin) {
            #expect(
                origin == .teardown,
                "a teardown-caused supersession must say so — silence is only correct because of this (#428 ruling 2, #436)"
            )
        } catch {
            Issue.record("expected .superseded(origin: .teardown), got \(error)")
        }
    }

    /// **Last writer wins, and it is the rule the service's belts are built
    /// on.** Two stops interleave with one parked start; the origin the start
    /// resumes with is the LATER one. A teardown that lands after a bare stop
    /// owns the pipeline whatever ran before it — which is exactly the case
    /// where a repair would repaint a session that is going away.
    @Test func theOriginIsTheLastStopsNotTheFirsts() async throws {
        let assembler = ParkedAssembler()
        let controller = NativeVoiceCaptureController(assembler: assembler)
        let start = await parkedStart(controller, assembler)
        #expect(assembler.isParked, "fixture never reached the suspension point — the assertions below would be vacuous")

        await controller.stop(origin: .bareStop)
        await controller.stop(origin: .teardown)
        assembler.release()

        do {
            _ = try await start.value
            Issue.record("a start whose generation moved must not return a stream")
        } catch NativeVoiceCaptureController.CaptureError.superseded(_, let origin) {
            #expect(
                origin == .teardown,
                "the LAST stop owns the pipeline; reporting the first would repair a session that is being torn down (#436)"
            )
        } catch {
            Issue.record("expected .superseded(origin: .teardown), got \(error)")
        }
    }

    // The abandoned-start line's own text is pinned in
    // `VoiceInstrumentLogLineTests` (#428), where every voice log-line
    // formatter pin lives — one home, not two. #436 deliberately does NOT
    // change that line: the origin decides what the SERVICE does, and the
    // service's own live-session line is where it is named.
}
