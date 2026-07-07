import Foundation
import os

/// One seam, two brains (#27). Owns the Hermes client (the resilient Sessions
/// stack) and the on-device `LocalChatBackend`, and presents itself to
/// ChatStore as the single `any HermesClientProtocol` it already knows.
///
/// Routing rules (decided 2026-07-06 — automatic at first sight, selectable
/// once Hermes exists):
/// - Never-paired / never-keyed device → the local brain unconditionally.
///   No pairing wall (the App Store reviewer path, #31).
/// - Hermes configured → Hermes wins by default. Known-unreachable at send
///   time → NEW turns route local. There is never a silent mid-thread brain
///   swap: the brain that starts a run finishes it or fails honestly —
///   routing is evaluated per new message.
/// - Power-user picker (chat header + Settings → Models) appears once any
///   Hermes host exists; the choice is per-conversation and persisted.
/// - `activeBrain` drives the always-visible header indicator; finished
///   assistant messages are tagged with their producing brain so the
///   transcript stays honest across reconnects.
@MainActor
@Observable
final class ChatBackendRouter: HermesClientProtocol {

    enum Brain: String, Codable, CaseIterable, Sendable {
        case hermes
        case onDevice = "on-device"
        /// Selectable only after #30 lands the PCC tier; routed to the local
        /// backend (which owns the PCC session) when it does.
        case privateCloud = "private-cloud-beta"

        var displayLabel: String {
            switch self {
            case .hermes: "Hermes"
            case .onDevice: "On-Device"
            case .privateCloud: "Private Cloud β"
            }
        }

        /// HUD-style mono label for the header indicator + transcript tags.
        var monoLabel: String {
            switch self {
            case .hermes: "HERMES"
            case .onDevice: "ON-DEVICE"
            case .privateCloud: "PCC β"
            }
        }

        var glyph: String {
            switch self {
            case .hermes: "desktopcomputer"
            case .onDevice: "iphone"
            case .privateCloud: "cloud"
            }
        }
    }

    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "ChatBackendRouter")
    static let preferencesDefaultsKey = "talaria.chat.brainPreferences"
    /// Preference slot for a pick made before any conversation exists; it
    /// migrates onto the first conversation that sends.
    static let nextConversationKey = "next"

    /// The brain the NEXT message will use (and the one mid-run while a
    /// stream is active). Drives the chat-header indicator.
    private(set) var activeBrain: Brain
    /// Set for the lifetime of a streaming run — the no-mid-thread-swap lock.
    private var runningBrain: Brain?
    /// The brain that ran the most recent turn. ChatStore's post-turn
    /// metadata merge reads `currentConversation` after the stream ends (and
    /// after `runningBrain` clears) — it must still see the backend that
    /// actually produced the turn, even if routing has already re-resolved.
    private var lastRunBrain: Brain?

    private let hermes: any HermesClientProtocol
    private let local: any HermesClientProtocol
    /// Whether the direct chat path to a Hermes host is configured (API key
    /// present). This is the ROUTING signal.
    private let isHermesConfigured: @MainActor () -> Bool
    /// Whether any Hermes host has ever been set up (pairing or API key).
    /// This is the PICKER-visibility signal — once Hermes exists, the user
    /// can pin conversations to either brain.
    private let hasHermesHost: @MainActor () -> Bool
    /// Wired by AppContainer after construction (ChatStore owns the live
    /// conversation, and ChatStore is built on top of this router).
    var conversationIDProvider: @MainActor () -> UUID? = { nil }
    /// #30: PCC gates, wired by AppContainer to the local backend. Selectable
    /// = entitlement + availability pass (the picker entry exists at all);
    /// usable = can take a turn right now (also below the daily quota).
    var isPrivateCloudSelectable: @MainActor () -> Bool = { false }
    var isPrivateCloudUsable: @MainActor () -> Bool = { false }
    /// #30: tells the local backend which tier a locally-routed turn runs on.
    var applyLocalTier: (@MainActor (Brain) -> Void)?
    /// #30: honest one-line notice when a PCC-pinned conversation degrades to
    /// on-device (unavailable / rate-limited). Cleared when PCC recovers or
    /// the preference changes; ChatScreen renders it under the header.
    private(set) var privateCloudFallbackNotice: String?
    private let defaults: UserDefaults

    init(
        hermes: any HermesClientProtocol,
        local: any HermesClientProtocol,
        isHermesConfigured: @escaping @MainActor () -> Bool,
        hasHermesHost: @escaping @MainActor () -> Bool,
        defaults: UserDefaults = .standard
    ) {
        self.hermes = hermes
        self.local = local
        self.isHermesConfigured = isHermesConfigured
        self.hasHermesHost = hasHermesHost
        self.defaults = defaults
        self.activeBrain = isHermesConfigured() ? .hermes : .onDevice
    }

    // MARK: - Routing

    /// Brains the picker offers. Hermes needs a host; Private Cloud β needs
    /// the entitlement + availability check to actually pass (#30).
    var selectableBrains: [Brain] {
        var brains: [Brain] = hasHermesHost() ? [.hermes, .onDevice] : [.onDevice]
        if isPrivateCloudSelectable() {
            brains.append(.privateCloud)
        }
        return brains
    }

    /// The picker appears once there is genuinely more than one brain to
    /// pick — a Hermes host exists, or the PCC tier is live (#30).
    var showsBrainPicker: Bool { selectableBrains.count > 1 }

    /// Routing decision for a NEW turn. Evaluated per message; never flips a
    /// run already in flight.
    func resolvedBrainForNextTurn() -> Brain {
        let preferred = resolvePreferenceForCurrentConversation()

        // #30: a PCC pin degrades to on-device when the tier can't take the
        // turn (unavailable / daily quota reached) — visible via the header
        // indicator plus the one-line fallback notice, never silent.
        if preferred == .privateCloud {
            if isPrivateCloudUsable() {
                privateCloudFallbackNotice = nil
                return .privateCloud
            }
            if privateCloudFallbackNotice == nil {
                privateCloudFallbackNotice = "Private Cloud β is unavailable or over its daily limit — continuing on-device."
                Self.logger.notice("PCC pin degraded to on-device (unavailable/rate-limited)")
            }
            return .onDevice
        }

        guard isHermesConfigured() else { return .onDevice }
        if let preferred { return preferred }
        // Hermes wins by default; known-unreachable at send time routes new
        // turns local (the header indicator makes the change visible).
        return hermes.connectionStatus == .error ? .onDevice : .hermes
    }

    /// Re-derives `activeBrain` for the header indicator. No-op while a run
    /// is in flight — the indicator shows the brain actually producing the
    /// current turn until it settles.
    func refreshActiveBrain() {
        guard runningBrain == nil else { return }
        activeBrain = resolvedBrainForNextTurn()
    }

    // MARK: - Per-conversation preference (persisted)

    func preferredBrain(forConversation id: UUID?) -> Brain? {
        storedPreferences()[Self.preferenceKey(for: id)].flatMap(Brain.init(rawValue:))
    }

    /// Persists the user's pick for the given conversation (nil conversation
    /// = the next one to start; nil brain = back to automatic routing).
    func setPreferredBrain(_ brain: Brain?, forConversation id: UUID?) {
        var preferences = storedPreferences()
        let key = Self.preferenceKey(for: id)
        if let brain {
            preferences[key] = brain.rawValue
        } else {
            preferences.removeValue(forKey: key)
        }
        defaults.set(preferences, forKey: Self.preferencesDefaultsKey)
        // A fresh pick clears any stale PCC degradation notice — the next
        // resolution re-derives it if the tier is still down (#30).
        privateCloudFallbackNotice = nil
        refreshActiveBrain()
        Self.logger.notice("brain preference for \(key, privacy: .public) → \(brain?.rawValue ?? "automatic", privacy: .public)")
    }

    /// Preference for the live conversation, migrating a pre-conversation
    /// "next" pick onto the first conversation that actually sends.
    private func resolvePreferenceForCurrentConversation() -> Brain? {
        var preferences = storedPreferences()
        let conversationID = conversationIDProvider()
        if let conversationID, let pending = preferences[Self.nextConversationKey] {
            preferences[conversationID.uuidString] = pending
            preferences.removeValue(forKey: Self.nextConversationKey)
            defaults.set(preferences, forKey: Self.preferencesDefaultsKey)
        }
        let key = Self.preferenceKey(for: conversationID)
        return preferences[key].flatMap(Brain.init(rawValue:))
    }

    private func storedPreferences() -> [String: String] {
        (defaults.dictionary(forKey: Self.preferencesDefaultsKey) as? [String: String]) ?? [:]
    }

    private static func preferenceKey(for id: UUID?) -> String {
        id?.uuidString ?? nextConversationKey
    }

    /// Transcript tag for an assistant message's producing brain: nil for
    /// Hermes (the historical default — untagged bubbles read as before) and
    /// the mono label for everything else.
    nonisolated static func transcriptTag(forMessageBrain raw: String?) -> String? {
        guard let raw, let brain = Brain(rawValue: raw), brain != .hermes else { return nil }
        return brain.monoLabel
    }

    private func backend(for brain: Brain) -> any HermesClientProtocol {
        switch brain {
        case .hermes:
            return hermes
        case .onDevice, .privateCloud:
            // PCC is a mode of the local backend (32K PCC session, #30) —
            // never a third client.
            return local
        }
    }

    // MARK: - HermesClientProtocol

    var connectionStatus: ConnectionStatus {
        backend(for: runningBrain ?? activeBrain).connectionStatus
    }

    var currentConversation: Conversation? {
        backend(for: runningBrain ?? lastRunBrain ?? activeBrain).currentConversation
    }

    /// Health probe + routing re-evaluation. The chat screen calls this on
    /// appear and every ~10s, so a restarted gateway flips the next turn back
    /// to Hermes without user action (and a dead one flips it local).
    func connect() async {
        guard isHermesConfigured() else {
            activeBrain = .onDevice
            await local.connect()
            return
        }
        await hermes.connect()
        refreshActiveBrain()
        if (runningBrain ?? activeBrain) != .hermes {
            await local.connect()
        }
    }

    func disconnect() async {
        await hermes.disconnect()
        await local.disconnect()
    }

    func send(
        message: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) async -> Message {
        let brain = resolvedBrainForNextTurn()
        activeBrain = brain
        runningBrain = brain
        lastRunBrain = brain
        if brain != .hermes { applyLocalTier?(brain) }
        defer {
            runningBrain = nil
            refreshActiveBrain()
        }
        var reply = await backend(for: brain).send(
            message: message,
            attachments: attachments,
            clientMessageID: clientMessageID
        )
        if reply.sender == .hermes {
            reply.brain = brain.rawValue
        }
        return reply
    }

    func sendStreaming(
        message: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) -> AsyncStream<StreamingUpdate> {
        // Routing is decided HERE, once, for the whole run — the brain that
        // starts a run finishes it or fails honestly.
        let brain = resolvedBrainForNextTurn()
        activeBrain = brain
        runningBrain = brain
        lastRunBrain = brain
        if brain != .hermes { applyLocalTier?(brain) }
        Self.logger.notice("sendStreaming routed to \(brain.rawValue, privacy: .public)")
        let upstream = backend(for: brain).sendStreaming(
            message: message,
            attachments: attachments,
            clientMessageID: clientMessageID
        )
        return AsyncStream { continuation in
            Task { @MainActor [weak self] in
                for await update in upstream {
                    if case .finished(var message, let usage, let diff) = update {
                        if message.sender == .hermes {
                            message.brain = brain.rawValue
                        }
                        continuation.yield(.finished(message, usage, diff))
                    } else {
                        continuation.yield(update)
                    }
                }
                self?.runningBrain = nil
                // A run that failed because Hermes died flips the indicator
                // to the brain the NEXT message will actually use.
                self?.refreshActiveBrain()
                continuation.finish()
            }
        }
    }

    func loadConversation() async -> Conversation {
        await backend(for: runningBrain ?? activeBrain).loadConversation()
    }

    func clearConversation() async throws -> Conversation {
        // Clear BOTH sides: a new chat is a new thread on whichever brain the
        // next message routes to, and a stale Hermes session id must not
        // resurrect after a stretch of local chatting (or vice versa).
        let localFresh = try await local.clearConversation()
        do {
            let hermesFresh = try await hermes.clearConversation()
            return resolvedBrainForNextTurn() == .hermes ? hermesFresh : localFresh
        } catch {
            // The Hermes side failed to clear. If the next turn routes there,
            // that's the caller's honest failure; otherwise the local clear
            // stands.
            if resolvedBrainForNextTurn() == .hermes { throw error }
            return localFresh
        }
    }

    func availableModels() async throws -> [String] {
        try await backend(for: runningBrain ?? activeBrain).availableModels()
    }

    @discardableResult
    func switchModel(_ identifier: String) async throws -> String? {
        try await backend(for: runningBrain ?? activeBrain).switchModel(identifier)
    }

    func listSessions() async throws -> [HermesSessionInfo] {
        try await backend(for: runningBrain ?? activeBrain).listSessions()
    }

    func openSession(_ id: String) async throws -> Conversation {
        try await backend(for: runningBrain ?? activeBrain).openSession(id)
    }

    func reconcileFromServer() async -> Conversation? {
        // Interrupted-run reconcile is a server concept — only the Hermes
        // side can answer it; the local brain has no dropped-stream state.
        guard isHermesConfigured() else { return nil }
        return await hermes.reconcileFromServer()
    }
}
