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

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURLProvider: @MainActor () -> String?
    private let apiKeyProvider: @MainActor () -> String?

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
    private let usageIndex: SessionUsageIndexStore?
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
        session: URLSession = .shared,
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
        let hop = try await ensureHopForTurn()
        do {
            return try await postSyncChat(sessionId: hop.sessionId, profileID: hop.profileID, message: message, attachments: attachments)
        } catch SessionsClientError.sessionNotFound where hop.wasReused {
            Self.logger.notice("sync turn: persisted hop stale server-side (404) — re-hopping with transplant")
            journal.endHop()
            let fresh = try await ensureHopForTurn()
            return try await postSyncChat(sessionId: fresh.sessionId, profileID: fresh.profileID, message: message, attachments: attachments)
        }
    }

    private func postSyncChat(sessionId: String, profileID: UUID?, message: String, attachments: [PendingAttachment]) async throws -> String {
        let path = "\(Self.sessionsPath)/\(sessionId)/chat"
        let response: SyncChatResponse = try await postJSON(
            path: path,
            body: ChatTurnBody.make(message: message, attachments: attachments),
            profileID: profileID
        )
        return response.message?.content ?? response.content ?? ""
    }

    func sendStreaming(
        message content: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) -> AsyncStream<StreamingUpdate> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.yield(.failed("Client deallocated"))
                    continuation.finish()
                    return
                }
                await self.streamTurn(
                    message: content,
                    attachments: attachments,
                    into: continuation,
                    allowStaleHopRetry: true
                )
                continuation.finish()
            }
        }
    }

    /// One streamed turn against the active hop. `allowStaleHopRetry` guards
    /// the single 404 retry for a REUSED persisted hop whose server session
    /// expired: the handle swaps (that's what makes it a handle, not
    /// identity) and the turn re-runs once on a fresh, transplanted hop.
    private func streamTurn(
        message content: String,
        attachments: [PendingAttachment],
        into continuation: AsyncStream<StreamingUpdate>.Continuation,
        allowStaleHopRetry: Bool
    ) async {
        var capturedSessionId = ""
        var runId: String?
        var runStarted = false
        do {
            let hop = try await ensureHopForTurn()
            capturedSessionId = hop.sessionId
            // P1: the transplant just happened, before this turn hits the
            // wire — surface its cost so the receipts stay honest (#90).
            if let priming = hop.priming {
                continuation.yield(.contextPrimed(priming.usage))
            }
            let path = "\(Self.sessionsPath)/\(hop.sessionId)/chat/stream"
            let body = try encoder.encode(ChatTurnBody.make(message: content, attachments: attachments))
            let request = try makeRequest(path: path, method: "POST", body: body, accept: "text/event-stream", profileID: hop.profileID)

            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 404, hop.wasReused, allowStaleHopRetry {
                    Self.logger.notice("stream turn: persisted hop stale server-side (404) — re-hopping with transplant")
                    journal.endHop()
                    await streamTurn(
                        message: content,
                        attachments: attachments,
                        into: continuation,
                        allowStaleHopRetry: false
                    )
                    return
                }
                connectionStatus = .error
                continuation.yield(.failed("Hermes API returned status \(code)."))
                return
            }

            connectionStatus = .connected

            var currentEvent = "message"
            var currentData = ""
            var assembledContent = ""
            // #4.15: reasoning deltas from the `_thinking` channel,
            // assembled so the final message carries the full text.
            var assembledReasoning = ""
            var finalMessageDelivered = false
            var pendingFinalMessage: Message?
            // #21 Tier 1: files the agent writes are streamed inline on
            // `tool.started`; reconstruct them and attach to the final message.
            var producedFiles: [MessageAttachment] = []
            // #21 Tier 2: whitelist-relative paths of agent files announced
            // anywhere in the turn's tool calls. Binaries never ride the
            // stream (2026-07-16 probe: produced host-side via `terminal`,
            // `write_file` never called) — the PATH is the only client-visible
            // signal, so it's harvested from every tool payload and, at
            // finish, from the assistant's own prose.
            var announcedAgentPaths: [String] = []

            func dispatchEvent() {
                defer {
                    currentEvent = "message"
                    currentData = ""
                }
                guard !currentData.isEmpty else { return }
                switch currentEvent {
                case "run.started":
                    runStarted = true
                    if let rid = decodeJSONString(currentData, key: "run_id") {
                        runId = rid
                    }
                case "assistant.delta":
                    if let delta = decodeJSONString(currentData, key: "delta"),
                       !delta.isEmpty {
                        assembledContent += delta
                        continuation.yield(.textDelta(delta))
                    }
                case "tool.started", "tool.completed":
                    // #11: `tool.started` carries name + args + preview;
                    // `tool.completed` is usually empty (no result payload
                    // today — verified against the live host), so it only
                    // yields when the server names the finished tool.
                    if let event = parseToolCallEvent(
                        currentData,
                        phase: currentEvent == "tool.started" ? .started : .completed
                    ) {
                        continuation.yield(.toolActivity(event))
                    }
                    // #21: a write surfaces only on `tool.started` —
                    // `tool.completed` is empty. Content present → Tier 1
                    // stages the bytes now; content absent → a Tier 2
                    // fetchable rides `remotePath` instead.
                    if currentEvent == "tool.started" {
                        if let file = Self.parseWrittenFile(currentData, profileID: hop.profileID) {
                            producedFiles.append(file)
                        }
                        // #21 Tier 2: any tool call can reveal an agent-files
                        // path (`terminal` commands, search results) — harvest
                        // them all; dedupe happens at finish.
                        announcedAgentPaths.append(
                            contentsOf: Self.announcedAgentFilePaths(fromToolPayload: currentData)
                        )
                    }
                case "tool.progress":
                    // #4.15: reasoning rides `tool.progress` with
                    // `tool_name:"_thinking"` — a separate channel from
                    // the answer (SSE taxonomy, Phase 0). Forward the
                    // deltas so the UI can show thinking live; progress
                    // events for real tools stay dropped (no UI yet).
                    if let chunk = Self.thinkingDelta(fromToolProgress: currentData),
                       let delta = Self.incrementalReasoningDelta(from: chunk, assembled: assembledReasoning) {
                        assembledReasoning += delta
                        continuation.yield(.reasoningDelta(delta))
                    }
                case "assistant.completed":
                    // Streaming returns an empty final_response (text already
                    // streamed via assistant.delta), so the server sends content:"".
                    // Empty string is non-nil, so `?? assembledContent` won't fire;
                    // fall back to the assembled deltas when content is blank.
                    let declared = decodeJSONString(currentData, key: "content")
                    let finalContent = (declared?.isEmpty == false) ? declared! : assembledContent
                    pendingFinalMessage = Message(
                        sender: .hermes,
                        content: finalContent,
                        status: .delivered
                    )
                    // Defer `.finished` until run.completed delivers token usage.
                case "run.completed":
                    let usage = decodeRunUsage(currentData)
                    // #25: persist the run's usage keyed by this hop's server
                    // session — the CTX gauge's only source when the session
                    // is later resumed (the stored transcript carries no
                    // usage; see openSession). Tolerant by construction: an
                    // absent/malformed usage decodes to nil and records
                    // nothing, leaving the session honestly unknown.
                    if let usage {
                        usageIndex?.record(sessionID: hop.sessionId, usage: usage)
                    }
                    var message = pendingFinalMessage
                        ?? Message(sender: .hermes, content: assembledContent, status: .delivered)
                    // Reasoning attaches HERE, at the yield — never earlier: a
                    // `_thinking` chunk can land between assistant.completed
                    // and run.completed, and a value frozen at
                    // assistant.completed would lose it. Precedence (#60):
                    // the terminal transcript's structured reasoning wins —
                    // the gateway's `_thinking` stream is a defective
                    // answer-mirror upstream, while the real CoT rides
                    // `run.completed` per-message. The mirror guard applies
                    // to BOTH branches (60B): a structured aggregate that
                    // just restates the answer counts as absent and falls
                    // through, and assembled deltas attach only when
                    // genuinely distinct from the answer, so the day
                    // upstream streams real deltas they are adopted live;
                    // an answer-mirror never attaches.
                    let structured = decodeRunReasoning(currentData)
                    if let structured,
                       !Self.reasoningMirrorsAnswer(structured, content: message.content) {
                        message.reasoning = structured
                    } else if !assembledReasoning.isEmpty,
                              !Self.reasoningMirrorsAnswer(assembledReasoning, content: message.content) {
                        message.reasoning = assembledReasoning
                    }
                    // #21 Tier 2: paths announced in tool calls or the answer
                    // itself become fetchable bubbles (deduped against the
                    // Tier 1 reconstructions), stamped with the hop's birth
                    // profile so the fetch hits the right relay (Lane M).
                    producedFiles.append(contentsOf: Self.fetchableAgentFileAttachments(
                        announcedPaths: announcedAgentPaths + Self.agentFilesRelativePaths(in: message.content),
                        existing: producedFiles,
                        profileID: hop.profileID
                    ))
                    if !producedFiles.isEmpty { message.attachments = producedFiles }
                    continuation.yield(.finished(message, usage, nil))
                    finalMessageDelivered = true
                case "done":
                    break
                default:
                    break
                }
            }

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                if line.hasPrefix(":") { continue }
                if line.isEmpty {
                    dispatchEvent()
                    continue
                }
                if line.hasPrefix("event:") {
                    // URLSession's bytes.lines swallows the blank lines that
                    // separate SSE events, so the `line.isEmpty` dispatch above
                    // never fires. Flush the previous event when a new one begins.
                    if !currentData.isEmpty { dispatchEvent() }
                    currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if currentData.isEmpty {
                        currentData = value
                    } else {
                        currentData += "\n" + value
                    }
                }
            }

            // Flush any pending event the server didn't terminate with a blank line.
            if !currentData.isEmpty { dispatchEvent() }

            if !finalMessageDelivered {
                var fallbackMessage = pendingFinalMessage ?? Message(
                    sender: .hermes,
                    content: assembledContent,
                    status: .delivered
                )
                // #60: no run.completed payload exists here by construction,
                // so only the assembled `_thinking` text is available — and it
                // attaches only when it isn't the upstream answer-mirror.
                if !assembledReasoning.isEmpty,
                   !Self.reasoningMirrorsAnswer(assembledReasoning, content: fallbackMessage.content) {
                    fallbackMessage.reasoning = assembledReasoning
                }
                // #21 Tier 2: same fetchable-path sweep as the run.completed
                // case — a stream the server didn't terminate cleanly must
                // not drop announced files.
                producedFiles.append(contentsOf: Self.fetchableAgentFileAttachments(
                    announcedPaths: announcedAgentPaths + Self.agentFilesRelativePaths(in: fallbackMessage.content),
                    existing: producedFiles,
                    profileID: hop.profileID
                ))
                if !producedFiles.isEmpty { fallbackMessage.attachments = producedFiles }
                continuation.yield(.finished(fallbackMessage, nil, nil))
            }
        } catch {
            connectionStatus = .error
            Self.logger.warning("Sessions API stream failed: \(error.localizedDescription)")
            if runStarted {
                // Run committed server-side; a dropped stream (e.g. the app
                // suspended on lock) is recoverable, not a failure.
                continuation.yield(.interrupted(sessionId: capturedSessionId, runId: runId))
            } else if Self.isUnreachableError(error) {
                // The turn never reached the Sessions API — queueable in the
                // offline compose outbox (#90), not a dead-end failure.
                continuation.yield(.unreachable(failureMessage(for: error)))
            } else {
                continuation.yield(.failed(failureMessage(for: error)))
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

    /// Switches the active model. The Hermes agent dispatches `/model …` as a
    /// command turn; the chosen model applies once a fresh session is created
    /// — so the hop ends here, making "next session" mean the user's very
    /// next message: it hops to a fresh session under the new model with the
    /// journal transplanted. A model switch IS a brain hop (P1/#90).
    ///
    /// A command turn needs a session but NOT context: it reuses the current
    /// hop when one exists, and otherwise posts through a bare throwaway
    /// session — never `ensureHopForTurn()`, which would pay for a transplant
    /// that `endHop()` immediately discards (and the user's next message
    /// would pay for again).
    ///
    /// Returns the response text — it carries the authoritative
    /// "Context: N tokens" for the switched model, which the CTX meter's
    /// denominator reconciles against (#4).
    @discardableResult
    func switchModel(_ identifier: String) async throws -> String? {
        let command = "/model \(identifier)"
        var response: String?
        // M-6: model switching is an ACTIVE-profile surface (shim + gateway
        // pair). Only reuse the hop when it lives on the active profile — a
        // command turn posted to a foreign hop would pin the model on the
        // wrong host. A nil hop profile is the pre-Lane-M record, which can
        // only be the migrated (active) profile.
        let activeID = activeProfileIDProvider()
        if let hop = journal.activeHop, journal.activeHopIsCurrent,
           hop.profileID == nil || hop.profileID == activeID {
            do {
                response = try await postSyncChat(sessionId: hop.apiSessionId, profileID: hop.profileID, message: command, attachments: [])
            } catch SessionsClientError.sessionNotFound {
                journal.endHop()
            }
        }
        if response == nil {
            response = try await postSyncChat(sessionId: try await createBareSession(), profileID: nil, message: command, attachments: [])
        }
        journal.endHop()
        return response
    }

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
                profileName: profile?.name
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
    private func fetchSessionConversation(_ id: String, profileID: UUID?) async throws -> (sessionId: String, conversation: Conversation) {
        let path = "\(Self.sessionsPath)/\(id)/messages"
        let request = try makeRequest(path: path, method: "GET", body: nil, accept: "application/json", profileID: profileID)
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
        let messages = response.data.compactMap(Self.mapStoredMessage)
        let convo = Conversation(
            title: Conversation.defaultTitle,
            messages: messages,
            lastActivity: messages.last?.timestamp ?? .now
        )
        return (response.sessionId ?? id, convo)
    }

    nonisolated private static func mapStoredMessage(_ m: SessionMessagesResponse.StoredMessage) -> Message? {
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
        let activities: [ToolActivity]
        if sender == .hermes {
            activities = m.toolCalls.compactMap { call in
                guard let name = call.name, !name.isEmpty, name != "_thinking" else { return nil }
                return ToolActivity(label: name, startedAt: ts, isActive: false, detail: call.detail)
            }
        } else {
            activities = []
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
        return Message(
            sender: sender,
            content: text,
            timestamp: ts,
            status: .delivered,
            toolActivities: activities,
            reasoning: reasoning
        )
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
    private struct PreparedHop {
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
    private func ensureHopForTurn() async throws -> PreparedHop {
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

    /// POST /api/sessions — a fresh, unprimed server session on the given
    /// profile's gateway. Hop registration and transplanting are the
    /// caller's business.
    private func createBareSession(profileID: UUID? = nil) async throws -> String {
        let response: CreateSessionResponse = try await postJSON(
            path: Self.sessionsPath,
            body: EmptyBody(),
            profileID: profileID
        )
        return response.session.id
    }

    /// Lane M: stamps a session's immutable birth profile into the index.
    private func recordBirth(sessionId: String, profileID: UUID?) {
        guard let profileID else { return }
        profileIndex?.record(sessionID: sessionId, profileID: profileID)
    }

    /// Posts the transplant as the fresh session's first turn over SSE and
    /// returns the run's real token usage. Streamed rather than sync /chat
    /// because usage rides ONLY `run.completed` — the receipts carry real
    /// numbers or none (#46). Deltas are drained and discarded: the
    /// acknowledgment is meta-traffic, not conversation content.
    private func postPrimingTurn(sessionId: String, profileID: UUID?, text: String) async throws -> TokenUsage? {
        let path = "\(Self.sessionsPath)/\(sessionId)/chat/stream"
        let body = try encoder.encode(ChatTurnBody.make(message: text, attachments: []))
        let request = try makeRequest(path: path, method: "POST", body: body, accept: "text/event-stream", profileID: profileID)
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw SessionsClientError.requestFailed(
                "Hermes API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0) for the priming turn."
            )
        }

        var usage: TokenUsage?
        var currentEvent = "message"
        var currentData = ""
        func dispatchEvent() {
            defer {
                currentEvent = "message"
                currentData = ""
            }
            guard !currentData.isEmpty, currentEvent == "run.completed" else { return }
            usage = decodeRunUsage(currentData)
        }
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            if line.hasPrefix(":") { continue }
            if line.isEmpty {
                dispatchEvent()
                continue
            }
            if line.hasPrefix("event:") {
                if !currentData.isEmpty { dispatchEvent() }
                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                currentData = currentData.isEmpty ? value : currentData + "\n" + value
            }
        }
        if !currentData.isEmpty { dispatchEvent() }
        return usage
    }

    // MARK: - HTTP plumbing

    private func getJSON<T: Decodable>(path: String, profileID: UUID? = nil) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", body: nil, accept: "application/json", profileID: profileID)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data, path: path)
        return try decoder.decode(T.self, from: data)
    }

    private func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body, profileID: UUID? = nil) async throws -> T {
        let encodedBody = try encoder.encode(body)
        let request = try makeRequest(path: path, method: "POST", body: encodedBody, accept: "application/json", profileID: profileID)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data, path: path)
        return try decoder.decode(T.self, from: data)
    }

    private func makeRequest(path: String, method: String, body: Data?, accept: String, profileID: UUID? = nil) throws -> URLRequest {
        let endpoint = try resolveEndpoint(profileID: requestProfileID(profileID))
        guard let url = URL(string: normalizedBaseURL(endpoint.baseURL) + path) else {
            throw SessionsClientError.notConfigured("Hermes API base URL is not set.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.httpBody = body
        request.timeoutInterval = 300
        return request
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
        if let content = args.content {
            return MessageAttachment.agentFile(remotePath: path, content: content)
        }
        guard let relative = agentFilesRelativePaths(in: path).first else { return nil }
        return MessageAttachment.fetchableAgentFile(
            name: (relative as NSString).lastPathComponent,
            remotePath: relative,
            profileID: profileID
        )
    }

    // MARK: - Agent-file announcement scan (#21 Tier 2)

    /// The whitelisted agent-files directory's terminal component on BOTH
    /// hosts (OJAMD `O:\Hermes\MobileDL`, Mac `~/Hermes/agent-work/MobileDL`)
    /// — the anchor that lets the client derive the route-form relative path
    /// without knowing the host's absolute AGENT_FILES_DIR.
    nonisolated private static let agentFilesDirName = "MobileDL"

    /// Matches `MobileDL` followed by one or more path segments, either
    /// separator style (`\\` doubles in raw JSON, hence the `+`).
    nonisolated(unsafe) private static let agentFilesPathPattern =
        /(?i)MobileDL((?:[\/\\]+[A-Za-z0-9._\-]+)+)/
    /// A plausible file (not directory) tail: an extension of 1–8
    /// alphanumerics on a non-empty stem.
    nonisolated(unsafe) private static let fileExtensionPattern = /[^\/.]\.[A-Za-z0-9]{1,8}$/

    /// Extracts the agent-files-relative (route-form) paths mentioned in a
    /// string — host prose ("Saved to O:\Hermes\MobileDL\report.pdf"), tool
    /// args (`terminal` commands), search results. Windows or POSIX
    /// separators normalize to `/`; only tokens with a file-like extension
    /// qualify, so bare directory mentions ("your MobileDL folder") never
    /// produce a bubble. Order preserved, duplicates dropped.
    nonisolated static func agentFilesRelativePaths(in text: String) -> [String] {
        guard text.range(of: agentFilesDirName, options: .caseInsensitive) != nil else { return [] }
        var results: [String] = []
        var seen = Set<String>()
        for match in text.matches(of: agentFilesPathPattern) {
            var relative = String(match.1)
                .replacingOccurrences(of: "\\", with: "/")
            while relative.contains("//") {
                relative = relative.replacingOccurrences(of: "//", with: "/")
            }
            while relative.hasPrefix("/") { relative.removeFirst() }
            // Prose punctuation can ride the capture ("…report.pdf.").
            while relative.hasSuffix(".") { relative.removeLast() }
            guard !relative.isEmpty,
                  relative.firstMatch(of: fileExtensionPattern) != nil else { continue }
            let key = relative.lowercased()
            if seen.insert(key).inserted { results.append(relative) }
        }
        return results
    }

    /// Harvests agent-files paths from a `tool.started` payload by walking
    /// every string value in the JSON (args of ANY tool — the probe's binary
    /// rode a `terminal` command — plus `preview` and friends). Keys are
    /// walked in sorted order so the result is deterministic.
    nonisolated static func announcedAgentFilePaths(fromToolPayload raw: String) -> [String] {
        guard raw.range(of: agentFilesDirName, options: .caseInsensitive) != nil,
              let data = raw.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        var strings: [String] = []
        collectStrings(payload, into: &strings)
        var results: [String] = []
        var seen = Set<String>()
        for string in strings {
            for path in agentFilesRelativePaths(in: string) where seen.insert(path.lowercased()).inserted {
                results.append(path)
            }
        }
        return results
    }

    nonisolated private static func collectStrings(_ value: Any, into strings: inout [String]) {
        switch value {
        case let string as String:
            strings.append(string)
        case let array as [Any]:
            for element in array { collectStrings(element, into: &strings) }
        case let dictionary as [String: Any]:
            for key in dictionary.keys.sorted() {
                collectStrings(dictionary[key] as Any, into: &strings)
            }
        default:
            break
        }
    }

    /// Builds the turn's fetchable attachments from every announced path,
    /// deduped against paths already covered and against files the Tier 1
    /// path already reconstructed (a staged copy with real bytes beats a
    /// fetchable pointer to the same file).
    nonisolated static func fetchableAgentFileAttachments(
        announcedPaths: [String],
        existing: [MessageAttachment],
        profileID: UUID?
    ) -> [MessageAttachment] {
        var seenPaths = Set(existing.compactMap { $0.remotePath?.lowercased() })
        // Names normalize to their path tail: pre-fix Tier 1 attachments from
        // Windows paths carry the whole backslashed path as their fileName.
        var seenNames = Set(existing.map {
            MessageAttachment.lastPathComponentAcrossHosts($0.fileName).lowercased()
        })
        var results: [MessageAttachment] = []
        for path in announcedPaths {
            guard seenPaths.insert(path.lowercased()).inserted else { continue }
            let name = (path as NSString).lastPathComponent
            guard !name.isEmpty, seenNames.insert(name.lowercased()).inserted else { continue }
            results.append(.fetchableAgentFile(name: name, remotePath: path, profileID: profileID))
        }
        return results
    }

    private func failureMessage(for error: Error) -> String {
        if let sessionsError = error as? SessionsClientError {
            return sessionsError.errorDescription ?? "Hermes API request failed."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "Hermes API request failed." : described
    }

    // MARK: - Wire types

    private struct EmptyBody: Encodable {}

    /// Extracts token usage from a `run.completed` SSE payload. Hermes emits
    /// Anthropic-style keys (input/output/total); map onto TokenUsage's
    /// prompt/completion/total. Returns nil if usage is absent or unparseable.
    nonisolated private func decodeRunUsage(_ data: String) -> TokenUsage? {
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
    private struct ChatTurnBody: Encodable {
        let input: TurnInput

        private enum CodingKeys: String, CodingKey { case input }

        // Nonisolated logger — the enclosing client is @MainActor, but this
        // nested value type isn't, so it can't reach the class's isolated one.
        private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "SessionsHermesClient")

        /// Build a turn body from the composer's message + staged attachments.
        /// With no transmittable attachments the body stays a plain string so
        /// existing text turns are unchanged on the wire.
        static func make(message: String, attachments: [PendingAttachment]) -> ChatTurnBody {
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
                return ChatTurnBody(input: .text(message))
            }
            return ChatTurnBody(input: .parts(assembly.parts.map { part in
                switch part {
                case .text(let text): ContentPart.text(text)
                case .imageDataURL(let dataURL): ContentPart.imageURL(dataURL: dataURL)
                }
            }))
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

    private struct SyncChatResponse: Decodable {
        let message: AssistantMessage?
        let content: String?
        struct AssistantMessage: Decodable {
            let content: String
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
            enum CodingKeys: String, CodingKey {
                case id, title, preview, model, source
                case messageCount = "message_count"
                case lastActive = "last_active"
                case isActive = "is_active"
            }
        }
    }

    private struct SessionMessagesResponse: Decodable {
        let sessionId: String?
        let data: [StoredMessage]
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case data
        }
        struct StoredMessage: Decodable {
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
                case role, content, timestamp, reasoning
                case createdAt = "created_at"
                case toolCalls = "tool_calls"
                case reasoningContent = "reasoning_content"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
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

            enum CodingKeys: String, CodingKey {
                case name, tool, function, preview
                case toolName = "tool_name"
            }
            struct FunctionEnvelope: Decodable {
                let name: String?
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                var resolved: String?
                for key in [CodingKeys.name, .toolName, .tool] {
                    if let value = try? c.decodeIfPresent(String.self, forKey: key), value.isEmpty == false {
                        resolved = value
                        break
                    }
                }
                if resolved == nil,
                   let function = try? c.decodeIfPresent(FunctionEnvelope.self, forKey: .function) {
                    resolved = function.name
                }
                name = resolved
                detail = (try? c.decodeIfPresent(String.self, forKey: .preview)) ?? nil
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
