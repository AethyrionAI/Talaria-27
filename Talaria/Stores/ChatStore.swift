import Foundation
import UIKit
import os

private let chatLog = Logger(subsystem: "org.aethyrion.talaria", category: "ChatStore")

/// #21 Tier 2: transient per-attachment download state for fetchable agent
/// files. Absence from the map means idle (tap to download); staged-ness
/// itself is derived from the attachment's `localStoragePath`, never tracked
/// here.
enum AgentFileDownloadState: Equatable {
    case downloading
    case failed(String)
}

@MainActor
@Observable
final class ChatStore {
    var conversation: Conversation?
    var isLoading = false
    var pendingMessageSentAt: Date?
    /// #203 (1A): when this turn last showed ANY sign of life — a token, a
    /// reasoning delta, or a tool event. Production has no turn deadline of
    /// any kind (the 35s guillotine is battery-only), so a wedged turn spins
    /// silently until the user force-quits. This drives a visible "still
    /// working…" hint; it CANCELS NOTHING. #202B measured this model
    /// fabricating when cut off from a tool it expected, so an automatic
    /// deadline risks manufacturing the exact lie #202D removed — the user
    /// decides, via the Stop that already exists.
    var lastStreamActivityAt: Date?
    var lastTokenUsage: TokenUsage?

    /// #48: payload from a `hermes://ask?q=…` deep link, held until ChatScreen
    /// pulls it into the composer. Seed-only by design — a custom-scheme URL
    /// can be fired by any app or web page, so it must never auto-send.
    private(set) var pendingComposerSeed: String?

    func seedComposer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingComposerSeed = trimmed
    }

    func consumeComposerSeed() -> String? {
        defer { pendingComposerSeed = nil }
        return pendingComposerSeed
    }

    /// #123: share-extension payloads staged for the composer. A separate
    /// slot from the #48 ask-seed — see `ShareComposerSeed`.
    private(set) var pendingShareSeed: ShareComposerSeed?

    func seedComposerFromShare(text: String, attachments: [PendingAttachment]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        if var existing = pendingShareSeed {
            existing.text = [existing.text, trimmed].filter { !$0.isEmpty }.joined(separator: "\n")
            existing.attachments += attachments
            pendingShareSeed = existing
        } else {
            pendingShareSeed = ShareComposerSeed(text: trimmed, attachments: attachments)
        }
    }

    func consumeShareSeed() -> ShareComposerSeed? {
        defer { pendingShareSeed = nil }
        return pendingShareSeed
    }

    /// Reachability of the Hermes Sessions API itself — the direct connection
    /// (localhost:8642) that actually carries chat, independent of the relay.
    /// The relay is offline by design, so the Chat screen drives its connectivity
    /// UI from this rather than relay-sourced host status (which would otherwise
    /// paint a false "offline" banner). Updated by `refreshDirectHealth()`.
    private(set) var directConnectionStatus: ConnectionStatus = .disconnected
    private var isPollingEnabled = false
    private var pollingTask: Task<Void, Never>?
    /// #293(a): identity for `pollingTask` / `reconcileTask`, bumped when
    /// each loop is armed. A finishing loop clears its handle only while its
    /// generation is still current — the house pattern (`finishRun(_:)`,
    /// `clearActiveRunContext(matchingRunID:)`, `bootstrapGeneration`), which
    /// these two loops were the only ones in the file not applying.
    private var pollingGeneration = 0
    private var reconcileGeneration = 0
    private var streamingTask: Task<Void, Never>?
    private(set) var streamingMessageID: UUID?
    /// #291: the USER row belonging to the turn `streamingMessageID`'s
    /// placeholder is answering. Held so a Stop can settle precisely that
    /// row (see `settleStoppedUserMessage`) instead of sweeping every
    /// `.sending` user row in the transcript. Set beside the placeholder in
    /// `sendMessage`, cleared wherever that turn ends.
    private var streamingUserMessageID: UUID?

    /// #295: the session id of the turn currently streaming, captured so a
    /// later `cancelStreaming` can recover it (the expiration path arms real
    /// recovery from it — Task 2). Comes from the shared journal's active
    /// hop (`activeSessionID`) — `SessionsHermesClient.ensureHopForTurn()`
    /// records that hop before ANY stream event is yielded, so it is already
    /// correct by the time `sendMessage`'s loop processes its first update;
    /// refreshed every iteration below because a stale-hop 404 retry can
    /// swap the hop mid-turn with no event of its own. Cleared on every
    /// terminal path — normal finish, every error arm, and `cancelStreaming`
    /// — so a stale value can never survive into a later turn.
    ///
    /// #295 review follow-up: this used to be a `(sessionId:runId:)` tuple,
    /// but `runId` was dead weight — it is written ONLY by the per-iteration
    /// refresh below, which always carries forward whatever it already was
    /// (`self.activeStreamRun?.runId`), and nothing ever sets it to a real
    /// value: `runId` has no channel earlier than the `.interrupted` case
    /// itself (confirmed by reading `SessionsHermesClient.streamTurn`:
    /// `run.started`'s parsed `run_id` is a local var, never surfaced on any
    /// other `StreamingUpdate` case), and `.interrupted` uses its OWN
    /// case-bound `runId`, never this property, before nil-ing it out as a
    /// terminal path. So it was provably always nil here — dropped rather
    /// than carried as a field that looked meaningful but never was. The
    /// `.interrupted` arm's `armPendingRunRecovery` call still passes its
    /// real, case-bound `runId`; `cancelStreaming`'s call passes `nil`
    /// explicitly, honestly, for the same reason this field is gone.
    // harness-visible
    var activeStreamRun: String?

    var isStreaming: Bool { streamingMessageID != nil }

    /// #278: **the** "is a run in flight" question, for the bubble menu and
    /// for the store's own history-mutating guards alike.
    ///
    /// `isStreaming` is NOT that question and using it as such is what shipped
    /// the bug: leaving the chat screen mid-run drops the SSE connection, the
    /// stream yields `.interrupted`, and its handler sets
    /// `streamingMessageID = nil` while `pendingRun` stays live and the
    /// reconcile loop keeps going — nothing ever re-arms `streamingMessageID`.
    /// So for the whole reconcile window (minutes) `isStreaming` reads false
    /// while the run is very much alive, and Edit & Resend was both OFFERED
    /// and HONORED on it: it truncated under a live run, and the resend posted
    /// a SECOND run to the same server session.
    ///
    /// The menu and the store must read the same predicate — a menu that
    /// hides an item the store would still honor is a gate in name only.
    var isTranscriptBusy: Bool { streamingMessageID != nil || pendingRun != nil }

    /// #203 (1A): how long a streaming turn may go with NO sign of life
    /// before the UI says so. 8s is comfortably past a normal on-device
    /// first token (#208 measured whole turns at 35–49 output tokens) and
    /// well short of the 35s the battery guillotine uses.
    nonisolated static let stallHintAfter: TimeInterval = 8

    /// True when a turn is streaming and has been silent past the threshold.
    /// Pure function of two stored values, so it is unit-testable without a
    /// live stream.
    nonisolated static func isStalled(isStreaming: Bool, lastActivityAt: Date?,
                                      now: Date = .now) -> Bool {
        guard isStreaming, let lastActivityAt else { return false }
        return now.timeIntervalSince(lastActivityAt) >= stallHintAfter
    }

    /// Dynamic slash command catalog fetched from the connected Hermes host.
    /// Includes gateway commands, installed skills, custom personalities,
    /// and hidden quick-command metadata for manual slash dispatch.
    private(set) var commandCatalog: [SlashCommand] = SlashCommand.allBuiltIn

    /// Active model name from the Hermes agent config (e.g., "gpt-5.4-mini").
    private(set) var activeModelName: String?
    /// Context window size for the active model (e.g., 400000).
    private(set) var contextWindow: Int?

    var currentContextTokens: Int? {
        lastTokenUsage?.promptTokens
    }

    /// #46: session running totals over every metered Hermes turn. Input
    /// tokens sum across turns on purpose — each turn re-reads the context,
    /// so the sum is the billed amount, not the context size. Nil until at
    /// least one turn carries a receipt.
    /// P1 (#90): context-transplant priming accumulates SEPARATELY from
    /// metered chat turns — priming is real spend the user should see, but it
    /// isn't a conversation turn.
    struct SessionUsageTotals: Hashable {
        var promptTokens = 0
        var completionTokens = 0
        var totalTokens = 0
        var meteredTurns = 0
        var totalDuration: TimeInterval = 0
        var primingTokens = 0
        var primingHops = 0
    }

    var sessionUsageTotals: SessionUsageTotals? {
        guard let messages = conversation?.messages else { return nil }
        var totals = SessionUsageTotals()
        for message in messages {
            if message.isContextPriming {
                // A hop demonstrably happened even when its run reported no
                // usage — the count stays honest independent of the tokens.
                totals.primingHops += 1
                totals.primingTokens += message.usage?.totalTokens ?? 0
                continue
            }
            guard message.sender == .hermes, let usage = message.usage else { continue }
            totals.promptTokens += usage.promptTokens
            totals.completionTokens += usage.completionTokens
            totals.totalTokens += usage.totalTokens
            totals.meteredTurns += 1
            totals.totalDuration += message.turnDuration ?? 0
        }
        return (totals.meteredTurns > 0 || totals.primingHops > 0) ? totals : nil
    }

    private let hermesClient: any HermesClientProtocol
    private let chatLiveActivity = LiveActivityService()
    /// #304: the host-approval card's store — the `.approvalRequested` /
    /// `.approvalResolved` consumer, torn down on every turn terminal
    /// (bar 304-E). Wired by AppContainer; nil in constructions that predate
    /// it (tests, previews), where approval updates are safely dropped.
    var hostApprovals: HostApprovalStore?
    let persistence: any AppPersistenceStoreProtocol

    /// P1 (#90): the durable journal — the conversation's primary on-device
    /// record, shared with `SessionsHermesClient` (which reads the hop handle
    /// at send time). ChatStore re-syncs it at every point the settled
    /// transcript changes. Nil in tests that don't exercise continuity.
    let journal: ConversationJournalStore?

    /// Lane J (J-8): the store-level conversation selection — the API session
    /// handle of the journal's active hop. Rows write selection via
    /// `openSession(_:)` and the detail renders `conversation`, so no
    /// view-local selection exists to desync the split-view columns. NOTE:
    /// the sidebar's row highlight deliberately stays server-sourced
    /// (`HermesSessionInfo.isActive`, refreshed after each switch) for Lane F
    /// parity — this observable surface is the local truth for anything that
    /// needs selection without a fetch.
    var activeSessionID: String? { journal?.activeHop?.apiSessionId }

    /// P1 offline compose outbox (#90): turns composed while the Sessions API
    /// is unreachable park here (the SensorUploadService pattern) and drain
    /// oldest-first once it's reachable again.
    private var composeOutbox: ComposeOutboxState
    private var isDrainingComposeOutbox = false

    /// #277: the durable per-thread record of agent-written file chips (#21),
    /// write-through cached here. See `AgentAttachmentSidecar` for the key
    /// design; the short version is that `openSession` ASSIGNS the server
    /// transcript (which carries no attachments) and the conversation cache is
    /// a single slot the next thread evicts, so leaving a thread and coming
    /// back used to lose every chip in it while the staged bytes sat safe on
    /// disk.
    private var agentAttachments: AgentAttachmentSidecar

    /// #277: the last thread opened from the drawer. The sidecar's thread key
    /// is the SERVER SESSION ID; `activeSessionID` (the journal hop) is the
    /// authority and covers a NEW chat, which never goes through
    /// `openSession` — this is the fallback for threads that have no hop
    /// (local-brain sessions). Cleared on New chat and reset so a fresh
    /// thread's chips can never be filed under the departed thread's id.
    private var lastOpenedSessionID: String?

    /// The session id this conversation's chips are filed under, or nil when
    /// the thread has no server handle yet (a brand-new chat before its first
    /// turn). Nil means "do not record" — never "record under a guess".
    private var agentAttachmentThreadID: String? { activeSessionID ?? lastOpenedSessionID }
    /// Set when the in-flight send just re-queued its turn (still
    /// unreachable) — tells the drain loop to stop instead of spinning.
    private var didQueueComposeTurnDuringSend = false
    /// The outbox ENTRY id the in-flight send just queued under (#306 T1:
    /// the entry's own id, not the row's) — lets the drain restore a
    /// re-queued turn to the FRONT by identity, not by text match.
    private var lastQueuedComposeTurnID: UUID?

    /// Read-aloud (#2), wired by AppContainer. When `autoReadAloudEnabled`
    /// returns true, streamed `assistant.delta` chunks are fed to the TTS
    /// sentence buffer as they arrive. Both stay nil in tests.
    var speechOutput: SpeechOutputService?
    var autoReadAloudEnabled: (@MainActor () -> Bool)?

    /// #190: the keyed local-session store, wired by AppContainer. The
    /// walk-away persist inside `abandonPendingRun` writes through this; nil
    /// (tests, container-creation failure) restores pre-#190 behavior.
    var localSessions: (any LocalSessionStoring)?
    /// #190: the standalone-thread discriminator — same rule the local
    /// backend uses for legacy adoption, wired by AppContainer. Nil never
    /// persists (a conversation must be POSITIVELY local to enter the store;
    /// paired-mode Hermes threads must not). Since #190B the wired rule is
    /// ORIGIN-based — no host configured, or the id is already store-known —
    /// and membership is established below in
    /// `recordLocalOriginAfterSettledTurn`, never by scanning brain stamps.
    var isLocalSessionThread: (@MainActor (Conversation) -> Bool)?

    /// #190B: a failed session open, surfaced as state the UI renders — the
    /// old catch logged and returned, which is how a deterministic dead tap
    /// stayed invisible on device while the suite ran green (#189/#191's
    /// false-green family). Cleared by the next successful open, a new chat,
    /// or an explicit dismiss.
    struct SessionOpenFailure: Equatable {
        let sessionID: String
        let message: String
    }

    private(set) var sessionOpenFailure: SessionOpenFailure?

    func dismissSessionOpenFailure() {
        sessionOpenFailure = nil
    }

    /// On-device FoundationModels intelligence (#4.8 × #4.15), wired by
    /// AppContainer: conversation title + preview after the first completed
    /// exchange, one-line reasoning condensation. Stays nil in tests.
    var localIntelligence: LocalIntelligenceService?

    /// #14: wraps a deliberately-backgroundable long send (attachments — the
    /// #38 long-send path) in a BGContinuedProcessingTask so iOS shows system
    /// progress and keeps the run alive past app exit. Wired by AppContainer;
    /// stays nil in tests (no BGTaskScheduler in the test host).
    var beginContinuedSend: (@MainActor (String) -> ContinuedProcessingHandle?)?
    private var isGeneratingConversationCard = false

    /// #21 Tier 2: downloads a fetchable agent file — (birth profile id,
    /// route-form remote path) → a local temp URL. Wired by AppContainer to
    /// the per-profile relay factory (Lane M: the file lives on the
    /// announcing session's birth-profile relay, never a global base URL).
    /// Nil in tests and unwired constructions — the tap then fails honestly.
    var agentFileDownloader: (@MainActor (UUID?, String) async throws -> URL)?

    /// #21 Tier 2: in-flight/failed download state per attachment id, driving
    /// the fetchable bubble's spinner and honest-failure row.
    private(set) var agentFileDownloads: [UUID: AgentFileDownloadState] = [:]

    /// A run whose stream dropped (e.g. backgrounded on lock) but which is still
    /// running server-side. Reconciled via the Sessions messages endpoint when it
    /// completes. `sentAt` is captured here so reconcile is insulated from the
    /// relay-poll machinery that owns `pendingMessageSentAt`.
    private struct PendingRun {
        let sessionId: String
        let runId: String?
        let userMessageID: UUID
        let sentAt: Date
        /// Reasoning streamed before the drop (#4.15). The server transcript
        /// filters `_thinking`, so this local copy is the only survivor —
        /// re-attached to the reply when reconcile adopts it.
        let partialReasoning: String?
    }
    private var pendingRun: PendingRun?
    private var reconcileTask: Task<Void, Never>?
    /// #226 leg (c) / #227 instance 3: concurrent `reconcilePendingRuns()`
    /// callers coalesce onto this one in-flight pass. Distinct from
    /// `reconcileTask`, which is the polling LOOP started when a reconcile
    /// finds the run unfinished.
    private var reconcileInFlight: Task<Void, Never>?

    /// #145 Part C — the reconcile loop's budget is WALL CLOCK, not an attempt
    /// count.
    ///
    /// It used to read `maxAttempts = 60 // 60 x 2s = ~2 min`. **That comment
    /// budgeted only the `Task.sleep` and ignored the network call.** Every
    /// attempt runs `attemptReconcile` → `reconcileFromServer()`, an unbounded
    /// gateway fetch, so against a black-holed host (#136: packets DROPPED, so
    /// each request eats the full 60s `URLSession` timeout) the real ceiling was
    /// 60 × (2s + 60s) ≈ **62 minutes, not 2.** The loop is armed from the
    /// foreground chain and kept grinding long after the outage ended — one of
    /// the three reasons #145 outlives the outage that caused it.
    ///
    /// **An attempt counter cannot bound a loop whose per-attempt cost is
    /// unbounded.** A comment asserting a budget the code does not enforce is
    /// how this survived review, so the budget is now the thing the loop
    /// actually checks.
    ///
    /// **This bounds the LOOP, not a single call.** The deadline is only tested
    /// between attempts, so one hung fetch can still outlive it. Bounding the
    /// CALL is #145 Part A (a real `timeoutIntervalForResource` on the chat
    /// plane, which today defaults to `URLSession.shared`'s **7 days**). The two
    /// are complementary and **neither alone closes #145** — do not read this
    /// fix as making the chat plane safe on its own.
    // harness-visible: tests shrink these so the suite pays ~300ms, not ~2min.
    var reconcileWallClockBudget: Duration = .seconds(120)
    // harness-visible
    var reconcilePollInterval: Duration = .seconds(2)
    /// #145 Part C: lets a test watch the loop retire itself instead of sleeping
    /// a fixed duration and asserting on a stopwatch (which would be flaky under
    /// load — #183's territory).
    // harness-visible
    var hasActiveReconcileLoop: Bool { reconcileTask != nil }

    /// #237: run ids whose reconcile ALREADY ADOPTED a reply. A dying
    /// stream's late duplicate `.interrupted` must not re-arm one — that was
    /// the observed double-adoption (two notifications, thread quadrupled).
    /// Records only adoptive resolutions (never abandons); run ids are
    /// globally unique, so the set needs no clearing — a resolved run must
    /// never re-arm, even across thread switches. App-session lifetime.
    private var resolvedRunIDs: Set<String> = []

    /// Session id of the run awaiting reconcile, if any — what the relay's
    /// completion watcher needs to be told about (#38).
    var pendingRunSessionId: String? { pendingRun?.sessionId }

    /// #235 F3 — Owen's placement rule, pure so it truth-tables: a recovered
    /// reply below later exchanges is where nobody is looking; move it to the
    /// tail and stamp WHICH question it answers so it cannot masquerade as a
    /// reply to the newest one. Undisplaced → identity, byte-identical.
    nonisolated static func placingRecoveredReply(
        _ replyID: UUID, prompt: String?, in messages: [Message]
    ) -> [Message] {
        guard let idx = messages.firstIndex(where: { $0.id == replyID }),
              idx != messages.indices.last else { return messages }
        var result = messages
        var reply = result.remove(at: idx)
        reply.recoveredForPrompt = prompt.map { String($0.prefix(60)) } ?? "an earlier question"
        result.append(reply)
        return result
    }

    /// Called when conversation content changes (new message, streaming complete).
    /// Used by AppContainer to push widget data updates.
    var onConversationChanged: (@MainActor () -> Void)?

    /// #17: fired with the fresh session list whenever it's fetched — wired by
    /// AppContainer to Spotlight donation (gated there). Stays nil in tests.
    var onSessionsLoaded: (@MainActor ([HermesSessionInfo]) -> Void)?
    /// A pending run was resolved in-app (reconciled or abandoned). An
    /// observation seam — #237's resolution-idempotence tests assert through
    /// it; no production consumer since notification removal (#238).
    var onRunResolved: (@MainActor (String) -> Void)?

    /// A send reached a terminal failure the user will see (stream error
    /// before job acceptance, or polling exhaustion). Wired by AppContainer
    /// to the error haptic. Deliberately NOT fired by the cold-load cache
    /// finalization (#56) — that's bookkeeping for an old failure, and a
    /// buzz at launch would have no visible cause.
    var onSendFailed: (@MainActor () -> Void)?

    init(
        hermesClient: any HermesClientProtocol,
        persistence: any AppPersistenceStoreProtocol,
        journal: ConversationJournalStore? = nil
    ) {
        self.hermesClient = hermesClient
        self.persistence = persistence
        self.journal = journal
        self.composeOutbox = persistence.loadComposeOutboxState()
        self.agentAttachments = persistence.loadAgentAttachmentSidecar()
    }

    /// #277: files the current thread's agent-file chips under its server
    /// session id. Called wherever the settled transcript is persisted, so
    /// the sidecar's durability matches the conversation cache's exactly —
    /// a turn that never reached the cache never reached this either.
    ///
    /// Recording is a full REPLACE of that thread's rows, not a union: the
    /// rows are computed over the whole transcript, so they are already the
    /// complete answer, and a union would resurrect a chip that a truncation
    /// (#78) deliberately removed. A transcript with no chips writes nothing
    /// rather than an empty entry — an empty entry would occupy an LRU slot
    /// and evict a thread that has real records.
    /// `under` names the thread explicitly. `openSession` passes it because
    /// at that point the journal has not been re-synced yet, so a non-hop
    /// backend (the local brain) would still be reporting the DEPARTING
    /// Hermes thread's hop — filing the arriving thread's chips under the
    /// wrong session id. Everywhere else the hop is already correct.
    private func recordAgentAttachments(under explicitSessionID: String? = nil) {
        guard let sessionID = explicitSessionID ?? agentAttachmentThreadID,
              let conversation else { return }
        let rows = AgentAttachmentSidecar.rows(from: conversation.messages)
        guard !rows.isEmpty else { return }
        var updated = agentAttachments
        updated.record(sessionID: sessionID, rows: rows)
        guard updated != agentAttachments else { return }
        agentAttachments = updated
        persistence.saveAgentAttachmentSidecar(updated)
    }

    func loadConversationIfNeeded() async {
        if conversation == nil {
            conversation = persistence.loadConversationCache()
            // #237: heal pre-fix adopted-echo corruption at the restore
            // boundary — Owen's quadrupled thread renders single copies on
            // first load under the fix (bar 237-E's sim-reachable half).
            if var restored = conversation {
                restored.messages = Conversation.dedupingAdoptedEchoes(restored.messages)
                conversation = restored
            }
            if let cachedUsage = conversation?.latestUsage {
                lastTokenUsage = cachedUsage
            }
            finalizeStaleSendsFromCache()
            // #306 matrix row 12: no turn survives a relaunch — every
            // still-held entry surfaces, and nothing fires at launch.
            surfaceHeldTurnsAfterColdLoad()
        }
        if conversation != nil {
            // P1 (#90): align the journal with the restored thread. A cache
            // that predates the journal (id mismatch) rebuilds it with no hop
            // — the next Hermes turn hops fresh and transplants.
            if let conversation {
                journal?.sync(with: conversation)
            }
            // Queued offline turns drain as soon as there's a thread to
            // drain into; still-unreachable sends just re-queue.
            Task { [weak self] in await self?.drainComposeOutboxIfPossible() }
            return
        }
        await loadConversation()
    }

    /// Cache hygiene on cold load (#56). A user message still `.sending` in a
    /// freshly loaded cache belongs to a process that died mid-stream — no
    /// stream survives a relaunch, so that state can never resolve; flip it to
    /// `.failed` (the same terminal the polling-exhaustion path uses) so it
    /// renders with the retry affordance instead of pending forever. Honest
    /// caveat: the run may in fact have completed server-side (the in-memory
    /// pendingRun/session id don't survive process death), so the sessions
    /// drawer remains the authoritative view and retry is user-mediated, not
    /// automatic. Also scrubs any cached streaming placeholder (empty Hermes
    /// `.sending` row) that a mid-stream save (e.g. relay polling) let slip in.
    private func finalizeStaleSendsFromCache() {
        guard var conv = conversation else { return }
        var didChange = false

        for i in conv.messages.indices
        where conv.messages[i].sender == .user && conv.messages[i].status == .sending {
            conv.messages[i].status = .failed
            didChange = true
        }

        // #90: a `.queued` row whose compose-outbox entry vanished (cleared
        // state, decode failure) can never drain — flip it to .failed so it
        // gets the retry affordance instead of pending forever. Rows WITH an
        // entry stay queued by design: they survive relaunch and drain on
        // reachability. #306 T1: keyed by `transcriptRowID` now — only
        // `.unreachable` parks have rows; a mid-turn hold has nothing here
        // for this scrub to see, which is bar 306-F's corollary.
        let queuedTurnIDs = Set(composeOutbox.pendingTurns.compactMap(\.transcriptRowID))
        for i in conv.messages.indices
        where conv.messages[i].sender == .user
            && conv.messages[i].status == .queued
            && !queuedTurnIDs.contains(conv.messages[i].clientMessageID ?? conv.messages[i].id) {
            conv.messages[i].status = .failed
            didChange = true
        }

        let placeholderCount = conv.messages.count
        conv.messages.removeAll {
            $0.sender == .hermes
                && $0.status == .sending
                && $0.content.isEmpty
                && $0.toolActivities.isEmpty
        }
        didChange = didChange || conv.messages.count != placeholderCount

        guard didChange else { return }
        chatLog.notice("cold load: finalized stale in-flight send state from cache (#56)")
        conversation = conv
        persistence.saveConversationCache(conv)
    }

    func loadConversation() async {
        isLoading = true
        defer { isLoading = false }
        let cachedConversation = conversation ?? persistence.loadConversationCache()
        conversation = mergeConversationMetadata(
            from: cachedConversation,
            into: await hermesClient.loadConversation()
        )
        // #25: while a run is live, a refresh source's conversation-level
        // usage is an interim number (relay legacy accounting, another
        // backend's thread) — the gauge keeps the previous turn's honest
        // value until this run's own run.completed lands.
        if streamingMessageID == nil, let latestUsage = conversation?.latestUsage {
            lastTokenUsage = latestUsage
        }
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
            journal?.sync(with: conversation)
        }
        restartPendingPollingIfNeeded()
    }

    /// Returns whether the turn actually dispatched — false when a guard
    /// swallowed it (empty content, duplicate of a pending row). The compose
    /// outbox drain needs the distinction: a swallowed turn produced no
    /// stream, so neither success nor a re-queue happened (#90).
    @discardableResult
    func sendMessage(_ content: String, attachments: [PendingAttachment] = []) async -> Bool {
        // Reset FIRST, before any guard: the drain reads this after every
        // send, and a stale true from the previous send would corrupt its
        // stop/continue decision.
        didQueueComposeTurnDuringSend = false
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !attachments.isEmpty else { return false }
        guard hasPendingDuplicateMessage(trimmedContent, attachments: attachments) == false else { return false }

        let clientMessageID = UUID()
        let displayContent = trimmedContent.isEmpty && !attachments.isEmpty
            ? "[\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")]"
            : trimmedContent
        let optimistic = Message(
            id: clientMessageID,
            clientMessageID: clientMessageID,
            sender: .user,
            content: displayContent,
            status: .sending,
            attachments: attachments.map { MessageAttachment(from: $0) }
        )
        if conversation == nil {
            conversation = Conversation(title: Conversation.defaultTitle)
        }
        conversation?.messages.append(optimistic)
        conversation?.lastActivity = optimistic.timestamp
        pendingMessageSentAt = optimistic.timestamp
        lastStreamActivityAt = optimistic.timestamp

        // Persist the optimistic turn NOW, before streaming starts — the next
        // save otherwise only happens after the stream ends, so a process
        // death mid-run (Siri background launch reaped past the intent budget
        // (#56), app killed mid-stream) used to lose the sent exchange from
        // the cache entirely. Deliberately saved BEFORE the placeholder below
        // is appended: the placeholder is transient stream UI, and cold load
        // treats a cached one as garbage (see loadConversationIfNeeded).
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }

        // Append a placeholder Hermes message for streaming content
        let placeholderID = UUID()
        let placeholder = Message(
            id: placeholderID,
            sender: .hermes,
            content: "",
            status: .sending,
            isStreaming: true
        )
        conversation?.messages.append(placeholder)
        streamingMessageID = placeholderID
        // #291: the placeholder and the user row it answers are one turn —
        // a Stop has to be able to settle both.
        streamingUserMessageID = clientMessageID
        // #295: this turn hasn't learned its identifiers yet — an explicit
        // reset here (rather than trusting the previous turn's terminal to
        // have cleared it) documents "captured at stream start" at the one
        // place a new stream actually starts.
        activeStreamRun = nil
        restartPendingPollingIfNeeded()

        // #14: attachment sends are the deliberately-backgroundable long path —
        // wrap them in a continued-processing task (submitted here, in the
        // foreground, from the user's explicit send). Plain text turns stay
        // lightweight. On system revocation the stream would die on suspension
        // anyway, so expiration finalizes partial content via cancelStreaming.
        // #283 review re-review: `hardStopHost: false` — the SYSTEM revoked
        // the background budget, not the user tapping Stop, so the host run
        // must be left alone (recoverable via the ordinary poll) rather than
        // hard-killed. See `cancelStreaming`'s doc.
        let continuedSend = attachments.isEmpty ? nil : beginContinuedSend?(displayContent)
        continuedSend?.onExpiration = { [weak self] in self?.cancelStreaming(hardStopHost: false) }

        let stream = hermesClient.sendStreaming(message: trimmedContent, attachments: attachments, clientMessageID: clientMessageID)
        var acceptedJobID: UUID?
        var needsPollingFallback = false
        // P1 (#90): whether the settled exchange rode the active Hermes hop —
        // drives the journal's hop-waterline bump after the stream ends.
        var finishedViaHermesHop = false
        // #190B: whether this turn settled on a local brain — drives the
        // origin-based store membership below (`recordLocalOriginAfterSettledTurn`).
        var settledLocalBrainTurn = false

        streamingTask = Task { [weak self] in
            guard let self else { return }
            for await update in stream {
                if Task.isCancelled { break }
                // #295: refresh the captured session id on every event —
                // cheap, and the one thing that can change it mid-turn (a
                // stale-hop 404 retry re-hops inside the client with no
                // event of its own) needs the next iteration to see the
                // swap.
                if let sid = self.activeSessionID {
                    self.activeStreamRun = sid
                }
                switch update {
                case .messageSent(let jobID):
                    acceptedJobID = jobID
                    continuedSend?.advance(to: .accepted)

                case .textDelta(let delta):
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        conv.messages[idx].content += delta
                        conv.messages[idx].toolActivity = nil
                        for i in conv.messages[idx].toolActivities.indices {
                            conv.messages[idx].toolActivities[i].isActive = false
                        }
                        self.conversation = conv
                    }
                    if self.autoReadAloudEnabled?() == true {
                        self.speechOutput?.enqueueStreamChunk(delta, messageID: placeholderID)
                    }
                    continuedSend?.advance(to: .streaming)
                    continuedSend?.tick()
                    self.lastStreamActivityAt = .now

                case .reasoningDelta(let delta):
                    continuedSend?.tick()
                    self.lastStreamActivityAt = .now
                    // #4.15: accumulate the `_thinking` channel on the streaming
                    // placeholder — the bubble shows the newest line verbatim
                    // while the model reasons, ahead of any answer text.
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        conv.messages[idx].reasoning = (conv.messages[idx].reasoning ?? "") + delta
                        self.conversation = conv
                    }

                case .toolActivity(let event):
                    self.lastStreamActivityAt = .now
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        switch event.phase {
                        case .started:
                            // Tools run serially, so a new start resolves any
                            // still-active predecessor.
                            for i in conv.messages[idx].toolActivities.indices {
                                conv.messages[idx].toolActivities[i].isActive = false
                            }
                            // Anchor at the content streamed so far — this is
                            // what places the chip inline in the transcript (#10).
                            let activity = ToolActivity(
                                label: event.name,
                                detail: event.detail,
                                anchorOffset: conv.messages[idx].content.count
                            )
                            conv.messages[idx].toolActivities.append(activity)
                            conv.messages[idx].toolActivity = event.name
                        case .completed:
                            // tool.completed is usually empty on the wire; when
                            // it does name the tool, resolve its newest chip.
                            if let last = conv.messages[idx].toolActivities.lastIndex(where: {
                                $0.isActive && $0.label == event.name
                            }) {
                                conv.messages[idx].toolActivities[last].isActive = false
                                // #296 (296-C1): on a `.completed` event
                                // `detail` is the host's FAILURE text, not an
                                // input summary — see `ToolCallEvent.detail`.
                                // It goes to `failure`; the started event's
                                // `detail` (what the call touched) is left
                                // exactly as it was, because overwriting it
                                // would trade the more useful of the two away.
                                // Empty is treated as absent: a host that
                                // sends `"error": ""` on a SUCCESS is saying
                                // nothing went wrong, and writing "" would
                                // flip a completed call to interrupted — the
                                // #296 defect in reverse, which is 296-B.
                                if let failure = event.detail, !failure.isEmpty {
                                    conv.messages[idx].toolActivities[last].failure = failure
                                }
                            }
                        }
                        self.conversation = conv
                    }
                    if event.phase == .started {
                        // Show tool progress on Lock Screen / Dynamic Island
                        self.chatLiveActivity.startToolCall(toolName: event.name)
                        self.chatLiveActivity.updateToolProgress(event.name)
                    }
                    continuedSend?.tick()

                case .artifactProduced(let attachment):
                    // #258: the agent wrote a file and its bytes are already
                    // staged — put the chip on the still-streaming placeholder
                    // instead of making the user wait out the turn. Idempotent
                    // by id, so a re-delivery can never double the row.
                    self.lastStreamActivityAt = .now
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }),
                       !conv.messages[idx].attachments.contains(where: { $0.id == attachment.id }) {
                        // #262: stamp the generation point — the mirror of the
                        // tool-chip anchor above — so the chip renders inline
                        // where the file was written and stays there while the
                        // rest of the turn streams beneath it.
                        var anchored = attachment
                        anchored.anchorOffset = conv.messages[idx].content.count
                        conv.messages[idx].attachments.append(anchored)
                        self.conversation = conv
                    }
                    continuedSend?.tick()

                case .contextPrimed(let usage):
                    // P1 (#90): a fresh server session was just primed with
                    // condensed journal context, before this turn was posted.
                    // Surface the hop honestly in the transcript; the notice
                    // carries the priming turn's real cost so the session
                    // totals add up (priming is not free).
                    let notice = self.makePrimingNotice(usage: usage)
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        conv.messages.insert(notice, at: idx)
                        self.conversation = conv
                    } else {
                        self.conversation?.messages.append(notice)
                    }
                    continuedSend?.tick()

                case .modelResolved(let runtime):
                    // #223 Lane 5: header attribution from the gateway's own
                    // report of which model served the turn — resolved truth,
                    // not the optimistic pick. Display uses the id's tail
                    // ("deepseek/deepseek-v4-flash-0731" → the flash id alone).
                    if let resolved = runtime.model, !resolved.isEmpty {
                        activeModelName = resolved.split(separator: "/").last.map(String.init) ?? resolved
                    }

                case .approvalRequested(let request):
                    // #304: the HOST's question (or its degraded,
                    // question-less shape) — routed to the card's store. A
                    // different actor from ToolConfirmationCenter, and the
                    // two cards can be on screen at once.
                    self.lastStreamActivityAt = .now
                    if request.question == nil {
                        self.hostApprovals?.raiseDegraded(
                            runID: request.runID,
                            profileID: request.profileID,
                            endpoint: request.endpoint
                        )
                    } else {
                        self.hostApprovals?.raise(request)
                    }
                    continuedSend?.tick()

                case .approvalResolved(let runID, let choice):
                    // #304: idempotent teardown — our own POST's echo or
                    // someone else's answer (bar 304-E).
                    self.hostApprovals?.markResolved(runID: runID, choice: choice)

                case .finished(let finalMessage, let usage, let diff):
                    finishedViaHermesHop = finalMessage.sender == .hermes
                        && (finalMessage.brain == nil || finalMessage.brain == ChatBackendRouter.Brain.hermes.rawValue)
                    settledLocalBrainTurn = finalMessage.sender == .hermes
                        && (finalMessage.brain == ChatBackendRouter.Brain.onDevice.rawValue
                            || finalMessage.brain == ChatBackendRouter.Brain.privateCloud.rawValue)
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        let activities = self.conversation?.messages[idx].toolActivities ?? []
                        let streamedReasoning = self.conversation?.messages[idx].reasoning
                        let streamedArtifacts = self.conversation?.messages[idx].attachments ?? []
                        var resolved = finalMessage
                        resolved.toolActivities = activities
                        resolved.codeDiff = diff
                        // #258: the final message's list LEADS — it is the
                        // authoritative one (`run.completed` is where the #21
                        // Tier 2 fetchables get appended). Artifacts the
                        // stream already put on screen are merged in behind
                        // it rather than overwritten away, so a backend whose
                        // finish doesn't repeat them can't make a chip the
                        // user watched appear vanish at the end of the turn.
                        // Dedupe is by attachment id: the Sessions client
                        // yields the SAME value it accumulates into
                        // `producedFiles`, so the streamed chip and its
                        // final-message twin are one row (bar 258-A). Two
                        // genuine writes to one path stay two rows — distinct
                        // ids, distinct staged bytes, write order preserved.
                        if !streamedArtifacts.isEmpty {
                            // #262: the final list's twin of a streamed chip
                            // carries no anchor (the client built it before
                            // the store stamped one) — transfer the streamed
                            // anchor onto it, or the chip would drop from its
                            // inline spot to the trailing grid at the finish
                            // boundary: the exact jump the lane removes.
                            let streamedAnchors = Dictionary(
                                streamedArtifacts.compactMap { chip in
                                    chip.anchorOffset.map { (chip.id, $0) }
                                },
                                uniquingKeysWith: { first, _ in first }
                            )
                            for i in resolved.attachments.indices
                            where resolved.attachments[i].anchorOffset == nil {
                                resolved.attachments[i].anchorOffset =
                                    streamedAnchors[resolved.attachments[i].id]
                            }
                            var seen = Set(resolved.attachments.map(\.id))
                            for artifact in streamedArtifacts where seen.insert(artifact.id).inserted {
                                resolved.attachments.append(artifact)
                            }
                        }
                        // #4.15: keep the accumulated reasoning when the final
                        // message doesn't carry its own (relay/mock clients) —
                        // unless it just mirrors the answer (#60: the defective
                        // `_thinking` channel echoes the answer verbatim; the
                        // client refused to attach it, so the placeholder's
                        // copy must not resurrect it here).
                        if resolved.reasoning == nil,
                           let streamed = streamedReasoning, !streamed.isEmpty,
                           !SessionsHermesClient.reasoningMirrorsAnswer(streamed, content: resolved.content) {
                            resolved.reasoning = streamed
                        }
                        // #46: the turn receipt. Usage rode this run's
                        // `run.completed` (or the local brain's session
                        // stats); duration is wall-clock from the optimistic
                        // send; the serving model keys cost estimates.
                        // Previously each turn overwrote the last in
                        // lastTokenUsage and rendered nowhere.
                        if resolved.usage == nil { resolved.usage = usage }
                        if resolved.turnDuration == nil {
                            resolved.turnDuration = self.pendingMessageSentAt.map {
                                Date.now.timeIntervalSince($0)
                            }
                        }
                        // Hermes-brain turns only: `activeModelName` is the
                        // gateway's model, and stamping it on an on-device /
                        // PCC turn (#27 brain tags) would price a free local
                        // turn at the Hermes model's rate.
                        if resolved.servingModel == nil,
                           resolved.brain == nil || resolved.brain == ChatBackendRouter.Brain.hermes.rawValue {
                            resolved.servingModel = self.activeModelName
                        }
                        // #120: a mid-stream conversation merge (the 2s relay
                        // poll, a refresh) can already have adopted this reply
                        // from a backend that appends it before yielding
                        // `.finished` (LocalChatBackend, the mock). Replacing
                        // the placeholder would then render the same UUID
                        // twice — undefined ForEach behavior. Drop any
                        // pre-merged copy; the placeholder's slot keeps the
                        // row (it's the bubble the user watched stream).
                        if var conv = self.conversation {
                            conv.messages.removeAll { $0.id == resolved.id && $0.id != placeholderID }
                            if let slot = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                                conv.messages[slot] = resolved
                            }
                            self.conversation = conv
                        }
                    }
                    // The direct stream completed, so this message definitively
                    // succeeded — mark it delivered, recovering even if the relay
                    // polling fallback had already flipped it to .failed.
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                        if self.conversation?.messages[idx].status != .delivered {
                            self.conversation?.messages[idx].status = .delivered
                        }
                    }
                    self.conversation = self.mergeConversationMetadata(
                        from: self.conversation,
                        into: self.hermesClient.currentConversation
                    )
                    // #25: run.completed is the numerator's authority — a
                    // conversation-level number the merge carried in (relay
                    // accounting, a stale cache) must not outrank it.
                    if let usage {
                        self.lastTokenUsage = usage
                    } else if let latestUsage = self.conversation?.latestUsage {
                        self.lastTokenUsage = latestUsage
                    }
                    self.detectModelSwitch(from: finalMessage.content)
                    self.streamingMessageID = nil
                    // #295: the turn is fully settled — no later cancelStreaming
                    // could still need these identifiers.
                    self.activeStreamRun = nil
                    self.pendingMessageSentAt = nil
                    // #304 bar 304-E: the driver exited — an outstanding
                    // approval card is torn down, never left tappable.
                    self.hostApprovals?.clearForTurnEnd()
                    self.chatLiveActivity.endActivity()
                    // #110: the finished content lets the service retract the
                    // pending queue when a #102 breaker trip shortened the
                    // reply below what already streamed to the synthesizer.
                    self.speechOutput?.finishStream(
                        messageID: placeholderID,
                        finishedContent: finalMessage.content
                    )
                    continuedSend?.finish(success: true)
                    // #306 matrix row 1: the ONE terminal that fires.
                    self.resolveHeldTurn(after: .completed)

                case .interrupted(let sessionId, let runId):
                    // #237: a late duplicate from a dying stream must not
                    // re-arm a run whose reconcile already adopted — that was
                    // the double-adoption. Tear the turn down quietly instead.
                    if let runId, self.resolvedRunIDs.contains(runId) {
                        if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                            self.conversation?.messages.remove(at: idx)
                        }
                        self.streamingMessageID = nil
                        // #295: a late duplicate is still a terminal outcome
                        // for THIS stream — nothing left to capture for.
                        self.activeStreamRun = nil
                        self.hostApprovals?.clearForTurnEnd()   // #304 bar 304-E
                        self.chatLiveActivity.endActivity()
                        self.speechOutput?.cancelStream(messageID: placeholderID)
                        continuedSend?.finish(success: true)
                        // #306 matrix row 4: noise from a dying stream —
                        // whatever the queue was doing, it keeps doing.
                        self.resolveHeldTurn(after: .lateDuplicate)
                        break
                    }
                    // Run committed server-side but the stream dropped (lock /
                    // background). Not a failure: mark the turn working and let the
                    // reconcile loop pick up the reply when it lands.
                    // #295 Task 2: placeholder-removal + PendingRun mint +
                    // reconcile-arm now live in `armPendingRunRecovery` — the SAME
                    // helper `cancelStreaming(hardStopHost: false)` calls, so the
                    // two arms cannot drift apart.
                    self.armPendingRunRecovery(
                        placeholderID: placeholderID,
                        sessionId: sessionId,
                        runId: runId,
                        userMessageID: clientMessageID
                    )
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                        self.conversation?.messages[idx].status = .working
                    }
                    self.streamingMessageID = nil
                    // #295: the identifiers just moved into `pendingRun`
                    // above — this stream's own capture has nothing left to
                    // recover from it.
                    self.activeStreamRun = nil
                    // #304 bar 304-E: `.interrupted` is a driver exit too —
                    // including the degraded Deny card D(i) raised during the
                    // recovery window. Past this point the reconcile loop
                    // owns the run; a card against it would read from a
                    // cleared context. #305 is the filed home for approvals
                    // that outlive the screen.
                    self.hostApprovals?.clearForTurnEnd()
                    self.chatLiveActivity.endActivity()
                    self.speechOutput?.cancelStream(messageID: placeholderID)
                    // #14: the continued task's job — keeping the stream alive —
                    // is over; the reconcile loop owns recovery from here. Not a
                    // failure in the system progress UI.
                    continuedSend?.finish(success: true)
                    // #306 matrix row 3: HOLD until the pendingRun resolves —
                    // firing here is #307's corruption (the reconcile would
                    // adopt the queued turn's reply as this run's answer).
                    self.resolveHeldTurn(after: .streamDroppedRunLive)
                case .unreachable(let errorMessage):
                    // P1 offline compose outbox (#90): the turn never reached
                    // the Sessions API at all. Text-only turns park durably
                    // (`.queued`) and auto-send when the API is reachable
                    // again; attachment turns keep the honest .failed
                    // dead-end — they have no durable wire form to park.
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        self.conversation?.messages.remove(at: idx)
                    }
                    if attachments.isEmpty, !trimmedContent.isEmpty {
                        if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                            self.conversation?.messages[idx].status = .queued
                        }
                        // #306 T1: the row id rides as `transcriptRowID`; the
                        // entry's own id is minted by the store (the broken
                        // fusion). Thread-keyed so the park travels with its
                        // thread (#306 T2 correction).
                        let entryID = self.composeOutbox.enqueueUnreachable(
                            transcriptRowID: clientMessageID,
                            text: trimmedContent,
                            threadKey: self.currentComposeThreadKey
                        )
                        self.persistComposeOutbox()
                        self.didQueueComposeTurnDuringSend = true
                        self.lastQueuedComposeTurnID = entryID
                        chatLog.notice("compose outbox: turn queued while Sessions API unreachable (#90)")
                    } else {
                        if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                            self.conversation?.messages[idx].status = .failed
                        }
                        self.conversation?.messages.append(
                            Message(sender: .system, content: errorMessage, status: .failed)
                        )
                    }
                    self.streamingMessageID = nil
                    // #295: the turn never reached the host at all — nothing
                    // for a later cancelStreaming to recover.
                    self.activeStreamRun = nil
                    self.pendingMessageSentAt = nil
                    self.hostApprovals?.clearForTurnEnd()   // #304 bar 304-E
                    self.chatLiveActivity.endActivity()
                    self.speechOutput?.cancelStream(messageID: placeholderID)
                    continuedSend?.finish(success: false)
                    // #306 matrix row 5: a text turn just parked — the hold
                    // demotes into the same outbox BEHIND it, order
                    // preserved. An attachment turn took the honest .failed
                    // dead-end instead, so the hold SURFACEs.
                    self.resolveHeldTurn(
                        after: attachments.isEmpty && !trimmedContent.isEmpty
                            ? .unreachable : .failedOutright
                    )

                case .failed(let errorMessage):
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        if acceptedJobID == nil {
                            self.conversation?.messages[idx] = Message(
                                sender: .system,
                                content: errorMessage,
                                status: .failed
                            )
                        } else {
                            self.conversation?.messages.remove(at: idx)
                        }
                    }
                    self.streamingMessageID = nil
                    // #295: whether this settles `.failed` or falls through to
                    // the polling fallback below, THIS stream is over —
                    // nothing left for a later cancelStreaming to recover.
                    self.activeStreamRun = nil
                    self.hostApprovals?.clearForTurnEnd()   // #304 bar 304-E
                    self.chatLiveActivity.endActivity()
                    self.speechOutput?.cancelStream(messageID: placeholderID)
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                        self.conversation?.messages[idx].status = acceptedJobID == nil ? .failed : .sending
                    }
                    if acceptedJobID != nil {
                        needsPollingFallback = true
                    } else {
                        self.pendingMessageSentAt = nil
                        self.onSendFailed?()
                    }
                    continuedSend?.finish(success: false)
                    // #306 matrix rows 6/7: an outright failure SURFACEs the
                    // hold (the follow-up was composed against an answer
                    // that never came); a post-accept failure HOLDs — the
                    // poll loop owns the turn and resolves to row 1 or 8.
                    self.resolveHeldTurn(
                        after: acceptedJobID == nil ? .failedOutright : .failedAfterAccept
                    )
                }
            }
        }
        await streamingTask?.value
        streamingTask = nil
        // #291: this turn is over however it ended — a later Stop belongs to
        // whatever turn is live THEN, never to this one's row.
        if streamingUserMessageID == clientMessageID {
            streamingUserMessageID = nil
        }

        // #14: belt-and-braces — a stream that ended without a terminal case
        // must still complete its continued-processing task (idempotent).
        continuedSend?.finish(success: true)

        // If streaming failed after the job was accepted, immediately refresh once
        // and then fall back to polling only if the server still hasn't delivered.
        if needsPollingFallback {
            let refreshed = await hermesClient.loadConversation()
            conversation = mergeConversationMetadata(from: conversation, into: refreshed)
            if let latestUsage = conversation?.latestUsage {
                lastTokenUsage = latestUsage
            }
            streamingMessageID = nil
            restartPendingPollingIfNeeded()
        }

        if !hasPendingMessages {
            pendingMessageSentAt = nil
        }

        if let conversation {
            persistence.saveConversationCache(conversation)
            // #277: a chip the agent produced this turn becomes durable HERE,
            // beside the cache save — the cache is a single slot the next
            // thread evicts, and the server transcript will never give the
            // chip back. Before the sync below, so the hop that carried this
            // turn is still the thread's id.
            recordAgentAttachments()
            onConversationChanged?()
            // P1 (#90): re-sync the durable journal with the settled
            // transcript. A Hermes-brain finish bumps the hop waterline over
            // the new exchange; local-brain turns leave it behind on purpose
            // — that's what marks the hop stale, so the next Hermes turn
            // starts a fresh, re-transplanted session.
            journal?.sync(with: conversation, lastExchangeViaActiveHop: finishedViaHermesHop)
        }

        if settledLocalBrainTurn {
            recordLocalOriginAfterSettledTurn()
        }
        finalizeOnDeviceIntelligence()
        return true
    }

    /// #190B: store membership IS local origin. A thread enters the keyed
    /// store the moment its FIRST assistant turn settles on a local brain —
    /// a thread born local — and from then on the origin-based discriminator
    /// (`isLocalSessionThread`: no host configured, or id store-known) keeps
    /// it eligible for the walk-away persist, the legacy-cache catch-up, and
    /// the drawer's live row, across process death. A thread whose earlier
    /// assistant turns exist (a paired-mode Hermes thread that #192 flipped
    /// mid-conversation) is NOT born local and never enters the store — its
    /// identity is a Hermes session; contamination is exactly what the old
    /// stamp-scanning rule allowed. Already-member threads get their stored
    /// copy refreshed so the settled turn survives a later process death.
    private func recordLocalOriginAfterSettledTurn() {
        guard let localSessions, isLocalSessionThread != nil,
              let conversation, !conversation.messages.isEmpty else { return }
        if isLocalSessionThread?(conversation) == true {
            localSessions.upsertSession(conversation)
            return
        }
        let assistantTurns = conversation.messages.filter { $0.sender == .hermes }.count
        if assistantTurns == 1 {
            localSessions.upsertSession(conversation)
            chatLog.notice("local origin established for '\(conversation.id.uuidString, privacy: .public)' — first assistant turn settled on-device (#190B)")
        }
    }

    /// #295 Task 2: shared recovery-arming mechanics between the `.interrupted`
    /// stream-terminal case above (the reference implementation) and the
    /// expiration path in `cancelStreaming(hardStopHost: false)`. Both mirror
    /// the SAME shape — a run that committed server-side but whose stream the
    /// client lost (a network drop, or the OS revoking a background budget)
    /// is not a failure: remove the placeholder preserving whatever reasoning
    /// streamed before the drop, mint a `PendingRun` from the run's
    /// identifiers, and arm the reconcile loop so `reconcileFromServer()`
    /// picks up the reply once it lands. Each call site still owns its OWN
    /// surrounding specifics (how it settles the user row, which local vs.
    /// stored identifiers it has in scope) — only this identical middle is
    /// factored out, so a future edit to one arm's recovery mechanics can't
    /// silently drift from the other's.
    private func armPendingRunRecovery(
        placeholderID: UUID,
        sessionId: String,
        runId: String?,
        userMessageID: UUID
    ) {
        var partialReasoning: String?
        if let idx = conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
            partialReasoning = conversation?.messages[idx].reasoning
            conversation?.messages.remove(at: idx)
        }
        pendingRun = PendingRun(
            sessionId: sessionId,
            runId: runId,
            userMessageID: userMessageID,
            sentAt: pendingMessageSentAt ?? .now,
            partialReasoning: partialReasoning
        )
        startReconcileLoopIfNeeded()
    }

    /// #184: THE teardown primitive for switching conversation context —
    /// every path that walks away from the current thread (clear, session
    /// switch, pairing-lifecycle reset) calls this instead of hand-rolling
    /// its own subset. It releases everything the departing run holds: the
    /// reconcile loop, the pending run, the streaming task, the poll loop,
    /// and the Live Activity. Firing `onRunResolved` on the way out is
    /// deliberate — the user chose to walk away, so the relay watch stands
    /// down rather than staying armed against a session this store has
    /// stopped tracking (#38; AppContainer expects paired watches).
    ///
    /// #190: the same walk-away moment is when the departing thread must be
    /// persisted — before whatever replaces it becomes current — so the
    /// persist lives HERE, first, not hand-rolled into each path. It can:
    /// the store's main-context save is synchronous.
    ///
    /// `stopSpeech` is the one per-path difference (kept for `reset()`'s
    /// callers to reason about explicitly, though every current path now
    /// passes true — see `openSession`).
    private func abandonPendingRun(stopSpeech: Bool) {
        persistDepartingLocalSession()
        reconcileTask?.cancel()
        reconcileTask = nil
        if let abandoned = pendingRun {
            onRunResolved?(abandoned.sessionId)
        }
        pendingRun = nil
        streamingTask?.cancel()
        streamingTask = nil
        streamingMessageID = nil
        streamingUserMessageID = nil
        // #295: this cancellation doesn't route through `cancelStreaming`,
        // so it has to clear the capture itself — "releases everything the
        // departing run holds" above is the promise this line keeps honest.
        activeStreamRun = nil
        // #192: release the router's routing lock with the run — a dropped
        // stream must not leave `runningBrain` set and wedge the brain
        // toggle until force quit.
        hermesClient.abandonActiveRun()
        pollingTask?.cancel()
        pollingTask = nil
        pendingMessageSentAt = nil
        // #304 bar 304-E: a walk-away (thread switch, clear, reset) exits
        // the driver too — the card must not survive into the next thread.
        hostApprovals?.clearForTurnEnd()
        // #306 matrix row 11: the walk-away park. The departing thread's
        // hold travels with that thread (surfaced — its awaited turn will
        // never report a terminal now) and can never fire into the arriving
        // one: the fire and the chip are both keyed to the CURRENT thread.
        parkHeldTurnsOnWalkAway()
        chatLiveActivity.endActivity()
        if stopSpeech {
            speechOutput?.stop()
        }
    }

    /// #190: the walk-away persist. A departing thread that is positively
    /// LOCAL (never a paired-mode Hermes thread — its history lives
    /// server-side) and non-empty is upserted into the keyed session store,
    /// so New/switch/reset stop destroying standalone history. Both seams
    /// nil (tests, store-creation failure) restore pre-#190 behavior.
    private func persistDepartingLocalSession() {
        guard let localSessions,
              let conversation, !conversation.messages.isEmpty,
              isLocalSessionThread?(conversation) == true else { return }
        localSessions.upsertSession(conversation)
    }

    func clearConversation() async throws {
        // #306 (O8): capture the DEPARTING thread's keys before anything
        // replaces the conversation — the clear kills that thread's queue,
        // and only that thread's.
        let departingThreadKeys = currentComposeThreadKeys
        abandonPendingRun(stopSpeech: true)
        let fresh = try await hermesClient.clearConversation()
        conversation = fresh
        // #277: the new thread has no server handle until its first turn
        // mints a hop. Clearing this is what stops the fresh thread's chips
        // being filed under the thread the user just left.
        lastOpenedSessionID = nil
        lastTokenUsage = fresh.latestUsage
        pendingMessageSentAt = nil
        sessionOpenFailure = nil
        persistence.saveConversationCache(fresh)
        onConversationChanged?()
        // P1 (#90): the journal resets to the fresh thread's identity (the
        // client already ended its hop). Queued offline turns belonged to the
        // cleared thread — they die with it (the #90 precedent, unchanged:
        // `.unreachable` parks and legacy nil-keyed entries).
        //
        // #306 row 11 (review round 1 fix): a HELD turn does NOT die here.
        // M-15 made New Chat non-destructive — the departing thread stays in
        // the drawer, reopenable — so the held entry PARKS with its thread
        // (already surfaced by `abandonPendingRun` above) and is restored on
        // return, exactly as the filed matrix says for "thread switch, new
        // chat". Only genuinely destructive teardown (`reset()`, the pairing
        // lifecycle) still nukes the whole store. Owen's O8 tail (he may
        // prefer kill-on-new-chat) is surfaced in NEEDS-OWEN; this follows
        // the filed matrix until he re-rules. OTHER threads' entries were
        // never this clear's business.
        journal?.sync(with: fresh)
        composeOutbox.pendingTurns.removeAll { turn in
            guard let key = turn.threadKey else { return true }
            guard departingThreadKeys.contains(key) else { return false }
            return turn.reason == .unreachable
        }
        persistComposeOutbox()
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// `hardStopHost` gates the REAL server-side interrupt
    /// (`hermesClient.hardStopActiveRun()`) — nothing else in this function
    /// changes between the two values. Defaults to `true`: every EXPLICIT
    /// stop (the in-app Stop button via `ChatScreen`, Siri's Cancel via
    /// `AskHermesIntent`/`AskHermesLongRunSupport`) wants the host actually
    /// told to stop, and none of those call sites need to change to get it.
    ///
    /// #283 Task 7 (S23) review re-review: the continued-send expiration
    /// handler (below, `beginContinuedSend`'s `onExpiration`) ALSO enters
    /// through this same function — the system revoking a background task's
    /// budget with NO user action, not a walk-away that bypasses
    /// `cancelStreaming` entirely. It passes `hardStopHost: false` to
    /// distinguish that SYSTEM-revoked budget from a user-initiated Stop, so
    /// the host run is left alone rather than hard-killed on a turn the user
    /// never asked to stop. That much is load-bearing.
    ///
    /// #295 close-out (Owen's ruling, 2026-08-08 — SHIPPED, not a plan): the
    /// expiration path does NOT "degrade to the ordinary recovery poll" —
    /// `restartPendingPollingIfNeeded`'s loop only ever re-merges
    /// `hermesClient.loadConversation()`'s CACHED conversation (no network
    /// call on the sessions plane), so it was never capable of retrieving an
    /// answer the host is still generating. The genuine recovery route
    /// (`pendingRun` + `startReconcileLoopIfNeeded()` → `reconcileFromServer()`,
    /// a real GET) now arms on THIS path too, mirroring the `.interrupted`
    /// arm's mechanics (`armPendingRunRecovery`, above) — but ONLY when
    /// `hermesClient.currentRunIsServerRecoverable` says the run is on a
    /// plane whose host keeps generating after this client's stream drops
    /// (the real Hermes plane, sessions or runs — `reconcileFromServer()` is
    /// routed by `ChatBackendRouter`, so the one arming site here recovers
    /// correctly whichever plane owns the turn). A LOCAL-brain turn (on-device
    /// / PCC, #30) reads `false` from that gate — nothing is ever committed
    /// server-side for it, so nothing would ever satisfy the reconcile filter,
    /// and worse, `reconcileFromServer()` resolves against `journal.activeHop`
    /// rather than the pending run's own session id, so an unrelated LATER
    /// Hermes turn on that hop could wrongly adopt a dead local turn's
    /// reasoning (see the gate's own doc,
    /// `HermesClientProtocol.currentRunIsServerRecoverable`, for the full
    /// cross-hop-corruption chain). A local-brain expiration therefore keeps
    /// the pre-#295 behavior: finalize the placeholder as a terminal
    /// `.delivered` bubble, same as an explicit Stop — no recovery is coming,
    /// so silence over that turn is the honest outcome, not a hole.
    /// User-initiated Stop (`hardStopHost: true`) is byte-unchanged by any of
    /// this: `.delivered`, silent, no `PendingRun`, no reconcile armed (bar
    /// 295-B) — the user does not want the answer.
    ///
    /// Every other effect below — cancelling the local task, releasing the
    /// router's routing lock, finalizing the UI, ending the Live Activity —
    /// still happens on every path; only the network call and the recovery
    /// arm are gated.
    func cancelStreaming(hardStopHost: Bool = true) {
        // #306: whether this call is actually terminating a live turn — a
        // defensive cancel with nothing streaming must not restore or
        // surface a held message.
        let terminatedALiveTurn = streamingMessageID != nil
        // #295 (Owen's ruling, review follow-up): read recoverability FIRST —
        // before cancelling the consuming task (which the router treats as a
        // walk-away and may itself release the routing lock from, per
        // `consumerWalkAwayAloneReleasesTheRoutingLock`) and before
        // `abandonActiveRun()` below explicitly releases it. Either one can
        // clear the very signal this reads (`ChatBackendRouter.runningBrain`),
        // so it has to be captured before both, not just before the second.
        let turnIsServerRecoverable = hermesClient.currentRunIsServerRecoverable
        streamingTask?.cancel()
        streamingTask = nil
        if hardStopHost {
            hermesClient.hardStopActiveRun()
        }
        // #192: the stopped run is over from the consumer's side — release
        // the router's routing lock so the brain toggle re-derives now.
        // Unconditional: correct on BOTH paths, gated or not.
        hermesClient.abandonActiveRun()
        // #304 bar 304-E: Stop (or a revoked background budget) ends the
        // turn — an outstanding approval card goes with it. The host's own
        // machinery settles the parked approval: an explicit Stop's `/stop`
        // resolves it as deny host-side (`tools/approval.py:3695-3703`), and
        // an unanswered park times out on the host's window.
        hostApprovals?.clearForTurnEnd()
        chatLiveActivity.endActivity()
        // User asked for silence along with the stop — cut read-aloud too.
        speechOutput?.stop()

        // #295 Task 2 + review follow-up: the expiration path
        // (`hardStopHost: false`) diverges here from an explicit Stop, but
        // ONLY when the turn is on a plane that can actually be recovered.
        // Finalizing the placeholder as a terminal `.delivered` bubble (the
        // `else` branch below) would be the silent hole bar 295-A exists to
        // close IF the host is still generating — but arming a `PendingRun`
        // for a turn that ISN'T server-recoverable (the on-device/PCC brain,
        // #30) is worse than that hole: nothing is ever committed for it to
        // reconcile against, so the loop re-arms itself indefinitely
        // (`performReconcilePendingRuns` on every foreground/appear), AND —
        // because `reconcileFromServer()` resolves against `journal.activeHop`
        // rather than `pending.sessionId` — a LATER, unrelated Hermes turn on
        // that same hop can satisfy this pending run's `sender == .hermes &&
        // timestamp > pending.sentAt` filter and get wrongly stamped with
        // THIS dead turn's reasoning/duration and re-paired with THIS turn's
        // prompt. `armPendingRunRecovery` (removes the placeholder preserving
        // partial reasoning, mints a `PendingRun`, starts the reconcile loop)
        // only runs when `turnIsServerRecoverable` says yes.
        var armedRecovery = false
        if !hardStopHost,
           turnIsServerRecoverable,
           let placeholderID = streamingMessageID,
           let userMessageID = streamingUserMessageID,
           let sessionId = activeStreamRun ?? activeSessionID {
            // #295 carried finding (Task 1 self-review): `activeStreamRun` is
            // written ONLY inside the stream's `for await` loop (below,
            // `sendMessage`), and `SessionsHermesClient` never yields
            // `.messageSent` — the first update it can yield at all is
            // whatever the turn actually produces. On an attachment turn
            // (the ONLY turns that reach this path — `continuedSend` is nil
            // for text-only sends) whose OWN upload outlasts the background
            // budget, expiration can fire before the loop has processed a
            // single `StreamingUpdate`, leaving `activeStreamRun` nil right
            // when a sessionId is needed. `activeSessionID` (the shared
            // journal's active hop) is the fallback, not a parallel capture
            // path: `SessionsHermesClient.ensureHopForTurn()` records that
            // hop before the turn's POST even goes out — well before the
            // upload that can outlast the budget — so it is already correct
            // in this exact window (confirmed in Task 1's report, and pinned
            // here by `expirationArmsRecoveryEvenWithZeroStreamingUpdatesProcessed`).
            // `runId` has no channel here at all (see `activeStreamRun`'s own
            // doc) — `nil` is honest, not a placeholder for something missing.
            armPendingRunRecovery(
                placeholderID: placeholderID,
                sessionId: sessionId,
                runId: nil,
                userMessageID: userMessageID
            )
            armedRecovery = true
        } else if let sid = streamingMessageID,
           var conv = conversation,
           let idx = conv.messages.firstIndex(where: { $0.id == sid }) {
            // An explicit Stop (`hardStopHost: true`); a turn on a
            // non-recoverable plane (`turnIsServerRecoverable == false` —
            // the gate this review follow-up added); or the residual
            // defensive tail for an expiration that has no session
            // identifier at all to recover with. All three share ONE
            // honest answer: nothing is going to arrive later that this
            // client is still watching for, so finalize now instead of
            // promising a recovery that either isn't coming or would
            // resolve onto the wrong turn.
            if Self.stoppedPlaceholderHasNothingToShow(conv.messages[idx]) {
                // #294: a Stop taken before the first token leaves a
                // placeholder with no content, no tool activity, no chip and
                // no reasoning — and the two lines below would make that
                // TERMINAL (`.delivered`, not streaming), which is precisely
                // the shape the cold-load scrubber cannot rescue (it only
                // catches `.sending`). So it persisted, survived relaunch and
                // rendered as a bare box. Remove it instead: same outcome the
                // scrubber would have produced, one turn earlier.
                conv.messages.remove(at: idx)
            } else {
                conv.messages[idx].isStreaming = false
                conv.messages[idx].status = .delivered
                // #296: this loop used to be the single
                // `isActive = false` sweep below, and that sweep is where
                // `✓ TERMINAL` came from. The rail reads
                // not-streaming-and-not-active as DONE, so collapsing "was
                // running when the turn was cut short" into the same flag
                // that means "finished normally" made the app assert a
                // command completed that the user had just killed — and on a
                // turn stopped before any prose, that chip is the entire
                // message.
                //
                // **Two passes, and the order is load-bearing.** The marker
                // is written to the activities that are STILL ACTIVE, read
                // BEFORE anything clears the flag; only then does the second
                // pass clear. Fusing them into one loop that clears and then
                // tests would mark nothing at all, silently — the same
                // read-before-clear shape #295 pinned on this very function
                // with a dedicated test, and it is pinned here the same way —
                // `stopDuringAToolCallKeepsTheActivityRow` fails on a nil
                // `failure`, which is exactly what a fused loop produces.
                // Activities already inactive were resolved normally earlier
                // in this turn (prose arrived, a successor started, or a
                // named `tool.completed` landed) — they are genuinely
                // finished and are left untouched. That is bar 296-B.
                //
                // WHICH marker: `hardStopHost` distinguishes the two ways
                // this branch is reached. `true` is the user's own Stop.
                // `false` is the continued-send expiration that did NOT arm
                // recovery — the #295 review follow-up's gate, a turn on a
                // plane that cannot be resumed, where nothing is coming back
                // for it either. Both are honest reasons a call did not
                // finish; they are not the same reason, and "Stopped" on a
                // turn the user never stopped would be a small lie of its
                // own. (The RECOVERABLE expiration never reaches here at all
                // — it takes the `armPendingRunRecovery` branch above, which
                // removes the placeholder. Marking a turn that is about to
                // resolve successfully would be the worst of the three.)
                let marker = hardStopHost
                    ? ToolActivity.stoppedByUser
                    : ToolActivity.interruptedBySystem
                for i in conv.messages[idx].toolActivities.indices
                where conv.messages[idx].toolActivities[i].isActive {
                    conv.messages[idx].toolActivities[i].failure = marker
                }
                for i in conv.messages[idx].toolActivities.indices {
                    conv.messages[idx].toolActivities[i].isActive = false
                }
            }
            conversation = conv
        }
        // #291/#295: settle THIS turn's user row. `cancelStreaming` used to
        // finalize only the assistant placeholder, so the user's optimistic
        // row stayed `.sending` — which is exactly `hasPendingMessages`, one
        // of the three conditions the poll loop's exhaustion branch tests.
        // ~60s after a deliberate Stop it flipped the row to `.failed` and
        // fired `onSendFailed` (an error haptic) on a turn the host had
        // received and partly answered. The host DID receive the message on
        // BOTH paths through here, so `.sending`/`.failed` are never honest —
        // but "settled" means different things depending on whether real
        // recovery is actually armed. A user-initiated Stop (`hardStopHost:
        // true`) is over, full stop: `.delivered`. The continued-send
        // expiration (`hardStopHost: false`) settles `.working` ONLY when
        // `armedRecovery` is true — the reconcile loop is genuinely watching
        // for the reply, so `.delivered` there would be the lie in the other
        // direction, claiming an answer that hasn't arrived. But when
        // `armedRecovery` is false (the gate said not recoverable, or no
        // session id resolved at all), NOTHING is watching — `.working`
        // there would be a lie of its own, a row stuck forever with no
        // reconcile loop and no poll-exhaustion scrub (`hasPendingMessages`
        // only counts `.sending`, never `.working`) to ever correct it. That
        // case settles `.delivered`, same as an explicit Stop, because as far
        // as this client can ever know, no recovery is coming.
        settleStoppedUserMessage(as: (hardStopHost || !armedRecovery) ? .delivered : .working)
        // #306 matrix rows 2/9/10 — report the OBSERVED terminal, never the
        // row status (all three of these can leave the row `.delivered`).
        // Row 2 (Stop): never auto-fire; the text restores (O2). Row 9
        // (expiration, recovery armed): HOLD — the reconcile owns it. Row 10
        // (expiration, nothing coming): HOLD + SURFACE.
        if terminatedALiveTurn {
            if hardStopHost {
                resolveHeldTurn(after: .stopped)
            } else {
                resolveHeldTurn(after: armedRecovery ? .expiredRecoverable : .expiredUnrecoverable)
            }
        }
        streamingMessageID = nil
        // #295: whatever this stream's captured identifiers were, this
        // function is itself a terminal path for it.
        activeStreamRun = nil
        streamingUserMessageID = nil
        pendingMessageSentAt = nil
        lastStreamActivityAt = nil

        if let conversation {
            persistence.saveConversationCache(conversation)
            // #277: stopping a run does not un-write the file the agent
            // already produced — a chip on the stopped reply is as durable as
            // the transcript this line just saved.
            recordAgentAttachments()
            onConversationChanged?()
        }
    }

    /// #291/#295: flips the stopped turn's OWN user row from `.sending` to
    /// the caller's chosen terminal — `.delivered` for a user-initiated Stop,
    /// `.working` for the continued-send expiration path (see the call site
    /// in `cancelStreaming`). Deliberately targeted rather than a blanket
    /// sweep of every `.sending` user row: a queued/draining outbox turn or a
    /// second send in flight is not this Stop's business, and settling
    /// somebody else's row would be the same class of lie in the other
    /// direction. `.sending` is required — a row already settled by its own
    /// terminal (`.working` after an interrupt, `.queued` offline) is left
    /// alone.
    private func settleStoppedUserMessage(as status: MessageStatus) {
        guard let userMessageID = streamingUserMessageID,
              var conv = conversation,
              let idx = conv.messages.firstIndex(where: {
                  $0.sender == .user
                      && ($0.id == userMessageID || $0.clientMessageID == userMessageID)
              }),
              conv.messages[idx].status == .sending
        else { return }
        conv.messages[idx].status = status
        conversation = conv
    }

    /// #294: whether a stopped streaming placeholder carries nothing worth
    /// keeping. The prose half REUSES `cleanCloseArmsRecovery` — #235 F1's
    /// emptiness decision, which `deliverPolledTerminal` also reuses rather
    /// than restating — so the third producer of terminal assistant rows
    /// cannot drift from the other two. The rest of the test is additive and
    /// strictly more conservative than the cold-load scrubber's
    /// (content + tool activities): a Stop must not eat an agent-file chip
    /// (#277 keeps those durable through exactly this call) or reasoning the
    /// `_thinking` channel streamed before the answer began (#4.15 renders
    /// it on a non-streaming bubble, and the server transcript will never
    /// give it back).
    ///
    /// #291 close-out: deliberately NOT checked here — `codeDiff`, `usage`,
    /// and `reasoningSummary`. Not an oversight; each is provably
    /// unreachable on a placeholder this function is ever called on (one
    /// still mid-stream, caught by `cancelStreaming` before `.finished`):
    /// - `codeDiff` and `usage` are populated in exactly one place, the
    ///   `.finished` stream-event case (`resolved.codeDiff = diff`,
    ///   `if resolved.usage == nil { resolved.usage = usage }`) — that case
    ///   IS the terminal, so a message this function sees has never reached it.
    /// - `reasoningSummary` is populated only by `condensePendingReasoning()`,
    ///   which requires `!$0.isStreaming` on its candidate — a still-streaming
    ///   placeholder is categorically excluded from that pass.
    ///
    /// This is the #276 field-by-field hazard shape: if a future field is
    /// added to `Message` and populated anywhere OTHER than the `.finished`
    /// case or a `!isStreaming` gate, this predicate will silently treat a
    /// placeholder carrying that field as empty and delete it. Re-verify the
    /// three bullets above (or add the new field to them) before trusting
    /// this function unchanged.
    nonisolated static func stoppedPlaceholderHasNothingToShow(_ message: Message) -> Bool {
        SessionsHermesClient.cleanCloseArmsRecovery(runStarted: true, effectiveContent: message.content)
            && message.toolActivities.isEmpty
            && message.attachments.isEmpty
            && (message.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    // MARK: - Fetchable agent files (#21 Tier 2)

    /// Tap→download→stage for a fetchable agent-file bubble: pulls the bytes
    /// from the announcing session's birth-profile relay, stages them into
    /// the Attachments dir, and flips the attachment to its staged form —
    /// from then on the bubble behaves exactly like a Tier 1 bubble
    /// (preview sheet + ShareLink). Failures land in `agentFileDownloads`
    /// with an honest message; tapping again retries.
    func fetchAgentFile(_ attachment: MessageAttachment, in message: Message) async {
        guard attachment.localStoragePath == nil,
              let remotePath = attachment.remotePath,
              agentFileDownloads[attachment.id] != .downloading
        else { return }
        guard let downloader = agentFileDownloader else {
            agentFileDownloads[attachment.id] = .failed("Downloads aren't available in this session.")
            return
        }
        agentFileDownloads[attachment.id] = .downloading
        do {
            let temporaryURL = try await downloader(attachment.remoteProfileID, remotePath)
            guard let stagedPath = MessageAttachment.stageFetchedAgentFile(
                from: temporaryURL,
                preferredFileName: attachment.fileName
            ) else {
                agentFileDownloads[attachment.id] = .failed("Couldn't save the downloaded file.")
                return
            }
            if var conv = conversation,
               let messageIdx = conv.messages.firstIndex(where: { $0.id == message.id }),
               let attachmentIdx = conv.messages[messageIdx].attachments.firstIndex(where: { $0.id == attachment.id }) {
                conv.messages[messageIdx].attachments[attachmentIdx] =
                    conv.messages[messageIdx].attachments[attachmentIdx].staged(atLocalPath: stagedPath)
                conversation = conv
                persistence.saveConversationCache(conv)
                onConversationChanged?()
            } else {
                // The transcript moved on mid-download (cleared, switched
                // session) — nothing to attach the bytes to.
                try? FileManager.default.removeItem(atPath: stagedPath)
            }
            agentFileDownloads[attachment.id] = nil
        } catch {
            agentFileDownloads[attachment.id] = .failed(Self.agentFileFailureMessage(for: error))
            chatLog.notice("agent file fetch failed (#21): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Honest, user-facing failure text for a fetch: auth, not-found, and
    /// offline each get a specific line (the acceptance triad); everything
    /// else surfaces its own description.
    nonisolated static func agentFileFailureMessage(for error: Error) -> String {
        if let downloadError = error as? RelayAPIClient.FileDownloadError {
            switch downloadError {
            case .unauthorized:
                return "The relay refused this device's authorization. Re-pair with the host and try again."
            case .notFound:
                return "The file isn't available from the relay — it may have been moved or removed on the host."
            case .failed(let message):
                return message
            }
        }
        if SessionsHermesClient.isUnreachableError(error) {
            return "The relay is unreachable. Check the connection and tap to retry."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "The download failed. Tap to retry." : described
    }

    // MARK: - Voice transcript hand-off (#1)

    /// Appends a completed voice session to the conversation, composed entirely
    /// on-device from the TalkStore snapshot: the "[Voice session ended]" banner
    /// plus the finalized transcript turns. The old relay inject endpoint is out
    /// of the path — the transcript renders and persists (UserDefaults cache)
    /// even when the relay/host is unreachable.
    ///
    /// When `postToHermes` is true, the transcript is also POSTed to the Sessions
    /// API as a normal text turn so the agent has the voice context for the next
    /// exchange. Best-effort and fire-and-forget: the reply is discarded and a
    /// failure never touches the locally composed messages.
    func appendVoiceTranscript(_ session: CompletedVoiceSession, postToHermes: Bool) {
        let transcriptMessages = Self.voiceTranscriptMessages(from: session)
        guard !transcriptMessages.isEmpty else { return }

        if conversation == nil {
            conversation = Conversation(title: Conversation.defaultTitle)
        }
        conversation?.messages.append(contentsOf: transcriptMessages)
        conversation?.lastActivity = transcriptMessages.last?.timestamp ?? .now
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
            // P1 (#90): voice turns are conversation content — journaled so a
            // transplant carries them. They didn't ride the Hermes hop, so
            // the waterline stays behind and the next Hermes turn re-hops
            // with the voice context transplanted. The explicit context POST
            // below is then mostly redundant on the Sessions path, but it
            // stays: non-hop backends (mock/legacy relay) have no transplant,
            // and double context is harmless where hops exist.
            journal?.sync(with: conversation)
        }

        // #280: THE fix. This was the outermost of three blockers — the card
        // generator was never invoked on the voice path at all, so a thread
        // whose only user turns were spoken kept `Conversation.defaultTitle`
        // forever and the drawer rendered its own preview on both lines.
        //
        // Placement is load-bearing, not incidental:
        //   * AFTER the append + persist above, so the transcript the
        //     generator reads is the settled one;
        //   * BEFORE the `postToHermes` guard, so it runs on BOTH branches —
        //     a local-only voice session gets a title too;
        //   * OUTSIDE the Task below. `conversationCard` can reach
        //     `model.tokenCount(...)`, and a `tokenCount()` concurrent with a
        //     live FoundationModels streaming turn kills that turn on device
        //     (ModelManagerError 1001 -> "error -1"). Both pre-existing call
        //     sites run after a turn settles, which is why this has never
        //     bitten; this one stays on the same side of that line.
        finalizeOnDeviceIntelligence()

        guard postToHermes else { return }
        let contextTurn = Self.voiceTranscriptTurnText(from: session)
        guard !contextTurn.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            // P1 (#90): the journal sync above just left the hop waterline
            // behind, so this sync send will usually hop — a transplant paid
            // for on a path that yields no stream. Capture the hop identity
            // before/after so the priming still surfaces in the transcript
            // and totals (priming is not free, even here).
            let hopBefore = self.journal?.activeHop?.apiSessionId
            let reply = await self.hermesClient.send(
                message: contextTurn,
                attachments: [],
                clientMessageID: UUID()
            )
            if reply.status == .failed {
                chatLog.notice("voice transcript context turn failed — transcript stays local-only this session")
                return
            }
            if let journal = self.journal,
               let hop = journal.activeHop,
               hop.apiSessionId != hopBefore,
               journal.hasEntries {
                self.appendPrimingNotice(usage: hop.primingUsage)
            }
        }
    }

    /// The context-transplant notice row (#90): honest label + the priming
    /// turn's real usage, marked so the session totals separate priming from
    /// metered chat turns.
    private func makePrimingNotice(usage: TokenUsage?) -> Message {
        let label = usage.map {
            "[Context transplanted into a fresh session — \(TurnReceiptFormat.fullTokenLabel($0.totalTokens)) tokens]"
        } ?? "[Context transplanted into a fresh session]"
        return Message(
            sender: .system,
            content: label,
            status: .delivered,
            usage: usage,
            servingModel: activeModelName,
            isContextPriming: true
        )
    }

    /// Appends the context-transplant notice for a priming that happened on a
    /// non-streaming path (the voice context POST) — the streamed path gets
    /// its notice from `.contextPrimed` instead (#90).
    private func appendPrimingNotice(usage: TokenUsage?) {
        conversation?.messages.append(makePrimingNotice(usage: usage))
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }
    }

    /// Builds the chat messages for a completed voice session: a system banner
    /// (carrying the duration for `VoiceSessionBanner`) followed by one message
    /// per finalized spoken turn (`.voiceUser` / `.voiceHermes`). Partial turns,
    /// empty turns (e.g. image-only frames), and system notices are dropped.
    /// Returns [] when nothing was actually spoken.
    nonisolated static func voiceTranscriptMessages(from session: CompletedVoiceSession) -> [Message] {
        var messages: [Message] = []
        for item in session.transcript where !item.isPartial {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let sender: MessageSender
            switch item.speaker {
            case .user: sender = .voiceUser
            case .hermes: sender = .voiceHermes
            case .system: continue
            }
            messages.append(Message(sender: sender, content: text, status: .delivered))
        }
        guard !messages.isEmpty else { return [] }
        let banner = Message(
            sender: .system,
            content: "[Voice session ended]",
            status: .delivered,
            voiceSessionDuration: session.duration
        )
        return [banner] + messages
    }

    /// The plain-text turn POSTed to the Sessions API so the agent sees the
    /// voice exchange as context. Empty when the session had no spoken turns.
    nonisolated static func voiceTranscriptTurnText(from session: CompletedVoiceSession) -> String {
        let lines: [String] = session.transcript.compactMap { item in
            guard !item.isPartial, item.speaker != .system else { return nil }
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "\(item.speaker == .user ? "User" : "Hermes"): \(text)"
        }
        guard !lines.isEmpty else { return "" }
        return """
        [Voice session transcript — shared for context. No reply needed.]
        \(lines.joined(separator: "\n"))
        """
    }

    /// Why `/save` can refuse before it even tries to write.
    enum ExportError: LocalizedError {
        case nothingToSave
        case documentsUnavailable

        var errorDescription: String? {
            switch self {
            case .nothingToSave:
                "There's no conversation to save yet."
            case .documentsUnavailable:
                "The Documents folder isn't available on this device."
            }
        }
    }

    /// Writes the current conversation to Documents as JSON and returns the
    /// file URL, throwing on any failure so `/save` reports honestly instead
    /// of claiming success unconditionally.
    @discardableResult
    func exportConversationToFile() throws -> URL {
        guard let conversation else { throw ExportError.nothingToSave }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "hermes_conversation_\(timestamp).json"

        let exportData: [String: Any] = [
            "title": conversation.title,
            "sessionId": conversation.id.uuidString,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "messageCount": conversation.messages.count,
            "messages": conversation.messages.map { msg in
                [
                    "role": msg.sender.rawValue,
                    "content": msg.content,
                    "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                ] as [String: String]
            },
        ]

        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ExportError.documentsUnavailable
        }
        let fileURL = dir.appendingPathComponent(filename)

        let data = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func setConversationTitle(_ title: String) {
        conversation?.title = title
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }
    }

    func retryMessage(_ message: Message) async {
        // A retried turn must not ALSO drain from the compose outbox later —
        // drop any queued copy before re-sending (#90). #306 trap 8: matched
        // by TRANSCRIPT ROW, so a mid-turn hold (row-less by construction)
        // can never be silently deleted by someone else's retry.
        composeOutbox.removeEntry(withTranscriptRowID: message.clientMessageID ?? message.id)
        persistComposeOutbox()

        // #279: remove the failed row through the SAME adoption tail the
        // truncation primitive uses. A bare `messages.removeAll` here left
        // the backend's mirror still holding the row, and the mirror is the
        // BASE of the post-turn merge (`:886-889`) — so the retried turn's
        // own finish put the removed row straight back, above the retried
        // copy. Two identical user bubbles, which is what the user sees.
        // Index-based, and the index is kept: the restore below needs it.
        let removedIndex = conversation?.messages.firstIndex(where: { $0.id == message.id })
        let removedRow = removedIndex.flatMap { conversation?.messages[$0] }
        if let removedIndex {
            conversation?.messages.remove(at: removedIndex)
            // #279: NOT `truncateTranscript(from:)` — that removes
            // `index...` to the END of the transcript, and a `.failed` row
            // can sit anywhere (the bubble's retry affordance has no
            // "is it the last row" condition, and #56's
            // `finalizeStaleSendsFromCache` manufactures mid-transcript
            // failed rows on every cold load after a mid-stream death).
            // Routing the FILING literally would delete every turn below the
            // retried one; what is owed is the adoption, not the truncation.
            adoptLocalTranscript()
        }

        // Determine the user content to retry (attachments can't be recovered
        // from metadata). #275: user-AUTHORED, so a dictated turn is a valid
        // retry source — matching `.user` alone re-sent the last TYPED turn
        // and silently answered a different question.
        let sourceMessage: Message?
        if message.sender.isUserAuthored {
            sourceMessage = message
        } else {
            sourceMessage = conversation?.messages.last(where: { $0.sender.isUserAuthored })
        }

        // #279: every early return below leaves the row REMOVED unless it is
        // put back — same residual `regenerateReply` was given
        // `restoreTruncatedRows` for (`:1858-1864`), which this path never got.
        guard let sourceMessage else {
            restoreRetriedRow(removedRow, at: removedIndex, why: "no re-sendable source turn")
            return
        }
        let attachments = sourceMessage.attachments.compactMap(PendingAttachment.restore)
        let content = Self.normalizedRetryContent(for: sourceMessage)
        guard !content.isEmpty || !attachments.isEmpty else {
            restoreRetriedRow(removedRow, at: removedIndex, why: "the turn has nothing re-sendable")
            return
        }

        // #279: `sendMessage`'s `Bool` was DISCARDED here. It returns false
        // from the empty guard (`:575`) and from `hasPendingDuplicateMessage`
        // (`:576`) — a byte-identical turn still `.sending` or `.queued`
        // elsewhere in the thread — and when it did, the failed row had been
        // deleted and nothing was sent.
        let dispatched = await sendMessage(content, attachments: attachments)
        guard !dispatched else { return }
        restoreRetriedRow(removedRow, at: removedIndex, why: "the re-send was swallowed by a send guard")
    }

    /// #279: puts a retried row back when the re-send never dispatched.
    /// Thin wrapper over `restoreTruncatedRows` (id-deduped, re-adopts) so
    /// every early return in `retryMessage` restores identically and logs the
    /// same way `regenerateReply` does (`:1863`).
    private func restoreRetriedRow(_ row: Message?, at index: Int?, why: String) {
        guard let row, let index else { return }
        chatLog.notice("retry: \(why, privacy: .public) — restoring the removed row at index \(index) (#279/#78)")
        restoreTruncatedRows([row], at: index)
    }

    // MARK: - Transcript truncation (#78)

    /// **The one way to remove a RANGE of rows from the rendered transcript**
    /// — everything from `index` to the end.
    ///
    /// **This doc said "the one way to remove rows" and that was FALSE when
    /// it was written (corrected #279, 2026-08-09).** `retryMessage` removed
    /// a row with a bare `messages.removeAll` and never came through here, so
    /// the mirror kept it and the retried turn's own merge put it back — the
    /// exact failure the paragraph below describes, live in the one path #78
    /// did not touch. The invariant that actually holds is one level down:
    /// **every removal of a row the mirror may hold exits through
    /// `adoptLocalTranscript()`.** (Scoped that narrowly on purpose — #279's
    /// re-verify, 2026-08-10: several sites still prune rows with bare
    /// mutations, but every one removes rows the mirror never held — empty
    /// `.hermes` placeholders, never-posted `.queued` rows — which cannot
    /// resurrect. A removal that CAN meet the mirror goes through here.) This
    /// primitive owns the range case; `retryMessage` removes its single row
    /// and calls that tail directly, because truncating-to-the-end on a
    /// mid-transcript `.failed` row would delete every turn below it.
    ///
    /// Truncating the local array is only half the operation, and always was
    /// (#78): every backend keeps its OWN mirror of the thread, and this
    /// store treats that mirror as an authoritative refresh source — merging
    /// it back over the transcript at the end of every turn, on every ~2s
    /// poll tick, and on the streaming fallback path, with the mirror as the
    /// BASE ordering. A truncation that never reaches the mirror is undone
    /// within one tick: the removed rows come back IN PLACE and the
    /// regenerated reply is left stranded at the tail. So the primitive
    /// persists, syncs the journal, notifies, and hands the truncated thread
    /// to the client.
    ///
    /// Returns the removed rows so a caller whose follow-up send never
    /// dispatches can put them back (`restoreTruncatedRows`).
    @discardableResult
    func truncateTranscript(from index: Int, reason: String) -> [Message] {
        guard var conv = conversation, conv.messages.indices.contains(index) else { return [] }
        let removed = Array(conv.messages[index...])
        conv.messages.removeSubrange(index...)
        conversation = conv
        chatLog.notice("truncate [\(reason, privacy: .public)]: removed \(removed.count) row(s) from index \(index); \(conv.messages.count) remain (#78)")
        adoptLocalTranscript()
        return removed
    }

    /// Puts rows a truncation removed back where they were — the safety net
    /// for a caller that truncated in order to re-send and then didn't send
    /// (#78's residual: `sendMessage`'s duplicate guard swallowing a
    /// byte-identical re-roll left history destroyed in memory with nothing
    /// sent and nothing persisted). Id-deduped, so a partially-recovered
    /// transcript can't double a row.
    private func restoreTruncatedRows(_ rows: [Message], at index: Int) {
        guard !rows.isEmpty, var conv = conversation else { return }
        let present = Set(conv.messages.map(\.id))
        let missing = rows.filter { !present.contains($0.id) }
        guard !missing.isEmpty else { return }
        conv.messages.insert(contentsOf: missing, at: min(index, conv.messages.count))
        conversation = conv
        adoptLocalTranscript()
    }

    /// Publishes the current transcript as the whole of the thread: persist,
    /// notify, re-sync the journal, and hand it to the client so its mirror
    /// stops disagreeing with what the user is looking at (#78).
    private func adoptLocalTranscript() {
        guard let conversation else { return }
        persistence.saveConversationCache(conversation)
        onConversationChanged?()
        // P1 (#90): the journal follows the truncation (waterline clamps).
        journal?.sync(with: conversation)
        hermesClient.adoptTruncatedConversation(conversation)
    }

    // MARK: - Per-turn regenerate / edit (#44)

    /// Re-rolls a successful Hermes reply from its context menu: truncates the
    /// transcript from the user turn that produced the reply, then re-sends
    /// that turn through the full pipeline (attachments restored).
    /// No-op while a run is streaming (the menu also hides the item).
    ///
    /// The truncation runs through `truncateTranscript`, so it reaches the
    /// backend's mirror and survives the merges (#78). On the Hermes path the
    /// GATEWAY session still holds every turn — the documented `/retry`
    /// caveat — so the agent's context is unchanged and reopening the session
    /// from the drawer re-imports the server's history. On the local brain
    /// the truncation is total: the mirror and the `LanguageModelSession` both
    /// drop the removed turns.
    func regenerateReply(_ message: Message) async {
        // #278: `isTranscriptBusy`, not `isStreaming` — a dropped stream
        // leaves a live run behind with `streamingMessageID` already nil.
        guard !isTranscriptBusy else {
            chatLog.notice("regenerate: refused — a run is still in flight (#278)")
            return
        }
        guard let conv = conversation,
              let replyIdx = conv.messages.firstIndex(where: { $0.id == message.id }),
              // #275: user-AUTHORED, so a DICTATED producing turn is found.
              // Matching `.user` alone skipped it, took an earlier typed turn,
              // and truncated history the user never asked to lose.
              let userIdx = conv.messages[..<replyIdx].lastIndex(where: { $0.sender.isUserAuthored })
        else {
            chatLog.notice("regenerate: no producing user turn above this reply — nothing truncated, nothing sent (#78/#275)")
            return
        }

        let userMessage = conv.messages[userIdx]
        let attachments = userMessage.attachments.compactMap(PendingAttachment.restore)
        let content = Self.normalizedRetryContent(for: userMessage)
        guard !content.isEmpty || !attachments.isEmpty else {
            chatLog.notice("regenerate: the producing turn has nothing re-sendable — nothing truncated (#78)")
            return
        }

        let removed = truncateTranscript(from: userIdx, reason: "regenerate")
        let dispatched = await sendMessage(content, attachments: attachments)
        guard !dispatched else { return }
        // A send guard swallowed the re-roll — in practice the duplicate
        // check, when an identical turn is still pending elsewhere in the
        // thread. Nothing was sent, so the truncation destroyed history for
        // nothing; put it back rather than leave the user short a turn.
        chatLog.notice("regenerate: the re-send was swallowed by a send guard — restoring \(removed.count) truncated row(s) (#78)")
        restoreTruncatedRows(removed, at: userIdx)
    }

    /// The pieces a truncated user turn hands back to the composer.
    struct EditableTurn {
        let text: String
        let attachments: [PendingAttachment]
    }

    /// The truncation half of edit-and-resend (#44) — same semantics as
    /// `/undo`, but returning the removed turn's restorable content so the
    /// caller can seed the composer. Nothing is sent here; the user edits and
    /// taps send. Returns nil (and leaves the transcript untouched) while a
    /// run is streaming or for non-user messages.
    ///
    /// `.voiceUser` is deliberately NOT accepted: a voice-transcript row is
    /// not an editable composed turn, and the bubble menu offers Edit &
    /// Resend only on `.user` rows to match (#44's recorded decision,
    /// re-confirmed under #275). That is a product decision, not the #275
    /// producing-turn bug.
    ///
    /// #78: routed through `truncateTranscript`, which is what makes the
    /// truncation survive the send that follows. Before that it looked
    /// correct — nothing sends at this moment, so no merge runs — and was
    /// wiped the instant the user tapped send.
    func extractTurnForEditing(_ message: Message) -> EditableTurn? {
        // #278: the same belt the bubble menu wears. `!isStreaming` alone let
        // this truncate under a live run whose stream had merely dropped, and
        // the resend then posted a second run to the same server session.
        guard !isTranscriptBusy, message.status.isSettled else {
            chatLog.notice("edit-and-resend: refused — a run is still in flight (#278)")
            return nil
        }
        guard message.sender == .user,
              let conv = conversation,
              let idx = conv.messages.firstIndex(where: { $0.id == message.id })
        else { return nil }

        let attachments = message.attachments.compactMap(PendingAttachment.restore)
        let text = Self.normalizedRetryContent(for: message)
        truncateTranscript(from: idx, reason: "edit-and-resend")
        return EditableTurn(text: text, attachments: attachments)
    }

    func setPollingEnabled(_ isEnabled: Bool) {
        isPollingEnabled = isEnabled
        if isEnabled {
            restartPendingPollingIfNeeded()
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    // MARK: - Direct Sessions API health

    /// Probes the direct Sessions API (`/v1/models`, via the client's `connect()`)
    /// and records the outcome in `directConnectionStatus`. The probe creates no
    /// chat session and has no side effect beyond the status. While a response is
    /// actively streaming the connection is, by definition, live, so we skip the
    /// probe and report `.connected`.
    func refreshDirectHealth() async {
        // #307 (review round 1): this guard stays `!isStreaming`, NOT
        // `!isTranscriptBusy`. Tightening it here would skip the probe and
        // assert `.connected` UNPROBED for the whole reconcile window (up to
        // 120s, entered by a stream DROP — weak-to-negative evidence of
        // connectivity), painting the offline banner, the pip, and three
        // Settings surfaces ONLINE on a dead network — #180's
        // hidden-degradation shape. The #307 corruption fix lives in
        // `drainComposeOutboxIfPossible`'s own `!isTranscriptBusy` guard,
        // which this trigger cannot bypass; the probe here keeps reporting
        // honestly through the window.
        guard !isStreaming else {
            directConnectionStatus = .connected
            return
        }
        await hermesClient.connect()
        directConnectionStatus = hermesClient.connectionStatus
        // P1 (#90): reachability is the compose outbox's drain trigger — the
        // chat screen runs this probe on appear and every ~10s.
        if directConnectionStatus == .connected {
            await drainComposeOutboxIfPossible()
        }
    }

    // MARK: - Offline compose outbox (P1 / #90)

    /// Whether any composed turns are parked waiting for reachability.
    /// #306 T1: drain-eligible (`.released`) entries only — a mid-turn hold
    /// is waiting on its TURN, not on reachability, and has its own surface
    /// (`currentThreadHeldTurn`).
    var hasQueuedComposeTurns: Bool { !composeOutbox.releasedTurns.isEmpty }

    /// #306 T2: the thread key a new outbox entry is stamped with — the
    /// server session id where one exists (stable across leave-and-return
    /// via the drawer), else the conversation's local UUID (stable for
    /// local-brain threads, whose identity never leaves the device).
    private var currentComposeThreadKey: String? {
        activeSessionID ?? lastOpenedSessionID ?? conversation?.id.uuidString
    }

    /// Every key the CURRENT thread answers to. Matching is deliberately
    /// wider than stamping: a hold stamped with the conversation UUID in the
    /// pre-hop window still matches after the hop lands, and one stamped
    /// with the hop id matches after a drawer round-trip re-opens the
    /// session (`lastOpenedSessionID`).
    private var currentComposeThreadKeys: Set<String> {
        var keys = Set<String>()
        if let sessionID = activeSessionID { keys.insert(sessionID) }
        if let openedID = lastOpenedSessionID { keys.insert(openedID) }
        if let conversationID = conversation?.id { keys.insert(conversationID.uuidString) }
        return keys
    }

    /// Nil-keyed entries are legacy (pre-#306) and have always meant "the
    /// current thread" — they keep exactly that behavior.
    private func composeTurnBelongsToCurrentThread(_ turn: ComposeOutboxState.PendingTurn) -> Bool {
        guard let key = turn.threadKey else { return true }
        return currentComposeThreadKeys.contains(key)
    }

    /// Drain-eligible AND this thread's: the drain sends into the CURRENT
    /// conversation, so an entry keyed to another thread must wait for its
    /// own thread to be frontmost (#306 T2 / matrix row 11).
    private func isDrainableComposeTurn(_ turn: ComposeOutboxState.PendingTurn) -> Bool {
        turn.phase == .released && composeTurnBelongsToCurrentThread(turn)
    }

    /// #240: a queued turn whose text the server ALREADY holds as a user
    /// message (at/after `composedAt` − 60s clock-skew slack) was delivered —
    /// the park was a misclassification of the accepted-but-pre-`run.started`
    /// window, and re-sending it makes Hermes answer the question twice.
    nonisolated static func historyAdoptsQueuedTurn(
        _ turn: ComposeOutboxState.PendingTurn,
        serverMessages: [Message]
    ) -> Bool {
        let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return serverMessages.contains { message in
            message.sender == .user
                && message.timestamp >= turn.composedAt.addingTimeInterval(-60)
                && message.content.trimmingCharacters(in: .whitespacesAndNewlines) == text
        }
    }

    /// Drains queued turns oldest-first through the normal send pipeline
    /// (each drained turn hops/transplants exactly like a live send). The
    /// queued transcript row is replaced by the re-send's fresh optimistic
    /// row. Stops as soon as a send re-queues — still unreachable; the next
    /// reachability signal retries.
    func drainComposeOutboxIfPossible() async {
        // #307: `!isStreaming` here let the outbox drain INTO A LIVE RUN
        // during the reconcile window (`streamingMessageID` nil, `pendingRun`
        // live — exactly the #278 state), and `attemptReconcile` then adopted
        // the drained turn's reply as the dropped run's answer, re-attached
        // the dropped run's reasoning to it, and stamped it with the old
        // turn's duration. `isTranscriptBusy` is THE "is a run in flight"
        // question; bar 306-E pins this line.
        guard !isDrainingComposeOutbox, !isTranscriptBusy,
              composeOutbox.pendingTurns.contains(where: { isDrainableComposeTurn($0) })
        else { return }
        isDrainingComposeOutbox = true
        defer { isDrainingComposeOutbox = false }

        // #240: one history fetch per drain. A queued turn the server already
        // holds was DELIVERED (pre-`run.started` parking) — drop the outbox
        // copy instead of making Hermes answer it twice. A nil fetch
        // (offline, or no server-backed session) drains exactly as before:
        // the guard is an optimization, not a gate.
        let serverMessages = await hermesClient.reconcileFromServer()?.messages

        while let turn = composeOutbox.pendingTurns.first(where: { isDrainableComposeTurn($0) }) {
            composeOutbox.remove(entryID: turn.id)
            persistComposeOutbox()
            // #306 T1: only `.unreachable` parks have a transcript row to
            // replace; a released hold mints its first row inside the
            // `sendMessage` below (the identity ruling).
            if let rowID = turn.transcriptRowID, var conv = conversation {
                conv.messages.removeAll { $0.id == rowID || $0.clientMessageID == rowID }
                conversation = conv
            }
            // #306: the #240 adoption guard applies ONLY to `.unreachable`
            // parks — those were posted once, so a server-side twin means
            // "already delivered". A held turn was NEVER posted; a matching
            // server row can only be a coincidental repeat inside the skew
            // window, and adopting it would eat the message.
            if turn.reason == .unreachable,
               let serverMessages, Self.historyAdoptsQueuedTurn(turn, serverMessages: serverMessages) {
                // The transcript already carries the server's copy (the #235
                // reconcile adopted the server view); the queued row was
                // removed above — persist that removal, since no send
                // pipeline follows to do it.
                chatLog.notice("compose outbox: turn already delivered server-side — adopted, not re-sent (#240)")
                if let conversation { persistence.saveConversationCache(conversation) }
                continue
            }
            let dispatched = await sendMessage(turn.text)
            if !dispatched {
                if turn.reason == .heldDuringTurn {
                    // #306 trap 6 / bar 306-B: a swallowed FIRE is a failure,
                    // not a dedupe — the drain's leniency below exists for
                    // parked rows whose transcript twin still represents the
                    // message, and a held turn HAS no twin. Re-surface it so
                    // the user decides, never silently drop.
                    var restored = turn
                    restored.phase = .surfaced
                    composeOutbox.pendingTurns.insert(restored, at: 0)
                    persistComposeOutbox()
                    chatLog.notice("mid-turn hold: fire swallowed by a send guard — re-surfaced, not dropped (#306)")
                    continue
                }
                // Swallowed by a sendMessage guard — in practice the
                // duplicate check, meaning an identical row is already
                // pending in the transcript. Dropping the outbox copy IS the
                // dedupe; the pending row still represents the message.
                chatLog.notice("compose outbox: drained turn duplicated a pending row — dropped (#90)")
                continue
            }
            if didQueueComposeTurnDuringSend {
                // The re-queue appended the turn behind any still-waiting
                // ones — restore it to the front (by identity) so the queue
                // stays FIFO.
                if let requeuedID = lastQueuedComposeTurnID,
                   let idx = composeOutbox.pendingTurns.firstIndex(where: { $0.id == requeuedID }),
                   idx > 0 {
                    let requeued = composeOutbox.pendingTurns.remove(at: idx)
                    composeOutbox.pendingTurns.insert(requeued, at: 0)
                    persistComposeOutbox()
                }
                chatLog.notice("compose outbox: still unreachable — \(self.composeOutbox.pendingTurns.count) turn(s) remain queued (#90)")
                break
            }
        }
    }

    private func persistComposeOutbox() {
        persistence.saveComposeOutboxState(composeOutbox)
    }

    // MARK: - Mid-turn message queue (#306)

    /// #306 (O2/trap 7): reads the composer's LIVE text at Stop time, wired
    /// by ChatScreen. The Stop-restore must not let the last writer win: an
    /// empty composer takes the held text back (via the #48 seed); a
    /// composer the user has since typed into KEEPS the user's text, and the
    /// held text stays on the chip for explicit restore. Nil (tests, Siri's
    /// Cancel with no composer on screen) reads as empty.
    var composerLiveText: (@MainActor () -> String)?

    /// The current thread's mid-turn hold, if any — held or surfaced; a
    /// `.released` entry is in drain flight and no longer the chip's
    /// business. Drives the composer chip (chip, not a transcript bubble —
    /// the identity ruling and #282 both forbid a row).
    var currentThreadHeldTurn: ComposeOutboxState.PendingTurn? {
        composeOutbox.pendingTurns.first {
            $0.reason == .heldDuringTurn && $0.phase != .released
                && composeTurnBelongsToCurrentThread($0)
        }
    }

    /// #306 T2 — the hold: commit the NEXT message while a turn is still in
    /// flight. Thread-scoped, depth 1 (O4: "a next message, not a mailbox"),
    /// persisted immediately (the `sendMessage` precedent — nothing may die
    /// holding the only copy), and mints NO transcript row (C3). Returns
    /// false when there is nothing to wait on (`isTranscriptBusy` — C2,
    /// never `isStreaming`) or a hold already exists for this thread.
    @discardableResult
    func holdComposedTurn(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard isTranscriptBusy else { return false }
        guard currentThreadHeldTurn == nil else { return false }
        composeOutbox.hold(text: trimmed, threadKey: currentComposeThreadKey)
        persistComposeOutbox()
        chatLog.notice("mid-turn hold: composed turn held against the thread (#306)")
        return true
    }

    /// The chip's Cancel/Discard: removes the hold with nothing posted.
    func cancelHeldTurn() {
        guard let turn = currentThreadHeldTurn else { return }
        composeOutbox.remove(entryID: turn.id)
        persistComposeOutbox()
    }

    /// The chip's Edit: removes the hold and hands its text back for the
    /// composer. The entry id dies here; a later re-hold mints a fresh one.
    func editHeldTurn() -> String? {
        guard let turn = currentThreadHeldTurn else { return nil }
        composeOutbox.remove(entryID: turn.id)
        persistComposeOutbox()
        return turn.text
    }

    /// The surfaced chip's "Send now": the user's explicit fire. Same gate
    /// as the automatic one — never into a live run.
    func sendHeldTurnNow() async {
        guard !isTranscriptBusy, !isDrainingComposeOutbox else { return }
        guard let turn = currentThreadHeldTurn else { return }
        composeOutbox.releaseToTail(entryID: turn.id)
        persistComposeOutbox()
        await drainComposeOutboxIfPossible()
    }

    /// #306 T3 — how a turn ended, as OBSERVED at its terminal arm. The fire
    /// condition branches on this and never on the user row's final status:
    /// `.completed`, `.stopped`, and `.expiredUnrecoverable` all leave that
    /// row `.delivered` (trap 3 / bar 306-D), so a status read ships matrix
    /// rows 2 and 10 as bugs on day one.
    enum ObservedTurnTerminal {
        /// Matrix row 1 — `.finished`, or the poll loop confirming delivery
        /// (row 7's happy resolution). The ONE terminal that fires.
        case completed
        /// Row 2 — the user's Stop. Never fires; text restores (O2).
        case stopped
        /// Row 3 — stream dropped, run committed; `pendingRun` is live and
        /// `attemptReconcile` owns resolution. HOLD.
        case streamDroppedRunLive
        /// Row 4 — a dying stream's late duplicate (#237). No-op.
        case lateDuplicate
        /// Row 5 — the host never got the turn. DEMOTE into the outbox
        /// behind the just-parked turn; reachability owns it from here.
        case unreachable
        /// Row 6 — failed before acceptance. HOLD + SURFACE.
        case failedOutright
        /// Row 7 — failed after acceptance; the poll loop owns the turn.
        /// HOLD — resolves to `.completed` or `.pollExhausted`.
        case failedAfterAccept
        /// Row 8 — the poll loop gave up. HOLD + SURFACE.
        case pollExhausted
        /// Row 9 — background budget expired, recovery armed (#295). HOLD —
        /// identical to row 3.
        case expiredRecoverable
        /// Row 10 — background budget expired, nothing is coming (#295).
        /// HOLD + SURFACE (`.delivered` here means settled, not answered).
        case expiredUnrecoverable
        /// Row 3's resolution — `attemptReconcile` adopted the dropped run's
        /// reply. Fires.
        case reconciled
        /// Row 3's other tail — the reconcile budget expired with no
        /// adoption. SURFACE, never silently fire.
        case reconcileBudgetExpired
    }

    /// #306 T3 — THE single resolution point. Every terminal arm reports its
    /// outcome here (not twelve scattered edits), and this switch is the
    /// whole of the matrix's queue column. Walk-away (row 11) and process
    /// death (row 12) do not come through a terminal at all — they park via
    /// `abandonPendingRun` and the cold-load surface pass respectively.
    private func resolveHeldTurn(after terminal: ObservedTurnTerminal) {
        switch terminal {
        case .completed, .reconciled:
            attemptHeldTurnFire()
        case .stopped:
            performStopRestoreOfHeldTurn()
        case .streamDroppedRunLive, .failedAfterAccept, .expiredRecoverable, .lateDuplicate:
            break // HOLD — the turn (or its recovery) is still in motion.
        case .unreachable:
            demoteHeldTurnIntoOutbox()
        case .failedOutright, .pollExhausted, .expiredUnrecoverable, .reconcileBudgetExpired:
            surfaceHeldTurn()
        }
    }

    /// Schedules the fire off the terminal arm's synchronous path. The fire
    /// itself re-checks the gate — the scheduled task may run into a world
    /// where a new turn already started.
    private func attemptHeldTurnFire() {
        Task { [weak self] in await self?.fireHeldTurnIfReady() }
    }

    /// #306 T4 — the fire. Gated strictly on `!isTranscriptBusy` (C2 — the
    /// #278 window keeps `isStreaming` false while a run is very much alive,
    /// and firing there is #307's corruption: `attemptReconcile` adopts the
    /// queued turn's reply as the dropped run's answer) and
    /// `!isDrainingComposeOutbox`. Only a `.held` entry fires — a surfaced
    /// one NEVER auto-fires (the user decides via Send now). The release
    /// moves the entry into the drain, which owns the remove-then-send
    /// discipline so `hasPendingDuplicateMessage` cannot swallow the post.
    private func fireHeldTurnIfReady() async {
        guard !isTranscriptBusy, !isDrainingComposeOutbox else { return }
        guard let turn = currentThreadHeldTurn, turn.phase == .held else { return }
        composeOutbox.releaseToTail(entryID: turn.id)
        persistComposeOutbox()
        chatLog.notice("mid-turn hold: firing after a completed turn (#306)")
        await drainComposeOutboxIfPossible()
    }

    /// #306 O2 — Stop means stop, and the text comes BACK. With an empty
    /// composer the held text restores through the #48 seed (seed-only,
    /// never auto-send; ChatScreen already consumes it). With diverged live
    /// text (trap 7) the user's typing keeps the composer and the held text
    /// surfaces on the chip for explicit restore — last writer must not win.
    private func performStopRestoreOfHeldTurn() {
        guard let turn = currentThreadHeldTurn, turn.phase == .held else { return }
        let liveText = (composerLiveText?() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if liveText.isEmpty {
            composeOutbox.remove(entryID: turn.id)
            persistComposeOutbox()
            seedComposer(turn.text)
            chatLog.notice("mid-turn hold: Stop — held text restored to the composer (#306 O2)")
        } else {
            var surfaced = turn
            surfaced.phase = .surfaced
            composeOutbox.update(surfaced)
            persistComposeOutbox()
            chatLog.notice("mid-turn hold: Stop with diverged composer — held text surfaced on the chip (#306 trap 7)")
        }
    }

    /// Matrix row 5 — the turn this hold was waiting on never reached the
    /// host. The `.unreachable` arm just parked THAT turn; the hold joins
    /// the same outbox BEHIND it, order preserved, and reachability owns
    /// both from here. Never fires; never vanishes.
    private func demoteHeldTurnIntoOutbox() {
        guard let turn = currentThreadHeldTurn, turn.phase == .held else { return }
        composeOutbox.releaseToTail(entryID: turn.id)
        persistComposeOutbox()
        chatLog.notice("mid-turn hold: demoted into the offline outbox behind the parked turn (#306 row 5)")
    }

    /// Rows 6/8/10 + row 3's budget expiry: the turn produced no answer.
    /// The chip says so and offers Send now / Edit / Discard — auto-firing
    /// into a broken session is worse than one extra tap (O3).
    private func surfaceHeldTurn() {
        guard var turn = currentThreadHeldTurn, turn.phase == .held else { return }
        turn.phase = .surfaced
        composeOutbox.update(turn)
        persistComposeOutbox()
    }

    /// Row 11 — the walk-away park, called from `abandonPendingRun` (the one
    /// teardown primitive every walk-away path calls). The departing
    /// thread's hold is not discarded and not fired: it surfaces, because
    /// the turn it was waiting on will never report a terminal now.
    ///
    /// **Review round 2: `.released` held-origin entries surface here too.**
    /// A row-5 demote leaves the hold `.released` behind its `.unreachable`
    /// predecessor; if the thread is then departed non-destructively, the
    /// predecessor dies with the clear (#90) but the released hold survives
    /// — and `.released` bypasses the chip entirely, so on return it would
    /// AUTO-SEND via the drain, without the message it followed, with no
    /// confirmation: the exact silent post the matrix's SURFACE rows exist
    /// to prevent. Demoting it back to `.surfaced` at the DEPARTURE BOUNDARY
    /// makes return show the chip (Send now / Edit / Discard) instead.
    /// In-thread behavior is untouched: a demote that never leaves its
    /// thread still drains oldest-first, and `.unreachable`-origin parks
    /// keep #90's auto-resend semantics — those were confirmed sends.
    private func parkHeldTurnsOnWalkAway() {
        var changed = false
        for idx in composeOutbox.pendingTurns.indices {
            let turn = composeOutbox.pendingTurns[idx]
            guard turn.reason == .heldDuringTurn,
                  turn.phase != .surfaced,
                  composeTurnBelongsToCurrentThread(turn) else { continue }
            composeOutbox.pendingTurns[idx].phase = .surfaced
            changed = true
        }
        if changed { persistComposeOutbox() }
    }

    /// Row 12 — process death mid-turn. No turn survives a relaunch, so
    /// every still-`.held` entry (any thread) surfaces on cold load — and
    /// nothing fires at launch: the fire only ever runs off an observed
    /// terminal, which a launch does not have.
    private func surfaceHeldTurnsAfterColdLoad() {
        var changed = false
        for idx in composeOutbox.pendingTurns.indices
        where composeOutbox.pendingTurns[idx].reason == .heldDuringTurn
            && composeOutbox.pendingTurns[idx].phase == .held {
            composeOutbox.pendingTurns[idx].phase = .surfaced
            changed = true
        }
        if changed {
            persistComposeOutbox()
            chatLog.notice("mid-turn hold: surfaced after cold load — the turn it waited on died with the process (#306 row 12)")
        }
    }

    // MARK: - Model controls

    /// Model identifiers exposed by the connected host. Returns [] when the host
    /// is unreachable so callers can fall back to placeholder options.
    func availableModels() async -> [String] {
        (try? await hermesClient.availableModels()) ?? []
    }

    /// Switches the active model. Applies to the NEXT session (the Hermes agent
    /// dispatches `/model` as a command turn), so start a new chat for it to take
    /// effect. Updates the displayed model immediately for toolbar feedback.

    // MARK: - Sessions

    /// The most recent successfully fetched session list (#96): the server
    /// half of the in-app conversation search corpus. Search never fetches
    /// per keystroke — it reads this snapshot, which refreshes whenever the
    /// drawer (or any other caller) loads sessions. Kept across a failed
    /// refresh: a stale-but-real list beats an empty one.
    private(set) var lastLoadedSessions: [HermesSessionInfo] = []

    /// #175: when `lastLoadedSessions` was fetched. The session list has no
    /// timer behind it — every fetch is a view appearing (the chat seams, the
    /// persistent sidebar's mount, a settings screen wanting a count) and none
    /// of them know about the others, so an idle minute logged three identical
    /// `GET /api/sessions`. This is the shared cache they were all missing.
    private var lastSessionsLoadAt: Date?

    /// How long an unforced `loadSessions()` may answer from the snapshot.
    /// Sized to swallow a burst of near-simultaneous appearances, not to hold
    /// a list across real use: everything that MUTATES the list (open, clear,
    /// new chat) forces through.
    static let sessionsSnapshotTTL: TimeInterval = 15

    /// Recent sessions from the host. Returns [] when unreachable.
    ///
    /// Answers from `lastLoadedSessions` when a fetch landed within
    /// `sessionsSnapshotTTL` (#175). Pass `force: true` after anything that
    /// changed the list server-side — a stale count there would be a lie, not
    /// a saved request.
    func loadSessions(force: Bool = false) async -> [HermesSessionInfo] {
        if !force,
           let loadedAt = lastSessionsLoadAt,
           Date.now.timeIntervalSince(loadedAt) < Self.sessionsSnapshotTTL {
            chatLog.verbose("loadSessions: served \(lastLoadedSessions.count) from snapshot (#175)")
            return lastLoadedSessions
        }
        do {
            let sessions = try await hermesClient.listSessions()
            chatLog.verbose("loadSessions: got \(sessions.count) sessions")
            lastLoadedSessions = sessions
            lastSessionsLoadAt = .now
            onSessionsLoaded?(sessions)
            return sessions
        } catch {
            // #190B: a failed refresh serves the stale-but-real snapshot
            // instead of [] — returning empty here EMPTIED the drawer
            // whenever the configured host's fetch failed, which on device
            // read as "the departing chat vanished after New" (it was in the
            // snapshot all along). `lastSessionsLoadAt` deliberately stays
            // untouched so the next unforced load retries instead of caching
            // the failure.
            chatLog.error("loadSessions: FAILED — \(error.localizedDescription, privacy: .public); serving \(self.lastLoadedSessions.count) from the last real list")
            return lastLoadedSessions
        }
    }

    /// Opens an existing session: loads its history and continues that thread.
    func openSession(_ id: String) async {
        chatLog.verbose("openSession: opening '\(id)'")
        // #184: abandon the departing session's run BEFORE the client
        // switches its internal session — `reconcileFromServer()` takes no
        // session argument, so a stale pendingRun would be compared against
        // the new session's server view and smear S1 artifacts onto it.
        // stopSpeech true since #190 (Owen, 2026-07-26): session A's
        // read-aloud continuing over session B is the same cross-session
        // leak, audible instead of persisted — a switch is a commit, not a
        // browse.
        abandonPendingRun(stopSpeech: true)
        do {
            let fetched = try await hermesClient.openSession(id)
            // #277: the server transcript rebuilds the write_file CARD from
            // its stored tool calls and can never rebuild the CHIP — the
            // stored call decodes name + preview, never `args`/`content`, so
            // a Tier-1 attachment has nothing to be reconstructed from. Put
            // the recorded chips back before the conversation is published,
            // so the cache save below carries them too.
            //
            // Deliberately NOT routed through `mergeConversationMetadata`:
            // that merge is built for two views of ONE thread, and here the
            // local conversation is a DIFFERENT thread — it would re-append
            // every departing row as "unconfirmed" (#248), hand the arriving
            // thread the departing conversation's UUID (P1/#90, which the
            // journal hop and #27's brain pins key on), and keep the
            // departing title (#4.8). Pinned in
            // `AgentFileChipPersistenceTests`.
            var convo = fetched
            convo.messages = AgentAttachmentSidecar.replaying(
                agentAttachments.rows(forSessionID: id),
                onto: convo.messages
            )
            conversation = convo
            lastOpenedSessionID = id
            lastTokenUsage = convo.latestUsage
            pendingMessageSentAt = nil
            sessionOpenFailure = nil
            persistence.saveConversationCache(convo)
            // Re-file under the ids this fetch just handed us: the server's
            // stable row identity (#237). That upgrades every record from the
            // content tier to the id tier, so the content fingerprint is only
            // ever needed for ONE crossing — the first return after the chip
            // was made on a client-minted placeholder id.
            recordAgentAttachments(under: id)
            onConversationChanged?()
            // P1 (#90): the Sessions client already adopted the thread into
            // the journal (identity + current hop); this sync is the no-op
            // alignment for non-hop backends (local brain, mocks).
            journal?.sync(with: convo)
            chatLog.verbose("openSession: loaded \(convo.messages.count) messages for '\(id)'")
        } catch {
            // #190B: a failed open is user-visible state, not a log line —
            // the silent version of this catch is why the 2026-07-26 device
            // fail read as a dead tap.
            let described = error.localizedDescription
            sessionOpenFailure = SessionOpenFailure(
                sessionID: id,
                message: described.isEmpty ? "The conversation couldn't be opened." : described
            )
            chatLog.error("openSession: FAILED for '\(id, privacy: .public)' — \(described, privacy: .public)")
        }
    }

    func replaceCommandCatalog(_ catalog: [SlashCommand], activeModel: String? = nil, contextWindow: Int? = nil) {
        commandCatalog = catalog.isEmpty ? SlashCommand.allBuiltIn : catalog
        if let activeModel { activeModelName = activeModel }
        if let contextWindow { updateContextWindow(contextWindow, source: "command catalog") }
    }

    func resetCommandCatalog() {
        commandCatalog = SlashCommand.allBuiltIn
        activeModelName = nil
        updateContextWindow(nil, source: "catalog reset")
    }

    /// Drops back to the built-in command list WITHOUT discarding the active
    /// model or its Hermes-reported context window. Used when a catalog refresh
    /// merely failed (the relay is offline by design much of the time) — a
    /// transient fetch failure must not demote the CTX denominator from a
    /// Hermes-reported value to the nominal client-side table (#4).
    func restoreBuiltInCatalog() {
        commandCatalog = SlashCommand.allBuiltIn
    }

    func reset() {
        // #184: reset() runs on the pairing lifecycle — its two callers are
        // handlePairingActivated/-Removed, after which initialize() runs
        // against a DIFFERENT host. The departing host's stream and pending
        // run must die here or they leak cross-host (the same race class the
        // #136 comments at both call sites reason about for the bootstrap).
        abandonPendingRun(stopSpeech: true)
        isPollingEnabled = false
        resetCommandCatalog()
        conversation = nil
        isLoading = false
        pendingMessageSentAt = nil
        lastTokenUsage = nil
        sessionOpenFailure = nil
        lastLoadedSessions = []
        persistence.clearConversationCache()
        journal?.reset()
        composeOutbox = ComposeOutboxState()
        persistence.clearComposeOutboxState()
        // #277: the sidecar names every file the agent wrote for this pairing
        // — it goes with the conversation cache, not one unpair later.
        lastOpenedSessionID = nil
        agentAttachments = AgentAttachmentSidecar()
        persistence.clearAgentAttachmentSidecar()
    }

    func resolvedContextWindow(fallbackModelName: String?) -> Int? {
        contextWindow ?? Self.inferredContextWindow(for: fallbackModelName)
    }

    private var hasPendingMessages: Bool {
        conversation?.messages.contains(where: { $0.sender == .user && $0.status == .sending }) == true
    }

    private func hasPendingDuplicateMessage(_ content: String, attachments: [PendingAttachment]) -> Bool {
        conversation?.messages.contains(where: {
            $0.sender == .user
                && ($0.status == .sending || $0.status == .queued)
                && Self.normalizedRetryContent(for: $0) == content
                && attachmentSignature(for: $0.attachments) == attachmentSignature(for: attachments.map { MessageAttachment(from: $0) })
        }) == true
    }

    // ⚠️ #145's sibling defect — FILED, NOT FIXED. The comment here used to read
    // "30 × 2s = 60 seconds max" and was wrong by more than an order of magnitude:
    // the 2s is the SLEEP, and each attempt also makes a network call the arithmetic
    // ignored. Against a black-holed host that call used to run to the shared 300s
    // ceiling, putting the real bound near 2.5 HOURS. #145 Part A now caps
    // interactive requests at 20s, so today's true ceiling is 30 × (2s + ≤20s) ≈
    // 11 minutes — still not 60 seconds, and still the attempt-counter shape Part C
    // replaced with a wall-clock budget in the reconcile loop.
    //
    // Left in place deliberately (scope: #145 Part E's residue), and the number is
    // NOT the fix — `reconcileWallClockBudget`'s shape is. Do not add a third loop
    // of this shape; convert this one when it is routed.
    private static let maxPollAttempts = 30

    private func restartPendingPollingIfNeeded() {
        guard isPollingEnabled, hasPendingMessages else {
            pollingTask?.cancel()
            pollingTask = nil
            return
        }

        guard pollingTask == nil else { return }

        // #293(a): the token. The teardown at the bottom of this task used to
        // read `self.pollingTask?.isCancelled == false`, which is TRUE
        // precisely when a newer task has already replaced this one — so a
        // finishing loop could nil out its successor's handle and leave the
        // live task unreachable. Same shape, and the same fix, as
        // `ChatBackendRouter.finishRun(_:)`, `clearActiveRunContext(matchingRunID:)`
        // and `AppContainer`'s `bootstrapGeneration`: only the task that still
        // owns the handle may clear it.
        pollingGeneration &+= 1
        let generation = pollingGeneration

        pollingTask = Task { [weak self] in
            guard let self else { return }
            var attempts = 0

            while !Task.isCancelled, attempts < Self.maxPollAttempts {
                attempts += 1
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                let fresh = await self.hermesClient.loadConversation()
                self.conversation = self.mergeConversationMetadata(from: self.conversation, into: fresh)
                // #25: adopt the merged usage only when no stream is live —
                // mid-stream it's an interim number and the gauge must not
                // flash it. Recovery polling (stream died post-accept,
                // streamingMessageID already nil) still settles through here.
                if self.streamingMessageID == nil, let latestUsage = self.conversation?.latestUsage {
                    self.lastTokenUsage = latestUsage
                }
                if let conversation = self.conversation {
                    self.persistence.saveConversationCache(conversation)
                    self.onConversationChanged?()
                }
                if self.hasPendingMessages == false {
                    self.pendingMessageSentAt = nil
                    // #306 matrix row 7 → row 1: the poll confirmed delivery
                    // — a completed terminal. (After any OTHER terminal the
                    // held entry is no longer `.held`, so this report is a
                    // no-op there; the fire branches on observed terminals
                    // and phases, never on row status.)
                    self.resolveHeldTurn(after: .completed)
                    break
                }
            }

            // If we exhausted attempts, mark stuck messages as failed — but only
            // when no direct stream is still in flight. A tool-heavy turn can run
            // past the 60s poll window, and the stream (not the relay) is the
            // authority on delivery, so we must not preempt it with a false failure.
            if attempts >= Self.maxPollAttempts, self.hasPendingMessages, self.streamingMessageID == nil {
                if var conv = self.conversation {
                    for i in conv.messages.indices where conv.messages[i].sender == .user && conv.messages[i].status == .sending {
                        conv.messages[i].status = .failed
                    }
                    self.conversation = conv
                    self.persistence.saveConversationCache(conv)
                }
                self.pendingMessageSentAt = nil
                self.onSendFailed?()
                // #306 matrix row 8: the poll gave up — HOLD + SURFACE.
                // (Also why the queue mints no early `.sending` row: this
                // sweep is not targeted and would have eaten it.)
                self.resolveHeldTurn(after: .pollExhausted)
            }

            if self.pollingGeneration == generation {
                self.pollingTask = nil
            }
        }
    }

    /// Re-attaches transient streaming artifacts (tool timeline, code diff) onto the
    /// canonical conversation that the relay returned, since the relay knows nothing
    /// about those client-only fields.
    // MARK: - Interrupted-run reconcile (Phase 1)

    /// Called on app foreground to catch a run that finished while the app was
    /// suspended and the in-app loop couldn't tick.
    #if DEBUG
    /// harness-visible (#226 leg c): seeds a pending run so the single-flight
    /// can be exercised without driving a real dropped stream. `#if DEBUG`
    /// because production never reads it — and per #218, a gating edit is
    /// verified with a Release build, which this lane's gate run does.
    func seedPendingRunForTesting(sessionId: String, runId: String?) {
        pendingRun = PendingRun(
            sessionId: sessionId,
            runId: runId,
            userMessageID: UUID(),
            sentAt: .distantPast,
            partialReasoning: nil
        )
    }
    #endif

    /// #226 leg (c) / **#227 instance 3** — single-flight.
    ///
    /// Four call sites invoke this (`AppContainer.swift:1573,1682,1699,1776`),
    /// and on a foreground transition more than one can fire. Without
    /// coalescing, two concurrent reconciles could both find the same pending
    /// run, both succeed, and both post a completion notification — the third
    /// banner in §D4's measured ×3.
    ///
    /// Same shape as `AppSessionStore.refreshAccessTokenIfNeeded`'s keyed task
    /// map and #145 Part D's activation task. **Deliberately not an
    /// `isReconciling` Bool:** every concurrent caller passes that check before
    /// any of them sets it, which is the non-guard #227 exists to name.
    func reconcilePendingRuns() async {
        if let running = reconcileInFlight {
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performReconcilePendingRuns()
        }
        reconcileInFlight = task
        await task.value
        if reconcileInFlight == task { reconcileInFlight = nil }
    }

    private func performReconcilePendingRuns() async {
        guard let pending = pendingRun else { return }
        if await attemptReconcile(pending) == false {
            startReconcileLoopIfNeeded()
        }
    }

    private func startReconcileLoopIfNeeded() {
        guard reconcileTask == nil, pendingRun != nil else { return }
        let budget = reconcileWallClockBudget
        let interval = reconcilePollInterval
        // #293(a): the same token as the poll loop's — this teardown cleared
        // `reconcileTask` unconditionally, so a loop finishing one main-actor
        // hop after a newer one was armed would nil the NEW task's handle.
        reconcileGeneration &+= 1
        let generation = reconcileGeneration
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            // #145 Part C: elapsed WALL TIME is the budget. See
            // `reconcileWallClockBudget` for why the old attempt counter was
            // wrong by ~30× and why this still needs Part A to be sufficient.
            let deadline = ContinuousClock.now + budget
            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let pending = self.pendingRun else { break }
                if await self.attemptReconcile(pending) { break }
            }
            // #306 matrix row 3's other tail: the budget ran out with no
            // adoption and the run is still unresolved — SURFACE the held
            // message, never silently fire (`pendingRun` stays live, so the
            // fire gate would block anyway; the user gets the honest chip).
            if !Task.isCancelled, self.pendingRun != nil {
                self.resolveHeldTurn(after: .reconcileBudgetExpired)
            }
            if self.reconcileGeneration == generation {
                self.reconcileTask = nil
            }
        }
    }

    /// One reconcile pass: fetch the server's view of the session; if the
    /// assistant reply landed after the run started, adopt it, notify, and clear
    /// the pending run. Returns true when resolved.
    @discardableResult
    private func attemptReconcile(_ pending: PendingRun) async -> Bool {
        guard let serverConvo = await hermesClient.reconcileFromServer() else { return false }
        let reply = serverConvo.messages.last(where: {
            $0.sender == .hermes
                && $0.timestamp > pending.sentAt
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        guard let reply else {
            // #293(b) — MEASUREMENT ONLY, deliberately not a fix. This
            // predicate compares a CLIENT clock (`pending.sentAt` is a local
            // `Date()`) against HOST timestamps with strict `>` and no slack,
            // while the sibling guard one screen away
            // (`historyAdoptsQueuedTurn`) subtracts 60s and calls that
            // clock-skew slack in so many words. If the phone runs ahead of
            // the host, every reply row stamps earlier than `sentAt` and this
            // pass can never match. Adding slack here would change BEHAVIOR
            // on a hypothesis nobody has measured, so log the two clocks and
            // their delta instead — one line per failed pass, readable from a
            // device log — and let the numbers decide.
            let newestHostRow = serverConvo.messages.last(where: { $0.sender == .hermes })?.timestamp
            chatLog.notice(
                "reconcile pass found no candidate (#293b): sentAt=\(pending.sentAt.timeIntervalSince1970, privacy: .public) newestHermesRow=\(newestHostRow?.timeIntervalSince1970 ?? -1, privacy: .public) delta=\(newestHostRow.map { $0.timeIntervalSince(pending.sentAt) } ?? .nan, privacy: .public) hermesRows=\(serverConvo.messages.filter { $0.sender == .hermes }.count, privacy: .public)"
            )
            return false
        }

        // #235 F3: the prompt text lives in the PRE-adoption conversation
        // (server rows have different ids) — capture it before replacing.
        let promptText = conversation?.messages
            .first(where: { $0.id == pending.userMessageID })?.content

        conversation = mergeConversationMetadata(from: conversation, into: serverConvo)
        // #4.15: the server transcript filters `_thinking`, so the reasoning
        // that streamed before the drop survives only in the pending run —
        // re-attach it (partial by definition: the stream died mid-think).
        if let partial = pending.partialReasoning, !partial.isEmpty,
           var conv = conversation,
           let idx = conv.messages.firstIndex(where: { $0.id == reply.id }),
           conv.messages[idx].reasoning == nil {
            conv.messages[idx].reasoning = partial
            conversation = conv
        }
        // #46: receipt for the reconciled turn. Duration comes from two real
        // timestamps (send → reply landing). Usage is adopted only when the
        // reply is the session's last Hermes message — the conversation-level
        // `latestUsage` then belongs to this run; anything else would be a
        // guess.
        if var conv = conversation,
           let idx = conv.messages.firstIndex(where: { $0.id == reply.id }) {
            if conv.messages[idx].turnDuration == nil {
                conv.messages[idx].turnDuration = reply.timestamp.timeIntervalSince(pending.sentAt)
            }
            if conv.messages[idx].usage == nil,
               serverConvo.messages.last(where: { $0.sender == .hermes })?.id == reply.id {
                conv.messages[idx].usage = serverConvo.latestUsage
            }
            if conv.messages[idx].servingModel == nil {
                conv.messages[idx].servingModel = activeModelName
            }
            conversation = conv
        }
        if let latestUsage = conversation?.latestUsage {
            lastTokenUsage = latestUsage
        }
        // #235 F3: Owen's placement rule — a recovered reply displaced by
        // later exchanges lands at the TAIL, where the user is looking.
        if var conv = conversation {
            conv.messages = Self.placingRecoveredReply(reply.id, prompt: promptText, in: conv.messages)
            conversation = conv
        }
        // #237: this run has adopted — a late duplicate interrupt for it is
        // noise from here on, never a re-arm.
        if let runId = pending.runId {
            resolvedRunIDs.insert(runId)
        }
        pendingRun = nil
        pendingMessageSentAt = nil
        onRunResolved?(pending.sessionId)
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
            // P1 (#90): the reconciled exchange ran on the active hop's
            // server session — journal it and bump the waterline.
            journal?.sync(with: conversation, lastExchangeViaActiveHop: true)
        }
        finalizeOnDeviceIntelligence()
        // #306 matrix row 3 resolved: the dropped run's reply was adopted —
        // the held message may now fire (the gate re-checks busyness).
        resolveHeldTurn(after: .reconciled)
        return true
    }

    // MARK: - On-device intelligence (#4.8 × #4.15)

    /// Post-turn on-device work: a real title + preview once the first
    /// exchange completes, and a one-line condensation of any reasoning the
    /// turn streamed. Fire-and-forget; every path is guarded so it can run
    /// after every turn without redoing work. No-op when AppContainer hasn't
    /// wired `localIntelligence` (tests).
    private func finalizeOnDeviceIntelligence() {
        generateConversationCardIfNeeded()
        Task { [weak self] in await self?.condensePendingReasoning() }
    }

    /// Generates the conversation's `{title, preview}` after the first
    /// completed exchange (#4.8). Runs only while the title is still the
    /// placeholder, so a manual `/title` (or an earlier generation) is never
    /// overwritten. When the on-device model is unavailable the service
    /// falls back to truncation internally — the conversation still gets a
    /// real label.
    /// The `{userText, assistantText}` the card generator runs on, or nil when
    /// the conversation has no completed exchange to label yet.
    ///
    /// #280: extracted from `generateConversationCardIfNeeded` so the
    /// selection is a pure function with a test of its own — the predicates
    /// here are exactly what decides whether a thread is titled at all, and
    /// they were previously reachable only through a store with a live
    /// `LocalIntelligenceService` wired.
    nonisolated static func conversationCardInputs(
        for conversation: Conversation
    ) -> (userText: String, assistantText: String)? {
        guard let firstReply = conversation.messages.first(where: {
            $0.sender.isAgentAuthored
                && $0.status == .delivered
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        else { return nil }

        // The user side of the exchange. normalizedRetryContent maps the
        // synthetic "[N attachment(s)]" display placeholder to "" — it's not
        // user words and must never become the title; with it empty, the card
        // (and the truncation fallback) derives everything from the reply.
        let firstUserText = conversation.messages
            .first(where: { $0.sender.isUserAuthored })
            .map { normalizedRetryContent(for: $0) } ?? ""

        return (userText: firstUserText, assistantText: firstReply.content)
    }

    private func generateConversationCardIfNeeded() {
        guard let intelligence = localIntelligence,
              let conversation,
              conversation.title == Conversation.defaultTitle,
              !isGeneratingConversationCard,
              let inputs = Self.conversationCardInputs(for: conversation)
        else { return }

        let conversationID = conversation.id
        isGeneratingConversationCard = true
        Task { [weak self] in
            let card = await intelligence.conversationCard(
                userText: inputs.userText,
                assistantText: inputs.assistantText
            )
            guard let self else { return }
            self.isGeneratingConversationCard = false
            // Re-check before writing: the chat may have been cleared or
            // retitled by hand while the model ran.
            guard var conv = self.conversation,
                  conv.id == conversationID,
                  conv.title == Conversation.defaultTitle
            else { return }
            if !card.preview.isEmpty { conv.generatedPreview = card.preview }
            self.conversation = conv
            if !card.title.isEmpty {
                chatLog.notice("on-device conversation card generated (#4.8)")
                self.setConversationTitle(card.title)   // persists + notifies
            } else {
                self.persistence.saveConversationCache(conv)
                self.onConversationChanged?()
            }
        }
    }

    /// Condenses un-summarized reasoning into one line each (#4.15) via the
    /// on-device model — only while foregrounded (background scheduling isn't
    /// worth fighting for; the collapsed row already falls back to the last
    /// raw reasoning line). Newest first, a few per pass: a foreground return
    /// can owe more than one (several turns settled while backgrounded), and
    /// a nil summary ends the pass — model unavailable or a guardrail veto
    /// would otherwise hammer the same input. Also invoked from AppContainer
    /// on foreground so backgrounded turns get their summaries on return.
    func condensePendingReasoning() async {
        for _ in 0 ..< 3 {
            guard let intelligence = localIntelligence,
                  UIApplication.shared.applicationState == .active,
                  let conv = conversation,
                  let index = conv.messages.lastIndex(where: {
                      $0.sender == .hermes
                          && ($0.reasoning?.isEmpty == false)
                          && $0.reasoningSummary == nil
                          && !$0.isStreaming
                  }),
                  let reasoning = conv.messages[index].reasoning
            else { return }

            let messageID = conv.messages[index].id
            guard let summary = await intelligence.condensedReasoning(reasoning) else { return }
            // The conversation may have changed while the model ran — re-find.
            guard var current = conversation,
                  let idx = current.messages.firstIndex(where: { $0.id == messageID })
            else { return }
            current.messages[idx].reasoningSummary = summary
            conversation = current
            persistence.saveConversationCache(current)
            onConversationChanged?()
        }
    }

    private func mergeConversationMetadata(
        from localConversation: Conversation?,
        into refreshedConversation: Conversation?
    ) -> Conversation? {
        guard var refreshedConversation else { return localConversation }

        // #120: never import the same message id twice from a refresh source
        // (a relay transcript, a backend's own thread). The local-vs-refreshed
        // dedupe below can't see an internal duplicate — it would flow into
        // the rendered collection wholesale. First occurrence wins.
        var seenRefreshedIDs = Set<UUID>()
        refreshedConversation.messages = refreshedConversation.messages.filter {
            seenRefreshedIDs.insert($0.id).inserted
        }

        guard let localConversation else { return refreshedConversation }

        // #299: locally-born assistant rows adopt the host's identity at the
        // merge — see `serverIdentityAdoptions`. Consumed twice below: as the
        // field-carry loop's last lookup arm, and as pre-confirmation before
        // `unconfirmedLocalMessages` (whose tiers are untouched).
        let identityAdoptions = Self.serverIdentityAdoptions(
            local: localConversation.messages,
            refreshed: refreshedConversation.messages
        )
        let adoptedLocalIDs = Set(identityAdoptions.values)

        if refreshedConversation.latestUsage == nil {
            refreshedConversation.latestUsage = localConversation.latestUsage
        }

        // Conversation-level metadata is client-local (#4.8): the Sessions
        // client's base conversation only ever carries the placeholder title
        // and no preview, so a merge must not demote the local ones. (Also
        // fixes the long-standing quirk of a manual /title reverting on the
        // next exchange — and without this, the title-generation gate would
        // re-trip and re-run the on-device model every single turn.)
        if refreshedConversation.title == Conversation.defaultTitle,
           localConversation.title != Conversation.defaultTitle {
            refreshedConversation.title = localConversation.title
        }
        if refreshedConversation.generatedPreview == nil {
            refreshedConversation.generatedPreview = localConversation.generatedPreview
        }

        for index in refreshedConversation.messages.indices {
            let remote = refreshedConversation.messages[index]

            // Prefer exact UUID match (works when the relay echoes back the same ID).
            var local: Message?
            if let byID = localConversation.messages.first(where: { $0.id == remote.id }) {
                local = byID
            } else if let remoteClientMessageID = remote.clientMessageID {
                local = localConversation.messages.first(where: {
                    $0.id == remoteClientMessageID || $0.clientMessageID == remoteClientMessageID
                })
            } else if let remoteJobID = remote.jobID {
                // Fallback: the streaming placeholder had a client-generated UUID that
                // differs from the server-assigned message ID.  Match on jobID + sender
                // instead, but only for Hermes messages that actually carry artifacts.
                local = localConversation.messages.first(where: {
                    $0.jobID == remoteJobID
                        && $0.sender == remote.sender
                        && $0.sender == .hermes
                        && (!$0.toolActivities.isEmpty || $0.codeDiff != nil)
                })
            }
            if local == nil, let adoptedID = identityAdoptions[remote.id] {
                // #299: the host row's locally-born twin, paired by turn —
                // its client-only fields (reasoning, receipts, activities)
                // ride the host row exactly as a tier-1 match's would. A
                // FALLBACK after every existing arm rather than a fourth
                // `else if`, so an adopted row's fields can never be dropped
                // by an arm that fired and then failed to match (the jobID
                // arm can): whenever the adopted row is excluded from the
                // unconfirmed re-append below, its fields ride here.
                local = localConversation.messages.first(where: { $0.id == adoptedID })
            }

            guard let local else { continue }

            if !local.toolActivities.isEmpty {
                refreshedConversation.messages[index].toolActivities = local.toolActivities
                refreshedConversation.messages[index].toolActivity = local.toolActivity
            }

            if let diff = local.codeDiff, refreshedConversation.messages[index].codeDiff == nil {
                refreshedConversation.messages[index].codeDiff = diff
            }

            // Reasoning is client-only (#4.15) — the server transcript filters
            // the `_thinking` channel out, so a refresh would otherwise drop it.
            if refreshedConversation.messages[index].reasoning == nil, let reasoning = local.reasoning {
                refreshedConversation.messages[index].reasoning = reasoning
            }
            if refreshedConversation.messages[index].reasoningSummary == nil, let summary = local.reasoningSummary {
                refreshedConversation.messages[index].reasoningSummary = summary
            }

            // Turn receipts are client-only too (#46) — the server transcript
            // carries no per-message usage, duration, or serving model.
            if refreshedConversation.messages[index].usage == nil, let usage = local.usage {
                refreshedConversation.messages[index].usage = usage
            }
            if refreshedConversation.messages[index].turnDuration == nil, let duration = local.turnDuration {
                refreshedConversation.messages[index].turnDuration = duration
            }
            if refreshedConversation.messages[index].servingModel == nil, let model = local.servingModel {
                refreshedConversation.messages[index].servingModel = model
            }

            if !local.attachments.isEmpty {
                refreshedConversation.messages[index].attachments = Self.mergeAttachments(
                    local.attachments,
                    onto: refreshedConversation.messages[index].attachments
                )
            }
        }

        // Preserve any local message the relay hasn't echoed back yet — not just
        // streaming placeholders, but also just-sent user messages still in flight.
        // The relay assigns its own message IDs, so a local message is "confirmed"
        // only if the refreshed conversation contains it by id OR by clientMessageID.
        // Anything unconfirmed must survive the merge, otherwise a sent message
        // vanishes the instant the first poll/refresh returns without it.
        // #299: a local row whose identity was adopted above IS confirmed —
        // its host twin carries its fields and its stable id — so it is not
        // in the unconfirmed filter's input, exactly as a tier-1 hit would
        // leave it. The tiers themselves are untouched.
        refreshedConversation.messages.append(contentsOf: Self.unconfirmedLocalMessages(
            local: localConversation.messages.filter { !adoptedLocalIDs.contains($0.id) },
            refreshed: refreshedConversation.messages
        ))

        // P1 (#90): conversation identity is LOCAL and durable. Refresh
        // sources mint a new Conversation UUID on every fetch; adopting it
        // would churn the thread's identity on each reconcile/poll —
        // resetting the journal (dropping the hop and forcing a spurious
        // re-transplant) and orphaning per-conversation brain pins (#27).
        // The merged thread keeps the local id.
        //
        // #289: field-by-field rebuild — the same silent-drop shape as
        // `mergeAttachments` below, and complete today (6 of 6). If you add a
        // field to `Conversation`, add it here in the same commit.
        if refreshedConversation.id != localConversation.id {
            refreshedConversation = Conversation(
                id: localConversation.id,
                title: refreshedConversation.title,
                messages: refreshedConversation.messages,
                lastActivity: refreshedConversation.lastActivity,
                latestUsage: refreshedConversation.latestUsage,
                generatedPreview: refreshedConversation.generatedPreview
            )
        }

        // #237: every adoption pass exits through the sweep, so even a
        // pre-fix-corrupted local (or an unforeseen union path) converges to
        // single copies instead of compounding.
        refreshedConversation.messages = Conversation.dedupingAdoptedEchoes(refreshedConversation.messages)
        return refreshedConversation
    }

    /// #248: which local messages survive an adoption merge as "unconfirmed"
    /// (and get re-appended so an in-flight send never vanishes). Three
    /// confirmation tiers: exact id, echoed `clientMessageID` — and, because
    /// the GATEWAY transcript carries no `clientMessageID` at all, a CONTENT
    /// CLAIM for user rows: each refreshed user row lacking a client id
    /// confirms at most ONE content-identical local user row (dequeue
    /// counting, so a legitimate repeat still in flight keeps its copy).
    /// Without the third tier, the just-sent user row failed both id checks
    /// after a stall-recovery adoption and was re-appended BELOW the
    /// recovered reply — Owen's build-1987 dupe, healed only by re-entry.
    ///
    /// **#281 — a refreshed row that ALREADY confirms a local twin by id
    /// mints no claim.** Tier 1 returns without decrementing, so any claim
    /// such a row minted was SURPLUS, and the next content-identical local
    /// user row — the one the user had just re-sent — ate it and was filtered
    /// out of the merge. On the Hermes path every previously-adopted row has
    /// exactly that shape once a thread has been opened from the drawer:
    /// `SessionsHermesClient.mapStoredMessage` stamps a stable
    /// server-derived id and never a `clientMessageID`. So on a thread where
    /// the same prompt had been sent twice, a regenerate truncated, re-sent,
    /// and the fresh user row VANISHED — the bubble left on screen was the
    /// older content-identical ask, still carrying its original timestamp
    /// (*"It didn't show the current time for when I actually regenerated
    /// it"* — Owen, the 78-F device failure).
    nonisolated static func unconfirmedLocalMessages(
        local: [Message], refreshed: [Message]
    ) -> [Message] {
        let refreshedIDs = Set(refreshed.map(\.id))
        let refreshedClientIDs = Set(refreshed.compactMap(\.clientMessageID))
        let localIDs = Set(local.map(\.id))
        var claimableUserContent: [String: Int] = [:]
        for row in refreshed
        where row.sender == .user && row.clientMessageID == nil && !localIDs.contains(row.id) {
            claimableUserContent[row.content.trimmingCharacters(in: .whitespacesAndNewlines), default: 0] += 1
        }
        return local.filter { localRow in
            if refreshedIDs.contains(localRow.id) { return false }
            if let clientID = localRow.clientMessageID, refreshedClientIDs.contains(clientID) { return false }
            if localRow.sender == .user {
                let key = localRow.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let claimable = claimableUserContent[key], claimable > 0 {
                    claimableUserContent[key] = claimable - 1
                    return false
                }
            }
            return true
        }
    }

    /// #299: server-derived identity at adoption for locally-born ASSISTANT
    /// rows. A `.hermes` row born in-app has NO confirmation tier — tier 1
    /// misses (its id is a client `UUID()` from the streaming assembly, the
    /// host's copy carries `stableMessageID`, #237), tier 2 misses (the
    /// gateway transcript echoes no `clientMessageID`, #248), and tier 3 is
    /// `.user`-only by construction — so every reconcile of an in-app thread
    /// re-appended each settled assistant row, and `dedupingAdoptedEchoes`
    /// could not collapse the pair because its key includes the timestamp and
    /// the phone's clock is not the host's.
    ///
    /// Returns host-row id → locally-born assistant row id: when the merge
    /// confirms a turn, the host's copy of its reply is paired with the local
    /// row so the local row counts as confirmed (exactly as a tier-1 hit
    /// would leave it) and its client-only fields ride the host row. The
    /// surviving merged row is the same row a drawer reopen would produce —
    /// stable id, host content — and confirms at tier 1 on every later
    /// reconcile, which is what keeps the fix convergent rather than a
    /// per-merge patch.
    ///
    /// Pairing is TURN-anchored, deliberately not a content claim for
    /// `.hermes` rows (that alternative re-imports the demand-side hazards
    /// #282 exists to narrow — and would fail exactly when adoption matters
    /// most, a stall-truncated partial whose host twin carries the full
    /// text). A turn anchors on its USER row — by id, by `clientMessageID`
    /// linkage, or by trimmed content, monotonic and in order (tier 3's
    /// dequeue semantics) — and the turn's settled, non-streaming, non-empty
    /// locally-born `.hermes` rows then zip in order against the turn's
    /// unclaimed non-empty host assistant rows. Everything ineligible fails
    /// OPEN: an unpaired local row keeps its client id and survives the merge
    /// as unconfirmed, which is the pre-#299 behaviour and never loses data.
    /// Voice rows neither anchor nor adopt (`.voiceHermes` renders as a
    /// transcript, not a streamed reply — swapping in the host's `.hermes`
    /// twin would change what the thread IS); a dictated turn still starts a
    /// turn (`isUserAuthored`, #275) so its replies never leak into the
    /// previous turn's candidates.
    nonisolated static func serverIdentityAdoptions(
        local: [Message], refreshed: [Message]
    ) -> [UUID: UUID] {
        let refreshedIDs = Set(refreshed.map(\.id))
        let refreshedClientIDs = Set(refreshed.compactMap(\.clientMessageID))
        let localIDs = Set(local.map(\.id))

        // A transcript as turns: every user-authored row starts one; rows
        // before the first user row form an anchorless preamble (no adoption).
        func turns(_ messages: [Message]) -> [(anchor: Message?, replies: [Message])] {
            var result: [(anchor: Message?, replies: [Message])] = []
            var current: (anchor: Message?, replies: [Message])?
            for row in messages {
                if row.sender.isUserAuthored {
                    if let finished = current { result.append(finished) }
                    current = (anchor: row.sender == .user ? row : nil, replies: [])
                } else {
                    if current == nil { current = (anchor: nil, replies: []) }
                    if row.sender == .hermes { current?.replies.append(row) }
                }
            }
            if let finished = current { result.append(finished) }
            return result
        }

        func anchors(_ localRow: Message, _ remoteRow: Message) -> Bool {
            if localRow.id == remoteRow.id { return true }
            if let remoteClientID = remoteRow.clientMessageID,
               localRow.id == remoteClientID || localRow.clientMessageID == remoteClientID {
                return true
            }
            return localRow.content.trimmingCharacters(in: .whitespacesAndNewlines)
                == remoteRow.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var adoptions: [UUID: UUID] = [:]
        let localTurns = turns(local)
        var nextLocalTurn = localTurns.startIndex
        for remoteTurn in turns(refreshed) {
            guard let remoteAnchor = remoteTurn.anchor else { continue }
            // Monotonic: each local turn pairs at most once, in order; the
            // cursor only advances on a match, so a host-only turn (another
            // client's exchange) never consumes a local one.
            guard let matched = localTurns[nextLocalTurn...].firstIndex(where: { localTurn in
                guard let localAnchor = localTurn.anchor else { return false }
                return anchors(localAnchor, remoteAnchor)
            }) else { continue }
            nextLocalTurn = matched + 1

            let hostRows = remoteTurn.replies.filter { row in
                !localIDs.contains(row.id)
                    && !row.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let locallyBorn = localTurns[matched].replies.filter { row in
                guard !refreshedIDs.contains(row.id) else { return false }
                if let clientID = row.clientMessageID, refreshedClientIDs.contains(clientID) {
                    return false   // tier 2's row — not this pass's to pair
                }
                return row.status.isSettled && !row.isStreaming
                    && !row.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            for (hostRow, localRow) in zip(hostRows, locallyBorn) {
                adoptions[hostRow.id] = localRow.id
            }
        }
        return adoptions
    }

    /// Pairs a refresh source's attachments with the local ones and carries
    /// every client-side field across.
    ///
    /// **#276: this rebuilds the value field by field, which is a silent-drop
    /// hazard the type system cannot catch — every field has a default, so an
    /// omission compiles and reads as `nil`.** `anchorOffset` (#262) was
    /// omitted here and no test referenced this function at all, so every
    /// refresh merge quietly demoted an anchored chip back to the trailing
    /// grid — the exact jump #262 existed to remove. If you add a field to
    /// `MessageAttachment`, add it here in the same commit.
    ///
    /// `nonisolated static` so the pairing rules can be pinned directly,
    /// alongside `unconfirmedLocalMessages` and `historyAdoptsQueuedTurn`.
    nonisolated static func mergeAttachments(_ localAttachments: [MessageAttachment], onto remoteAttachments: [MessageAttachment]) -> [MessageAttachment] {
        guard !remoteAttachments.isEmpty else { return localAttachments }

        // #185: pair by identity, dequeueing each claimed local so N
        // same-named remotes (two picker rounds of the same file name — the
        // only trigger; memos and photos mint unique names) resolve to N
        // distinct local entries instead of all aliasing the first match.
        // Precedence mirrors the message-level merge above: id when the echo
        // preserves it, then (fileName, mimeType), then same-index insurance.
        var unclaimed = localAttachments
        return remoteAttachments.enumerated().map { index, remote in
            let claimed = unclaimed.firstIndex(where: { $0.id == remote.id })
                ?? unclaimed.firstIndex(where: {
                    $0.fileName == remote.fileName && $0.mimeType == remote.mimeType
                })
            let match = claimed.map { unclaimed.remove(at: $0) } ?? localAttachments[safe: index]
            guard let match else { return remote }
            return MessageAttachment(
                id: remote.id,
                kind: remote.kind,
                fileName: remote.fileName,
                mimeType: remote.mimeType,
                thumbnailBase64: remote.thumbnailBase64 ?? match.thumbnailBase64,
                localStoragePath: match.localStoragePath,
                // Client-only (#9): the server never echoes the audio path;
                // the local copy is the source of truth for playback.
                voiceMemoAudioPath: match.voiceMemoAudioPath,
                // Client-only (#21 Tier 2): the fetch pointer and its birth
                // profile never round-trip through the server either.
                remotePath: match.remotePath,
                remoteProfileID: match.remoteProfileID,
                // #276: the inline anchor (#262). Client-derived from the
                // stream's own ordering, so the server never echoes one —
                // but prefer a remote value if one ever appears rather than
                // pinning the local copy as authoritative.
                anchorOffset: remote.anchorOffset ?? match.anchorOffset
            )
        }
    }

    /// #280: `nonisolated static` because it reads no instance state, and
    /// `conversationCardInputs(for:)` — a pure function testable without a
    /// store — needs it. Instance callers reach it through `Self.`.
    nonisolated static func normalizedRetryContent(for message: Message) -> String {
        if !message.attachments.isEmpty,
           message.content.range(of: #"^\[\d+ attachment"#, options: .regularExpression) != nil {
            return ""
        }
        return message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attachmentSignature(for attachments: [MessageAttachment]) -> String {
        attachments
            .map { "\($0.kind)|\($0.fileName)|\($0.mimeType)" }
            .sorted()
            .joined(separator: "||")
    }

    // MARK: - Model Switch Detection

    /// Detect a model switch from the agent's response text.
    /// Updates activeModelName and contextWindow immediately so the
    /// toolbar chip reflects the change in the same render frame.
    // Regex for context window in /model response: "Context: 1,000,000 tokens"
    nonisolated(unsafe) private static let contextWindowPattern = /Context:\s*([\d,]+)\s*tokens/

    /// Extracts the Hermes-reported context window from a `/model` response
    /// ("Context: 262,144 tokens"). This is the authoritative denominator
    /// source for the CTX meter (#4). Nil when the response carries none.
    nonisolated static func reportedContextWindow(in text: String) -> Int? {
        guard let match = text.firstMatch(of: contextWindowPattern) else { return nil }
        let raw = String(match.1).replacingOccurrences(of: ",", with: "")
        guard let value = Int(raw), value > 0 else { return nil }
        return value
    }

    /// Single write path for the CTX denominator, logging every change with its
    /// source so a wrong meter reading is a one-line log read (#4 acceptance).
    private func updateContextWindow(_ value: Int?, source: String) {
        guard value != contextWindow else { return }
        contextWindow = value
        if let value {
            chatLog.notice("contextWindow ← \(value) [\(source, privacy: .public)]")
        } else {
            chatLog.notice("contextWindow ← nil [\(source, privacy: .public)] — display falls back to inferred table")
        }
    }

    private func detectModelSwitch(from text: String) {
        // Match: "Model switched to `claude-sonnet-4-6`" or "Model switched: gpt-4-turbo"
        // Model ids can be slashed (e.g. "anthropic/claude-opus-4.8" from the nous
        // portal), so the capture class must include `/`. Inside a `/.../` regex
        // literal the slash is escaped as `\/`. Keep `-` last so it stays literal.
        let patterns: [Regex<(Substring, Substring)>] = [
            /[Mm]odel\s+switched\s+to\s+`?([A-Za-z0-9._\/-]+)`?/,
            /[Mm]odel\s+switched:\s+`?([A-Za-z0-9._\/-]+)`?/,
        ]
        for pattern in patterns {
            if let match = text.firstMatch(of: pattern) {
                let newModel = String(match.1)
                activeModelName = newModel

                // v0.8.0: the /model response includes "Context: N tokens"
                // — parse it directly instead of relying on a heuristic table.
                // If absent, clear and let the next catalog refresh resolve it.
                updateContextWindow(
                    Self.reportedContextWindow(in: text),
                    source: "chat /model response"
                )
                return
            }
        }
    }

    /// Fallback-only lookup for cases where the connector has not yet provided
    /// an explicit context window. This should never overwrite a known value.
    static func inferredContextWindow(for modelName: String?) -> Int? {
        guard let modelName, !modelName.isEmpty else { return nil }
        let n = modelName.lowercased()

        if n.contains("claude-opus-4-6") || n.contains("claude-opus-4.6")
            || n.contains("claude-sonnet-4-6") || n.contains("claude-sonnet-4.6") {
            return 1_000_000
        }
        if n.contains("claude") { return 200_000 }
        if n.contains("gpt-4.1") { return 1_047_576 }
        if n.contains("gpt-5") { return 128_000 }
        if n.contains("gpt-4") { return 128_000 }
        if n.contains("gemini") { return 1_048_576 }
        if n.contains("gemma-4-31b") || n.contains("gemma-4-26b") { return 256_000 }
        if n.contains("gemma-3") { return 131_072 }
        if n.contains("gemma") { return 8_192 }
        if n.contains("deepseek") { return 128_000 }
        if n.contains("llama") { return 131_072 }
        if n.contains("qwen") { return 131_072 }
        if n.contains("minimax") { return 204_800 }
        if n.contains("glm") { return 202_752 }
        if n.contains("kimi") { return 262_144 }
        if n.contains("mimo-v2-pro") || n.contains("mimo-v2-omni") { return 1_048_576 }
        return 128_000
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

#if DEBUG
// MARK: - Forced-trip harness entry (#134 — DEBUG builds only)

extension ChatStore {
    /// Drives the #134 synthetic degenerate turn through THIS store's normal
    /// send path — the same streaming consumer, read-aloud enqueue, and
    /// finish/retraction handling every real turn gets (building a parallel
    /// consumer would silently skip the #110 seam this harness exists to
    /// verify). The backend is armed one-shot; the router preference pins
    /// the turn to the on-device brain (a Hermes-paired device would
    /// otherwise route it to Hermes) and is restored afterward.
    func debugRunForcedTrip(
        copies: Int = LocalChatBackend.debugDegenerateDefaultCopies,
        holdLiveSDKStream: Bool = false
    ) async {
        guard !isStreaming else { return }
        LocalChatBackend.debugForcedTripCopies = copies
        LocalChatBackend.debugForcedTripHoldsLiveSDKStream = holdLiveSDKStream

        let router = hermesClient as? ChatBackendRouter
        let preSendConversationID = conversation?.id
        let previousPreference = router?.preferredBrain(forConversation: preSendConversationID)
        // pick-only (#192): the harness pin is scoped to this conversation —
        // it must not rewrite the user's sticky app-wide mode.
        router?.setPreferredBrain(.onDevice, forConversation: preSendConversationID, updatesDefault: false)
        await sendMessage("Force repetition trip — #134 debug harness")
        // Restore on the conversation that actually sent (a nil pre-send id
        // means the send created it).
        router?.setPreferredBrain(previousPreference, forConversation: conversation?.id ?? preSendConversationID, updatesDefault: false)
        // Belt-and-braces: if the turn somehow routed elsewhere, the one-shot
        // arming must not hijack the user's next real on-device turn.
        LocalChatBackend.debugForcedTripCopies = nil
        LocalChatBackend.debugForcedTripHoldsLiveSDKStream = false
    }
}
#endif
