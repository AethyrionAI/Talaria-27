import Foundation
import Testing
@testable import Talaria

/// #364: stored transcripts on 0.20.3 carry FULL tool args
/// (`tool_calls[].function.arguments`) on both lanes — the app can rebuild
/// Tier-1 chips at refetch time from the server's own record. Every arm here
/// pins the degrade path too: absent/malformed arguments must map EXACTLY as
/// today (activity only, no chip, no crash) — that posture is also the
/// OJAMD-unverified guard, because the wire shape itself is the gate.
struct StoredArgsReconstructionTests {

    // MARK: - Fixtures

    private func storedRow(
        id: Int? = 42,
        toolCallJSON: String
    ) throws -> SessionsHermesClient.SessionMessagesResponse.StoredMessage {
        let json = """
        {"id": \(id.map(String.init) ?? "null"), "role": "assistant",
         "content": "done", "timestamp": 1787027880.7,
         "tool_calls": [\(toolCallJSON)]}
        """
        return try JSONDecoder().decode(
            SessionsHermesClient.SessionMessagesResponse.StoredMessage.self,
            from: Data(json.utf8)
        )
    }

    private func map(_ row: SessionsHermesClient.SessionMessagesResponse.StoredMessage) -> Message? {
        SessionsHermesClient.mapStoredMessage(row, sessionId: "sess-364")
    }

    private static let writeCallJSON = """
    {"id":"call_1","type":"function","function":{"name":"write_file",
     "arguments":"{\\"path\\":\\"/tmp/notes/a.md\\",\\"content\\":\\"hello stored\\"}"}}
    """

    // MARK: - 364-A: reconstruction

    @Test func reconstructsTier1ChipFromStoredArguments() throws {
        let message = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))

        #expect(message.attachments.count == 1)
        let chip = try #require(message.attachments.first)
        #expect(chip.fileName == "a.md")
        #expect(chip.localStoragePath != nil)
        // The staged bytes are the verbatim stored content.
        if let path = chip.localStoragePath {
            #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "hello stored")
        }
        // The activity's detail is the path — which is ALSO what lets the
        // #362 mirror correlator match this row after a refetch.
        #expect(message.toolActivities.first?.detail == "/tmp/notes/a.md")
    }

    @Test func attachmentIDIsDeterministicAcrossRefetches() throws {
        let first = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))
        let second = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))
        #expect(first.attachments.first?.id == second.attachments.first?.id)
    }

    @Test func rowWithoutServerIDStillReconstructsWithFreshID() throws {
        // No stable anchor to key on — the chip still appears, with a fresh
        // UUID, matching stableMessageID's fallback posture.
        let first = try #require(map(try storedRow(id: nil, toolCallJSON: Self.writeCallJSON)))
        let second = try #require(map(try storedRow(id: nil, toolCallJSON: Self.writeCallJSON)))
        #expect(first.attachments.count == 1)
        #expect(second.attachments.count == 1)
        #expect(first.attachments.first?.id != second.attachments.first?.id)
    }

    @Test func flatArgumentsKeyIsTolerated() throws {
        let flat = """
        {"name":"write_file",
         "arguments":"{\\"path\\":\\"/tmp/flat.md\\",\\"content\\":\\"flat\\"}"}
        """
        let message = try #require(map(try storedRow(toolCallJSON: flat)))
        #expect(message.attachments.count == 1)
        #expect(message.attachments.first?.fileName == "flat.md")
    }

    @Test func createFileAlsoReconstructs() throws {
        let create = """
        {"function":{"name":"create_file",
         "arguments":"{\\"file_path\\":\\"/tmp/c.md\\",\\"text\\":\\"drift\\"}"}}
        """
        let message = try #require(map(try storedRow(toolCallJSON: create)))
        // The arg-key drift tolerance is WrittenFileArgs' — file_path/text
        // must work here exactly as they do on the live stream.
        #expect(message.attachments.count == 1)
        #expect(message.attachments.first?.fileName == "c.md")
    }

    @Test func emptyContentIsARealEmptyFile() throws {
        let empty = """
        {"function":{"name":"write_file",
         "arguments":"{\\"path\\":\\"/tmp/empty.md\\",\\"content\\":\\"\\"}"}}
        """
        let message = try #require(map(try storedRow(toolCallJSON: empty)))
        #expect(message.attachments.count == 1)
    }

    // MARK: - 364-A: the degrade arms (today's behavior, exactly)

    @Test func absentArgumentsMapsAsToday() throws {
        let bare = #"{"function":{"name":"write_file"}}"#
        let message = try #require(map(try storedRow(toolCallJSON: bare)))
        #expect(message.attachments.isEmpty)
        #expect(message.toolActivities.first?.label == "write_file")
        #expect(message.toolActivities.first?.detail == nil)
    }

    @Test func malformedArgumentsNeverCrashAndNeverInvent() throws {
        for arguments in ["not json at all", "{}", "null", "[1,2,3]"] {
            let call = """
            {"function":{"name":"write_file",
             "arguments":"\(arguments.replacingOccurrences(of: "\"", with: "\\\""))"}}
            """
            let message = try #require(map(try storedRow(toolCallJSON: call)))
            #expect(message.attachments.isEmpty, "arguments = \(arguments)")
        }
    }

    @Test func pathOnlyArgumentsFillDetailButNeverFabricateContent() throws {
        // A pointer-only write mirrors nothing and reconstructs nothing —
        // but the PATH is real, so the activity detail gets it, which is
        // what lets a LATER mirror item attach to this refetched row.
        let pathOnly = """
        {"function":{"name":"write_file",
         "arguments":"{\\"path\\":\\"/tmp/pointer.bin\\"}"}}
        """
        let message = try #require(map(try storedRow(toolCallJSON: pathOnly)))
        #expect(message.attachments.isEmpty)
        #expect(message.toolActivities.first?.detail == "/tmp/pointer.bin")
    }

    @Test func nonWriteToolArgumentsAreIgnored() throws {
        let exec = """
        {"function":{"name":"execute_command",
         "arguments":"{\\"path\\":\\"/tmp/x.md\\",\\"content\\":\\"nope\\"}"}}
        """
        let message = try #require(map(try storedRow(toolCallJSON: exec)))
        #expect(message.attachments.isEmpty)
        #expect(message.toolActivities.first?.label == "execute_command")
    }

    @Test func storedPreviewStillWinsTheDetailSlot() throws {
        // When the server DID store a preview, it stays the detail — least
        // change, and the correlator's clipped-preview match handles it.
        let withPreview = """
        {"function":{"name":"write_file",
         "arguments":"{\\"path\\":\\"/tmp/p.md\\",\\"content\\":\\"x\\"}"},
         "preview":"/tmp/p.md"}
        """
        let message = try #require(map(try storedRow(toolCallJSON: withPreview)))
        #expect(message.toolActivities.first?.detail == "/tmp/p.md")
        #expect(message.attachments.count == 1)
    }

    // MARK: - 364-B: the sidecar crossing

    @Test func sidecarReplaySkipsAChipTheRowAlreadyCarries() throws {
        // A pre-364 sidecar record (streaming-time random id) replayed onto
        // a row that post-364 reconstruction already gave the same file —
        // one chip, not two.
        let message = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))
        #expect(message.attachments.count == 1)

        let oldChip = MessageAttachment(
            kind: "file", fileName: "a.md", mimeType: "text/markdown",
            localStoragePath: "/old/staged/a.md"
        )
        let record = AgentAttachmentSidecar.Row(
            messageID: message.id,
            contentKey: AgentAttachmentSidecar.fingerprint(sender: message.sender, content: message.content),
            attachments: [oldChip]
        )
        let replayed = AgentAttachmentSidecar.replaying([record], onto: [message])
        #expect(replayed[0].attachments.count == 1)
    }

    @Test func sidecarReplayStillAddsGenuinelyNewChips() throws {
        // The skip is same-file only — a record for a DIFFERENT file still
        // replays (the #277 behavior this must not break).
        let message = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))
        let otherChip = MessageAttachment(
            kind: "file", fileName: "other.md", mimeType: "text/markdown",
            localStoragePath: "/old/staged/other.md"
        )
        let record = AgentAttachmentSidecar.Row(
            messageID: message.id,
            contentKey: AgentAttachmentSidecar.fingerprint(sender: message.sender, content: message.content),
            attachments: [otherChip]
        )
        let replayed = AgentAttachmentSidecar.replaying([record], onto: [message])
        #expect(replayed[0].attachments.count == 2)
    }

    // MARK: - #367: the turn-split crossing (Owen's OJAMD reopen, 2026-08-18)

    @Test func sidecarReplaySkipsAChipASiblingRowOfTheTurnCarries() throws {
        // A refetched turn SPLITS into rows: reconstruction decorates the
        // tool-call row, while the live-attach sidecar record anchors to the
        // prose tail. Per-row same-file dedupe let both land — one write,
        // two chips (the split-row class's second hit in one day). The skip
        // is turn-scoped now.
        let user = Message(sender: .user, content: "write a haiku file")
        let toolRow = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))
        #expect(toolRow.attachments.count == 1)
        let proseRow = Message(sender: .hermes, content: "Done — a.md has the haiku.")

        let liveChip = MessageAttachment(
            kind: "file", fileName: "a.md", mimeType: "text/markdown",
            localStoragePath: "/old/staged/a.md"
        )
        let record = AgentAttachmentSidecar.Row(
            messageID: proseRow.id,
            contentKey: AgentAttachmentSidecar.fingerprint(sender: proseRow.sender, content: proseRow.content),
            attachments: [liveChip]
        )
        let replayed = AgentAttachmentSidecar.replaying([record], onto: [user, toolRow, proseRow])

        #expect(replayed[2].attachments.isEmpty)
        let turnChips = replayed.flatMap(\.attachments).filter { $0.fileName == "a.md" }
        #expect(turnChips.count == 1)
    }

    @Test func sidecarReplayStillReplaysTheSameFileAcrossTurns() throws {
        // Scope guard: the SAME path written in an EARLIER turn is a
        // different artifact — a user-authored row bounds the scan, and the
        // record still replays.
        let firstTurnRow = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))
        let secondAsk = Message(sender: .user, content: "write it again")
        let proseRow = Message(sender: .hermes, content: "Rewrote a.md.")

        let liveChip = MessageAttachment(
            kind: "file", fileName: "a.md", mimeType: "text/markdown",
            localStoragePath: "/old/staged/a.md"
        )
        let record = AgentAttachmentSidecar.Row(
            messageID: proseRow.id,
            contentKey: AgentAttachmentSidecar.fingerprint(sender: proseRow.sender, content: proseRow.content),
            attachments: [liveChip]
        )
        let replayed = AgentAttachmentSidecar.replaying(
            [record], onto: [firstTurnRow, secondAsk, proseRow])

        #expect(replayed[2].attachments.count == 1)
    }

    // MARK: - 364-C: the mirror stands down when reconstruction beat it

    @Test @MainActor func mirrorItemDropsWhenReconstructionAlreadyFilled() throws {
        let message = try #require(map(try storedRow(toolCallJSON: Self.writeCallJSON)))

        @MainActor
        final class Transcript: ArtifactMirrorTranscript {
            var mirrorSessionID: String? = "sess-364"
            var mirrorMessages: [Message]
            var persisted = 0
            init(messages: [Message]) { self.mirrorMessages = messages }
            func persistMirrorAttachments() { persisted += 1 }
        }
        let transcript = Transcript(messages: [message])
        let correlator = ArtifactMirrorCorrelator(transcript: transcript)
        correlator.receive(
            ArtifactMirrorItem(
                platformItemID: "late", sessionID: "sess-364", path: "/tmp/notes/a.md",
                content: "hello stored", turnID: nil, toolCallID: nil, hostTimestamp: nil
            )
        )
        #expect(transcript.mirrorMessages[0].attachments.count == 1)
        #expect(transcript.persisted == 0)
        #expect(correlator.pendingCountForDiagnostics == 0)
    }
}
