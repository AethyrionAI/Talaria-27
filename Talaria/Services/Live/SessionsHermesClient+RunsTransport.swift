import Foundation
import os

/// This file's logger. Deliberately NOT the client's own `private static let
/// logger` — that one is file-scoped to `SessionsHermesClient.swift` — and
/// deliberately the same subsystem/category, so runs-plane lines land in the
/// same Console filter as the sessions-plane ones they replace.
private let runsTransportLogger = Logger(subsystem: "org.aethyrion.talaria", category: "SessionsHermesClient")

// Phase 3 slice 3A (#283): the runs-plane turn transport. Wire contract and
// probe evidence: design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md §2,
// planning/superpowers/research/251-phase3-gap/I-3a0-persistence-attachment-probe.md.
extension SessionsHermesClient {
    struct RunsTurnBody: Encodable {
        struct HistoryEntry: Encodable {
            let role: String
            let content: String
        }

        enum RunsTurnInput: Encodable {
            case text(String)
            /// Attachment turns: the 3A-0 probe proved a bare parts array 400s
            /// on /v1/runs ("No user message found in input") while the
            /// single-user-message wrap reaches the agent with the image intact.
            case userParts([ChatTurnBody.ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text):
                    try container.encode(text)
                case .userParts(let parts):
                    try container.encode([RunsInputMessage(parts: parts)])
                }
            }
        }

        private struct RunsInputMessage: Encodable {
            let parts: [ChatTurnBody.ContentPart]
            private enum CodingKeys: String, CodingKey { case role, content }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("user", forKey: .role)
                try container.encode(parts, forKey: .content)
            }
        }

        let input: RunsTurnInput
        let sessionID: String
        let conversationHistory: [HistoryEntry]
        let provider: String?
        let model: String?

        private enum CodingKeys: String, CodingKey {
            case input, provider, model
            case sessionID = "session_id"
            case conversationHistory = "conversation_history"
        }

        // Nonisolated logger — same shape as `ChatTurnBody`'s: the enclosing
        // client is @MainActor, but this nested value type isn't.
        private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "SessionsHermesClient")

        static func make(
            message: String,
            attachments: [PendingAttachment],
            sessionID: String,
            history: [HistoryEntry],
            selection: ModelSelection?
        ) -> RunsTurnBody {
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

            let input: RunsTurnInput
            if assembly.parts.isEmpty {
                input = .text(message)
            } else {
                input = .userParts(assembly.parts.map { part in
                    switch part {
                    case .text(let text): ChatTurnBody.ContentPart.text(text)
                    case .imageDataURL(let dataURL): ChatTurnBody.ContentPart.imageURL(dataURL: dataURL)
                    }
                })
            }
            return RunsTurnBody(
                input: input,
                sessionID: sessionID,
                conversationHistory: history,
                provider: selection?.provider,
                model: selection?.modelID
            )
        }
    }

    // MARK: - Runs-plane frame parser (Task 2, #283)

    /// One parsed runs-plane SSE frame. Cases mirror the event names the
    /// `/v1/runs` stream emits; `.ignored` covers frame types the app
    /// receives but does not yet act on.
    enum RunsEvent: Equatable {
        case messageDelta(String)
        case toolStarted(name: String, preview: String?)
        case toolCompleted(name: String, error: String?)
        case reasoning(String)
        case runCompleted(output: String, rawJSON: String)
        case runFailed(error: String)
        case runCancelled
        case ignored(String)
    }

    /// Parses one runs-plane SSE frame.
    ///
    /// **Load-bearing dialect note:** the runs stream has NO `event:` lines —
    /// every frame is a single `data: {json}` line carrying the event name
    /// INSIDE the JSON under `"event"`, and `bytes.lines` swallows the blank
    /// separators between frames. So the runs-plane read loop must dispatch
    /// on EVERY `data:` line immediately, unlike the sessions-plane parser
    /// (`SessionsHermesClient`'s main SSE loop), which buffers content until
    /// the NEXT `event:` line flushes it. Reusing that flush-on-next-`event:`
    /// strategy here would buffer forever, since this dialect never sends one.
    ///
    /// `jsonPayload` is the JSON text after `data: `. Returns `nil` for
    /// payloads that aren't a JSON object or carry no string `"event"` key;
    /// returns `.ignored(name)` for both known-but-unused event names
    /// (`approval.request`, `approval.responded`, `subagent.start`,
    /// `subagent.complete`) and any other event name this parser doesn't
    /// otherwise recognize — forward-tolerant of new event types the way the
    /// rest of this client's SSE parsing is (see `decodeJSONString`,
    /// `thinkingDelta(fromToolProgress:)`).
    nonisolated static func parseRunsFrame(_ jsonPayload: String) -> RunsEvent? {
        guard let data = jsonPayload.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = payload["event"] as? String
        else { return nil }

        switch name {
        case "message.delta":
            guard let delta = payload["delta"] as? String else { return nil }
            return .messageDelta(delta)
        case "tool.started":
            guard let toolName = payload["tool"] as? String else { return nil }
            return .toolStarted(name: toolName, preview: payload["preview"] as? String)
        case "tool.completed":
            guard let toolName = payload["tool"] as? String else { return nil }
            return .toolCompleted(name: toolName, error: payload["error"] as? String)
        case "reasoning.available":
            guard let text = payload["text"] as? String else { return nil }
            return .reasoning(text)
        case "run.completed":
            return .runCompleted(output: (payload["output"] as? String) ?? "", rawJSON: jsonPayload)
        case "run.failed":
            return .runFailed(error: (payload["error"] as? String) ?? "")
        case "run.cancelled":
            return .runCancelled
        default:
            // Known-but-unused (approval.*, subagent.*) and any unrecognized
            // future event name both land here — a valid frame the app
            // chooses not to act on, distinct from an unparseable one.
            return .ignored(name)
        }
    }

    // MARK: - Runs-plane turn driver (Task 4, #283)

    /// The runs plane's root path. `POST` submits, `GET {id}` polls status,
    /// `GET {id}/events` streams.
    static let runsPath = "/v1/runs"

    /// `POST /v1/runs` → `202 {"run_id":…,"status":"started"}`
    /// (`api_server.py:6700`). The id is the handle for the event stream, the
    /// status poll, `/stop` and `/approval`.
    struct RunSubmitResponse: Decodable {
        let runID: String
        private enum CodingKeys: String, CodingKey { case runID = "run_id" }
    }

    /// One read of `GET /v1/runs/{id}` — the pollable status object the
    /// gateway retains for `_RUN_STATUS_TTL` (3600s, `api_server.py:6187`).
    /// This, not stream replay, is what survives a dropped connection: the
    /// event queue is popped on disconnect (`:6765-6766`), so a reconnect
    /// 404s and every delta after the drop is gone, while `status` + `output`
    /// + `usage` stay readable for an hour (plan §1.6 N2).
    struct RunStatusSnapshot: Sendable {
        let status: String
        let output: String?
        let error: String?
        /// The whole status body, kept so `decodeRunUsage` can read its
        /// top-level `usage` block — the same Anthropic-style keys the
        /// `run.completed` frame carries.
        let rawJSON: String

        /// The gateway's own LIVE set (`api_server.py:1525`). Written as a
        /// negative on purpose: a status name we have never seen must read as
        /// terminal, or a future rename parks the poll forever.
        static let liveStatuses: Set<String> = ["queued", "running", "waiting_for_approval", "stopping"]

        var isTerminal: Bool { !Self.liveStatuses.contains(status) }

        /// Tolerant by construction — an unparseable body or a payload with no
        /// string `status` is "no snapshot", never a throw.
        init?(_ data: Data) {
            guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let status = payload["status"] as? String
            else { return nil }
            self.status = status
            self.output = payload["output"] as? String
            self.error = payload["error"] as? String
            self.rawJSON = String(decoding: data, as: UTF8.self)
        }
    }

    /// One streamed turn over the runs plane: submit, subscribe, decode.
    ///
    /// Yields into the SAME `AsyncStream<StreamingUpdate>` contract
    /// `streamTurn` uses, so `ChatStore` cannot tell the planes apart — that
    /// is the whole point of the slice, and it is what makes the Developer
    /// switch a real A/B rather than a fork.
    ///
    /// Differences from the sessions driver, each forced by the wire and none
    /// of them papered over:
    /// - **No `allowStaleHopRetry`.** The submit does not hit
    ///   `/api/sessions/{id}/…`, so a 404 there is a server error, not an
    ///   expired hop — it surfaces as `.failed`.
    /// - **No `.artifactProduced`, ever.** The runs `tool.started` carries no
    ///   `args` (`api_server.py:6222-6229`), so #21 Tier 1 reconstruction has
    ///   no source here. Honest absence beats a chip that cannot be opened.
    /// - **No `.modelResolved`.** The runs `run.completed` carries no
    ///   `runtime` block; inventing one would be a fabricated attribution.
    /// - **History rides the body** (N4: runs WRITE the session transcript but
    ///   never READ it).
    ///
    /// Exactly-once discipline: `finishedYielded` guards a single terminal
    /// yield (`.finished` OR `.failed` OR `.interrupted`) per turn, and every
    /// exit path finishes the continuation.
    func streamTurnViaRuns(
        message content: String,
        attachments: [PendingAttachment],
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async {
        var capturedSessionId = ""
        var runID: String?
        // The run is COMMITTED the moment the submit returns an id — from
        // there a dropped connection is recoverable, never re-queueable
        // (#240: parking an accepted turn re-sends it and Hermes answers
        // twice).
        var runSubmitted = false
        var streamOpened = false
        var finishedYielded = false
        var assembledContent = ""
        var assembledReasoning = ""
        defer { continuation.finish() }

        do {
            let hop = try await ensureHopForTurn()
            capturedSessionId = hop.sessionId
            // P1 (#90): the transplant just happened, before this turn hits
            // the wire — surface its cost so the receipts stay honest. The
            // priming turn itself deliberately stays on the SESSIONS plane in
            // 3A: it is hop SETUP, not the turn transport being migrated.
            if let priming = hop.priming {
                continuation.yield(.contextPrimed(priming.usage))
            }

            // N4 (code-read then PROVEN 2026-08-07): a run WRITES its turn into
            // the session row but never READS it, so the thread's context has
            // to ride the submit body. Server truth is current precisely
            // because of that write half.
            //
            // A failure here is NOT swallowed: a contextless turn does not
            // fail loudly, it answers plausibly from long-term memory — the
            // exact shape the probe caught. Better a visible error the user
            // can retry. Known gap, named rather than hidden: the sessions
            // plane re-hops a 404 on a REUSED hop and this path has no
            // stale-hop retry in 3A, so an expired persisted hop surfaces as
            // `.failed` here where the sessions plane would recover.
            let history = try await fetchRunsHistory(
                sessionId: hop.sessionId,
                profileID: hop.profileID,
                excludingTrailing: content
            )

            let submit: RunSubmitResponse = try await postJSON(
                path: Self.runsPath,
                body: RunsTurnBody.make(
                    message: content,
                    attachments: attachments,
                    sessionID: hop.sessionId,
                    history: history,
                    selection: modelSelection
                ),
                profileID: hop.profileID
            )
            // Task 7 promotes this to `activeRunContext` (what `/stop` and
            // `/approval` address).
            let acceptedRunID = submit.runID
            runID = acceptedRunID
            runSubmitted = true

            // Subscribe IMMEDIATELY: the handler tolerates a short
            // registration race (`api_server.py:6730`), and every event
            // emitted before we attach is gone — the queue has no replay.
            let eventsRequest = try makeRequest(
                path: "\(Self.runsPath)/\(acceptedRunID)/events",
                method: "GET",
                body: nil,
                accept: "text/event-stream",
                profileID: hop.profileID
            )
            let (bytes, response) = try await session.bytes(for: eventsRequest)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                // The run is already committed, so this is a RECOVERY case,
                // never a re-send: fall to the status poll, and when the run
                // has not finished yet hand off to the same `.interrupted`
                // machinery a dropped sessions stream uses.
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                runsTransportLogger.notice(
                    "runs: event subscribe for \(acceptedRunID, privacy: .public) returned \(code) — polling status"
                )
                finishedYielded = await deliverPolledTerminal(
                    runID: acceptedRunID,
                    hop: hop,
                    assembledContent: assembledContent,
                    assembledReasoning: assembledReasoning,
                    into: continuation
                )
                if !finishedYielded {
                    continuation.yield(.interrupted(sessionId: hop.sessionId, runId: acceptedRunID))
                    finishedYielded = true
                }
                return
            }
            streamOpened = true
            connectionStatus = .connected

            // #246: silence past the threshold THROWS out of this loop and the
            // catch below classifies it like any post-submit drop
            // (`.interrupted`). The guard wraps only the post-2xx byte stream,
            // so pre-response failures keep their unreachable/failed semantics.
            for try await line in Self.stallGuardedLines(bytes.lines, threshold: streamStallThreshold) {
                if Task.isCancelled { break }
                if line.hasPrefix(":") { continue }
                guard line.hasPrefix("data:") else { continue }
                // Dialect (see `parseRunsFrame`): NO `event:` lines, so every
                // `data:` line is a whole frame and dispatches IMMEDIATELY.
                // The sessions loop's flush-on-next-`event:` strategy would
                // buffer forever here.
                var payload = String(line.dropFirst(5))
                if payload.hasPrefix(" ") { payload.removeFirst() }
                guard let event = Self.parseRunsFrame(payload) else { continue }

                switch event {
                case .messageDelta(let delta):
                    guard !delta.isEmpty else { continue }
                    assembledContent += delta
                    continuation.yield(.textDelta(delta))
                case .reasoning(let text):
                    // Same increment-vs-snapshot hedge the sessions
                    // `_thinking` path applies — the runs channel's wire mode
                    // is no better verified than that one.
                    if let delta = Self.incrementalReasoningDelta(from: text, assembled: assembledReasoning) {
                        assembledReasoning += delta
                        continuation.yield(.reasoningDelta(delta))
                    }
                case .toolStarted(let name, let preview):
                    continuation.yield(.toolActivity(ToolCallEvent(name: name, phase: .started, detail: preview)))
                    // Deliberately nothing else: no `args`, so no Tier 1
                    // reconstruction and no path harvest from the payload.
                case .toolCompleted(let name, _):
                    continuation.yield(.toolActivity(ToolCallEvent(name: name, phase: .completed, detail: nil)))
                case .runCompleted(let output, let rawJSON):
                    let usage = Self.decodeRunUsage(rawJSON)
                    // #25: the resumed session's CTX numerator. Tolerant —
                    // absent usage records nothing and the session stays
                    // honestly unknown.
                    if let usage {
                        usageIndex?.record(sessionID: hop.sessionId, usage: usage)
                    }
                    let message = runsFinalMessage(
                        output: output,
                        assembledContent: assembledContent,
                        assembledReasoning: assembledReasoning,
                        profileID: hop.profileID
                    )
                    continuation.yield(.finished(message, usage, nil))
                    finishedYielded = true
                case .runFailed(let error):
                    connectionStatus = .error
                    continuation.yield(.failed(Self.runFailureText(error)))
                    finishedYielded = true
                case .runCancelled:
                    // Task 7 adds the client-initiated-stop flag, which ends
                    // a user's own stop silently. Until then every cancel is
                    // treated as someone else's — recovery, not failure.
                    continuation.yield(.interrupted(sessionId: hop.sessionId, runId: acceptedRunID))
                    finishedYielded = true
                case .ignored:
                    continue
                }
                if finishedYielded { break }
            }

            if !finishedYielded {
                // Clean close with no terminal frame. Task 6 replaces this
                // with the bounded poll loop; the single-read seam already
                // resolves the common case where the run finished while the
                // stream was dying, and anything else arms the #235 recovery
                // machinery exactly as a dropped sessions stream does.
                finishedYielded = await deliverPolledTerminal(
                    runID: acceptedRunID,
                    hop: hop,
                    assembledContent: assembledContent,
                    assembledReasoning: assembledReasoning,
                    into: continuation
                )
                if !finishedYielded {
                    continuation.yield(.interrupted(sessionId: hop.sessionId, runId: acceptedRunID))
                    finishedYielded = true
                }
            }
        } catch {
            connectionStatus = .error
            runsTransportLogger.warning("runs-plane turn failed: \(error.localizedDescription, privacy: .public)")
            // Defensive: nothing after a terminal yield can throw today, but
            // the exactly-once rule is stated here rather than inferred.
            guard !finishedYielded else { return }
            if runSubmitted || streamOpened {
                // Accepted server-side — the run keeps going without us.
                continuation.yield(.interrupted(sessionId: capturedSessionId, runId: runID))
            } else if Self.isUnreachableError(error) {
                // Never reached the host: queueable in the offline compose
                // outbox (#90), not a dead end.
                continuation.yield(.unreachable(failureMessage(for: error)))
            } else {
                continuation.yield(.failed(failureMessage(for: error)))
            }
            finishedYielded = true
        }
    }

    // MARK: - History pre-fetch (N4)

    /// The conversation history a run must be handed, read from server truth.
    ///
    /// `excludingTrailing` is the turn about to be sent: ChatStore's
    /// optimistic row is client-side only, so the server should not be
    /// carrying it yet — but a re-send (or a server that raced the write)
    /// would put it at the tail, and shipping it twice reads to the agent as
    /// the user repeating themselves.
    func fetchRunsHistory(
        sessionId: String,
        profileID: UUID?,
        excludingTrailing outgoing: String = ""
    ) async throws -> [RunsTurnBody.HistoryEntry] {
        let (_, conversation) = try await fetchSessionConversation(sessionId, profileID: profileID)
        return Self.runsHistory(from: conversation.messages, excludingTrailing: outgoing)
    }

    /// Pure mapping half of the pre-fetch. Prose strings only — the server
    /// coerces history content with `str()` (`api_server.py:6360-6370`), so a
    /// structured value would arrive as its Python repr.
    nonisolated static func runsHistory(
        from messages: [Message],
        excludingTrailing outgoing: String
    ) -> [RunsTurnBody.HistoryEntry] {
        var entries: [RunsTurnBody.HistoryEntry] = []
        for message in messages {
            let role: String
            switch message.sender {
            case .user: role = "user"
            case .hermes: role = "assistant"
            default: continue   // system notices are ours, not the thread's
            }
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            entries.append(RunsTurnBody.HistoryEntry(role: role, content: text))
        }
        let trimmedOutgoing = outgoing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOutgoing.isEmpty,
           let last = entries.last,
           last.role == "user",
           last.content == trimmedOutgoing {
            entries.removeLast()
        }
        return entries
    }

    // MARK: - Status poll (the Task 6 seam)

    /// Reads `GET /v1/runs/{id}` and returns the snapshot only when the run
    /// has reached a terminal status.
    ///
    /// **Task 6 owns the LOOP.** What lands here is the honest degenerate
    /// case — ONE read, terminal-or-nil — so the loss paths call the real
    /// recovery entry point from day one instead of a stub that would have to
    /// be re-plumbed. A still-running run returns nil today and the caller
    /// falls through to `.interrupted`, which is exactly what the sessions
    /// plane does with a dropped stream.
    func pollRunToTerminal(runID: String, profileID: UUID?) async -> RunStatusSnapshot? {
        do {
            let request = try makeRequest(
                path: "\(Self.runsPath)/\(runID)",
                method: "GET",
                body: nil,
                accept: "application/json",
                profileID: profileID
            )
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode),
                  let snapshot = RunStatusSnapshot(data),
                  snapshot.isTerminal
            else { return nil }
            return snapshot
        } catch {
            runsTransportLogger.warning(
                "runs: status poll for \(runID, privacy: .public) failed — \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Polls once and, if the run is terminal, delivers this turn's single
    /// terminal yield from the status object. Returns whether it did.
    private func deliverPolledTerminal(
        runID: String,
        hop: PreparedHop,
        assembledContent: String,
        assembledReasoning: String,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async -> Bool {
        guard let snapshot = await pollRunToTerminal(runID: runID, profileID: hop.profileID) else {
            return false
        }
        switch snapshot.status {
        case "completed":
            let output = snapshot.output ?? ""
            // #235 F1, the SAME guard the sessions plane applies to a clean
            // close (`cleanCloseArmsRecovery`, applied at
            // `SessionsHermesClient.swift:521-531`) — reused, not restated, so
            // the two planes cannot drift on it. A terminal status with no
            // answer text anywhere paints an EMPTY bubble and suppresses all
            // recovery; it must arm `.interrupted` instead. `runStarted: true`
            // is the truth here by construction: we are holding a run id.
            let effectiveContent = output.isEmpty ? assembledContent : output
            guard !Self.cleanCloseArmsRecovery(runStarted: true, effectiveContent: effectiveContent) else {
                runsTransportLogger.notice(
                    "runs: status 'completed' for \(runID, privacy: .public) carried no answer text — arming recovery, not an empty bubble"
                )
                continuation.yield(.interrupted(sessionId: hop.sessionId, runId: runID))
                return true
            }
            let usage = Self.decodeRunUsage(snapshot.rawJSON)
            if let usage {
                usageIndex?.record(sessionID: hop.sessionId, usage: usage)
            }
            let message = runsFinalMessage(
                output: output,
                assembledContent: assembledContent,
                assembledReasoning: assembledReasoning,
                profileID: hop.profileID
            )
            continuation.yield(.finished(message, usage, nil))
        case "failed":
            connectionStatus = .error
            continuation.yield(.failed(Self.runFailureText(snapshot.error ?? "")))
        default:
            // `cancelled`, `stopped`, or a terminal status name this build
            // does not know: the run is over and there is no answer to show,
            // so it is recovery, not a failure claim.
            continuation.yield(.interrupted(sessionId: hop.sessionId, runId: runID))
        }
        return true
    }

    // MARK: - Terminal message assembly

    /// The final `Message` a terminal run delivers — shared by the
    /// `run.completed` frame and the status poll so the two can never drift.
    private func runsFinalMessage(
        output: String,
        assembledContent: String,
        assembledReasoning: String,
        profileID: UUID?
    ) -> Message {
        var message = Message(
            sender: .hermes,
            // `output` is the authoritative answer; the streamed deltas are
            // the fallback for a terminal payload that carries none (the
            // sessions plane's `?? assembledContent` shape).
            content: output.isEmpty ? assembledContent : output,
            status: .delivered
        )
        // #60: the runs plane has no structured per-message transcript to
        // prefer, so the assembled `reasoning.available` text is the only
        // candidate — and it attaches only when it isn't the upstream
        // answer-mirror.
        if !assembledReasoning.isEmpty,
           !Self.reasoningMirrorsAnswer(assembledReasoning, content: message.content) {
            message.reasoning = assembledReasoning
        }
        // #21 Tier 2, PROSE half only. The runs `tool.started` carries no
        // `args`, so nothing may be harvested from a tool payload here — a
        // chip minted from a `preview` would be a claim we cannot honor. The
        // assistant's own answer is a different source and still counts.
        let fetchables = Self.fetchableAgentFileAttachments(
            announcedPaths: Self.agentFilesRelativePaths(in: message.content),
            existing: [],
            profileID: profileID
        )
        if !fetchables.isEmpty { message.attachments = fetchables }
        return message
    }

    /// User-facing text for a failed run: the host's own reason when it gave
    /// one, else an honest generic. Never invents a cause.
    nonisolated static func runFailureText(_ error: String) -> String {
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "The Hermes run failed." : trimmed
    }
}
