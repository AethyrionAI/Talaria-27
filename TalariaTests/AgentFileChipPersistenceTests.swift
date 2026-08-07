import Foundation
import Testing
@testable import Talaria

/// #277 — agent-written file chips (#21 Tier 1) must survive LEAVING a thread
/// and coming back, not just a relaunch into the same thread.
///
/// The defect these pins were written against: `ChatStore.openSession` is a
/// straight ASSIGNMENT of the fetched conversation, so `mergeConversationMetadata`
/// — the only thing that preserves client-side fields — is never reached on
/// that path; the server transcript rebuilds `toolActivities` from its stored
/// tool calls but carries no attachments (the stored call decodes `name` and
/// `detail`, never `args`/`content`); and the conversation cache is a SINGLE
/// SLOT, so opening any other thread evicts the previous thread's rows. The
/// fingerprint is the asymmetry Owen reported on three threads: **the
/// write_file CARD survives and the CHIP does not.**
///
/// The bytes were never lost — staged files sit under Application Support and
/// nothing prunes them. Only the `MessageAttachment` RECORD went missing, and
/// this lane makes that record durable per thread.
struct AgentFileChipPersistenceTests {

    // MARK: - Fixtures

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "agent-chip-persistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// A Tier-1 staged agent file — the value `SessionsHermesClient.parseWrittenFile`
    /// yields when `write_file`'s args carried the content.
    private static func stagedFile(named name: String) -> MessageAttachment {
        MessageAttachment(
            kind: "file",
            fileName: name,
            mimeType: "text/markdown",
            localStoragePath: "/tmp/talaria-agent-files/\(name)"
        )
    }

    /// The client double, shaped to the two facts that produce the defect:
    ///
    /// 1. A live turn announces the written file mid-stream (`.artifactProduced`,
    ///    #258) and the store anchors the chip on the streaming placeholder —
    ///    the placeholder's id is CLIENT-minted.
    /// 2. `openSession` returns what the SERVER stores: the same prose, a
    ///    `write_file` tool activity, **no attachments**, and — mirroring #237's
    ///    stable identity — a message id derived from the server row, which is
    ///    NOT the client-minted one. That id change across the refetch boundary
    ///    is why the sidecar cannot key on message id alone.
    ///
    /// It also begins a journal hop the way `SessionsHermesClient` does, so the
    /// store learns the thread's server session id exactly where production
    /// learns it — a NEW chat never goes through `openSession`, which is the
    /// path 277-C walks.
    @MainActor
    private final class AgentFileClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        /// Server session id this client mints for the live thread.
        var liveSessionID = "api_live"
        /// What each openSession id returns — the host's stored transcript.
        var storedTranscripts: [String: Conversation] = [:]
        /// Chips the next turn announces, in order.
        var artifacts: [MessageAttachment] = []
        var replyText = "Wrote the report."
        private let journal: ConversationJournalStore?

        init(journal: ConversationJournalStore?) {
            self.journal = journal
        }

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: replyText, status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            // What the Sessions client does when it creates or reuses the
            // server session behind this turn: the hop IS the thread's id.
            journal?.beginHop(apiSessionId: liveSessionID, primingUsage: nil)
            let artifacts = self.artifacts
            let reply = Message(sender: .hermes, content: replyText, status: .delivered)
            return AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                for artifact in artifacts {
                    continuation.yield(.artifactProduced(artifact))
                }
                continuation.yield(.finished(reply, nil, nil))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            if let currentConversation { return currentConversation }
            let fresh = Conversation(title: Conversation.defaultTitle)
            currentConversation = fresh
            return fresh
        }

        func clearConversation() async throws -> Conversation {
            let fresh = Conversation(title: Conversation.defaultTitle)
            currentConversation = fresh
            return fresh
        }

        func openSession(_ id: String) async throws -> Conversation {
            guard let stored = storedTranscripts[id] else {
                return Conversation(title: Conversation.defaultTitle)
            }
            // The server transcript is authoritative and is re-mapped fresh on
            // every fetch — hand back a copy so a caller can never mutate the
            // host's "stored" rows through this reference.
            return stored
        }
    }

    /// The server's stored form of an assistant row that wrote a file: prose
    /// plus a `write_file` activity, and **no attachments** (bar 277-B pins
    /// that this is the real mapping, not a fixture convenience).
    private static func storedAssistantRow(
        content: String,
        sessionID: String,
        serverRowID: Int
    ) -> Message {
        Message(
            id: SessionsHermesClient.stableMessageID(sessionId: sessionID, serverRowID: serverRowID),
            sender: .hermes,
            content: content,
            timestamp: Date(timeIntervalSince1970: 1_754_500_000 + Double(serverRowID)),
            status: .delivered,
            toolActivities: [ToolActivity(label: "write_file", startedAt: .now, isActive: false, detail: "report.md")]
        )
    }

    private static func storedUserRow(
        content: String,
        sessionID: String,
        serverRowID: Int
    ) -> Message {
        Message(
            id: SessionsHermesClient.stableMessageID(sessionId: sessionID, serverRowID: serverRowID),
            sender: .user,
            content: content,
            timestamp: Date(timeIntervalSince1970: 1_754_500_000 + Double(serverRowID)),
            status: .delivered
        )
    }

    /// A store wired the way production wires it — real persistence, a real
    /// journal (the sidecar's thread key comes from its hop on a NEW chat).
    @MainActor
    private func makeStore() -> (ChatStore, AgentFileClient, UserDefaultsAppPersistenceStore) {
        let persistence = makePersistence()
        let journal = ConversationJournalStore(persistence: persistence)
        let client = AgentFileClient(journal: journal)
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        return (store, client, persistence)
    }

    // MARK: - 277-A: the chip survives leaving the thread

    /// **277-A** — Owen's 277-C device bar, in units: a NEW chat produces a
    /// file chip, the user opens a DIFFERENT conversation from the drawer
    /// (which evicts the single-slot cache), and returns. The chip is still
    /// on the reply.
    ///
    /// Fails today with `attachments == []`: `openSession` assigns the server
    /// transcript, which never carried the attachment.
    @Test @MainActor
    func agentFileChipSurvivesLeavingAndReturningToTheThread() async throws {
        let (store, client, _) = makeStore()
        let chip = Self.stagedFile(named: "report.md")
        client.artifacts = [chip]
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()

        await store.sendMessage("Write me a report")
        // Pre-condition: the chip is on the reply while the thread is live.
        #expect(store.conversation?.messages.last?.attachments.count == 1)

        // The host's stored form of the SAME thread — prose + the write_file
        // card, no attachments, server-derived ids.
        client.storedTranscripts["api_A"] = Conversation(title: "Report", messages: [
            Self.storedUserRow(content: "Write me a report", sessionID: "api_A", serverRowID: 1),
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_A", serverRowID: 2),
        ])
        client.storedTranscripts["api_B"] = Conversation(title: "Other", messages: [
            Self.storedUserRow(content: "Unrelated", sessionID: "api_B", serverRowID: 1),
            Message(sender: .hermes, content: "Unrelated answer", status: .delivered),
        ])

        // Leave for another thread (this is what evicts the cache slot), then
        // come back.
        await store.openSession("api_B")
        await store.openSession("api_A")

        let reply = try #require(store.conversation?.messages.last)
        #expect(reply.sender == .hermes)
        #expect(reply.attachments.count == 1)
        #expect(reply.attachments.first?.fileName == "report.md")
        #expect(reply.attachments.first?.localStoragePath == "/tmp/talaria-agent-files/report.md")
        // The write_file CARD was never the broken half — it must still be
        // there too, so the fix is "card AND chip", not "chip instead".
        #expect(reply.toolActivities.count == 1)
    }

    /// The chip's INLINE placement (#262) has to come back with it — a
    /// restored chip demoted to the trailing grid is the #276 jump, arriving
    /// by a different road.
    @Test @MainActor
    func restoredChipKeepsItsInlineAnchor() async throws {
        let (store, client, _) = makeStore()
        client.artifacts = [Self.stagedFile(named: "report.md")]
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()
        await store.sendMessage("Write me a report")
        let liveAnchor = store.conversation?.messages.last?.attachments.first?.anchorOffset

        client.storedTranscripts["api_A"] = Conversation(title: "Report", messages: [
            Self.storedUserRow(content: "Write me a report", sessionID: "api_A", serverRowID: 1),
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_A", serverRowID: 2),
        ])
        await store.openSession("api_B")
        await store.openSession("api_A")

        let restored = try #require(store.conversation?.messages.last?.attachments.first)
        #expect(restored.anchorOffset == liveAnchor)
    }

    /// The second return matches by MESSAGE ID, not by content: the first
    /// restore re-files the record under the server's stable row identity
    /// (#237), so the content tier is needed exactly once — on the first
    /// crossing of the client-id → server-id boundary.
    ///
    /// Pinned by rewriting the stored prose after the first return: a
    /// content-only key would lose the chip; the id key holds it.
    @Test @MainActor
    func returningTwiceMatchesByServerRowIdentity() async throws {
        let (store, client, _) = makeStore()
        client.artifacts = [Self.stagedFile(named: "report.md")]
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()
        await store.sendMessage("Write me a report")

        client.storedTranscripts["api_A"] = Conversation(title: "Report", messages: [
            Self.storedUserRow(content: "Write me a report", sessionID: "api_A", serverRowID: 1),
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_A", serverRowID: 2),
        ])
        await store.openSession("api_B")
        await store.openSession("api_A")

        // Same server row, different prose — only the stable id can pair them.
        client.storedTranscripts["api_A"] = Conversation(title: "Report", messages: [
            Self.storedUserRow(content: "Write me a report", sessionID: "api_A", serverRowID: 1),
            Self.storedAssistantRow(content: "Wrote the report (edited).", sessionID: "api_A", serverRowID: 2),
        ])
        await store.openSession("api_B")
        await store.openSession("api_A")

        let reply = try #require(store.conversation?.messages.last)
        #expect(reply.content == "Wrote the report (edited).")
        #expect(reply.attachments.count == 1)
    }

    /// Returning twice must not DOUBLE the chip — replay is idempotent by
    /// attachment id, the same rule `.artifactProduced` and the finish merge
    /// already use (#258).
    @Test @MainActor
    func replayIsIdempotentAcrossRepeatedReturns() async throws {
        let (store, client, _) = makeStore()
        client.artifacts = [Self.stagedFile(named: "report.md")]
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()
        await store.sendMessage("Write me a report")

        client.storedTranscripts["api_A"] = Conversation(title: "Report", messages: [
            Self.storedUserRow(content: "Write me a report", sessionID: "api_A", serverRowID: 1),
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_A", serverRowID: 2),
        ])
        for _ in 0 ..< 3 {
            await store.openSession("api_B")
            await store.openSession("api_A")
        }

        #expect(store.conversation?.messages.last?.attachments.count == 1)
    }

    /// Two replies with IDENTICAL prose, each with its own file: the records
    /// must pair one-to-one, not both alias the first row. Same dequeue-
    /// counting rule as `mergeAttachments` (#185) and `unconfirmedLocalMessages`
    /// (#248) — a content claim is spent when it is used.
    @Test @MainActor
    func identicalRepliesEachKeepTheirOwnChip() async throws {
        let (store, client, _) = makeStore()
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()

        client.artifacts = [Self.stagedFile(named: "first.md")]
        await store.sendMessage("Write it")
        client.artifacts = [Self.stagedFile(named: "second.md")]
        await store.sendMessage("Again please")

        client.storedTranscripts["api_A"] = Conversation(title: "Report", messages: [
            Self.storedUserRow(content: "Write it", sessionID: "api_A", serverRowID: 1),
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_A", serverRowID: 2),
            Self.storedUserRow(content: "Again please", sessionID: "api_A", serverRowID: 3),
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_A", serverRowID: 4),
        ])
        await store.openSession("api_B")
        await store.openSession("api_A")

        let messages = try #require(store.conversation?.messages)
        let replies = messages.filter { $0.sender == .hermes }
        #expect(replies.count == 2)
        #expect(replies.first?.attachments.map(\.fileName) == ["first.md"])
        #expect(replies.last?.attachments.map(\.fileName) == ["second.md"])
    }

    /// A thread with no records of its own is untouched — no chip leaks from
    /// the thread next door. The sidecar is keyed per session id, and the
    /// single-slot cache's eviction is what made cross-thread leakage the
    /// hazard worth pinning.
    @Test @MainActor
    func aThreadWithoutRecordsGetsNoChips() async throws {
        let (store, client, _) = makeStore()
        client.artifacts = [Self.stagedFile(named: "report.md")]
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()
        await store.sendMessage("Write me a report")

        client.storedTranscripts["api_B"] = Conversation(title: "Other", messages: [
            Self.storedUserRow(content: "Write me a report", sessionID: "api_B", serverRowID: 1),
            // Byte-identical prose to thread A's reply: content alone must
            // never be enough to claim a record across threads.
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_B", serverRowID: 2),
        ])
        await store.openSession("api_B")

        #expect(store.conversation?.messages.allSatisfy { $0.attachments.isEmpty } == true)
    }

    /// Privacy: `reset()` (unpair / sign-out) clears the conversation cache,
    /// and the sidecar — file names and staged paths of everything the agent
    /// wrote — must go with it, not outlive the pairing that produced it.
    ///
    /// Passes pre-fix for the trivial reason that nothing survived at all;
    /// it earns its keep afterwards.
    @Test @MainActor
    func resetClearsTheSidecar() async throws {
        let (store, client, _) = makeStore()
        client.artifacts = [Self.stagedFile(named: "report.md")]
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()
        await store.sendMessage("Write me a report")

        store.reset()

        client.storedTranscripts["api_A"] = Conversation(title: "Report", messages: [
            Self.storedUserRow(content: "Write me a report", sessionID: "api_A", serverRowID: 1),
            Self.storedAssistantRow(content: "Wrote the report.", sessionID: "api_A", serverRowID: 2),
        ])
        await store.openSession("api_A")

        #expect(store.conversation?.messages.last?.attachments.isEmpty == true)
    }

    // MARK: - Why the "cheap intermediate" was NOT taken

    /// #277 floated routing `openSession` through `mergeConversationMetadata`
    /// as a cheap first step. **It is not safe, and this pin is why.**
    ///
    /// The merge is built for two views of ONE thread. On `openSession` the
    /// local conversation is a DIFFERENT thread, so every merge rule inverts:
    /// `unconfirmedLocalMessages` (#248) re-appends every departing row the
    /// arriving transcript "hasn't echoed" — i.e. all of them — smearing
    /// thread A into thread B; the P1/#90 identity rule hands the arriving
    /// thread the DEPARTING conversation's UUID, which is what the journal
    /// hop and the per-conversation brain pins (#27) key on; and the #4.8
    /// title rule keeps the departing thread's title because the fetched one
    /// is the placeholder.
    ///
    /// So the durable sidecar is the whole fix, and `openSession` stays an
    /// assignment. If a later lane reaches for the merge here, this pin fails
    /// first.
    @Test @MainActor
    func openSessionDoesNotAdoptTheDepartingThreadsRowsTitleOrIdentity() async throws {
        let (store, client, _) = makeStore()
        client.liveSessionID = "api_A"
        await store.loadConversationIfNeeded()
        await store.sendMessage("Thread A question")
        let departingID = try #require(store.conversation?.id)

        client.storedTranscripts["api_B"] = Conversation(title: "Thread B", messages: [
            Self.storedUserRow(content: "Thread B question", sessionID: "api_B", serverRowID: 1),
            Self.storedAssistantRow(content: "Thread B answer.", sessionID: "api_B", serverRowID: 2),
        ])
        await store.openSession("api_B")

        let opened = try #require(store.conversation)
        #expect(opened.messages.count == 2)
        #expect(opened.messages.allSatisfy { !$0.content.contains("Thread A") })
        #expect(opened.title == "Thread B")
        #expect(opened.id != departingID)
    }

    // MARK: - 277-B: the server mapping carries the card, never the chip

    /// **277-B** — the asymmetry, pinned against the REAL decode + map path so
    /// the next reader does not have to rediscover it from a device report.
    ///
    /// `GET /api/sessions/{id}/messages` stores a tool call as name + preview
    /// only: no `args`, no `content`. So a resumed `write_file` row yields the
    /// CARD (one tool activity) and can never yield the CHIP. That is not a
    /// bug in the mapping — the attachment is a client-side reconstruction
    /// (#21 Tier 1) that never round-trips — and it is exactly why the fix is
    /// a client-side sidecar rather than a decode change. This pin passes
    /// before and after the fix by design; it fails only if someone teaches
    /// the mapper to invent attachments.
    @Suite(.serialized)
    struct StoredWriteFileRowMappingTests {

        private final class MessagesStubProtocol: URLProtocol, @unchecked Sendable {
            nonisolated(unsafe) static var body = ""

            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

            override func startLoading() {
                let url = request.url ?? URL(string: "http://hermes.test")!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }

            override func stopLoading() {}
        }

        @Test @MainActor
        func storedWriteFileRowYieldsTheCardAndNoAttachment() async throws {
            let suiteName = "stored-write-file-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MessagesStubProtocol.self]
            let session = URLSession(configuration: configuration)
            // The probed stored shape: tool_calls carry name + preview only.
            MessagesStubProtocol.body = #"""
            {"session_id":"api_sess","data":[
            {"id":1,"role":"user","content":"Write me a report","timestamp":1754500000.0},
            {"id":2,"role":"assistant","content":"Wrote the report.","timestamp":1754500005.0,
             "tool_calls":[{"tool_name":"write_file","preview":"O:\\Hermes\\report.md"}]}
            ]}
            """#
            defer { MessagesStubProtocol.body = "" }

            let client = SessionsHermesClient(
                baseURLProvider: { "http://hermes.test" },
                apiKeyProvider: { "test-key" },
                journal: ConversationJournalStore(persistence: persistence),
                transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
                session: session
            )
            let messages = try await client.openSession("api_sess").messages

            let assistant = try #require(messages.last)
            #expect(assistant.sender == .hermes)
            // The CARD survives the round trip…
            #expect(assistant.toolActivities.count == 1)
            #expect(assistant.toolActivities.first?.label == "write_file")
            #expect(assistant.toolActivities.first?.detail == #"O:\Hermes\report.md"#)
            // …and the CHIP cannot: no args, no content, nothing to stage.
            #expect(assistant.attachments.isEmpty)
        }
    }
}
