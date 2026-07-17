import AppIntents
import Foundation
import os

/// #66 diagnostics: one `.notice` line per joint of the Spotlight tap-through
/// chain — entity query (Spotlight → entity), `perform()` (entity → intent),
/// and the deep link it builds — so Console.app can name the broken joint
/// without a rebuild (the #58 lesson). `.notice` because Console's default
/// view suppresses `.info`; `privacy: .public` because interpolations redact
/// without it.
private let spotlightOpenLog = Logger(
    subsystem: "org.aethyrion.talaria",
    category: "SpotlightOpen"
)

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
        let resolved = AppContainer.sharedDefault().spotlightIndexing.resolveSessions(identifiers)
        spotlightOpenLog.notice(
            "ChatSessionEntityQuery resolved \(resolved.count, privacy: .public)/\(identifiers.count, privacy: .public) for ids [\(identifiers.joined(separator: ","), privacy: .public)]"
        )
        return resolved
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
        let resolved = AppContainer.sharedDefault().spotlightIndexing.resolveFiles(identifiers)
        spotlightOpenLog.notice(
            "AgentFileEntityQuery resolved \(resolved.count, privacy: .public)/\(identifiers.count, privacy: .public) for ids [\(identifiers.joined(separator: ","), privacy: .public)]"
        )
        return resolved
    }
}

// MARK: - Open intents

/// Spotlight tap-through for a donated session. Routes through the
/// `hermes://session/{id}` deep link so external openers and this intent
/// share one navigation code path (AppEntry.handleDeeplink).
struct OpenSessionIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Hermes Session"
    static let description = IntentDescription("Opens a Hermes chat session in Talaria.")
    // #66: must stay `false`. The `OpenURLIntent` returned from `perform()`
    // IS the app launch — pairing it with `openAppWhenRun = true` is the
    // exact combination that made Control Center silently swallow taps (#58,
    // see HermesControls.swift), and the 2026-07-13 device pass showed the
    // same dead tap here. Declared EXPLICITLY rather than omitted (the
    // HermesControls shape) because `OpenIntent` rides a different protocol
    // chain (`SystemIntent`) whose default for this member is undocumented —
    // absence could silently mean `true`. `SpotlightOpenIntentTests` pins
    // both open intents to false; do not re-add `true`.
    static let openAppWhenRun = false

    @Parameter(title: "Session")
    var target: ChatSessionEntity

    /// Split out of `perform()` so the #66 configuration test can pin the
    /// route shape (percent-encoded id on `hermes://session/`).
    static func destination(forSessionID id: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "hermes://session/\(encoded)") ?? URL(string: "hermes://chat")!
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = Self.destination(forSessionID: target.id)
        spotlightOpenLog.notice(
            "OpenSessionIntent.perform fired — session \(target.id, privacy: .public), opening \(url.absoluteString, privacy: .public)"
        )
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// Spotlight tap-through for a donated agent file: lands on the chat
/// transcript, where the file bubble (ShareLink) lives.
struct OpenAgentFileIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Hermes File"
    static let description = IntentDescription("Opens Talaria's chat, where the file was shared.")
    // #66: must stay `false` — same conflict as `OpenSessionIntent` (never
    // device-verified, but the shape was identical). Explicit for the same
    // reason; pinned by `SpotlightOpenIntentTests`.
    static let openAppWhenRun = false

    @Parameter(title: "File")
    var target: AgentFileEntity

    /// Compile-time literal — parsing cannot fail. Static so the #66
    /// configuration test can pin the route.
    static let destination = URL(string: "hermes://chat")!

    func perform() async throws -> some IntentResult & OpensIntent {
        spotlightOpenLog.notice(
            "OpenAgentFileIntent.perform fired — file \(target.id, privacy: .public) (\(target.fileName, privacy: .public)), opening \(Self.destination.absoluteString, privacy: .public)"
        )
        return .result(opensIntent: OpenURLIntent(Self.destination))
    }
}
