import Foundation
import Testing
@testable import Talaria

/// **#340 bar 340-U-C's MECHANISM — the due date resolved from the user's own
/// words when the model left the argument empty.**
///
/// Tasks 1 and 2 built the two halves: `DeviceActionParsing.detectDue(in:now:)`
/// reads a date out of a sentence deterministically, and
/// `ToolEventRelay.beginTurn(userText:)` carries the sentence to the tool belt.
/// Neither is reachable from production yet — Task 2's own report says the seam
/// is "dead storage until Task 3". This file pins the join.
///
/// **Owen's decisions, encoded here rather than described:**
/// 1. the fallback fires ONLY when the model's `due` argument is EMPTY — an
///    unparseable value stays on today's wrong-value path;
/// 2. reminders only (no calendar/alarm equivalent is built);
/// 3. no date in the words ⇒ the card stays DATELESS, and nothing is invented.
///
/// **Why the card, not the return string.** #340's founding artifact is a card
/// that read TITLE set / **DUE EMPTY** while the model's reply claimed a time.
/// `BareClockWiringTests` established the shape: drive `performCreate`
/// end-to-end with `now` pinned, read the staged card's DUE field, decline.
/// Declining creates nothing and needs no EventKit grant, and the argument is
/// on the record before the confirmation gate is consulted.
@MainActor
struct ReminderDueFallbackTests {

    // MARK: - Helpers

    /// `now`, pinned to a wall-clock time on TODAY's date.
    ///
    /// `NSDataDetector` resolves "tomorrow" against the **process's real
    /// clock** and takes no reference date, so a `now` on a fabricated calendar
    /// day would compare the detector's real tomorrow against an invented one.
    /// Pinning the time of day while keeping today's date is the one
    /// construction that makes day-offset assertions deterministic — the same
    /// rule `DeviceActionParsingDetectDueTests` runs on, and its reason.
    private func todayAt(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                              of: Calendar.current.startOfDay(for: Date()))!
    }

    private func day(_ offset: Int, from now: Date, at hour: Int, _ minute: Int) -> Date {
        let calendar = Calendar.current
        let shifted = calendar.date(byAdding: .day, value: offset, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted)!
    }

    /// Drives `performCreate` to completion and reports BOTH what it staged and
    /// what it returned — `BareClockWiringTests`' seam, with the user's
    /// sentence threaded in.
    ///
    /// **The body moved to `StagedReminderProbe` (#340 Task 4)**, unchanged, for
    /// the reason Task 3 gave when it hoisted `RepoSourceWitness`: Task 4 needs
    /// the same drive with a relay it has configured, and the right move at that
    /// moment is one helper rather than one more copy. The two measured hazards
    /// it closes — a yield-counted poll that cannot see an off-actor callee, and
    /// awaiting a task that may never finish — are documented there.
    private func staged(rawDue: String, userText: String,
                        now: Date) async -> (due: String?, result: String) {
        await StagedReminderProbe.staged(rawDue: rawDue, userText: userText,
                                         now: now, relay: ToolEventRelay())
    }

    private func stagedDue(rawDue: String, userText: String, now: Date) async -> String? {
        await staged(rawDue: rawDue, userText: userText, now: now).due
    }

    // MARK: - The fallback, through the card (the rows the brief names)

    /// **The bar's mechanism, end to end.** The model sent nothing; the user's
    /// own sentence carries the date; the card the user is shown must read
    /// tomorrow at 4 PM.
    ///
    /// The expectation is built from `now` rather than routed back through
    /// `detectDue`, so this is not a restatement of Task 1 — if the detector
    /// ever stopped reading "tomorrow at 4pm" as 16:00 this row reds, and so
    /// does `DeviceActionParsingDetectDueTests`.
    @Test func anEmptyDueTakesTheDateFromTheUsersWords() async {
        let now = todayAt(9, 15)

        let due = await stagedDue(rawDue: "",
                                  userText: "Remind me to call mom tomorrow at 4pm",
                                  now: now)

        #expect(due?.isEmpty == false,
                "DUE came through EMPTY — the user said a date and the card does not carry it")
        #expect(due == DeviceActionParsing.displayDate(day(1, from: now, at: 16, 0)),
                "expected tomorrow 4:00 PM, got \(due ?? "nil")")
    }

    /// **Owen's decision 1, the half that is easy to break.** A populated
    /// argument keeps today's path byte-for-byte: the model's `16:30` wins even
    /// though the user's sentence names a different, equally readable time. A
    /// fallback that ran unconditionally — or that preferred the "richer" of
    /// the two — would pass every other row in this file.
    @Test func aPopulatedDueBeatsTheUsersWords() async {
        let now = todayAt(9, 15)

        let due = await stagedDue(rawDue: "16:30",
                                  userText: "Remind me to call mom tomorrow at 9am",
                                  now: now)

        #expect(due == DeviceActionParsing.displayDate(day(0, from: now, at: 16, 30)),
                "the model's own argument must win, got \(due ?? "nil")")
    }

    /// **Owen's decision 3.** No date in the words ⇒ dateless. Nothing is
    /// invented, which is #180's family and the one failure mode worse than the
    /// omission this lane is fixing.
    @Test func wordsWithNoDateStillStageADatelessCard() async {
        let due = await stagedDue(rawDue: "", userText: "Remind me to call mom",
                                  now: todayAt(9, 15))

        #expect(due?.isEmpty == true,
                "a due date was invented from a sentence that names none — got \(due ?? "nil")")
    }

    /// **Owen's decision 1's other half: EMPTY, not UNREADABLE.** A non-empty
    /// argument the app cannot parse stays on today's wrong-value path even
    /// when the user's sentence would have resolved cleanly. The scorer counts
    /// that as `wrong-value`, and it must stay countable: a fallback that
    /// rescued unparseable arguments would silently zero the bucket #340-C
    /// measured.
    @Test func anUnparseableDueDoesNotFallBackToTheUsersWords() async {
        let due = await stagedDue(rawDue: "sometime later",
                                  userText: "Remind me to call mom tomorrow at 4pm",
                                  now: todayAt(9, 15))

        #expect(due?.isEmpty == true,
                "an unparseable argument must NOT be rescued by the fallback — got \(due ?? "nil")")
    }

    /// The three existing guards run on the fallback's result **unchanged**.
    ///
    /// `detectDue` never returns a past instant, so past-due cannot fire from
    /// this path — but the wee-hour ask can, and it is the one guard a
    /// user-worded date can reach. "tomorrow at 5am" is exactly #233's shape,
    /// and the tool must bounce it rather than stage a card, precisely as it
    /// does for a model-supplied `T05:00`.
    @Test func aFallbackDueRunsTheSameGuardsAModelSuppliedOneDoes() async {
        let outcome = await staged(rawDue: "",
                                   userText: "Remind me to call mom tomorrow at 5am",
                                   now: todayAt(9, 15))

        #expect(outcome.due == nil, "a wee-hour fallback due must not stage a card")
        #expect(outcome.result.contains("early morning"),
                "expected #233's wee-hour bounce, got: \(outcome.result)")
    }

    // MARK: - The instrument's `source=` field, pinned by value

    /// `source=userText` — the fallback produced the date.
    @Test func theSourceIsUserTextWhenTheFallbackProducedTheDate() {
        let now = todayAt(9, 15)

        let resolution = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: "Remind me to call mom tomorrow at 4pm", now: now)

        #expect(resolution.source == "userText")
        #expect(resolution.date == day(1, from: now, at: 16, 0))
        #expect(resolution.bareClock == "no", "an empty argument carries no bare clock")
    }

    /// `source=model` — the model's own argument produced it. Both model
    /// shapes are pinned: the bare clock route (a) resolves, and an explicit
    /// ISO timestamp, which is a different branch of the same answer.
    @Test func theSourceIsModelWhenTheArgumentProducedTheDate() {
        let now = todayAt(9, 15)

        let bare = ReminderCreateTool.resolvedDue(
            rawDue: "16:30", userText: "Remind me to call mom tomorrow at 9am", now: now)
        #expect(bare.source == "model")
        #expect(bare.date == day(0, from: now, at: 16, 30))
        #expect(bare.bareClock == "resolved",
                "the scorer's existing bareClock column must survive this change")

        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let explicit = ReminderCreateTool.resolvedDue(
            rawDue: iso.string(from: day(3, from: now, at: 11, 0)),
            userText: "Remind me to call mom tomorrow at 4pm", now: now)
        #expect(explicit.source == "model")
        #expect(explicit.date == day(3, from: now, at: 11, 0))
        #expect(explicit.bareClock == "no")
    }

    /// `source=none` — the card is dateless. Both routes to it are pinned,
    /// because they are different findings downstream: an EMPTY argument whose
    /// sentence names nothing is `omitted`, an UNPARSEABLE one is
    /// `wrong-value`, and the scorer must keep telling them apart.
    @Test func theSourceIsNoneWhenTheCardStaysDateless() {
        let now = todayAt(9, 15)

        let omitted = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: "Remind me to call mom", now: now)
        #expect(omitted.source == "none")
        #expect(omitted.date == nil)

        let unreadable = ReminderCreateTool.resolvedDue(
            rawDue: "sometime later",
            userText: "Remind me to call mom tomorrow at 4pm", now: now)
        #expect(unreadable.source == "none")
        #expect(unreadable.date == nil)
        #expect(unreadable.bareClock == "no")
    }

    /// The resolver's three source values are EXHAUSTIVE and disjoint. A fourth
    /// value would reach the log line and the scorer would bucket it under a
    /// name nobody wrote — so the label set is pinned rather than assumed.
    @Test func theSourceLabelIsAlwaysOneOfTheThree() {
        let now = todayAt(9, 15)
        let cases: [(String, String)] = [
            ("", "Remind me to call mom tomorrow at 4pm"),
            ("", "Remind me to call mom"),
            ("16:30", "Remind me to call mom tomorrow at 9am"),
            ("sometime later", "Remind me to call mom tomorrow at 4pm"),
            ("", ""),
        ]
        for (rawDue, userText) in cases {
            let source = ReminderCreateTool.resolvedDue(
                rawDue: rawDue, userText: userText, now: now).source
            #expect(["model", "userText", "none"].contains(source),
                    "unexpected source label \"\(source)\" for raw=\"\(rawDue)\"")
        }
    }

    // MARK: - Decision 2's second clause: the CANDIDATE COUNT

    /// **Owen's decision 2 has two clauses and only the first was built.** The
    /// ruling reads *"take the EARLIEST future date and LOG THE CANDIDATE
    /// COUNT"* — `detectDueCandidates` existed and nothing consumed its count,
    /// so the one edge the ruling is about (a message carrying TWO dates, where
    /// the earliest-future rule is actually choosing rather than merely
    /// passing a single answer through) was invisible in every archive.
    ///
    /// **`0` on the model path is a claim, not a placeholder.** The count is
    /// only computed when the fallback RAN: a populated argument short-circuits
    /// before the detector is ever constructed, which is what keeps today's
    /// path byte-for-byte unchanged (`NSDataDetector`'s first construction in a
    /// process costs ~36 ms — measured in this file's own RED). So `0` reads as
    /// "the fallback did not run, or ran and found nothing", and the `source=`
    /// field is what tells those two apart on the same line.
    ///
    /// A date phrase built from `now` rather than written as a literal, for the
    /// reason `DeviceActionParsingDetectDueTests` gives: a hardcoded date starts
    /// failing the day after it is written and reads as a parser regression.
    @Test func theCandidateCountIsTheFallbacksOwnAndZeroOnTheModelPath() {
        let now = todayAt(9, 15)
        let twoDates = "Remind me tomorrow at 4pm and again on "
            + monthDay(day(2, from: now, at: 9, 0)) + " at 9am"

        let two = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: twoDates, now: now)
        #expect(two.candidates == 2,
                "the two-date edge decision 2 rules on must be visible, got \(two.candidates)")
        #expect(two.date == day(1, from: now, at: 16, 0),
                "and the count must not disturb the earliest-future answer")

        let one = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: "Remind me to call mom tomorrow at 4pm", now: now)
        #expect(one.candidates == 1)

        let noneFound = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: "Remind me to call mom", now: now)
        #expect(noneFound.candidates == 0, "no date in the words is a zero")

        // The model path never counts: the detector is not reached at all.
        let model = ReminderCreateTool.resolvedDue(
            rawDue: "16:30", userText: twoDates, now: now)
        #expect(model.candidates == 0,
                "a populated argument must not run the detector, got \(model.candidates)")

        // …and neither does the `armed-nofallback` arm, whose whole
        // contribution is that the fallback did not run.
        let off = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: twoDates, now: now, allowUserTextFallback: false)
        #expect(off.candidates == 0, "the switch is off; nothing was counted")
    }

    /// A date phrase built from `now` — see the row above.
    private func monthDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }
}

/// **The structural half of Task 3 — three pins that no runtime test in this
/// target can make.**
///
/// The battery loop needs a live `LanguageModelSession` per trial (#324: the
/// simulator cannot generate at all on this model), and `os_log` output is not
/// readable from the test process. So the log line's FIELD ORDER and the
/// battery's per-trial call are only checkable by reading production's bytes.
///
/// Gated on the simulator for the same reason `DeviceActionParsingDetectDueTests`
/// is: off-simulator the read fails with NSCocoaErrorDomain 260, which measures
/// the sandbox and not the code.
struct ReminderDueSourceWitnessTests {

    // MARK: - The instrument line

    /// **`source=` must sit BEFORE ` parsed=`, and this is not style.**
    ///
    /// `score-due-omission.py`'s `parsed` group runs GREEDILY to end-of-line,
    /// so any field appended after it is silently swallowed into that group.
    /// The scorer's own comment records this: route (a) put `bareClock=` ahead
    /// of `parsed` for exactly this reason, and notes that a trailing field
    /// would have made every `parsed` read `nil bareClock=no` — zeroing the
    /// `unreadable` bucket without a single test noticing. This row is that
    /// comment turned into a check.
    ///
    /// **Extended by the final fix wave (2026-09-04) to cover `candidates=`,
    /// which is the SECOND field to land in front of `parsed` under this same
    /// rule.** The order is pinned as a chain — `bareClock` → `source` →
    /// `candidates` → `parsed` — rather than as three independent facts,
    /// because the hazard is positional: any one of them drifting past `parsed`
    /// corrupts every reading of it, and a pin that only knew about `source`
    /// would have watched the new field walk straight into the trap it was
    /// written for.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theInstrumentLineCarriesSourceAheadOfParsed() throws {
        let line = try RepoSourceWitness.soleLine(
            containing: "createReminder due raw=",
            in: RepoSourceWitness.deviceActionToolsPath)

        let bareClock = try #require(line.range(of: "bareClock="),
                                     "the scorer's bareClock column is gone from the instrument line")
        let source = try #require(line.range(of: "source="),
                                  "the instrument line carries no source= field")
        let candidates = try #require(line.range(of: "candidates="),
                                      "the instrument line carries no candidates= field")
        let parsed = try #require(line.range(of: "parsed="),
                                  "the instrument line carries no parsed= field")

        #expect(bareClock.lowerBound < source.lowerBound,
                "source= must follow bareClock=, matching the scorer's field order")
        #expect(source.lowerBound < candidates.lowerBound,
                "candidates= must follow source=, matching the scorer's field order")
        #expect(candidates.lowerBound < parsed.lowerBound,
                "candidates= must precede parsed= — parsed runs greedily to end-of-line and would swallow it")
        #expect(source.lowerBound < parsed.lowerBound,
                "source= must precede parsed= — parsed runs greedily to end-of-line and would swallow it")
    }

    /// The field is the RESOLVER's answer, not a second opinion. A literal, or
    /// a re-derivation at the log site, could drift from the date the card
    /// actually carries — and the whole point of `resolvedDue` returning both
    /// is that they cannot.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theInstrumentLineInterpolatesTheResolversOwnSource() throws {
        let line = try RepoSourceWitness.soleLine(
            containing: "createReminder due raw=",
            in: RepoSourceWitness.deviceActionToolsPath)

        #expect(line.contains("source=\\(resolution.source"),
                "source= must interpolate the resolver's value, not restate the rule at the log site")
    }

    /// **Every `createReminder` tool reads the turn's text — production and all
    /// three `#if DEBUG` treatment copies.**
    ///
    /// The copies exist so a measured cell's ONLY delta from production is
    /// model-facing TEXT — *"two structs, one engine"*, in `performCreate`'s
    /// own words, and each copy's doc comment claims it in as many words. If
    /// only production passed the user's sentence, those comments would become
    /// false the moment this landed and every future A/B against `armed` would
    /// silently move the ENGINE as well as the guide. The count is pinned
    /// rather than the sites, so adding a fifth copy that forgets it reds here.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func everyReminderCreateToolCarriesTheTurnsUserText() throws {
        let source = try RepoSourceWitness.source(RepoSourceWitness.deviceActionToolsPath)

        let reads = source.components(separatedBy: "await relay.currentTurnUserText").count - 1
        #expect(reads == 4,
                "expected 4 reads of the turn text (production + three DEBUG copies), found \(reads)")

        let passes = source.components(separatedBy: "userText: turnUserText").count - 1
        #expect(passes == 4,
                "expected 4 createReminder call sites to pass it on, found \(passes)")
    }

    // MARK: - The battery's per-trial call (#215 applied to this instrument)

    /// **The due-date battery's trials must carry the prompt text, or bar
    /// 340-U-C measures the fallback in its OFF configuration.**
    ///
    /// Every DEBUG instrument calls the bare `toolRelay?.beginTurn()` once per
    /// trial (#343's governor reset), and Task 2 made that bare form CLEAR
    /// `currentTurnUserText`. So without this the fallback can never fire in a
    /// battery trial, `source=userText` would read 0/40, and the bar would miss
    /// for a reason that has nothing to do with the product — #215's unrouted
    /// cell exactly: a rate measured on a configuration production never enters.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theDueDateBatteryCarriesThePromptTextIntoTheTurn() throws {
        let loop = try RepoSourceWitness.functionBody(
            from: "func runActionBattery(", in: RepoSourceWitness.batteryPath)
        #expect(loop.contains("toolRelay?.beginTurn(userText: carriesUserText ? prompt : nil)"),
                "the shared trial loop must pass the prompt text when the caller asked for it")

        let battery = try RepoSourceWitness.functionBody(
            from: "func runDueDateBattery(", in: RepoSourceWitness.batteryPath)
        #expect(battery.contains("carriesUserText: true"),
                "runDueDateBattery must opt in, or its trials measure the fallback switched off")
    }

    /// **The control for the witness above, and it has both halves.**
    ///
    /// An empty extraction passes every `!contains` assertion vacuously; a
    /// whole-file extraction passes every `contains` assertion for the wrong
    /// reason. Both bodies are therefore checked for a marker unique to them
    /// and for the absence of the NEXT function's declaration, which is exactly
    /// what an unbounded read would drag in.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func theBatteryWitnessReadsTwoBoundedFunctionBodies() throws {
        let loop = try RepoSourceWitness.functionBody(
            from: "func runActionBattery(", in: RepoSourceWitness.batteryPath)
        #expect(loop.contains("battery: WARMUP begin cell="),
                "the witness read no runActionBattery body at all — a vacuous pin")
        #expect(!loop.contains("func runDestallBattery("),
                "the witness overran runActionBattery — its pins would pass on another function's text")

        let battery = try RepoSourceWitness.functionBody(
            from: "func runDueDateBattery(", in: RepoSourceWitness.batteryPath)
        #expect(battery.contains("promptSet: Self.dueDatePromptSet"),
                "the witness read no runDueDateBattery body at all — a vacuous pin")
        #expect(!battery.contains("func runDeclineBattery("),
                "the witness overran runDueDateBattery — its pins would pass on another function's text")
    }

    /// **Every OTHER instrument keeps its bare call, byte-identical.**
    ///
    /// The bare form is #343's governor reset AND Task 2's clear-the-field
    /// boundary. An instrument that started carrying text would let a trial
    /// resolve a due date from a sentence typed several trials ago — the exact
    /// leak `aTurnWithNoTextClearsTheLastOne` pins from the other side. One
    /// opt-in exists, in one function, and this row is what keeps it to one.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func noOtherInstrumentPassesTextToTheTurnBoundary() throws {
        let instruments = [
            "Talaria/Services/Live/LocalChatBackend+CardClause.swift",
            "Talaria/Services/Live/LocalChatBackend+Refusal.swift",
            "Talaria/Services/Live/LocalChatBackend+OfferRead.swift",
            "Talaria/Services/Live/LocalChatBackend+ToolFailure.swift",
        ]
        for path in instruments {
            let source = try RepoSourceWitness.source(path)
            #expect(source.contains("toolRelay?.beginTurn()"),
                    "\(path) no longer resets the turn per trial — #343's leak, reopened")
            #expect(!source.contains("beginTurn(userText:"),
                    "\(path) started carrying turn text — only runActionBattery may opt in")
        }

        // The shape battery lives in the same file as the opt-in, so it is
        // checked by body rather than by file.
        let shape = try RepoSourceWitness.functionBody(
            from: "func runShapeBattery(", in: RepoSourceWitness.batteryPath)
        #expect(shape.contains("toolRelay?.beginTurn()"),
                "runShapeBattery's bare per-trial reset is gone")
        #expect(!shape.contains("beginTurn(userText:"),
                "runShapeBattery must keep the bare form")
    }
}
