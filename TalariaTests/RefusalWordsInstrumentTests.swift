#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #337 bar 337-D — the refusal-words instrument, tested STRUCTURALLY.
///
/// Structural is the only honest option here for the same reason #335's
/// instruments are: **the simulator cannot generate at all** (beta5 — an
/// un-bridged `LanguageModelError -1` wrapping `ModelManagerError 1026`), so a
/// test that required a real refusal could only ever pass on hardware. What
/// these pin is the wiring: the capture sink sees a refusal's exact text and
/// the counters behind it, the run seals with per-cell error tallies when the
/// model throws on every trial, and the record carries the fields the #337
/// entry will be scored from.
struct GovernorRefusalCaptureTests {

    /// The whole point of the capture: the string the MODEL is handed, not a
    /// paraphrase of it. Pinned against `admit`'s own return value so the two
    /// can never drift — a capture that recorded its own copy of the text
    /// would keep reporting the old wording the day someone reworded the
    /// refusal.
    @MainActor
    @Test func captureRecordsTheExactStringTheModelReceives() {
        let capture = ToolCallGovernor.RefusalCapture()
        ToolCallGovernor.RefusalCapture.current = capture
        defer { ToolCallGovernor.RefusalCapture.current = nil }

        let governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = governor.admit(tool: "readReminders")
        guard case .refused(let handed) = governor.admit(tool: "createReminder") else {
            Issue.record("expected a refusal")
            return
        }

        let observed = capture.drain()
        #expect(observed.count == 1)
        #expect(observed.first?.text == handed,
                "the captured text must BE the refusal, not a copy of its wording")
    }

    /// The two branches say different things (#225 pins that) and the record
    /// has to be able to tell them apart — "the budget was already spent when
    /// this call arrived" and "this tool has been called four times" are
    /// opposite findings about the same cut.
    @MainActor
    @Test func captureDistinguishesTheBudgetBranchFromTheRepeatBranch() {
        let capture = ToolCallGovernor.RefusalCapture()
        ToolCallGovernor.RefusalCapture.current = capture
        defer { ToolCallGovernor.RefusalCapture.current = nil }

        let budgeted = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = budgeted.admit(tool: "a")
        _ = budgeted.admit(tool: "b")
        let repeated = ToolCallGovernor(perTurnBudget: 99, sameToolRepeatCap: 1)
        _ = repeated.admit(tool: "a")
        _ = repeated.admit(tool: "a")

        let observed = capture.drain()
        #expect(observed.map(\.reason) == [.perTurnBudget, .sameToolRepeat])
    }

    /// **The counters are what make a leaked budget legible.** A refusal with
    /// `callsThisTurn` at the ceiling and `callsOfThisTool` at zero is a turn
    /// that never called that tool at all being refused for calls some earlier
    /// turn made — indistinguishable from a real grind without these two
    /// numbers, and that ambiguity is exactly what #337's rows cannot resolve.
    @MainActor
    @Test func captureCarriesTheGovernorCountersAtTheMomentOfRefusal() throws {
        let capture = ToolCallGovernor.RefusalCapture()
        ToolCallGovernor.RefusalCapture.current = capture
        defer { ToolCallGovernor.RefusalCapture.current = nil }

        let governor = ToolCallGovernor(perTurnBudget: 3, sameToolRepeatCap: 99)
        for _ in 1...3 { _ = governor.admit(tool: "readCalendar") }
        _ = governor.admit(tool: "createReminder")

        let observed = try #require(capture.drain().first)
        #expect(observed.callsThisTurn == 3)
        #expect(observed.callsOfThisTool == 0,
                "a tool refused on a budget it never spent is the leak's signature")
        #expect(observed.tool == "createReminder")
    }

    /// A drain is a per-trial boundary; a sink that kept its buffer would
    /// attribute trial N's refusals to trial N+1.
    @MainActor
    @Test func drainingClearsTheBuffer() {
        let capture = ToolCallGovernor.RefusalCapture()
        ToolCallGovernor.RefusalCapture.current = capture
        defer { ToolCallGovernor.RefusalCapture.current = nil }

        let governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 1)
        _ = governor.admit(tool: "a")
        _ = governor.admit(tool: "a")
        #expect(capture.drain().count == 1)
        #expect(capture.drain().isEmpty)
    }

    /// The hot path must cost nothing when no instrument is running — and,
    /// more importantly, a governor must never be silently observed by a sink
    /// a previous run forgot to tear down.
    @MainActor
    @Test func noSinkMeansNoCapture() {
        ToolCallGovernor.RefusalCapture.current = nil
        let governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 1)
        _ = governor.admit(tool: "a")
        #expect(governor.admit(tool: "a").isRefused, "refusal behaviour is unchanged by the sink")
    }
}

struct RefusalWordsRegistryTests {

    /// Unattended-eligible, and the flags are the claim: auto-DECLINE writes
    /// nothing, so the conductor's alarm rule and the iPad EventKit rule both
    /// pass. If this instrument ever gains an accept-mode arm these flags must
    /// change with it — a flag that lies is how an unattended run creates an
    /// alarm at 6:30 AM.
    @Test func refusalWordsIsRegisteredAsAWriteFreeDeclineInstrument() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "refusal-words"))
        #expect(spec.confirmationMode == .autoDecline)
        #expect(!spec.writesEventKit && !spec.writesAlarms)
    }

    /// The two cells differ in ONE thing and the enum is where that is
    /// declared; a third cell added without a stated contrast is a cell whose
    /// delta cannot be attributed.
    @Test func theInstrumentHasExactlyTheTwoTurnBoundaryCells() {
        #expect(LocalChatBackend.RefusalWordsCell.allCases.map(\.rawValue) == ["turn-reset", "leaked"])
    }

    /// The #337 instruments ride `runActionBattery`'s OWN prompt strings, so a
    /// rate reported by one is denominated in the same prompts as a rate
    /// reported by the other. Pinned verbatim because the drift this guards is
    /// silent (#215's `routedTrialShape` is the same lesson).
    @Test func theActionPromptSetIsTheBatterysOwn() {
        let prompts = LocalChatBackend.actionBatteryDefaultPrompts
        #expect(prompts.map(\.tag) == ["remind", "alarm", "calendar"])
        #expect(prompts.map(\.text) == [
            "Remind me to test Talaria at 4:30pm",
            "Set an alarm for 6:30",
            "Put lunch with Sam on my calendar Friday at noon",
        ])
    }
}

/// The run-level bar, and the one #333's conductor's verdict rests on: a new
/// `BatteryRunRecord` must exist and be SEALED, or the unattended harness
/// reads `failed` however good the measurement was.
///
/// `.serialized` because these drive the ONE shared static recorder and run
/// store through `beginBatteryRun()`'s global mutex; two in parallel would
/// have the second refused, which is the mutex working and the test failing
/// for an unrelated reason.
@Suite(.serialized)
@MainActor
struct RefusalWordsInstrumentRunTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "refusal-words-instrument-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    /// Ids by SET DIFFERENCE, never `loadRuns().first`: the persisted stamp is
    /// ISO8601 second-granularity, and two runs inside one second decode to
    /// equal sort keys (#335's lane found this the hard way).
    private func idsOnDisk() -> Set<UUID> {
        Set(LocalChatBackend.batteryRunStore.loadRuns().map(\.id))
    }

    private func freshRun(after known: Set<UUID>) throws -> BatteryRunRecord {
        try #require(LocalChatBackend.batteryRunStore.loadRuns().first { !known.contains($0.id) },
                     "no NEW run record appeared — exactly what #333's conductor reports as failed")
    }

    @Test func theInstrumentSealsARunEvenWhereTheModelThrows() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()

        await backend.runRefusalWordsInstrument(trials: 1)

        let record = try freshRun(after: known)
        #expect(record.endedCleanly == true, "endRun() must run on the sim path too, or the artifact is INCOMPLETE")
        #expect(record.kind == "refusal-words")
        #expect(!record.probes.isEmpty, "an empty run is DROPPED by endRun() and the conductor reports failed")
    }

    /// #215's rule per band: every row carries a counted denominator and a
    /// counted error tally. On the sim EVERY trial throws, so this run is the
    /// all-errors case — and a summary that reported a clean-looking rate here
    /// would be reporting fail-safe noise as data.
    @Test func everyCellSummaryCarriesItsCountedDenominatorAndErrorTally() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runRefusalWordsInstrument(trials: 1)
        let record = try freshRun(after: known)

        let summaries = record.probes.filter { $0.band == "refusal-summary" }
        #expect(summaries.count == LocalChatBackend.RefusalWordsCell.allCases.count)
        for row in summaries {
            #expect(row.errors != nil, "row \"\(row.probe)\" has no error tally — unsampled reads as clean")
            let attempted = try #require(row.metrics?["attempted"])
            #expect(attempted == Double(LocalChatBackend.actionBatteryDefaultPrompts.count),
                    "the denominator must be COUNTED attempts, never a constant")
            #expect(row.trials == Int(attempted))
            for key in ["cutTrials", "refusalsTotal", "generationErrors", "timeouts",
                        "retriesAttempted", "retryErrors", "userVisibleReplies"] {
                #expect(row.metrics?[key] != nil, "cell summary is missing \(key)")
            }
        }
    }

    /// Every trial gets a row whatever happened to it — the failure this
    /// guards is a run that quietly drops its broken trials and reports the
    /// survivors as the population.
    @Test func everyTrialProducesARowWithANamedOutcome() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runRefusalWordsInstrument(trials: 1)
        let record = try freshRun(after: known)

        let trialRows = record.probes.filter { $0.band == "refusal-trial" }
        let expected = LocalChatBackend.RefusalWordsCell.allCases.count
            * LocalChatBackend.actionBatteryDefaultPrompts.count
        #expect(trialRows.count == expected)
        for row in trialRows {
            let outcome = try #require(row.notes?["outcome"])
            #expect(["answered", "empty", "error", "timeout",
                     "cut-retry-answered", "cut-retry-failed", "cut-retry-empty"].contains(outcome),
                    "unclassifiable outcome \"\(outcome)\"")
            #expect(row.metrics?["refusals"] != nil)
            #expect(row.metrics?["cutFired"] != nil)
            #expect(row.errors != nil)
        }
        // Every trial also lands in the familiar trial grammar, so the #196
        // classifiers and the results page read this run like any other.
        #expect(record.trials.count == expected)
    }

    /// **The #225 B2 gap, made structural.** A cut trial may never be recorded
    /// as a bare empty row again: whenever `cutFired`, the row must say what
    /// happened to the retry — answered, failed, or genuinely empty — and the
    /// text has to be in the record when there was one.
    @Test func aCutTrialAlwaysCarriesItsRetryVerdict() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runRefusalWordsInstrument(trials: 1)
        let record = try freshRun(after: known)

        for row in record.probes where (row.metrics?["cutFired"] ?? 0) == 1 {
            let outcome = try #require(row.notes?["outcome"])
            #expect(outcome.hasPrefix("cut-"), "a cut trial must report a retry verdict")
            #expect(row.metrics?["retryAttempted"] == 1)
            if outcome == "cut-retry-answered" { #expect(row.notes?["retryText"] != nil) }
            if outcome == "cut-retry-failed" { #expect(row.notes?["retryError"] != nil) }
        }
    }

    /// The sink is global; a run that left it installed would keep capturing
    /// into a dead buffer and attribute the NEXT battery's refusals to this
    /// instrument.
    @Test func theCaptureSinkIsTornDownWhenTheRunEnds() async throws {
        let backend = makeBackend()
        await backend.runRefusalWordsInstrument(trials: 1)
        #expect(ToolCallGovernor.RefusalCapture.current == nil)
    }
}
#endif
