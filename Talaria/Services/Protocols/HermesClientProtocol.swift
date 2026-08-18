import Foundation

/// Lightweight summary of a Hermes session, returned by `listSessions()`.
/// Service-layer DTO — the UI maps this to its own `SessionSummary`.
struct HermesSessionInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let preview: String?
    let model: String?
    let source: String?
    let messageCount: Int
    let lastActive: Date?
    let isActive: Bool
    /// Lane M (#114): the backend profile this session lives on — session
    /// ids are server-scoped. Nil from single-backend clients (local brain,
    /// mocks, profile-less constructions).
    let profileID: UUID?
    /// Display name of that profile, carried for the drawer's foreign-host
    /// badge so the UI never re-resolves ids.
    let profileName: String?
    /// #122: cumulative billing/usage from the Sessions LIST/DETAIL endpoints
    /// (a cost surface, never a context meter — see #25). Nil when the wire
    /// omitted it (old/sparse session) or the client has no such data (local
    /// brain, mocks) — an absent value hides the cost row, never shows zeros.
    let usage: SessionUsage?
    /// #190: false only for remote-stub rows — sessions the drawer still
    /// shows (dimmed) but no configured host can open right now.
    let isResumable: Bool
    /// Honest one-line reason shown on an unresumable row. Nil while
    /// `isResumable` is true.
    let unresumableReason: String?

    init(
        id: String,
        title: String?,
        preview: String?,
        model: String?,
        source: String?,
        messageCount: Int,
        lastActive: Date?,
        isActive: Bool,
        profileID: UUID? = nil,
        profileName: String? = nil,
        usage: SessionUsage? = nil,
        isResumable: Bool = true,
        unresumableReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.model = model
        self.source = source
        self.messageCount = messageCount
        self.lastActive = lastActive
        self.isActive = isActive
        self.profileID = profileID
        self.profileName = profileName
        self.usage = usage
        self.isResumable = isResumable
        self.unresumableReason = unresumableReason
    }

    /// #190: the same session, re-marked as unopenable — how the router
    /// surfaces remote stubs once no configured host can resume them.
    func asUnresumable(reason: String) -> HermesSessionInfo {
        HermesSessionInfo(
            id: id,
            title: title,
            preview: preview,
            model: model,
            source: source,
            messageCount: messageCount,
            lastActive: lastActive,
            isActive: false,
            profileID: profileID,
            profileName: profileName,
            usage: usage,
            isResumable: false,
            unresumableReason: reason
        )
    }
}

/// #357 (3C): how a steer SUBMIT resolved. Every arm distinct, none of them
/// "applied" — the applied signal is `StreamingUpdate.steerLanded` and only
/// that (bar 357-G; the wording rule 306-J means the UI never says "sent"
/// off any of these).
enum SteerSubmitOutcome: Equatable, Sendable {
    /// 2xx `accepted: true` — the host took the text. "We asked", no more.
    case submitted
    /// 409 `run_not_accepting_steer` — the run is past taking steers.
    case windowClosed
    /// 404 `run_not_found` — the run is gone (TTL, reap, wrong host).
    case runGone
    /// This client has no in-flight run to address.
    case noActiveRun
    /// The POST demonstrably did not land (transport/config failure).
    case unreachable(String)
    /// Anything else the host said, verbatim-ish.
    case rejected(String)
}

@MainActor
protocol HermesClientProtocol {
    var connectionStatus: ConnectionStatus { get }
    var currentConversation: Conversation? { get }

    /// #295 (Owen's ruling, review follow-up): whether the run CURRENTLY
    /// active on this client, if any, is on a plane whose host keeps
    /// generating after the client's own stream drops — i.e. whether
    /// `reconcileFromServer()` could ever resolve it. `ChatStore.cancelStreaming`
    /// reads this to decide whether the continued-send expiration path
    /// (`hardStopHost: false`) may arm a `PendingRun` + reconcile loop at
    /// all, and it MUST be read before `abandonActiveRun()` — which, on
    /// `ChatBackendRouter`, clears the exact signal this is built from.
    ///
    /// The default is `false`: a plain client with no concept of "brain"
    /// (mock, relay, the on-device backend) has nothing still running once
    /// the app stops watching, so arming recovery would only ever be a false
    /// promise — worse, on a client sharing a journal hop with an unrelated
    /// EARLIER Hermes turn, it would arm a `PendingRun` that can never
    /// resolve against ITS OWN turn but could wrongly adopt a LATER Hermes
    /// reply on that same hop (`reconcileFromServer()` resolves against
    /// `journal.activeHop`, not `pending.sessionId`) — cross-hop corruption,
    /// not just a silent hole. `ChatBackendRouter` overrides this to check
    /// which brain currently holds the routing lock, and `SessionsHermesClient`
    /// overrides it to unconditional `true` (it IS the Hermes plane by
    /// construction) so a raw client wired directly — bypassing the router,
    /// as some tests do — still reads correctly.
    var currentRunIsServerRecoverable: Bool { get }
    func connect() async
    func disconnect() async
    func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message
    func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate>
    func loadConversation() async -> Conversation
    func clearConversation() async throws -> Conversation

    /// Lists the model identifiers the connected host exposes (e.g. /v1/models).
    func availableModels() async throws -> [String]

    /// Requests a model switch. Per the Hermes Sessions API this applies to the
    /// NEXT session, so callers should start a fresh session for it to take effect.
    /// Returns the host's response text — it carries the authoritative
    /// "Context: N tokens" for the switched model (#4). Nil when the client
    /// has no response to report.
    @discardableResult
    func switchModel(_ identifier: String) async throws -> String?

    /// Lists recent sessions from the host's Sessions API.
    func listSessions() async throws -> [HermesSessionInfo]

    /// Opens an existing session: adopts its id and returns its message history
    /// as a Conversation. New messages continue that thread.
    func openSession(_ id: String) async throws -> Conversation

    /// Re-fetches the current session's messages from the host (GET /messages)
    /// so a run that completed while the stream was dropped can be reconciled.
    /// Returns nil for clients without a server-backed session (relay / mock).
    func reconcileFromServer() async -> Conversation?

    /// #192: the consumer walked away from the in-flight run (clear, session
    /// switch, a continued-send expiring) — NOT the explicit Stop tap.
    /// Clients holding per-run state release it here so an abandoned stream
    /// can never wedge later routing; the default is a no-op. Sessions-plane
    /// parity (#283 review ruling): this MUST NOT reach the network — a
    /// walk-away lets the host keep generating, so switching threads or
    /// clearing mid-turn doesn't throw away an answer the write-half would
    /// otherwise have preserved. `ChatStore.cancelStreaming(hardStopHost:)`
    /// calls this UNCONDITIONALLY, on every path — explicit Stop and
    /// walk-away alike — because releasing the routing lock is always
    /// correct; only `hardStopActiveRun()` below is gated by that
    /// parameter.
    func abandonActiveRun()

    /// #283 Task 7 (S23): the explicit user Stop tap's real server-side
    /// interrupt. `ChatStore.cancelStreaming(hardStopHost:)` is its one call
    /// site, gated by that parameter: `true` (the default — the in-app Stop
    /// button, and Siri's Cancel via `AskHermesIntent`/
    /// `AskHermesLongRunSupport`) fires it; `false` (the ONE other caller,
    /// the continued-send expiration handler — the system revoking a
    /// background task's budget with NO user action) skips it, so the host
    /// run is left alone rather than hard-killed on a turn the user never
    /// asked to stop. A real server-side interrupt for clients that can
    /// issue one (the Hermes runs plane's `POST /v1/runs/{id}/stop`); the
    /// default is a no-op for clients with nothing to interrupt server-side
    /// (mock / relay / the on-device brain). Distinct from `abandonActiveRun`
    /// above: a walk-away must never hard-kill a run the user didn't ask to
    /// stop, so this is the ONLY door that touches the network.
    ///
    /// #295 close-out (SHIPPED): skipping this call does NOT "degrade to
    /// the ordinary recovery poll" — there is no client-side host-recovery
    /// poll on the expiration path. What it degrades to instead is the real
    /// route: on a server-recoverable turn, `ChatStore.cancelStreaming`
    /// arms `pendingRun` / `reconcileFromServer()`, the same mechanics the
    /// `.interrupted` arm uses; on a local-brain turn (nothing server-side
    /// to reconcile against) it finalizes the placeholder instead, same as
    /// an explicit Stop. See `ChatStore.cancelStreaming(hardStopHost:)`'s
    /// doc for the full account.
    ///
    /// **#328 route 2 — the return value is the whole point of this signature
    /// change, and it is deliberately narrow.** `true` means a stop request
    /// was ISSUED to the host for a run this client actually had in flight.
    /// `false` means nothing was sent at all — no run context, no runs plane,
    /// no network call. That distinction was previously invisible: the method
    /// returned `Void` and guard-returned silently, so **every ordinary
    /// sessions `chat/stream` turn — the default, the one the phone uses —
    /// had its Stop swallowed here while the UI looked like it obeyed.** Owen
    /// measured it on device (`sleep 90 && echo Done`: the host ran the whole
    /// command and answered on reopen). The caller needs to know so it can
    /// say what is true.
    ///
    /// **`true` is NOT a promise the host stopped**, and must never be read as
    /// one. The POST is fire-and-forget (see the runs implementation): a
    /// transport failure is logged and deliberately does not mark the run
    /// self-stopped. The honest reading of `true` is *"we asked"* — which is
    /// exactly the claim the UI is allowed to make. Route 1 (making a
    /// sessions-plane Stop actually reach the host) is a separate question,
    /// gated on #328's bar 328-A route probe.
    @discardableResult
    func hardStopActiveRun() -> Bool

    /// #322: the id of the run this client currently has in flight, if its
    /// plane has run ids at all.
    ///
    /// **Read-before-clear, exactly like `currentRunIsServerRecoverable`
    /// above.** `hardStopActiveRun()` clears `activeRunContext` as its FIRST
    /// statement, and `ChatBackendRouter`'s override answers from
    /// `runningBrain`, which `abandonActiveRun()` releases — so
    /// `ChatStore.cancelStreaming` must capture this at the top of the
    /// function, before either call, or it reads nil on every Stop.
    ///
    /// The default is `nil`, and nil is HONEST rather than a gap: a plane
    /// with no run id (the on-device brain, the relay, the mock) has no
    /// `/v1/runs/{id}` to read a final status from, so #322's read is
    /// correctly skipped and the gauge goes unknown.
    var activeRunID: String? { get }

    /// #357 (3C): submit a steer against the client's in-flight run over the
    /// native route. The outcome classifies the SUBMIT only — `submitted` is
    /// "we asked", exactly the `hardStopActiveRun` reading; applied is a
    /// stream fact (`StreamingUpdate.steerLanded`), never an HTTP one.
    func steerActiveRun(text: String) async -> SteerSubmitOutcome

    /// #322: ONE bounded, best-effort `GET /v1/runs/{id}` taken on the
    /// cancellation path so the CTX gauge stops holding the PRIOR run's
    /// numbers after a Stop.
    ///
    /// **This is a single read, and that is a hard constraint, not a
    /// preference.** It exists downstream of #292, which killed a runs
    /// producer that fired ~60 requests over 2 minutes; implementations must
    /// issue exactly one request, never retry, and never start a loop or a
    /// producer Task. Returns the run's usage when the status object carries
    /// one; `nil` on every other outcome — transport failure, a 404 for an
    /// already-reaped run, a body with no `usage` block, or a plane with no
    /// runs endpoint. The caller renders `nil` as honestly unknown (#215 /
    /// #180 instrument honesty), never as the previous run's number.
    ///
    /// The default is `nil` for the same reason `activeRunID` defaults to
    /// nil: no runs plane, nothing to read.
    func finalRunUsage(runID: String) async -> TokenUsage?

    /// #304 (Phase 3 slice 3B): answer a HOST approval parked on a `/v1/runs`
    /// run — `POST /v1/runs/{run_id}/approval {"choice": …}`. Declared beside
    /// `hardStopActiveRun()` because it is the same seam shape: a run-scoped
    /// server command, forwarded `primary`-only by `ResilientHermesClient`
    /// and by routing lock in `ChatBackendRouter`.
    ///
    /// Two deliberate differences from the stop:
    /// - **The address rides the CALL, not client state.** `runID` and the
    ///   run's frozen `endpoint` come from the `RunApprovalRequest` VALUE the
    ///   stream frame minted — never from `activeRunContext`, whose single
    ///   slot is cleared on terminal exit and can name a different run by the
    ///   time a human answers (the #285 trap, dispatch §9).
    /// - **Not fire-and-forget.** The classified outcome is the card's whole
    ///   truth: only a 2xx is success, every 4xx renders distinctly (bar
    ///   304-C), and a transport failure keeps the card LIVE (#264's rule).
    ///   The POST reaching the host is what makes a state true (#279's
    ///   discipline) — callers mutate nothing until this returns.
    ///
    /// The default is `.unsupported`: a client with no runs plane (mock /
    /// relay / the on-device brain) has nothing to answer on.
    func answerApproval(runID: String, choice: String, endpoint: SessionsHermesClient.ResolvedEndpoint) async -> RunApprovalAnswerOutcome

    /// #78: the consumer TRUNCATED the thread (regenerate, edit-and-resend)
    /// and this conversation is now the whole of it. Every client that keeps
    /// its own mirror in `currentConversation` must adopt it here.
    ///
    /// Not optional politeness — ChatStore treats a client's mirror as an
    /// authoritative refresh source and merges it back over the rendered
    /// transcript at the end of every turn, on every ~2s poll tick, and on
    /// the streaming fallback path. `mergeConversationMetadata` takes the
    /// refresh source as the BASE ordering, so a mirror that still holds the
    /// removed rows restores them IN PLACE and leaves the regenerated reply
    /// stranded at the tail — the whole of #78's device symptom.
    ///
    /// The default is a no-op for mirror-less clients.
    func adoptTruncatedConversation(_ conversation: Conversation)
}

extension HermesClientProtocol {
    // Default no-ops so model-less clients (mock / legacy relay) conform without
    // change. Model-capable clients (SessionsHermesClient) and the resilient
    // wrapper override these. Declaring them as requirements above (not just here)
    // keeps dynamic dispatch through `any HermesClientProtocol` intact.
    func availableModels() async throws -> [String] { [] }
    func switchModel(_ identifier: String) async throws -> String? { nil }
    func listSessions() async throws -> [HermesSessionInfo] { [] }
    func openSession(_ id: String) async throws -> Conversation { await loadConversation() }
    func reconcileFromServer() async -> Conversation? { nil }
    // #295: `false` — see the requirement's doc above. A client with a real
    // server-recoverable plane (`ChatBackendRouter`, `SessionsHermesClient`)
    // overrides this explicitly rather than relying on the default.
    var currentRunIsServerRecoverable: Bool { false }
    func abandonActiveRun() {}
    // #328 route 2: `false` — this default IS the swallowed Stop. A client
    // with nothing to interrupt server-side (mock / relay / the on-device
    // brain) sends no request, and now says so instead of returning Void and
    // letting the caller assume otherwise.
    @discardableResult
    func hardStopActiveRun() -> Bool { false }
    // #322: no runs plane, so no run id and nothing to read a final status
    // from. Both defaults are the honest absence the caller renders as an
    // unknown gauge — never a fabricated zero and never the prior number.
    var activeRunID: String? { nil }
    // #357 (3C): no runs plane, so no run to steer — the honest absence.
    // `SessionsHermesClient` overrides with the real POST; the router
    // forwards by routing lock.
    func steerActiveRun(text: String) async -> SteerSubmitOutcome { .noActiveRun }
    func finalRunUsage(runID: String) async -> TokenUsage? { nil }
    // #304: no runs plane to answer on — the honest dead end, never a fake
    // success. `SessionsHermesClient` overrides with the real POST;
    // `ResilientHermesClient`/`ChatBackendRouter` override to forward.
    func answerApproval(runID: String, choice: String, endpoint: SessionsHermesClient.ResolvedEndpoint) async -> RunApprovalAnswerOutcome { .unsupported }
    func adoptTruncatedConversation(_ conversation: Conversation) {}
}
