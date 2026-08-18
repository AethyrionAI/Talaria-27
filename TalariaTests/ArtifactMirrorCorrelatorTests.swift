import Foundation
import Testing
@testable import Talaria

/// #362 3D-A: the correlator's match rules, each arm pinned both ways — a
/// do-nothing correlator fails every attach test, an attach-anything one
/// fails every drop test.
@MainActor
struct ArtifactMirrorCorrelatorTests {

    // MARK: - Fixtures

    @MainActor
    final class FakeTranscript: ArtifactMirrorTranscript {
        var mirrorSessionID: String?
        var mirrorMessages: [Message] = []
        var persistCount = 0
        init(sessionID: String? = "s1") { self.mirrorSessionID = sessionID }
        func persistMirrorAttachments() { persistCount += 1 }
    }

    private func agentMessage(
        content: String = "reply",
        writePaths: [String] = [],
        attachments: [MessageAttachment] = []
    ) -> Message {
        var message = Message(sender: .hermes, content: content)
        message.toolActivities = writePaths.map {
            ToolActivity(
                id: UUID(), label: "write_file", startedAt: Date(),
                isActive: false, detail: $0, anchorOffset: content.count
            )
        }
        message.attachments = attachments
        return message
    }

    private func mirrorItem(
        session: String = "s1", path: String = "notes/a.txt", content: String = "abc",
        id: String = "item-1"
    ) -> ArtifactMirrorItem {
        ArtifactMirrorItem(
            platformItemID: id, sessionID: session, path: path, content: content,
            turnID: nil, toolCallID: nil, hostTimestamp: nil
        )
    }

    private func correlator(
        _ transcript: FakeTranscript,
        holdWindow: TimeInterval = 600,
        clock: @escaping () -> Date = Date.init
    ) -> ArtifactMirrorCorrelator {
        ArtifactMirrorCorrelator(transcript: transcript, holdWindow: holdWindow, clock: clock)
    }

    // MARK: - Attach arms

    @Test func attachesToTheMessageWithTheMatchingWriteActivity() {
        let transcript = FakeTranscript()
        transcript.mirrorMessages = [
            agentMessage(content: "wrote b", writePaths: ["other/b.txt"]),
            agentMessage(content: "wrote a", writePaths: ["notes/a.txt"]),
        ]
        correlator(transcript).receive(mirrorItem())

        #expect(transcript.mirrorMessages[0].attachments.isEmpty)
        let attached = transcript.mirrorMessages[1].attachments
        #expect(attached.count == 1)
        #expect(attached.first?.fileName == "a.txt")
        #expect(attached.first?.localStoragePath != nil)
        #expect(attached.first?.anchorOffset == "wrote a".count)
        #expect(transcript.persistCount == 1)
    }

    @Test func samePathTwiceFillsNewestFirstThenOlder() {
        let transcript = FakeTranscript()
        transcript.mirrorMessages = [
            agentMessage(content: "first write", writePaths: ["notes/a.txt"]),
            agentMessage(content: "second write", writePaths: ["notes/a.txt"]),
        ]
        let correlator = correlator(transcript)
        correlator.receive(mirrorItem(content: "v2", id: "item-1"))
        #expect(transcript.mirrorMessages[1].attachments.count == 1)
        #expect(transcript.mirrorMessages[0].attachments.isEmpty)

        correlator.receive(mirrorItem(content: "v1", id: "item-2"))
        #expect(transcript.mirrorMessages[0].attachments.count == 1)
        #expect(transcript.mirrorMessages[1].attachments.count == 1)
    }

    @Test func upgradesAPointerOnlyChipInPlace() {
        // The runs plane's prose sweep already made a fetchable chip for the
        // path; the mirror must fill THAT chip, not add a second one.
        let pointer = MessageAttachment(
            kind: "file", fileName: "a.txt", mimeType: "text/plain",
            localStoragePath: nil, remotePath: "notes/a.txt", anchorOffset: 4
        )
        let transcript = FakeTranscript()
        transcript.mirrorMessages = [
            agentMessage(content: "wrote a", writePaths: ["notes/a.txt"], attachments: [pointer])
        ]
        correlator(transcript).receive(mirrorItem())

        let attachments = transcript.mirrorMessages[0].attachments
        #expect(attachments.count == 1)
        #expect(attachments.first?.id == pointer.id)
        #expect(attachments.first?.localStoragePath != nil)
        #expect(attachments.first?.remotePath == "notes/a.txt")
        #expect(attachments.first?.anchorOffset == 4)
    }

    @Test func clippedPreviewStillMatchesItsPath() {
        let clipped = String("deeply/nested/dir/notes/a.txt".prefix(20)) + "…"
        let transcript = FakeTranscript()
        transcript.mirrorMessages = [agentMessage(writePaths: [clipped])]
        correlator(transcript).receive(mirrorItem(path: "deeply/nested/dir/notes/a.txt"))
        #expect(transcript.mirrorMessages[0].attachments.count == 1)
    }

    // MARK: - Drop / hold arms

    @Test func wrongSessionNeverAttaches() {
        let transcript = FakeTranscript(sessionID: "OTHER")
        transcript.mirrorMessages = [agentMessage(writePaths: ["notes/a.txt"])]
        let correlator = correlator(transcript)
        correlator.receive(mirrorItem(session: "s1"))
        #expect(transcript.mirrorMessages[0].attachments.isEmpty)
        #expect(correlator.pendingCountForDiagnostics == 1)
    }

    @Test func unknownPathHoldsWithoutAttaching() {
        let transcript = FakeTranscript()
        transcript.mirrorMessages = [agentMessage(writePaths: ["other/b.txt"])]
        let correlator = correlator(transcript)
        correlator.receive(mirrorItem(path: "notes/a.txt"))
        #expect(transcript.mirrorMessages[0].attachments.isEmpty)
        #expect(correlator.pendingCountForDiagnostics == 1)
    }

    @Test func alreadyFilledPathDropsWithoutDuplicating() {
        // Redelivery / double-mirror: a Tier-1 chip for the path already
        // exists — the item must neither dup the chip nor land elsewhere.
        let filled = MessageAttachment(
            kind: "file", fileName: "a.txt", mimeType: "text/plain",
            localStoragePath: "/staged/a.txt"
        )
        let transcript = FakeTranscript()
        transcript.mirrorMessages = [
            agentMessage(writePaths: ["notes/a.txt"], attachments: [filled])
        ]
        let correlator = correlator(transcript)
        correlator.receive(mirrorItem())
        #expect(transcript.mirrorMessages[0].attachments.count == 1)
        #expect(transcript.mirrorMessages[0].attachments.first?.id == filled.id)
        #expect(transcript.persistCount == 0)
    }

    @Test func expiryYieldsToASameRetryMatch() {
        // Pin the retry order: attach gets first claim, expiry only claims
        // items that STILL don't match. An exact session+path match is never
        // a wrong-message risk, so the window is hygiene, not correctness.
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let transcript = FakeTranscript()
        let correlator = correlator(transcript, holdWindow: 600, clock: { now })
        correlator.receive(mirrorItem())  // no messages at all yet → held
        #expect(correlator.pendingCountForDiagnostics == 1)

        now = now.addingTimeInterval(601)
        transcript.mirrorMessages = [agentMessage(writePaths: ["notes/a.txt"])]
        correlator.retryPending()
        #expect(transcript.mirrorMessages[0].attachments.count == 1)
        #expect(correlator.pendingCountForDiagnostics == 0)
    }

    @Test func expiryDropsAnItemThatStillHasNoMatch() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let transcript = FakeTranscript()
        let correlator = correlator(transcript, holdWindow: 600, clock: { now })
        correlator.receive(mirrorItem())
        now = now.addingTimeInterval(601)
        correlator.retryPending()
        #expect(correlator.pendingCountForDiagnostics == 0)

        // The thread appears later — too late; nothing may attach now.
        transcript.mirrorMessages = [agentMessage(writePaths: ["notes/a.txt"])]
        correlator.retryPending()
        #expect(transcript.mirrorMessages[0].attachments.isEmpty)
    }

    @Test func heldItemAttachesWhenTheActivityArrives() {
        // 3D-D early-arrival: HUB.wake often lands the drain before the app
        // has processed the tool.started frame.
        let transcript = FakeTranscript()
        let correlator = correlator(transcript)
        correlator.receive(mirrorItem())
        #expect(correlator.pendingCountForDiagnostics == 1)

        transcript.mirrorMessages = [agentMessage(writePaths: ["notes/a.txt"])]
        correlator.retryPending()
        #expect(transcript.mirrorMessages[0].attachments.count == 1)
        #expect(correlator.pendingCountForDiagnostics == 0)
    }

    @Test func heldItemAttachesWhenItsThreadOpens() {
        // 3D-D cross-thread: drained while another thread was open, attaches
        // when the matching thread is opened within the hold window.
        let transcript = FakeTranscript(sessionID: "OTHER")
        let correlator = correlator(transcript)
        correlator.receive(mirrorItem(session: "s1"))
        #expect(correlator.pendingCountForDiagnostics == 1)

        transcript.mirrorSessionID = "s1"
        transcript.mirrorMessages = [agentMessage(writePaths: ["notes/a.txt"])]
        correlator.retryPending()
        #expect(transcript.mirrorMessages[0].attachments.count == 1)
    }

    @Test func userMessagesAreNeverMatchTargets() {
        var userMessage = Message(sender: .user, content: "wrote a")
        userMessage.toolActivities = [
            ToolActivity(
                id: UUID(), label: "write_file", startedAt: Date(),
                isActive: false, detail: "notes/a.txt", anchorOffset: 0
            )
        ]
        let transcript = FakeTranscript()
        transcript.mirrorMessages = [userMessage]
        let correlator = correlator(transcript)
        correlator.receive(mirrorItem())
        #expect(transcript.mirrorMessages[0].attachments.isEmpty)
        #expect(correlator.pendingCountForDiagnostics == 1)
    }

    @Test func pendingBufferIsBounded() {
        let transcript = FakeTranscript(sessionID: nil)
        let correlator = correlator(transcript)
        for index in 0..<(ArtifactMirrorCorrelator.maxPending + 5) {
            correlator.receive(mirrorItem(path: "p\(index).txt", id: "i\(index)"))
        }
        #expect(correlator.pendingCountForDiagnostics == ArtifactMirrorCorrelator.maxPending)
    }
}
