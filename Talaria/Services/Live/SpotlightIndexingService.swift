import AppIntents
import CoreSpotlight
import Foundation
import os

private let spotlightLog = Logger(subsystem: "org.aethyrion.talaria", category: "SpotlightIndexing")

/// #17: donates Hermes sessions and #21 Tier-1 staged agent files to the
/// system index as `IndexedEntity`, strictly behind the Privacy Settings
/// toggle (default OFF) — chat titles and previews entering the system index
/// is a real privacy trade, so it's an explicit opt-in, never a default.
@MainActor
final class SpotlightIndexingService {

    /// Wired by AppContainer to the persisted Settings toggle. Nil (tests /
    /// unwired) reads as disabled — donation can never happen by accident.
    var isEnabled: (@MainActor () -> Bool)?

    /// Last-donated entities, kept for intent-time resolution
    /// (ChatSessionEntityQuery / AgentFileEntityQuery). Sessions are mirrored
    /// to UserDefaults so "open that" resolves after a relaunch without a
    /// network round-trip.
    private(set) var sessionEntities: [String: ChatSessionEntity] = [:]
    private(set) var fileEntities: [String: AgentFileEntity] = [:]

    private static let sessionCacheKey = "hermes.spotlight.sessionEntities"

    init() {
        loadSessionCache()
    }

    // MARK: - Donation

    func donateSessions(_ sessions: [HermesSessionInfo]) {
        guard isEnabled?() == true, !sessions.isEmpty else { return }
        let entities = sessions.map(ChatSessionEntity.init(info:))
        for entity in entities {
            sessionEntities[entity.id] = entity
        }
        persistSessionCache()
        Task {
            do {
                try await CSSearchableIndex.default().indexAppEntities(entities)
                spotlightLog.notice("donated \(entities.count) session entities")
            } catch {
                spotlightLog.error("session donation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func donateAgentFiles(from conversation: Conversation?) {
        guard isEnabled?() == true else { return }
        let fresh = Self.agentFileEntities(in: conversation).filter { fileEntities[$0.id] == nil }
        guard !fresh.isEmpty else { return }
        for entity in fresh {
            fileEntities[entity.id] = entity
        }
        Task {
            do {
                try await CSSearchableIndex.default().indexAppEntities(fresh)
                spotlightLog.notice("donated \(fresh.count) agent-file entities")
            } catch {
                spotlightLog.error("agent-file donation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// #21 Tier-1 staged files are file attachments carried on HERMES-sent
    /// messages — user uploads ride user messages and stay out of the index.
    nonisolated static func agentFileEntities(in conversation: Conversation?) -> [AgentFileEntity] {
        guard let conversation else { return [] }
        return conversation.messages
            .filter { $0.sender == .hermes }
            .flatMap(\.attachments)
            .filter { $0.kind == "file" && $0.localStoragePath != nil }
            .map {
                AgentFileEntity(
                    id: $0.id.uuidString,
                    fileName: $0.fileName,
                    localStoragePath: $0.localStoragePath
                )
            }
    }

    /// Toggle-off teardown — no orphaned index entries (acceptance criterion).
    /// `deleteAllSearchableItems` is safe here: sessions and agent files are
    /// the only things Talaria has ever donated.
    func removeAllDonations() {
        sessionEntities = [:]
        fileEntities = [:]
        UserDefaults.standard.removeObject(forKey: Self.sessionCacheKey)
        Task {
            do {
                try await CSSearchableIndex.default().deleteAllSearchableItems()
                spotlightLog.notice("removed all Spotlight donations")
            } catch {
                spotlightLog.error("donation removal failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Intent-time resolution

    func resolveSessions(_ identifiers: [String]) -> [ChatSessionEntity] {
        // Unknown ids (cache cleared, different device) still resolve to a
        // bare entity so the open intent can route — the session list is the
        // authority once the app opens.
        identifiers.map { sessionEntities[$0] ?? ChatSessionEntity(id: $0, title: "Hermes Session") }
    }

    func suggestedSessions() -> [ChatSessionEntity] {
        Array(
            sessionEntities.values
                .sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
                .prefix(5)
        )
    }

    func resolveFiles(_ identifiers: [String]) -> [AgentFileEntity] {
        identifiers.compactMap { fileEntities[$0] }
    }

    // MARK: - Session cache persistence

    private struct CachedSession: Codable {
        let id: String
        let title: String
        let preview: String?
        let lastActive: Date?
    }

    private func persistSessionCache() {
        let payload = sessionEntities.values.map {
            CachedSession(id: $0.id, title: $0.title, preview: $0.preview, lastActive: $0.lastActive)
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionCacheKey)
    }

    private func loadSessionCache() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.sessionCacheKey),
            let payload = try? JSONDecoder().decode([CachedSession].self, from: data)
        else { return }
        for cached in payload {
            sessionEntities[cached.id] = ChatSessionEntity(
                id: cached.id,
                title: cached.title,
                preview: cached.preview,
                lastActive: cached.lastActive
            )
        }
    }
}
