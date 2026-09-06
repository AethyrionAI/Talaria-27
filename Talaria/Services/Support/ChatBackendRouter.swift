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
///   Hermes host exists. #192 (decided 2026-07-27): an explicit pick is a
///   STICKY MODE — it persists as the resolution default every new chat
///   inherits, with per-conversation overrides layered on top, so a
///   conversation-id rotation (New chat / clear / openSession) can never
///   silently revert the brain. Only an explicit pick — or an announced,
///   #30-style fallback — changes what routes.
/// - `activeBrain` drives the always-visible header indicator; finished
///   assistant messages are tagged with their producing brain so the
///   transcript stays honest across reconnects. Every `activeBrain` change
///   logs old → new, its initiator, and the conversation key consulted;
///   every refusal to re-derive logs the guard that refused (#192).
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

        /// The widest `monoLabel` across all brains ("ON-DEVICE" today). The
        /// chat header pill reserves this width so it never wraps inside
        /// itself and doesn't resize on brain switches (#42). Character count
        /// is a valid width proxy only because the label renders in
        /// JetBrains Mono.
        static var widestMonoLabel: String {
            allCases.map(\.monoLabel).max { $0.count < $1.count } ?? ""
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
    /// Slot for a pick made before any conversation exists; it migrates
    /// onto the first conversation that resolves. Since #192 only pick-only
    /// (non-sticky) writes land here — an explicit user pick with no
    /// conversation goes straight to `stickyDefaultKey`.
    static let nextConversationKey = "next"
    /// #192: the sticky-mode slot — the user's last explicit pick, inherited
    /// by every conversation that has no override of its own. UUID
    /// conversation keys can never collide with it.
    static let stickyDefaultKey = "default"

    /// The brain the NEXT message will use (and the one mid-run while a
    /// stream is active). Drives the chat-header indicator.
    private(set) var activeBrain: Brain
    /// Set for the lifetime of a run — the no-mid-thread-swap lock. #192:
    /// paired with `currentRunID` so only the run that set it can release it
    /// asynchronously, and cleared on EVERY exit (completion, consumer
    /// termination, `abandonActiveRun`) — a dropped stream must never wedge
    /// routing until force quit.
    private var runningBrain: Brain?
    /// Identity of the in-flight run; guards `finishRun` against a stale
    /// async teardown clearing a NEWER run's lock.
    private var currentRunID: UUID?
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

    /// **#395: whether the tier is off because the USER turned it off**, as
    /// opposed to being unavailable or rate-limited.
    ///
    /// It exists purely so the fallback notice can tell the truth. Both causes
    /// degrade to on-device identically, but reporting a user's own setting as
    /// *"unavailable or over its daily limit"* is the #180 family exactly — a
    /// surface describing a state it did not observe — and it is the kind of
    /// message that sends someone hunting for a network fault they do not have.
    var isPrivateCloudDisabledByUser: @MainActor () -> Bool = { false }
    var isPrivateCloudUsable: @MainActor () -> Bool = { false }
    /// #30: tells the local backend which tier a locally-routed turn runs on.
    var applyLocalTier: (@MainActor (Brain) -> Void)?
    /// #30: honest one-line notice when a PCC-pinned conversation degrades to
    /// on-device (unavailable / rate-limited). Cleared when PCC recovers or
    /// the preference changes; ChatScreen renders it under the header.
    private(set) var privateCloudFallbackNotice: String?
    /// #192: honest one-line notice when AUTOMATIC routing (no explicit pick
    /// anywhere) falls back to on-device because Hermes is known-unreachable
    /// — the same #30 pattern: an un-asked brain change is never silent.
    /// Cleared when automatic resolution routes to Hermes again or the user
    /// picks explicitly.
    private(set) var automaticFallbackNotice: String?
    /// #190: whether a session id names a stored/live LOCAL session — lets
    /// `openSession` route local ids to the local backend even while the
    /// active brain is Hermes (the unified drawer mixes both sources). Wired
    /// by AppContainer; nil keeps the pre-#190 active-brain routing.
    var isLocalSessionID: (@MainActor (String) -> Bool)?
    /// #190 Phase 4: records the last session list a LIVE Hermes host
    /// returned, so the drawer can keep that history visible (dimmed) after
    /// the host stops being configured. Wired by AppContainer.
    var recordRemoteSessions: (@MainActor ([HermesSessionInfo]) -> Void)?
    /// #190 Phase 4: the recorded remote-session snapshot, surfaced —
    /// re-marked unresumable — while no Hermes host is configured.
    var remoteSessionStubs: (@MainActor () -> [HermesSessionInfo])?
    private let defaults: UserDefaults

    /// #190: the honest reason line a dimmed remote-stub row carries.
    static let unresumableReason = "Host unpaired — reconnect to open"

    /// #425: the reason a dimmed remote-stub row carries when a host IS
    /// configured but could not be reached. Deliberately NOT
    /// `unresumableReason` — an unpaired host and a host that timed out are
    /// different states with different remedies, and this line is the only
    /// place the user learns which one they are in.
    static let hostUnreachableReason = "Host unreachable — reconnect to open"

    /// 425-D: the reason a dimmed remote-stub row carries during the WINDOW
    /// between the interim paint and the host's answer.
    ///
    /// Deliberately NOT `hostUnreachableReason`, even though 425-D's brief
    /// described the interim as "the failure-path shape". At interim time the
    /// host has not failed — it has not been ASKED yet — and on a reachable
    /// host it will answer in a few hundred milliseconds. Reusing the
    /// unreachable wording would put a false alarm on screen for exactly as
    /// long as a healthy host takes to reply, which is the "never flash a
    /// WRONG state" constraint being broken by the fix that constraint was
    /// written for. A row that says it is being checked, and then either
    /// un-dims or names the timeout, is true at every instant.
    static let hostPendingReason = "Contacting host…"

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
        resolveBrainForNextTurn().brain
    }

    /// #192: resolution carries its reason so every `activeBrain` change can
    /// name its initiator in the log — the instrumentation half of the
    /// silent-reversion fix.
    private struct BrainResolution {
        let brain: Brain
        let reason: String
    }

    private func resolveBrainForNextTurn() -> BrainResolution {
        let preference = resolvePreference()

        // #30: a PCC pick degrades to on-device when the tier can't take the
        // turn (unavailable / daily quota reached) — visible via the header
        // indicator plus the one-line fallback notice, never silent.
        if preference.brain == .privateCloud {
            if isPrivateCloudUsable() {
                privateCloudFallbackNotice = nil
                return BrainResolution(brain: .privateCloud, reason: preference.source)
            }
            if privateCloudFallbackNotice == nil {
                // #395: name the cause the user can act on.
                if isPrivateCloudDisabledByUser() {
                    privateCloudFallbackNotice = "Private Cloud β is turned off in Settings — continuing on-device."
                    Self.logger.notice("PCC pin degraded to on-device (disabled by user)")
                } else {
                    privateCloudFallbackNotice = "Private Cloud β is unavailable or over its daily limit — continuing on-device."
                    Self.logger.notice("PCC pin degraded to on-device (unavailable/rate-limited)")
                }
            }
            return BrainResolution(
                brain: .onDevice,
                reason: isPrivateCloudDisabledByUser() ? "pcc-disabled-by-user" : "pcc-degraded")
        }

        guard isHermesConfigured() else {
            automaticFallbackNotice = nil
            return BrainResolution(brain: .onDevice, reason: "hermes-unconfigured")
        }
        if let preferred = preference.brain {
            return BrainResolution(brain: preferred, reason: preference.source)
        }
        // Fully automatic: Hermes wins by default; known-unreachable at send
        // time routes new turns local — announced via the #30-style notice,
        // never just a silently moved pill (#192).
        if hermes.connectionStatus == .error {
            if automaticFallbackNotice == nil {
                automaticFallbackNotice = "Hermes is unreachable — new messages run on-device until it recovers."
                Self.logger.notice("automatic routing fell back to on-device: Hermes connectionStatus is error (#192)")
            }
            return BrainResolution(brain: .onDevice, reason: "hermes-unreachable")
        }
        automaticFallbackNotice = nil
        return BrainResolution(brain: .hermes, reason: "automatic-default")
    }

    /// Re-derives `activeBrain` for the header indicator. No-op while a run
    /// is in flight — the indicator shows the brain actually producing the
    /// current turn until it settles. #192: the refusal is LOGGED — this is
    /// the only guard on the switch path that can decline a re-derivation,
    /// and its silent decline is how a wedged run hid for a whole session.
    func refreshActiveBrain() {
        if let runningBrain {
            Self.logger.notice("refreshActiveBrain REFUSED: run in flight on \(runningBrain.rawValue, privacy: .public) — re-derivation deferred to run teardown (#192)")
            return
        }
        let resolution = resolveBrainForNextTurn()
        setActiveBrain(resolution.brain, initiator: "refresh/\(resolution.reason)")
    }

    /// #192: THE single writer for `activeBrain`. Logs every change — old →
    /// new, the initiator, and the conversation key consulted — so the next
    /// silent-reversion report carries evidence instead of a mystery.
    private func setActiveBrain(_ brain: Brain, initiator: String) {
        guard brain != activeBrain else { return }
        let old = activeBrain
        activeBrain = brain
        let conversationKey = conversationIDProvider()?.uuidString ?? "none"
        Self.logger.notice("activeBrain \(old.rawValue, privacy: .public) → \(brain.rawValue, privacy: .public) initiator=\(initiator, privacy: .public) conversation=\(conversationKey, privacy: .public) (#192)")
    }

    // MARK: - Brain preference (persisted; sticky mode since #192)

    /// The pick the given conversation resolves under: its own override if
    /// one exists (the pre-conversation "next" slot when no conversation
    /// exists yet), else the sticky default. Drives the picker checkmarks,
    /// so they reflect what will actually route — not merely whether this
    /// conversation has its own row.
    func preferredBrain(forConversation id: UUID?) -> Brain? {
        let preferences = storedPreferences()
        if let brain = preferences[Self.preferenceKey(for: id)].flatMap(Brain.init(rawValue:)) {
            return brain
        }
        return preferences[Self.stickyDefaultKey].flatMap(Brain.init(rawValue:))
    }

    /// Persists the user's pick. #192 (sticky mode): an explicit brain pick
    /// writes BOTH the conversation's override and the sticky default, so
    /// new chats inherit it and an id rotation can never revert the brain.
    /// nil brain = back to full automatic routing (clears both). Callers
    /// pinning a single conversation programmatically — the #30 escalation
    /// offer, the #134 debug harness — pass `updatesDefault: false`: a
    /// scoped pin must not hijack the user's app-wide mode.
    func setPreferredBrain(_ brain: Brain?, forConversation id: UUID?, updatesDefault: Bool = true) {
        var preferences = storedPreferences()
        let key = Self.preferenceKey(for: id)
        if let brain {
            preferences[key] = brain.rawValue
            if updatesDefault {
                preferences[Self.stickyDefaultKey] = brain.rawValue
                preferences.removeValue(forKey: Self.nextConversationKey)
            }
        } else {
            preferences.removeValue(forKey: key)
            if updatesDefault {
                preferences.removeValue(forKey: Self.stickyDefaultKey)
                preferences.removeValue(forKey: Self.nextConversationKey)
            }
        }
        defaults.set(preferences, forKey: Self.preferencesDefaultsKey)
        // A fresh pick clears any stale fallback notice — the next
        // resolution re-derives it if the tier is still down (#30/#192).
        privateCloudFallbackNotice = nil
        automaticFallbackNotice = nil
        let scope = updatesDefault ? "pick+default" : "pick-only"
        Self.logger.notice("brain preference \(key, privacy: .public) → \(brain?.rawValue ?? "automatic", privacy: .public) [\(scope, privacy: .public)] (#192)")
        refreshActiveBrain()
    }

    /// Effective preference for the live conversation under sticky mode:
    /// the conversation's own override wins, else the sticky default. A
    /// "next"-slot pick (legacy stored picks, and the pick-only harness pin)
    /// still migrates onto the first conversation that resolves, exactly as
    /// pre-#192 — stored picks are never stranded.
    private func resolvePreference() -> (brain: Brain?, source: String) {
        var preferences = storedPreferences()
        let conversationID = conversationIDProvider()
        if let conversationID, let pending = preferences[Self.nextConversationKey] {
            preferences[conversationID.uuidString] = pending
            preferences.removeValue(forKey: Self.nextConversationKey)
            defaults.set(preferences, forKey: Self.preferencesDefaultsKey)
        }
        if let brain = preferences[Self.preferenceKey(for: conversationID)].flatMap(Brain.init(rawValue:)) {
            let key = conversationID?.uuidString ?? Self.nextConversationKey
            return (brain, "override(\(key))")
        }
        if let brain = preferences[Self.stickyDefaultKey].flatMap(Brain.init(rawValue:)) {
            return (brain, "sticky-default")
        }
        return (nil, "automatic")
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
            setActiveBrain(.onDevice, initiator: "connect/unconfigured")
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
        let resolution = resolveBrainForNextTurn()
        let brain = resolution.brain
        let runID = UUID()
        setActiveBrain(brain, initiator: "send/\(resolution.reason)")
        runningBrain = brain
        currentRunID = runID
        lastRunBrain = brain
        if brain != .hermes { applyLocalTier?(brain) }
        defer { finishRun(runID, outcome: "send-completed") }
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
        let resolution = resolveBrainForNextTurn()
        let brain = resolution.brain
        let runID = UUID()
        setActiveBrain(brain, initiator: "stream/\(resolution.reason)")
        runningBrain = brain
        currentRunID = runID
        lastRunBrain = brain
        if brain != .hermes { applyLocalTier?(brain) }
        Self.logger.notice("sendStreaming routed to \(brain.rawValue, privacy: .public)")
        let upstream = backend(for: brain).sendStreaming(
            message: message,
            attachments: attachments,
            clientMessageID: clientMessageID
        )
        return AsyncStream { continuation in
            let pump = Task { @MainActor [weak self] in
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
                // Reached on upstream completion AND on pump cancellation
                // (AsyncStream iteration is cancellation-aware) — either way
                // the run is over and routing must re-derive. A run that
                // failed because Hermes died flips the indicator to the
                // brain the NEXT message will actually use.
                self?.finishRun(runID, outcome: "stream-ended")
                continuation.finish()
            }
            // #192: the consumer walking away (stop button, clear, session
            // switch — anything that cancels ChatStore's streaming task)
            // terminates this stream. Without this hook, an upstream that
            // never finishes (the #145/#184 dropped-run family) held
            // `runningBrain` for the life of the process and wedged the
            // brain toggle until force quit.
            continuation.onTermination = { _ in
                pump.cancel()
            }
        }
    }

    /// #192: the one run-teardown primitive. Releases the routing lock set
    /// by the identified run and re-derives `activeBrain`; a stale teardown
    /// (a late onTermination after a newer run started) is a no-op by token.
    private func finishRun(_ id: UUID, outcome: String) {
        guard currentRunID == id else { return }
        currentRunID = nil
        if let brain = runningBrain {
            Self.logger.notice("run finished on \(brain.rawValue, privacy: .public) [\(outcome, privacy: .public)] — routing lock released (#192)")
        }
        runningBrain = nil
        refreshActiveBrain()
    }

    /// #192: consumer-side abandonment — wired into ChatStore's
    /// `abandonPendingRun` (#184's teardown primitive) and `cancelStreaming`
    /// so every walk-away path releases the routing lock synchronously
    /// instead of waiting on a stream that may never end.
    ///
    /// #283 review ruling: this is LOCK RELEASE ONLY and must never forward
    /// to the backend — a walk-away (thread switch, clear, a continued-send
    /// expiring) must not hard-kill a host run the user didn't ask to stop.
    /// The explicit Stop tap gets `hardStopActiveRun()` below, called
    /// separately by `ChatStore.cancelStreaming()` BEFORE this.
    func abandonActiveRun() {
        guard let brain = runningBrain else { return }
        Self.logger.notice("abandonActiveRun: releasing routing lock held by \(brain.rawValue, privacy: .public) (#192)")
        currentRunID = nil
        runningBrain = nil
        refreshActiveBrain()
    }

    /// #295 (Owen's ruling, review follow-up): whether the run CURRENTLY
    /// holding the routing lock, if any, is recoverable via
    /// `reconcileFromServer()`. Only `.hermes` is — `.onDevice` and
    /// `.privateCloud` both route to `local` (`backend(for:)` above, #30:
    /// PCC is a mode of the local backend, never a third client), which
    /// finishes or dies IN-PROCESS the moment the app stops watching. There
    /// is no host still generating for either to reconcile against.
    /// `ChatStore.cancelStreaming` MUST read this BEFORE calling
    /// `abandonActiveRun()` above, which clears `runningBrain` — the signal
    /// this is built from.
    var currentRunIsServerRecoverable: Bool {
        runningBrain == .hermes
    }

    /// #283 Task 7 (S23), review ruling: the explicit Stop tap's real
    /// server-side interrupt — `ChatStore.cancelStreaming()`'s ONE call site
    /// for this method. Forwards to the brain that IS running (currently
    /// meaningful only on the Hermes runs plane; a no-op everywhere else)
    /// WITHOUT touching the routing lock — `abandonActiveRun()` above, which
    /// `cancelStreaming()` calls immediately afterward, is what releases it.
    /// Splitting the two means a plain walk-away (no Stop tap) can release
    /// the lock without ever reaching the network.
    ///
    /// #328 route 2: forwards the ISSUED/NOT-ISSUED answer too. No routing
    /// lock means no run to stop, which is `false` — the honest absence, not
    /// a failure.
    @discardableResult
    func hardStopActiveRun() -> Bool {
        guard let brain = runningBrain else { return false }
        return backend(for: brain).hardStopActiveRun()
    }

    /// #322: the in-flight run's id, forwarded by routing lock exactly like
    /// `hardStopActiveRun` above — and, exactly like
    /// `currentRunIsServerRecoverable`, it MUST be read before
    /// `abandonActiveRun()`, which clears `runningBrain`.
    var activeRunID: String? {
        guard let brain = runningBrain else { return nil }
        return backend(for: brain).activeRunID
    }

    /// #357 (3C): forwarded by routing lock exactly like `hardStopActiveRun`
    /// — no lock means no run to steer, the honest absence.
    func steerActiveRun(text: String) async -> SteerSubmitOutcome {
        guard let brain = runningBrain else { return .noActiveRun }
        return await backend(for: brain).steerActiveRun(text: text)
    }

    /// #322: the final status read, and it is deliberately **NOT** gated on
    /// `runningBrain` the way every other run-scoped forward here is.
    ///
    /// A `/v1/runs/{id}` id can only ever have come from the Hermes plane,
    /// and this read is taken DETACHED, after `cancelStreaming` has already
    /// called `abandonActiveRun()` — which releases the very lock the other
    /// forwards consult. Gating on it would return nil on every Stop, which
    /// is precisely the silent no-op this note exists to prevent.
    func finalRunUsage(runID: String) async -> TokenUsage? {
        await hermes.finalRunUsage(runID: runID)
    }

    /// #368 (3E): the dropped-run recovery read. **Not gated on
    /// `runningBrain`, for exactly the reason `finalRunUsage` above is not:**
    /// the recovery loop runs AFTER `cancelStreaming` has called
    /// `abandonActiveRun()`, which releases the lock, so gating would return
    /// nil on every pass and the collapse would be a silent no-op. Gated on
    /// `isHermesConfigured()` instead, matching `reconcileFromServer()` — the
    /// only other recovery-shaped forward here.
    func resolveDroppedRun(runID: String, sessionID: String, profileID: UUID?) async -> DroppedRunResolution? {
        guard isHermesConfigured() else { return nil }
        return await hermes.resolveDroppedRun(runID: runID, sessionID: sessionID, profileID: profileID)
    }

    /// #430: the run's own host, forwarded UNGATED for exactly the reason
    /// `finalRunUsage` above is — a `/v1/runs/{id}` id can only have come from
    /// the Hermes plane, and both readers (the `.interrupted` arm and
    /// `cancelStreaming`) can run after `abandonActiveRun()` has released
    /// `runningBrain`. Gating would answer nil on every Stop, which is the
    /// silent no-op this note exists to prevent.
    func runProfileID(forRunID runID: String) -> UUID? {
        hermes.runProfileID(forRunID: runID)
    }

    /// #304: the approval answer, forwarded by routing lock exactly like
    /// `hardStopActiveRun` above. A live card only exists while the runs
    /// turn (or its recovery poll) is alive — `ChatStore` tears it down on
    /// every driver exit (bar 304-E) — so the lock names the owning brain.
    /// If the lock is gone anyway, the protocol default's `.unsupported` is
    /// the honest answer; guessing a backend is not.
    func answerApproval(runID: String, choice: String, endpoint: SessionsHermesClient.ResolvedEndpoint) async -> RunApprovalAnswerOutcome {
        guard let brain = runningBrain else { return .unsupported }
        return await backend(for: brain).answerApproval(runID: runID, choice: choice, endpoint: endpoint)
    }

    func loadConversation() async -> Conversation {
        await backend(for: runningBrain ?? activeBrain).loadConversation()
    }

    /// #78: a truncation is a property of the THREAD, not of a brain — so it
    /// goes to BOTH backends, not to `backend(for:)`. #192 flips brains
    /// mid-conversation by design, and `currentConversation` above reads from
    /// whichever one last ran; a mirror left untruncated on the other side is
    /// a loaded gun that fires on the first turn after a flip.
    func adoptTruncatedConversation(_ conversation: Conversation) {
        local.adoptTruncatedConversation(conversation)
        hermes.adoptTruncatedConversation(conversation)
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
        try await listSessions(interim: nil)
    }

    func listSessions(
        interim: (@MainActor ([HermesSessionInfo]) -> Void)?
    ) async throws -> [HermesSessionInfo] {
        // #190: ONE unified list, sorted globally by recency — never two
        // lanes. The local store's sessions always participate; the Hermes
        // side contributes its live list while configured, and its last
        // recorded snapshot — dimmed, unresumable — once it isn't. A local
        // listing failure can't exist in practice (`try?` is shape, not
        // policy).
        //
        // #425: a host that is configured but UNREACHABLE degrades the same
        // way, instead of throwing. The old shape fetched the local rows
        // first and then threw them away with the host's error, and
        // `ChatStore.loadSessions` answered from `lastLoadedSessions` —
        // zero rows in any launch that had not yet completed one successful
        // host list. Owen's phone dropped off the tailnet on 2026-09-04 and
        // the entire shelf went blank: Local, PCC and Hermes threads all ride
        // this one call, so one throw hid three origins' worth of history
        // that was never lost, only unread. The host being away is a true
        // state and the drawer says so per row; it is not a reason to hide
        // work that lives on the phone.
        let localSessions = (try? await local.listSessions()) ?? []
        guard isHermesConfigured() else {
            let stubs = (remoteSessionStubs?() ?? []).map {
                $0.asUnresumable(reason: Self.unresumableReason)
            }
            return Self.sortedByRecency(localSessions + stubs)
        }
        // 425-D: the half already on the phone goes out NOW, before the host
        // is awaited. #425 stopped the local rows being thrown away by a host
        // failure; this stops them being held hostage by its LATENCY — Owen's
        // device pass (build 3257, 2026-09-04) watched a correct degraded
        // shelf arrive ~20 s after an empty one, the local rows in hand the
        // whole time. The stubs ride along dimmed with `hostPendingReason`
        // rather than `hostUnreachableReason`: the host has not failed here,
        // it has not been ASKED yet, and on a reachable host it answers in a
        // few hundred milliseconds.
        //
        // At most ONE call, and never the answer: the returned list below is
        // always the caller's last word, on every path out of this function
        // (merged, degraded, or a rethrown cancellation whose caller keeps
        // its last good list).
        if let interim {
            let pending = (remoteSessionStubs?() ?? []).map {
                $0.asUnresumable(reason: Self.hostPendingReason)
            }
            interim(Self.sortedByRecency(localSessions + pending))
        }
        let hermesSessions: [HermesSessionInfo]
        do {
            hermesSessions = try await hermes.listSessions()
        } catch {
            // A CANCELLED load is the caller walking away, not the host being
            // away, and must never be degraded into one. Two screens list
            // from a cancellable `.task` (`SettingsChannelsScreen`,
            // `SessionsSettingsScreen`), so dismissing a sheet cancels the
            // in-flight fetch — `URLError(.cancelled)` out of the
            // single-profile `fetchSessionList`, or `CancellationError` from
            // a cancelled `Task`. Swallowing either would put
            // `ChatStore.loadSessions` on its SUCCESS path, writing this
            // dimmed list into `lastLoadedSessions` and stamping
            // `lastSessionsLoadAt` — a good list from a slow-but-REACHABLE
            // host replaced by unopenable rows and cached for the whole 15 s
            // snapshot TTL. Re-throwing hands it back to that store's own
            // catch, which serves the last real list exactly as before.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            // `SessionsHermesClient.listSessions` already tolerates partial
            // failure — one profile of several going quiet drops out of the
            // round — and throws only when no list came back at all. So
            // reaching here means NO configured host answered.
            let stubs = (remoteSessionStubs?() ?? []).map {
                $0.asUnresumable(reason: Self.hostUnreachableReason)
            }
            Self.logger.notice("listSessions: no configured host answered — \(error.localizedDescription, privacy: .public); serving \(localSessions.count, privacy: .public) local row(s) + \(stubs.count, privacy: .public) dimmed host row(s) from the last snapshot")
            // Deliberately NOT `recordRemoteSessions`: those stubs ARE the
            // last real host list, and the snapshot write REPLACES
            // (`SwiftDataLocalSessionStore.recordRemoteSessionStubs`), so
            // recording a failure would delete the only remote history the
            // drawer has left.
            return Self.sortedByRecency(localSessions + stubs)
        }
        recordRemoteSessions?(hermesSessions)
        return Self.sortedByRecency(hermesSessions + localSessions)
    }

    nonisolated static func sortedByRecency(_ infos: [HermesSessionInfo]) -> [HermesSessionInfo] {
        infos.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    func openSession(_ id: String) async throws -> Conversation {
        // #190: the unified drawer mixes sources, so an id routes by
        // MEMBERSHIP on both sides — a stored local session opens on the
        // local backend even while the active brain is Hermes, and a
        // non-local id is a REMOTE session that opens on Hermes even while
        // the active brain is local (the 2026-07-26 device fail: active-brain
        // routing sent Hermes rows to `LocalChatBackend`, which threw
        // `sessionNotFound` on every tap). Only an unconfigured Hermes falls
        // back to the active brain — those rows are unresumable stubs and
        // the drawer already blocks their taps, so the fallback exists for
        // shape, not policy.
        if isLocalSessionID?(id) == true {
            return try await local.openSession(id)
        }
        guard isHermesConfigured() else {
            return try await backend(for: runningBrain ?? activeBrain).openSession(id)
        }
        return try await hermes.openSession(id)
    }

    func reconcileFromServer() async -> Conversation? {
        // Interrupted-run reconcile is a server concept — only the Hermes
        // side can answer it; the local brain has no dropped-stream state.
        guard isHermesConfigured() else { return nil }
        return await hermes.reconcileFromServer()
    }
}
