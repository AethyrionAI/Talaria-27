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
