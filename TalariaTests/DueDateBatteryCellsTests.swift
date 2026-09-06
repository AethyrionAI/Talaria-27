import Foundation
import Testing
@testable import Talaria

/// **#340 bar 340-U-D's ARM — `armed-nofallback`, the same-run mutation cell.**
///
/// Task 3 built the fallback and the `source=` field; 340-U-C asks how high
/// `populated-future` climbs with it on. **340-U-D asks the question that makes
/// that number mean something: how high does it climb with the fallback OFF, on
/// the same prompt, in the same run, against the same model in the same thermal
/// state?** #200O settled that cross-run comparison is worthless here — three
/// cells landed on exactly 6/10 remind on three different texts — so the control
/// has to travel with the treatment.
///
/// **The lever is the fallback and ONLY the fallback.** `carriesUserText` was
/// the obvious candidate and it is the wrong one: switching it off would also
/// blank `currentTurnUserText`, so the two arms would differ in what the BELT
/// sees as well as in what the resolver does. An A/B has to hand both arms the
/// same input. So the cell rides production's belt, production's guide,
/// production's instructions and production's turn text, and differs in exactly
/// one Bool.
///
/// **One engine, never a second copy.** The other reminder cells swap in a
/// `ReminderCreateTool…` struct; this one does not, because a fifth copy of the
/// tool would carry a second copy of `performCreate`'s create flow with it —
/// *"two structs, one engine"*, in that function's own words, and the retired
/// `armed-bareclock` cell is the lane's own record of what happens when a copy
/// outlives the thing it was copied from. The switch is a DEBUG-only flag on the
/// relay that the ONE engine consults at the ONE place the fallback lives.
@MainActor
struct DueDateBatteryCellsTests {

    private func todayAt(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                              of: Calendar.current.startOfDay(for: Date()))!
    }

    private func day(_ offset: Int, from now: Date, at hour: Int, _ minute: Int) -> Date {
        let calendar = Calendar.current
        let shifted = calendar.date(byAdding: .day, value: offset, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted)!
    }

    /// #340 bar 340-F4's column reads RELATIONS, never absolute dates — the
    /// same rule (and the same two helpers) `DeviceActionParsingDetectDueTests`
    /// runs on, because a hardcoded expectation rots at a fixed hour every day.
    private func hourMinute(_ date: Date) -> (hour: Int, minute: Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour!, c.minute!)
    }

    private func dayOffset(from now: Date, to date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day!
    }

    /// A relay with the DEBUG fallback switch set as asked.
    private func relay(disablingFallback: Bool) -> ToolEventRelay {
        let relay = ToolEventRelay()
        relay.disableUserTextDueFallback = disablingFallback
        return relay
    }

    // MARK: - The cell exists, and the instrument dispatches it

    /// The label is the export vocabulary, so it is pinned by value — the same
    /// rule `destallCellLabelsMatchTheDispatch` applies to every other cell.
    ///
    /// **`nofallback`, not `fallbackoff` or `nofb`:** `score-due-omission.py`'s
    /// own self-test fixture already writes `shape=armed-nofallback`, and the
    /// scorer reads the cell out of the log line rather than from any shared
    /// constant. A rename on either side would score the arm as a cell nobody
    /// declared.
    @Test func theNofallbackCellCarriesItsLabel() {
        #expect(LocalChatBackend.ActionBatteryCell.armedNofallback.rawValue
                == "armed-nofallback")
    }

    /// **The A/B is a DEFAULT, not something an operator has to remember.**
    ///
    /// 340-U-D's whole claim is a within-run contrast, and a cell that ships
    /// reachable but unselected would leave the contrast to whoever types the
    /// cell list into the Developer screen — which is exactly how the retired
    /// `bareClockBatteryCells` constant came to have zero call sites while
    /// documenting itself as "Pinned".
    @Test func theDueDateBatteryRunsBothArmsByDefault() {
        #expect(LocalChatBackend.dueDateBatteryCells.contains(.armedNofallback),
                "the nofallback arm must ride the default cell list, or 340-U-D depends on an operator typing it")
        #expect(LocalChatBackend.dueDateBatteryCells.contains(.armed),
                "the treatment arm must still be there")
    }

    /// And the registry's `due-date` spec dispatches that same list. The spec
    /// takes the constant by reference, so this row is what proves the two have
    /// not been allowed to drift into two lists with one name.
    @Test func theRegistrysDueDateSpecCarriesTheNofallbackArm() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "due-date"),
                                "the due-date instrument is gone from the registry")
        let cells = try #require(spec.defaultCells,
                                 "due-date lost its cell dimension — the conductor would refuse a TALARIA_CELLS request for it")
        #expect(cells.contains(.armedNofallback),
                "the registry's due-date cells are \(cells.map(\.rawValue))")
    }

    /// The cell must not route. #216's partition row pins the whole enum, but
    /// this says it locally too: a routed nofallback arm would differ from
    /// `armed` in two ways and measure neither.
    @Test func theNofallbackCellDoesNotRoute() {
        #expect(!LocalChatBackend.ActionBatteryCell.armedNofallback.isRouted)
    }

    // MARK: - Bar 340-F4: the phrase-diversity cell

    /// The label is export vocabulary and #416-G requires it to be UNIQUE
    /// across every instrument's cells — the scorer groups on `shape=`, so two
    /// cells sharing a name would pool two measurements into one number.
    @Test func thePhrasesCellCarriesAUniqueLabel() {
        #expect(LocalChatBackend.ActionBatteryCell.armedPhrases.rawValue == "armed-phrases")
        let labels = LocalChatBackend.ActionBatteryCell.allCases.map(\.rawValue)
        #expect(Set(labels).count == labels.count, "two cells share a raw value")
        #expect(labels.filter { $0.contains("phrases") } == ["armed-phrases"],
                "another cell has taken the `phrases` name")
    }

    /// **The cell's prompt list is EXACTLY the plan's eight phrasings**, in the
    /// plan's own order (`2026-09-04-340-due-date-from-user-words.md:69`).
    /// Pinned by value because the eight are the measurement: a ninth added
    /// quietly, or one silently reworded, changes what the device card reports
    /// without changing its name.
    @Test func thePhrasesCellRunsExactlyTheEightPhrasings() {
        let set = LocalChatBackend.duePhrasePromptSet

        #expect(set.count == 8)
        #expect(set.map(\.tag) == ["tmrw4pm", "at430", "in20min", "nexttue9am",
                                   "tonight", "eve7", "friday", "at4"])
        #expect(set.map(\.text) == [
            "Remind me to test Talaria tomorrow at 4pm",
            "Remind me to test Talaria at 4:30",
            "Remind me to test Talaria in 20 minutes",
            "Remind me to test Talaria next Tuesday 9am",
            "Remind me to test Talaria tonight",
            "Remind me to test Talaria this evening at 7",
            "Remind me to test Talaria on Friday",
            "Remind me to test Talaria at 4",
        ])
        #expect(Set(set.map(\.tag)).count == 8, "the `p=` tags must be unique — the scorer groups on them")
    }

    /// **Eight phrasings × 5 = 40 — the ruling's own arithmetic**, and the row
    /// that stops `--trials 40` meaning 320 trials on a phone whose thermal
    /// state is a VOID condition.
    @Test func theRunsTrialsAreDividedAcrossTheEightPhrasings() {
        #expect(LocalChatBackend.trialsPerPrompt(promptCount: 8, trials: 40) == 5,
                "the card's `--trials 40` must be eight phrasings x 5")
        // A one-prompt list has nothing to divide — every other cell is
        // byte-identical to what it ran before this bar.
        #expect(LocalChatBackend.trialsPerPrompt(promptCount: 1, trials: 40) == 40)
        // Floors at one rather than running zero trials silently.
        #expect(LocalChatBackend.trialsPerPrompt(promptCount: 8, trials: 3) == 1)
    }

    /// **Only this cell brings its own prompts.** The lookup is what keeps
    /// every existing denominator where it was — `armed`, `armed-dateguide`
    /// and `armed-nofallback` still run the run's prompt set at the run's
    /// trial count.
    @Test func onlyThePhrasesCellSubstitutesItsOwnPrompts() {
        for cell in LocalChatBackend.ActionBatteryCell.allCases where cell != .armedPhrases {
            #expect(LocalChatBackend.cellPromptSet(for: cell) == nil,
                    "\(cell.rawValue) substituted a prompt list — every existing denominator would move")
        }
        let own = LocalChatBackend.cellPromptSet(for: .armedPhrases)
        #expect(own?.count == 8)
    }

    /// **Armed exactly like `.armed`.** The cell is a phrase-diversity arm, not
    /// a treatment: identical belt (no tool swap), no routing, and — critically
    /// — it is NOT the nofallback arm, so the fallback is ON.
    ///
    /// The belt half is a SOURCE witness rather than a call, because
    /// `destallBelt` over an empty array returns an empty array for every cell
    /// in the enum: the comparison would pass for a cell that swapped the
    /// reminder tool, which is the one thing it is supposed to catch.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func thePhrasesCellIsArmedLikeProduction() throws {
        let body = try RepoSourceWitness.functionBody(
            from: "func destallBelt(from tools: [any Tool], cell: ActionBatteryCell)",
            in: RepoSourceWitness.batteryPath,
            boundary: "\n    nonisolated static func ")
        let identityArm = try #require(body.components(separatedBy: "return tools").first)
        #expect(identityArm.contains(".armedPhrases"),
                "armed-phrases must ride the IDENTITY belt arm — a tool swap would make it a treatment")

        #expect(!LocalChatBackend.ActionBatteryCell.armedPhrases.isRouted)
        #expect(LocalChatBackend.ActionBatteryCell.armedPhrases != .armedNofallback,
                "the fallback must be ON for this cell")
    }

    /// **THE EXPECTED-RESOLUTION COLUMN — MEASURED 2026-09-06, not predicted,
    /// and it falsified the prediction the bar itself carried.**
    ///
    /// 340-F4's bar text guessed that *"'in 20 minutes' and 'on Friday'-style
    /// day-only phrasings are honest nils"*. Measured against
    /// `now = todayAt(9, 15)`:
    ///
    /// | tag | measured | resolves? |
    /// |---|---|---|
    /// | `tmrw4pm` | tomorrow 16:00 | yes |
    /// | `at430` | **04:30 or 16:30 — the detector's hand, see below** | yes |
    /// | `in20min` | nil | **no** |
    /// | `nexttue9am` | next Tuesday 09:00 | yes |
    /// | `tonight` | today 19:00 | yes |
    /// | `eve7` | today 19:00 | yes |
    /// | `friday` | the coming Friday 12:00 | yes |
    /// | `at4` | today 16:00 | yes — 340-F1 |
    ///
    /// **SEVEN of the eight resolve; only the duration does not.** `tonight`
    /// and `on Friday` both resolve, because `NSDataDetector` gives them a
    /// default hour (19:00 and 12:00) — so a device bar written as "five of
    /// eight" would have been wrong in the generous direction.
    ///
    /// **And the measurement found something 340-F1 does NOT fix.** `at 4:30`
    /// is matched by the DETECTOR, so it never reaches the second pass and the
    /// 12-hour rule never sees it. At 04:06 local it came back as **04:30
    /// TOMORROW** — the AM reading 340-F1 was ruled against, surviving on the
    /// one path the ruling scoped out ("in the SECOND PASS only").
    ///
    /// **⚠️ AND ITS HAND DEPENDS ON THE PROCESS'S REAL CLOCK, which the first
    /// cut of this row got wrong and the 340-F4 mutation run caught.** The pin
    /// was written as 04:30/offset 1 from the 04:06 measurement and RED at
    /// 05:22 for a reason that had nothing to do with the mutation: the
    /// detector picks the next occurrence of 4:30 on a 12-hour clock relative
    /// to `Date()`, not to the injected `now`, so before 04:30 it yields
    /// today's 04:30 (then rolled to tomorrow against `now`) and after it
    /// yields today's 16:30 (kept, because 16:30 > 09:15). **Both readings are
    /// this row's subject; only the HAND is invariant.** So the assertion is
    /// `hour % 12 == 4`, minute 30, strictly future — and the device card must
    /// record the run's local time, because `at430`'s expected value is not
    /// knowable without it.
    ///
    /// Rows whose hand comes from the detector's own defaults (`tonight`,
    /// `eve7`, `friday`) are asserted only as "resolves, strictly future" for
    /// the same reason.
    @Test func theExpectedResolutionColumnIsPinnedPerPhrasing() throws {
        let now = todayAt(9, 15)
        let due = { (tag: String) -> Date? in
            let text = LocalChatBackend.duePhrasePromptSet.first { $0.tag == tag }?.text
            return text.flatMap { DeviceActionParsing.detectDue(in: $0, now: now) }
        }

        // The one honest nil: a duration is neither detector-resolvable nor a
        // clock, and 340-U-A's continuation allowlist refuses the bare "20".
        #expect(due("in20min") == nil, "a duration must never manufacture a time")

        // Deterministic rows — their answers are fixed by `now` alone.
        let tomorrow4pm = try #require(due("tmrw4pm"))
        #expect(hourMinute(tomorrow4pm) == (16, 0))
        #expect(dayOffset(from: now, to: tomorrow4pm) == 1)

        // `at 4:30` is the DETECTOR's, which reads the REAL clock: 04:30
        // tomorrow before 04:30 local, 16:30 today after it. Only the HAND is
        // invariant — and the hand is what says 340-F1 does not reach this
        // shape, since the second pass would have made it unambiguous.
        let ambiguousHalfPast = try #require(due("at430"))
        #expect(hourMinute(ambiguousHalfPast).minute == 30)
        #expect(hourMinute(ambiguousHalfPast).hour % 12 == 4,
                "`at 4:30` must still read as the 4 hand, got \(hourMinute(ambiguousHalfPast).hour)")
        #expect(ambiguousHalfPast > now)

        let nextTuesday = try #require(due("nexttue9am"))
        #expect(hourMinute(nextTuesday) == (9, 0))
        #expect(Calendar.current.component(.weekday, from: nextTuesday) == 3, "Tuesday")

        let bareFour = try #require(due("at4"))
        #expect(hourMinute(bareFour) == (16, 0),
                "340-F1: a bare 4 said at 09:15 is this afternoon, not 04:00 tomorrow")
        #expect(dayOffset(from: now, to: bareFour) == 0)

        // Detector-defaulted rows: resolves, strictly future, hand not pinned.
        for tag in ["tonight", "eve7", "friday"] {
            let resolved = try #require(due(tag), "\(tag) must resolve")
            #expect(resolved > now, "\(tag) resolved to a non-future instant")
        }
    }

    // MARK: - The flag, and what it does to the engine

    /// **Default OFF.** The flag is a measurement switch; a default of `true`
    /// would switch the product off for every caller that never heard of it.
    @Test func theFallbackSwitchDefaultsToOff() {
        #expect(ToolEventRelay().disableUserTextDueFallback == false)
    }

    /// **The turn boundary CLEARS the switch — fix round 1's row (a).**
    ///
    /// `ToolEventRelay` is one instance per `AppContainer`, shared by
    /// production chat and every instrument in the launch. The battery writes
    /// the switch per trial from the cell, which stops it leaking between
    /// CELLS — but `.armedNofallback` is the last default cell, so without a
    /// reset the terminal state of every default due-date run was `true` and
    /// stayed `true` for the rest of the process: the next instrument created
    /// its reminders with the fix off, and a hand check of the fallback in
    /// chat read as a product regression.
    ///
    /// A default of `false` on a FRESH relay never saw that, which is why
    /// `theFallbackSwitchDefaultsToOff` passed throughout. The switch is
    /// per-turn state exactly like `currentTurnUserText`, so it clears where
    /// that clears — and the bare `beginTurn()` is the form every other
    /// instrument and every production turn makes.
    @Test func aTurnBoundaryClearsTheFallbackSwitch() {
        let relay = ToolEventRelay()

        relay.disableUserTextDueFallback = true
        relay.beginTurn()
        #expect(relay.disableUserTextDueFallback == false,
                "a bare beginTurn() left the measurement switch set — it leaks to every later turn in the launch")

        relay.disableUserTextDueFallback = true
        relay.beginTurn(userText: "remind me to call mom tomorrow at 4pm")
        #expect(relay.disableUserTextDueFallback == false,
                "the production turn form left the switch set")
    }

    /// **The within-run isolation this fix must not break.**
    ///
    /// The battery's per-trial write happens AFTER `beginTurn`, so the reset
    /// above cannot take the `armed-nofallback` cell's own arming away from
    /// it — and the `armed` cell's next trial still resolves the date. This
    /// row drives the two writes in production's order, on ONE relay, and
    /// asserts both halves; reorder the pair and it reds.
    @Test func anArmedTrialAfterANofallbackTrialStillStagesTheDate() async {
        let now = todayAt(9, 15)
        let prompt = "Remind me to call mom tomorrow at 4pm"
        let relay = ToolEventRelay()

        // Production's order, twice: open the turn, then arm from the cell.
        // (`StagedReminderProbe` hands `performCreate` the same sentence
        // directly, which is what the belt's `currentTurnUserText` carries on
        // a real trial.)
        func trial(_ cell: LocalChatBackend.ActionBatteryCell) async -> String {
            relay.beginTurn(userText: prompt)
            relay.disableUserTextDueFallback = (cell == .armedNofallback)
            let due = await StagedReminderProbe.staged(
                rawDue: "", userText: prompt, now: now, relay: relay).due
            return due ?? "<nil>"
        }

        let first = await trial(.armedNofallback)
        let second = await trial(.armed)

        #expect(first.isEmpty,
                "the nofallback trial staged \(first) — its own arming was lost to the turn-boundary reset")
        #expect(second == DeviceActionParsing.displayDate(day(1, from: now, at: 16, 0)),
                "the armed trial after a nofallback trial did not resolve the date — got \(second)")
    }

    /// **The arm, through the card.** Same empty argument, same date-bearing
    /// sentence, same `now` as the control below — and the user is shown a
    /// DATELESS card, because the fallback did not run.
    @Test func theNofallbackArmStagesADatelessCard() async {
        let now = todayAt(9, 15)

        let due = await StagedReminderProbe.staged(
            rawDue: "", userText: "Remind me to call mom tomorrow at 4pm",
            now: now, relay: relay(disablingFallback: true)).due

        #expect(due?.isEmpty == true,
                "the fallback ran with the switch set — got \(due ?? "nil")")
    }

    /// **The control, and it is the same call with one Bool flipped.**
    ///
    /// Without this row the row above would pass on a broken fallback, a broken
    /// detector, or a seam that never carried the sentence at all — every one of
    /// which also produces a dateless card. The pair is the measurement; neither
    /// half is.
    @Test func theTreatmentArmStagesTomorrowFromTheSameInputs() async {
        let now = todayAt(9, 15)

        let due = await StagedReminderProbe.staged(
            rawDue: "", userText: "Remind me to call mom tomorrow at 4pm",
            now: now, relay: relay(disablingFallback: false)).due

        #expect(due == DeviceActionParsing.displayDate(day(1, from: now, at: 16, 0)),
                "the control arm must still resolve tomorrow 4:00 PM, got \(due ?? "nil")")
    }

    /// **`source=none` on a nofallback trial whose argument was empty** — which
    /// is what the scorer reads, and what makes the arm's `userText=0` a
    /// measurement rather than an absence of data.
    ///
    /// Note what it is NOT: `legacy`. That label means the archive predates the
    /// field entirely. This arm makes the positive claim that no date reached
    /// the card, and the resolver is where that claim is minted.
    @Test func theNofallbackArmReportsSourceNone() {
        let now = todayAt(9, 15)

        let resolution = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: "Remind me to call mom tomorrow at 4pm",
            now: now, allowUserTextFallback: false)

        #expect(resolution.source == "none",
                "expected source=none with the fallback off, got \(resolution.source)")
        #expect(resolution.date == nil)
        #expect(resolution.bareClock == "no",
                "an empty argument still carries no bare clock")
    }

    /// **The switch touches the FALLBACK and nothing else.** A model-supplied
    /// argument must resolve identically in both arms — otherwise the cell is
    /// measuring the resolver rather than the fallback, and the two arms'
    /// `source=model` counts would not be comparable.
    @Test func theSwitchLeavesAModelSuppliedArgumentAlone() {
        let now = todayAt(9, 15)

        let on = ReminderCreateTool.resolvedDue(
            rawDue: "16:30", userText: "Remind me to call mom tomorrow at 9am",
            now: now, allowUserTextFallback: true)
        let off = ReminderCreateTool.resolvedDue(
            rawDue: "16:30", userText: "Remind me to call mom tomorrow at 9am",
            now: now, allowUserTextFallback: false)

        #expect(on.date == day(0, from: now, at: 16, 30))
        #expect(on.date == off.date, "the switch moved a model-supplied date")
        #expect(on.source == "model" && off.source == "model")
        #expect(on.bareClock == off.bareClock)
    }
}

/// **The structural half of Task 4 — pins no runtime test in this target can
/// make.**
///
/// The battery loop needs a live `LanguageModelSession` per trial (#324: the
/// simulator cannot generate on this model at all), so what it does to the relay
/// between trials is only checkable by reading production's bytes. And the
/// Release containment claim is about code that, by construction, is not in the
/// binary the test runs in.
struct DueDateNofallbackWitnessTests {

    /// The three production files that may name the switch. Listed for the
    /// error message only — `everyMentionOfTheSwitchSitsInsideADebugRegion`
    /// enumerates the whole tree rather than trusting this list.
    private static let expectedHomes = [
        "Talaria/Services/Live/DeviceTools/DeviceToolBelt.swift",
        "Talaria/Services/Live/DeviceTools/DeviceActionTools.swift",
        "Talaria/Services/Live/LocalChatBackend+Battery.swift",
    ]

    // MARK: - The Release containment pin

    /// Whether each line of `source` sits inside an ACTIVE `#if DEBUG` branch.
    ///
    /// Maintains a stack over `#if` / `#elseif` / `#else` / `#endif`. A level
    /// contributes DEBUG-only-ness when its condition mentions `DEBUG` and does
    /// not negate it; an `#else` is the branch the OTHER configuration takes, so
    /// it contributes nothing. Anything it cannot classify contributes nothing
    /// either — the check must FAIL SAFE, reporting an unguarded mention rather
    /// than waving one through, because the cost of a false red is a minute and
    /// the cost of a false green is a Release build that ships a measurement
    /// switch.
    private static func debugGuarded(_ source: String) -> [(line: String, guarded: Bool)] {
        var stack: [Bool] = []
        var out: [(String, Bool)] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                stack.append(isDebugCondition(trimmed.dropFirst(4)))
                out.append((String(line), stack.contains(true)))
                continue
            }
            if trimmed.hasPrefix("#elseif ") {
                if !stack.isEmpty { stack[stack.count - 1] = isDebugCondition(trimmed.dropFirst(8)) }
                out.append((String(line), stack.contains(true)))
                continue
            }
            if trimmed == "#else" {
                if !stack.isEmpty { stack[stack.count - 1] = false }
                out.append((String(line), stack.contains(true)))
                continue
            }
            if trimmed == "#endif" {
                out.append((String(line), stack.contains(true)))
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            out.append((String(line), stack.contains(true)))
        }
        return out
    }

    private static func isDebugCondition(_ condition: some StringProtocol) -> Bool {
        let text = String(condition)
        guard text.contains("DEBUG") else { return false }
        // `!DEBUG` is the Release branch wearing a DEBUG-shaped name.
        return !text.contains("!DEBUG") && !text.contains("! DEBUG")
    }

    /// **Production cannot reach the switch, and this is the half a Release
    /// build alone cannot show.**
    ///
    /// A Release build proves the tree COMPILES; it does not prove the symbol is
    /// absent from the shipped binary, because a symbol reachable from
    /// non-DEBUG code would compile perfectly well and simply ship. #218's
    /// lesson runs the other way too — the Release build is necessary and it is
    /// not sufficient. This row reads every Swift file under `Talaria/` and
    /// requires each mention of the switch to sit inside an active `#if DEBUG`.
    ///
    /// It also requires at least one mention, so a rename cannot make it pass by
    /// finding nothing — the `cmd | grep || echo "absent"` trap, which this
    /// project has paid for before.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func everyMentionOfTheSwitchSitsInsideADebugRegion() throws {
        let root = RepoSourceWitness.repoRoot.appendingPathComponent("Talaria")
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "Talaria/ is unreadable — this pin must fail loudly, not vacuously")

        var mentions = 0
        var unguarded: [String] = []
        var files: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains("disableUserTextDueFallback") else { continue }
            files.insert(url.lastPathComponent)
            for (line, guarded) in Self.debugGuarded(text)
            where line.contains("disableUserTextDueFallback") {
                mentions += 1
                if !guarded {
                    unguarded.append("\(url.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(mentions >= 3,
                "found \(mentions) mentions of the switch — a rename would make this pin vacuous, so it fails rather than passing on an empty search")
        #expect(unguarded.isEmpty,
                "the switch is reachable from a non-DEBUG region:\n\(unguarded.joined(separator: "\n"))")
        #expect(files.count == 3,
                "expected the switch in exactly the three files that own it (\(Self.expectedHomes.map { ($0 as NSString).lastPathComponent })), found \(files.sorted())")
    }

    /// **The control for the scanner**, because a classifier that answered
    /// `true` for everything would pass the row above with no work done. Two
    /// synthetic files, one guarded and one not, plus the `#else` arm that is
    /// the whole reason the scanner is not a `contains("#if DEBUG")`.
    @Test func theDebugRegionScannerTellsTheTwoApart() {
        let guarded = """
        #if DEBUG
        var flag = false
        #endif
        """
        let unguarded = """
        #if DEBUG
        let a = 1
        #else
        var flag = false
        #endif
        var b = 2
        """
        #expect(Self.debugGuarded(guarded).first { $0.line.contains("flag") }?.guarded == true)
        #expect(Self.debugGuarded(unguarded).first { $0.line.contains("flag") }?.guarded == false,
                "an #else branch is the RELEASE branch and must never read as guarded")
        #expect(Self.debugGuarded(unguarded).first { $0.line.contains("var b") }?.guarded == false,
                "the scanner never popped the #if — everything after would read as guarded")
        #expect(Self.debugGuarded("#if !DEBUG\nvar flag = false\n#endif")
                    .first { $0.line.contains("flag") }?.guarded == false,
                "#if !DEBUG is the Release branch wearing a DEBUG-shaped name")
    }

    // MARK: - The engine consults the switch ONCE

    /// **One consult, at the fallback term, in the ONE engine.**
    ///
    /// The alternative — a fifth `ReminderCreateTool…` struct for the cell —
    /// would put a second copy of the create flow behind the measurement, which
    /// is the mistake `performCreate`'s own doc comment exists to prevent
    /// (*"two structs, one engine"*) and the mistake the retired
    /// `armed-bareclock` copy eventually became. So the pin is on the CALL SITE:
    /// exactly one line in `DeviceActionTools.swift` reads the relay's switch,
    /// and `resolvedDue`'s fallback term is what consumes it.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theEngineConsultsTheSwitchAtExactlyOnePlace() throws {
        let line = try RepoSourceWitness.soleLine(
            containing: "relay.disableUserTextDueFallback",
            in: RepoSourceWitness.deviceActionToolsPath)
        #expect(line.contains("await"),
                "the relay is MainActor-isolated; the read must be an await, not a stashed copy")

        let source = try RepoSourceWitness.source(RepoSourceWitness.deviceActionToolsPath)
        let engines = source.components(separatedBy: "func performCreate(").count - 1
        #expect(engines == 2,
                "expected exactly two performCreate engines — reminders and calendar — found \(engines); a third means the nofallback cell got a copy instead of a flag")
    }

    /// The fallback term itself is what the flag gates — not the log line, not
    /// the guards, not the card. If the consult ever moved off the term, an arm
    /// could report `source=none` while the card carried a date.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theSwitchGatesTheFallbackTermItself() throws {
        // The SOLE line carrying the detector call, which is the fallback term
        // itself. Reading the whole function body instead would be VACUOUS: the
        // parameter name appears in `resolvedDue`'s own signature, so a version
        // that declared the switch and then ignored it would satisfy a
        // body-level `contains` and a body-level ordering check alike. The gate
        // has to be on the same line as the thing it gates.
        // NEEDLE RE-POINTED 2026-09-04 (the final fix wave), and the claim is
        // unchanged. The term now calls the LIST form — decision 2's second
        // clause needs the candidate count, and `detectDue` is exactly
        // `candidates.first`, so the answer did not move. The old needle
        // (`…detectDue(in: userText`) would now match ZERO lines and this row
        // would red for a reason unrelated to what it asserts.
        let term = try RepoSourceWitness.soleLine(
            containing: "DeviceActionParsing.detectDueCandidates(in: userText",
            in: RepoSourceWitness.deviceActionToolsPath)
        #expect(term.contains("allowUserTextFallback"),
                "the fallback term is not gated by the switch — got: \(term)")
        #expect(term.contains("rawDue.isEmpty"),
                "Owen's decision 1 (fire on an EMPTY argument only) left the term")
    }

    // MARK: - The battery arms it for this cell's trials and no other's

    /// **The switch is written EVERY trial, from the cell, at the turn
    /// boundary — so it cannot leak into the `armed` arm of the same run.**
    ///
    /// A matched set-here/clear-there pair is the shape that leaks: #343's
    /// governor bug was precisely a per-turn field reset somewhere other than
    /// the turn boundary, and `beginTurn(userText:)`'s `nil` default exists
    /// because Task 2 reached the same conclusion. One unconditional assignment
    /// derived from `cell` has no "clear" step to forget: every non-nofallback
    /// trial writes `false` as a side effect of writing anything at all.
    ///
    /// Pinned as the SOLE assignment-from-the-cell in the file, which is what
    /// makes the pair shape a failure rather than an alternative. (The needle
    /// carries `= (cell` on purpose: fix round 1 added a SECOND mention to
    /// this file — the run-end clear pinned by
    /// `theRunEndClearsTheSwitchBesideTheTrialTagClear` — so a bare
    /// `disableUserTextDueFallback` needle would now find two lines and this
    /// pin would fail for a reason unrelated to its claim.)
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theBatteryArmsTheSwitchFromTheCellEveryTrial() throws {
        let line = try RepoSourceWitness.soleLine(
            containing: "disableUserTextDueFallback = (cell",
            in: RepoSourceWitness.batteryPath)
        #expect(line.contains("toolRelay?.disableUserTextDueFallback = (cell == .armedNofallback)"),
                "the battery must write the switch from the cell on every trial — a conditional set leaks into the next cell's trials; got: \(line)")

        let loop = try RepoSourceWitness.functionBody(
            from: "func runActionBattery(", in: RepoSourceWitness.batteryPath)
        #expect(loop.contains("battery: WARMUP begin cell="),
                "the witness read no runActionBattery body at all — a vacuous pin")
        #expect(loop.contains("disableUserTextDueFallback"),
                "the assignment is outside the shared trial loop, so some trials never write it")
        let begin = try #require(loop.range(of: "toolRelay?.beginTurn(userText:"))
        let arm = try #require(loop.range(of: "toolRelay?.disableUserTextDueFallback"))
        #expect(begin.lowerBound < arm.lowerBound,
                "the switch must be armed at the turn boundary, after the turn is opened")
    }

    /// **The run's END clears the switch too — fix round 1's row (b).**
    ///
    /// `beginTurn` clears it at every turn boundary, so nothing that OPENS a
    /// turn can inherit a previous run's setting. That is the load-bearing
    /// half. This is the other one: the battery's warm-up trial opens no turn
    /// (`batteryWarmupTag` is set, `beginTurn` is not called), and a run that
    /// dies mid-cell never reaches another boundary at all — so the relay is
    /// left holding whatever the last trial wrote, which for the default cell
    /// list is `true`. The clear sits beside the `batteryTrialTag` clear
    /// because that is already the run's teardown line, and a teardown split
    /// across two places is the shape that gets half-forgotten.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theRunEndClearsTheSwitchBesideTheTrialTagClear() throws {
        let loop = try RepoSourceWitness.functionBody(
            from: "func runActionBattery(", in: RepoSourceWitness.batteryPath)
        #expect(loop.contains("battery: DONE (#200)"),
                "the witness read no runActionBattery teardown at all — a vacuous pin")

        let arm = try #require(loop.range(of: "disableUserTextDueFallback = (cell"),
                               "the per-trial arming line is gone — this pin reads the teardown relative to it")
        let clear = try #require(
            loop.range(of: "toolRelay?.disableUserTextDueFallback = false", range: arm.upperBound..<loop.endIndex),
            "the run ends without clearing the switch — the relay is shared with production chat and every later instrument in the launch")
        let tag = try #require(
            loop.range(of: "ToolEventRelay.batteryTrialTag = nil", range: arm.upperBound..<loop.endIndex),
            "runActionBattery's trial-tag clear is gone — re-point this pin at its successor")

        // Beside it, and after it: the teardown is one place, not two.
        //
        // "Beside" is defined as *nothing EXECUTABLE stands between them* —
        // a comment, however long, still leaves the two clears one block. A
        // character-distance pin would have measured the comment instead of
        // the code, and would red the day someone explains the clear better.
        #expect(tag.upperBound <= clear.lowerBound,
                "the switch is cleared before the trial tag — keep the teardown in one order so a reader finds both")
        let intervening = loop[tag.upperBound..<clear.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        #expect(intervening.isEmpty,
                "the run-end clear drifted away from the trial-tag clear — \(intervening.count) statement(s) now stand between them, starting: \(intervening.first ?? "")")
    }

    /// **The cell rides production's belt** — no tool swap, no instructions
    /// swap. Its only delta from `armed` is the flag, and a belt swap would make
    /// it two deltas wearing one name.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theCellSwapsNoToolAndNoInstructions() throws {
        let belt = try RepoSourceWitness.functionBody(
            from: "static func destallBelt(", in: RepoSourceWitness.batteryPath,
            boundary: "\n    /// ")
        #expect(belt.contains("return tools"),
                "the witness read no destallBelt body at all — a vacuous pin")
        #expect(belt.contains(".armedNofallback"),
                "the cell is missing from the belt shaper — Swift's exhaustive switch would not compile, so this can only mean the witness is reading the wrong function")
        #expect(!belt.contains("case .armedNofallback:"),
                "the cell has a belt swap of its own — it must ride production's belt, or it differs from `armed` in two ways instead of one")

        // The instructions switch lives inside the trial loop's cell pass.
        let source = try RepoSourceWitness.source(RepoSourceWitness.batteryPath)
        #expect(!source.contains("case .armedNofallback:"),
                "the cell has a switch arm somewhere in the battery — belt, instructions or profile. Its only delta from `armed` may be the fallback switch.")
    }
}
