import AVFoundation
import Testing
@testable import Talaria

/// **#138-B/C — when may the realtime session force the output to the speaker?**
///
/// This exists because of a defect whose cause was the FIX for something else.
/// `forceSpeakerIfNeeded` is called twice around connect — once after
/// `setRemoteDescription`, once more on a 500 ms timer described in the source
/// as a "safety net" — and each call handed CoreAudio a route reconfiguration
/// even when the route was already correct. A route change makes the system
/// echo canceller re-adapt, and the 500 ms call lands squarely in the window
/// where the FIRST assistant utterance plays.
///
/// **Measured 2026-08-22, 4 of 4 session starts on the speakerphone route:**
/// the assistant's own audio leaked into the microphone and was transcribed as
/// a user turn, which — with `interrupt_response: true` — cut the assistant off
/// mid-greeting. Always the first utterance; never afterwards. The phantom
/// turns were `嗨`, `Echt?`, `OK.` and `Kanada`: short, mostly non-English
/// tokens, which is the signature of echo residue reaching a speech recogniser
/// rather than of a person speaking.
///
/// **What these tests deliberately do NOT claim.** They pin the DECISION, not
/// the acoustics. That the skip actually removes the self-interrupt is a device
/// measurement (138-A's re-run), not something a unit test can see.
struct SpeakerRouteOverrideTests {

    private typealias Subject = LiveVoiceSessionService

    /// The case the whole lane is about: already on the speaker, so overriding
    /// buys nothing and costs an AEC re-adaptation.
    @Test func alreadyOnTheBuiltInSpeakerDoesNotOverrideAgain() {
        #expect(Subject.shouldOverrideOutputToSpeaker(
            currentOutputPortTypes: [.builtInSpeaker]
        ) == false)
    }

    /// **138-C — the safety net keeps its purpose.**
    ///
    /// The override exists because WebRTC reconfigures the audio session under
    /// us; a build that stopped correcting a genuinely wrong route would have
    /// traded a rare self-interrupt for quiet audio out of the earpiece, which
    /// is strictly worse. `.builtInReceiver` is exactly that case.
    @Test func anEarpieceRouteIsSTILLCorrectedBecauseThatIsWhyTheOverrideExists() {
        #expect(Subject.shouldOverrideOutputToSpeaker(
            currentOutputPortTypes: [.builtInReceiver]
        ))
    }

    /// Pre-existing behaviour, pinned because this lane rewrote the function
    /// that owned it. Headsets handle their own volume and routing.
    @Test func everyExternalOutputIsLeftAlone() {
        for port in [AVAudioSession.Port.headphones, .bluetoothA2DP, .bluetoothHFP,
                     .bluetoothLE, .airPlay, .carAudio] {
            #expect(Subject.shouldOverrideOutputToSpeaker(currentOutputPortTypes: [port]) == false,
                    "overrode an external output: \(port.rawValue)")
        }
    }

    /// An external output wins even when the speaker is also listed — a real
    /// shape during a route transition. Ordering must not decide it.
    @Test func anExternalOutputWinsOverAConcurrentlyListedSpeaker() {
        #expect(Subject.shouldOverrideOutputToSpeaker(
            currentOutputPortTypes: [.builtInSpeaker, .headphones]
        ) == false)
        #expect(Subject.shouldOverrideOutputToSpeaker(
            currentOutputPortTypes: [.headphones, .builtInSpeaker]
        ) == false)
    }

    /// An unknown or empty route asserts the intent rather than assuming it
    /// holds. Declining here would mean a session whose route could not be
    /// read never gets its speaker override at all — failing toward silence,
    /// which is the direction #180 forbids.
    @Test func anUnreadableRouteFallsTowardAssertingTheSpeaker() {
        #expect(Subject.shouldOverrideOutputToSpeaker(currentOutputPortTypes: []))
        #expect(Subject.shouldOverrideOutputToSpeaker(currentOutputPortTypes: [.builtInMic]))
    }

    /// **The wiring pin the 2026-08-23 Opus-week audit found missing.** The
    /// tests above pin the pure decision; unwiring either call site while
    /// keeping the function would have left them green — the #340 wiring
    /// shape. So the structural invariant is pinned in the source (the #399
    /// pattern): exactly THREE spellings of the name in
    /// `LiveVoiceSessionService.swift` — the definition and its two call
    /// sites (configureAudioSession, and the post-connect re-assert).
    /// Fails loudly if the source cannot be read.
    @Test func theSpeakerDecisionIsWiredAtBothCallSites() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria/Services/Live/LiveVoiceSessionService.swift")
        let source = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "cannot read LiveVoiceSessionService.swift — this check did not run"
        )
        let spellings = source.components(separatedBy: "shouldOverrideOutputToSpeaker").count - 1
        #expect(spellings == 3, """
            expected exactly 3 spellings of shouldOverrideOutputToSpeaker \
            (1 definition + 2 call sites); found \(spellings) — a call site \
            was unwired (or a new one was added without extending this pin)
            """)
    }
}
