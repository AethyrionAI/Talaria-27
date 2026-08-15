import Foundation
import FoundationModels

// #337 bar 337-F — **the confirmation-card A/B.**
//
// #337-A, a real production turn on 2026-08-12: *"**Confirmation card:** A
// reminder to 'take out the trash' at 8 AM has been created."* No card
// appeared, nothing was tapped, nothing was created. The model did not merely
// fabricate — it emitted the app's own affordance name, in prose, which a user
// cannot tell from the real card except by the absence of buttons.
//
// The candidate mechanism was filed with a text pointer and explicitly NOT
// elected: every action tool's description ends with *"The user sees a
// confirmation card and can edit or cancel before anything is created."* A
// model that declines to call the tool still has that sentence in context and
// can narrate it.
//
// This measures it. Production's descriptions are the control; the treatment
// is the SAME descriptions with only that clause removed. **Production's
// defaults do not change** — the stripped strings are harness-only constants
// derived by removal from production's own statics, and the entry says in so
// many words: do not edit the descriptions in production on the strength of
// the hypothesis alone.
#if DEBUG
extension LocalChatBackend {

    /// The three arms, and why there are three rather than the two the bar
    /// names.
    ///
    /// **The phrase has more than one home.** The tool descriptions teach it
    /// (three sites), and so does the armed instruction blurb —
    /// `"Every action tool shows the user a confirmation card first; if they
    /// decline, accept it gracefully."` A two-arm design that removed it from
    /// the descriptions alone could only ever produce an interpretable
    /// POSITIVE: a null would be consistent with "the descriptions were never
    /// the source" AND with "the blurb kept teaching it," and nothing in the
    /// run could separate those. The third arm is what makes a null mean
    /// something.
    ///
    /// **What is held CONSTANT in all three arms, deliberately:** the promoted
    /// card-narration clause (#200J/#200K — *"The confirmation card is shown
    /// automatically when you call an action tool — never write the card out…"*).
    /// That clause is a COUNTERMEASURE, not a teaching: #200J measured it
    /// taking card narration from 3 to 0 in 40 trials. Removing it would
    /// confound this manipulation with rolling back a promotion, and the delta
    /// would be unattributable. It does still contain the phrase — so **no arm
    /// here is a zero-exposure arm**, and a null in arm C bounds the
    /// description hypothesis rather than exonerating the phrase.
    enum CardClauseArm: String, CaseIterable {
        /// Production descriptions and production instructions, verbatim.
        case control
        /// The clause removed from the three action tools' descriptions.
        /// Nothing else differs. This is 337-F's pre-registered manipulation.
        case toolsStripped = "tools-stripped"
        /// Arm B plus the armed blurb's own confirmation-card sentence.
        case toolsAndBlurbStripped = "tools-blurb-stripped"
        /// **337-F-2 — the ISOLATING arm, added 2026-08-13 after the first run.**
        /// The blurb sentence removed and the descriptions left ALONE. 337-F
        /// measured arm B at 7/30 imitations (descriptions stripped, no effect,
        /// p = 0.51) and arm C at 0/30 with 30/30 tool calls — but arm C moves
        /// BOTH strings, so the blurb carried the effect only *by elimination*.
        /// This arm moves one string and is the only thing that can license a
        /// promotion.
        ///
        /// **Position is deliberate: LAST.** This instrument calls
        /// `beginTurn()` per trial, so it is free of #337's leaked-budget
        /// confound (`cutTrials = 0` in all three arms of the first run) and the
        /// only order effect left is thermal — which in that run moved AGAINST
        /// the result (arm C ran hottest and scored best). The worst slot
        /// therefore makes a POSITIVE finding conservative. **A null here would
        /// be uninterpretable** and would need a reversed-order re-run, not a
        /// conclusion.
        case blurbStripped = "blurb-stripped"
        /// **337-F-2b — the REWORDED arm, added 2026-08-13 on Owen's go after
        /// the isolating arm came back clean.** The blurb sentence REPLACED
        /// rather than removed: decline guidance kept, card vocabulary gone,
        /// descriptions untouched. This is the arm that would justify a
        /// production text change, because `blurb-stripped` buys its 0/30 by
        /// deleting an instruction whose decline half this prompt set never
        /// exercises (30/30 of its calls were made, so nothing was declined).
        ///
        /// Position LAST, for the same reason `blurbStripped` is: the worst
        /// slot makes a positive conservative, and a null here would need a
        /// reversed-order re-run rather than a conclusion.
        case blurbReworded = "blurb-reworded"
    }

    /// The belt each arm registers: identity for the control, and for the
    /// stripped arms the same instances with ONE string swapped on each action
    /// tool. Returns the count of tools actually swapped, because "the
    /// treatment applied to three tools" is a claim the record has to be able
    /// to make — a belt that happened to carry none would otherwise produce a
    /// treatment arm identical to its control and a clean-looking null.
    nonisolated static func cardClauseBelt(from tools: [any Tool],
                                           arm: CardClauseArm) -> (belt: [any Tool], swapped: Int) {
        // #337-F-2: NOT `arm != .control`. The blurb-only arm is also a
        // treatment and must leave the descriptions alone — under the old
        // guard it silently became arm C while still reporting its own name,
        // which is a treatment that reads clean and measures the wrong thing.
        // Enumerated rather than negated so a future arm has to state its
        // intent here instead of inheriting one.
        switch arm {
        case .control, .blurbStripped, .blurbReworded: return (tools, 0)
        case .toolsStripped, .toolsAndBlurbStripped: break
        }
        var swapped = 0
        let belt: [any Tool] = tools.map { tool in
            if var reminder = tool as? ReminderCreateTool {
                reminder.description = ReminderCreateTool.cardClauseStripped337
                swapped += 1
                return reminder
            }
            if var calendar = tool as? CalendarEventTool {
                calendar.description = CalendarEventTool.cardClauseStripped337
                swapped += 1
                return calendar
            }
            if var alarm = tool as? AlarmTool {
                alarm.description = AlarmTool.cardClauseStripped337
                swapped += 1
                return alarm
            }
            return tool
        }
        return (belt, swapped)
    }

    /// The instructions each arm passes. Arm C removes the armed blurb's
    /// confirmation-card sentence by exact substring; `removed` reports
    /// whether the removal changed anything, so a silently-no-op treatment is
    /// visible in the artifact instead of reading as a null result.
    nonisolated static func cardClauseInstructions(_ instructions: String,
                                                   arm: CardClauseArm) -> (text: String, removed: Bool) {
        // #337-F-2: two arms remove the blurb now — arm C (with the
        // descriptions) and the isolating arm (without them).
        // #337-F-2b: the reworded arm SUBSTITUTES rather than removes — the
        // decline guidance survives, the card vocabulary does not. Handled
        // first because its replacement is not the empty string.
        if arm == .blurbReworded {
            let text = instructions.replacingOccurrences(
                of: DeviceActionClauses.armedBlurbCardSentence,
                with: DeviceActionClauses.armedBlurbCardSentenceReworded337F2)
            return (text, text != instructions)
        }
        // #337-F-2: two arms remove the blurb — arm C (with the descriptions)
        // and the isolating arm (without them).
        switch arm {
        case .control, .toolsStripped: return (instructions, false)
        case .toolsAndBlurbStripped, .blurbStripped: break
        case .blurbReworded: break  // handled above
        }
        // #337-F-2b PROMOTED 2026-08-15: production now ships the REWORDED
        // sentence, so the strip arms must target what ships — otherwise they
        // remove a sentence the instructions no longer contain and every
        // treatment silently becomes its own control. `removed:` would have
        // caught that in the artifact (it is why it exists), but a treatment
        // that can only report "I did nothing" is not worth running.
        //
        // NOTE the arms' MEANING changed with the promotion: they now measure
        // removing the approval sentence, not removing the card sentence.
        // #337-F's published numbers were the latter and are not re-labelled.
        let stripped = instructions.replacingOccurrences(
            of: DeviceActionClauses.armedBlurbShippingSentence, with: "")
        return (stripped, stripped != instructions)
    }

    /// The prose shapes that imitate the app's own affordance.
    ///
    /// Deliberately NARROW. This is not an action-claim detector (that
    /// question is #336's, and the reply *"I've set a reminder for you"* is a
    /// claim without being an impersonation); it detects the app's UI
    /// vocabulary appearing in the model's prose, which is the NEW dimension
    /// #337-A found and the batteries could not see.
    ///
    /// The two shapes are the two that have actually been observed: #337-A's
    /// literal *"Confirmation card:"* heading, and the 15 uncut action turns
    /// of run `A7AB9960` that opened *"Here's the confirmation…"*.
    nonisolated static let confirmationCardImitationShapes = [
        "confirmation card",
        "here's the confirmation",
        "here is the confirmation",
    ]

    /// The matched shape, or nil. **Apostrophes are normalized first**: the
    /// model writes curly ones and #225 B3's first classifier pass used a
    /// straight apostrophe, which read every claim as a non-claim until sample
    /// text visibly contradicted its own bucket. The same bug, pre-empted.
    nonisolated static func confirmationCardImitation(in text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .lowercased()
        return confirmationCardImitationShapes.first { normalized.contains($0) }
    }

    /// One trial of the A/B.
    struct CardClauseTrialOutcome {
        var armedText: String?
        var error: String?
        var timedOut = false
        var cutFired = false
        var toolCallsAdmitted = 0
        /// The post-cut toolless retry — recorded for the same reason 337-D
        /// records it (#225 B2), but read differently here: the retry turn
        /// registers NO belt in any arm, so an imitation in the retry is
        /// evidence about the INSTRUCTIONS, never about the descriptions.
        var retryText: String?
        var retryError: String?
    }

    /// #337-F. Three arms × the three action prompts × `trials`.
    ///
    /// **Auto-DECLINE, so it is unattended-eligible and writes nothing.** The
    /// phenomenon lives on turns where the model calls NO tool — #337-A's turn
    /// had none — and on those turns the confirmation mode is unreachable, so
    /// the arm that matters is untouched by the choice. On the turns where the
    /// model does call, a decline result enters the transcript where an
    /// approval would have; both arms pay that identically, so the CONTRAST
    /// holds while the absolute rate is not production's. `toolCallsAdmitted`
    /// is recorded per trial so the zero-tool turns can be read on their own.
    ///
    /// **A turn boundary before every trial.** `runActionBattery` never calls
    /// `relay.beginTurn()`, so the governor's per-turn budget accumulates
    /// across its whole run; an A/B run under that condition would be mostly
    /// phase cuts and would measure the cut rather than the clause. This
    /// instrument resets, which is what production does.
    func runCardClauseAB(trials: Int, arms: [CardClauseArm] = CardClauseArm.allCases,
                         warmup: Bool = LocalChatBackend.batteryWarmupDefault) async {
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
        let productionInstructions = Self.instructionsText(
            for: shape,
            deviceContext: Self.deviceContextLine(),
            hasTools: !base.isEmpty,
            hasImageTools: false
        )
        let options = Self.shapedGenerationOptions(Self.chatGenerationOptions(for: activeTier), shape: shape)
        Self.batteryEmit("battery: START trials=\(trials) arms=\(arms.count) prompts=\(prompts.count) warmup=\(warmup) (#337-F card-clause)")
        // #200V: through the CONTROL's construction, because the control is
        // arm 1 and a cold control against two warm treatments is a confound
        // sitting exactly where this A/B's effect would be.
        if warmup {
            await runDiscardedWarmup(belt: base, instructions: productionInstructions,
                                     options: options, item: "#337-F")
        }
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: arms.map(\.rawValue),
                                      kind: "card-clause")

        for arm in arms {
            emitThermal(cell: arm.rawValue, at: "start")
            let (belt, swapped) = Self.cardClauseBelt(from: base, arm: arm)
            let (instructions, blurbRemoved) = Self.cardClauseInstructions(productionInstructions, arm: arm)
            // The MANIPULATION CHECK, recorded before any trial runs. An arm
            // whose treatment did not apply is a broken arm, and the artifact
            // must say so rather than let its null pool with the control's.
            Self.batteryRecorder.recordProbe(
                probe: "337-F manipulation check \(arm.rawValue)",
                expected: true,
                correct: arm == .control ? 1 : (swapped > 0 ? 1 : 0),
                trials: 1, variant: arm.rawValue, band: "manipulation", errors: 0,
                metrics: [
                    "descriptionsSwapped": Double(swapped),
                    "blurbRemoved": blurbRemoved ? 1 : 0,
                    "beltSize": Double(belt.count),
                    "instructionsChars": Double(instructions.count),
                    "cardPhraseInInstructions":
                        Self.confirmationCardImitation(in: instructions) == nil ? 0 : 1,
                    // #337-F-2b: `blurbRemoved` alone cannot tell the REWORDED
                    // arm from the blurb-only arm — both report the original
                    // sentence gone. This MEASURES the replacement's presence
                    // in the text actually passed, rather than inferring it
                    // from the arm's name, so a substitution that silently
                    // failed to apply cannot read as a clean null.
                    "rewordedSentencePresent":
                        instructions.contains(
                            DeviceActionClauses.armedBlurbCardSentenceReworded337F2) ? 1 : 0,
                ],
                notes: [
                    "expectedSwaps": arm == .control ? "0 (control)" : "3 action tools",
                    // The phrase survives in every arm via the promoted
                    // card-narration clause, held constant on purpose. Stated
                    // in the record so no reader mistakes arm C for zero
                    // exposure.
                    "residualExposure": "the promoted card-narration clause is held constant in all arms",
                ])
            Self.batteryEmit("battery: ARM \(arm.rawValue) swapped=\(swapped) blurbRemoved=\(blurbRemoved) reworded=\(instructions.contains(DeviceActionClauses.armedBlurbCardSentenceReworded337F2)) (#337-F)")

            var attempted = 0
            var armedImitations = 0
            var retryImitations = 0
            var trialsWithToolCalls = 0
            var cutTrials = 0
            var generationErrors = 0
            var timeouts = 0
            var retryErrors = 0
            var armedRepliesNonEmpty = 0

            for (tag, prompt) in prompts {
                for trial in 1...trials {
                    let trialTag = Self.refusalTrialTag(cell: arm.rawValue, prompt: tag, trial: trial)
                    ToolEventRelay.batteryTrialTag = trialTag
                    Self.batteryEmit("battery: BEGIN \(trialTag)")
                    Self.batteryRecorder.beginTrial()
                    toolRelay?.beginTurn()
                    attempted += 1

                    let outcome = await executeCardClauseTrial(
                        belt: belt, instructions: instructions, options: options, prompt: prompt)

                    let armedHit = outcome.armedText.flatMap { Self.confirmationCardImitation(in: $0) }
                    let retryHit = outcome.retryText.flatMap { Self.confirmationCardImitation(in: $0) }
                    if armedHit != nil { armedImitations += 1 }
                    if retryHit != nil { retryImitations += 1 }
                    if outcome.toolCallsAdmitted > 0 { trialsWithToolCalls += 1 }
                    if outcome.cutFired { cutTrials += 1 }
                    if outcome.timedOut { timeouts += 1 }
                    if outcome.error != nil && !outcome.cutFired && !outcome.timedOut { generationErrors += 1 }
                    if outcome.retryError != nil { retryErrors += 1 }
                    if let text = outcome.armedText, !text.isEmpty { armedRepliesNonEmpty += 1 }

                    recordCardClauseTrial(outcome, arm: arm, promptTag: tag, trial: trial,
                                          trialTag: trialTag, armedHit: armedHit, retryHit: retryHit)
                }
            }
            // `correct` = trials whose ARMED reply carried the imitation shape.
            // The denominator is COUNTED attempts, and the error tallies name
            // the trials that could not answer the question at all — a band
            // where every trial threw reports 0/n with n errors, never a clean
            // zero rate (#215).
            Self.batteryRecorder.recordProbe(
                probe: "337-F arm summary \(arm.rawValue)",
                expected: true, correct: armedImitations, trials: attempted,
                variant: arm.rawValue, band: "card-clause-summary",
                errors: generationErrors + timeouts + retryErrors,
                metrics: [
                    "attempted": Double(attempted),
                    "armedImitations": Double(armedImitations),
                    "retryImitations": Double(retryImitations),
                    "trialsWithToolCalls": Double(trialsWithToolCalls),
                    "armedRepliesNonEmpty": Double(armedRepliesNonEmpty),
                    "cutTrials": Double(cutTrials),
                    "generationErrors": Double(generationErrors),
                    "timeouts": Double(timeouts),
                    "retryErrors": Double(retryErrors),
                    "descriptionsSwapped": Double(swapped),
                    "blurbRemoved": blurbRemoved ? 1 : 0,
                ],
                notes: ["reading": "mechanism = armedImitations/attempted; behaviour = trialsWithToolCalls/attempted"])
            Self.batteryEmit("battery: ARM SUMMARY \(arm.rawValue) attempted=\(attempted) imitations=\(armedImitations) calls=\(trialsWithToolCalls) cut=\(cutTrials) genErrors=\(generationErrors) timeouts=\(timeouts) (#337-F)")
            emitThermal(cell: arm.rawValue, at: "end")
        }
        ToolEventRelay.batteryTrialTag = nil
        Self.batteryEmit("battery: DONE (#337-F)")
        Self.batteryRecorder.endRun()
    }

    private func executeCardClauseTrial(belt: [any Tool], instructions: String,
                                        options: GenerationOptions,
                                        prompt: String) async -> CardClauseTrialOutcome {
        var outcome = CardClauseTrialOutcome()
        let executedBefore = toolRelay?.executedCallsThisTurn ?? 0
        let session = LanguageModelSession(model: model, tools: belt,
                                           instructions: Instructions(instructions))
        let respondTask = Task { try await session.respond(to: Prompt(prompt), options: options) }
        let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
        do {
            outcome.armedText = try await respondTask.value.content
            timeoutTask.cancel()
        } catch is CancellationError {
            timeoutTask.cancel()
            outcome.timedOut = true
        } catch {
            timeoutTask.cancel()
            outcome.error = String(describing: error)
            outcome.cutFired = Self.isToolPhaseCut(error)
        }
        outcome.toolCallsAdmitted = max(0, (toolRelay?.executedCallsThisTurn ?? 0) - executedBefore)
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

    private func recordCardClauseTrial(_ outcome: CardClauseTrialOutcome, arm: CardClauseArm,
                                       promptTag: String, trial: Int, trialTag: String,
                                       armedHit: String?, retryHit: String?) {
        if let text = outcome.armedText {
            let lower = text.lowercased()
            let cant = lower.hasPrefix("i can\u{2019}t") || lower.hasPrefix("i cant")
                || lower.hasPrefix("i cannot") || lower.hasPrefix("i can not") || lower.hasPrefix("i can't")
            let denial = Self.batteryDenialPatterns.contains { lower.contains($0) }
            Self.batteryRecorder.endTrial(shape: arm.rawValue, prompt: promptTag, trial: trial,
                                          text: text, cant: cant, denial: denial)
        } else if outcome.timedOut {
            Self.batteryRecorder.endTrialTimeout(shape: arm.rawValue, prompt: promptTag, trial: trial)
        } else {
            Self.batteryRecorder.endTrialError(shape: arm.rawValue, prompt: promptTag, trial: trial,
                                               error: outcome.error ?? "unknown")
        }

        var notes: [String: String] = [:]
        if let text = outcome.armedText { notes["armedText"] = text }
        if let armedHit { notes["armedImitationShape"] = armedHit }
        if let retryHit { notes["retryImitationShape"] = retryHit }
        if let retryText = outcome.retryText { notes["retryText"] = retryText }
        if let retryError = outcome.retryError { notes["retryError"] = String(retryError.prefix(400)) }
        if let error = outcome.error { notes["armedError"] = String(error.prefix(400)) }
        notes["outcome"] = {
            if outcome.cutFired { return outcome.retryText == nil ? "cut-retry-failed" : "cut-retry-answered" }
            if outcome.timedOut { return "timeout" }
            if outcome.error != nil { return "error" }
            if let text = outcome.armedText, !text.isEmpty { return "answered" }
            return "empty"
        }()

        Self.batteryRecorder.recordProbe(
            probe: "337-F \(trialTag)",
            expected: true, correct: armedHit == nil ? 0 : 1, trials: 1,
            variant: arm.rawValue, band: "card-clause-trial",
            errors: (outcome.error != nil && !outcome.cutFired ? 1 : 0) + (outcome.retryError != nil ? 1 : 0),
            metrics: [
                // The MECHANISM reading and the BEHAVIOUR reading, side by
                // side and never collapsed: a clause that stops the prose
                // without producing a call has moved one and not the other,
                // and a single number could not say which.
                "armedImitation": armedHit == nil ? 0 : 1,
                "retryImitation": retryHit == nil ? 0 : 1,
                "toolCallsAdmitted": Double(outcome.toolCallsAdmitted),
                "cutFired": outcome.cutFired ? 1 : 0,
                "timedOut": outcome.timedOut ? 1 : 0,
                "claimsCreation": Self.claimsCreation(outcome.armedText ?? "") ? 1 : 0,
            ],
            notes: notes)

        Self.batteryEmit("battery: \(trialTag) imitation=\(armedHit ?? "—") calls=\(outcome.toolCallsAdmitted) outcome=\(notes["outcome"] ?? "—") (#337-F)")
    }
}
#endif
