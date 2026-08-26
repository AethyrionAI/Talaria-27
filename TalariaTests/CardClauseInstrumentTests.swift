#if DEBUG
import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// #337 bar 337-F — the confirmation-card A/B, tested STRUCTURALLY.
///
/// The sim cannot generate, so nothing here asserts a rate. What it pins is
/// the part of an A/B that can be wrong without anyone noticing: that the
/// treatment ACTUALLY REMOVES something, that the control is production
/// verbatim, that the manipulation is recorded so a no-op treatment cannot
/// masquerade as a null result, and that the run seals with counted error
/// tallies when every trial throws.
struct CardClauseManipulationTests {

    /// **The guard against the whole A/B silently becoming a no-op.** The
    /// treatment strings are derived by removal; if production is ever
    /// reworded and the clause constant is not, the removal quietly stops
    /// removing and both arms become the control — the run then reports a
    /// clean null for a manipulation that never happened. This is the test
    /// that goes red instead.
    @Test func everyActionToolsTreatmentTextActuallyLosesTheClause() {
        let pairs = [
            (ReminderCreateTool.productionDescription, ReminderCreateTool.cardClauseStripped337),
            (CalendarEventTool.productionDescription, CalendarEventTool.cardClauseStripped337),
            (AlarmTool.productionDescription, AlarmTool.cardClauseStripped337),
        ]
        for (production, stripped) in pairs {
            #expect(production.contains("confirmation card"),
                    "production description no longer carries the clause: \(production)")
            #expect(stripped != production, "the removal removed nothing from: \(production)")
            #expect(!stripped.lowercased().contains("confirmation card"),
                    "the clause survived the removal: \(stripped)")
            // Only the clause goes. The first sentence is what makes the two
            // arms differ in exactly one way.
            #expect(production.hasPrefix(stripped), "the removal changed more than the trailing clause")
        }
    }

    /// The blurb sentence is quoted verbatim from production's own armed
    /// instructions. If that sentence is reworded, arm C stops removing
    /// anything — and, like the description clause, the failure is silent
    /// without this.
    @MainActor
    @Test func theArmedBlurbSentenceIsPresentInProductionInstructions() {
        let instructions = LocalChatBackend.instructionsText(
            deviceContext: "test", hasTools: true, hasImageTools: false)
        // #337-F-2b PROMOTED 2026-08-15: the removal target is now whatever
        // SHIPS, read through the one alias production also uses. Asserting the
        // literal pre-promotion sentence here is what made this test go red on
        // the promotion — correctly, since its subject is "arm C can still find
        // its target", not "the target says the word card".
        #expect(instructions.contains(DeviceActionClauses.armedBlurbShippingSentence),
                "arm C's removal target is not in production's armed instructions")
        // And the PRE-promotion sentence must be GONE from production — this is
        // the half that fails if someone reverts the promotion without reverting
        // the alias, which would leave the arms stripping a sentence that is not
        // there and every treatment silently becoming its own control.
        #expect(!instructions.contains(DeviceActionClauses.armedBlurbSentencePre337F2b),
                "the pre-#337-F-2b sentence is still shipping")
        let (stripped, removed) = LocalChatBackend.cardClauseInstructions(
            instructions, arm: .toolsAndBlurbStripped)
        #expect(removed)
        #expect(!stripped.contains(DeviceActionClauses.armedBlurbShippingSentence))
    }

    /// The control must be production, byte for byte — an A/B whose control
    /// drifted is two treatments.
    @MainActor
    @Test func theControlArmChangesNothing() {
        let instructions = LocalChatBackend.instructionsText(
            deviceContext: "test", hasTools: true, hasImageTools: false)
        let (text, removed) = LocalChatBackend.cardClauseInstructions(instructions, arm: .control)
        #expect(text == instructions)
        #expect(!removed)

        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        let belt: [any Tool] = [ReminderCreateTool(relay: relay, confirmations: confirmations)]
        let (controlBelt, swapped) = LocalChatBackend.cardClauseBelt(from: belt, arm: .control)
        #expect(swapped == 0)
        #expect((controlBelt.first as? ReminderCreateTool)?.description
                == ReminderCreateTool.productionDescription)
    }

    /// All three action tools are swapped, and the count is reported — the
    /// record's manipulation row is only meaningful if this number is real.
    @MainActor
    @Test func theTreatmentSwapsEveryActionToolAndReportsHowMany() throws {
        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        let belt: [any Tool] = [
            ReminderCreateTool(relay: relay, confirmations: confirmations),
            CalendarEventTool(relay: relay, confirmations: confirmations),
            AlarmTool(relay: relay, confirmations: confirmations, alarmService: AlarmService()),
        ]
        let (treated, swapped) = LocalChatBackend.cardClauseBelt(from: belt, arm: .toolsStripped)
        #expect(swapped == 3)
        #expect(treated.count == belt.count, "the belt's size and order must not change")
        for tool in treated {
            #expect(LocalChatBackend.confirmationCardImitation(in: tool.description) == nil,
                    "\(tool.name) still teaches the phrase: \(tool.description)")
        }
    }

    /// **Production's shipping belt is unchanged by this lane.** The seam is a
    /// `var` with production's own static as its default; a call site that
    /// passes no description must still get production's text.
    @MainActor
    @Test func productionCallSitesStillGetProductionDescriptions() {
        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        #expect(CalendarEventTool(relay: relay, confirmations: confirmations).description
                == CalendarEventTool.productionDescription)
        #expect(AlarmTool(relay: relay, confirmations: confirmations, alarmService: AlarmService()).description
                == AlarmTool.productionDescription)
        #expect(ReminderCreateTool(relay: relay, confirmations: confirmations).description
                == ReminderCreateTool.productionDescription)
    }

    /// **337-F-2's whole reason for existing.** Arm C removes the descriptions
    /// AND the blurb, so its 0/30 was attributable to the blurb only by
    /// elimination. This arm removes the blurb ALONE — which means the
    /// descriptions must come through as production's own text, byte for byte.
    ///
    /// The production change that makes this fail: `cardClauseBelt` treats
    /// "not the control" as "strip the descriptions" (`guard arm != .control`),
    /// which is exactly what it did when this arm was added. Under that guard
    /// the new arm is silently arm C and the isolation is lost while the
    /// artifact still reports a distinct arm name — a treatment that reads as
    /// clean and is measuring the wrong thing.
    @MainActor
    @Test func theBlurbOnlyArmRemovesTheBlurbAndLeavesTheDescriptionsAlone() {
        let instructions = LocalChatBackend.instructionsText(
            deviceContext: "test", hasTools: true, hasImageTools: false)
        let (stripped, removed) = LocalChatBackend.cardClauseInstructions(
            instructions, arm: .blurbStripped)
        #expect(removed, "the blurb-only arm removed nothing from the instructions")
        // #337-F-2b PROMOTED 2026-08-15 — the arm strips what SHIPS.
        #expect(!stripped.contains(DeviceActionClauses.armedBlurbShippingSentence))

        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        let belt: [any Tool] = [
            ReminderCreateTool(relay: relay, confirmations: confirmations),
            CalendarEventTool(relay: relay, confirmations: confirmations),
            AlarmTool(relay: relay, confirmations: confirmations, alarmService: AlarmService()),
        ]
        let (untouched, swapped) = LocalChatBackend.cardClauseBelt(
            from: belt, arm: .blurbStripped)
        #expect(swapped == 0, "the blurb-only arm must not touch the descriptions")
        #expect((untouched.first as? ReminderCreateTool)?.description
                == ReminderCreateTool.productionDescription,
                "the descriptions must be production's own text in this arm")
        for tool in untouched {
            #expect(LocalChatBackend.confirmationCardImitation(in: tool.description) != nil,
                    "\(tool.name) lost the phrase — this arm leaves the descriptions ALONE")
        }
    }

    /// **337-F-2b — the REWORDED arm.** 337-F-2 proved the blurb sentence alone
    /// is sufficient for both the impersonation and the missing tool calls, but
    /// DELETING it also deletes decline guidance the three-create prompt set
    /// never exercises. This arm replaces rather than removes: the decline
    /// instruction survives, the card vocabulary does not.
    ///
    /// The replacement must lose the word "confirmation" outright, not just
    /// "card" — BOTH observed specimens are seeded by it (`Confirmation card:`
    /// and `Here's the confirmation`), so a rewording that kept "confirmation"
    /// would leave half the seed in place and a null would mean nothing.
    @Test func theRewordedSentenceKeepsDeclineGuidanceAndDropsTheCardVocabulary() {
        let reworded = DeviceActionClauses.armedBlurbCardSentenceReworded337F2
        #expect(LocalChatBackend.confirmationCardImitation(in: reworded) == nil,
                "the replacement still carries an imitation shape: \(reworded)")
        #expect(!reworded.lowercased().contains("confirmation"),
                "the replacement still seeds the word 'confirmation': \(reworded)")
        #expect(!reworded.lowercased().contains("card"),
                "the replacement still seeds the word 'card': \(reworded)")
        #expect(reworded.lowercased().contains("decline"),
                "the replacement dropped the decline guidance it exists to keep")
    }

    /// ~~The reworded arm SUBSTITUTES: production's sentence gone, the
    /// replacement present, descriptions untouched.~~
    ///
    /// **REWRITTEN 2026-08-15 — the arm is now IDENTITY WITH CONTROL, because
    /// Owen promoted the sentence it used to substitute in.** What this test
    /// pins is therefore the opposite of what it pinned yesterday: that the arm
    /// CANNOT differ from production, that the promoted sentence is what ships,
    /// and that the pre-promotion sentence is gone. Measuring the promotion now
    /// needs a ROLLBACK arm substituting the other way (#200L's shape); it does
    /// not exist yet, and this test is not a substitute for one.
    @MainActor
    @Test func theRewordedArmSubstitutesAndLeavesTheDescriptionsAlone() {
        let instructions = LocalChatBackend.instructionsText(
            deviceContext: "test", hasTools: true, hasImageTools: false)
        let (text, changed) = LocalChatBackend.cardClauseInstructions(
            instructions, arm: .blurbReworded)
        // ⚠️ THIS ASSERTION INVERTED ON 2026-08-15 AND THE INVERSION IS THE
        // POINT. The arm substitutes pre-promotion → reworded. Owen promoted the
        // reworded sentence, so production no longer contains the pre-promotion
        // text and the substitution finds nothing: `changed` is now FALSE and
        // the arm is IDENTITY WITH CONTROL.
        //
        // That is the `armed-cardfix` precedent repeating (#200K): a treatment
        // cell whose treatment shipped becomes identity, which is not a broken
        // cell — it is what lets the arm POOL with the control as a re-verify.
        // The test asserts the identity rather than deleting itself, because the
        // property worth pinning is now "this arm cannot silently differ from
        // production", and because a future rollback would flip it straight back.
        #expect(!changed,
                "the reworded arm is post-promotion identity; a change means production drifted off armedBlurbShippingSentence")
        #expect(text == instructions, "identity arm altered the instructions")
        // The shipping text is the reworded one either way.
        #expect(text.contains(DeviceActionClauses.armedBlurbCardSentenceReworded337F2),
                "the promoted sentence is not in production's instructions")
        #expect(!text.contains(DeviceActionClauses.armedBlurbSentencePre337F2b),
                "the pre-promotion sentence is still present")
        // NOT `confirmationCardImitation(in: text) == nil`. That assertion was
        // written first and failed — correctly. The promoted
        // `cardNarrationClause` (#200J/#200K) is held CONSTANT in every arm and
        // itself contains the words "confirmation card"; removing it would
        // confound this manipulation with rolling back a promotion. **No arm
        // here is a zero-exposure arm**, by design, and a test demanding zero
        // exposure would have forced the wrong change to the instrument.
        #expect(text.contains("never write the card out"),
                "the promoted countermeasure must survive in the reworded arm")

        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        let belt: [any Tool] = [ReminderCreateTool(relay: relay, confirmations: confirmations)]
        let (untouched, swapped) = LocalChatBackend.cardClauseBelt(
            from: belt, arm: .blurbReworded)
        #expect(swapped == 0, "the reworded arm must not touch the descriptions")
        #expect((untouched.first as? ReminderCreateTool)?.description
                == ReminderCreateTool.productionDescription)
    }

    /// Arm C must keep moving BOTH strings — the new arm is an addition, not a
    /// re-pointing of the old one.
    @MainActor
    @Test func theToolsAndBlurbArmStillMovesBothStrings() {
        let instructions = LocalChatBackend.instructionsText(
            deviceContext: "test", hasTools: true, hasImageTools: false)
        let (_, removed) = LocalChatBackend.cardClauseInstructions(
            instructions, arm: .toolsAndBlurbStripped)
        #expect(removed)

        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        let belt: [any Tool] = [ReminderCreateTool(relay: relay, confirmations: confirmations)]
        let (treated, swapped) = LocalChatBackend.cardClauseBelt(
            from: belt, arm: .toolsAndBlurbStripped)
        #expect(swapped == 1)
        #expect(LocalChatBackend.confirmationCardImitation(
            in: treated.first?.description ?? "") == nil)
    }
}

struct ConfirmationCardImitationDetectorTests {

    /// #337-A's reply, verbatim. The detector exists for this string.
    @Test func detectsTheProductionTurnThatFoundTheDefect() {
        let reply = "**Confirmation card:** A reminder to \u{201C}take out the trash\u{201D} at 8 AM has been created."
        #expect(LocalChatBackend.confirmationCardImitation(in: reply) == "confirmation card")
    }

    /// **The curly-apostrophe trap, pre-empted.** #225 B3's first classifier
    /// pass used a straight apostrophe and the model writes curly ones, so
    /// every claim read as a non-claim. `Here's` is exactly that shape.
    @Test func detectsTheOfferShapeWithEitherApostrophe() {
        let curly = "Here\u{2019}s the confirmation \u{2014} would you like me to create this reminder?"
        let straight = "Here's the confirmation — would you like me to create this reminder?"
        #expect(LocalChatBackend.confirmationCardImitation(in: curly) == "here's the confirmation")
        #expect(LocalChatBackend.confirmationCardImitation(in: straight) == "here's the confirmation")
    }

    /// Narrow on purpose. An action CLAIM is #336's question and a different
    /// detector's job; this one answers "did the model imitate the app's own
    /// affordance", and a claim without the UI vocabulary is not that.
    @Test func doesNotFireOnAPlainActionClaim() {
        #expect(LocalChatBackend.confirmationCardImitation(in: "I've set a reminder for 4:30 PM.") == nil)
        #expect(LocalChatBackend.confirmationCardImitation(in: "Your alarm is set for 6:30.") == nil)
    }
}

struct CardClauseRegistryTests {

    @Test func cardClauseIsRegisteredAsAWriteFreeDeclineInstrument() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "card-clause"))
        #expect(spec.confirmationMode == .autoDecline)
        #expect(!spec.writesEventKit && !spec.writesAlarms)
    }

    /// #372(b): the focused remedy A/B is registered with the SAME derived
    /// flags. A two-arm sibling that quietly declared different capabilities
    /// would be a spec bug the conductor acts on, not a documentation nit.
    @Test func theRemedyABIsRegisteredWithTheSameWriteFreeDeclineFlags() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "card-clause-remedy"))
        #expect(spec.confirmationMode == .autoDecline)
        #expect(!spec.writesEventKit && !spec.writesAlarms)
        #expect(spec.defaultCells == nil)
    }

    /// 372-C5: this pin is what makes adding an arm without naming it a
    /// failure rather than a silent widening of the export vocabulary — the
    /// same shape as `ActionBatteryCell.allCases.count`, which caught #340's
    /// new case on 2026-08-21. Five → six with #372(c)'s rollback; **six →
    /// seven with #372(b)'s `.required` remedy (2026-08-26)**, and it fired as
    /// designed: the arm landed, this pin went red, and the arm had to be
    /// named before the suite would pass.
    @Test func theABHasSevenNamedArmsWithTheRemedyOneLast() {
        #expect(LocalChatBackend.CardClauseArm.allCases.map(\.rawValue)
                == ["control", "tools-stripped", "tools-blurb-stripped",
                    "blurb-stripped", "blurb-reworded", "blurb-rollback",
                    "toolmode-required"])
    }

    // MARK: - #372(b) / 337-H — the `.required` remedy's structural bars

    /// 🔴 **372-H1 — EXACTLY ONE arm forces the tool-calling mode.**
    ///
    /// The remedy's whole claim is that it is a DECODING change rather than a
    /// prose one, so it is only interpretable against arms that leave the mode
    /// alone. An arm that quietly inherited the forced mode would turn its own
    /// prose result into a bundle of two treatments.
    @Test func theOnlyArmThatForcesToolCallingIsTheRemedy() {
        for arm in LocalChatBackend.CardClauseArm.allCases {
            #expect(LocalChatBackend.cardClauseForcesToolCalling(arm: arm)
                    == (arm == .toolmodeRequired),
                    "\(arm.rawValue) disagrees with the one-forced-arm rule")
        }
    }

    /// 🔴 **372-H2 — the remedy changes NEITHER descriptions NOR instructions.**
    /// If it moved a string as well as the mode, its delta would be
    /// unattributable — the exact confound `cardClauseBelt`'s enumerated
    /// switch and `cardClauseInstructions`' explicit cases exist to prevent.
    @MainActor
    @Test func theRemedyArmLeavesEveryStringAlone() {
        let belt: [any Tool] = [
            ReminderCreateTool(relay: ToolEventRelay(), confirmations: ToolConfirmationCenter())
        ]
        let swapped = LocalChatBackend.cardClauseBelt(from: belt, arm: .toolmodeRequired)
        #expect(swapped.swapped == 0, "the remedy arm must not touch descriptions")

        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone running iOS 27.0.",
            hasTools: true, hasImageTools: false)
        let result = LocalChatBackend.cardClauseInstructions(production, arm: .toolmodeRequired)
        #expect(result.removed == false)
        #expect(result.text == production,
                "the remedy arm moved an instruction byte — its delta would be a bundle, not a mode")
    }

    /// 🔴 **372-H3 — PRODUCTION SETS NO TOOL-CALLING MODE, and this lane does
    /// not change that.** #337-H named the remedy and Owen's direction was
    /// explicit that it ships as an ARM: the device A/B decides, not the build.
    /// This is the pin that goes red if a later lane promotes it by editing
    /// `chatGenerationOptions` instead of by measuring it.
    @Test func productionGenerationOptionsStillSetNoToolCallingMode() {
        // Both tiers named as literals rather than swept: `LocalModelTier` is
        // not `CaseIterable`, and widening a production enum to satisfy a test
        // is a change to the thing under test.
        for tier: LocalChatBackend.LocalModelTier in [.onDevice, .privateCloud] {
            #expect(LocalChatBackend.chatGenerationOptions(for: tier).toolCallingMode == nil,
                    "production now sets a tool-calling mode for \(tier) — 337-H's remedy was promoted without a run")
        }
    }

    /// 🔴 **The manipulation column, and the DEFECT #372's lane found in it.**
    ///
    /// The expression that stood at the call site was
    /// `arm == .control ? 1 : (swapped > 0 ? 1 : 0)`, so every arm whose
    /// treatment is an INSTRUCTION swap scored 0 — `blurb-stripped` and
    /// `blurb-rollback` both applied cleanly on 2026-08-21 and both were
    /// recorded as treatments that had failed to apply. The column built to
    /// catch a silent no-op was itself silently wrong.
    ///
    /// `blurbReworded` returning false on `blurbRemoved == false` is CORRECT
    /// and is 372-C1's finding: post-promotion that arm is identity with
    /// control and the column should say so.
    @Test func theManipulationColumnIsTrueOnlyForArmsThatActuallyApplied() {
        typealias A = LocalChatBackend.CardClauseArm
        let applied = LocalChatBackend.cardClauseManipulationApplied

        #expect(applied(A.control, 0, false))
        #expect(applied(A.toolsStripped, 3, false))
        #expect(!applied(A.toolsStripped, 0, false))
        // Two-part treatment: half is not applied.
        #expect(applied(A.toolsAndBlurbStripped, 3, true))
        #expect(!applied(A.toolsAndBlurbStripped, 3, false))
        #expect(!applied(A.toolsAndBlurbStripped, 0, true))
        // The instruction arms — the three the old expression got wrong.
        #expect(applied(A.blurbStripped, 0, true))
        #expect(!applied(A.blurbStripped, 0, false))
        #expect(applied(A.blurbRollback, 0, true))
        #expect(!applied(A.blurbReworded, 0, false))
        // The remedy applies on its own terms and swaps nothing at all.
        #expect(applied(A.toolmodeRequired, 0, false))
    }

    // MARK: - #372(a) — the decline half, finally observable

    /// 🔴 **372-A1 — a trial with NO decline is NOT scored, and that is #215's
    /// rule rather than tidiness.**
    ///
    /// This is the bar the whole (a) half turns on. A reply cannot misattribute
    /// a refusal that never happened, so scoring a zero-decline trial enters a
    /// free verdict into the tally and dilutes the rate with rows that had no
    /// opportunity to fail. The text below WOULD score `.attributedToTool` if
    /// the guard were removed — which is exactly what makes this test
    /// isolating rather than decorative.
    @Test func aTrialWithNoDeclineIsNotScoredEvenWhenTheTextWouldScore() {
        let misattributing = "It seems the event couldn't be added."
        #expect(DeclineAttributionScorer.verdict(for: misattributing) == .attributedToTool,
                "the specimen no longer scores — this test's premise is gone")

        let row = LocalChatBackend.declineHalfRow(replyText: misattributing,
                                                  declinesObserved: 0)
        #expect(row.exercised == false)
        #expect(row.verdict == nil,
                "a trial where nothing was declined was scored for decline attribution")
    }

    /// The other side: when the half WAS exercised, the reply is scored, and it
    /// is scored by #392's scorer rather than by a second implementation.
    @Test func anExercisedDeclineIsScoredByTheSharedScorer() {
        let blamesTheTool = "It seems the event couldn't be added."
        let blamesNobody = "No event was created."
        let namesTheUser = "You declined, so the event wasn't created."

        #expect(LocalChatBackend.declineHalfRow(replyText: blamesTheTool, declinesObserved: 1)
                == (true, .attributedToTool))
        #expect(LocalChatBackend.declineHalfRow(replyText: blamesNobody, declinesObserved: 1)
                == (true, .actorUnnamed))
        #expect(LocalChatBackend.declineHalfRow(replyText: namesTheUser, declinesObserved: 2)
                == (true, .attributedToUser))
    }

    /// An exercised decline whose trial produced no text at all is EXERCISED
    /// with no verdict — not `unscorable`. The distinction is real: an absent
    /// reply is instrument state (a throw, a timeout), while `unscorable` is a
    /// reply nobody could classify, which is behaviour.
    @Test func anExercisedDeclineWithNoReplyIsExercisedButUnverdicted() {
        let row = LocalChatBackend.declineHalfRow(replyText: nil, declinesObserved: 1)
        #expect(row.exercised == true)
        #expect(row.verdict == nil)
    }
}

/// 🔴 **372-A2 — the gate COUNTS every decline it can produce.**
///
/// #372(a) went unfiled for so long because no instrument could see a decline:
/// `toolCallsAdmitted` is the governor's number and says a call got through,
/// not that the gate ever answered it. The counter is the thing instruments
/// read a delta off, so a site that forgot to increment would report a lower
/// decline rate than the truth and read exactly like a clean result.
///
/// **The assertions run against the PER-INSTANCE count, deliberately.** The
/// static mirror is what instruments read — they reach the gate through tools
/// they do not own — but it is process-global, and Swift Testing runs suites in
/// parallel, so an exact-equality assertion against it would fail whenever
/// another suite declined in the same instant. The negative control below ("an
/// approval must not move it") is the assertion that makes all three site tests
/// mean something, and it is only writable against a count nothing else can
/// touch. One test pins that the two counters move together.
@MainActor
struct ConfirmationDeclineCountingTests {

    @Test func theBatteryAutoDeclinePathIncrementsTheCounter() async {
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        _ = await center.requestConfirmation(
            title: "Create this reminder?",
            fields: [.init(key: "title", label: "Title", value: "t")])
        #expect(center.declineCount == 1,
                "the auto-decline path produced a decline the counter never saw")
    }

    @Test func theUsersOwnDeclineIncrementsTheCounter() async {
        let center = ToolConfirmationCenter()
        async let decision = center.requestConfirmation(
            title: "Schedule on this iPhone?",
            fields: [.init(key: "request", label: "Alarm", value: "6:30am")])
        while center.pending == nil { await Task.yield() }
        center.decline()
        _ = await decision
        #expect(center.declineCount == 1, "an explicit decline produced no count")
    }

    /// The defensive second-request decline — the site most likely to be
    /// forgotten, because it is the one that never renders a card and never
    /// passes through `resolve`.
    @Test func theDefensiveSecondRequestDeclineIncrementsTheCounter() async {
        let center = ToolConfirmationCenter()
        async let first = center.requestConfirmation(
            title: "First?", fields: [.init(key: "a", label: "A", value: "1")])
        while center.pending == nil { await Task.yield() }
        _ = await center.requestConfirmation(
            title: "Second?", fields: [.init(key: "b", label: "B", value: "2")])
        #expect(center.declineCount == 1,
                "the pending-collision decline is invisible to the counter")
        center.approve()
        _ = await first
        // The approval that followed must not have added one.
        #expect(center.declineCount == 1)
    }

    /// 🔴 The negative half, and it is what stops the three tests above from
    /// passing against a counter incremented on EVERY resolution.
    @Test func anApprovalDoesNotIncrementTheDeclineCounter() async {
        let center = ToolConfirmationCenter()
        async let decision = center.requestConfirmation(
            title: "Create?", fields: [.init(key: "title", label: "T", value: "x")])
        while center.pending == nil { await Task.yield() }
        center.approve()
        _ = await decision
        #expect(center.declineCount == 0, "an approval incremented the DECLINE counter")
    }

    /// The static mirror is the one instruments actually read, so it has to
    /// move with the instance count. Asserted as a `>= 1` delta for the reason
    /// in this suite's note — the point here is that the mirror moves AT ALL,
    /// which a drifted `noteDecline` would break silently.
    @Test func theStaticMirrorMovesWithTheInstanceCount() async {
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        let before = ToolConfirmationCenter.batteryDeclineCount
        _ = await center.requestConfirmation(
            title: "Create?", fields: [.init(key: "title", label: "T", value: "x")])
        #expect(center.declineCount == 1)
        #expect(ToolConfirmationCenter.batteryDeclineCount - before >= 1,
                "the instance counted a decline the static mirror did not — instruments read the mirror")
    }

    // MARK: - #372(c) — the rollback arm's structural bars

    /// 🔴 **372-C1 — the bar this arm exists because of.**
    ///
    /// `blurb-reworded` substitutes the PRE-promotion sentence for the
    /// reworded one. Production has shipped the reworded one since
    /// 2026-08-15, so that substitution matches nothing and the arm is
    /// identity with control. This test pins the state directly, so nobody has
    /// to rediscover it from a flat run: **the old arm no-ops on production
    /// text, and the new one does not.**
    @Test func theRewordedArmIsNowAnIdentityAndTheRollbackIsNot() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone running iOS 27.0.",
            hasTools: true, hasImageTools: false)

        let reworded = LocalChatBackend.cardClauseInstructions(production, arm: .blurbReworded)
        #expect(reworded.removed == false,
                "blurb-reworded still changes production text — the promotion may have been reverted")
        #expect(reworded.text == production)

        let rollback = LocalChatBackend.cardClauseInstructions(production, arm: .blurbRollback)
        #expect(rollback.removed == true,
                "the rollback arm did NOT substitute — a manipulation that silently no-ops is exactly what this arm was built to escape")
        #expect(rollback.text != production)
    }

    /// 372-C3: reached by its ALIAS, never a fresh literal. Two copies of the
    /// pinned text is how the shipping sentence came to live in two places
    /// before 2026-08-15; the fix then was to stop having two copies.
    @Test func theRollbackRestoresThePinnedPrePromotionSentenceExactly() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone running iOS 27.0.",
            hasTools: true, hasImageTools: false)
        let rolled = LocalChatBackend.cardClauseInstructions(production, arm: .blurbRollback).text

        #expect(rolled.contains(DeviceActionClauses.armedBlurbSentencePre337F2b),
                "the pre-promotion sentence is not present verbatim")
        #expect(!rolled.contains(DeviceActionClauses.armedBlurbShippingSentence),
                "the shipping sentence survived the rollback — the arm swapped nothing, or swapped into the wrong place")
    }

    /// 372-C2: one delta, and it is an INSTRUCTION delta. A rollback arm that
    /// also moved the tool descriptions would measure a bundle and report it
    /// as a sentence.
    /// `@MainActor` on the test, not the suite: `ToolEventRelay` and
    /// `ToolConfirmationCenter` are MainActor-isolated, and everything else in
    /// here is pure string work that has no reason to hop.
    @MainActor
    @Test func theRollbackArmLeavesToolDescriptionsAlone() {
        let belt: [any Tool] = [
            ReminderCreateTool(relay: ToolEventRelay(), confirmations: ToolConfirmationCenter())
        ]
        let result = LocalChatBackend.cardClauseBelt(from: belt, arm: .blurbRollback)
        #expect(result.swapped == 0, "the rollback arm must not touch descriptions (372-C2)")
    }

    /// The control stays a control. Cheap, and it is the assertion that would
    /// catch a substitution accidentally applied to every arm.
    @Test func theControlArmStillChangesNothing() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone running iOS 27.0.",
            hasTools: true, hasImageTools: false)
        let control = LocalChatBackend.cardClauseInstructions(production, arm: .control)
        #expect(control.removed == false)
        #expect(control.text == production)
    }
}

/// `.serialized` for the same reason #335's run tests are: one shared static
/// recorder and run store behind `beginBatteryRun()`'s global mutex.
@Suite(.serialized)
@MainActor
struct CardClauseInstrumentRunTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "card-clause-instrument-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    private func idsOnDisk() -> Set<UUID> {
        Set(LocalChatBackend.batteryRunStore.loadRuns().map(\.id))
    }

    private func freshRun(after known: Set<UUID>) throws -> BatteryRunRecord {
        try #require(LocalChatBackend.batteryRunStore.loadRuns().first { !known.contains($0.id) },
                     "no NEW run record appeared — exactly what #333's conductor reports as failed")
    }

    @Test func theABSealsARunEvenWhereTheModelThrows() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()

        await backend.runCardClauseAB(trials: 1)

        let record = try freshRun(after: known)
        #expect(record.endedCleanly == true)
        #expect(record.kind == "card-clause")
        #expect(record.cells == LocalChatBackend.CardClauseArm.allCases.map(\.rawValue))
    }

    /// The manipulation check is what stops a broken treatment reading as a
    /// null. It must exist for every arm and it must be recorded BEFORE the
    /// arm's trials, so a run that died mid-arm still says what it was doing.
    @Test func everyArmRecordsWhetherItsTreatmentActuallyApplied() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runCardClauseAB(trials: 1)
        let record = try freshRun(after: known)

        let checks = record.probes.filter { $0.band == "manipulation" }
        #expect(checks.count == LocalChatBackend.CardClauseArm.allCases.count)
        for row in checks {
            #expect(row.metrics?["descriptionsSwapped"] != nil)
            #expect(row.metrics?["blurbRemoved"] != nil)
            #expect(row.notes?["residualExposure"] != nil,
                    "no arm is a zero-exposure arm and the record has to say so")
        }
        // A test backend has no belt installed, so zero descriptions are
        // swappable — which is the honest reading here and exactly the state
        // the check exists to make visible rather than silently score.
        let control = try #require(checks.first { $0.variant == "control" })
        #expect(control.metrics?["descriptionsSwapped"] == 0)
    }

    /// #215 per band: counted denominators, counted errors, and BOTH readings
    /// kept apart — a summary that reported only the imitation rate could not
    /// distinguish a clause that stopped the prose from one that also produced
    /// the call.
    @Test func everyArmSummaryCarriesBothReadingsAndItsErrorTally() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runCardClauseAB(trials: 1)
        let record = try freshRun(after: known)

        let summaries = record.probes.filter { $0.band == "card-clause-summary" }
        #expect(summaries.count == LocalChatBackend.CardClauseArm.allCases.count)
        for row in summaries {
            #expect(row.errors != nil)
            let attempted = try #require(row.metrics?["attempted"])
            #expect(attempted == Double(LocalChatBackend.actionBatteryDefaultPrompts.count))
            #expect(row.trials == Int(attempted))
            #expect(row.metrics?["armedImitations"] != nil, "the MECHANISM reading is missing")
            #expect(row.metrics?["trialsWithToolCalls"] != nil, "the BEHAVIOUR reading is missing")
            #expect(row.metrics?["generationErrors"] != nil)
            #expect(row.metrics?["timeouts"] != nil)
            // #372(a): the decline half's own tallies, and the note that names
            // its denominator. Without the note a later reader divides the
            // misattribution count by `attempted` and reports a defect rate
            // that falls whenever the model simply calls nothing.
            #expect(row.metrics?["declineHalfExercised"] != nil,
                    "#372(a)'s count is missing — the entry still cannot say whether the half is reached")
            #expect(row.metrics?["declineAttributedToTool"] != nil)
            #expect(row.metrics?["declineAttributedToUser"] != nil)
            #expect(row.metrics?["declineActorUnnamed"] != nil)
            #expect(row.metrics?["declineUnscorable"] != nil)
            #expect(row.notes?["declineReading"] != nil)
            // #372(b): which decoding regime produced these rows.
            #expect(row.metrics?["toolCallingForced"] != nil)
        }
        // The remedy arm is the ONLY one whose summary reports a forced mode.
        let forced = summaries.filter { $0.metrics?["toolCallingForced"] == 1 }
        #expect(forced.count == 1)
        #expect(forced.first?.variant == LocalChatBackend.CardClauseArm.toolmodeRequired.rawValue)
    }

    @Test func everyTrialProducesARowCarryingBothMetrics() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runCardClauseAB(trials: 1)
        let record = try freshRun(after: known)

        let trialRows = record.probes.filter { $0.band == "card-clause-trial" }
        let expected = LocalChatBackend.CardClauseArm.allCases.count
            * LocalChatBackend.actionBatteryDefaultPrompts.count
        #expect(trialRows.count == expected)
        for row in trialRows {
            #expect(row.metrics?["armedImitation"] != nil)
            #expect(row.metrics?["toolCallsAdmitted"] != nil)
            #expect(row.errors != nil)
            #expect(row.notes?["outcome"] != nil)
            // #372(a): kept SEPARATE from `toolCallsAdmitted` rather than
            // derived from it — a call admitted by the governor is not a call
            // the gate answered, and reading one off the other is the inference
            // that let the decline half go unmeasured.
            #expect(row.metrics?["declinesObserved"] != nil)
            #expect(row.metrics?["declineHalfExercised"] != nil)
            #expect(row.metrics?["toolCallingForced"] != nil)
        }
        #expect(record.trials.count == expected)
    }
}
#endif
