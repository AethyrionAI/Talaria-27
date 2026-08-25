import CryptoKit
import Foundation
import os

/// Talks directly to the Hermes API server's Sessions API (default :8642).
///
/// Replaces the relay → connector → Hermes-CLI pipe for chat. Responses are
/// structured JSON / SSE, so they carry no ANSI codes and keep reasoning in a
/// separate channel. Relay/connector are still used for sensors and pairing.
///
/// P1 continuity fabric (OPEN_ITEMS #90): the server session id is an
/// EPHEMERAL, per-hop handle owned by the `ConversationJournalStore` — never
/// the conversation's identity. When no current hop exists (first launch, a
/// stale/expired server session, a model switch, local-brain turns in
/// between), the next turn creates a FRESH server session and transplants
/// condensed journal context into it as turn zero (mechanism validated by the
/// #89 probe) instead of leaning on one long-lived server session.
@MainActor
final class SessionsHermesClient: HermesClientProtocol {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "SessionsHermesClient")
    private static let modelsPath = "/v1/models"
    private static let modelOptionsPath = "/api/model/options"
    private static let sessionsPath = "/api/sessions"

    var connectionStatus: ConnectionStatus = .disconnected
    var currentConversation: Conversation?

    // runs-path-visible (#283): the runs driver opens its own SSE stream and
    // status polls on this same session (`SessionsHermesClient+RunsTransport`).
    let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURLProvider: @MainActor () -> String?
    private let apiKeyProvider: @MainActor () -> String?

    /// #246: how long the live SSE byte stream may go SILENT before the turn
    /// is declared stalled. A zombie stream — socket open, bytes never
    /// coming, the backgrounded-and-returned shape — never ends, so without
    /// this nothing ever threw and recovery never armed. Firing converts to
    /// `.interrupted` (the same catch as a dropped stream), which degrades
    /// transport to the budgeted reconcile poll — a false positive on a
    /// legitimately quiet slow turn still resolves; it never loses the
    /// answer. 60s clears any observed healthy inter-event gap. Var, not
    /// let: the suite shortens it to exercise the guard. // harness-visible
    var streamStallThreshold: Duration = .seconds(60)

    /// #283 slice 3A: how long the runs-plane recovery poll WAITS between
    /// reads of `GET /v1/runs/{id}`. The status object is cheap and the
    /// gateway retains it for an hour, but a tight loop would be a spin — 2s
    /// resolves a run that finished while the stream was dying within one
    /// interval, and costs one request per 2s for a run that has not.
    /// Var, not let: the suite shortens it to run the loop in milliseconds.
    // harness-visible
    var runsPollInterval: Duration = .seconds(2)

    /// #283 slice 3A: the **STREAMED** turn's recovery-poll wall-clock budget
    /// — `streamTurnViaRuns` only. It does NOT bound `send(...)`; that path
    /// has its own, much shorter ceiling (`runsSyncBudget` below), because a
    /// caller holding no continuation has nothing to degrade to.
    ///
    /// Past it the turn hands off to the same `.interrupted` machinery a
    /// dropped sessions stream uses (ChatStore's pendingRun reconcile) —
    /// degrading, never spinning and never claiming failure. That hand-off is
    /// what buys the long budget: nothing is lost by waiting, and the answer
    /// stays recoverable afterwards either way (status TTL is an hour). This
    /// is also what bounds the pathological cases the poll can otherwise meet
    /// forever: a run parked in `waiting_for_approval`, or a host that answers
    /// `running` for a run nobody will ever finish. 120s clears any turn worth
    /// waiting inline for.
    /// Var, not let: the suite shortens it. // harness-visible
    var runsPollBudget: Duration = .seconds(120)

    /// #283 slice 3A: the **SYNC** turn's budget — `syncTurnViaRuns` only.
    ///
    /// Deliberately NOT `runsPollBudget`. `send(...)` is a non-stream call
    /// with a user waiting on a single answer and no `.interrupted` machinery
    /// to hand off to, so it lives under the #145 Part A policy for
    /// everything that is not a stream (`interactiveRequestTimeout` = 20s,
    /// `requestTimeout(forAccept:)`). The sessions sync path it replaces was
    /// already capped there — its one `POST /chat` carried that 20s stamp —
    /// so **20s is parity, not a new restriction**; the runs path just has to
    /// state the ceiling itself, since submit-then-poll is many short requests
    /// rather than one long one and no per-request timeout can bound it.
    ///
    /// Expiring is not the end of the run: the submit was accepted, so the
    /// answer keeps being produced and stays readable for the status TTL (1h).
    /// The throw says so rather than implying the turn was lost.
    /// Var, not let: the suite shortens it. // harness-visible
    var runsSyncBudget: Duration = .seconds(20)

    /// #283 Task 7: the run `POST /v1/runs/{id}/stop` addresses. Set the
    /// moment a submit succeeds (`streamTurnViaRuns` / `syncTurnViaRuns`),
    /// cleared on that same turn's terminal exit — so a stop request always
    /// targets the run actually in flight, or finds nothing and no-ops.
    /// `private(set)`: only `setActiveRunContext`/`clearActiveRunContext`
    /// below may write it; everyone else (the router, `hardStopActiveRun`'s
    /// own callers) reads.
    /// #285: carries the turn's frozen `endpoint` too, so a stop issued
    /// after a mid-turn profile switch still addresses the host the run
    /// actually lives on.
    /// #304 (superseding this doc's old "and a future `/approval`" promise):
    /// the approval answer deliberately does NOT read this slot — it is
    /// SINGLE and cleared on terminal exit, so a card answered even a beat
    /// after the driver returned would address nothing. `answerApproval`
    /// rides the `RunApprovalRequest` VALUE's own frozen run id + endpoint
    /// instead (dispatch §9 trap 1).
    private(set) var activeRunContext: (runID: String, profileID: UUID?, endpoint: ResolvedEndpoint)?

    /// #283 Task 7: run ids WE told the host to stop. A late `run.cancelled`
    /// frame or a polled `cancelled` status for one of these is the
    /// self-initiated stop completing, not someone else's cancel, and must
    /// end the turn SILENTLY (no `.interrupted`). Populated by
    /// `hardStopActiveRun()`, drained (checked-and-removed) by the runs
    /// driver's terminal handling for that same id.
    ///
    /// **#293(c): the drain is not guaranteed, so the BOUND is enforced by
    /// the code rather than asserted in prose.** This doc used to promise
    /// the set "never grows past the handful of runs actually in flight" —
    /// true while the insert happened at the stop request, but the #279
    /// review fix moved it to AFTER the `/stop` POST returns (so a POST that
    /// never reached the host cannot silence a run). An insert can therefore
    /// land after the driver's last drain with nothing left to remove it.
    /// Run ids are server-unique, so a stale flag can never silence a
    /// different run — what was actually broken was a comment asserting an
    /// invariant the code no longer held. A bounded insertion-ordered list
    /// makes it hold again: oldest evicted first, so the live runs are
    /// always the survivors.
    private(set) var selfStoppedRunIDs: [String] = []

    /// #293(c): "a handful", stated as a number. Comfortably more than the
    /// runs that can be in flight at once (this client drives one turn at a
    /// time) and small enough that an undrained entry costs nothing.
    static let selfStoppedRunIDLimit = 8

    // runs-path-visible (#283): the only mutators for the two properties
    // above. Both are declared here because Swift extensions cannot add
    // stored properties, but every call site is in
    // `SessionsHermesClient+RunsTransport.swift` — a different file — so
    // these narrow methods are the seam that lets the driver write them
    // while keeping the properties themselves `private(set)`.
    func setActiveRunContext(runID: String, profileID: UUID?, endpoint: ResolvedEndpoint) {
        activeRunContext = (runID, profileID, endpoint)
    }

    /// No-ops if `activeRunContext` no longer names `matchingRunID` — either
    /// it was already cleared (e.g. `hardStopActiveRun()` beat this to it) or
    /// it belongs to a different, later run. Either way there is nothing
    /// harmful to do: never clears a context this call didn't own.
    func clearActiveRunContext(matchingRunID: String) {
        guard activeRunContext?.runID == matchingRunID else { return }
        activeRunContext = nil
    }

    func markSelfStopped(runID: String) {
        guard !selfStoppedRunIDs.contains(runID) else { return }
        selfStoppedRunIDs.append(runID)
        // #293(c): evict oldest-first. An entry only survives here because
        // its own driver never drained it, so the oldest is by construction
        // the one least likely to still be owed a terminal.
        if selfStoppedRunIDs.count > Self.selfStoppedRunIDLimit {
            selfStoppedRunIDs.removeFirst(selfStoppedRunIDs.count - Self.selfStoppedRunIDLimit)
        }
    }

    /// Checks membership AND removes in one step — the terminal frame/poll
    /// arm that calls this consumes the flag exactly once.
    func consumeSelfStopped(runID: String) -> Bool {
        guard let index = selfStoppedRunIDs.firstIndex(of: runID) else { return false }
        selfStoppedRunIDs.remove(at: index)
        return true
    }

    /// The durable journal (shared with ChatStore via AppContainer). Owns the
    /// conversation's identity and the active hop handle; this client only
    /// ever reads the handle and begins/ends hops.
    private let journal: ConversationJournalStore
    /// Composes the priming turn a fresh hop is transplanted with.
    private let transplanter: ContextTransplanter
    /// Lane M (#114): the backend profile new server sessions are born on —
    /// stamped onto the hop and the session→profile index at creation, since
    /// session ids are server-scoped. Nil in profile-less constructions.
    private let activeProfileIDProvider: @MainActor () -> UUID?
    /// Lane M: the durable session→birth-profile index. Optional so tests
    /// (and the mock path) run without one.
    private let profileIndex: SessionProfileIndexStore?
    /// #25: the durable session→last-run-usage index — written whenever a
    /// `run.completed` delivers usage, read back on `openSession` so a
    /// resumed session's CTX gauge has a numerator (the stored-messages
    /// endpoint carries none). Optional like `profileIndex`.
    // runs-path-visible (#283): the runs `run.completed` records usage the
    // same way the sessions one does.
    let usageIndex: SessionUsageIndexStore?
    /// Lane M PR 2 (M-5): resolves a NON-ACTIVE profile's chat endpoint
    /// (gateway base URL + that profile's API key). Requests for the active
    /// profile keep riding `baseURLProvider`/`apiKeyProvider` — byte-identical
    /// to the single-backend path. Returning nil means the profile has no
    /// usable endpoint (unknown id, no key cached yet).
    private let profileEndpointResolver: @MainActor (UUID) -> (baseURL: String, apiKey: String)?
    /// Lane M PR 2: every profile chat should list sessions from (M-5's
    /// "drawer shows all sessions"). Empty = single-backend behavior.
    private let chatProfilesProvider: @MainActor () -> [BackendProfile]
    /// Lane M (M-16): when set, the NEXT fresh hop is created on this profile
    /// instead of the active one — "new chat on <profile>" without flipping
    /// the default. Consumed when the hop is successfully created; a failed
    /// creation keeps it armed so the user's pick survives a retry.
    var pendingNewSessionProfileID: UUID?

    init(
        baseURLProvider: @escaping @MainActor () -> String?,
        apiKeyProvider: @escaping @MainActor () -> String?,
        journal: ConversationJournalStore,
        transplanter: ContextTransplanter,
        // #145 Part A: NOT `.shared` — its `timeoutIntervalForResource` is 7 days.
        session: URLSession = SessionsHermesClient.makeChatPlaneSession(),
        activeProfileIDProvider: @escaping @MainActor () -> UUID? = { nil },
        profileIndex: SessionProfileIndexStore? = nil,
        usageIndex: SessionUsageIndexStore? = nil,
        profileEndpointResolver: @escaping @MainActor (UUID) -> (baseURL: String, apiKey: String)? = { _ in nil },
        chatProfilesProvider: @escaping @MainActor () -> [BackendProfile] = { [] }
    ) {
        self.baseURLProvider = baseURLProvider
        self.apiKeyProvider = apiKeyProvider
        self.journal = journal
        self.transplanter = transplanter
        self.session = session
        self.activeProfileIDProvider = activeProfileIDProvider
        self.profileIndex = profileIndex
        self.usageIndex = usageIndex
        self.profileEndpointResolver = profileEndpointResolver
        self.chatProfilesProvider = chatProfilesProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// #223 Lane 5: the active profile's model pick, set by AppContainer on
    /// profile switch and by the picker on apply. Nil = no pick — turns carry
    /// no model fields and the host default rules. Read at body-build time by
    /// all three turn paths (sync, stream, priming).
    var modelSelection: ModelSelection?

    /// Normalizes a routing profile id for request building: the ACTIVE
    /// profile (and profile-less nil) collapse to nil so those requests take
    /// the pre-Lane-M provider path exactly.
    private func requestProfileID(_ profileID: UUID?) -> UUID? {
        guard let profileID, profileID != activeProfileIDProvider() else { return nil }
        return profileID
    }

    // MARK: - HermesClientProtocol

    func connect() async {
        connectionStatus = .connecting
        do {
            let _: ModelsResponse = try await getJSON(path: Self.modelsPath)
            connectionStatus = .connected
        } catch {
            Self.logger.warning("Sessions API /v1/models failed: \(error.localizedDescription)")
            connectionStatus = .error
        }
    }

    func disconnect() async {
        // Deliberately does NOT end the hop: the handle is durable across
        // connection state (and relaunches) so a still-live server session
        // can be resumed without re-priming. Staleness is handled at send
        // time (404 → fresh transplanted hop).
        connectionStatus = .disconnected
    }

    func send(
        message: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) async -> Message {
        do {
            let content = try await performSyncTurn(message: message, attachments: attachments)
            connectionStatus = .connected
            return Message(
                sender: .hermes,
                content: content,
                status: .delivered
            )
        } catch {
            connectionStatus = .error
            return Message(
                sender: .system,
                content: failureMessage(for: error),
                status: .failed
            )
        }
    }

    /// One sync chat turn against the active hop, with the stale-hop retry: a
    /// persisted hop whose server session expired 404s — swap the handle and
    /// retry ONCE on a fresh, transplanted hop. Only a REUSED hop retries; a
    /// just-created session 404ing is a real server problem.
    private func performSyncTurn(message: String, attachments: [PendingAttachment]) async throws -> String {
        // #382: the runs plane is the ONLY turn transport — the sessions-plane
        // sync POST and the Developer switch that could select it are deleted
        // (restore recipe in OPEN_ITEMS #382 if a migration bridge is ever
        // needed). The stale-hop 404 retry survives unchanged: it was always
        // one mechanism, not one per transport.
        let hop = try await ensureHopForTurn()
        do {
            return try await syncTurnViaRuns(hop: hop, message: message, attachments: attachments)
        } catch SessionsClientError.sessionNotFound where hop.wasReused {
            Self.logger.notice("sync turn: persisted hop stale server-side (404) — re-hopping with transplant")
            discardStaleHop()
            let fresh = try await ensureHopForTurn()
            return try await syncTurnViaRuns(hop: fresh, message: message, attachments: attachments)
        }
    }

    /// The stale-hop swap every turn path makes when a persisted hop's server
    /// session has expired: drop the dead handle — it is a handle, not the
    /// conversation's identity — so the next `ensureHopForTurn()` creates a
    /// fresh, transplanted one.
    // runs-path-visible (#283): the runs driver's history pre-fetch is the one
    // session-scoped request a runs turn makes, so it meets the same 404.
    func discardStaleHop() {
        journal.endHop()
    }

    func sendStreaming(
        message content: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) -> AsyncStream<StreamingUpdate> {
        AsyncStream { continuation in
            let producer = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.yield(.failed("Client deallocated"))
                    continuation.finish()
                    return
                }
                // #382: the runs plane is the only turn transport — the
                // sessions-plane stream driver and the switch that could
                // select it are deleted. ChatStore still never learns which
                // plane served a turn; there is now exactly one.
                await self.streamTurnViaRuns(
                    message: content,
                    attachments: attachments,
                    into: continuation
                )
                continuation.finish()
            }
            // #292: the consumer walking away (stop button, thread switch,
            // backgrounding — anything that cancels ChatStore's streaming
            // task) terminates this stream. Without this hook, the producer
            // ran on with Task.isCancelled == false for its whole life — on
            // the runs plane that meant up to ~60 authenticated
            // GET /v1/runs/{id} polls over the 120s budget for a turn nobody
            // was watching. Same shape as ChatBackendRouter's #192 hook, one
            // layer down. Three cancellation checks in +RunsTransport.swift
            // (the events-loop break, and pollRunToTerminal's top-of-loop
            // check and sleep catch) are this hook's customers — they were
            // unreachable from a walk-away until it existed.
            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    /// #246: thrown by the stall guard when the byte stream goes silent past
    /// the threshold. Reaching the stream driver's catch (`streamTurnViaRuns`,
    /// +RunsTransport) with `responseReceived` true (always, post-2xx by
    /// construction) classifies it `.interrupted`.
    struct StreamStallError: Error {}

    /// #246: wraps a line sequence so that prolonged SILENCE throws instead
    /// of blocking forever. A pump task owns the base iterator and forwards
    /// lines, stamping a shared clock; a watchdog task checks the clock and
    /// fails the stream when it goes stale. The suspension case falls out
    /// for free: while the app is suspended neither task runs, and on resume
    /// the watchdog's next check sees the stale clock and throws — which is
    /// exactly the backgrounded-zombie shape that filed this item.
    nonisolated static func stallGuardedLines<S: AsyncSequence & Sendable>(
        _ base: S,
        threshold: Duration
    ) -> AsyncThrowingStream<String, Error> where S.Element == String {
        AsyncThrowingStream { continuation in
            let lastActivity = OSAllocatedUnfairLock(initialState: ContinuousClock.now)
            let pump = Task {
                do {
                    for try await line in base {
                        lastActivity.withLock { $0 = ContinuousClock.now }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let checkEvery = max(threshold / 4, .milliseconds(50))
            let watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: checkEvery)
                    if Task.isCancelled { break }
                    let last = lastActivity.withLock { $0 }
                    if ContinuousClock.now - last > threshold {
                        continuation.finish(throwing: StreamStallError())
                        break
                    }
                }
            }
            continuation.onTermination = { _ in
                pump.cancel()
                watchdog.cancel()
            }
        }
    }

    func loadConversation() async -> Conversation {
        if let currentConversation { return currentConversation }
        let fresh = Conversation(title: Conversation.defaultTitle)
        currentConversation = fresh
        return fresh
    }

    /// Re-fetches the active hop's messages from the host so an interrupted
    /// run can be reconciled. A pure fetch — unlike `openSession`, the journal
    /// is NOT re-adopted here (this is the same thread, not a switch;
    /// ChatStore's post-reconcile sync records the settled exchange).
    func reconcileFromServer() async -> Conversation? {
        guard let hop = journal.activeHop else { return nil }
        // M-5: reconcile against the hop's BIRTH host, not the active one —
        // a run left pending on OJAMD must still resolve after switching to
        // the Mac.
        guard let (_, convo) = try? await fetchSessionConversation(hop.apiSessionId, profileID: hop.profileID) else { return nil }
        currentConversation = convo
        connectionStatus = .connected
        return convo
    }

    /// #295: this client IS the Hermes plane by construction — any run it
    /// has active is always server-recoverable via `reconcileFromServer()`
    /// above. `ChatBackendRouter` overrides the same requirement to check
    /// which brain currently holds its routing lock; this override is what
    /// makes a raw `SessionsHermesClient` wired directly (bypassing the
    /// router — some tests do this) still answer correctly rather than
    /// falling through to the protocol's conservative `false` default.
    var currentRunIsServerRecoverable: Bool { true }

    /// #78: adopt a consumer-side truncation. `currentConversation` here is a
    /// FETCH CACHE — the last thing this client read from the host — and
    /// ChatStore treats it as an authoritative refresh source, so a stale
    /// copy re-imports the rows the user just removed.
    ///
    /// **Honest limit, and it is a real one:** this fixes our mirror, not the
    /// host. The gateway session still holds every turn, so the agent's own
    /// context is unchanged (the documented `/retry` caveat) and any path
    /// that RE-FETCHES the server transcript — `openSession`,
    /// `reconcileFromServer` — legitimately re-imports it. On the Hermes
    /// path a truncation survives merges and relaunch; it does not survive
    /// reopening the session from the drawer.
    func adoptTruncatedConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }

    func clearConversation() async throws -> Conversation {
        // The hop dies with the thread; the journal's identity reset happens
        // in ChatStore, which knows which fresh conversation was adopted
        // (this client's or the local brain's, per the router).
        journal.endHop()
        let fresh = Conversation(title: Conversation.defaultTitle)
        currentConversation = fresh
        return fresh
    }

    // MARK: - Model controls

    /// Lists switchable model identifiers from the host's /api/model/options.
    /// #223 Lane 5: the full provider catalog for the picker — auth state,
    /// setup warnings, pricing, and the host's current default pair. Same
    /// route `availableModels()` flattens, decoded whole.
    func fetchModelCatalog() async throws -> GatewayModelCatalog {
        try await getJSON(path: Self.modelOptionsPath)
    }

    func availableModels() async throws -> [String] {
        // The OpenAI-compatible /v1/models endpoint reports only the Hermes
        // agent itself as a single pseudo-model ("hermes-agent"). The real list
        // of switchable models lives at /api/model/options (provider-grouped —
        // the same source `hermes model` uses). Flatten the authenticated
        // providers' models into a de-duplicated, ordered id list.
        let response: ModelOptionsResponse = try await getJSON(path: Self.modelOptionsPath)
        var ids: [String] = []
        var seen = Set<String>()
        for provider in response.providers where provider.authenticated == true {
            for model in provider.models ?? [] where !model.isEmpty {
                if seen.insert(model).inserted { ids.append(model) }
            }
        }
        return ids
    }

    // MARK: - Session lifecycle


    // MARK: - Sessions list / open

    func listSessions() async throws -> [HermesSessionInfo] {
        let profiles = chatProfilesProvider()

        // Single-backend path (profile-less constructions, or exactly one
        // profile): one fetch, server order preserved — pre-Lane-M behavior.
        guard profiles.count > 1 else {
            let only = profiles.first
            let infos = try await fetchSessionList(profileID: nil, tagAs: only)
            for info in infos { recordBirth(sessionId: info.id, profileID: info.profileID) }
            return infos
        }

        // M-5: the drawer shows ALL profiles' sessions. Fetch each host
        // concurrently and tolerate partial failure — an unreachable host's
        // sessions just don't appear this round (its index entries are kept:
        // pruning only runs on a complete sweep).
        let activeID = activeProfileIDProvider()
        // Build fix (2026-07-16): `withTaskGroup` with @MainActor children
        // trips "pattern that the region-based isolation checker does not
        // understand" on the iOS 27 SDK regardless of capture Sendability
        // (three variants tried). Unstructured Task handles bypass the
        // task-group region machinery: fetches still overlap at the await
        // points, partial failure is still tolerated, error fidelity is
        // preserved, and every handle is awaited before the box is read.
        let gathered = ProfileFetchAccumulator()
        let handles = profiles.map { profile in
            Task { @MainActor [weak self] in
                guard let self else {
                    gathered.failures.append(SessionsClientError.requestFailed("Client deallocated"))
                    return
                }
                do {
                    let requestID = profile.id == activeID ? nil : profile.id
                    let infos = try await self.fetchSessionList(profileID: requestID, tagAs: profile)
                    gathered.lists.append((profile, infos))
                } catch {
                    gathered.failures.append(error)
                    Self.logger.notice("listSessions: '\(profile.name, privacy: .public)' unreachable — \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        for handle in handles {
            await handle.value
        }
        var lists = gathered.lists
        let failures = gathered.failures

        guard !lists.isEmpty else {
            throw failures.first ?? SessionsClientError.requestFailed("No backend profile answered.")
        }

        // Order profile results deterministically (task-group completion
        // order is racy) before the recency merge.
        let profileOrder = Dictionary(uniqueKeysWithValues: profiles.enumerated().map { ($0.element.id, $0.offset) })
        lists.sort { (profileOrder[$0.profile.id] ?? .max) < (profileOrder[$1.profile.id] ?? .max) }

        let merged = Self.mergeSessionLists(lists.map(\.infos))
        for info in merged { recordBirth(sessionId: info.id, profileID: info.profileID) }
        // Deliberately NO index pruning here: the fetch is limit-capped
        // (50/host), so "absent from this sweep" ≠ "gone from the host" —
        // pruning would unbind older sessions that still resolve. Stale
        // entries are cheap and harmless by design.
        return merged
    }

    /// One host's session list, tagged with its profile (M-5).
    private func fetchSessionList(profileID: UUID?, tagAs profile: BackendProfile?) async throws -> [HermesSessionInfo] {
        let path = "\(Self.sessionsPath)?limit=50&order=recent&min_messages=1"
        let request = try makeRequest(path: path, method: "GET", body: nil, accept: "application/json", profileID: profileID)
        let (data, httpResponse) = try await session.data(for: request)
        try ensureSuccess(response: httpResponse, data: data)
        let response: SessionsListResponse
        do {
            response = try decoder.decode(SessionsListResponse.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "(binary)"
            Self.logger.error("listSessions: decode FAILED — \(error.localizedDescription, privacy: .public). Raw: \(snippet, privacy: .public)")
            throw error
        }
        Self.logger.verbose("listSessions: decoded \(response.data.count) rows for '\(profile?.name ?? "active")'")
        return response.data.map { row in
            HermesSessionInfo(
                id: row.id,
                title: row.title,
                preview: row.preview,
                model: row.model,
                source: row.source,
                messageCount: row.messageCount ?? 0,
                lastActive: row.lastActive.map { Date(timeIntervalSince1970: $0) },
                isActive: row.isActive ?? false,
                profileID: profile?.id,
                profileName: profile?.name,
                usage: row.usage
            )
        }
    }

    /// Recency merge for multi-host lists (M-5): rows interleave by
    /// `lastActive` (newest first, unknown-recency rows last), and rows with
    /// equal timestamps keep their input order. A single list passes through
    /// untouched. Static + nonisolated so tests drive it directly.
    nonisolated static func mergeSessionLists(_ lists: [[HermesSessionInfo]]) -> [HermesSessionInfo] {
        guard lists.count > 1 else { return lists.first ?? [] }
        let combined = lists.flatMap { $0 }
        // Stable sort: decorate with the input offset.
        return combined.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.lastActive, rhs.element.lastActive) {
                case let (l?, r?):
                    if l != r { return l > r }
                    return lhs.offset < rhs.offset
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// Adopts `id` as the active session and returns its full history. The
    /// journal rebuilds under the new conversation's identity with the
    /// session as an already-current hop (its history IS its context —
    /// nothing to transplant). New messages then continue that thread (see
    /// ensureHopForTurn()).
    func openSession(_ id: String) async throws -> Conversation {
        // M-5: the session's history lives on its BIRTH host — resolve the
        // endpoint from the index (unrecorded ids are pre-profile sessions,
        // which belong to the active/migrated profile).
        let birthProfileID = profileIndex?.profileID(forSessionID: id) ?? activeProfileIDProvider()
        let (sessionId, fetched) = try await fetchSessionConversation(id, profileID: birthProfileID)
        var convo = fetched
        // #25: the stored transcript carries no usage of any kind (probe
        // 2026-07-16: per-row `token_count` is always null, and the session
        // list's `input_tokens` is cumulative billing, not occupancy — see
        // SessionUsageIndex). The resumed session's CTX numerator is the
        // cached usage from its last live `run.completed`, or honestly
        // absent (nil hides the gauge; it must never render 0%). Deliberately
        // NOT applied in reconcileFromServer: the reconcile path stamps
        // `latestUsage` onto the recovered reply's receipt, and the cache
        // holds the PREVIOUS run's numbers there — a wrong receipt.
        convo.latestUsage = usageIndex?.usage(forSessionID: sessionId)
        currentConversation = convo
        connectionStatus = .connected
        journal.adoptServerSession(id: sessionId, conversation: convo, profileID: birthProfileID)
        recordBirth(sessionId: sessionId, profileID: birthProfileID)
        return convo
    }

    /// GET + decode + map of one session's history — shared by `openSession`
    /// (which adopts it) and `reconcileFromServer` (which must not).
    // runs-path-visible (#283): the runs history pre-fetch reads server truth
    // through this same GET (N4 — runs WRITE the transcript but never read it).
    // #285: the runs pre-fetch passes the turn's frozen `endpoint`;
    // sessions-plane callers omit it and resolve live per request, as before.
    func fetchSessionConversation(_ id: String, profileID: UUID?, endpoint: ResolvedEndpoint? = nil) async throws -> (sessionId: String, conversation: Conversation) {
        let path = "\(Self.sessionsPath)/\(id)/messages"
        let request = try makeRequest(path: path, method: "GET", body: nil, accept: "application/json", profileID: profileID, endpoint: endpoint)
        let (data, httpResponse) = try await session.data(for: request)
        try ensureSuccess(response: httpResponse, data: data, path: path)
        let response: SessionMessagesResponse
        do {
            response = try decoder.decode(SessionMessagesResponse.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "(binary)"
            Self.logger.error("openSession: decode FAILED for '\(id, privacy: .public)' — \(error.localizedDescription, privacy: .public). Raw: \(snippet, privacy: .public)")
            throw error
        }
        Self.logger.verbose("openSession: decoded \(response.data.count) messages for '\(id)'")
        let messages = response.data.compactMap { Self.mapStoredMessage($0, sessionId: id) }
        let convo = Conversation(
            title: Conversation.defaultTitle,
            messages: messages,
            lastActivity: messages.last?.timestamp ?? .now
        )
        return (response.sessionId ?? id, convo)
    }

    nonisolated static func mapStoredMessage(_ m: SessionMessagesResponse.StoredMessage, sessionId: String) -> Message? {   // harness-visible (#364)
        let sender: MessageSender
        switch (m.role ?? "").lowercased() {
        case "user": sender = .user
        case "assistant": sender = .hermes
        default: return nil   // skip system / tool / other roles
        }
        let text = (m.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ts = m.timestamp.map { Date(timeIntervalSince1970: $0) } ?? .now

        // #10: restore the tool timeline when the API includes tool_calls on
        // an assistant row. The stored transcript carries no position data, so
        // reloaded chips anchor at the head of the message (offset 0).
        //
        // #364: the server ALSO stores each call's full `arguments` (verified
        // 0.20.3, both lanes), so a write tool's Tier-1 chip is rebuilt right
        // here from the server's own record — verbatim content, never
        // invention — and the activity detail gets the path, which is what
        // lets the #362 mirror correlator match a refetched row. Rows whose
        // calls carry no/unparseable arguments map exactly as pre-#364.
        var activities: [ToolActivity] = []
        var attachments: [MessageAttachment] = []
        if sender == .hermes {
            for call in m.toolCalls {
                guard let name = call.name, !name.isEmpty, name != "_thinking" else { continue }
                var detail = call.detail
                if Self.isWrittenFileTool(name),
                   let raw = call.arguments,
                   let args = try? JSONDecoder().decode(WrittenFileArgs.self, from: Data(raw.utf8)),
                   let path = args.path, !path.isEmpty {
                    if detail == nil || detail?.isEmpty == true { detail = path }
                    if let content = args.content,
                       var staged = MessageAttachment.agentFile(remotePath: path, content: content) {
                        if let rowID = m.id {
                            staged = MessageAttachment(
                                id: Self.stableAgentFileAttachmentID(
                                    sessionId: sessionId, serverRowID: rowID, path: path
                                ),
                                kind: staged.kind,
                                fileName: staged.fileName,
                                mimeType: staged.mimeType,
                                localStoragePath: staged.localStoragePath
                            )
                        }
                        attachments.append(staged)
                    }
                }
                // #371: this rebuild is the one site that mints activities
                // the app never watched finish — the transcript carries no
                // per-call outcome, so `isActive: false` here is a DEFAULT,
                // not an observation. Stamp the provenance so the chip can
                // say "completed while away" instead of wearing the
                // witnessed checkmark.
                activities.append(ToolActivity(label: name, startedAt: ts, isActive: false, detail: detail, provenance: .reconstructed))
            }
        }

        // #121: restore the reasoning pane on resume. The stored transcript
        // carries the same reasoning the live `run.completed` path adopts
        // (#60) — attach it to the same `Message.reasoning` field so the
        // existing disclosure renders with no UI change. Only assistant rows
        // reason; user rows never carry it.
        let reasoning = sender == .hermes ? storedReasoning(m, content: text) : nil

        // An assistant row can be tool-calls-only (the text lands on a later
        // row) — keep it so the chips survive history reload.
        guard !text.isEmpty || !activities.isEmpty else { return nil }
        // #237: a re-fetch must reproduce the SAME id, or the merge's
        // unconfirmed-locals preserve treats every previously-adopted row as
        // new and unions the whole prior transcript (the 32→128 quadrupling).
        // Rows without a server id keep the fresh-UUID fallback, honestly.
        let stableID = m.id.map { Self.stableMessageID(sessionId: sessionId, serverRowID: $0) }
        return Message(
            id: stableID ?? UUID(),
            sender: sender,
            content: text,
            timestamp: ts,
            status: .delivered,
            toolActivities: activities,
            reasoning: reasoning,
            attachments: attachments
        )
    }

    /// #364: the write tools whose stored/streamed args carry a
    /// reconstructable `{path, content}` — the same pair `parseWrittenFile`
    /// accepts on the live stream.
    nonisolated static func isWrittenFileTool(_ name: String) -> Bool {
        name == "write_file" || name == "create_file"
    }

    /// #364: deterministic attachment identity for a chip rebuilt from a
    /// stored row's args — the #237 pattern with its own domain, keyed by
    /// session, row, and path, so every refetch of the same write maps to
    /// the same UUID and the sidecar replay's id-dedupe holds across
    /// refetches. Rows without a server id fall back to a fresh UUID,
    /// matching `stableMessageID`'s posture.
    nonisolated static func stableAgentFileAttachmentID(sessionId: String, serverRowID: Int, path: String) -> UUID {
        let digest = SHA256.hash(data: Data("talaria-agentfile:\(sessionId):\(serverRowID):\(path)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// #237: deterministic message identity from the server's own row id —
    /// SHA-256 over a domain-separated key, truncated to 16 bytes with
    /// RFC-4122 version/variant bits, so every fetch of the same row maps to
    /// the same UUID. App-side only; the server contract is untouched.
    nonisolated static func stableMessageID(sessionId: String, serverRowID: Int) -> UUID {
        let digest = SHA256.hash(data: Data("talaria-msg:\(sessionId):\(serverRowID)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// #368 (3E): deterministic identity for a reply adopted from a RUN
    /// STATUS read — the #237 pattern with its own domain, keyed by the run
    /// id (globally unique, and the only stable handle a status read gives
    /// us; the recovered answer has no server ROW id to key on, which is
    /// exactly why the sessions reconcile had to guess positionally).
    ///
    /// Determinism is what makes the adoption idempotent: two recovery passes
    /// racing the same terminal status produce the SAME id, so the second
    /// merges instead of duplicating — #237's shape, prevented rather than
    /// cleaned up after.
    nonisolated static func stableRecoveredRunMessageID(runID: String) -> UUID {
        let digest = SHA256.hash(data: Data("talaria-run:\(runID)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The reasoning to restore for a resumed assistant row, or nil (#121).
    /// Prefers `reasoning_content` (the live channel's key, matching
    /// `decodeRunReasoning`'s per-entry preference), falling back to
    /// `reasoning` only when the primary is blank/absent. Applies the #60
    /// answer-mirror guard to the chosen value: the defective upstream
    /// `_thinking` channel historically stored the ANSWER under reasoning, so
    /// a row whose reasoning just restates its own content is dropped — a
    /// restored pane parroting its answer is the exact #60 regression. A
    /// mirror does NOT fall back to the other key: both keys are duplicates on
    /// the wire, so the fallback would be the same mirror.
    nonisolated private static func storedReasoning(_ m: SessionMessagesResponse.StoredMessage, content: String) -> String? {
        let chosen: String?
        if let primary = m.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !primary.isEmpty {
            chosen = primary
        } else if let fallback = m.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !fallback.isEmpty {
            chosen = fallback
        } else {
            chosen = nil
        }
        guard let reasoning = chosen else { return nil }
        return reasoningMirrorsAnswer(reasoning, content: content) ? nil : reasoning
    }

    // MARK: - Hop lifecycle (P1 / OPEN_ITEMS #90)

    /// A server session ready to carry the next turn.
    // runs-path-visible (#283): both turn drivers take a hop.
    struct PreparedHop {
        let sessionId: String
        /// True when this call reused a persisted hop — whose server session
        /// may have expired; the 404 stale-hop retry applies only then.
        let wasReused: Bool
        /// Set when this call created a fresh hop AND transplanted journal
        /// context into it. Nil for continued hops and for fresh hops on an
        /// empty journal (nothing to transplant).
        let priming: PrimingReceipt?
        /// The hop's birth profile (M-5) — every request on this hop resolves
        /// its endpoint from it, never from the active profile.
        let profileID: UUID?
    }

    /// The transplant's cost, for the receipts (#46/#90). `usage` is the
    /// priming turn's real `run.completed` usage — nil when the server
    /// reported none (real data only, never estimated).
    struct PrimingReceipt: Sendable {
        let usage: TokenUsage?
    }

    /// The P1 replacement for the old single-session `ensureSession()`.
    /// Reuses the active hop while it is current; otherwise creates a FRESH
    /// server session and, when the journal carries history, transplants
    /// condensed context into it as turn zero. A hop goes stale when journal
    /// entries land that its server session never saw — local-brain turns,
    /// voice transcripts — or when no hop exists at all (first launch, after
    /// a model switch, after a 404 on an expired session).
    ///
    /// If the priming turn fails, no hop is recorded: the just-created server
    /// session is abandoned and the next attempt re-creates and re-primes —
    /// a little server-side litter, never a silently unprimed session.
    // runs-path-visible (#283): hop preparation (including the transplant
    // priming turn, which stays on the SESSIONS plane in 3A) is shared.
    func ensureHopForTurn() async throws -> PreparedHop {
        if let hop = journal.activeHop, journal.activeHopIsCurrent {
            return PreparedHop(sessionId: hop.apiSessionId, wasReused: true, priming: nil, profileID: hop.profileID)
        }

        // M-6/M-16: fresh hops are born on the active profile, unless a
        // "new chat on <profile>" pick armed an override. The override is
        // consumed only once the hop actually exists — a failed creation
        // keeps it armed for the retry.
        let targetProfileID = pendingNewSessionProfileID ?? activeProfileIDProvider()
        let sessionId = try await createBareSession(profileID: targetProfileID)
        if currentConversation == nil {
            currentConversation = Conversation(title: Conversation.defaultTitle)
        }

        guard journal.hasEntries else {
            journal.beginHop(apiSessionId: sessionId, primingUsage: nil, profileID: targetProfileID)
            recordBirth(sessionId: sessionId, profileID: targetProfileID)
            pendingNewSessionProfileID = nil
            return PreparedHop(sessionId: sessionId, wasReused: false, priming: nil, profileID: targetProfileID)
        }

        let composition = await transplanter.composePriming(from: journal.entries)
        let usage = try await postPrimingTurn(sessionId: sessionId, profileID: targetProfileID, text: composition.text)
        // #25: the priming turn IS the fresh session's context occupancy —
        // seed the resume cache so a session abandoned right after its
        // transplant still reads honestly when reopened.
        if let usage {
            usageIndex?.record(sessionID: sessionId, usage: usage)
        }
        journal.beginHop(apiSessionId: sessionId, primingUsage: usage, profileID: targetProfileID)
        recordBirth(sessionId: sessionId, profileID: targetProfileID)
        pendingNewSessionProfileID = nil
        Self.logger.notice("hop: fresh session primed from \(composition.entryCount) journal entries (\(composition.condensedByModel ? "condensed" : "verbatim tail", privacy: .public), \(usage?.totalTokens ?? 0) tokens)")
        return PreparedHop(sessionId: sessionId, wasReused: false, priming: PrimingReceipt(usage: usage), profileID: targetProfileID)
    }

    // MARK: - #241 — session-model immunity

    /// The gateway's own advertised identity on `/v1/models`. It is a ROUTING
    /// SENTINEL meaning *"use the gateway default"*, **not** a model any
    /// provider serves — so it must never leave this client as a model id.
    ///
    /// Upstream persists `model = body.get("model") or self._model_name`
    /// (`api_server.py:3397`), which is why a bare create stores this string
    /// on every session we make. The routing gate then compares the stored
    /// value against the live sentinel (`:2345`): while they match the session
    /// routes to the host default and all is well, but any divergence — the
    /// "API server model name" field, a profile rename, a different host —
    /// turns the stored alias into a request for a nonexistent model, a
    /// non-retryable 404 that reaches the client as HTTP 200.
    nonisolated static let gatewaySelfAlias = "hermes-agent"

    /// The one choke point every model id passes through before it can reach a
    /// create or pin body (#241 bar 241-D). Returns a trimmed, non-empty id,
    /// or nil when there is nothing safe to send — and nil always degrades to
    /// today's bare body rather than blocking anything.
    ///
    /// The alias match is EXACT (case-insensitively), not a substring test: a
    /// real model genuinely named `vendor/hermes-agent-v2` must still be
    /// sendable. It is the sentinel itself that is unroutable, not the letters.
    nonisolated static func wireSafeModelID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare(gatewaySelfAlias) != .orderedSame
        else { return nil }
        return trimmed
    }

    /// The create body. A nil `model` encodes to `{}` — the synthesized
    /// `Encodable` omits nil optionals — so the degraded path stays
    /// byte-identical to the pre-#241 `EmptyBody()` shape.
    ///
    /// **Deliberately carries NO `require_model_lock`.** The lock trio is the
    /// PER-TURN contract (`ChatTurnBody`); sending it here would make the
    /// session's stored `browser_model_lock` *confirmed*, which changes turn
    /// routing to `route_source: "session_model_lock"`. A bare `model` lands at
    /// `api_server.py:3397` and fixes the stored id while leaving that lock
    /// record unconfirmed — and
    /// `_runtime_request_from_persisted_session_lock` returns nil outright for
    /// an unconfirmed lock, so turn semantics are provably untouched.
    private struct CreateSessionBody: Encodable {
        let model: String?
    }

    /// #241: the host's default model id, resolved once per gateway per
    /// process. A present key with a nil VALUE means "probed, nothing usable
    /// came back" — cached so an unreachable or pre-0.20.0 host costs one
    /// probe rather than one per session created.
    ///
    /// Keyed by resolved base URL, not by profile id: the active profile
    /// collapses to a nil `profileID`, so a profile switch would otherwise
    /// read the previous host's default out of the cache.
    private var hostDefaultModelByBaseURL: [String: String?] = [:]

    /// #241 resolution order at session creation:
    /// 1. the profile's own `ModelSelection` — the user's explicit pick;
    /// 2. the host's real default from `/api/model/options` (the catalog's
    ///    top-level pair, e.g. `kimi-coding` / `kimi-k3`);
    /// 3. nil — create bare, exactly as before.
    ///
    /// **Never throws.** Every failure degrades to nil, because a session that
    /// cannot be created is strictly worse than a session that stores the
    /// alias. `/v1/models` is deliberately NOT consulted: it advertises only
    /// the alias, which is the very string this lane exists to keep off the
    /// wire.
    private func resolveCreateModel(profileID: UUID?) async -> String? {
        if let picked = Self.wireSafeModelID(modelSelection?.modelID) { return picked }

        let cacheKey = (try? resolveTurnEndpoint(profileID: profileID))?.baseURL ?? ""
        if let cached = hostDefaultModelByBaseURL[cacheKey] { return cached }

        var resolved: String?
        do {
            let catalog: GatewayModelCatalog = try await getJSON(
                path: Self.modelOptionsPath,
                profileID: profileID
            )
            resolved = Self.wireSafeModelID(catalog.model)
            if resolved == nil {
                Self.logger.notice("#241: host catalog names no usable default model — creating the session bare")
            }
        } catch {
            Self.logger.notice("#241: host catalog unavailable (\(error.localizedDescription, privacy: .public)) — creating the session bare")
        }
        hostDefaultModelByBaseURL[cacheKey] = resolved
        return resolved
    }

    /// POST /api/sessions — a fresh, unprimed server session on the given
    /// profile's gateway. Hop registration and transplanting are the
    /// caller's business.
    ///
    /// #241: no longer bare by default. It sends an explicit `model` so the
    /// gateway cannot fall through to `self._model_name` and persist its own
    /// routing sentinel as this session's model.
    private func createBareSession(profileID: UUID? = nil) async throws -> String {
        let model = await resolveCreateModel(profileID: profileID)
        let response: CreateSessionResponse = try await postJSON(
            path: Self.sessionsPath,
            body: CreateSessionBody(model: model),
            profileID: profileID
        )
        if model == nil {
            // #241 path 3 is RETIRED with #382: this bare create DID inherit
            // the alias, and the first-turn runtime pin that used to replace
            // it died with the sessions turn plane — the runs wire carries no
            // `runtime` block to pin from (documented in +RunsTransport). The
            // exposure is narrow (a catalog-less host AND no selection) and
            // recorded under #241/#382; the primary defense — resolving an
            // explicit wire-safe model into this very body — is unchanged.
            Self.logger.notice("#241: bare create on a catalog-less host — the session keeps the host default (the first-turn pin retired with #382)")
        }
        return response.session.id
    }


    /// Lane M: stamps a session's immutable birth profile into the index.
    private func recordBirth(sessionId: String, profileID: UUID?) {
        guard let profileID else { return }
        profileIndex?.record(sessionID: sessionId, profileID: profileID)
    }

    /// Posts the transplant as the fresh session's first turn and returns the
    /// run's real token usage — the receipts carry real numbers or none (#46).
    ///
    /// #382: rides the runs plane like every other turn (the sessions
    /// `chat/stream` primer was the last turn-submitting sessions call site).
    /// Submit, poll to terminal, read usage off the status object. The
    /// acknowledgment is meta-traffic, not conversation content, so nothing
    /// streams and nothing is shown — and a primer whose answer never lands
    /// within budget (or fails host-side) primes with a nil receipt exactly
    /// as the old drain did when the stream died: the submit was accepted,
    /// so the transplant text IS in the session either way (N4: runs WRITE
    /// the session transcript).
    private func postPrimingTurn(sessionId: String, profileID: UUID?, text: String) async throws -> TokenUsage? {
        let endpoint = try resolveTurnEndpoint(profileID: profileID)
        let submit: RunSubmitResponse = try await postJSON(
            path: Self.runsPath,
            body: RunsTurnBody.make(
                message: text,
                attachments: [],
                sessionID: sessionId,
                // A just-created session has no history — and runs never
                // read it anyway (N4); the transplant text is the payload.
                history: [],
                selection: modelSelection
            ),
            endpoint: endpoint
        )
        guard let snapshot = await pollRunToTerminal(
            runID: submit.runID,
            profileID: profileID,
            endpoint: endpoint,
            budget: runsSyncBudget,
            haltOnApprovalPark: true
        ), snapshot.status == "completed" else { return nil }
        return Self.decodeRunUsage(snapshot.rawJSON)
    }

    // MARK: - HTTP plumbing

    /// #285 (the #283 adjacency): one turn's endpoint, resolved ONCE at turn
    /// start. A runs turn is many requests over up to minutes of wall clock,
    /// each of which used to re-resolve the live providers — so a mid-turn
    /// profile switch could redirect a turn's later polls to the new host.
    /// The turn drivers resolve one of these at birth and every request in
    /// the turn's family carries it.
    struct ResolvedEndpoint: Sendable, Equatable {  // runs-path-visible (#283/#285)
        let baseURL: String
        let apiKey: String
    }

    // runs-path-visible (#283/#285): the turn drivers' one resolution point.
    func resolveTurnEndpoint(profileID: UUID?) throws -> ResolvedEndpoint {
        let resolved = try resolveEndpoint(profileID: requestProfileID(profileID))
        return ResolvedEndpoint(baseURL: resolved.baseURL, apiKey: resolved.apiKey)
    }

    private func getJSON<T: Decodable>(path: String, profileID: UUID? = nil, endpoint: ResolvedEndpoint? = nil) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", body: nil, accept: "application/json", profileID: profileID, endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data, path: path)
        return try decoder.decode(T.self, from: data)
    }

    // runs-path-visible (#283): the runs submit (`POST /v1/runs`) is an
    // ordinary JSON post — same encode/status/decode discipline.
    func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body, profileID: UUID? = nil, endpoint: ResolvedEndpoint? = nil) async throws -> T {
        let encodedBody = try encoder.encode(body)
        let request = try makeRequest(path: path, method: "POST", body: encodedBody, accept: "application/json", profileID: profileID, endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data, path: path)
        return try decoder.decode(T.self, from: data)
    }

    // runs-path-visible (#283): every runs-plane request is built here too, so
    // auth, base-URL normalization and the #145 timeout split stay one policy.
    // #285: a non-nil `endpoint` (the turn's frozen resolution) wins over the
    // live `profileID` path — sessions-plane callers, whose turns are a single
    // request, keep passing `profileID` and resolve at build time as before.
    func makeRequest(path: String, method: String, body: Data?, accept: String, profileID: UUID? = nil, endpoint: ResolvedEndpoint? = nil) throws -> URLRequest {
        let resolved = try endpoint ?? resolveTurnEndpoint(profileID: profileID)
        guard let url = URL(string: normalizedBaseURL(resolved.baseURL) + path) else {
            throw SessionsClientError.notConfigured("Hermes API base URL is not set.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(resolved.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.httpBody = body
        request.timeoutInterval = Self.requestTimeout(forAccept: accept)
        return request
    }

    // MARK: - #235 F1 — the empty clean-close decision

    /// #235 F1: a stream that ends CLEANLY (no thrown error) without
    /// run.completed, on a run that started, with no answer text assembled —
    /// the 9:47 shape. Delivering it as `.finished` produced an empty bubble
    /// and suppressed all recovery; it must arm the same `.interrupted` path
    /// a thrown error takes. Non-empty content keeps the fallback: a partial
    /// streamed answer beats store adoption, which would drop it.
    nonisolated static func cleanCloseArmsRecovery(runStarted: Bool, effectiveContent: String) -> Bool {
        runStarted && effectiveContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - #145 Part A — the chat plane's timeout budget

    /// SSE turns legitimately run for minutes. For a stream
    /// `timeoutIntervalForRequest` is an IDLE gap (time since the last bytes
    /// arrived), not a total duration, so this bounds a *silent* stream without
    /// capping a long one.
    nonisolated static let streamingRequestTimeout: TimeInterval = 300

    /// Everything that is not a stream. A user is watching the foreground
    /// refresh, and eight of these run serially in `handleAppDidBecomeActive` —
    /// at the old 300s each that is most of an hour against a black-holed host.
    ///
    /// **This caps one REQUEST, which stopped being the whole story in #283.**
    /// This 20s policy holds **PER REQUEST, not per `send(...)`.** The
    /// runs-plane sync turn (`syncTurnViaRuns`) answers a `send(...)` with
    /// submit-then-poll — many short requests, each correctly stamped 20s
    /// here — and `runsSyncBudget` (`:89`) bounds only ONE of those legs, the
    /// POLL LOOP inside `pollRunToTerminal`. It does NOT sum the history
    /// pre-fetch GET or the submit POST that precede it; each of those is
    /// independently capped at this same 20s, but nothing adds the three
    /// together. **Worst case for one `send(...)` on the runs plane is
    /// roughly 60–80s** — history GET (20s) + submit POST (20s) + poll
    /// budget (20s, overshootable by one more in-flight 20s read) — against
    /// the sessions `/chat` turn it replaces, which was one request capped
    /// at 20s flat. (Corrected 2026-08-07, review of #279 — the prior text
    /// here claimed this "holds end-to-end," which was false; no behavior
    /// changed, this is a documentation-only fix.) The STREAMED recovery
    /// poll is the deliberate exception and carries `runsPollBudget`
    /// instead, because it degrades to `.interrupted` rather than making a
    /// user wait.
    nonisolated static let interactiveRequestTimeout: TimeInterval = 20

    /// #145 Part A — which budget a request gets.
    ///
    /// `makeRequest` stamped **`timeoutInterval = 300` on EVERY request**, so a
    /// single foreground refresh could hang five minutes and the serial chain
    /// far longer. Part C bounded the reconcile LOOP; **this bounds the CALL,
    /// which is what makes Part C sufficient** — Part C's deadline is only tested
    /// between attempts, so without this one hung fetch outlived it.
    ///
    /// **The trap, and why the split keys off `Accept`:** shortening the
    /// streaming budget would kill live turns and present as a network bug. The
    /// code already distinguishes the two — `text/event-stream` on the two
    /// streaming call sites, `application/json` on the other four — so this reads
    /// a distinction that exists rather than inventing new plumbing that could
    /// drift out of sync with it.
    ///
    /// **Unknown values fall to the SHORT budget deliberately: fail safe, not
    /// fail open.** A future call site that forgets the header gets bounded
    /// rather than silently granted the streaming allowance.
    nonisolated static func requestTimeout(forAccept accept: String) -> TimeInterval {
        accept == "text/event-stream" ? streamingRequestTimeout : interactiveRequestTimeout
    }

    /// #145 Part A — the chat plane's own session.
    ///
    /// The default was `URLSession.shared`, whose `timeoutIntervalForResource` is
    /// **SEVEN DAYS**. That is the knob that makes a wedge effectively permanent:
    /// a request can outlive the outage, the app's patience, and any reasonable
    /// idea of "this failed."
    ///
    /// One session serves both paths because the per-request budget above is the
    /// real discriminator; the resource ceiling here only has to be generous
    /// enough for the longest legitimate SSE run. **One hour, not seven days.**
    ///
    /// Deliberately NOT `RelayAPIClient.makeBootstrapProbeSession()` — that one's
    /// own comment says it must never serve the chat path or SSE streams, and a
    /// 10s resource timeout there would break exactly the runs this preserves.
    nonisolated static func makeChatPlaneSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = interactiveRequestTimeout
        configuration.timeoutIntervalForResource = 3600
        return URLSession(configuration: configuration)
    }

    /// #145 Part A — for the Hermes-plane clients that **never stream**:
    /// the retired models shim (`:8765`, #223 Lane 5), `CronJobService`, `SkillsService`,
    /// `InsightsService`. All four defaulted to `URLSession.shared` — 60s
    /// request over a **7-day** resource ceiling — and
    /// `seedActiveModelFromShim()` puts one of them directly in
    /// `handleAppDidBecomeActive`'s chain, so #145's wedge reached them too.
    ///
    /// **Stricter than `makeChatPlaneSession()` on purpose.** That one carries a
    /// one-hour resource ceiling only because an SSE turn legitimately runs for
    /// minutes. **These four have zero streaming call sites** (verified: no
    /// `text/event-stream`, no `session.bytes(…)` in any of them), so nothing
    /// justifies letting one of their requests live past a minute.
    ///
    /// **One factory, not four copies.** Five clients with five hand-tuned
    /// configs is how a timeout policy drifts until nobody can say what the
    /// budget is. It lives beside `makeChatPlaneSession()` because this file
    /// already owns the plane's timeout policy; if it ever wants its own home
    /// that is a move, not a rewrite.
    nonisolated static func makeInteractiveHermesPlaneSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = interactiveRequestTimeout
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    /// Resolves the gateway a request should hit (M-5). nil = the ACTIVE
    /// profile via the original providers — the pre-Lane-M path, byte for
    /// byte. A non-nil id is a session pinned to a non-active birth profile.
    private func resolveEndpoint(profileID: UUID?) throws -> (baseURL: String, apiKey: String) {
        if let profileID {
            guard let resolved = profileEndpointResolver(profileID) else {
                throw SessionsClientError.notConfigured("This conversation lives on a backend profile with no usable endpoint. Check its gateway URL and API key in Settings → Server.")
            }
            let baseURL = resolved.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let apiKey = resolved.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseURL.isEmpty else {
                throw SessionsClientError.notConfigured("The session's backend profile has no gateway URL set.")
            }
            guard !apiKey.isEmpty else {
                throw SessionsClientError.notConfigured("The session's backend profile has no API key set.")
            }
            return (baseURL, apiKey)
        }
        guard let baseURL = baseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            throw SessionsClientError.notConfigured("Hermes API base URL is not set.")
        }
        guard let apiKey = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw SessionsClientError.notConfigured("Hermes API key is not set.")
        }
        return (baseURL, apiKey)
    }

    private func normalizedBaseURL(_ raw: String) -> String {
        var trimmed = raw
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    private func ensureSuccess(response: URLResponse, data: Data, path: String = "") throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionsClientError.requestFailed("Hermes API returned an invalid response.")
        }
        // A 404 on a session-scoped path means the server session is gone
        // (expired/pruned) — the typed error drives the stale-hop retry
        // (#90). Non-session paths (e.g. /v1/models) keep the generic error.
        if httpResponse.statusCode == 404, path.hasPrefix(Self.sessionsPath + "/") {
            throw SessionsClientError.sessionNotFound
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let bodySnippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw SessionsClientError.requestFailed(
                "Hermes API returned status \(httpResponse.statusCode). \(bodySnippet)"
            )
        }
    }

    /// Transport-level failures where the request DEMONSTRABLY never reached
    /// the Sessions API — the offline compose outbox's queue signal (#90).
    /// Deliberately narrow: queued turns AUTO-RESEND on reachability, so an
    /// ambiguous failure must not qualify. `.timedOut` and
    /// `.networkConnectionLost` can fire after the body reached the server
    /// (the run may have committed) — those stay `.failed`, where a human
    /// decides about the retry. Anything the server actually answered (HTTP
    /// status errors, decode failures) and configuration gaps are also NOT
    /// unreachable: retrying identical bytes later won't fix those.
    nonisolated static func isUnreachableError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    nonisolated private func decodeJSONString(_ raw: String, key: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return dict[key] as? String
        }
        return nil
    }

    /// #4.15: extracts a reasoning delta from a `tool.progress` payload. Only
    /// `tool_name:"_thinking"` events qualify — that's the reasoning channel
    /// (verified Phase 0), never a real tool. The delta text key is read
    /// tolerantly (`delta`/`content`/`text`/`message`/`preview`, then
    /// `args.{delta,content,text}`) — the same shape-drift posture as the
    /// other SSE parsers here. The exact key ships unverified against the live
    /// host (device probe pending — see OPEN_ITEMS #60); the fallback chain
    /// keeps a key drift from silently killing the feature.
    nonisolated static func thinkingDelta(fromToolProgress raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let name = (payload["tool_name"] as? String)
            ?? (payload["name"] as? String)
            ?? (payload["tool"] as? String)
        guard name == "_thinking" else { return nil }
        for key in ["delta", "content", "text", "message", "preview"] {
            if let value = payload[key] as? String, !value.isEmpty { return value }
        }
        if let args = payload["args"] as? [String: Any] {
            for key in ["delta", "content", "text"] {
                if let value = args[key] as? String, !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// #4.15 wire-mode hedge: whether `_thinking` events carry increments or
    /// cumulative snapshots is unverified (same probe as the delta key — see
    /// OPEN_ITEMS #60). A chunk that starts with everything assembled so far
    /// is a snapshot — only its new suffix is the delta. Returns nil when the
    /// chunk adds nothing. In genuine increment mode the prefix compare fails
    /// on the first character, so the hedge is effectively free there.
    nonisolated static func incrementalReasoningDelta(from chunk: String, assembled: String) -> String? {
        guard !chunk.isEmpty else { return nil }
        if !assembled.isEmpty, chunk.hasPrefix(assembled) {
            let suffix = String(chunk.dropFirst(assembled.count))
            return suffix.isEmpty ? nil : suffix
        }
        return chunk
    }

    /// #60 mirror guard: the gateway's `_thinking` channel is defective
    /// upstream — its single cumulative end-of-stream event carries the
    /// assistant ANSWER verbatim, not reasoning. True when `reasoning` is
    /// just the answer text, whitespace-folded so chunk-join artifacts can
    /// never fake a difference. An answer-mirror must never attach as
    /// reasoning; genuinely distinct text (real deltas, the day upstream
    /// fixes the stream) compares different and passes through. Callers
    /// guard for non-empty reasoning first.
    nonisolated static func reasoningMirrorsAnswer(_ reasoning: String, content: String) -> Bool {
        whitespaceFolded(reasoning) == whitespaceFolded(content)
    }

    /// Collapses every whitespace run (spaces, tabs, newlines) to a single
    /// space and trims the ends — the same fold as #110's
    /// `SpeechOutputService.shouldRetractSpeech`, copied so the two mirror
    /// detections can't drift apart.
    private nonisolated static func whitespaceFolded(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// #11: builds a `ToolCallEvent` from a `tool.started` / `tool.completed`
    /// payload (`{tool_name, args:{…}, preview}`). `_thinking` is the reasoning
    /// channel, never a tool call. Returns nil when no tool name is present —
    /// the norm for `tool.completed`, whose payload is empty on the wire today.
    nonisolated private func parseToolCallEvent(_ raw: String, phase: ToolCallEvent.Phase) -> ToolCallEvent? {
        guard let data = raw.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = payload["tool_name"] as? String,
              !name.isEmpty,
              name != "_thinking"
        else { return nil }
        guard phase == .started else {
            return ToolCallEvent(name: name, phase: .completed)
        }
        return ToolCallEvent(name: name, phase: .started, detail: Self.toolCallDetail(from: payload))
    }

    /// Compact single-line input summary for a tool chip (#11): the server's
    /// `preview` when present, else up to three `args` entries with long values
    /// elided so the collapsed chip stays phone-sized.
    nonisolated private static func toolCallDetail(from payload: [String: Any]) -> String? {
        if let preview = payload["preview"] as? String,
           !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preview
        }
        guard let args = payload["args"] as? [String: Any], !args.isEmpty else { return nil }
        // Lead with the params that identify what the call touched.
        let priority = ["path", "file_path", "filename", "command", "query", "url", "pattern"]
        let orderedKeys = args.keys.sorted { a, b in
            let ia = priority.firstIndex(of: a) ?? Int.max
            let ib = priority.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }
        let pairs = orderedKeys.prefix(3).map { "\($0): \(compactArgValue(args[$0] ?? ""))" }
        return pairs.isEmpty ? nil : pairs.joined(separator: " · ")
    }

    nonisolated private static func compactArgValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            if string.count > 80 {
                let bytes = ByteCountFormatter.string(fromByteCount: Int64(string.utf8.count), countStyle: .file)
                return "\(bytes) text"
            }
            return string.replacingOccurrences(of: "\n", with: " ")
        case let number as NSNumber:
            return number.stringValue
        case is [Any]:
            return "[…]"
        case is [String: Any]:
            return "{…}"
        default:
            return String(describing: value)
        }
    }

    /// #21: pulls an agent-written file out of a `tool.started` payload.
    /// Recognizes `write_file` / `create_file`; tolerant of arg-key drift
    /// (`args`/`arguments`/`input`, `path`/`file_path`, `content`/`text`) so a
    /// minor server-shape change doesn't silently drop the attachment.
    /// Content present → Tier 1 stages the bytes now. Content absent (a
    /// binary — the stream never carries its bytes) → a Tier 2 fetchable
    /// attachment, but only when the path sits inside the whitelisted
    /// agent-files dir: the relay would 404 anything else, and the app never
    /// attempts arbitrary host paths. Returns nil for any other tool, when
    /// the path is absent, or for a content-less path outside the whitelist.
    nonisolated static func parseWrittenFile(_ raw: String, profileID: UUID?) -> MessageAttachment? {
        guard let data = raw.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ToolStartedEnvelope.self, from: data)
        else { return nil }
        let tool = (envelope.toolName ?? "").lowercased()
        guard tool == "write_file" || tool == "create_file" else { return nil }
        guard let args = envelope.args,
              let path = args.path, !path.isEmpty
        else { return nil }
        // #375: content present → Tier 1 stages the bytes. Content ABSENT
        // used to mint a Tier 2 "TAP TO DOWNLOAD" chip fetched over the relay;
        // the relay is retired on both hosts and the download was ruled
        // unneeded (Owen, 2026-08-19), so nothing is minted rather than a chip
        // the app cannot honour.
        guard let content = args.content else { return nil }
        return MessageAttachment.agentFile(remotePath: path, content: content)
    }

    // runs-path-visible (#283): one failure-text policy across both planes.
    func failureMessage(for error: Error) -> String {
        if let sessionsError = error as? SessionsClientError {
            return sessionsError.errorDescription ?? "Hermes API request failed."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "Hermes API request failed." : described
    }

    // MARK: - Wire types

    // (#241) `EmptyBody` retired with the bare create — `CreateSessionBody`
    // with a nil `model` encodes to the same `{}` and is the only create body.

    /// Extracts token usage from a `run.completed` SSE payload. Hermes emits
    /// Anthropic-style keys (input/output/total); map onto TokenUsage's
    /// prompt/completion/total. Returns nil if usage is absent or unparseable.
    // runs-path-visible (#283): shared by both planes' run.completed decode
    nonisolated static func decodeRunUsage(_ data: String) -> TokenUsage? {
        guard let raw = data.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RunCompletedEnvelope.self, from: raw),
              let usage = envelope.usage
        else { return nil }
        return TokenUsage(
            promptTokens: usage.inputTokens,
            completionTokens: usage.outputTokens,
            totalTokens: usage.totalTokens
        )
    }

    /// Extracts the model's REAL reasoning from a `run.completed` SSE payload
    /// (#60): the terminal transcript carries it per-message under
    /// `reasoning_content` (and a duplicate `reasoning` key), while the
    /// streamed `_thinking` channel mirrors the answer. On tool-using turns
    /// the transcript is multi-message and the genuine plan CoT rides the
    /// INTERMEDIATE assistant entries (60B), so EVERY assistant entry
    /// contributes: non-blank segments aggregate in transcript order,
    /// blank-line joined — matching Hermes's own web UI, which shows each
    /// reasoning segment across the run. Per entry, `reasoning_content` is
    /// preferred with `reasoning` as the fallback (blank counts as absent —
    /// same shape-drift posture as the other parsers here). Returns nil when
    /// no segment survives or the payload is unparseable.
    nonisolated private func decodeRunReasoning(_ data: String) -> String? {
        guard let raw = data.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RunCompletedEnvelope.self, from: raw),
              let transcript = envelope.messages
        else { return nil }
        var segments: [String] = []
        for entry in transcript where entry.role == "assistant" {
            for candidate in [entry.reasoningContent, entry.reasoning] {
                guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else { continue }
                segments.append(trimmed)
                break
            }
        }
        return segments.isEmpty ? nil : segments.joined(separator: "\n\n")
    }

    /// Extracts the #223 Lane 5 `runtime` block from a `run.completed` SSE
    /// payload. v0.20.0 rides it both top-level and nested under `usage`;
    /// top-level wins, nested is the fallback. Nil on older gateways.
    nonisolated static func decodeTurnRuntime(_ data: String) -> TurnRuntime? {
        guard let raw = data.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RuntimeEnvelope.self, from: raw)
        else { return nil }
        return envelope.runtime ?? envelope.usage?.runtime
    }

    private struct RuntimeEnvelope: Decodable {
        let runtime: TurnRuntime?
        let usage: NestedRuntime?
        struct NestedRuntime: Decodable { let runtime: TurnRuntime? }
    }

    private struct RunCompletedEnvelope: Decodable {
        let usage: RunCompletedUsage?
        let messages: [RunTranscriptMessage]?
    }

    /// One transcript row in the terminal `run.completed` payload (#60).
    /// Only the reasoning-bearing keys are decoded; everything else
    /// (content, finish_reason) is ignored.
    private struct RunTranscriptMessage: Decodable {
        let role: String?
        let reasoning: String?
        let reasoningContent: String?
        enum CodingKeys: String, CodingKey {
            case role, reasoning
            case reasoningContent = "reasoning_content"
        }
    }

    private struct RunCompletedUsage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let totalTokens: Int
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }

    /// `tool.started` payload for the file-write probe (#21). Tolerant of arg-key
    /// drift across Hermes versions — the canonical shape is
    /// `{tool_name, args:{path, content}}`.
    private struct ToolStartedEnvelope: Decodable {
        let toolName: String?
        let args: WrittenFileArgs?

        enum CodingKeys: String, CodingKey {
            case toolName = "tool_name"
            case name, tool
            case args, arguments, input
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            var resolvedName: String?
            for key in [CodingKeys.toolName, .name, .tool] {
                if let value = try? c.decodeIfPresent(String.self, forKey: key) {
                    resolvedName = value
                    break
                }
            }
            toolName = resolvedName

            var resolvedArgs: WrittenFileArgs?
            for key in [CodingKeys.args, .arguments, .input] {
                if let value = try? c.decodeIfPresent(WrittenFileArgs.self, forKey: key) {
                    resolvedArgs = value
                    break
                }
            }
            args = resolvedArgs
        }
    }

    private struct WrittenFileArgs: Decodable {
        let path: String?
        let content: String?

        enum CodingKeys: String, CodingKey {
            case path, content
            case filePath = "file_path"
            case filename, text
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            var resolvedPath: String?
            for key in [CodingKeys.path, .filePath, .filename] {
                if let value = try? c.decodeIfPresent(String.self, forKey: key) {
                    resolvedPath = value
                    break
                }
            }
            path = resolvedPath

            var resolvedContent: String?
            for key in [CodingKeys.content, .text] {
                if let value = try? c.decodeIfPresent(String.self, forKey: key) {
                    resolvedContent = value
                    break
                }
            }
            content = resolvedContent
        }
    }

    /// The chat-turn request body. `input` encodes either as a plain string
    /// (text-only turn — byte-identical to the old behavior) or, when
    /// transmittable attachments are present, as an OpenAI-style content-parts
    /// array the Hermes API server's `_normalize_multimodal_content` accepts:
    /// `{"type":"text",...}` + `{"type":"image_url","image_url":{"url":
    /// "data:<mime>;base64,<data>"}}`. Images ship as data-URL parts; text-MIME
    /// files inline as delimited `{type:"text"}` parts (#43 — the endpoint
    /// rejects real file/document parts with `unsupported_content_type`, and
    /// they used to be silently dropped here). The assembly rules (ordering,
    /// budget, delimiting, truncation) live in `AttachmentInlining` so they're
    /// unit-testable and shared with the voice-memo transcript path.
    // internal, not private — test-visible (#223 Lane 5: L5-A pins the wire
    // shape). Same widening convention as the #216 `// harness-visible` tag.
    struct ChatTurnBody: Encodable {
        let input: TurnInput
        // #223 Lane 5: the per-turn model lock. All three nil on a no-pick
        // turn — synthesized Encodable omits nil optionals, keeping the
        // encoded JSON byte-compatible with the pre-Lane-5 wire shape.
        let provider: String?
        let model: String?
        let requireModelLock: Bool?

        private enum CodingKeys: String, CodingKey {
            case input, provider, model
            case requireModelLock = "require_model_lock"
        }

        // Nonisolated logger — the enclosing client is @MainActor, but this
        // nested value type isn't, so it can't reach the class's isolated one.
        private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "SessionsHermesClient")

        /// Build a turn body from the composer's message + staged attachments.
        /// With no transmittable attachments the body stays a plain string so
        /// existing text turns are unchanged on the wire. A non-nil selection
        /// adds the #223 Lane 5 lock trio; `require_model_lock` is always true
        /// alongside `model` — a bare `model` is silently ignored (#241).
        static func make(message: String, attachments: [PendingAttachment], selection: ModelSelection?) -> ChatTurnBody {
            let assembly = AttachmentInlining.assemble(message: message, attachments: attachments)

            // A raw (un-extracted) PDF or other binary has no wire shape; the
            // composer blocks send while one is staged (#8), so reaching this
            // means a non-UI path leaked one — log loudly, don't fail the turn.
            for fileName in assembly.notTransmittable {
                Self.logger.warning("Attachment \(fileName, privacy: .public) has no wire representation — not transmitted (#8)")
            }
            // Over-budget attachments already carry an in-band omission stub
            // so the agent (and the user, through it) sees the gap.
            for fileName in assembly.omittedForBudget {
                Self.logger.warning("Attachment \(fileName, privacy: .public) over aggregate body budget — omission stub sent instead")
            }

            // Empty parts = text-only turn (or nothing transmittable): plain
            // string, byte-identical to the pre-attachment wire shape. Also
            // the defensive fallback — the server 400s empty-array turns.
            guard !assembly.parts.isEmpty else {
                return ChatTurnBody(
                    input: .text(message),
                    provider: selection?.provider,
                    model: selection?.modelID,
                    requireModelLock: selection == nil ? nil : true
                )
            }
            return ChatTurnBody(
                input: .parts(assembly.parts.map { part in
                    switch part {
                    case .text(let text): ContentPart.text(text)
                    case .imageDataURL(let dataURL): ContentPart.imageURL(dataURL: dataURL)
                    }
                }),
                provider: selection?.provider,
                model: selection?.modelID,
                requireModelLock: selection == nil ? nil : true
            )
        }

        /// `input` is a string for text-only turns, or an array of content parts
        /// when images ride along. Encoded as an unkeyed single value either way.
        enum TurnInput: Encodable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text):
                    try container.encode(text)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }
        }

        enum ContentPart: Encodable {
            case text(String)
            case imageURL(dataURL: String)

            private enum CodingKeys: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }
            private struct ImageURLValue: Encodable { let url: String }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .imageURL(let dataURL):
                    try container.encode("image_url", forKey: .type)
                    try container.encode(ImageURLValue(url: dataURL), forKey: .imageURL)
                }
            }
        }
    }

    private struct CreateSessionResponse: Decodable {
        let session: SessionEnvelope
        struct SessionEnvelope: Decodable {
            let id: String
        }
    }

    private struct ModelsResponse: Decodable {
        let data: [ModelInfo]?
        struct ModelInfo: Decodable {
            let id: String?
        }
    }

    /// Subset of /api/model/options needed to flatten the picker list. Extra
    /// keys (provider labels, auth hints, pricing, current selection) are
    /// ignored; `models` is a flat list of model-id strings per provider.
    private struct ModelOptionsResponse: Decodable {
        let providers: [ProviderRow]
        struct ProviderRow: Decodable {
            let models: [String]?
            let authenticated: Bool?
        }
    }

    private struct SessionsListResponse: Decodable {
        let data: [Row]
        struct Row: Decodable {
            let id: String
            let title: String?
            let preview: String?
            let model: String?
            let source: String?
            let messageCount: Int?
            let lastActive: Double?
            let isActive: Bool?
            /// #122: cumulative billing/usage that rides on the same row —
            /// tolerantly decoded (absent/malformed → nil, the whole thing nil
            /// when no usage key is present). A cost surface, not a meter (#25).
            let usage: SessionUsage?
            enum CodingKeys: String, CodingKey {
                case id, title, preview, model, source
                case messageCount = "message_count"
                case lastActive = "last_active"
                case isActive = "is_active"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
                preview = (try? c.decodeIfPresent(String.self, forKey: .preview)) ?? nil
                model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil
                source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
                messageCount = (try? c.decodeIfPresent(Int.self, forKey: .messageCount)) ?? nil
                lastActive = (try? c.decodeIfPresent(Double.self, forKey: .lastActive)) ?? nil
                isActive = (try? c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? nil
                // Usage keys are flat siblings of the row keys, so it reads the
                // SAME decoder (its own keyed container), not a nested object.
                usage = SessionUsage.decodeIfPresent(from: decoder)
            }
        }
    }

    struct SessionMessagesResponse: Decodable {   // harness-visible (#364)
        let sessionId: String?
        let data: [StoredMessage]
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case data
        }
        struct StoredMessage: Decodable {
            /// #237: the server row id — the stable-identity anchor. Tolerant:
            /// absent decodes nil and the row keeps a fresh UUID.
            let id: Int?
            let role: String?
            let content: String?
            let timestamp: Double?
            /// Tool calls the API attaches to an assistant row, when it does
            /// (#10 — tolerant: absent/unknown shapes decode to []).
            let toolCalls: [StoredToolCall]
            /// Reasoning the model produced for this row, carried by
            /// `GET .../messages` on every resume (#121, probed 2026-07-16:
            /// both keys present, often null). Decoded tolerantly — absent,
            /// null, or a non-string all fold to nil, never a throw.
            let reasoning: String?
            let reasoningContent: String?
            enum CodingKeys: String, CodingKey {
                case id, role, content, timestamp, reasoning
                case createdAt = "created_at"
                case toolCalls = "tool_calls"
                case reasoningContent = "reasoning_content"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                // #237: tolerant — a non-integer or absent id folds to nil
                // and the row keeps a fresh UUID (no stable anchor to use).
                id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? nil
                role = try c.decodeIfPresent(String.self, forKey: .role)
                let ts = try? c.decodeIfPresent(Double.self, forKey: .timestamp)
                let created = try? c.decodeIfPresent(Double.self, forKey: .createdAt)
                timestamp = (ts ?? nil) ?? (created ?? nil)
                // content may be a plain string or an array of {type, text} parts.
                if let s = try? c.decode(String.self, forKey: .content) {
                    content = s
                } else if let parts = try? c.decode([ContentPart].self, forKey: .content) {
                    content = parts.compactMap(\.text).joined(separator: "\n")
                } else {
                    content = nil
                }
                toolCalls = (try? c.decodeIfPresent([StoredToolCall].self, forKey: .toolCalls)) ?? []
                reasoning = (try? c.decodeIfPresent(String.self, forKey: .reasoning)) ?? nil
                reasoningContent = (try? c.decodeIfPresent(String.self, forKey: .reasoningContent)) ?? nil
            }
            struct ContentPart: Decodable {
                let type: String?
                let text: String?
            }
        }

        /// One stored tool call — tolerant of shape drift: flat
        /// `{name|tool_name|tool}` or OpenAI-style `{function:{name}}`;
        /// `preview` is kept as the chip detail when present.
        struct StoredToolCall: Decodable {
            let name: String?
            let detail: String?
            /// #364: the raw args JSON the server stored for this call —
            /// `function.arguments` (the observed 0.20.3 shape) or a flat
            /// `arguments` key. Tolerant: absent/null/non-string fold to nil,
            /// and nil means "map exactly as pre-#364" — which is also the
            /// posture on hosts whose storage never carried args (OJAMD is
            /// unverified): the wire shape itself is the gate.
            let arguments: String?

            enum CodingKeys: String, CodingKey {
                case name, tool, function, preview, arguments
                case toolName = "tool_name"
            }
            struct FunctionEnvelope: Decodable {
                let name: String?
                let arguments: String?
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let function = try? c.decodeIfPresent(FunctionEnvelope.self, forKey: .function)
                var resolved: String?
                for key in [CodingKeys.name, .toolName, .tool] {
                    if let value = try? c.decodeIfPresent(String.self, forKey: key), value.isEmpty == false {
                        resolved = value
                        break
                    }
                }
                if resolved == nil { resolved = function?.name }
                name = resolved
                detail = (try? c.decodeIfPresent(String.self, forKey: .preview)) ?? nil
                let nested = function?.arguments
                let flat = (try? c.decodeIfPresent(String.self, forKey: .arguments)) ?? nil
                arguments = nested ?? flat
            }
        }
    }

    enum SessionsClientError: LocalizedError {
        case notConfigured(String)
        case requestFailed(String)
        /// The server session behind the active hop no longer exists (#90) —
        /// the send paths swap the handle and retry once on a fresh hop.
        case sessionNotFound

        var errorDescription: String? {
            switch self {
            case .notConfigured(let message), .requestFailed(let message):
                return message
            case .sessionNotFound:
                return "The Hermes session no longer exists on the host."
            }
        }
    }
}


/// Region-checker workaround box for the multi-host session fetch (M-5).
/// Every child task in the fetch group is MainActor-isolated, so appends
/// never race; the MainActor-isolated reference type (implicitly Sendable)
/// is what lets results cross the task-group boundary without moving
/// non-Sendable `(BackendProfile, Result<_, any Error>)` tuples through it,
/// which the iOS 27 SDK's region-based isolation checker rejects outright.
@MainActor
private final class ProfileFetchAccumulator {
    var lists: [(profile: BackendProfile, infos: [HermesSessionInfo])] = []
    var failures: [Error] = []
}
