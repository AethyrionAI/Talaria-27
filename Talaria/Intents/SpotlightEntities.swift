import AppIntents
import Foundation

// MARK: - #17 Spotlight surface
//
// Hermes sessions and #21 Tier-1 staged agent files donated to the system
// index as IndexedEntity. Donation is strictly gated behind the Privacy
// Settings toggle (default OFF) — see SpotlightIndexingService. Entities are
// persistent (session ids + staged attachment ids), never transient, per the
// verified caveat. Plain Spotlight search works today; the Siri AI consumer
// of the semantic index rides the same donations when it rolls out.

/// A Hermes chat session, identified by the Sessions API string id
/// (NOT the client-local Conversation UUID).
struct ChatSessionEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hermes Session"
    static let defaultQuery = ChatSessionEntityQuery()

    let id: String
    var title: String
    var preview: String?
    var lastActive: Date?

    init(id: String, title: String, preview: String? = nil, lastActive: Date? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
        self.lastActive = lastActive
    }

    init(info: HermesSessionInfo) {
        let trimmedTitle = info.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: info.id,
            title: trimmedTitle?.isEmpty == false ? trimmedTitle! : "Hermes Session",
            preview: info.preview,
            lastActive: info.lastActive
        )
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle = preview ?? "Hermes session"
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }
}

struct ChatSessionEntityQuery: EntityQuery {
    /// Resolution reads the last-donated cache (persisted across relaunches)
    /// rather than a network round-trip — intents must resolve fast.
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ChatSessionEntity] {
        AppContainer.sharedDefault().spotlightIndexing.resolveSessions(identifiers)
    }

    @MainActor
    func suggestedEntities() async throws -> [ChatSessionEntity] {
        AppContainer.sharedDefault().spotlightIndexing.suggestedSessions()
    }
}

/// A #21 Tier-1 agent file: reconstructed from the SSE stream and staged
/// locally, carried as a file attachment on a Hermes-sent message.
struct AgentFileEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hermes File"
    static let defaultQuery = AgentFileEntityQuery()

    /// The staged MessageAttachment's UUID string.
    let id: String
    var fileName: String
    var localStoragePath: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(fileName)", subtitle: "File from Hermes")
    }
}

struct AgentFileEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [AgentFileEntity] {
        AppContainer.sharedDefault().spotlightIndexing.resolveFiles(identifiers)
    }
}

// MARK: - Open intents

/// Spotlight tap-through for a donated session. Routes through the
/// `hermes://session/{id}` deep link so external openers and this intent
/// share one navigation code path (AppEntry.handleDeeplink).
struct OpenSessionIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Hermes Session"
    static let description = IntentDescription("Opens a Hermes chat session in Talaria.")
    static let openAppWhenRun = true

    @Parameter(title: "Session")
    var target: ChatSessionEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        let encoded = target.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? target.id
        let url = URL(string: "hermes://session/\(encoded)") ?? URL(string: "hermes://chat")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// Spotlight tap-through for a donated agent file: lands on the chat
/// transcript, where the file bubble (ShareLink) lives.
struct OpenAgentFileIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Hermes File"
    static let description = IntentDescription("Opens Talaria's chat, where the file was shared.")
    static let openAppWhenRun = true

    @Parameter(title: "File")
    var target: AgentFileEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "hermes://chat")!))
    }
}
