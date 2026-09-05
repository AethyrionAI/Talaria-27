@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import Testing
@testable import Talaria

/// #428 — the capture-generation bar (428-B).
///
/// **Task 1 seeds this file with the fixture ONLY.** The behavioural bar (a
/// `stop()` interleaved with a parked `assemble` must supersede the start and
/// install nothing) is Task 2's; all this suite proves today is that the two
/// seams Task 1 opens — `SpeechAnalysisAssembling` and
/// `NativeVoiceCaptureController(assembler:)` — exist and can be driven by a
/// fake.
@Suite("428-B capture generation")
struct NativeVoiceCaptureGenerationTests {

    /// Parks inside `assemble` until the test releases it, so a test can hold a
    /// capture start at its one remaining suspension point.
    ///
    /// Polling, not a `CheckedContinuation`, and deliberately BOUNDED — the
    /// `TalkStoreBackgroundRevokeTests.ParkedStartVoiceService` rule: a
    /// stranded continuation hangs the whole suite with no message, which is
    /// exactly the failure this lane is trying to make visible rather than
    /// suffer.
    final class ParkedAssembler: SpeechAnalysisAssembling, @unchecked Sendable {
        private let lock = NSLock()
        private var entered = false
        private var released = false

        /// True from the moment `assemble` is entered until `release()`.
        var isParked: Bool { lock.withLock { entered && !released } }
        var didEnter: Bool { lock.withLock { entered } }

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
                transcriber: .speech(transcriber)
            )
        }
    }

    /// The seam exists: the controller accepts an injected assembler.
    ///
    /// Nothing is started here — constructing the controller must not touch the
    /// audio engine, so this is safe on a simulator whose input node reports
    /// 0 Hz (#428 Task 0(b), probe 2).
    @Test func theControllerAcceptsAnInjectedAssembler() {
        let assembler = ParkedAssembler()
        let controller: NativeVoiceCaptureController? =
            NativeVoiceCaptureController(assembler: assembler)
        #expect(controller != nil, "the assembler seam must construct a controller")
        #expect(assembler.didEnter == false, "constructing a controller must not assemble anything")
    }
}
