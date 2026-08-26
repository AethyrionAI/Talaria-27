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
        /// **#372(c) — the ROLLBACK arm, added 2026-08-21. The only thing that
        /// can still measure the 2026-08-15 promotion.**
        ///
        /// `blurbReworded` above substitutes `armedBlurbCardSentence` → the
        /// reworded text. Production has SHIPPED the reworded text since the
        /// promotion, so that substitution now matches nothing: the arm is
        /// **identity with control** and its `reworded=` row correctly reports
        /// that it did nothing. Not broken — out of anything to measure.
        ///
        /// This arm substitutes the OTHER way, putting the pre-promotion
        /// sentence back (`armedBlurbSentencePre337F2b`, reached by its alias
        /// per 372-C3 so there is never a second copy of the pinned text).
        /// #200L's shape, one instrument over.
        ///
        /// **Position LAST, and the reason is recorded rather than stylistic:**
        /// this instrument calls `beginTurn()` per trial so it carries no
        /// #343 governor confound, leaving thermal as the only order effect —
        /// and in #337-F's run thermal moved AGAINST the result. The worst slot
        /// therefore makes a positive finding conservative and leaves a null
        /// UNINTERPRETABLE rather than convenient. A null here needs a
        /// reversed-order re-run, not a conclusion.
        case blurbRollback = "blurb-rollback"
        /// **#372(b) / 337-H — the `.required` REMEDY, wired 2026-08-26. The
        /// first arm in this instrument that does not try to persuade the model
        /// with prose.**
        ///
        /// #337-H named it and nobody built it: `GenerationOptions
        /// .toolCallingMode` is iOS-27 API that moves tool use from
        /// model-decided to developer-set, and **production does not set it at
        /// all** (`chatGenerationOptions` passes samplingMode / temperature /
        /// maximumResponseTokens only, so every production turn runs the
        /// default). The candidate is: on a turn already classified as needing
        /// a device tool, make the call MANDATORY rather than asking for it.
        ///
        /// This instrument is the right host because its failure mode IS
        /// 337-H's target — the zero-tool turn that writes the confirmation
        /// card out in prose and calls nothing. Belt and instructions are
        /// production verbatim here; the ONLY delta is the decoding mode, which
        /// is why it can be read against the same control as every prose arm.
        ///
        /// **The demote exit is mandatory, not stylistic** (#200E, and Apple's
        /// own doc comment): a static `.required` loops until a tool throws, so
        /// the arm rides `toolmodeMode(after:)` — `.required` until the first
        /// call, `.allowed` after — through `ToolmodeBatteryProfile`.
        ///
        /// **It ships as an ARM and nothing else.** Owen's night-batch
        /// direction was explicit: no production default moves, the device A/B
        /// decides. `theOnlyArmThatForcesToolCallingIsTheRemedy` pins that, and
        /// `productionGenerationOptionsSetNoToolCallingMode` pins the default it
        /// must not disturb.
        ///
        /// **Position LAST, for this instrument's recorded reason:** it calls
        /// `beginTurn()` per trial so it carries no #343 governor confound,
        /// leaving thermal as the only order effect — and in #337-F's run
        /// thermal moved AGAINST the result. The worst slot makes a positive
        /// finding conservative and leaves a null uninterpretable rather than
        /// convenient.
        case toolmodeRequired = "toolmode-required"
    }

    /// #372(b): whether an arm forces the tool-calling mode. A function rather
    /// than a comparison at the call site, for `isRouted`'s reason one
    /// instrument over — the property is the thing a new arm must state, and a
    /// call site that tested `arm == .toolmodeRequired` inline would be a rule
    /// living in one place with no way to assert it.
    nonisolated static func cardClauseForcesToolCalling(arm: CardClauseArm) -> Bool {
        switch arm {
        case .control, .toolsStripped, .toolsAndBlurbStripped,
             .blurbStripped, .blurbReworded, .blurbRollback: return false
        case .toolmodeRequired: return true
        }
    }

    /// **Did this arm's treatment actually APPLY?** — the manipulation band's
    /// `correct` column, extracted here so it can be asserted.
    ///
    /// 🔴 **This is a DEFECT FOUND BY #372's lane, not a refactor.** The
    /// expression that stood at the call site was
    /// `arm == .control ? 1 : (swapped > 0 ? 1 : 0)` — i.e. **every arm whose
    /// treatment is an INSTRUCTION swap scored 0**, because instruction arms
    /// swap no descriptions. `blurb-stripped` and `blurb-rollback` both applied
    /// cleanly on 2026-08-21 and both were recorded in the artifact's `correct`
    /// column as treatments that had failed to apply. Nobody was misled, and
    /// only because the reader went to the `instructionsChars` /
    /// `rewordedSentencePresent` METRICS instead — which is to say the column
    /// built to catch a silent no-op was itself silently wrong, and the
    /// evidence that saved the reading came from somewhere else.
    ///
    /// #372(b) is what made it urgent: the remedy arm swaps no description AND
    /// changes no instruction byte, so under the old expression it would have
    /// been permanently indistinguishable from a broken arm.
    ///
    /// Each arm is asked about the manipulation it actually performs.
    /// `toolsAndBlurbStripped` requires BOTH, deliberately — it is the only arm
    /// that claims two, and an arm that applied half of a two-part treatment is
    /// not a treatment that applied.
    ///
    /// **`blurbReworded` returning false is CORRECT and is 372-C1's finding,
    /// not a regression:** production has shipped the reworded sentence since
    /// 2026-08-15, so that arm's substitution matches nothing and it is
    /// identity with control. The column should say so.
    nonisolated static func cardClauseManipulationApplied(arm: CardClauseArm,
                                                          swapped: Int,
                                                          blurbRemoved: Bool) -> Bool {
        switch arm {
        case .control: return true
        case .toolsStripped: return swapped > 0
        case .toolsAndBlurbStripped: return swapped > 0 && blurbRemoved
        case .blurbStripped, .blurbReworded, .blurbRollback: return blurbRemoved
        case .toolmodeRequired: return cardClauseForcesToolCalling(arm: arm)
        }
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
        // #372(c): the rollback arm moves ONE instruction string and leaves
        // the descriptions alone — stated here rather than inherited, which is
        // what this switch being enumerated is for.
        // #372(b): the `.required` remedy moves the DECODING MODE and nothing
        // else — belt and instructions production verbatim, so its delta is
        // attributable to the mode rather than to a bundle. Stated here for the
        // same reason the rollback states it.
        case .control, .blurbStripped, .blurbReworded, .blurbRollback,
             .toolmodeRequired: return (tools, 0)
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
        // #372(c): the ROLLBACK — put the pre-promotion sentence back. This is
        // the only arm that still moves relative to what production ships, and
        // therefore the only one that can measure the promotion at all.
        //
        // Both operands are ALIASES on purpose (372-C3): `armedBlurbShipping‐
        // Sentence` is whatever ships today and `armedBlurbSentencePre337F2b`
        // is the pinned pre-promotion text. Writing either as a literal here
        // would re-create the two-copies problem the promotion had to fix, and
        // a future promotion would leave this arm rolling back to a sentence
        // nobody ships.
        if arm == .blurbRollback {
            let text = instructions.replacingOccurrences(
                of: DeviceActionClauses.armedBlurbShippingSentence,
                with: DeviceActionClauses.armedBlurbSentencePre337F2b)
            return (text, text != instructions)
        }
        // #337-F-2: two arms remove the blurb — arm C (with the descriptions)
        // and the isolating arm (without them).
        switch arm {
        // #372(b): production instructions VERBATIM. The remedy's whole claim
        // is that it does not need words, so an arm that also moved a sentence
        // would be unable to make it.
        case .control, .toolsStripped, .toolmodeRequired: return (instructions, false)
        case .toolsAndBlurbStripped, .blurbStripped: break
        case .blurbReworded, .blurbRollback: break  // both handled above
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

    /// **#372(a) — was the DECLINE HALF actually exercised on this trial, and
    /// if so what did the model say about it?**
    ///
    /// The shipping blurb is two clauses: *"Every action tool asks the user to
    /// approve it before anything changes; **if they decline, accept that
    /// gracefully**."* #337-F-2b kept the second clause on purpose — the
    /// blurb-stripped arm bought its 0/30 by deleting decline guidance — and
    /// #372(a) filed that **no trial has ever exercised it**, so the clause has
    /// been carried on faith through a promotion and a rollback arm.
    ///
    /// **The thing that made it unfileable is that the instrument could not
    /// see a decline.** `toolCallsAdmitted` is the governor's number: it says a
    /// call got through, not that the gate ever answered it. This reads the
    /// gate's own counter instead.
    ///
    /// **`verdict` is nil unless the half was exercised, and that is #215's
    /// rule rather than tidiness.** Scoring decline attribution on a trial
    /// where nothing was declined measures a configuration the trial never
    /// entered — the reply cannot misattribute a refusal that did not happen,
    /// so a zero-decline trial would enter the tally as a free `.actorUnnamed`
    /// or `.unscorable` and dilute the rate with rows that had no opportunity
    /// to fail. That is exactly the unarmed-cell error, one instrument over.
    ///
    /// The scorer is #392's, reached rather than re-implemented: this is its
    /// first call site inside an instrument, which is its own small finding —
    /// it shipped 2026-08-23 with unit tests and a Mac-side log scorer and no
    /// Swift caller at all.
    nonisolated static func declineHalfRow(replyText: String?, declinesObserved: Int)
        -> (exercised: Bool, verdict: DeclineAttributionScorer.Verdict?) {
        guard declinesObserved > 0 else { return (false, nil) }
        guard let replyText else { return (true, nil) }
        return (true, DeclineAttributionScorer.verdict(for: replyText))
    }

    /// One trial of the A/B.
    struct CardClauseTrialOutcome {
        var armedText: String?
        var error: String?
        var timedOut = false
        var cutFired = false
        var toolCallsAdmitted = 0
        /// #372(a): declines produced by the gate DURING this trial, as a delta
        /// on `ToolConfirmationCenter.batteryDeclineCount`. Zero means the
        /// decline half was not reached, whatever the call count says.
        var declinesObserved = 0
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
                correct: Self.cardClauseManipulationApplied(
                    arm: arm, swapped: swapped, blurbRemoved: blurbRemoved) ? 1 : 0,
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
                    // #372(b): the remedy arm's manipulation is INVISIBLE in
                    // every column above — belt identical, instructions
                    // byte-identical, description count zero — so without this
                    // row it would be indistinguishable from the control in the
                    // artifact, which is the "treatment that silently no-ops"
                    // failure the whole manipulation band exists to prevent.
                    "toolCallingForced": Self.cardClauseForcesToolCalling(arm: arm) ? 1 : 0,
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
            // #372(a): the decline half's own tallies. `declineHalfExercised`
            // is the count this entry has been unable to state since it was
            // filed; the verdict tally is scored over THAT denominator and
            // never over `attempted`, because a trial with no decline had no
            // opportunity to misattribute one (#215).
            var declineHalfExercised = 0
            var declineVerdicts: [DeclineAttributionScorer.Verdict: Int] = [:]

            for (tag, prompt) in prompts {
                for trial in 1...trials {
                    let trialTag = Self.refusalTrialTag(cell: arm.rawValue, prompt: tag, trial: trial)
                    ToolEventRelay.batteryTrialTag = trialTag
                    Self.batteryEmit("battery: BEGIN \(trialTag)")
                    Self.batteryRecorder.beginTrial()
                    toolRelay?.beginTurn()
                    attempted += 1

                    let outcome = await executeCardClauseTrial(
                        belt: belt, instructions: instructions, options: options,
                        prompt: prompt, arm: arm)

                    let decline = Self.declineHalfRow(replyText: outcome.armedText,
                                                      declinesObserved: outcome.declinesObserved)
                    if decline.exercised { declineHalfExercised += 1 }
                    if let verdict = decline.verdict { declineVerdicts[verdict, default: 0] += 1 }
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
                                          trialTag: trialTag, armedHit: armedHit, retryHit: retryHit,
                                          decline: decline)
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
                    "toolCallingForced": Self.cardClauseForcesToolCalling(arm: arm) ? 1 : 0,
                    // #372(a): the number this entry has been owed since it was
                    // filed — how many trials actually REACHED the decline
                    // half. Reported next to the verdict tally rather than as a
                    // rate, because the rate's own denominator is this count
                    // and a reader must be able to see when it is zero.
                    "declineHalfExercised": Double(declineHalfExercised),
                    "declineAttributedToUser":
                        Double(declineVerdicts[.attributedToUser] ?? 0),
                    "declineAttributedToTool":
                        Double(declineVerdicts[.attributedToTool] ?? 0),
                    "declineActorUnnamed": Double(declineVerdicts[.actorUnnamed] ?? 0),
                    "declineUnscorable": Double(declineVerdicts[.unscorable] ?? 0),
                ],
                notes: [
                    "reading": "mechanism = armedImitations/attempted; behaviour = trialsWithToolCalls/attempted",
                    // Spelled out in the artifact because the wrong
                    // denominator here is the whole #215 error: dividing the
                    // misattribution count by `attempted` folds in every trial
                    // that was never declined and reports a defect rate that
                    // falls whenever the model simply calls nothing.
                    "declineReading": "decline verdicts are scored over declineHalfExercised, NEVER over attempted — a trial with no decline had no opportunity to misattribute one",
                ])
            Self.batteryEmit("battery: ARM SUMMARY \(arm.rawValue) attempted=\(attempted) imitations=\(armedImitations) calls=\(trialsWithToolCalls) declines=\(declineHalfExercised) toolTold=\(declineVerdicts[.attributedToTool] ?? 0) cut=\(cutTrials) genErrors=\(generationErrors) timeouts=\(timeouts) (#337-F)")
            emitThermal(cell: arm.rawValue, at: "end")
        }
        ToolEventRelay.batteryTrialTag = nil
        Self.batteryEmit("battery: DONE (#337-F)")
        Self.batteryRecorder.endRun()
    }

    private func executeCardClauseTrial(belt: [any Tool], instructions: String,
                                        options: GenerationOptions,
                                        prompt: String,
                                        arm: CardClauseArm) async -> CardClauseTrialOutcome {
        var outcome = CardClauseTrialOutcome()
        let executedBefore = toolRelay?.executedCallsThisTurn ?? 0
        // #372(a): sampled ACROSS the trial, so the delta counts only what this
        // trial's gate answered. A run-level total could not tell a trial that
        // was declined from one that merely followed twenty that were.
        let declinesBefore = ToolConfirmationCenter.batteryDeclineCount
        // #372(b) / 337-H: the remedy arm is the ONE session in this instrument
        // built through a DynamicProfile — the mode has to be re-evaluated per
        // model turn for the demote exit to exist at all, and a plain
        // `GenerationOptions.toolCallingMode = .required` is fixed for the
        // whole request and loops (#200E, Apple's own doc comment). Every other
        // arm keeps the plain session it has always had, so the remedy adds a
        // construction rather than changing one.
        let session: LanguageModelSession
        // The generation options ride the PROFILE on the remedy arm and the
        // respond() call gets an empty set — #200E's own discipline, and it is
        // load-bearing rather than cosmetic: options passed to respond() are
        // fixed for the whole request, so re-supplying them there is how a
        // demote exit silently stops existing.
        let respondOptions: GenerationOptions
        if Self.cardClauseForcesToolCalling(arm: arm) {
            session = LanguageModelSession(profile: ToolmodeBatteryProfile(
                model: model, belt: belt, instructionsText: instructions, options: options))
            respondOptions = GenerationOptions()
        } else {
            session = LanguageModelSession(model: model, tools: belt,
                                           instructions: Instructions(instructions))
            respondOptions = options
        }
        let respondTask = Task { try await session.respond(to: Prompt(prompt), options: respondOptions) }
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
        outcome.declinesObserved = max(0, ToolConfirmationCenter.batteryDeclineCount - declinesBefore)
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
                                       armedHit: String?, retryHit: String?,
                                       decline: (exercised: Bool, verdict: DeclineAttributionScorer.Verdict?)) {
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
        // #372(a): only present when the half was reached. An ABSENT key is a
        // trial that had no decline, which is a different fact from a trial
        // whose decline nobody could classify — the latter is
        // `unscorable` and is present.
        if let verdict = decline.verdict { notes["declineVerdict"] = verdict.rawValue }
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
                // #372(a): kept SEPARATE from `toolCallsAdmitted` rather than
                // derived from it. A call admitted by the governor is not a
                // call the gate answered, and reading one off the other is the
                // inference that let the decline half go unmeasured this long.
                "declinesObserved": Double(outcome.declinesObserved),
                "declineHalfExercised": decline.exercised ? 1 : 0,
                // #372(b): recorded per trial as well as per arm, so a partial
                // run still says which decoding regime produced its rows.
                "toolCallingForced": Self.cardClauseForcesToolCalling(arm: arm) ? 1 : 0,
            ],
            notes: notes)

        Self.batteryEmit("battery: \(trialTag) imitation=\(armedHit ?? "—") calls=\(outcome.toolCallsAdmitted) declines=\(outcome.declinesObserved) declineVerdict=\(decline.verdict?.rawValue ?? "—") outcome=\(notes["outcome"] ?? "—") (#337-F)")
    }
}
#endif
