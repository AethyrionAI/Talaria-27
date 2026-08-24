import Foundation
import Testing
@testable import Talaria

/// #258 Task 1 — agent-written files reach the transcript WHILE the turn is
/// still streaming. Before this lane the client accumulated `write_file`
/// reconstructions into a local `producedFiles` array and only assigned them
/// at `run.completed`, so the openable chip appeared a whole turn late (the
/// tool pill was live, the artifact was not).
///
/// Two halves are pinned here:
///  * the wire half — a streamed `tool.started` write yields
///    `.artifactProduced` BEFORE `.finished`, and the same attachment (same
///    id) is still the one the final message carries;
///  * the store half — the placeholder renders it mid-turn, and the
///    `run.completed` assign merges rather than duplicates (bar 258-A:
///    exactly one chip per file).
@Suite(.serialized)
struct ArtifactStreamingTests {

    // MARK: - Fixtures

    @MainActor
    private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "artifact-stream-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    @MainActor

    private func removeStaged(_ attachments: [MessageAttachment]) {
        for attachment in attachments {
            if let path = attachment.localStoragePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }
    // #382 TOMBSTONE: the two WIRE tests that led this file
    // (streamedWriteYieldsTheArtifactBeforeTheTurnFinishes,
    // twoWritesToTheSamePathStreamTwoDistinctArtifacts) drove the
    // sessions-plane SSE parser's Tier-1 reconstruction — write_file args
    // lifted off `tool.started` frames. They stayed green after #368's
    // cutover only because their bare test client rode the transport seam's
    // conservative `{ false }` default onto the legacy plane; #382 deleted
    // the plane, the parser, and the default. On the runs plane the stream
    // deliberately carries no args — the plugin's artifact MIRROR delivers
    // the bytes instead, pinned by
    // `mirrorItemChipsTheRunsPlaneWriteWithoutAPointer` (+RunsTransport
    // tests, #375). The store-half tests below are transport-independent
    // and unchanged.

    // MARK: - Store: the placeholder renders it mid-turn, once

    /// Yields the scripted artifacts, then pumps (bounded) until the store's
    /// placeholder has drained them, snapshots what the transcript looked like
    /// mid-turn, and only then yields `.finished`. The pump is bounded on
    /// purpose — a stranded waiter would hang the suite rather than fail it.
    @MainActor
    private final class ArtifactStreamClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var streamedArtifacts: [MessageAttachment] = []
        var finalAttachments: [MessageAttachment] = []
        weak var store: ChatStore?

        private(set) var midTurnAttachmentIDs: [UUID] = []
        private(set) var midTurnWasStreaming = false

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            AsyncStream { continuation in
                Task { @MainActor in
                    continuation.yield(.messageSent(jobID: UUID()))
                    continuation.yield(.textDelta("Writing the file."))
                    for artifact in self.streamedArtifacts {
                        continuation.yield(.artifactProduced(artifact))
                    }
                    for _ in 0 ..< 500 {
                        if self.placeholderAttachmentIDs().count >= self.streamedArtifacts.count { break }
                        await Task.yield()
                    }
                    self.midTurnAttachmentIDs = self.placeholderAttachmentIDs()
                    self.midTurnWasStreaming = self.store?.streamingMessageID != nil
                    let final = Message(
                        sender: .hermes,
                        content: "Writing the file.",
                        status: .delivered,
                        attachments: self.finalAttachments
                    )
                    continuation.yield(.finished(final, nil, nil))
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }

        private func placeholderAttachmentIDs() -> [UUID] {
            guard let id = store?.streamingMessageID,
                  let message = store?.conversation?.messages.first(where: { $0.id == id })
            else { return [] }
            return message.attachments.map(\.id)
        }
    }

    @MainActor
    private func makeStore(
        streamed: [MessageAttachment],
        final: [MessageAttachment],
        label: String
    ) -> (ChatStore, ArtifactStreamClient) {
        let client = ArtifactStreamClient()
        client.streamedArtifacts = streamed
        client.finalAttachments = final
        let store = ChatStore(hermesClient: client, persistence: makePersistence(label))
        client.store = store
        return (store, client)
    }

    private func makeStagedAttachment(named name: String, content: String) throws -> MessageAttachment {
        try #require(MessageAttachment.agentFile(remotePath: "O:\\Hermes\\\(name)", content: content))
    }

    @Test @MainActor
    func artifactRendersOnThePlaceholderWhileTheTurnIsStillStreaming() async throws {
        let artifact = try makeStagedAttachment(named: "out.md", content: "# Report")
        defer { removeStaged([artifact]) }
        let (store, client) = makeStore(streamed: [artifact], final: [artifact], label: "mid-turn")

        await store.sendMessage("Write it")

        // Mid-turn: the chip was on the still-streaming placeholder.
        #expect(client.midTurnWasStreaming)
        #expect(client.midTurnAttachmentIDs == [artifact.id])

        // Bar 258-A: the `run.completed` assign carries the same file — one chip.
        let reply = try #require(store.conversation?.messages.last(where: { $0.sender == .hermes }))
        #expect(reply.attachments.count == 1)
        #expect(reply.attachments.first?.id == artifact.id)
        #expect(!reply.isStreaming)
    }

    @Test @MainActor
    func finalListLeadsAndStreamedOnlyArtifactsAreKeptNotDropped() async throws {
        // The `run.completed` list is the source of truth and leads the order
        // (it is what appends the Tier 2 fetchables). Anything the stream
        // delivered that the final message doesn't carry is appended, not
        // silently dropped — the user watched that chip appear.
        let streamedOnly = try makeStagedAttachment(named: "scratch.md", content: "scratch")
        let fromRunCompleted = try makeStagedAttachment(named: "final.md", content: "final")
        defer { removeStaged([streamedOnly, fromRunCompleted]) }
        let (store, _) = makeStore(
            streamed: [streamedOnly],
            final: [fromRunCompleted],
            label: "streamed-only"
        )

        await store.sendMessage("Write it")

        let reply = try #require(store.conversation?.messages.last(where: { $0.sender == .hermes }))
        #expect(reply.attachments.map(\.id) == [fromRunCompleted.id, streamedOnly.id])
    }

    @Test @MainActor
    func streamedAnchorSurvivesTheFinishMergeLeadList() async throws {
        // 262-C: ChatStore stamps the content length at `.artifactProduced`
        // ("Writing the file." = 17 chars streamed first); the final message's
        // same-id twin carries no anchor. The lead-list dedupe must resolve to
        // ONE row that keeps the STREAMED anchor — losing it would drop the
        // chip to the trailing grid at the finish boundary, the exact jump
        // this lane removes.
        let artifact = try makeStagedAttachment(named: "anchored.md", content: "# Report")
        defer { removeStaged([artifact]) }
        let (store, _) = makeStore(streamed: [artifact], final: [artifact], label: "anchor-merge")

        await store.sendMessage("Write it")

        let reply = try #require(store.conversation?.messages.last(where: { $0.sender == .hermes }))
        #expect(reply.attachments.count == 1)
        #expect(reply.attachments.first?.anchorOffset == 17)
    }

    @Test @MainActor
    func finishAddingASecondFileKeepsExactlyOneChipPerFile() async throws {
        // Two files ⇒ two chips, and the one that streamed mid-turn is not
        // duplicated when the finish repeats it. (#375: the second file used
        // to be a Tier 2 fetchable announced in prose; those are gone, so the
        // same merge is exercised with a second staged file — the property
        // under test was never about which tier the newcomer was.)
        let tier1 = try makeStagedAttachment(named: "summary.md", content: "# Sum")
        let second = try makeStagedAttachment(named: "probe.md", content: "probe")
        defer { removeStaged([tier1, second]) }
        let tier2 = second
        let (store, client) = makeStore(streamed: [tier1], final: [tier1, tier2], label: "tier1-plus-second")

        await store.sendMessage("Write it")

        // The Tier 1 chip was already on screen before the fetchable joined it.
        #expect(client.midTurnAttachmentIDs == [tier1.id])
        let reply = try #require(store.conversation?.messages.last(where: { $0.sender == .hermes }))
        #expect(reply.attachments.map(\.id) == [tier1.id, tier2.id])
        // And the settled transcript persisted with both chips intact.
        let cached = try #require(store.persistence.loadConversationCache())
        let cachedReply = try #require(cached.messages.last(where: { $0.sender == .hermes }))
        #expect(cachedReply.attachments.count == 2)
    }
}
