import Foundation
import SwiftData
import os

// MARK: - Records (#190)

/// One stored standalone session. The transcript is an encoded-`Conversation`
/// blob, NOT a SwiftData relationship — deliberate (#190 Phase 1): `Message`
/// is a rich Codable graph (attachments, tool activities, usage) already
/// proven through the single-slot conversation cache, so the blob restores
/// with exactly the cache's fidelity and evolves with the same decoders; a
/// relationship would mean re-modeling that whole graph as a parallel
/// SwiftData schema for queries nobody runs. Everything the drawer lists is
/// denormalized onto row attributes, so listing never touches a transcript.
@Model
final class LocalSessionRecord {
    // sessionID, not id — a stored `id` would shadow `PersistentModel.id`
    // (PersistentIdentifier); kept unambiguous on purpose.
    @Attribute(.unique) var sessionID: UUID
    var title: String
    var createdAt: Date
    var lastActivity: Date
    var messageCount: Int
    var preview: String?
    var transcriptData: Data

    init(
        sessionID: UUID,
        title: String,
        createdAt: Date,
        lastActivity: Date,
        messageCount: Int,
        preview: String?,
        transcriptData: Data
    ) {
        self.sessionID = sessionID
        self.title = title
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.messageCount = messageCount
        self.preview = preview
        self.transcriptData = transcriptData
    }
}

/// Last-known snapshot of one server-side session (#190 Phase 4) — metadata
/// only, never a transcript. Exists so the drawer can keep Hermes history
/// visible (dimmed, with a reason) after the host stops being configured.
@Model
final class RemoteSessionStubRecord {
    // stubID, not id — same PersistentModel.id shadowing avoidance as above.
    @Attribute(.unique) var stubID: String
    var title: String?
    var preview: String?
    var model: String?
    var source: String?
    var messageCount: Int
    var lastActive: Date?
    var profileID: UUID?
    var profileName: String?

    init(
        stubID: String,
        title: String?,
        preview: String?,
        model: String?,
        source: String?,
        messageCount: Int,
        lastActive: Date?,
        profileID: UUID?,
        profileName: String?
    ) {
        self.stubID = stubID
        self.title = title
        self.preview = preview
        self.model = model
        self.source = source
        self.messageCount = messageCount
        self.lastActive = lastActive
        self.profileID = profileID
        self.profileName = profileName
    }
}

// MARK: - Store

/// The SwiftData-backed `LocalSessionStoring` (#190). Main-actor and
/// synchronous throughout — synchronous by design so persistence can live
/// inside ChatStore's `abandonPendingRun` teardown primitive (#184) instead
/// of re-fragmenting it.
@MainActor
final class SwiftDataLocalSessionStore: LocalSessionStoring {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalSessionStore")

    private let context: ModelContext

    private init(container: ModelContainer) {
        // A PRIVATE context, deliberately NOT `container.mainContext`.
        // mainContext is main-QUEUE-asserting (NSMainQueueConcurrencyType
        // underneath), and on this beta a MainActor Task can execute on a
        // non-main OS thread ("Task N") — every mainContext fetch from the
        // chat screen's async chain then dies in CoreData's thread assert as
        // a silent SIGTRAP (verified live in lldb; the identical fetch on
        // the true main thread succeeds). This store is @MainActor, so all
        // access is serial — actor confinement, not queue assertion, is the
        // safety here. Saves are explicit throughout (`saveContext`), so
        // mainContext's autosave is not missed.
        self.context = ModelContext(container)
    }

    /// Nil when the container cannot be created — callers degrade to the
    /// pre-#190 single-slot behavior rather than crashing at boot.
    ///
    /// Everything here is pinned EXPLICITLY rather than left `.automatic`:
    /// this store is app-private by design (nothing outside the app target
    /// reads it), so `groupContainer: .none` keeps it out of the widget app
    /// group — which the unsigned `CODE_SIGNING_ALLOWED=NO` test host cannot
    /// access anyway — and `cloudKitDatabase: .none` pins off CloudKit
    /// resolution. Named store, not `default.store`, so any future SwiftData
    /// user in this app can't collide with it.
    static func make(inMemoryOnly: Bool = false) -> SwiftDataLocalSessionStore? {
        do {
            let schema = Schema([LocalSessionRecord.self, RemoteSessionStubRecord.self])
            let configuration = ModelConfiguration(
                "TalariaLocalSessions",
                schema: schema,
                isStoredInMemoryOnly: inMemoryOnly,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return SwiftDataLocalSessionStore(container: container)
        } catch {
            logger.error("ModelContainer creation failed — local session history disabled: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: LocalSessionStoring

    func upsertSession(_ conversation: Conversation) {
        let data: Data
        do {
            data = try JSONEncoder().encode(conversation)
        } catch {
            Self.logger.error("upsertSession: transcript encode failed — \(error.localizedDescription, privacy: .public)")
            return
        }
        let preview = conversation.generatedPreview ?? conversation.lastMessage?.content
        if let record = fetchRecord(id: conversation.id) {
            record.title = conversation.title
            record.lastActivity = conversation.lastActivity
            record.messageCount = conversation.messages.count
            record.preview = preview
            record.transcriptData = data
        } else {
            context.insert(LocalSessionRecord(
                sessionID: conversation.id,
                title: conversation.title,
                createdAt: conversation.messages.first?.timestamp ?? conversation.lastActivity,
                lastActivity: conversation.lastActivity,
                messageCount: conversation.messages.count,
                preview: preview,
                transcriptData: data
            ))
        }
        saveContext("upsertSession")
    }

    func sessionSummaries() -> [LocalSessionSummary] {
        // Plain fetch + in-memory sort: the set is bounded (one row per
        // local session), and staying off descriptor sort/predicate keeps
        // reads on the simplest possible SwiftData surface on this beta.
        let records = ((try? context.fetch(FetchDescriptor<LocalSessionRecord>())) ?? [])
            .sorted { $0.lastActivity > $1.lastActivity }
        return records.map {
            LocalSessionSummary(
                id: $0.sessionID,
                title: $0.title,
                preview: $0.preview,
                messageCount: $0.messageCount,
                createdAt: $0.createdAt,
                lastActivity: $0.lastActivity
            )
        }
    }

    func conversation(withID id: UUID) -> Conversation? {
        guard let record = fetchRecord(id: id) else { return nil }
        do {
            return try JSONDecoder().decode(Conversation.self, from: record.transcriptData)
        } catch {
            Self.logger.error("conversation(withID:): transcript decode failed — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func hasSession(withID id: UUID) -> Bool {
        fetchRecord(id: id) != nil
    }

    func recordRemoteSessionStubs(_ infos: [HermesSessionInfo]) {
        let existing = (try? context.fetch(FetchDescriptor<RemoteSessionStubRecord>())) ?? []
        let byID = Dictionary(existing.map { ($0.stubID, $0) }, uniquingKeysWith: { first, _ in first })
        let keepIDs = Set(infos.map(\.id))
        // The snapshot REPLACES: sessions the host no longer lists drop out.
        for record in existing where !keepIDs.contains(record.stubID) {
            context.delete(record)
        }
        var seen = Set<String>()
        for info in infos where seen.insert(info.id).inserted {
            if let record = byID[info.id] {
                record.title = info.title
                record.preview = info.preview
                record.model = info.model
                record.source = info.source
                record.messageCount = info.messageCount
                record.lastActive = info.lastActive
                record.profileID = info.profileID
                record.profileName = info.profileName
            } else {
                context.insert(RemoteSessionStubRecord(
                    stubID: info.id,
                    title: info.title,
                    preview: info.preview,
                    model: info.model,
                    source: info.source,
                    messageCount: info.messageCount,
                    lastActive: info.lastActive,
                    profileID: info.profileID,
                    profileName: info.profileName
                ))
            }
        }
        saveContext("recordRemoteSessionStubs")
    }

    func remoteSessionStubs() -> [HermesSessionInfo] {
        let records = (try? context.fetch(FetchDescriptor<RemoteSessionStubRecord>())) ?? []
        return records
            .sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
            .map {
                HermesSessionInfo(
                    id: $0.stubID,
                    title: $0.title,
                    preview: $0.preview,
                    model: $0.model,
                    source: $0.source,
                    messageCount: $0.messageCount,
                    lastActive: $0.lastActive,
                    isActive: false,
                    profileID: $0.profileID,
                    profileName: $0.profileName
                )
            }
    }

    // MARK: - Internals

    private func fetchRecord(id: UUID) -> LocalSessionRecord? {
        // Plain fetch + in-memory match, same rationale as
        // `sessionSummaries()` — the row set is bounded, and this keeps every
        // read off the beta's descriptor machinery.
        ((try? context.fetch(FetchDescriptor<LocalSessionRecord>())) ?? [])
            .first { $0.sessionID == id }
    }

    private func saveContext(_ operation: StaticString) {
        do {
            try context.save()
        } catch {
            Self.logger.error("\(operation, privacy: .public): save failed — \(error.localizedDescription, privacy: .public)")
        }
    }
}
