import Foundation
import Testing
@testable import Talaria

/// A structural pin has to read the repo's own sources, so it can only be
/// scored where the test process shares the Mac's filesystem — a simulator.
/// Off-simulator the read fails with NSCocoaErrorDomain 260, which measures
/// the sandbox and not the parser. Same gate as `Phase0ActionCautionTests`.
private let repoSourcesAreReadableAtRuntime: Bool = {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
}()

/// **#340 — the due date the USER'S OWN WORDS name (bar 340-U-A).**
///
/// `DeviceActionParsing.detectDue(in:now:)` is the deterministic half of the
/// #340 lane. The on-device brain leaves `due` empty on roughly half the turns
/// whose prompt text plainly carried a date phrase; a later task threads the
/// user's message into `ReminderCreateTool.performCreate` and calls this when
/// the argument is empty. **No model is involved here and none may be** — the
/// last test in this file pins that structurally.
///
/// **Owen's three decisions, encoded:** the earliest FUTURE date when a
/// message carries two; `NSDataDetector` first and the existing bare-clock
/// parser second; **no date in the words ⇒ `nil`** — the card stays dateless
/// and nothing is ever invented.
///
/// ---
///
/// **Why every `now` here is TODAY's date with a pinned time-of-day, and why
/// that is not laziness.** `NSDataDetector` resolves relative phrasings
/// ("tomorrow", "4:30pm", "Friday") against the **process's real clock** and
/// exposes no reference-date parameter — there is no way to hand it an
/// injected `now`. A test that pinned `now` to an arbitrary calendar day would
/// therefore compare the detector's *real* tomorrow against a *fabricated*
/// one and fail for a reason that has nothing to do with the parser. Pinning
/// the **time of day** while keeping today's **date** is the one construction
/// that makes day-offset assertions deterministic.
///
/// Everything below asserts RELATIONS — hour, minute, whole-day offset from
/// `now`, weekday, strictly-after-`now` — and never an absolute date. That is
/// 340-G's instrument flaw applied to a test suite: a fixed *"at 4:30pm"*
/// expectation scores one way before 16:30 local and the other way after, and
/// would rot silently at 16:30 every day.
///
/// **Provenance.** Every expected value below was first measured on macOS
/// 26.6.2's Foundation detector (Task 0's probe, plus a supplementary
/// substring probe run by this task). The simulator run is the parity proof,
/// not that probe — a row that behaves differently on iOS 27 is reported as a
/// parity finding rather than quietly re-fitted.
struct DeviceActionParsingDetectDueTests {

    // MARK: - Helpers

    /// `now`, pinned to a wall-clock time on TODAY's date. See the suite note.
    ///
    /// `Calendar.date(bySettingHour:minute:second:of:)` was measured to set the
    /// time on the SAME day rather than searching forward to the next
    /// occurrence (09:00 set on an 18:21 base returns 09:00 that same day), so
    /// this genuinely moves the clock backwards within today.
    private func todayAt(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                              of: Calendar.current.startOfDay(for: Date()))!
    }

    private func hourMinute(_ date: Date) -> (hour: Int, minute: Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour!, c.minute!)
    }

    /// Whole calendar days between two instants — the only day comparison that
    /// survives a `now` pinned to an arbitrary time of day.
    private func dayOffset(from now: Date, to date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day!
    }

    /// A date phrase built from `now` rather than written as a literal, so the
    /// row cannot expire. A hardcoded "2026-09-09" would start failing on
    /// 2026-09-10 and read as a parser regression.
    private func monthDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }

    private func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func days(_ count: Int, from now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: count, to: now)!
    }

    // MARK: - Rows the detector resolves on its own

    /// The plan's motivating example. The day word licenses the bare hour and
    /// the detector's own convention reads "4" as the afternoon one.
    @Test func tomorrowAtFourPMResolvesToTomorrowAfternoon() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me to call mom tomorrow at 4pm", now: now))
        #expect(hourMinute(due) == (16, 0))
        #expect(dayOffset(from: now, to: due) == 1)
        #expect(due > now)
    }

    /// A bare `4:30` with no meridiem — **the one shape whose detector reading
    /// this suite may not pin to a number, and the reason is a measurement.**
    ///
    /// Task 0 probed all twelve `h:30` clocks at 09:16 and read off a *fixed*
    /// waking-hours map — 1–8 as PM, 9–12 as AM, "with no reference to the
    /// current time." **That is falsified.** Re-probed on 2026-09-04 at
    /// 11:02:51 local, `"Remind me at 10:30"` resolved to **22:30**, where the
    /// same text at 09:16 had given 10:30; the flip landed between 10:55 and
    /// 11:02 in three runs of this very suite. Every one of Task 0's twelve
    /// rows was still ahead of its 09:16 probe time, so a clock-independent map
    /// and "the next occurrence of that reading in a 12-hour cycle" fit the
    /// data identically — and only the second survives a later probe.
    ///
    /// `NSDataDetector` takes no reference date, so this ambiguity is not
    /// something a test can hold still. Asserting `16:30` here would score one
    /// way before ~16:30 local and the other way after — the exact rot this
    /// suite's own header warns about, written into a row. So the row pins what
    /// is actually invariant: the parser's contract, and the fact that the
    /// reading is one of the two the digits can carry.
    @Test func aBareColonClockResolvesToOneOfItsTwoReadingsAndIsAlwaysFuture() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me to test Talaria at 4:30", now: now))
        #expect(hourMinute(due).minute == 30)
        #expect([4, 16].contains(hourMinute(due).hour),
                "a bare 4:30 must read as 04:30 or 16:30, got \(hourMinute(due).hour)")
        #expect(due > now)
    }

    /// A weekday + time. Asserted by WEEKDAY, never by day offset: the gate
    /// runs on whichever day it runs, and "next Tuesday" is 1–7 days out.
    @Test func nextTuesdayNineAMResolvesToATuesdayMorning() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me next Tuesday 9am to call the dentist",
                                          now: now))
        #expect(hourMinute(due) == (9, 0))
        #expect(Calendar.current.component(.weekday, from: due) == 3)   // Tuesday
        #expect(due > now)
    }

    /// A same-day word with a built-in hour. 19:00 is the detector's own
    /// default for "tonight" — the app does not choose it.
    @Test func tonightResolvesToSevenPMToday() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "remind me tonight to take the bins out", now: now))
        #expect(hourMinute(due) == (19, 0))
        #expect(dayOffset(from: now, to: due) == 0)
    }

    @Test func thisEveningAtSevenResolvesToSevenPMToday() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me this evening at 7 to call mom", now: now))
        #expect(hourMinute(due) == (19, 0))
        #expect(dayOffset(from: now, to: due) == 0)
    }

    /// A day with no time defaults to noon, and a weekday name always takes
    /// the NEXT occurrence — probed on a Friday, "on Friday" returned +7 days
    /// rather than today.
    @Test func aDayWithNoTimeDefaultsToNoonOnThatWeekday() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me on Friday to call mom", now: now))
        #expect(hourMinute(due) == (12, 0))
        #expect(Calendar.current.component(.weekday, from: due) == 6)   // Friday
        #expect(due > now)
    }

    @Test func noonResolvesToMiddayToday() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me at noon to eat", now: now))
        #expect(hourMinute(due) == (12, 0))
        #expect(dayOffset(from: now, to: due) == 0)
    }

    /// An explicit calendar date. Built from `now` so the row cannot expire.
    @Test func anExplicitMonthAndDayWithATimeResolvesToThatDate() throws {
        let now = todayAt(9, 15)
        let text = "Remind me on \(monthDay(days(5, from: now))) at 3pm to file the report"
        let due = try #require(DeviceActionParsing.detectDue(in: text, now: now))
        #expect(hourMinute(due) == (15, 0))
        #expect(dayOffset(from: now, to: due) == 5)
    }

    /// The ISO form a user might paste. Also the shape `parseBareClock`
    /// deliberately refuses (any `-` disqualifies it), so this row proves the
    /// detector — not the second pass — carries it.
    @Test func anISOTimestampInTheMessageResolves() throws {
        let now = todayAt(9, 15)
        let text = "Remind me at \(isoDay(days(5, from: now)))T15:00 to file the report"
        let due = try #require(DeviceActionParsing.detectDue(in: text, now: now))
        #expect(hourMinute(due) == (15, 0))
        #expect(dayOffset(from: now, to: due) == 5)
    }

    /// **The instrument's own and only prompt**, in the morning regime — the
    /// clock is still ahead, so the answer is today.
    @Test func theInstrumentPromptAskedInTheMorningResolvesToTodayAtHalfPastFour() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me to test Talaria at 4:30pm", now: now))
        #expect(hourMinute(due) == (16, 30))
        #expect(dayOffset(from: now, to: due) == 0)
    }

    /// A meridiem separated by a space. Either path may serve this — the
    /// detector matched `"4 pm"` on macOS — and both must land on 16:00.
    @Test func aSpacedMeridiemStillReadsAsTheAfternoonHour() throws {
        let now = todayAt(9, 15)
        let due = try #require(DeviceActionParsing.detectDue(in: "Remind me at 4 pm", now: now))
        #expect(hourMinute(due) == (16, 0))
        #expect(due > now)
    }

    // MARK: - The roll-forward, which is the whole fix on the night the instrument runs

    /// A clock already behind `now`. The detector pins a time-only phrase to
    /// TODAY, full stop, and hands back a date in the past — it never rolls
    /// forward. Without this the parser would violate its own contract on
    /// every evening turn.
    @Test func aClockAlreadyPassedTodayRollsToTomorrow() throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me to call mom at 7:45am", now: now))
        #expect(hourMinute(due) == (7, 45))
        #expect(dayOffset(from: now, to: due) == 1)
        #expect(due > now)
    }

    /// A MORNING clock asked about in the AFTERNOON. The detector pins it to
    /// today and hands it back hours gone; the roll-forward is what turns it
    /// into the answer the user meant.
    ///
    /// **The meridiem is written out on purpose, and that is this row's whole
    /// stability story.** The bare `10:30` this row used to carry is
    /// *ambiguous*, and the sibling row above records the measurement that its
    /// AM/PM reading tracks the real clock — at 11:02 local it became 22:30, a
    /// future time needing no roll, and the row stopped testing the roll at all
    /// while still looking like it did. An explicit `am` removes the ambiguity,
    /// so the detector's answer is 10:30 today at any hour the gate runs and
    /// the roll is exercised every time.
    @Test func aMorningClockAskedInTheAfternoonRollsToTomorrow() throws {
        let now = todayAt(14, 0)
        let due = try #require(DeviceActionParsing.detectDue(in: "Remind me at 10:30am", now: now))
        #expect(hourMinute(due) == (10, 30))
        #expect(dayOffset(from: now, to: due) == 1)
        #expect(due > now)
    }

    /// **The row the device run turns on.** 340-U-C's instrument sends this one
    /// text 40 times, and the run is scheduled for the evening — the exact
    /// regime in which the detector's raw answer is 16:30 TODAY, already
    /// elapsed. Unrolled, all 40 trials would land in the scorer's
    /// `already-past` bucket (pinned at zero) and trip `performCreate`'s
    /// past-due bounce besides.
    @Test func theInstrumentPromptAskedInTheEveningRollsToTomorrow() throws {
        let now = todayAt(18, 21)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me to test Talaria at 4:30pm", now: now))
        #expect(hourMinute(due) == (16, 30))
        #expect(dayOffset(from: now, to: due) == 1)
        #expect(due > now)
    }

    /// **The seam between two contracts, pinned deliberately.**
    /// `resolveBareClock` shares `isPastDue`'s five-minute grace, so on its own
    /// it would call 16:30 "still ahead" at 16:32 and hand back a time two
    /// minutes gone. `detectDue`'s contract is strictly stronger — never a
    /// value `<= now` — so the grace window rolls a day here. Written down
    /// because it is a genuine behavioural difference between the two
    /// functions and not an accident of ordering.
    @Test func aClockInsideThePastDueGraceStillRollsForward() throws {
        let now = todayAt(16, 32)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me to test Talaria at 4:30pm", now: now))
        #expect(hourMinute(due) == (16, 30))
        #expect(dayOffset(from: now, to: due) == 1)
        #expect(due > now)
    }

    // MARK: - The bare-clock second pass (every hour the detector cannot see)

    /// A standalone bare hour is **not a date to `NSDataDetector` at any
    /// hour** — all twelve were probed and all twelve returned no match. The
    /// second pass is therefore load-bearing rather than belt-and-braces.
    ///
    /// The reading is `parseBareClock`'s existing one and is deliberately not
    /// redesigned here: no marker means a **24-hour clock**, so "4" is 04:00,
    /// then `resolveBareClock` takes the next occurrence. At 09:15 that is
    /// today for 10/11/12 and tomorrow for 1–9 (09:00 is already behind the
    /// five-minute grace).
    @Test(arguments: 1...12)
    func aBareHourAfterAtResolvesThroughTheSecondPass(hour: Int) throws {
        let now = todayAt(9, 15)
        let due = try #require(
            DeviceActionParsing.detectDue(in: "Remind me at \(hour)", now: now),
            "bare hour \(hour) produced no due date"
        )
        #expect(hourMinute(due) == (hour, 0))
        #expect(dayOffset(from: now, to: due) == (hour >= 10 ? 0 : 1))
        #expect(due > now)
    }

    // MARK: - The words carry no date

    @Test func aMessageWithNoDatePhraseStaysDateless() {
        let now = todayAt(9, 15)
        #expect(DeviceActionParsing.detectDue(in: "Remind me to test Talaria", now: now) == nil)
    }

    @Test func aSecondMessageWithNoDatePhraseStaysDateless() {
        let now = todayAt(9, 15)
        #expect(DeviceActionParsing.detectDue(in: "Remind me to buy milk", now: now) == nil)
    }

    /// "next week" names a week and not a date, and the detector declines it.
    /// Inventing a default here is exactly what decision 5 forbids.
    @Test func anUnresolvableRelativeSpanStaysDateless() {
        let now = todayAt(9, 15)
        #expect(DeviceActionParsing.detectDue(in: "Remind me to plan the trip next week",
                                              now: now) == nil)
    }

    /// **The false-positive family, and the reason the second pass is framed
    /// rather than token-wise.** A duration is neither detector-resolvable nor
    /// a clock. Run over every token, `parseBareClock` would accept the bare
    /// "20" as 20:00 and schedule the reminder for 8 PM — the user said twenty
    /// minutes.
    @Test func aDurationInMinutesIsNotAClockTime() {
        let now = todayAt(9, 15)
        #expect(DeviceActionParsing.detectDue(in: "Remind me to check the oven in 20 minutes",
                                              now: now) == nil)
    }

    /// Same family: "3" would become 03:00.
    @Test func aDurationInHoursIsNotAClockTime() {
        let now = todayAt(9, 15)
        #expect(DeviceActionParsing.detectDue(in: "Remind me to call the vet in 3 hours",
                                              now: now) == nil)
    }

    /// Same family, and the one that shows the hazard is not about durations
    /// at all: any stray small integer in a title has this shape.
    @Test func aStrayIntegerInATitleIsNotAClockTime() {
        let now = todayAt(9, 15)
        #expect(DeviceActionParsing.detectDue(in: "Remind me to call table 4", now: now) == nil)
    }

    /// **An explicit past DATE is honest rather than rolled.** The user named a
    /// day; silently moving it would trade this lane's defect for a worse one.
    /// Only a CLOCK-only phrase — which names no day at all — may roll.
    @Test func anExplicitlyPastDateStaysDateless() {
        let now = todayAt(9, 15)
        let text = "Remind me at \(isoDay(days(-3, from: now)))T09:00 to file the report"
        #expect(DeviceActionParsing.detectDue(in: text, now: now) == nil)
    }

    /// A same-day word whose hour is already behind the clock means TODAY, and
    /// today is gone. Nothing is invented in its place.
    @Test func aSameDayWordAlreadyElapsedStaysDateless() {
        let now = todayAt(22, 0)
        #expect(DeviceActionParsing.detectDue(in: "remind me tonight to take the bins out",
                                              now: now) == nil)
    }

    // MARK: - Two dates in one message (Owen's decision 2: the earliest FUTURE one)

    /// Document order and chronological order coincide here.
    @Test func twoDatesTakeTheEarliestFutureOne() throws {
        let now = todayAt(9, 15)
        let text = "Remind me tomorrow at 4pm and again on \(monthDay(days(2, from: now))) at 9am"
        #expect(DeviceActionParsing.detectDueCandidates(in: text, now: now).count == 2,
                "the row is only a two-date row if the detector saw two dates")
        let due = try #require(DeviceActionParsing.detectDue(in: text, now: now))
        #expect(hourMinute(due) == (16, 0))
        #expect(dayOffset(from: now, to: due) == 1)
    }

    /// **The twin that makes the first row mean something.** The detector
    /// returns matches in DOCUMENT order, so a parser taking `matches.first`
    /// passes the row above and fails this one. Same two dates, written the
    /// other way round; the same answer.
    @Test func twoDatesInReverseDocumentOrderStillTakeTheEarliestFutureOne() throws {
        let now = todayAt(9, 15)
        let text = "Remind me on \(monthDay(days(2, from: now))) at 9am and again tomorrow at 4pm"
        #expect(DeviceActionParsing.detectDueCandidates(in: text, now: now).count == 2,
                "the row is only a two-date row if the detector saw two dates")
        let due = try #require(DeviceActionParsing.detectDue(in: text, now: now))
        #expect(hourMinute(due) == (16, 0))
        #expect(dayOffset(from: now, to: due) == 1)
    }

    /// The candidate list is sorted and strictly future — the property
    /// `detectDue` reduces, stated once rather than re-asserted per row.
    @Test func theCandidateListIsSortedAndStrictlyFuture() {
        let now = todayAt(9, 15)
        let text = "Remind me on \(monthDay(days(2, from: now))) at 9am and again tomorrow at 4pm"
        let candidates = DeviceActionParsing.detectDueCandidates(in: text, now: now)
        #expect(candidates == candidates.sorted())
        #expect(candidates.allSatisfy { $0 > now })
        #expect(candidates.first == DeviceActionParsing.detectDue(in: text, now: now))
    }

    // MARK: - Structural pin: this path is deterministic and stays that way

    /// **No model may enter this file.** `detectDue` exists because the brain
    /// leaves `due` empty; resolving it with another generation would reinstate
    /// the failure it fixes, and would make a unit-testable path
    /// untestable. The pin is structural because the regression it guards
    /// against is a future edit, not a current bug.
    ///
    /// **A positive control is included and is the whole reason to trust the
    /// scan.** A check that has never fired is indistinguishable from a check
    /// that CANNOT fire — the false-green shape of a success marker a no-op
    /// satisfies. `LocalChatBackend+IntentRouting.swift` really does construct
    /// sessions, so if the control ever fails the scan has gone blind and must
    /// be repointed rather than believed.
    ///
    /// Note `@Generable` is deliberately NOT banned: this file declares tool
    /// ARGUMENT schemas, which are a description of the tool's inputs and not
    /// a call into a model.
    @Test(
        .enabled(
            if: repoSourcesAreReadableAtRuntime,
            """
            This bar reads the repo's Swift sources at runtime, so it can only be scored \
            where the test process shares the Mac's filesystem — a simulator. Off-simulator \
            the sources do not exist and the read fails with NSCocoaErrorDomain 260, which \
            measures the sandbox and not the parser.
            """
        )
    )
    func theDeviceActionToolsSourceNeverReachesAModel() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root

        let banned = ["LanguageModelSession", "SystemLanguageModel", ".respond(", "streamResponse("]

        let control = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Talaria/Services/Live/LocalChatBackend+IntentRouting.swift"),
            encoding: .utf8)
        #expect(control.contains("LanguageModelSession"),
                """
                POSITIVE CONTROL FAILED: the scan can no longer find a known model call — \
                repoint it rather than trusting the negative below
                """)

        let subject = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Talaria/Services/Live/DeviceTools/DeviceActionTools.swift"),
            encoding: .utf8)
        for token in banned {
            #expect(!subject.contains(token),
                    """
                    DeviceActionTools.swift now contains \(token) — the #340 due-date path \
                    must stay deterministic
                    """)
        }
    }
}
