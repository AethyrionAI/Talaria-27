import Foundation
import FoundationModels

// #211A — **offer-instead-of-act on READ paths, where no confirmation gate
// excuses it.**
//
// Several production replies OFFER the right tool without calling it —
// *"Would you like me to check your health data for other metrics?"* On a
// CREATE path an offer is at least adjacent to the confirmation gate: the
// model is about to ask permission anyway. **On a read path there is no gate
// to excuse it.** The user asked a question the model could have answered
// outright, and got a question back.
//
// #211 banked the corroborating observation this instrument exists to test
// directly: on `stepsdirect`, control offered on **4/10** and the promoted
// scoped-`readMotion` treatment offered on **0/10** — evidence the shape is
// **downstream of tool choice** rather than a separate disease with its own
// cure. The entry's own instruction was *"a lane should test that directly
// before assuming it needs its own words,"* so there is deliberately **no
// prose-treatment arm here.** The arms are production, production with the
// pinned tool ambiguity restored, and a ceiling.
#if DEBUG
extension LocalChatBackend {

    /// The three arms, and why the third one is not optional.
    ///
    /// **A detector that never fires is indistinguishable from a clean run.**
    /// If production offers on 0/30 and the rollback offers on 0/30, that
    /// reading is consistent with "the disease is gone" AND with "the scorer
    /// is broken", and nothing else in the run separates them. The ceiling arm
    /// is the discriminator — the same reasoning as the deliberately-nonsense
    /// control verb in the plugin-deploy probe, and as #373's positive control
    /// on the button scan.
    enum OfferReadArm: String, CaseIterable {
        /// Production belt, production instructions, **the router in front** —
        /// the configuration the app actually ships. This is the arm whose
        /// number may be quoted as a production rate (#215); every other arm
        /// is a cell contrast.
        case control
        /// #211's PINNED ROLLBACK — `MotionTool.stepClaimingDescription211`,
        /// the pre-promotion description that still claims "today's step
        /// count" and therefore competes with `readHealth` for a step
        /// question. Instructions untouched; one description swapped.
        ///
        /// **This is the hypothesis under test, stated as a manipulation.**
        /// If restoring tool AMBIGUITY brings the offers back, the shape is
        /// downstream of tool choice and #211A needs no words of its own — it
        /// closes into #211's lineage. If it does not, the offer survives
        /// unambiguous tools and a prose lane is warranted on evidence rather
        /// than on assumption.
        ///
        /// Placed SECOND, immediately after the control, and that is a
        /// deliberate departure from this project's usual "newest arm last".
        /// The worst-slot convention exists to make a POSITIVE conservative
        /// when thermal drift would flatter it. Here the primary is a
        /// within-run contrast between exactly these two arms, and thermal
        /// drift would INFLATE the later one in the same direction as the
        /// hypothesis — so the honest placement is adjacent to its control,
        /// not maximally far from it.
        case toolRollback = "tool-rollback"
        /// **The intended CEILING and positive control — but its founding
        /// assumption is FALSIFIED (2026-08-27, #211A's two device runs).**
        /// Every tool in `offerReadToolNames` is removed; the action tools and
        /// the production instructions stay.
        ///
        /// ⚠️ This comment used to read *"The model now cannot answer a read
        /// question by calling anything, so offering (or an honest denial) is
        /// all that is left."* **It can.** Three tools are removed and the model
        /// keeps a dozen, so it SUBSTITUTES: measured over two runs (n=20 per
        /// prompt), `healthbare` answered with `readCalendar` — the user's
        /// schedule, in place of their health — and `weatherbare` with
        /// `currentLocation` + `searchPlaces("weather Saucier, MS")`. Both
        /// offered on **0 of 20**. The two prompts with no substitute,
        /// `motiondirect` and `stepsdirect`, offered 10/20 and 4/20.
        ///
        /// So this arm bounds nothing: D1's ≥50% assumes a ceiling that cannot
        /// act, and this one acts in 25 of 40 trials. Restricting scoring to the
        /// substitution-free prompts reaches only 35%. See `.toolless`, which
        /// exists to answer whether ≥50% is achievable at all.
        ///
        /// It is **not a promotion candidate and never could be** — dropping
        /// useful tools globally is a product regression, the #200U
        /// `armed-nocontact` precedent. It exists to bound the achievable
        /// contrast and, more importantly, to make a zero elsewhere in the run
        /// mean something.
        ///
        /// Placed LAST because it is a control rather than a finding: thermal
        /// drift can only push it in its already-expected direction, which is
        /// the cheapest place in the run to spend a confound.
        case noReadBelt = "no-read-belt"
        /// **The TOOLLESS probe (#211A-E1..E3, 2026-08-27).** Zero tools on the
        /// belt — not "the read ones removed", *all* of them. Substitution is
        /// the mechanism that made `.noReadBelt` fail as a ceiling, and this is
        /// the only arm in which substitution is impossible by construction.
        ///
        /// It answers ONE design question: is D1's ≥50% reachable by any arm on
        /// this runtime, or was the threshold never grounded? Its own rate is
        /// **not a pass/fail bar** — picking a threshold after seeing 17.5% and
        /// 35.0% would be exactly the post-hoc redefinition #215 bans.
        ///
        /// **Never a promotion candidate**, for `.noReadBelt`'s reason and more
        /// so: shipping an agent with no tools is not a product. The `cant` rate
        /// is reported beside the offer rate because the discriminating outcome
        /// (211A-E3) is the model DENYING rather than offering.
        case toolless = "toolless"
    }

    /// The READ tools these prompts could be answered with. Named as data
    /// because the ceiling arm removes exactly this set and the manipulation
    /// row counts exactly this set — two call sites that must not drift, and
    /// a hand-written `filter` in each is how they would.
    nonisolated static let offerReadToolNames: Set<String> = [
        "readHealth", "readMotion", "currentWeather",
    ]

    /// The three arms a DEFAULT `offer-read` run has always meant.
    ///
    /// Stated explicitly rather than left as `allCases` (#211A-E, 2026-08-27):
    /// `.toolless` was added to the enum as a diagnostic, and `allCases` would
    /// have silently turned every default run into four arms — changing what
    /// every previous `offer-read` artifact is comparable to, without one line
    /// of the diff saying so. A default that shifts when someone appends an
    /// enum case is not a default.
    nonisolated static let offerReadDefaultArms: [OfferReadArm] = [
        .control, .toolRollback, .noReadBelt,
    ]

    /// The prompt rows, **selected from the pinned sets by tag rather than
    /// retyped** (372-C3's rule, applied to prompts instead of clauses).
    ///
    /// Every row here is a string some earlier run already measured, so this
    /// instrument's cells are readable against #209's and #211's history. A
    /// fresh literal would have produced four prompts that merely LOOK like
    /// those — the two-copies problem that put the shipping blurb in two
    /// places before 2026-08-15.
    ///
    /// The resolution is checked by `theOfferReadPromptSetResolvesEveryTag`:
    /// `compactMap` over a renamed tag returns a SHORTER array, not an error,
    /// so an upstream rename would silently shrink the run and every rate in
    /// it would still look fine.
    nonisolated static let offerReadPromptTags = [
        // #211's disease prompt — the one with 4/10 offers on record.
        "stepsdirect",
        // #211's guard prompt: the promotion must not be re-broken, and a
        // motion question is where the promoted text earns its keep.
        "motiondirect",
        // #209's bare-field rows, on two DIFFERENT read tools — so a finding
        // here is about read paths rather than about one tool's description.
        "weatherbare",
        "healthbare",
    ]

    nonisolated static var offerReadBatteryPrompts: [(tag: String, text: String)] {
        let pool = motionScopeBatteryPrompts + readToolBatteryPrompts
        return offerReadPromptTags.compactMap { tag in pool.first { $0.tag == tag } }
    }

    /// The belt each arm registers, plus the two counts the manipulation row
    /// needs: how many tools were SWAPPED and how many read tools SURVIVED.
    ///
    /// Both numbers, not one. `swapped` catches a rollback that found no
    /// `MotionTool` to swap; `readToolsPresent` catches a ceiling arm that
    /// removed nothing — and neither can stand in for the other, because the
    /// two arms fail in opposite directions.
    nonisolated static func offerReadBelt(from tools: [any Tool], arm: OfferReadArm)
        -> (belt: [any Tool], swapped: Int, readToolsPresent: Int) {
        var swapped = 0
        let belt: [any Tool]
        // Enumerated rather than negated, for `cardClauseBelt`'s reason: a
        // future arm must state its intent here instead of inheriting the
        // control's by default.
        switch arm {
        case .control:
            belt = tools
        case .toolRollback:
            belt = tools.map { tool in
                if var motion = tool as? MotionTool {
                    motion.description = MotionTool.stepClaimingDescription211
                    swapped += 1
                    return motion
                }
                return tool
            }
        case .noReadBelt:
            belt = tools.filter { !offerReadToolNames.contains($0.name) }
        case .toolless:
            // #211A-E1: EVERY tool, not a named subset. `.noReadBelt` filters by
            // `offerReadToolNames` and that is exactly why it failed as a
            // ceiling — the model reached for whatever was left. An empty belt
            // is the only construction substitution cannot defeat.
            belt = []
        }
        return (belt, swapped, belt.filter { offerReadToolNames.contains($0.name) }.count)
    }

    // MARK: - The scorer

    /// The prose shapes that OFFER to do the read instead of doing it.
    ///
    /// Deliberately narrow, and every shape is interrogative-or-conditional by
    /// construction: this detects the model handing the decision back, not the
    /// model describing what it can do. *"I can check your steps"* as a bare
    /// statement is a capability claim and is **not** here; *"I can check your
    /// steps if you'd like"* is, because the conditional is the hand-back.
    ///
    /// The seed is #211A's own recorded specimen — *"Would you like me to
    /// check your health data for other metrics?"* — widened only to the
    /// polite variants of the same move.
    nonisolated static let offerInsteadOfActShapes = [
        "would you like me to",
        "do you want me to",
        "shall i check",
        "shall i look",
        "should i check",
        "should i look",
        "want me to check",
        "want me to look",
        "if you'd like me to",
        "if you would like me to",
        "let me know if you'd like",
        "let me know if you want",
        "just say the word",
    ]

    /// The matched shape, or nil. Apostrophes are normalized through the
    /// shared `normalizedForMatching`, which exists because #225 B3's first
    /// classifier pass used a straight apostrophe against a model that types
    /// curly ones and read every hit as a miss.
    nonisolated static func offerInsteadOfAct(in text: String) -> String? {
        let normalized = normalizedForMatching(text)
        return offerInsteadOfActShapes.first { normalized.contains($0) }
    }

    /// **The four buckets, and the reason they are four rather than two.**
    ///
    /// An offer is only the defect when the model offered *instead of* acting.
    /// #211A's own specimen — *"…check your health data for **other
    /// metrics**?"* — reads like a follow-on to an answer that was given, and
    /// a scorer that counted every offer shape would fold the courteous
    /// follow-up into the defect and inflate the rate with good turns. So the
    /// discriminator is the TOOL CALL, and both readings are recorded side by
    /// side and never collapsed (`+CardClause.swift`'s mechanism/behaviour
    /// rule).
    ///
    /// `neitherActedNorOffered` is the residue — denials, stalls, empty
    /// replies — and it is a NAMED bucket rather than an implied remainder,
    /// because 340-H5′-B's guard is only writable if the residue has a name: a
    /// treatment that stops offers by producing silence has not helped anyone.
    enum OfferReadVerdict: String, Sendable, CaseIterable {
        /// 🔴 The defect: an offer shape, and no tool was called.
        case offeredWithoutActing
        /// Benign: the model acted AND offered more. Counted, never pooled
        /// with the defect.
        case offeredAfterActing
        /// Clean: a tool was called and no offer shape appeared.
        case actedNoOffer
        /// Neither — a denial, a stall, an empty reply, an error.
        case neitherActedNorOffered
    }

    /// Classify one trial. Pure, so the bar is a unit test rather than a
    /// device run.
    ///
    /// **A nil reply is `neitherActedNorOffered` only when nothing was called,
    /// and that is not a technicality.** A trial that threw after calling a
    /// tool did act; scoring it as residue would let an arm with a high error
    /// rate look like an arm that stopped offering.
    nonisolated static func offerReadVerdict(replyText: String?,
                                             toolCallsAdmitted: Int) -> OfferReadVerdict {
        let offered = replyText.flatMap { offerInsteadOfAct(in: $0) } != nil
        switch (offered, toolCallsAdmitted > 0) {
        case (true, false): return .offeredWithoutActing
        case (true, true): return .offeredAfterActing
        case (false, true): return .actedNoOffer
        case (false, false): return .neitherActedNorOffered
        }
    }

    /// One trial of the battery.
    struct OfferReadTrialOutcome {
        var replyText: String?
        var error: String?
        var timedOut = false
        var cutFired = false
        var toolCallsAdmitted = 0
        /// #215: whether the ROUTER armed this trial. The primary rate is
        /// computed over armed-routed trials only — a trial the router sent
        /// toolless has no belt at all, which is the ceiling arm's condition
        /// arriving by accident, and pooling it into the control's numerator
        /// would import exactly the contamination this instrument's third arm
        /// exists to isolate.
        var routedArmed = true
        var routeFailed = false
    }

    // MARK: - The run

    /// #211A. Three arms × four read prompts × `trials`.
    ///
    /// **Auto-DECLINE, and nothing here can write anyway.** The prompts are
    /// read questions and the tools that answer them are read tools; the
    /// action tools ride the production belt only because removing them would
    /// change the belt in a second way. Auto-decline is checked first in
    /// `ToolConfirmationCenter.requestConfirmation`, so a grab still creates
    /// nothing and the reap is a no-op — the instrument is
    /// unattended-eligible.
    ///
    /// **A turn boundary before every trial** (#343). `runActionBattery` did
    /// not have one until 2026-08-15 and every battery rate measured between
    /// 2026-08-02 and that fix is governor-strangled; an instrument written
    /// after that finding has no excuse for repeating it.
    ///
    /// **The router runs per trial**, so the control's rate carries #215's
    /// warrant rather than its caveat — 337-C's lesson, applied at build time
    /// instead of as a follow-on bar.
    func runOfferReadBattery(trials: Int, arms: [OfferReadArm] = LocalChatBackend.offerReadDefaultArms,
                             warmup: Bool = LocalChatBackend.batteryWarmupDefault) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let prompts = Self.offerReadBatteryPrompts
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
        Self.batteryEmit("battery: START trials=\(trials) arms=\(arms.count) prompts=\(prompts.count) warmup=\(warmup) (#211A offer-read)")
        // #200V: through the CONTROL's construction — arm 1 is the control and
        // a cold control against two warm arms is a confound sitting exactly
        // where this battery's contrast would be.
        if warmup {
            await runDiscardedWarmup(belt: base, instructions: productionInstructions,
                                     options: options, item: "#211A")
        }
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: arms.map(\.rawValue),
                                      kind: "offer-read")

        for arm in arms {
            emitThermal(cell: arm.rawValue, at: "start")
            let (belt, swapped, readToolsPresent) = Self.offerReadBelt(from: base, arm: arm)
            // The MANIPULATION CHECK, recorded before any trial runs — an arm
            // whose treatment did not apply must not let its null pool with
            // the control's.
            Self.batteryRecorder.recordProbe(
                probe: "211A manipulation check \(arm.rawValue)",
                expected: true,
                correct: Self.offerReadManipulationApplied(
                    arm: arm, swapped: swapped, readToolsPresent: readToolsPresent,
                    beltCount: belt.count) ? 1 : 0,
                trials: 1, variant: arm.rawValue, band: "manipulation", errors: 0,
                metrics: [
                    "descriptionsSwapped": Double(swapped),
                    "readToolsPresent": Double(readToolsPresent),
                    "beltSize": Double(belt.count),
                    "instructionsChars": Double(productionInstructions.count),
                    // Measured in the text actually passed, never inferred
                    // from the arm's name: this instrument changes NO
                    // instruction byte in any arm, and the row has to be able
                    // to prove that rather than assert it.
                    "stepClaimPresentInBelt":
                        belt.contains { $0.description.contains("today's step count") } ? 1 : 0,
                ],
                notes: [
                    "expectedManipulation": {
                        switch arm {
                        case .control: return "none (control)"
                        case .toolRollback: return "1 description swap (MotionTool), instructions untouched"
                        case .noReadBelt: return "the 3 offerReadToolNames removed (NOT every read tool — #211A), instructions untouched"
                        case .toolless: return "every tool removed (belt empty), instructions untouched"
                        }
                    }(),
                    "noProseArm": "#211A tests tool choice FIRST per the entry — no arm here changes an instruction",
                ])
            Self.batteryEmit("battery: ARM \(arm.rawValue) swapped=\(swapped) readTools=\(readToolsPresent) belt=\(belt.count) (#211A)")

            var attempted = 0
            var routedArmedTrials = 0
            var routedToollessTrials = 0
            var routeFailures = 0
            var generationErrors = 0
            var timeouts = 0
            var cutTrials = 0
            var repliesNonEmpty = 0
            // Tallied twice: over every attempt, and over the ARMED-routed
            // subset that is the primary denominator. Both are reported, per
            // 340-H5′-C — the one time the two denominators disagreed, the
            // disagreement was the finding.
            var verdicts: [OfferReadVerdict: Int] = [:]
            var armedVerdicts: [OfferReadVerdict: Int] = [:]
            var trialsWithToolCalls = 0

            for (tag, prompt) in prompts {
                for trial in 1...trials {
                    let trialTag = Self.refusalTrialTag(cell: arm.rawValue, prompt: tag, trial: trial)
                    ToolEventRelay.batteryTrialTag = trialTag
                    Self.batteryEmit("battery: BEGIN \(trialTag)")
                    Self.batteryRecorder.beginTrial()
                    toolRelay?.beginTurn()
                    attempted += 1

                    let outcome = await executeOfferReadTrial(
                        belt: belt, instructions: productionInstructions,
                        options: options, prompt: prompt)

                    let verdict = Self.offerReadVerdict(replyText: outcome.replyText,
                                                        toolCallsAdmitted: outcome.toolCallsAdmitted)
                    verdicts[verdict, default: 0] += 1
                    if outcome.routedArmed {
                        routedArmedTrials += 1
                        armedVerdicts[verdict, default: 0] += 1
                    } else {
                        routedToollessTrials += 1
                    }
                    if outcome.routeFailed { routeFailures += 1 }
                    if outcome.toolCallsAdmitted > 0 { trialsWithToolCalls += 1 }
                    if outcome.cutFired { cutTrials += 1 }
                    if outcome.timedOut { timeouts += 1 }
                    if outcome.error != nil && !outcome.cutFired && !outcome.timedOut { generationErrors += 1 }
                    if let text = outcome.replyText, !text.isEmpty { repliesNonEmpty += 1 }

                    recordOfferReadTrial(outcome, arm: arm, promptTag: tag, trial: trial,
                                         trialTag: trialTag, verdict: verdict)
                }
            }
            // `correct` = trials scoring the DEFECT, over counted attempts. The
            // error tallies name the trials that could not answer the question
            // at all, so a band where every trial threw reports 0/n with n
            // errors rather than a clean zero rate (#215, and `21F0C10D`).
            Self.batteryRecorder.recordProbe(
                probe: "211A arm summary \(arm.rawValue)",
                expected: true,
                correct: verdicts[.offeredWithoutActing] ?? 0, trials: attempted,
                variant: arm.rawValue, band: "offer-read-summary",
                errors: generationErrors + timeouts,
                metrics: [
                    "attempted": Double(attempted),
                    "routedArmedTrials": Double(routedArmedTrials),
                    "routedToollessTrials": Double(routedToollessTrials),
                    "routeFailures": Double(routeFailures),
                    "trialsWithToolCalls": Double(trialsWithToolCalls),
                    "repliesNonEmpty": Double(repliesNonEmpty),
                    "cutTrials": Double(cutTrials),
                    "generationErrors": Double(generationErrors),
                    "timeouts": Double(timeouts),
                    "descriptionsSwapped": Double(swapped),
                    "readToolsPresent": Double(readToolsPresent),
                    // All four buckets, under BOTH denominators (340-H5′-C).
                    // Never a union: an `offeredWithoutActing` traded for a
                    // `neitherActedNorOffered` is not an improvement, and a
                    // single combined number could not say so.
                    "offeredWithoutActing": Double(verdicts[.offeredWithoutActing] ?? 0),
                    "offeredAfterActing": Double(verdicts[.offeredAfterActing] ?? 0),
                    "actedNoOffer": Double(verdicts[.actedNoOffer] ?? 0),
                    "neitherActedNorOffered": Double(verdicts[.neitherActedNorOffered] ?? 0),
                    "armedOfferedWithoutActing": Double(armedVerdicts[.offeredWithoutActing] ?? 0),
                    "armedOfferedAfterActing": Double(armedVerdicts[.offeredAfterActing] ?? 0),
                    "armedActedNoOffer": Double(armedVerdicts[.actedNoOffer] ?? 0),
                    "armedNeitherActedNorOffered": Double(armedVerdicts[.neitherActedNorOffered] ?? 0),
                ],
                notes: [
                    "primary": "offeredWithoutActing / routedArmedTrials — the ARMED-routed denominator, per #215",
                    "guard": "neitherActedNorOffered must not rise: an offer traded for a stall is not a cure (340-H5′-B)",
                    "ceiling": "the no-read-belt arm is a POSITIVE CONTROL — if it does not offer, the scorer is blind and no other arm may be read",
                ])
            Self.batteryEmit("battery: ARM SUMMARY \(arm.rawValue) attempted=\(attempted) armedRouted=\(routedArmedTrials) offerNoAct=\(verdicts[.offeredWithoutActing] ?? 0) offerAfterAct=\(verdicts[.offeredAfterActing] ?? 0) acted=\(verdicts[.actedNoOffer] ?? 0) neither=\(verdicts[.neitherActedNorOffered] ?? 0) genErrors=\(generationErrors) timeouts=\(timeouts) (#211A)")
            emitThermal(cell: arm.rawValue, at: "end")
        }
        ToolEventRelay.batteryTrialTag = nil
        Self.batteryEmit("battery: DONE (#211A)")
        Self.batteryRecorder.endRun()
    }

    /// Whether the arm's treatment applied — the manipulation band's `correct`
    /// column, extracted so it can be asserted rather than trusted. The
    /// `cardClauseManipulationApplied` shape, and it exists here from the
    /// start because that one was written as an inline ternary and was WRONG
    /// for three arms for five days.
    nonisolated static func offerReadManipulationApplied(arm: OfferReadArm,
                                                         swapped: Int,
                                                         readToolsPresent: Int,
                                                         beltCount: Int) -> Bool {
        switch arm {
        case .control: return true
        case .toolRollback: return swapped > 0
        case .noReadBelt: return readToolsPresent == 0
        // #211A-E1: `readToolsPresent == 0` is ALSO true of `.noReadBelt`, so it
        // cannot witness this arm — an empty belt is the claim, and only
        // beltCount can state it.
        case .toolless: return beltCount == 0
        }
    }

    private func executeOfferReadTrial(belt: [any Tool], instructions: String,
                                       options: GenerationOptions,
                                       prompt: String) async -> OfferReadTrialOutcome {
        var outcome = OfferReadTrialOutcome()
        // #215: sample the failure tally across the routing call.
        // `routeNeedsDeviceTool` fails SAFE — a thrown generation returns
        // `armed` — so without this the record cannot tell a classification
        // from a crash, which is #213's bug.
        let failuresBefore = Self.routerFailureTally
        let needsTool = await routeNeedsDeviceTool(prompt: prompt)
        outcome.routeFailed = Self.routerFailureTally > failuresBefore
        outcome.routedArmed = needsTool
        Self.batteryEmit("battery: route=\(needsTool ? "armed" : "toolless") failed=\(outcome.routeFailed) (#211A)")
        Self.batteryRecorder.recordRoute(needsTool ? "armed" : "toolless", failed: outcome.routeFailed)
        // Through the shared seam, never a hand-built toolless turn: that is
        // how #215's own instrument went stale the day #202D promoted clause
        // v2. The ARM's belt transform has already been applied, so a toolless
        // route drops it — correctly, because production drops the belt too.
        let shaped = Self.routedTrialShape(
            needsTool: needsTool, armedBelt: belt, armedInstructions: instructions,
            deviceContext: Self.deviceContextLine())

        let executedBefore = toolRelay?.executedCallsThisTurn ?? 0
        let session = LanguageModelSession(model: model, tools: shaped.belt,
                                           instructions: Instructions(shaped.instructions))
        let respondTask = Task { try await session.respond(to: Prompt(prompt), options: options) }
        let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
        do {
            outcome.replyText = try await respondTask.value.content
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
        return outcome
    }

    private func recordOfferReadTrial(_ outcome: OfferReadTrialOutcome, arm: OfferReadArm,
                                      promptTag: String, trial: Int, trialTag: String,
                                      verdict: OfferReadVerdict) {
        if let text = outcome.replyText {
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

        var notes: [String: String] = ["verdict": verdict.rawValue]
        if let text = outcome.replyText { notes["replyText"] = text }
        if let shape = outcome.replyText.flatMap({ Self.offerInsteadOfAct(in: $0) }) {
            notes["offerShape"] = shape
        }
        if let error = outcome.error { notes["error"] = String(error.prefix(400)) }
        notes["route"] = outcome.routedArmed ? "armed" : "toolless"

        Self.batteryRecorder.recordProbe(
            probe: "211A \(trialTag)",
            expected: true,
            correct: verdict == .offeredWithoutActing ? 1 : 0, trials: 1,
            variant: arm.rawValue, band: "offer-read-trial",
            errors: (outcome.error != nil && !outcome.cutFired ? 1 : 0),
            metrics: [
                // The DEFECT reading and the BEHAVIOUR reading, side by side
                // and never collapsed — a manipulation that stops the offer
                // without producing a call has moved one and not the other,
                // and one number could not say which.
                "offeredWithoutActing": verdict == .offeredWithoutActing ? 1 : 0,
                "offeredAfterActing": verdict == .offeredAfterActing ? 1 : 0,
                "toolCallsAdmitted": Double(outcome.toolCallsAdmitted),
                "routedArmed": outcome.routedArmed ? 1 : 0,
                "routeFailed": outcome.routeFailed ? 1 : 0,
                "cutFired": outcome.cutFired ? 1 : 0,
                "timedOut": outcome.timedOut ? 1 : 0,
                // Co-recorded rather than used to suppress the verdict. A
                // reply that denies AND offers is a real specimen class; a
                // guard that swallowed it would under-count the defect, and a
                // guard that scored it would confuse #202D's honest refusal
                // with this one. Partitioning is the reader's job and this is
                // the column that lets them do it.
                "denial": Self.batteryDenialPatterns.contains {
                    (outcome.replyText ?? "").lowercased().contains($0)
                } ? 1 : 0,
            ],
            notes: notes)

        Self.batteryEmit("battery: \(trialTag) verdict=\(verdict.rawValue) offer=\(notes["offerShape"] ?? "—") calls=\(outcome.toolCallsAdmitted) route=\(notes["route"] ?? "—") (#211A)")
    }
}
#endif
