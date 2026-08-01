import Foundation
import FoundationModels
import UIKit
import os

// Extracted from LocalChatBackend.swift (#216, 2026-08-01) — pure code motion.
//
// DEBUG-only instruments: the #134 forced-trip harness, the #120
// message-identity UITest harness, and the #196 session-shape instrument.
// They reach members marked `// harness-visible` in the main file, which are
// `internal` rather than `private` for exactly that reason.
#if DEBUG
// MARK: - Forced-trip harness (#134 — DEBUG builds only)

/// Device-verification harness for the ALREADY-SHIPPED #102 breaker and #110
/// read-aloud retraction. The base model's own guardrails defeat every
/// deterministic loop repro (it refuses verbatim-repeat and declines
/// long-form), so a synthetic degenerate stream is the only way to watch the
/// trip happen on a real device. The harness owns NO detection or collapse
/// logic — it scripts the snapshots and lets the production `streamTurn`
/// consumer path (deltas → `RepetitionBreaker` → collapse → finish) do the
/// rest. None of this exists in a Release build.
extension LocalChatBackend {

    /// One-shot arming: set by `ChatStore.debugRunForcedTrip` immediately
    /// before a normal send; the next `streamTurn` consumes and clears it.
    /// Static because extensions can't add stored instance properties —
    /// AppContainer builds exactly one LocalChatBackend per process, so
    /// process-wide arming is equivalent.
    static var debugForcedTripCopies: Int?
    /// Second mode: additionally hold a REAL SDK generation in flight (output
    /// suppressed) while the synthetic loop trips — proves that abandoning a
    /// live stream doesn't wedge the next turn.
    static var debugForcedTripHoldsLiveSDKStream = false

    /// The loop unit the synthetic stream repeats. Exactly 32 characters and
    /// not periodic at any divisor period, so detection first qualifies at
    /// 6 copies (6 × 32 = 192, the span floor) — the breaker ARMS at
    /// `repetitionMinimumRepeats` and ESCALATES at the
    /// `repetitionEscalationRepeats` floor of 12, the same shape the #102
    /// thresholds were tuned for.
    nonisolated static let debugDegenerateUnit = "The device loop signal repeats. "
    /// Benign lead-in: gives read-aloud a healthy sentence to start speaking
    /// (so the #110 retraction visibly CUTS a live queue) and proves the
    /// collapse preserves pre-loop text.
    nonisolated static let debugDegeneratePreamble = "Synthetic degenerate stream armed from Diagnostics. "
    /// Default copy count: the trip lands at copy 12; 16 leaves margin
    /// without meaningfully lengthening the run.
    nonisolated static let debugDegenerateDefaultCopies = 16
    /// Pacing between synthetic snapshots — realistic enough that speech has
    /// STARTED before the trip (#110 must retract a speaking queue, not one
    /// that never began) and a held live SDK stream is genuinely
    /// mid-generation when abandoned.
    nonisolated static let debugSnapshotPacing: Duration = .milliseconds(200)

    /// Cumulative snapshots mirroring FoundationModels' stream shape: the
    /// preamble alone, then one appended copy of the loop unit per snapshot.
    nonisolated static func debugDegenerateSnapshots(copies: Int = debugDegenerateDefaultCopies) -> [String] {
        var text = debugDegeneratePreamble
        var snapshots = [text]
        for _ in 0 ..< max(1, copies) {
            text += debugDegenerateUnit
            snapshots.append(text)
        }
        return snapshots
    }

    /// The forced-trip turn: everything a real streamed turn does — the user
    /// turn lands in history, cumulative snapshots diff onto `.textDelta`,
    /// every snapshot is judged by a real `RepetitionBreaker`, and the trip
    /// collapses the tail and invalidates the session (the D3 rebuild seam) —
    /// with the model generation replaced by scripted snapshots, plus an
    /// optional suppressed live one.
    // harness-entry: called from the production send path in
    // LocalChatBackend.swift behind a UITest/forced-trip flag. `fileprivate`
    // sufficed while this lived in that same file (#216 extraction).
    func runDebugForcedTripTurn(
        message: String,
        attachments: [PendingAttachment],
        clientMessageID: UUID,
        copies: Int,
        holdLiveSDKStream: Bool,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async {
        Self.logger.notice("debug forced trip: synthetic degenerate stream begins — \(copies, privacy: .public) copies, holds live SDK stream \(holdLiveSDKStream, privacy: .public) (#134)")
        var liveDrain: Task<Void, Never>?
        if holdLiveSDKStream {
            let prompt = Self.composePrompt(message: message, attachments: attachments)
            let liveSession = await preparedSession(nextPrompt: prompt, attachments: attachments, excludingClientMessageID: clientMessageID)
            // Through the #196 seam like every live generation: with a
            // nocall-armed picker, even this held stream must not fire
            // tools mid-instrument.
            let options = effectiveGenerationOptions()
            liveDrain = Task { @MainActor in
                // Output suppressed by design — the held stream exists only so
                // the trip abandons a REAL in-flight SDK generation.
                do {
                    for try await _ in liveSession.streamResponse(to: Prompt(prompt), options: options) {
                        if Task.isCancelled { break }
                    }
                } catch {
                    Self.logger.notice("debug forced trip: held SDK stream ended — \(error.localizedDescription, privacy: .public) (#134)")
                }
            }
        }
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        var emitted = ""
        var latestFull = ""
        var didTripRepetitionBreaker = false
        var repetitionBreaker = RepetitionBreaker()
        for snapshot in Self.debugDegenerateSnapshots(copies: copies) {
            if Task.isCancelled { break }
            try? await Task.sleep(for: Self.debugSnapshotPacing)
            latestFull = snapshot
            if let delta = Self.streamDelta(from: emitted, to: latestFull) {
                emitted += delta
                continuation.yield(.textDelta(delta))
            }
            if repetitionBreaker.shouldAbandon(afterObserving: Self.degenerateTailRepetitionRun(in: latestFull)) {
                didTripRepetitionBreaker = true
                Self.logger.notice("streamTurn: degenerate tail repetition escalated after \(latestFull.count, privacy: .public) chars — abandoning the stream, collapsing the looped tail (#102)")
                latestFull = Self.collapsingDegenerateTail(latestFull)
                break
            }
        }
        liveDrain?.cancel()
        // No generation happened, so no real usage exists to report
        // (real-data-only — the receipt stays empty rather than stale).
        let reply = Message(sender: .hermes, content: latestFull, status: .delivered)
        appendAssistantMessage(reply, usage: nil)
        if didTripRepetitionBreaker {
            // Same post-trip rule as production: the abandoned stream's
            // transcript state is unknowable — the next turn rebuilds from
            // our message history (D3 verifies exactly this).
            session = nil
        }
        continuation.yield(.finished(reply, nil, nil))
    }
}

// MARK: - Message-identity UITest harness (#120 — DEBUG builds only)

/// Model-free synthetic turn for the #120 end-to-end regression guard. It
/// exercises the production append → finish sequence with a deterministic
/// dwell so the 2s poll-tick merge lands in the duplicate-seeding window,
/// letting a black-box UITest observe whether the rendered transcript ever
/// holds the same id twice. Armed only by the `UITEST_DUPID_PROBE` launch
/// env, and compiled out of Release entirely.
extension LocalChatBackend {

    static var isUITestIdentityProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_DUPID_PROBE"] == "1"
    }

    /// Dwell strictly longer than one poll interval (2s) so at least one
    /// `loadConversation()` merge is guaranteed to land after the reply is
    /// appended but before `.finished` is yielded.
    private static var uiTestIdentityDwell: Duration { .seconds(2.6) }

    // harness-entry: called from the production send path in
    // LocalChatBackend.swift behind a UITest/forced-trip flag. `fileprivate`
    // sufficed while this lived in that same file (#216 extraction).
    func runUITestIdentityTurn(
        message: String,
        attachments: [PendingAttachment],
        clientMessageID: UUID,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async {
        connectionStatus = .connected
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        // Stream a short fixed reply the same way the live path does — one
        // `.textDelta` per word — so the placeholder renders as a real
        // streaming bubble.
        let responseText = "Acknowledged \(message)"
        var emitted = ""
        for word in responseText.split(separator: " ") {
            try? await Task.sleep(for: .milliseconds(60))
            let delta = (emitted.isEmpty ? "" : " ") + word
            emitted += delta
            continuation.yield(.textDelta(delta))
        }

        // Production ordering: the reply lands in `currentConversation`
        // (which `loadConversation()` serves to the poll merge) BEFORE
        // `.finished`. The dwell holds that window open long enough for the
        // merge to adopt the reply while the store still shows the
        // placeholder — the #120 race, made deterministic.
        let reply = Message(sender: .hermes, content: emitted, status: .delivered)
        appendAssistantMessage(reply, usage: nil)
        try? await Task.sleep(for: Self.uiTestIdentityDwell)
        // Model the unprimed-client shape (#120's unmasked case): on the
        // device the duplication only SURVIVED when the client's
        // `currentConversation` was nil at `.finished` (warm launch — cache
        // short-circuits priming), because the post-finish metadata merge
        // otherwise re-imports the backend thread and silently heals the
        // duplicate in the same MainActor turn. The poll-tick merge above
        // already adopted the reply from `loadConversation()`; clearing here
        // removes only the masking source, exactly like the unit test's
        // MidTurnMergeClient keeps its `currentConversation` nil by design.
        currentConversation = nil
        continuation.yield(.finished(reply, nil, nil))
    }
}

// MARK: - Session-shape instrument (#196, reworked from #194/176C — DEBUG builds only)

/// A/B cells for #196, third battery: STRUCTURAL decomposition of the armed
/// disease, after two batteries of prose treatments. Owen's verdict on the
/// second battery (n=20/cell, build 686d2e2): nothing on the armed path is
/// fixed — every prose cell edits sentences; none decomposed the structure.
/// The six battery cells (`batteryCells`) now isolate the armed session's
/// INGREDIENTS: instruction text (`armed-noinstr` / `toolless-noinstr`),
/// action-tool availability (`armed-readonly`), decode-time call ability
/// with schemas kept in context (`armed-nocall`, on the iOS-27
/// `GenerationOptions.toolCallingMode` control verified in Part 0), and
/// schema text with calling kept (`armed-noschema`, on
/// `Tool.includesSchemaInInstructions`). Battery-2's treatment cells stay in
/// the enum as HELD ship candidates (measured wins, held by Owen's verdict) —
/// picker-reachable for spot checks, no longer burning battery trials.
/// Armed by the `TALARIA_SESSION_SHAPE` launch environment or, at
/// a desk, the persisted Diagnostics override — following the
/// `UITEST_DUPID_PROBE` seam precedent: inert in every normal run, compiled
/// out of Release entirely. The selector touches session construction only
/// (`effectiveOfferedTools` / `effectiveInstructionsText` /
/// `effectiveGenerationOptions`).
extension LocalChatBackend {

    // CaseIterable (#196 third battery): lets the test pins iterate
    // `allCases` minus the treated shapes, so a future cell can never
    // dodge the identity pins by not being in an enumerated list.
    enum SessionShape: String, CaseIterable {
        /// Production behavior — the in-run control; both mechanisms live
        /// here (first battery: haiku 6/10, 8/10 reminder grabs, Norway
        /// 4/10 with 0 clean opens).
        case armed
        /// Production instructions, belt with ONLY `createReminder`'s
        /// description scoped against task-verb confusion
        /// (`ReminderCreateTool.scopedDescription196`). Fix the tool, not
        /// the prompt. Target: grabs ~8/10 → ~0.
        case armedRemfix = "armed-remfix"
        /// Production belt, instructions PLUS the composition-licensing
        /// sentence in the licensing clause. Target: Norway content up at
        /// unchanged haiku.
        case armedComplic = "armed-complic"
        /// Both treatments together — the actual ship candidate, measured
        /// in the same run so an interaction effect can't hide behind two
        /// individually-clean cells.
        case armedFix = "armed-fix"
        /// The production tool-less branch with tools unregistered — the far
        /// control (first battery: haiku 10/10 clean, Norway 0/10).
        case toolless
        /// The tool-less branch rebuilt with the licensing clause the bare
        /// branch never received in #176B, honesty caveat kept.
        case toollessLic = "toolless-lic"
        /// Third battery (#196 decomposition): production belt, NO
        /// instructions. Vs `armed`, isolates whether OUR instruction text
        /// is a net cause of the armed disease or the belt registration
        /// itself is — the fork every future fix routes on.
        case armedNoinstr = "armed-noinstr"
        /// No belt, no instructions — the in-app replica of the Shortcuts
        /// "Use Model" probe that wrote haiku happily on this same phone.
        /// Vs `toolless`, prices the bare branch's prose (which denies
        /// arithmetic 20/20 — text or model?).
        case toollessNoinstr = "toolless-noinstr"
        /// Production instructions; belt MINUS the three action tools
        /// (grabs die structurally — no tool to grab). If haiku CLEAN
        /// recovers toward toolless levels, the ship path is extending
        /// #176 availability gating to action tools.
        case armedReadonly = "armed-readonly"
        /// Production instructions AND belt, but every call runs with
        /// `toolCallingMode: .disallowed` (iOS 27): schemas stay in
        /// context, calling is impossible. The per-turn-routing ship
        /// path's proof cell.
        case armedNocall = "armed-nocall"
        /// Production instructions; the three action tools carry
        /// `includesSchemaInInstructions = false` — still callable,
        /// schemas hidden. Can the model grab what it cannot see? The
        /// semantics are undocumented; surprising results are findings,
        /// not bugs.
        case armedNoschema = "armed-noschema"
        /// Battery 4 (#196 cure lane): the licensed bare branch plus the
        /// two device-observed canary fixes — math/facts license and an
        /// output-format mandate (Apple template convention). The routed
        /// architecture's non-tool payload.
        case toollessLic2 = "toolless-lic2"
        /// Battery 4: the production candidate. A per-turn guided-generation
        /// router (few-shot, greedy — 80/80 on the Mac-host probe grid)
        /// decides whether the turn needs the device; tool turns get the
        /// production armed session, everything else gets `toolless-lic2`.
        /// WWDC26 session 242's sanctioned shape: tools withheld where
        /// "known to be irrelevant," decided contextually.
        case armedRouted = "armed-routed"

        /// Whether this cell hands the session a tool belt at all.
        /// `armedRouted` returns true — it CAN register; the per-turn
        /// router decides whether a given turn actually does.
        var registersTools: Bool {
            switch self {
            case .armed, .armedRemfix, .armedComplic, .armedFix,
                 .armedNoinstr, .armedReadonly, .armedNocall, .armedNoschema,
                 .armedRouted:
                return true
            case .toolless, .toollessLic, .toollessNoinstr, .toollessLic2:
                return false
            }
        }

        /// Whether this cell's belt carries the #196-scoped
        /// `createReminder` description (the remfix treatment).
        var usesScopedReminderDescription: Bool {
            switch self {
            case .armedRemfix, .armedFix:
                return true
            case .armed, .armedComplic, .toolless, .toollessLic,
                 .armedNoinstr, .toollessNoinstr, .armedReadonly, .armedNocall, .armedNoschema,
                 .toollessLic2, .armedRouted:
                return false
            }
        }

        /// Whether this cell hands the session instructions at all. The two
        /// `-noinstr` cells pass NOTHING: the battery builds the session
        /// with the `instructions:` parameter omitted entirely (resolving
        /// to the SDK's `Instructions? = nil` designated convenience init),
        /// and the live path builds a transcript with no instructions
        /// entry. `instructionsText(for:)` returns the empty string for
        /// them only so its switch stays exhaustive.
        var passesInstructions: Bool {
            switch self {
            case .armedNoinstr, .toollessNoinstr:
                return false
            case .armed, .armedRemfix, .armedComplic, .armedFix,
                 .toolless, .toollessLic, .armedReadonly, .armedNocall, .armedNoschema,
                 .toollessLic2, .armedRouted:
                return true
            }
        }
    }

    /// The belt each cell registers (#196): identity for every cell except
    /// the structural treatments —
    /// - remfix cells: ONLY the `createReminder` description string is
    ///   swapped (same instances, same order, same relay and gate);
    /// - `armed-readonly`: the three action tools are removed outright
    ///   (the #176 availability-gating mechanism, extended — filter by
    ///   concrete type so belt order never matters);
    /// - `armed-noschema`: the three action tools are COPIES with
    ///   `includesSchemaInInstructions` flipped off — still registered,
    ///   still callable, schemas hidden from the instructions. Read tools
    ///   untouched in both.
    nonisolated static func shapedBelt(from tools: [any Tool], shape: SessionShape) -> [any Tool] {
        switch shape {
        case .armedRemfix, .armedFix:
            return tools.map { tool in
                if var reminder = tool as? ReminderCreateTool {
                    reminder.description = ReminderCreateTool.scopedDescription196
                    return reminder
                }
                return tool
            }
        case .armedReadonly:
            return tools.filter {
                !($0 is ReminderCreateTool || $0 is CalendarEventTool || $0 is AlarmTool)
            }
        case .armedNoschema:
            return tools.map { tool in
                if var reminder = tool as? ReminderCreateTool {
                    reminder.includesSchemaInInstructions = false
                    return reminder
                }
                if var event = tool as? CalendarEventTool {
                    event.includesSchemaInInstructions = false
                    return event
                }
                if var alarm = tool as? AlarmTool {
                    alarm.includesSchemaInInstructions = false
                    return alarm
                }
                return tool
            }
        case .armed, .armedComplic, .toolless, .toollessLic, .armedNoinstr, .toollessNoinstr, .armedNocall,
             .toollessLic2, .armedRouted:
            // armedRouted's belt treatment happens per turn in the routing
            // gates, never here — shapedBelt stays the identity for it.
            return tools
        }
    }

    /// The generation options each cell runs with (#196 third battery):
    /// identity for every cell except `armed-nocall`, which sets the
    /// iOS-27 `toolCallingMode: .disallowed` — schemas stay in context,
    /// decode-time tool calling is impossible. Production options carry no
    /// override (pinned in `LocalChatBackendTests`), so `armed` remains
    /// byte-identical production.
    nonisolated static func shapedGenerationOptions(_ options: GenerationOptions, shape: SessionShape) -> GenerationOptions {
        guard shape == .armedNocall else { return options }
        var shaped = options
        shaped.toolCallingMode = .disallowed
        return shaped
    }

    /// Read once per process — the cells are launch-scoped, so a mid-run env
    /// mutation can never make one conversation's session builds disagree.
    static let activeSessionShape: SessionShape = {
        if let raw = ProcessInfo.processInfo.environment["TALARIA_SESSION_SHAPE"],
           let shape = SessionShape(rawValue: raw) {
            return shape
        }
        // Desk A/B (#196, folded from the 176C side branch): a DEBUG-only
        // persisted override so the cells are reachable from a home-screen
        // launch — OTA installs cannot carry launch environment, and the
        // phone is unreachable by Xcode over the tailnet. Read ONCE here like
        // the env path, so the launch-scoped invariant above holds: the
        // Diagnostics picker takes effect on the NEXT launch (force-quit
        // between cells is the A/B protocol anyway). Launch env wins when
        // both are set. A retired cell name still persisted on a phone
        // fails to parse and falls through to the default — production, by
        // design.
        if let raw = UserDefaults.standard.string(forKey: "debug.sessionShape"),
           let shape = SessionShape(rawValue: raw) {
            return shape
        }
        // The default is the PRODUCTION shape. Pre-promotion this was
        // `.armed`; since the 2026-07-28 battery-4 verdict the production
        // path routes, so an untouched Debug install behaves like Release.
        return .armedRouted
    }()

    /// The instructions each cell hands the session. `hasTools` /
    /// `hasImageTools` are the PRODUCTION inputs for this turn; the shape
    /// overrides from there, so `armed` is provably the production text.
    nonisolated static func instructionsText(
        for shape: SessionShape,
        deviceContext: String,
        date: Date = .now,
        hasTools: Bool = false,
        hasImageTools: Bool = false
    ) -> String {
        switch shape {
        case .armed, .armedRemfix, .armedReadonly, .armedNocall, .armedNoschema:
            // armed-remfix, and the third battery's belt/options
            // treatments (readonly / nocall / noschema), are STRUCTURAL:
            // their instructions are the production text verbatim — the
            // seams live in `shapedBelt` / `shapedGenerationOptions`.
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: hasTools, hasImageTools: hasImageTools
            )
        case .armedNoinstr, .toollessNoinstr:
            // These cells pass NO instructions (`passesInstructions ==
            // false` — callers omit the parameter / the transcript entry).
            // Empty keeps this switch exhaustive and the live context
            // budget honest at zero.
            return ""
        case .armedComplic, .armedFix:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: hasTools, hasImageTools: hasImageTools,
                includeCompositionLicensingSentence: true
            )
        case .toolless:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: false, hasImageTools: hasImageTools
            )
        case .toollessLic:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: false, hasImageTools: hasImageTools,
                includeToollessLicensingClause: true
            )
        case .toollessLic2:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: false, hasImageTools: hasImageTools,
                includeToollessLic2Clause: true
            )
        case .armedRouted:
            // The ARMED half of the routed pair — the toolless half is
            // resolved by the routing gates (`effectiveInstructionsText`
            // consults the turn's route and returns the `toollessLic2`
            // text instead when the turn needs no tool).
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: hasTools, hasImageTools: hasImageTools
            )
        }
    }
}
#endif
