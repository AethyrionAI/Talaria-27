import Foundation
import FoundationModels

// #337 bar 337-D — **the refusal-words instrument.**
//
// #232 filed the refusal grind in 2026-08-02 and closed it without ever
// recording a refusal string. #337 then measured the grind's RATE at scale —
// 69/90 and 74/90 action turns ending in `ToolPhaseCutError` on two device
// runs — and could still not say what any of those refusals said, because
// nothing captured them. Every number filed about the grind so far describes
// a text nobody has read.
//
// This instrument reads it: each refusal verbatim, with the governor state
// that produced it, whether the cut fired, and — bar 337-B / #225 B2's named
// gap — **the text of the post-cut toolless retry, which is what the user
// actually gets.** Until that last one is in the record a cut trial reads as
// an empty row, and #225 B2 says in so many words that the 70 empties may be
// read neither as clean nor as broken.
//
// **Auto-DECLINE, so it is unattended-eligible.** The grind is a property of
// the governor's counters, not of what happens after a confirmation resolves:
// a declined call is an EXECUTED call and counts toward the budget exactly
// like an accepted one. The cost is stated rather than hidden — see
// `runRefusalWordsInstrument`.
#if DEBUG
extension LocalChatBackend {

    /// #337-D's two cells, and the contrast between them is the instrument's
    /// second question rather than a control.
    ///
    /// **`turn-reset` is what PRODUCTION does.** `LocalChatBackend.send` and
    /// `streamTurn` both open with `beginToolTurn()` → `relay.beginTurn()` →
    /// `governor.beginTurn()`, so every production turn starts with a full
    /// budget of 12 and a clean per-tool tally. #225's own
    /// `theBudgetResetsForEachTurn` calls a leaked budget "the obvious way for
    /// this fix to become a worse bug than the one it fixes."
    ///
    /// **`leaked` is what the BATTERY does.** `runActionBattery`'s trial loop
    /// calls `session.respond` directly and never calls `beginTurn()` at all,
    /// so one governor's counters run across every trial of a whole run — and
    /// across every run in one app launch, since the governor is built once in
    /// `installTools`. Read that against #337's table before assuming which
    /// cell describes the app.
    ///
    /// The cells are otherwise IDENTICAL — same belt, same instructions, same
    /// options, same prompts, same order. One line of difference, which is the
    /// only shape that can attribute anything.
    enum RefusalWordsCell: String, CaseIterable {
        /// A turn boundary before every trial — production's contract.
        case turnReset = "turn-reset"
        /// One turn boundary at the START of the cell and none after — the
        /// battery's contract as it stands today.
        case leaked
    }

    /// One trial's refusal evidence, assembled before anything is recorded so
    /// the row and the emit line cannot describe different trials.
    struct RefusalTrialOutcome {
        var refusals: [ToolCallGovernor.RefusalObservation] = []
        var cutFired = false
        /// The armed attempt's reply, when it produced one.
        var text: String?
        /// The armed attempt's error, when it did not.
        var error: String?
        var timedOut = false
        /// #337-B / #225 B2: the text of the toolless retry production runs
        /// after a cut. `nil` when no cut fired; `nil` WITH `retryError` set
        /// when the retry itself failed — the two are different facts and the
        /// record keeps them apart.
        var retryText: String?
        var retryError: String?
        var toolCallCount = 0
    }

    /// The trial-tag grammar, pinned here so the emit lines and the probe row
    /// names cannot drift apart.
    nonisolated static func refusalTrialTag(cell: String, prompt: String, trial: Int) -> String {
        "shape=\(cell) p=\(prompt) t=\(trial)"
    }

    /// #337-D. Action prompts through the PRODUCTION armed construction, with
    /// every governor refusal captured verbatim and the post-cut retry run and
    /// recorded.
    ///
    /// **What it measures**, per trial: how many refusals the turn produced,
    /// what each one said and which branch produced it, the governor's two
    /// counters at that moment, whether the cut fired, how many tool calls
    /// were admitted, the armed attempt's reply-or-error, and the retried
    /// toolless turn's text.
    ///
    /// **What auto-decline costs, stated in advance.** Every create is
    /// declined, so on trials where the model DOES call a tool it then reasons
    /// about a refusal-shaped tool result it would not see under auto-accept.
    /// That is a real difference and it is why the row records
    /// `toolCallCount` — a trial with zero calls is untouched by the mode
    /// (nothing was ever staged), and those are the majority of #337's rows.
    /// What it buys is that the instrument writes NOTHING: no EventKit, no
    /// AlarmKit, no reap, so it can run unattended under the #333 conductor.
    ///
    /// **The retry is bound to production, not modelled.** `send`'s cut arm
    /// sets `turnRoutedToolless = true` and rebuilds; the shared
    /// `routedTrialShape(needsTool: false, …)` seam returns exactly that
    /// construction — empty belt plus `productionToollessInstructions`. #215
    /// built that seam because a battery once measured a toolless turn
    /// production had stopped speaking; going through it is what stops this
    /// instrument repeating that.
    func runRefusalWordsInstrument(trials: Int,
                                   cells: [RefusalWordsCell] = RefusalWordsCell.allCases) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let prompts = Self.actionBatteryDefaultPrompts
        let shape = SessionShape.armedRouted
        let base = Self.shapedBelt(
            from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: false),
            shape: shape
        )
        let instructions = Self.instructionsText(
            for: shape,
            deviceContext: Self.deviceContextLine(),
            hasTools: !base.isEmpty,
            hasImageTools: false
        )
        let options = Self.shapedGenerationOptions(Self.chatGenerationOptions(for: activeTier), shape: shape)
        Self.batteryEmit("battery: START trials=\(trials) cells=\(cells.count) prompts=\(prompts.count) (#337-D refusal-words)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: cells.map(\.rawValue),
                                      kind: "refusal-words")

        // The capture sink is armed for the whole run and torn down on every
        // exit path — a sink left installed would keep appending through the
        // next battery and attribute its refusals here.
        let capture = ToolCallGovernor.RefusalCapture()
        ToolCallGovernor.RefusalCapture.current = capture
        defer { ToolCallGovernor.RefusalCapture.current = nil }

        for cell in cells {
            emitThermal(cell: cell.rawValue, at: "start")
            // #215's error-path rule per band: every counter below is a
            // COUNTED denominator or a counted failure. No constant
            // denominators — a cell that threw on every trial must report
            // `attempted` trials, `errors` errors and a scored count of zero
            // rather than a clean-looking rate.
            var attempted = 0
            var cutTrials = 0
            var refusalTotal = 0
            var generationErrors = 0
            var timeouts = 0
            var retriesAttempted = 0
            var retryErrors = 0
            var retriesWithText = 0
            var trialsWithToolCalls = 0
            var repliesNonEmpty = 0
            // `leaked` gets its ONE boundary here and nowhere else.
            if cell == .leaked { toolRelay?.beginTurn() }
            for (tag, prompt) in prompts {
                for trial in 1...trials {
                    let trialTag = Self.refusalTrialTag(cell: cell.rawValue, prompt: tag, trial: trial)
                    ToolEventRelay.batteryTrialTag = trialTag
                    Self.batteryEmit("battery: BEGIN \(trialTag)")
                    Self.batteryRecorder.beginTrial()
                    if cell == .turnReset { toolRelay?.beginTurn() }
                    // Drain rather than trust emptiness: a straggler from the
                    // previous trial's guillotined task would otherwise be
                    // attributed to this one.
                    capture.drain()
                    attempted += 1

                    let outcome = await executeRefusalTrial(
                        belt: base, instructions: instructions, options: options,
                        prompt: prompt, capture: capture)

                    refusalTotal += outcome.refusals.count
                    if outcome.cutFired { cutTrials += 1 }
                    if outcome.timedOut { timeouts += 1 }
                    if outcome.error != nil && !outcome.cutFired && !outcome.timedOut { generationErrors += 1 }
                    if outcome.cutFired {
                        retriesAttempted += 1
                        if outcome.retryError != nil { retryErrors += 1 }
                        if let retry = outcome.retryText, !retry.isEmpty { retriesWithText += 1 }
                    }
                    if outcome.toolCallCount > 0 { trialsWithToolCalls += 1 }
                    if let text = outcome.text, !text.isEmpty { repliesNonEmpty += 1 }

                    recordRefusalTrial(outcome, cell: cell.rawValue, promptTag: tag,
                                       trial: trial, trialTag: trialTag)
                }
            }
            // The cell summary. `correct` is defined once, here: trials that
            // produced text a USER would have seen — the armed reply, or the
            // post-cut retry's reply when the armed attempt was cut. That is
            // the number #225 B2 said the instrument could not produce.
            let userVisible = repliesNonEmpty + retriesWithText
            Self.batteryRecorder.recordProbe(
                probe: "337-D cell summary \(cell.rawValue)",
                expected: true, correct: userVisible, trials: attempted,
                variant: cell.rawValue, band: "refusal-summary",
                errors: generationErrors + retryErrors,
                metrics: [
                    "attempted": Double(attempted),
                    "cutTrials": Double(cutTrials),
                    "refusalsTotal": Double(refusalTotal),
                    "generationErrors": Double(generationErrors),
                    "timeouts": Double(timeouts),
                    "retriesAttempted": Double(retriesAttempted),
                    "retryErrors": Double(retryErrors),
                    "retriesWithText": Double(retriesWithText),
                    "trialsWithToolCalls": Double(trialsWithToolCalls),
                    "armedRepliesNonEmpty": Double(repliesNonEmpty),
                    "userVisibleReplies": Double(userVisible),
                ],
                notes: ["turnBoundary": cell == .turnReset
                        ? "beginTurn() before every trial — production's contract"
                        : "beginTurn() once per cell — the battery's contract"])
            Self.batteryEmit("battery: CELL \(cell.rawValue) attempted=\(attempted) cut=\(cutTrials) refusals=\(refusalTotal) genErrors=\(generationErrors) timeouts=\(timeouts) retries=\(retriesAttempted) retryErrors=\(retryErrors) userVisible=\(userVisible) (#337-D)")
            emitThermal(cell: cell.rawValue, at: "end")
        }
        ToolEventRelay.batteryTrialTag = nil
        Self.batteryEmit("battery: DONE (#337-D)")
        Self.batteryRecorder.endRun()
    }

    /// One armed attempt plus, when it is cut, production's toolless retry.
    ///
    /// The 35s guillotine matches `executeBatteryTrial`'s so the two
    /// instruments' timeout populations are comparable; the retry gets its own
    /// budget for the same reason a production retry does — it is a second
    /// turn, not the tail of the first.
    private func executeRefusalTrial(belt: [any Tool], instructions: String,
                                     options: GenerationOptions, prompt: String,
                                     capture: ToolCallGovernor.RefusalCapture) async -> RefusalTrialOutcome {
        var outcome = RefusalTrialOutcome()
        // Admitted calls are read as a DELTA off the relay's own counter, not
        // as an absolute: in the `leaked` cell that counter is mid-run by
        // construction, and an absolute read there would report the cell's
        // running total as this trial's.
        let executedBefore = toolRelay?.executedCallsThisTurn ?? 0
        let session = LanguageModelSession(model: model, tools: belt,
                                           instructions: Instructions(instructions))
        let respondTask = Task { try await session.respond(to: Prompt(prompt), options: options) }
        let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
        do {
            let response = try await respondTask.value
            timeoutTask.cancel()
            outcome.text = response.content
        } catch is CancellationError {
            timeoutTask.cancel()
            outcome.timedOut = true
        } catch {
            timeoutTask.cancel()
            outcome.error = String(describing: error)
            outcome.cutFired = Self.isToolPhaseCut(error)
        }
        // Drained AFTER the attempt settles, so a refusal decided inside the
        // call that threw is still counted.
        outcome.refusals = capture.drain()
        outcome.toolCallCount = max(0, (toolRelay?.executedCallsThisTurn ?? 0) - executedBefore)
        if outcome.cutFired {
            let shaped = Self.routedTrialShape(
                needsTool: false, armedBelt: belt, armedInstructions: instructions,
                deviceContext: Self.deviceContextLine())
            let retrySession = LanguageModelSession(model: model, tools: shaped.belt,
                                                    instructions: Instructions(shaped.instructions))
            let retryTask = Task { try await retrySession.respond(to: Prompt(prompt), options: options) }
            let retryTimeout = Task { try? await Task.sleep(for: .seconds(35)); retryTask.cancel() }
            do {
                outcome.retryText = try await retryTask.value.content
                retryTimeout.cancel()
            } catch {
                retryTimeout.cancel()
                outcome.retryError = String(describing: error)
            }
        }
        return outcome
    }

    /// Writes ONE trial into the record twice over, deliberately: the familiar
    /// trial row (reply text, tool calls, confirmation outcomes — the #196
    /// grammar every existing classifier reads) and a probe row carrying the
    /// refusal evidence the trial row has no field for.
    ///
    /// The cut trial's trial-row is an ERROR row, and stays one. It is honest:
    /// the ARMED attempt did die. The retry's text belongs to a second turn
    /// and lands in the probe row rather than being back-filled into the first
    /// — writing it into `text` would make a cut trial indistinguishable from
    /// an armed trial that answered, which is precisely the conflation #225 B2
    /// is complaining about, only in the other direction.
    private func recordRefusalTrial(_ outcome: RefusalTrialOutcome, cell: String,
                                    promptTag: String, trial: Int, trialTag: String) {
        if let text = outcome.text {
            let lower = text.lowercased()
            let cant = lower.hasPrefix("i can\u{2019}t") || lower.hasPrefix("i cant")
                || lower.hasPrefix("i cannot") || lower.hasPrefix("i can not") || lower.hasPrefix("i can't")
            let denial = Self.batteryDenialPatterns.contains { lower.contains($0) }
            Self.batteryRecorder.endTrial(shape: cell, prompt: promptTag, trial: trial,
                                          text: text, cant: cant, denial: denial)
        } else if outcome.timedOut {
            Self.batteryRecorder.endTrialTimeout(shape: cell, prompt: promptTag, trial: trial)
        } else {
            Self.batteryRecorder.endTrialError(shape: cell, prompt: promptTag, trial: trial,
                                               error: outcome.error ?? "unknown")
        }

        var notes: [String: String] = [:]
        // **The words, verbatim, numbered.** One key per refusal rather than a
        // joined blob: a classifier that has to split a string on a separator
        // is one escaped character away from mis-attributing a refusal, and
        // these strings contain punctuation the model also writes.
        for (index, refusal) in outcome.refusals.enumerated() {
            notes["refusal\(index + 1)Text"] = refusal.text
            notes["refusal\(index + 1)Tool"] = refusal.tool
            notes["refusal\(index + 1)Reason"] = refusal.reason.rawValue
            notes["refusal\(index + 1)Counters"] =
                "callsThisTurn=\(refusal.callsThisTurn) callsOfThisTool=\(refusal.callsOfThisTool)"
        }
        if let retryText = outcome.retryText { notes["retryText"] = retryText }
        if let retryError = outcome.retryError { notes["retryError"] = String(retryError.prefix(400)) }
        if let error = outcome.error { notes["armedError"] = String(error.prefix(400)) }
        if let text = outcome.text { notes["armedText"] = text }
        // Named outcomes rather than a bool soup — "cut, and the retry spoke"
        // is a different user experience from "cut, and the retry died", and a
        // row that could only say `cut=true` would merge them.
        notes["outcome"] = {
            if outcome.cutFired {
                if outcome.retryError != nil { return "cut-retry-failed" }
                if let retry = outcome.retryText, !retry.isEmpty { return "cut-retry-answered" }
                return "cut-retry-empty"
            }
            if outcome.timedOut { return "timeout" }
            if outcome.error != nil { return "error" }
            if let text = outcome.text, !text.isEmpty { return "answered" }
            return "empty"
        }()

        Self.batteryRecorder.recordProbe(
            probe: "337-D \(trialTag)",
            expected: true,
            // A trial "scores" when the USER would have seen text — the armed
            // reply, or the retry's reply after a cut.
            correct: (outcome.text?.isEmpty == false || outcome.retryText?.isEmpty == false) ? 1 : 0,
            trials: 1, variant: cell, band: "refusal-trial",
            errors: (outcome.error != nil && !outcome.cutFired ? 1 : 0) + (outcome.retryError != nil ? 1 : 0),
            metrics: [
                "refusals": Double(outcome.refusals.count),
                "cutFired": outcome.cutFired ? 1 : 0,
                "timedOut": outcome.timedOut ? 1 : 0,
                "retryAttempted": outcome.cutFired ? 1 : 0,
                "retryAnswered": (outcome.retryText?.isEmpty == false) ? 1 : 0,
                "budgetRefusals": Double(outcome.refusals.filter { $0.reason == .perTurnBudget }.count),
                "repeatRefusals": Double(outcome.refusals.filter { $0.reason == .sameToolRepeat }.count),
                "toolCallsAdmitted": Double(outcome.toolCallCount),
            ],
            notes: notes)

        Self.batteryEmit("battery: \(trialTag) refusals=\(outcome.refusals.count) cut=\(outcome.cutFired) outcome=\(notes["outcome"] ?? "—") retryChars=\(outcome.retryText?.count ?? -1) (#337-D)")
        for (index, refusal) in outcome.refusals.enumerated() {
            Self.batteryEmit("battery: refusal#\(index + 1) \(trialTag) tool=\(refusal.tool) reason=\(refusal.reason.rawValue) callsThisTurn=\(refusal.callsThisTurn) callsOfThisTool=\(refusal.callsOfThisTool) text=\(refusal.text)")
        }
    }
}
#endif
