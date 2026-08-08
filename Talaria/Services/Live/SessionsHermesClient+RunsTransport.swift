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

            // Review of #279 (2026-08-07), LOG ONLY — no trimming: trimming what
            // history the agent sees is a behavioral decision, filed separately.
            // `AttachmentInlining.aggregateAttachmentBudget` (900 KB) was sized
            // against attachment parts alone, before the runs plane existed; on
            // the sessions plane the transcript lives server-side and never rides
            // the wire at all, so `conversationHistory` below ships on top of
            // that budget UNCOUNTED — new wire behavior with no measured
            // distribution yet. This is instrumentation so a device pass can
            // measure how often, and by how much, real turns cross the figure
            // the attachment budget was sized against.
            let historyBytes = history.reduce(0) { $0 + $1.role.utf8.count + $1.content.utf8.count }
            let attachmentPayloadBytes = assembly.parts.reduce(0) { total, part in
                switch part {
                case .text(let text): return total + text.utf8.count
                case .imageDataURL(let dataURL): return total + dataURL.utf8.count
                }
            }
            if historyBytes + attachmentPayloadBytes > AttachmentInlining.aggregateAttachmentBudget {
                Self.logger.warning(
                    "runs turn body: history \(historyBytes, privacy: .public) bytes + attachment payload \(attachmentPayloadBytes, privacy: .public) bytes exceeds the \(AttachmentInlining.aggregateAttachmentBudget, privacy: .public)-byte figure the attachment budget was sized against (history message count \(history.count, privacy: .public)) — instrumentation only, no trimming"
                )
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
    /// - **The stale-hop retry guards the HISTORY read, not the submit.** The
    ///   submit does not hit `/api/sessions/{id}/…`, so a 404 there is a real
    ///   server error; the pre-fetch does, and a persisted hop whose server
    ///   session expired 404s exactly there (N4 makes that read mandatory).
    ///   `allowStaleHopRetry` therefore means the same thing it means on the
    ///   sessions plane — re-hop ONCE, with a transplant, then give up — and
    ///   it uses the same `discardStaleHop()` + `ensureHopForTurn()` pieces.
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
        into continuation: AsyncStream<StreamingUpdate>.Continuation,
        allowStaleHopRetry: Bool = true
    ) async {
        var capturedSessionId = ""
        // Captured alongside the session id so the catch path — which is
        // reached without the `PreparedHop` in scope — can still address the
        // right host for the recovery poll (M-5: a session's requests resolve
        // from its BIRTH profile, never the active one).
        var capturedProfileID: UUID?
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
        // Task 7: the single choke point for every exit path (normal return
        // OR the catch below, since this whole function body sits inside the
        // `defer`'s scope) — whichever run THIS call submitted stops being
        // addressable the moment the turn is over. `clearActiveRunContext`
        // no-ops harmlessly if `hardStopActiveRun()` already cleared it (a
        // stop that lands while terminal delivery is in flight), and
        // `consumeSelfStopped` is drained here too so the flag never
        // outlives the run it was stamped for.
        defer {
            if let runID {
                clearActiveRunContext(matchingRunID: runID)
                _ = consumeSelfStopped(runID: runID)
            }
            continuation.finish()
        }

        do {
            let hop = try await ensureHopForTurn()
            capturedSessionId = hop.sessionId
            capturedProfileID = hop.profileID
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
            // can retry.
            //
            // Except for the ONE failure that is not the server's fault: a
            // persisted hop whose session the host has since pruned 404s here,
            // and that is a stale HANDLE, not a missing conversation. Same
            // response the sessions plane makes (`streamTurn`'s
            // `allowStaleHopRetry`) and the same two pieces — drop the handle,
            // re-run the turn setup once on a fresh transplanted hop. The run
            // has NOT been submitted at this point, so the retry cannot
            // double-send (#240).
            //
            // A brand-new, never-used session is NOT one of those failures:
            // probe-verified 2026-08-07 (I-3a0-persistence-attachment-probe.md,
            // N4 addendum) that `GET …/messages` on a session nobody has ever
            // turned returns `200` with an empty `data` array, not `404` — so a
            // fresh install's very first turn hits this pre-fetch safely and
            // needs no special-casing.
            let history: [RunsTurnBody.HistoryEntry]
            do {
                history = try await fetchRunsHistory(
                    sessionId: hop.sessionId,
                    profileID: hop.profileID,
                    excludingTrailing: content
                )
            } catch SessionsClientError.sessionNotFound where hop.wasReused && allowStaleHopRetry {
                runsTransportLogger.notice(
                    "runs turn: persisted hop stale server-side (404 on the history read) — re-hopping with transplant"
                )
                discardStaleHop()
                await streamTurnViaRuns(
                    message: content,
                    attachments: attachments,
                    into: continuation,
                    allowStaleHopRetry: false
                )
                return
            }

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
            let acceptedRunID = submit.runID
            runID = acceptedRunID
            runSubmitted = true
            // Task 7: promoted to client state — this is what `/stop` (and a
            // future `/approval`) address. Set as soon as the run is
            // committed server-side, not merely accepted for submission,
            // because that is the earliest moment a stop request means
            // anything.
            setActiveRunContext(runID: acceptedRunID, profileID: hop.profileID)

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
                    sessionId: hop.sessionId,
                    profileID: hop.profileID,
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
                    // Task 7: a run WE stopped (`hardStopActiveRun()`) ends
                    // SILENTLY here — no `.interrupted` — because ChatStore
                    // already tore down its own UI state the moment the user
                    // tapped Stop; announcing recovery for a cancel we asked
                    // for would be a second, unwanted teardown. Anyone
                    // else's cancel (server-side, another client) still arms
                    // recovery exactly as before.
                    if consumeSelfStopped(runID: acceptedRunID) {
                        runsTransportLogger.notice(
                            "runs: \(acceptedRunID, privacy: .public) cancelled — self-stopped, ending silently"
                        )
                    } else {
                        continuation.yield(.interrupted(sessionId: hop.sessionId, runId: acceptedRunID))
                    }
                    finishedYielded = true
                case .ignored:
                    continue
                }
                if finishedYielded { break }
            }

            if !finishedYielded {
                // Clean close with no terminal frame: the bounded poll is the
                // recovery, resolving both the common case (the run finished
                // while the stream was dying) and the slower one (it finishes
                // within the budget). Anything else arms the #235 machinery
                // exactly as a dropped sessions stream does.
                finishedYielded = await deliverPolledTerminal(
                    runID: acceptedRunID,
                    sessionId: hop.sessionId,
                    profileID: hop.profileID,
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
            if let acceptedRunID = runID, runSubmitted {
                // Accepted server-side, so this is a RECOVERY case and never
                // a re-send. The stream is gone but the status object is not:
                // poll it before degrading, because the answer this turn was
                // waiting for may already exist (3A-B). `Task.isCancelled`
                // makes the poll a no-op, so a stopped consumer costs nothing.
                finishedYielded = await deliverPolledTerminal(
                    runID: acceptedRunID,
                    sessionId: capturedSessionId,
                    profileID: capturedProfileID,
                    assembledContent: assembledContent,
                    assembledReasoning: assembledReasoning,
                    into: continuation
                )
                if !finishedYielded {
                    continuation.yield(.interrupted(sessionId: capturedSessionId, runId: acceptedRunID))
                }
            } else if runSubmitted || streamOpened {
                // A submit that returned no id, or a stream opened without
                // one: still committed server-side, but with no handle to
                // poll. The run keeps going without us.
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

    // MARK: - The sync turn (Task 6)

    /// One NON-streamed turn over the runs plane — the `send(...)` path
    /// (Ask-Hermes intents, widgets, anything that wants an answer rather than
    /// a stream).
    ///
    /// **There is no sync runs endpoint**, so submit + poll IS the sync path:
    /// `POST /v1/runs` returns a 202 with an id, and the answer only ever
    /// appears on the event stream or the status object. Polling is the honest
    /// one for a caller holding no continuation.
    ///
    /// Bounded by `runsSyncBudget` (20s, #145 Part A's non-stream ceiling),
    /// NOT by the streamed path's `runsPollBudget` — see both knobs' docs.
    ///
    /// Throws in every non-answer case, in the sessions sync path's style, so
    /// `send(...)`'s existing catch turns it into a `.system` failure message:
    /// a caller that got no answer must never be handed an empty success.
    /// A `sessionNotFound` from the history pre-fetch propagates deliberately
    /// — `performSyncTurn`'s stale-hop retry is what catches it.
    func syncTurnViaRuns(
        hop: PreparedHop,
        message: String,
        attachments: [PendingAttachment]
    ) async throws -> String {
        // N4: runs WRITE the session transcript but never READ it, so the
        // thread's context rides the submit body here exactly as it does on
        // the streamed path. Including on a session's first-ever turn: this
        // GET returns 200/[] on a never-used session, not 404 — see the note
        // at `streamTurnViaRuns`'s own `fetchRunsHistory` call above.
        let history = try await fetchRunsHistory(
            sessionId: hop.sessionId,
            profileID: hop.profileID,
            excludingTrailing: message
        )
        let submit: RunSubmitResponse = try await postJSON(
            path: Self.runsPath,
            body: RunsTurnBody.make(
                message: message,
                attachments: attachments,
                sessionID: hop.sessionId,
                history: history,
                selection: modelSelection
            ),
            profileID: hop.profileID
        )
        // Task 7: same promotion as the streamed path, so a stop issued
        // while a sync `send(...)` is in flight has something to address.
        // Cleared on every exit below via `defer` — the budget timeout, the
        // switch's throws, and its one successful return all go through it.
        setActiveRunContext(runID: submit.runID, profileID: hop.profileID)
        defer {
            clearActiveRunContext(matchingRunID: submit.runID)
            // The sync path has no continuation to silence (it throws or
            // returns a value, never yields `.interrupted`), but drains the
            // flag anyway so a stop issued mid-sync-turn never lingers in
            // the set past this call.
            _ = consumeSelfStopped(runID: submit.runID)
        }

        // `runsSyncBudget`, NOT `runsPollBudget`: a `send(...)` caller holds
        // no continuation, so there is no `.interrupted` to degrade to and
        // nothing to justify a two-minute wait. #145 Part A's non-stream
        // ceiling governs here, and the sessions `/chat` turn this replaces
        // was already capped at that same 20s by `requestTimeout(forAccept:)`.
        guard let snapshot = await pollRunToTerminal(
            runID: submit.runID,
            profileID: hop.profileID,
            budget: runsSyncBudget
        ) else {
            // Budget, 404 or cancellation. Giving up WATCHING is not the run
            // being lost: the submit was accepted, so the answer keeps being
            // produced and stays readable on the status object for the TTL
            // (1h). Say that, rather than implying the turn died — this path
            // has no `.interrupted` to arm, so the words are the whole
            // hand-off.
            throw SessionsClientError.requestFailed(
                "The Hermes run did not answer in time. It may still finish on the host — check the conversation shortly."
            )
        }

        switch snapshot.status {
        case "completed":
            let output = snapshot.output ?? ""
            // #235 F1's shape on the sync path: a "completed" run with no
            // answer text is not an answer. There is no recovery machinery
            // here, so it surfaces as a failure the user can retry rather
            // than an empty bubble.
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SessionsClientError.requestFailed(
                    "The Hermes run completed without producing an answer."
                )
            }
            // #25: the sync path's usage is real and rides the status object
            // (the sessions `/chat` response carries none) — record it so a
            // resumed session's CTX gauge has a numerator.
            if let usage = Self.decodeRunUsage(snapshot.rawJSON) {
                usageIndex?.record(sessionID: hop.sessionId, usage: usage)
            }
            return output
        case "failed":
            throw SessionsClientError.requestFailed(Self.runFailureText(snapshot.error ?? ""))
        default:
            // `cancelled`, `stopped`, or a terminal name this build does not
            // know. Never invents a cause.
            throw SessionsClientError.requestFailed(
                "The Hermes run ended as '\(snapshot.status)' without an answer."
            )
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

    // MARK: - Status poll (Task 6: the bounded loop)

    /// One read of the status endpoint, CLASSIFIED. The loop needs three
    /// answers Task 4's seam collapsed into a bare `nil`, and conflating them
    /// makes the loop wrong in both directions: a run that is merely still
    /// going has to keep the poll alive, a run the gateway no longer has must
    /// end it immediately, and a read that died in transport must be retried
    /// — one flaky GET is not evidence about the run at all.
    private enum RunStatusRead {
        case terminal(RunStatusSnapshot)
        /// Queued / running / waiting_for_approval / stopping — keep waiting.
        case live
        /// `404 run_not_found`: the status TTL (3600s) expired, or this id
        /// belongs to another host. No amount of polling produces an answer.
        case gone
        /// The read itself failed — transport error, non-404 HTTP error, or a
        /// body that is not a status object. Says nothing about the run.
        case unreadable(String)
    }

    /// How many CONSECUTIVE unreadable reads the poll tolerates before giving
    /// up early. One flaky GET must not kill a recovery; a host that answers
    /// nothing but garbage is not going to start, and burning the whole
    /// budget on it only delays the `.interrupted` hand-off. Reset by any
    /// successful read, so intermittent failures never accumulate.
    private static let runsPollUnreadableLimit = 3

    /// Polls `GET /v1/runs/{id}` until the run reaches a terminal status, and
    /// returns that snapshot — the recovery path's whole point.
    ///
    /// This, not stream replay, is what survives a dropped connection: the
    /// event queue is popped on disconnect (`api_server.py:6765-6766`) so a
    /// re-subscribe 404s and every delta after the drop is gone, while
    /// `status` + `output` + `usage` stay readable for an hour.
    ///
    /// Returns nil — the caller then arms `.interrupted`, the same hand-off a
    /// dropped sessions stream makes — when the run is still going at
    /// `runsPollBudget`, when the host 404s the id, when reads keep failing,
    /// or on cancellation. **Every one of those exits is bounded**: the loop
    /// cannot outlive the budget by more than one interval plus one read.
    ///
    /// `Task.isCancelled` exits silently: the consumer stopped, so there is
    /// nothing left to deliver an answer to.
    ///
    /// `budget` defaults to `runsPollBudget` — the STREAMED path's allowance,
    /// which is long because it degrades to `.interrupted` rather than making
    /// anyone wait. The sync path passes its own, much shorter
    /// `runsSyncBudget`: it has a user waiting on one answer and nothing to
    /// degrade to, so it lives under the #145 Part A non-stream policy.
    func pollRunToTerminal(
        runID: String,
        profileID: UUID?,
        budget: Duration? = nil
    ) async -> RunStatusSnapshot? {
        let deadline = ContinuousClock.now + (budget ?? runsPollBudget)
        var reads = 0
        var consecutiveUnreadable = 0

        while true {
            if Task.isCancelled { return nil }
            reads += 1
            switch await readRunStatus(runID: runID, profileID: profileID) {
            case .terminal(let snapshot):
                return snapshot
            case .live:
                consecutiveUnreadable = 0
            case .gone:
                runsTransportLogger.notice(
                    "runs: status poll for \(runID, privacy: .public) — host no longer has this run (404); arming recovery"
                )
                return nil
            case .unreadable(let reason):
                consecutiveUnreadable += 1
                runsTransportLogger.warning(
                    "runs: status read \(reads, privacy: .public) for \(runID, privacy: .public) failed — \(reason, privacy: .public)"
                )
                guard consecutiveUnreadable < Self.runsPollUnreadableLimit else {
                    runsTransportLogger.notice(
                        "runs: status poll for \(runID, privacy: .public) gave up after \(consecutiveUnreadable, privacy: .public) consecutive unreadable reads"
                    )
                    return nil
                }
            }

            guard ContinuousClock.now < deadline else {
                runsTransportLogger.notice(
                    "runs: status poll for \(runID, privacy: .public) exhausted its budget after \(reads, privacy: .public) reads — arming recovery"
                )
                return nil
            }
            do {
                try await Task.sleep(for: runsPollInterval)
            } catch {
                return nil   // cancelled mid-wait — the consumer is gone
            }
        }
    }

    /// One `GET /v1/runs/{id}`, classified. Never throws: every failure mode
    /// is a case the loop knows how to weigh.
    private func readRunStatus(runID: String, profileID: UUID?) async -> RunStatusRead {
        do {
            let request = try makeRequest(
                path: "\(Self.runsPath)/\(runID)",
                method: "GET",
                body: nil,
                accept: "application/json",
                profileID: profileID
            )
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unreadable("non-HTTP response")
            }
            // Only 404 is news ABOUT THE RUN. A 5xx is news about the host,
            // which may well pass — that is a retry, not a verdict.
            if httpResponse.statusCode == 404 { return .gone }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                return .unreadable("HTTP \(httpResponse.statusCode)")
            }
            guard let snapshot = RunStatusSnapshot(data) else {
                return .unreadable("status body carried no status field")
            }
            return snapshot.isTerminal ? .terminal(snapshot) : .live
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// Polls to terminal and, if it gets there, delivers this turn's single
    /// terminal yield from the status object. Returns whether the turn is
    /// now FULLY HANDLED — either a terminal yield was delivered, or (Task 7
    /// finding 1, below) a self-stopped run was silenced without one. Every
    /// call site's contract is "if this returns false, fall back to
    /// `.interrupted`" — so silencing has to happen HERE, in the one place
    /// all three fallback sites (subscribe-404, clean-close, the catch
    /// block's recovery poll) share, rather than three separate copies of
    /// the same check.
    ///
    /// Takes the session id and profile rather than the `PreparedHop` because
    /// the catch path reaches it holding only what it captured before the
    /// throw.
    private func deliverPolledTerminal(
        runID: String,
        sessionId: String,
        profileID: UUID?,
        assembledContent: String,
        assembledReasoning: String,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async -> Bool {
        guard let snapshot = await pollRunToTerminal(runID: runID, profileID: profileID) else {
            // Task 7 finding 1: the poll never reached a terminal snapshot —
            // budget exhausted, the host 404'd it (`gone`, already reaped),
            // or the unreadable-reads limit tripped. Every caller's fallback
            // for `false` is `.interrupted`, which is right for a stream
            // that merely dropped — but wrong for a run WE stopped: honoring
            // `/stop` can close the SSE with no `run.cancelled` frame, and
            // the host can reap the run before a poll ever catches it
            // `cancelled`. That shape must still end silently, exactly like
            // the terminal-snapshot `cancelled` arm below — just reached
            // from the "never went terminal" door instead of the "went
            // terminal as cancelled" one.
            if consumeSelfStopped(runID: runID) {
                runsTransportLogger.notice(
                    "runs: status poll for \(runID, privacy: .public) never resolved — self-stopped, ending silently"
                )
                return true
            }
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
                continuation.yield(.interrupted(sessionId: sessionId, runId: runID))
                return true
            }
            let usage = Self.decodeRunUsage(snapshot.rawJSON)
            if let usage {
                usageIndex?.record(sessionID: sessionId, usage: usage)
            }
            let message = runsFinalMessage(
                output: output,
                assembledContent: assembledContent,
                assembledReasoning: assembledReasoning,
                profileID: profileID
            )
            // The poll just completed a round trip and came back with an
            // answer — whatever killed the stream, the host is reachable.
            connectionStatus = .connected
            continuation.yield(.finished(message, usage, nil))
        case "failed":
            connectionStatus = .error
            continuation.yield(.failed(Self.runFailureText(snapshot.error ?? "")))
        default:
            // `cancelled`, `stopped`, or a terminal status name this build
            // does not know: the run is over and there is no answer to show.
            // Task 7: if WE stopped it (`hardStopActiveRun()`), that is the
            // self-initiated stop resolving and ends SILENTLY — otherwise
            // it's recovery, not a failure claim, exactly as before.
            if consumeSelfStopped(runID: runID) {
                runsTransportLogger.notice(
                    "runs: status poll for \(runID, privacy: .public) — '\(snapshot.status, privacy: .public)', self-stopped, ending silently"
                )
            } else {
                continuation.yield(.interrupted(sessionId: sessionId, runId: runID))
            }
        }
        return true
    }

    // MARK: - Stop (Task 7, #283 S23)

    /// The runs plane's REAL server-side interrupt. Before this, "Stop" only
    /// stopped the app listening (`ChatStore.cancelStreaming()` cancelling
    /// its own consumption `Task` + the router releasing its lock) while the
    /// host kept generating unattended (S24). This is what actually tells
    /// the host to stop.
    ///
    /// Reached through `ChatBackendRouter.hardStopActiveRun()` →
    /// `ResilientHermesClient.hardStopActiveRun()` → here — the protocol
    /// default (`HermesClientProtocol.swift`) is a no-op, so this override is
    /// what makes the forward do anything. `ChatStore.cancelStreaming
    /// (hardStopHost:)` is this method's ONE entry, and it fires only when
    /// that flag is `true` — the in-app Stop tap, Siri's Cancel via
    /// `AskHermesIntent`/`AskHermesLongRunSupport`. The continued-send
    /// expiration handler (the system revoking a background task's budget
    /// with NO user action) enters that SAME function, `hardStopHost:
    /// false`, so it never reaches here at all. The paths that never touch
    /// `cancelStreaming` in the first place — `abandonPendingRun`'s direct
    /// callers (a thread switch, clearing the conversation, `reset`) — call
    /// plain `abandonActiveRun()` instead, which stays a network-free no-op
    /// on this client: sessions-plane parity, so none of those walk-aways
    /// throw away an answer the write-half would otherwise have preserved.
    ///
    /// No-ops when nothing is active: a Stop tapped after the turn already
    /// finished (or on a backend that never had a run — the local brain)
    /// finds `activeRunContext` nil and sends no request. Otherwise it
    /// captures-and-clears the context immediately (so a second tap, or the
    /// terminal delivery racing this one, both see nil and no-op harmlessly —
    /// the UI teardown stays instant) and fires the POST fire-and-forget: the
    /// caller already tore down its own state and is not waiting on this.
    ///
    /// **`markSelfStopped` fires only once the POST has actually reached the
    /// host** (review of #279, 2026-08-07) — moved here, out of the
    /// synchronous prelude above, deliberately. Marking it BEFORE the request
    /// is known to have landed was a correctness bug, not a style choice: if
    /// the POST never reaches the host (unreachable, TLS trouble, the request
    /// itself cancelled), the host keeps generating unattended while the
    /// self-stopped flag makes the driver's own terminal handling
    /// (`.runCancelled`, `deliverPolledTerminal`'s default arm) end the turn
    /// SILENTLY — a Stop the user sees as having worked, when it did not
    /// reach the host at all. Now a transport failure marks nothing, so a
    /// later `run.cancelled` frame or polled terminal status for this run
    /// still surfaces as `.interrupted` (ordinary recovery), not silence.
    ///
    /// The `catch` below only ever sees a TRANSPORT failure — `session.data
    /// (for:)` does not throw on an HTTP error status. A 404 (`run_not_found`
    /// — the run already ended server-side on its own) comes back as
    /// ordinary, successful `data` and IS success for our purposes: the host
    /// heard the stop attempt (there was simply nothing left to stop), so
    /// `markSelfStopped` still fires on that arm.
    func hardStopActiveRun() {
        guard let context = activeRunContext else { return }
        clearActiveRunContext(matchingRunID: context.runID)
        let runID = context.runID
        let profileID = context.profileID
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let request = try self.makeRequest(
                    path: "\(Self.runsPath)/\(runID)/stop",
                    method: "POST",
                    body: nil,
                    accept: "application/json",
                    profileID: profileID
                )
                _ = try await self.session.data(for: request)
                // The POST reached the host — including a 404, which just
                // means the run was already over. Only NOW is it true that
                // the host has heard the stop, so only now may the driver's
                // terminal handling silence itself for this run.
                self.markSelfStopped(runID: runID)
            } catch {
                runsTransportLogger.error(
                    "runs: stop request for \(runID, privacy: .public) did NOT reach the host — \(error.localizedDescription, privacy: .public) — NOT marking self-stopped, so this run's eventual terminal delivery surfaces as recovery rather than a false silent success"
                )
            }
        }
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
