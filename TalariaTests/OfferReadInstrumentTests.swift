#if DEBUG
import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// #211A — **the offer-instead-of-act READ battery, tested STRUCTURALLY.**
///
/// The simulator cannot generate (#324), so nothing here asserts a rate and
/// nothing here is the measurement. What it pins is the set of things that can
/// be wrong in an A/B without anyone noticing: that the scorer fires on the
/// specimen it was built from and stays quiet on the near-miss, that the four
/// buckets are actually discriminated rather than collapsed, that each arm's
/// manipulation applies, that the prompt rows resolve to the pinned texts, and
/// that the run seals with counted error tallies when every trial throws.
///
/// The DEVICE bars (211A-D1..D3) are pre-registered in OPEN_ITEMS #211A and are
/// not run here.
struct OfferReadScorerTests {

    /// 🔴 **211A-B1 — the scorer fires on the recorded specimen.** The verbatim
    /// text from #211A's filing, plus the curly-apostrophe form the model
    /// actually types. #225 B3's first classifier pass matched a straight
    /// apostrophe against curly output and read every hit as a miss, which is
    /// why the normalization is shared rather than re-implemented here.
    @Test func firesOnTheRecordedSpecimenInBothApostropheForms() {
        #expect(LocalChatBackend.offerInsteadOfAct(
            in: "Would you like me to check your health data for other metrics?") != nil)
        #expect(LocalChatBackend.offerInsteadOfAct(
            in: "I can pull that up \u{2014} let me know if you\u{2019}d like me to.") != nil)
        #expect(LocalChatBackend.offerInsteadOfAct(
            in: "Do you want me to look at your step count?") != nil)
        #expect(LocalChatBackend.offerInsteadOfAct(
            in: "Shall I check the weather for you?") != nil)
    }

    /// 🔴 **211A-B1's other half, and the one that makes it a detector rather
    /// than a keyword count.** A bare capability STATEMENT is not the defect —
    /// the defect is handing the decision back. A scorer that fired on *"I can
    /// check your steps"* would score most correct read answers as the disease
    /// and manufacture a rate out of good turns.
    @Test func staysQuietOnCapabilityStatementsAndPlainAnswers() {
        #expect(LocalChatBackend.offerInsteadOfAct(in: "I can check your steps.") == nil)
        #expect(LocalChatBackend.offerInsteadOfAct(
            in: "You've taken 4,231 steps today.") == nil)
        #expect(LocalChatBackend.offerInsteadOfAct(
            in: "It's 68\u{00B0}F and clear in Biloxi right now.") == nil)
        // A denial is #202D's disease, not this one. It must not score here —
        // it is co-recorded as its own column instead.
        #expect(LocalChatBackend.offerInsteadOfAct(
            in: "I can't access your health data right now.") == nil)
    }

    /// 🔴 **211A-B2 — THE BUCKETS ARE DISCRIMINATED BY THE TOOL CALL, and this
    /// is the bar the whole scorer exists for.**
    ///
    /// #211A's own specimen offers to check *"other metrics"* — which reads
    /// like a courteous follow-on to an answer that was given. Counting every
    /// offer shape as the defect would fold good turns into the rate. The
    /// discriminator is whether the model ACTED, and the two readings are
    /// recorded side by side rather than collapsed into one number.
    @Test func theFourBucketsAreDiscriminatedByWhetherTheModelActed() {
        let offer = "Would you like me to check your steps?"
        let answer = "You've taken 4,231 steps today."

        #expect(LocalChatBackend.offerReadVerdict(replyText: offer, toolCallsAdmitted: 0)
                == .offeredWithoutActing)
        #expect(LocalChatBackend.offerReadVerdict(replyText: answer + " " + offer,
                                                  toolCallsAdmitted: 1)
                == .offeredAfterActing)
        #expect(LocalChatBackend.offerReadVerdict(replyText: answer, toolCallsAdmitted: 1)
                == .actedNoOffer)
        #expect(LocalChatBackend.offerReadVerdict(replyText: "I can't access that.",
                                                  toolCallsAdmitted: 0)
                == .neitherActedNorOffered)
    }

    /// A trial that threw AFTER calling a tool did act. Scoring it as residue
    /// would let an arm with a high error rate read as an arm that stopped
    /// offering — the `21F0C10D` shape, where instrument failure enters the
    /// record as behaviour.
    @Test func aThrownTrialThatCalledAToolIsNotScoredAsResidue() {
        #expect(LocalChatBackend.offerReadVerdict(replyText: nil, toolCallsAdmitted: 2)
                == .actedNoOffer)
        #expect(LocalChatBackend.offerReadVerdict(replyText: nil, toolCallsAdmitted: 0)
                == .neitherActedNorOffered)
    }
}

struct OfferReadManipulationTests {

    /// 🔴 **211A-B3 — the prompt set resolves EVERY tag.**
    ///
    /// The rows are selected from the pinned sets by tag rather than retyped
    /// (372-C3's rule). `compactMap` over a renamed tag returns a SHORTER
    /// array rather than an error, so an upstream rename would silently shrink
    /// the run while every rate in it still looked fine. This is the test that
    /// goes red instead.
    @Test func thePromptSetResolvesEveryTagAndComesFromThePinnedSets() throws {
        let prompts = LocalChatBackend.offerReadBatteryPrompts
        #expect(prompts.count == LocalChatBackend.offerReadPromptTags.count,
                "a tag failed to resolve — the run would silently be shorter than it reads")
        #expect(prompts.map(\.tag) == LocalChatBackend.offerReadPromptTags,
                "the resolved order does not match the pinned order")

        // Not merely "four rows exist": the TEXTS must be the pinned ones, so
        // this instrument's cells stay readable against #209's and #211's
        // history rather than measuring four strings that resemble them.
        let pool = LocalChatBackend.motionScopeBatteryPrompts
            + LocalChatBackend.readToolBatteryPrompts
        for row in prompts {
            let pinned = try #require(pool.first { $0.tag == row.tag })
            #expect(row.text == pinned.text)
            #expect(!row.text.isEmpty)
        }
    }

    /// 🔴 **211A-B4 — the rollback arm swaps EXACTLY the motion description.**
    /// A manipulation that found no `MotionTool` to swap would produce a
    /// treatment arm identical to its control and a clean-looking null, which
    /// is the failure `swapped` is counted to prevent.
    @MainActor
    @Test func theRollbackArmRestoresThePinnedStepClaimAndNothingElse() throws {
        let relay = ToolEventRelay()
        let belt: [any Tool] = [
            MotionTool(relay: relay),
            DeviceHealthTool(relay: relay),
            ReminderCreateTool(relay: relay, confirmations: ToolConfirmationCenter()),
        ]
        let rolled = LocalChatBackend.offerReadBelt(from: belt, arm: .toolRollback)
        #expect(rolled.swapped == 1, "the rollback swapped nothing — the arm is identity with control")
        #expect(rolled.belt.count == belt.count, "the rollback removed a tool; it must only reword one")

        let motion = try #require(rolled.belt.first { $0.name == "readMotion" })
        #expect(motion.description == MotionTool.stepClaimingDescription211,
                "reached by a fresh literal instead of the pinned rollback constant")
        // The control stays a control — the assertion that would catch a swap
        // accidentally applied to every arm.
        let control = LocalChatBackend.offerReadBelt(from: belt, arm: .control)
        #expect(control.swapped == 0)
        #expect(control.belt.count == belt.count)
    }

    /// 🔴 **211A-B5 — the CEILING arm actually removes every read tool, and
    /// leaves the rest alone.** This arm is the detector's positive control, so
    /// an arm that quietly removed nothing would take the run's only means of
    /// telling a clean result from a blind scorer.
    @MainActor
    @Test func theCeilingArmRemovesEveryReadToolAndKeepsTheRest() {
        let relay = ToolEventRelay()
        let belt: [any Tool] = [
            MotionTool(relay: relay),
            DeviceHealthTool(relay: relay),
            ReminderCreateTool(relay: relay, confirmations: ToolConfirmationCenter()),
        ]
        let ceiling = LocalChatBackend.offerReadBelt(from: belt, arm: .noReadBelt)
        #expect(ceiling.readToolsPresent == 0, "a read tool survived the ceiling arm")
        #expect(ceiling.belt.contains { $0.name == "createReminder" },
                "the ceiling arm removed more than the read tools — that is a second manipulation")
        #expect(ceiling.swapped == 0, "the ceiling arm must remove, never reword")

        // POSITIVE CONTROL on the filter itself: the same belt through the
        // control arm must still carry read tools, or the assertion above
        // would pass against a belt that never had any.
        let control = LocalChatBackend.offerReadBelt(from: belt, arm: .control)
        #expect(control.readToolsPresent == 2)
    }

    /// The manipulation band's `correct` column, asserted rather than trusted.
    /// It is written as a function here from the start because the equivalent
    /// inline ternary in `+CardClause.swift` was WRONG for three arms for five
    /// days — see `cardClauseManipulationApplied`.
    @Test func theManipulationColumnIsTrueOnlyWhenTheArmActuallyApplied() {
        #expect(LocalChatBackend.offerReadManipulationApplied(
            arm: .control, swapped: 0, readToolsPresent: 3, beltCount: 13))
        #expect(LocalChatBackend.offerReadManipulationApplied(
            arm: .toolRollback, swapped: 1, readToolsPresent: 3, beltCount: 13))
        #expect(!LocalChatBackend.offerReadManipulationApplied(
            arm: .toolRollback, swapped: 0, readToolsPresent: 3, beltCount: 13),
                "a rollback that swapped nothing must NOT read as applied")
        #expect(LocalChatBackend.offerReadManipulationApplied(
            arm: .noReadBelt, swapped: 0, readToolsPresent: 0, beltCount: 10))
        #expect(!LocalChatBackend.offerReadManipulationApplied(
            arm: .noReadBelt, swapped: 0, readToolsPresent: 1, beltCount: 10),
                "a ceiling arm that left a read tool must NOT read as applied")
        // #211A-E1: the toolless arm is witnessed by an EMPTY belt, and
        // `readToolsPresent == 0` cannot witness it — that is ALSO true of
        // `.noReadBelt`, which is why the parameter was added.
        #expect(LocalChatBackend.offerReadManipulationApplied(
            arm: .toolless, swapped: 0, readToolsPresent: 0, beltCount: 0))
        #expect(!LocalChatBackend.offerReadManipulationApplied(
            arm: .toolless, swapped: 0, readToolsPresent: 0, beltCount: 10),
                "a toolless arm with tools left on the belt must NOT read as applied")
    }
}

struct OfferReadRegistryTests {

    @Test func offerReadIsRegisteredAsAWriteFreeDeclineInstrument() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "offer-read"))
        #expect(spec.confirmationMode == .autoDecline)
        #expect(!spec.writesEventKit && !spec.writesAlarms)
        // #341: no `ActionBatteryCell` dimension, so the conductor REFUSES a
        // `TALARIA_CELLS` request for this instrument rather than ignoring one.
        #expect(spec.defaultCells == nil)
    }

    /// The arm-name pin — 372-C5's shape. Adding an arm without naming it here
    /// is a failure rather than a silent widening of the export vocabulary.
    ///
    /// It DID its job on 2026-08-27: adding `.toolless` (#211A-E) turned this
    /// red, which is the whole reason the pin exists. The arm is named here
    /// rather than the pin being loosened.
    @Test func theBatteryArmEnumIsPinnedWithTheCeilingLast() {
        #expect(LocalChatBackend.OfferReadArm.allCases.map(\.rawValue)
                == ["control", "tool-rollback", "no-read-belt", "toolless"])
    }

    /// **The claim that protects every prior `offer-read` artifact.**
    ///
    /// A DEFAULT run must still mean exactly the original three arms, ceiling
    /// last. `.toolless` is a diagnostic reached only through its own
    /// instrument (`offer-read-toolless`), and if it ever leaks into the
    /// defaults, every artifact recorded before 2026-08-27 stops being
    /// comparable to every artifact recorded after — silently, since the arm
    /// count is not in the instrument's name.
    ///
    /// This is pinned SEPARATELY from `allCases` on purpose: the enum is
    /// allowed to grow, the default is not.
    @Test func theDefaultRunIsStillTheOriginalThreeArms() {
        #expect(LocalChatBackend.offerReadDefaultArms.map(\.rawValue)
                == ["control", "tool-rollback", "no-read-belt"])
        #expect(!LocalChatBackend.offerReadDefaultArms.contains(.toolless),
                "the toolless diagnostic must never ride a default run")
    }
}

/// `.serialized` for `CardClauseInstrumentRunTests`' reason: one shared static
/// recorder and run store behind `beginBatteryRun()`'s global mutex.
@Suite(.serialized)
@MainActor
struct OfferReadInstrumentRunTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "offer-read-instrument-tests")!
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

    @Test func theBatterySealsARunEvenWhereTheModelThrows() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()

        await backend.runOfferReadBattery(trials: 1)

        let record = try freshRun(after: known)
        #expect(record.endedCleanly == true)
        #expect(record.kind == "offer-read")
        #expect(record.cells == LocalChatBackend.offerReadDefaultArms.map(\.rawValue))
    }

    @Test func everyArmRecordsWhetherItsTreatmentActuallyApplied() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runOfferReadBattery(trials: 1)
        let record = try freshRun(after: known)

        let checks = record.probes.filter { $0.band == "manipulation" }
        #expect(checks.count == LocalChatBackend.offerReadDefaultArms.count)
        for row in checks {
            #expect(row.metrics?["descriptionsSwapped"] != nil)
            #expect(row.metrics?["readToolsPresent"] != nil)
            #expect(row.notes?["expectedManipulation"] != nil)
            #expect(row.notes?["noProseArm"] != nil,
                    "#211A's entry says test tool choice FIRST — the record has to say no arm changed prose")
        }
    }

    /// 🔴 **211A-B6 — #215 per band: counted denominators, counted errors, all
    /// four buckets under BOTH denominators, and no union anywhere.**
    ///
    /// A summary that reported only the defect rate could not distinguish a
    /// manipulation that stopped the offer from one that also produced the
    /// call; a summary with no error tally reports fail-safe noise as data.
    @Test func everyArmSummaryCarriesAllFourBucketsBothDenominatorsAndItsErrorTally()
        async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runOfferReadBattery(trials: 1)
        let record = try freshRun(after: known)

        let summaries = record.probes.filter { $0.band == "offer-read-summary" }
        #expect(summaries.count == LocalChatBackend.offerReadDefaultArms.count)
        for row in summaries {
            #expect(row.errors != nil)
            let attempted = try #require(row.metrics?["attempted"])
            #expect(attempted == Double(LocalChatBackend.offerReadBatteryPrompts.count))
            #expect(row.trials == Int(attempted))
            for bucket in LocalChatBackend.OfferReadVerdict.allCases {
                #expect(row.metrics?[bucket.rawValue] != nil,
                        "bucket \(bucket.rawValue) is missing from the summary")
            }
            // The ARMED-routed denominator and its own four buckets — the
            // #215 half. A rate over `attempted` pools trials the router sent
            // toolless, which is the ceiling arm's condition arriving by
            // accident.
            #expect(row.metrics?["routedArmedTrials"] != nil)
            #expect(row.metrics?["routedToollessTrials"] != nil)
            #expect(row.metrics?["armedOfferedWithoutActing"] != nil)
            #expect(row.metrics?["armedNeitherActedNorOffered"] != nil)
            #expect(row.metrics?["generationErrors"] != nil)
            #expect(row.metrics?["timeouts"] != nil)
            #expect(row.notes?["primary"] != nil)
            #expect(row.notes?["ceiling"] != nil,
                    "the positive control's reading must travel with the run")
        }
    }

    @Test func everyTrialProducesARowCarryingBothReadings() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runOfferReadBattery(trials: 1)
        let record = try freshRun(after: known)

        let trialRows = record.probes.filter { $0.band == "offer-read-trial" }
        let expected = LocalChatBackend.offerReadDefaultArms.count
            * LocalChatBackend.offerReadBatteryPrompts.count
        #expect(trialRows.count == expected)
        for row in trialRows {
            #expect(row.metrics?["offeredWithoutActing"] != nil)
            #expect(row.metrics?["offeredAfterActing"] != nil)
            #expect(row.metrics?["toolCallsAdmitted"] != nil)
            #expect(row.metrics?["routedArmed"] != nil)
            #expect(row.metrics?["denial"] != nil)
            #expect(row.errors != nil)
            #expect(row.notes?["verdict"] != nil)
        }
        #expect(record.trials.count == expected)
    }
}
#endif
