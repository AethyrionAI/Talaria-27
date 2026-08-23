import Foundation
import Testing
@testable import Talaria

/// #9 — voice-memo attachments: the transcript is the attachment (ships via
/// the #8 text-inlining branch); the audio path rides alongside for local
/// playback. Recording/transcription/playback themselves need device audio
/// and aren't unit-testable headlessly — these tests cover the pure staging,
/// wire, and cache-compat surfaces.
struct VoiceMemoAttachmentTests {

    private let audioURL = URL(fileURLWithPath: "/tmp/VoiceMemo-test.m4a")
    private let recordedAt = Date(timeIntervalSince1970: 1_783_000_000)

    private func makeMemo(transcript: String = "Remember to reconcile the OJAMD fork.") -> PendingAttachment {
        PendingAttachment.voiceMemo(
            transcript: transcript,
            audioFileURL: audioURL,
            duration: 245,
            recordedAt: recordedAt
        )
    }

    // MARK: - Staging factory

    @Test func voiceMemoStagesAsTransmittableTextFile() {
        let memo = makeMemo()
        #expect(memo.kind == .file)
        #expect(memo.mimeType == "text/plain")
        #expect(memo.isVoiceMemo)
        // Text-MIME .file ⇒ rides the #8 inlining branch with no send-path change.
        #expect(memo.isTransmittable)
        #expect(memo.voiceMemoAudioPath == audioURL.path)
        // No thumbnail — the chip must read as "text will be sent".
        #expect(memo.thumbnailData == nil)
    }

    @Test func voiceMemoBodyCarriesProvenanceHeaderAndTranscript() {
        let memo = makeMemo(transcript: "Line one.\nLine two.")
        let body = String(decoding: memo.data, as: UTF8.self)
        // One bracketed provenance line (recorded time + duration), then the
        // transcript verbatim — never a rewritten or summarized version.
        #expect(body.hasPrefix("[Voice memo transcript — recorded "))
        #expect(body.contains("4m 05s"))
        #expect(body.hasSuffix("Line one.\nLine two."))
    }

    @Test func voiceMemoFileNameIsTimestampedText() {
        let name = PendingAttachment.voiceMemoFileName(recordedAt: recordedAt)
        #expect(name.hasPrefix("Voice Memo "))
        #expect(name.hasSuffix(".txt"))
        // Colons are unusable in file names — dots stand in.
        #expect(!name.contains(":"))
    }

    @Test func durationFormatsHumanReadably() {
        #expect(PendingAttachment.voiceMemoDuration(245) == "4m 05s")
        #expect(PendingAttachment.voiceMemoDuration(32) == "32s")
        #expect(PendingAttachment.voiceMemoDuration(0) == "0s")
        #expect(PendingAttachment.voiceMemoDuration(60) == "1m 00s")
    }

    // MARK: - Wire shape (reuses the #8 branch)

    @Test func voiceMemoInlinesAsDelimitedTextPart() {
        let memo = makeMemo(transcript: "The transcript itself.")
        let assembly = AttachmentInlining.assemble(message: "", attachments: [memo])
        #expect(assembly.notTransmittable.isEmpty)
        #expect(assembly.omittedForBudget.isEmpty)
        #expect(assembly.parts.count == 1)
        guard case .text(let block) = assembly.parts[0] else {
            Issue.record("Expected a delimited text part, got \(assembly.parts[0])")
            return
        }
        #expect(block.contains("===== BEGIN FILE: \(memo.fileName)"))
        #expect(block.contains("The transcript itself."))
        #expect(block.contains("===== END FILE: \(memo.fileName)"))
    }

    // MARK: - Message model carry-through + cache back-compat

    @Test func messageAttachmentCarriesAudioPath() {
        let memo = makeMemo()
        let message = MessageAttachment(from: memo)
        #expect(message.voiceMemoAudioPath == audioURL.path)
        #expect(message.kind == "file")
    }

    @Test func preVoiceMemoCacheJSONStillDecodes() throws {
        // A cached MessageAttachment from before #9 — no voiceMemoAudioPath key.
        let legacyJSON = Data("""
        {
            "id": "9C2AB1E4-3F5B-4D8A-9C0D-1E2F3A4B5C6D",
            "kind": "file",
            "fileName": "notes.md",
            "mimeType": "text/markdown"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(MessageAttachment.self, from: legacyJSON)
        #expect(decoded.voiceMemoAudioPath == nil)
        #expect(decoded.fileName == "notes.md")
    }

    @Test func messageAttachmentRoundTripsAudioPath() throws {
        let original = MessageAttachment(
            kind: "file",
            fileName: "Voice Memo 2026-07-06 14.30.05.txt",
            mimeType: "text/plain",
            voiceMemoAudioPath: "/private/var/memo.m4a"
        )
        let decoded = try JSONDecoder().decode(
            MessageAttachment.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded.voiceMemoAudioPath == "/private/var/memo.m4a")
    }
}

/// **#399 — the #84 guard on the memo audio surfaces, tested through the
/// PUBLIC entry points rather than through the decision alone.**
///
/// The decision (`shouldReleaseAudioSession`) is one line and a test of it in
/// isolation proves almost nothing: delete the call in `stop()` and such a
/// test stays green while the fix is gone. #340 measured exactly that — eleven
/// green parsing tests survived removing the `performCreate` wiring they
/// existed to protect — so these drive `stop()` and `discard()` and observe
/// the injected deactivation seam.
@MainActor
struct VoiceMemoAudioSessionGuardTests {

    // MARK: - The decision

    /// The load-bearing case, and the one the old code got wrong: an instance
    /// that never activated must never release. `VoiceMemoPlayer.stop()`
    /// carried the comment *"releasing an inactive session is harmless"* —
    /// which is the claim #84 falsified when read-aloud deactivating a session
    /// it had never activated killed a live mic.
    @Test func neitherServiceReleasesASessionItDidNotActivate() {
        #expect(VoiceMemoPlayer.shouldReleaseAudioSession(didActivate: false) == false)
        #expect(VoiceMemoRecorder.shouldReleaseAudioSession(didActivate: false) == false)
        #expect(VoiceMemoPlayer.shouldReleaseAudioSession(didActivate: true) == true)
        #expect(VoiceMemoRecorder.shouldReleaseAudioSession(didActivate: true) == true)
    }

    // MARK: - The WIRING (this is the half that catches a deleted fix)

    /// A fresh player has activated nothing, so `stop()` must not touch the
    /// shared session. **Restore the unconditional
    /// `setActive(false, .notifyOthersOnDeactivation)` and this goes RED** —
    /// which is the whole point of driving `stop()` instead of the predicate.
    @Test func playerStopDoesNotDeactivateASessionItNeverActivated() {
        let player = VoiceMemoPlayer()
        var deactivations = 0
        player.deactivateAudioSession = { deactivations += 1 }

        player.stop()
        player.stop()   // idempotent: still nothing to release

        #expect(deactivations == 0)
        #expect(player.playingPath == nil)
    }

    /// The recorder's sibling site. `discard()` reaches `finishRecorder()`
    /// unconditionally, so a discard with no recording in flight is the exact
    /// shape that used to fire a stray deactivation.
    @Test func recorderDiscardDoesNotDeactivateASessionItNeverActivated() {
        let recorder = VoiceMemoRecorder()
        var deactivations = 0
        recorder.deactivateAudioSession = { deactivations += 1 }

        recorder.discard()

        #expect(deactivations == 0)
        #expect(recorder.isRecording == false)
    }

    /// `stopRecording()` returns nil with nothing in flight and must also stay
    /// silent — it guards on `isRecording` before reaching `finishRecorder()`,
    /// and this pins that it keeps doing so.
    @Test func recorderStopWithNothingInFlightIsASessionNoOp() {
        let recorder = VoiceMemoRecorder()
        var deactivations = 0
        recorder.deactivateAudioSession = { deactivations += 1 }

        #expect(recorder.stopRecording() == nil)
        #expect(deactivations == 0)
    }

    /// **The mutation the seam-based tests above CANNOT see, closed here.**
    ///
    /// Those tests observe `deactivateAudioSession`. Removing the guard while
    /// keeping the seam turns them RED — but reverting to the ORIGINAL code,
    /// a direct `AVAudioSession.sharedInstance().setActive(false, …)`, bypasses
    /// the seam entirely and they stay GREEN while the shared session is being
    /// torn down for real. That is the historical shape, so leaving it uncovered
    /// would mean the suite cannot see the very defect #399 fixed.
    ///
    /// So this asserts the STRUCTURAL invariant instead: each service spells a
    /// deactivation exactly once, inside the seam's default. Precedent for a
    /// test that reads source is already in the tree —
    /// `score-decline-attribution-test.py` parses `DeclineAttributionScorer.swift`
    /// to hold two implementations in sync.
    ///
    /// Fails loudly if the sources cannot be read: a check that cannot run must
    /// say so rather than print a pass it did not earn.
    @Test func deactivationIsSpelledOnlyInsideTheInjectableSeam() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root

        for name in ["VoiceMemoPlayer", "VoiceMemoRecorder"] {
            let url = root.appendingPathComponent("Talaria/Services/Live/\(name).swift")
            let source = try #require(
                try? String(contentsOf: url, encoding: .utf8),
                "cannot read \(name).swift at \(url.path) — this check did not run"
            )
            let direct = source.components(separatedBy: "setActive(false").count - 1
            #expect(direct == 1, """
                \(name) spells `setActive(false` \(direct) time(s); expected exactly 1                 (the `deactivateAudioSession` default). A second one is a #84 release                 that bypasses the ownership guard and the seam that tests it.
                """)
        }
    }

    /// The guard must not become "never release". These services DO own the
    /// session while playing or recording, and failing to release it is the
    /// opposite defect — other audio stays ducked and the category stays wrong.
    ///
    /// Driven through the real release path by way of the decision the path
    /// consults, since activating for real needs device audio.
    @Test func theGuardStillReleasesWhatTheInstanceDidActivate() {
        #expect(VoiceMemoPlayer.shouldReleaseAudioSession(didActivate: true))
        #expect(VoiceMemoRecorder.shouldReleaseAudioSession(didActivate: true))
    }
}
