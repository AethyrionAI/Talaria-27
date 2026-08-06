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

    private final class ArtifactStubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private static func response(
        for request: URLRequest,
        body: String,
        contentType: String = "application/json"
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        return (response, Data(body.utf8))
    }

    /// Serializes `(event, data)` pairs into an SSE body, with a leading
    /// comment line of padding. The comment is skipped by the parse loop
    /// (`line.hasPrefix(":")`) and exists only so a short fixture body can't
    /// sit under a transport flush threshold.
    private static func sse(_ events: [(event: String, data: String)]) -> String {
        let padding = ": " + String(repeating: "-", count: 600) + "\n\n"
        return padding + events.map { "event: \($0.event)\ndata: \($0.data)\n\n" }.joined()
    }

    @MainActor
    private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "artifact-stream-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    @MainActor
    private func makeClient(persistence: UserDefaultsAppPersistenceStore) -> SessionsHermesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtifactStubURLProtocol.self]
        return SessionsHermesClient(
            baseURLProvider: { "http://ojamd:8642" },
            apiKeyProvider: { "key-test" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: URLSession(configuration: configuration),
            usageIndex: nil
        )
    }

    private static func installHandler(sseBody: String) {
        ArtifactStubURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/sessions" {
                return response(for: request, body: #"{"session": {"id": "api_artifact"}}"#)
            }
            if path.hasSuffix("/chat/stream") {
                return response(for: request, body: sseBody, contentType: "text/event-stream")
            }
            return response(for: request, body: #"{"session_id": "api_artifact", "data": []}"#)
        }
    }

    private func removeStaged(_ attachments: [MessageAttachment]) {
        for attachment in attachments {
            if let path = attachment.localStoragePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    private static func artifactIndices(_ updates: [StreamingUpdate]) -> [Int] {
        updates.indices.filter {
            if case .artifactProduced = updates[$0] { return true }
            return false
        }
    }

    private static func finishedIndex(_ updates: [StreamingUpdate]) -> Int? {
        updates.firstIndex {
            if case .finished = $0 { return true }
            return false
        }
    }

    private static func attachment(at index: Int, in updates: [StreamingUpdate]) -> MessageAttachment? {
        guard case .artifactProduced(let file) = updates[index] else { return nil }
        return file
    }

    // MARK: - Wire: the artifact arrives before the turn finishes

    @Test @MainActor
    func streamedWriteYieldsTheArtifactBeforeTheTurnFinishes() async throws {
        let persistence = makePersistence("before-finish")
        let client = makeClient(persistence: persistence)
        Self.installHandler(sseBody: Self.sse([
            (event: "run.started", data: #"{"run_id":"run_258"}"#),
            (event: "assistant.delta", data: #"{"delta":"Writing it now."}"#),
            (
                event: "tool.started",
                data: ##"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\out.md","content":"# Report"},"preview":"O:\\Hermes\\out.md"}"##
            ),
            (event: "tool.completed", data: #"{}"#),
            (event: "assistant.delta", data: #"{"delta":" Done."}"#),
            (event: "assistant.completed", data: #"{"content":"Writing it now. Done."}"#),
            (event: "run.completed", data: #"{"usage":{"input_tokens":10,"output_tokens":2,"total_tokens":12}}"#),
            (event: "done", data: #"{}"#),
        ]))
        defer { ArtifactStubURLProtocol.requestHandler = nil }

        var updates: [StreamingUpdate] = []
        for await update in client.sendStreaming(message: "Write it", attachments: [], clientMessageID: UUID()) {
            updates.append(update)
        }

        let artifactPositions = Self.artifactIndices(updates)
        #expect(artifactPositions.count == 1)
        let artifactIndex = try #require(artifactPositions.first)
        let finishedIndex = try #require(Self.finishedIndex(updates))
        // The whole point of the lane: the chip is deliverable mid-turn.
        #expect(artifactIndex < finishedIndex)

        let streamed = try #require(Self.attachment(at: artifactIndex, in: updates))
        defer { removeStaged([streamed]) }
        #expect(streamed.fileName == "out.md")
        let stagedPath = try #require(streamed.localStoragePath)
        #expect(FileManager.default.contents(atPath: stagedPath) == Data("# Report".utf8))

        guard case .finished(let message, _, _) = updates[finishedIndex] else {
            Issue.record("Expected a finished update")
            return
        }
        // Bar 258-A on the wire: `run.completed` still owns the final list,
        // and it is the SAME attachment — not a second reconstruction.
        #expect(message.attachments.count == 1)
        #expect(message.attachments.first?.id == streamed.id)
    }

    @Test @MainActor
    func twoWritesToTheSamePathStreamTwoDistinctArtifacts() async throws {
        // Two genuine writes are two events. They keep their own staged bytes
        // and their own identities, in write order — collapsing them would
        // throw away the first version and misreport the turn. This is exactly
        // what `run.completed` already did before the lane; streaming it early
        // changes nothing about the count.
        let persistence = makePersistence("same-path-twice")
        let client = makeClient(persistence: persistence)
        Self.installHandler(sseBody: Self.sse([
            (event: "run.started", data: #"{"run_id":"run_258b"}"#),
            (
                event: "tool.started",
                data: ##"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\notes.md","content":"draft one"}}"##
            ),
            (
                event: "tool.started",
                data: ##"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\notes.md","content":"draft two"}}"##
            ),
            (event: "assistant.completed", data: #"{"content":"Revised."}"#),
            (event: "run.completed", data: #"{}"#),
            (event: "done", data: #"{}"#),
        ]))
        defer { ArtifactStubURLProtocol.requestHandler = nil }

        var updates: [StreamingUpdate] = []
        for await update in client.sendStreaming(message: "Draft it twice", attachments: [], clientMessageID: UUID()) {
            updates.append(update)
        }

        let artifactPositions = Self.artifactIndices(updates)
        #expect(artifactPositions.count == 2)
        let streamed = artifactPositions.compactMap { Self.attachment(at: $0, in: updates) }
        defer { removeStaged(streamed) }
        guard streamed.count == 2 else {
            Issue.record("Expected two streamed artifacts, got \(streamed.count)")
            return
        }
        #expect(streamed.map(\.fileName) == ["notes.md", "notes.md"])
        #expect(streamed[0].id != streamed[1].id)
        #expect(streamed[0].localStoragePath != streamed[1].localStoragePath)
        let firstPath = try #require(streamed[0].localStoragePath)
        let secondPath = try #require(streamed[1].localStoragePath)
        #expect(FileManager.default.contents(atPath: firstPath) == Data("draft one".utf8))
        #expect(FileManager.default.contents(atPath: secondPath) == Data("draft two".utf8))

        let finishedIndex = try #require(Self.finishedIndex(updates))
        guard case .finished(let message, _, _) = updates[finishedIndex] else {
            Issue.record("Expected a finished update")
            return
        }
        // Two chips, not four — the streamed pair IS the final pair.
        #expect(message.attachments.count == 2)
        #expect(message.attachments.map(\.id) == streamed.map(\.id))
    }

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
    func finishAddingAFetchableKeepsExactlyOneChipPerFile() async throws {
        // The real #21 shape: `write_file` streamed a Tier 1 reconstruction and
        // `run.completed` appended a Tier 2 fetchable announced in prose. Two
        // files ⇒ two chips, and the streamed one is not duplicated.
        let tier1 = try makeStagedAttachment(named: "summary.md", content: "# Sum")
        defer { removeStaged([tier1]) }
        let tier2 = MessageAttachment.fetchableAgentFile(
            name: "probe.pdf", remotePath: "probe.pdf", profileID: nil
        )
        let (store, client) = makeStore(streamed: [tier1], final: [tier1, tier2], label: "tier1-plus-tier2")

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
