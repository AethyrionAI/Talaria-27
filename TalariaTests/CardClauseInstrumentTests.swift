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
        #expect(instructions.contains(DeviceActionClauses.armedBlurbCardSentence),
                "arm C's removal target is not in production's armed instructions")
        let (stripped, removed) = LocalChatBackend.cardClauseInstructions(
            instructions, arm: .toolsAndBlurbStripped)
        #expect(removed)
        #expect(!stripped.contains(DeviceActionClauses.armedBlurbCardSentence))
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
        #expect(!stripped.contains(DeviceActionClauses.armedBlurbCardSentence))

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

    /// The reworded arm SUBSTITUTES: production's sentence gone, the
    /// replacement present, descriptions untouched. A `removed`-only signal
    /// cannot tell this arm from the blurb-only arm, so the presence of the
    /// replacement is asserted directly.
    @MainActor
    @Test func theRewordedArmSubstitutesAndLeavesTheDescriptionsAlone() {
        let instructions = LocalChatBackend.instructionsText(
            deviceContext: "test", hasTools: true, hasImageTools: false)
        let (text, changed) = LocalChatBackend.cardClauseInstructions(
            instructions, arm: .blurbReworded)
        #expect(changed, "the reworded arm changed nothing")
        #expect(!text.contains(DeviceActionClauses.armedBlurbCardSentence),
                "production's sentence survived the substitution")
        #expect(text.contains(DeviceActionClauses.armedBlurbCardSentenceReworded337F2),
                "the replacement is not in the instructions")
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

    @Test func theABHasFiveNamedArmsWithTheRewordedOneLast() {
        #expect(LocalChatBackend.CardClauseArm.allCases.map(\.rawValue)
                == ["control", "tools-stripped", "tools-blurb-stripped",
                    "blurb-stripped", "blurb-reworded"])
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
        }
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
        }
        #expect(record.trials.count == expected)
    }
}
#endif
