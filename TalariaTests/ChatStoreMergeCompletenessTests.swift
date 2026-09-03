import Foundation
import Testing
@testable import Talaria

/// #422 final review, C1 — **the merge is where client-only fields go to die,
/// and this suite is the alarm.**
///
/// `ChatStore.mergeConversationMetadata` rebuilds the conversation from the
/// backend's own transcript and then carries the client-only `Message` fields
/// across ONE AT A TIME. A field the loop does not name is silently dropped —
/// on the settle itself (the merge runs on the statement after the stamp) and
/// again on every poll, refresh and reopen.
///
/// That is not hypothetical. `memoryProvenance` shipped through a whole lane
/// and a fix round in exactly that state: stamped correctly, pinned by four
/// tests, and erased microseconds later in production. The pins passed because
/// their fake clients never populated `currentConversation`, so the merge
/// returned early and handed back the stamped copy — a green suite over a chip
/// that could not render.
///
/// So there are two checks here, and neither is sufficient alone:
///
///  1. **Completeness** — every `Message.CodingKeys` case is either declared
///     server-owned or named in the carry loop's source. This is the #289
///     shape one level down: it cannot go stale silently, because a new field
///     fails it until someone decides which list it belongs in.
///  2. **Behaviour** — `ChatStoreMemoryProvenanceMergeTests` (below) drives a
///     real settle against a client that DOES populate
///     `currentConversation`, which is the shape the earlier pins were
///     missing.
@Suite("422-C1 merge completeness")
struct ChatStoreMergeCompletenessTests {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
    }

    /// Fields the SERVER transcript owns: the refreshed row's own value is
    /// authoritative, so the merge has nothing to carry. Adding a case here is
    /// a claim — "a refresh legitimately re-supplies this" — and it should be
    /// made deliberately, in a review, rather than by a loop that quietly
    /// forgot a field.
    private static let serverOwned: Set<String> = [
        "id", "clientMessageID", "sender", "content", "timestamp", "jobID",
        "status", "hostReportedFailure", "brain", "isContextPriming",
        "voiceSessionDuration",
    ]

    /// Fields the merge must carry from the local row. Each one is also
    /// required to APPEAR in the merge function's source below — a list that
    /// only agreed with itself would pass while the loop dropped everything.
    private static let carriedByMerge: Set<String> = [
        "toolActivities", "reasoning", "reasoningSummary",
        "usage", "turnDuration", "servingModel", "attachments",
        "memoryProvenance",
    ]

    /// Client-only fields the merge carries that are **not `CodingKeys` at
    /// all** — so they do not survive a conversation-cache reload either way.
    ///
    /// This list exists because the first run of the check above found them:
    /// `codeDiff` and `toolActivity` were classified as carried, and the
    /// phantom arm correctly reported that `Message` has no such coding keys.
    /// They are real merge behaviour and a real persistence gap, and pretending
    /// either half away would make this suite the thing it is guarding against.
    /// Checked against the merge SOURCE, and asserted to be absent from
    /// `CodingKeys`, so the day one of them becomes persisted this list is what
    /// goes red.
    private static let carriedButNotPersisted: Set<String> = ["codeDiff", "toolActivity"]

    /// Client-only fields that are neither coding keys NOR carried by the
    /// merge — named here so "unclassified" means "nobody has looked at it"
    /// rather than "we ran out of lists".
    ///
    /// `isStreaming` is transient by design: a reloaded row is not streaming.
    /// **`recoveredForPrompt` is a real gap, filed rather than fixed here** —
    /// it is client-only and IS dropped by a refresh, which is the #235 family
    /// one level down and outside this lane's scope. Writing it down is the
    /// point: the field was invisible to every check in the repo until this
    /// suite enumerated `Message`.
    private static let notPersistedAndNotCarried: Set<String> = ["recoveredForPrompt", "isStreaming"]

    /// The body of `mergeConversationMetadata`, as text.
    private static func mergeSource() throws -> String {
        let path = repoRoot.appendingPathComponent("Talaria/Stores/ChatStore.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        let marker = "private func mergeConversationMetadata("
        let start = try #require(source.range(of: marker),
                                 "mergeConversationMetadata was renamed — this check did not run")
        let rest = source[start.upperBound...]
        // Up to the next member at the same indentation — the EARLIEST of
        // them, not the first marker that happens to match. Two markers were
        // not enough: `nonisolated` and `static` members also end the function,
        // and missing one lets the "body" run on into unrelated code, where a
        // field name can appear for reasons that have nothing to do with the
        // merge. An over-reaching extract makes this check pass by accident.
        let end = ["\n    private func ", "\n    func ", "\n    nonisolated ", "\n    static ",
                   "\n    private static ", "\n    private var ", "\n    var "]
            .compactMap { rest.range(of: $0)?.lowerBound }
            .min()
        return String(end.map { rest[..<$0] } ?? rest)
    }

    /// **Every field is accounted for.** A new `Message` field fails here until
    /// it is placed in one of the two lists — which is the point: the decision
    /// is forced into a review instead of being made by omission.
    @Test func everyMessageFieldIsEitherServerOwnedOrCarriedByTheMerge() throws {
        let all = Set(Message.CodingKeys.allCases.map(\.stringValue))
        let classified = Self.serverOwned.union(Self.carriedByMerge)

        let unclassified = all.subtracting(classified)
        #expect(unclassified.isEmpty, """
            new Message field(s) \(unclassified.sorted()) are in neither list — decide whether \
            the server re-supplies them or the merge must carry them, or they will be dropped \
            on the next refresh exactly as memoryProvenance was
            """)

        let phantom = classified.subtracting(all)
        #expect(phantom.isEmpty,
                "these lists name field(s) Message no longer has: \(phantom.sorted())")
    }

    /// **And the "carried" list is not merely a list.** Every name in it must
    /// appear in the merge function's own source, so the classification is a
    /// claim about the code rather than about a constant in this file.
    @Test func everyCarriedFieldIsNamedInTheMergeItself() throws {
        let source = try Self.mergeSource()
        #expect(source.count > 500, "the extracted merge body is implausibly short — check the markers")

        for field in Self.carriedByMerge.union(Self.carriedButNotPersisted).sorted() {
            #expect(source.contains(field), """
                \(field) is listed as carried by the merge but does not appear in \
                mergeConversationMetadata — a refresh will drop it
                """)
        }
    }

    /// The inverse, and the one that would have caught C1: no server-owned
    /// field may be one the merge is silently expected to carry. Asserted by
    /// checking the two lists are disjoint — a field in both is a contradiction
    /// nobody would notice by reading them separately.
    @Test func theTwoListsAreDisjoint() {
        let both = Self.serverOwned.intersection(Self.carriedByMerge)
        #expect(both.isEmpty, "field(s) declared both server-owned and carried: \(both.sorted())")
    }

    /// The unpersisted pair really is unpersisted. If one of them gains a
    /// coding key, it must move into `carriedByMerge` — otherwise the
    /// partition above would silently stop covering it.
    @Test func theUnpersistedCarriedFieldsAreStillUnpersisted() {
        let all = Set(Message.CodingKeys.allCases.map(\.stringValue))
        let nowPersisted = Self.carriedButNotPersisted
            .union(Self.notPersistedAndNotCarried)
            .intersection(all)
        #expect(nowPersisted.isEmpty, """
            \(nowPersisted.sorted()) gained a coding key — move it into carriedByMerge so the \
            server-owned/carried partition keeps covering every persisted field
            """)
    }
}

/// #422 final review, C1 — the BEHAVIOURAL half: a settle whose client
/// populates `currentConversation`, which is what production always does and
/// what every earlier provenance pin was missing.
///
/// `ExplicitNoteCaptureTests`' spy leaves `currentConversation` nil, so
/// `mergeConversationMetadata` returns the local conversation untouched and the
/// stamped copy survives by accident. Here the backend supplies its own
/// transcript containing the SAME reply row without the stamp — the shape a
/// real gateway returns, because the stamp is a fact about the phone's memory
/// store that no server has ever heard of. If the merge does not carry the
/// field, the chip is erased on the settle itself.
@Suite("422-C1 provenance survives the merge")
@MainActor
struct ChatStoreMemoryProvenanceMergeTests {

    /// Yields one `.finished` reply AND publishes a backend transcript that
    /// contains the same reply, unstamped — the merge's actual input.
    @MainActor
    private final class MergingClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        private let memoryStore: MemoryStore
        /// What this turn "drew on", recorded against the reply exactly where
        /// `LocalChatBackend.recordMemoryUse` does it.
        var memoryUseToRecord: (entryIDs: [UUID], noteIDs: [UUID])?
        /// Whether to publish a backend transcript at all — the discriminator
        /// between this suite and the older spy-shaped pins.
        var publishesTranscript = true

        init(memoryStore: MemoryStore) { self.memoryStore = memoryStore }

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            let reply = Message(sender: .hermes, content: "Dr. Patel.", status: .delivered)
            if let use = memoryUseToRecord {
                memoryStore.recordUse(replyMessageID: reply.id,
                                      entryIDs: use.entryIDs, noteIDs: use.noteIDs)
            }
            if publishesTranscript {
                // The backend's own view: the same rows, by the same ids, with
                // none of the client-only fields. Set BEFORE `.finished`,
                // because ChatStore merges against it on the next statement.
                currentConversation = Conversation(
                    title: Conversation.defaultTitle,
                    messages: [
                        Message(id: clientMessageID, clientMessageID: clientMessageID,
                                sender: .user, content: message, status: .delivered),
                        Message(id: reply.id, sender: .hermes, content: reply.content,
                                status: .delivered),
                    ])
            }
            return AsyncStream { continuation in
                continuation.yield(.finished(reply, nil, nil))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "provenance-merge-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private func makeStore(_ memory: MemoryStore) -> (ChatStore, MergingClient) {
        let client = MergingClient(memoryStore: memory)
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())
        chatStore.memoryStore = memory
        return (chatStore, client)
    }

    /// **The pin C1 exists for.** Remove the `memoryProvenance` carry from
    /// `mergeConversationMetadata` and this goes red while every spy-based
    /// provenance test stays green — which is exactly how the defect shipped.
    @Test func aStampedReplySurvivesTheBackendTranscriptMerge() async throws {
        let memory = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, client) = makeStore(memory)
        let entryID = UUID()
        client.memoryUseToRecord = (entryIDs: [entryID], noteIDs: [])

        _ = await chatStore.sendMessage("Who is my dentist?")

        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        #expect(reply.memoryProvenance == .local(entryIDs: [entryID], noteIDs: [], savedNoteID: nil),
                """
                the metadata merge rebuilt the reply from the backend's transcript and dropped \
                the stamp — the chip cannot render in production, and no spy-based pin can see it
                """)
    }

    /// A saved note's stamp survives the same merge — the other provenance
    /// shape, and the one a HOST turn produces (no use row, only a note).
    @Test func aSavedNoteStampSurvivesTheMergeToo() async throws {
        let memory = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeStore(memory)

        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")

        let savedID = try #require(memory.allNotes().first?.noteID)
        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        #expect(reply.memoryProvenance == .local(entryIDs: [], noteIDs: [], savedNoteID: savedID))
    }

    /// The control that names the old pins' blind spot out loud: with NO
    /// backend transcript the merge returns early, so the stamp survives even
    /// when the carry is missing. Both arms are asserted so nobody can
    /// "fix" the suite by deleting the transcript from the fixture.
    @Test func withoutABackendTranscriptTheMergeIsNotEvenExercised() async throws {
        let memory = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, client) = makeStore(memory)
        client.publishesTranscript = false
        let entryID = UUID()
        client.memoryUseToRecord = (entryIDs: [entryID], noteIDs: [])

        _ = await chatStore.sendMessage("Who is my dentist?")

        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        #expect(reply.memoryProvenance == .local(entryIDs: [entryID], noteIDs: [], savedNoteID: nil))
        #expect(client.currentConversation == nil,
                "this arm must NOT populate a transcript — it is the weak shape, kept as a control")
    }
}
