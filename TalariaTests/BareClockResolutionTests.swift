import Foundation
import Testing
@testable import Talaria

/// **#340 route (a) — the app owns the DAY, the model owns the TIME.**
/// Bars 340-H1..H3.
///
/// Two prose candidates died before this one. 340-F put the rule in the
/// instructions layer and got **zero** due dates; 340-G put it in the `@Guide`
/// and got values that were **all already elapsed** — the model took the
/// guide's first clause and dropped *"or tomorrow's if that time has already
/// passed today."* Fifteen calls across both lanes produced exactly ONE
/// correct due date.
///
/// The conclusion those two runs earned is narrow and load-bearing: **the
/// model can produce the time and cannot produce the day.** So this lane stops
/// asking it to. Everything below is the day-arithmetic half, which is
/// deterministic, and therefore testable in a way neither predecessor was.
///
/// **Every test pins `now`.** 340-G's own instrument flaw was a fixed
/// *"at 4:30pm"* prompt that scores CORRECT before 16:30 local and
/// ALREADY-PAST after — the two lanes ran in different windows and are not
/// comparable on that bucket. A wall-clock-dependent test here would rot the
/// same way, silently, at 16:30 every day.
struct BareClockResolutionTests {

    private func at(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = .current
        return formatter.date(from: iso)!
    }

    private func parts(_ date: Date) -> (day: Int, hour: Int, minute: Int) {
        let c = Calendar.current.dateComponents([.day, .hour, .minute], from: date)
        return (c.day!, c.hour!, c.minute!)
    }

    // MARK: - 340-H1: the resolution, both branches, against a pinned `now`

    @Test func aBareTimeStillAheadResolvesToToday() throws {
        let clock = try #require(DeviceActionParsing.parseBareClock("16:30"))
        let resolved = try #require(
            DeviceActionParsing.resolveBareClock(clock, now: at("2026-08-21T09:00")))
        #expect(parts(resolved) == (21, 16, 30))
    }

    /// The branch 340-G proved the model cannot do. Asked at 18:21 for
    /// "4:30pm", the answer is TOMORROW's 16:30 — production's own past-due
    /// bounce text already says so in prose (*"the next time that clock time
    /// comes around"*); this is that sentence as code.
    @Test func aBareTimeAlreadyPassedResolvesToTomorrow() throws {
        let clock = try #require(DeviceActionParsing.parseBareClock("4:30pm"))
        let resolved = try #require(
            DeviceActionParsing.resolveBareClock(clock, now: at("2026-08-21T18:21")))
        #expect(parts(resolved) == (22, 16, 30))
    }

    /// The grace is `isPastDue`'s, shared rather than restated — two
    /// thresholds would let the app resolve a time its own guard then bounces,
    /// which is a loop wearing the shape of a fix. Four minutes ago is inside
    /// the five-minute grace, so it is still TODAY.
    @Test func theGraceWindowIsTheSameOneThePastDueGuardUses() throws {
        let clock = try #require(DeviceActionParsing.parseBareClock("09:00"))
        let resolved = try #require(
            DeviceActionParsing.resolveBareClock(clock, now: at("2026-08-21T09:04")))
        #expect(parts(resolved).day == 21, "inside isPastDue's grace, so today")

        let past = try #require(
            DeviceActionParsing.resolveBareClock(clock, now: at("2026-08-21T09:30")))
        #expect(parts(past).day == 22, "outside the grace, so tomorrow")
    }

    @Test(arguments: [
        ("16:30", 16, 30), ("9am", 9, 0), ("9 AM", 9, 0), ("4:30pm", 16, 30),
        ("11", 11, 0), ("0:15", 0, 15), ("23:59", 23, 59),
        ("12am", 0, 0), ("12pm", 12, 0), ("12:30am", 0, 30), ("7a.m.", 7, 0),
    ])
    func recognisedClockForms(_ raw: String, _ hour: Int, _ minute: Int) throws {
        let clock = try #require(DeviceActionParsing.parseBareClock(raw), "\(raw) should parse")
        #expect(clock.hour == hour && clock.minute == minute, "\(raw)")
    }

    /// Deliberately strict. A four-digit run is as easily a typo as a time,
    /// and this function's output goes straight into a reminder the user was
    /// told about — so the rejected cases are rejected, never guessed at.
    @Test(arguments: ["", "  ", "1630", "0930", "sometime", "later", "25", "24:00",
                      "9:5", "9:605", "-1", "13pm", "0am", "noon", "half four"])
    func rejectedForms(_ raw: String) {
        #expect(DeviceActionParsing.parseBareClock(raw) == nil, "\(raw) must not parse")
    }

    // MARK: - 340-H2: an explicit DATE is never rolled

    /// 🔴 **The bar that keeps this fix from becoming a worse defect.**
    ///
    /// A date the model or the user supplied is theirs to own. Silently
    /// rolling an explicit past date forward would mean the user asked for a
    /// date and got a different one — and #249's past-due guard exists to ASK
    /// about exactly that case rather than guess at it. `parseBareClock` must
    /// therefore refuse anything carrying a date, however clock-like its tail.
    @Test(arguments: ["2026-08-15T16:30", "2026-08-15 16:30", "2026-08-15",
                      "2026-08-15T16:30:00", "08/15 16:30"])
    func anythingCarryingADateIsNotABareClock(_ raw: String) {
        #expect(DeviceActionParsing.parseBareClock(raw) == nil,
                "\(raw) carries a date and must stay parseDateTime's (340-H2)")
    }

    /// The positive half of the same bar: those forms still parse as dates,
    /// so route (a) took nothing away.
    @Test func explicitDatesStillParseAsDatesAndKeepTheirDay() throws {
        let explicit = try #require(DeviceActionParsing.parseDateTime("2026-08-15T16:30"))
        #expect(parts(explicit) == (15, 16, 30))
    }

    // MARK: - 340-H3: nil still means nil

    /// **This is the bar that keeps the fix out of #180's family.** Route (a)
    /// resolves a time the model SENT; it does not license inventing one it
    /// did not. A reminder the app dated by itself, reported to the user as
    /// their time, is the founding defect wearing our logic instead of the
    /// model's.
    @Test func anEmptyOrUnreadableDueStillProducesNoDate() {
        #expect(DeviceActionParsing.parseBareClock("") == nil)
        #expect(DeviceActionParsing.parseDateTime("") == nil)
        #expect(ReminderCreateTool.resolveEditedDate(edited: "", original: nil) == nil)
        #expect(DeviceActionParsing.parseBareClock("whenever") == nil)
    }

    // MARK: - The card-edit path — a live defect independent of the model

    /// The Due field is user-editable, and typing the most natural thing into
    /// a field labelled Due — a plain clock time — was answered with
    /// *"Couldn't read \"18:00\" as a date."* Unlike the tool path, this half
    /// needs no model behaviour to change.
    @Test func aBareClockTypedIntoTheCardNowResolves() throws {
        let resolved = try #require(
            ReminderCreateTool.resolveEditedDate(edited: "18:00", original: nil,
                                                  now: at("2026-08-21T09:00")))
        #expect(parts(resolved) == (21, 18, 0))
    }

    /// Order matters, and 340-H2 applies to people as well as models: an
    /// explicit date typed into the card keeps its day.
    @Test func anExplicitDateTypedIntoTheCardKeepsItsDay() throws {
        let resolved = try #require(
            ReminderCreateTool.resolveEditedDate(edited: "2026-08-15T16:30", original: nil,
                                                  now: at("2026-08-21T09:00")))
        #expect(parts(resolved) == (15, 16, 30))
    }

    /// The untouched contract: an unchanged display string round-trips to the
    /// ORIGINAL date, never through the parser. A card the user did not edit
    /// must not be re-resolved against a newer clock.
    @Test func anUnEditedCardValueRoundTripsToTheOriginalDate() throws {
        let original = at("2026-08-15T16:30")
        let resolved = try #require(
            ReminderCreateTool.resolveEditedDate(
                edited: DeviceActionParsing.displayDate(original), original: original,
                now: at("2026-08-21T09:00")))
        #expect(resolved == original)
    }
}

/// 🔴 **The WIRING, which the suite above cannot see.**
///
/// Every test in `BareClockResolutionTests` calls `parseBareClock` /
/// `resolveBareClock` directly. All of them stay green if someone deletes the
/// three lines in `performCreate` that actually USE them — the production
/// path would go straight back to staging an empty DUE and the bars would
/// report success. That is this project's recorded shape for a test written
/// after a defect: pinned to text the fix did not touch.
///
/// So these drive `performCreate` end-to-end, with `now` pinned, and assert on
/// **the card the user would actually see** — which is where #340's founding
/// observation was made (TITLE set, **DUE EMPTY**, approved, and a reply
/// claiming *"set for 11"*).
@MainActor
struct BareClockWiringTests {

    private func at(_ iso: String) -> Date {
        DeviceActionParsing.parseDateTime(iso)!
    }

    /// Stages the card, reads the DUE field, declines. Declining is what the
    /// #340 due-date battery does for the same reason: the argument is on the
    /// record before the confirmation gate, so nothing needs to be created and
    /// no EventKit permission is involved.
    private func stagedDue(rawDue: String, now: Date) async -> String? {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        let task = Task {
            await ReminderCreateTool.performCreate(
                rawTitle: "Empty the dishwasher", rawDue: rawDue, rawList: "",
                relay: relay, confirmations: center, now: now)
        }
        var attempts = 0
        while center.pending == nil && attempts < 2000 { await Task.yield(); attempts += 1 }
        let due = center.pending?.fields.first { $0.key == "due" }?.value
        center.decline()
        _ = await task.value
        return due
    }

    /// **The founding defect, inverted.** *"Remind me to empty the dishwasher
    /// at 11"* produced a card reading DUE EMPTY, and a reminder that could
    /// never fire. A bare `"11"` must now reach the card as a real instant.
    @Test func aBareClockReachesTheCardAsARealDueDate() async {
        let due = await stagedDue(rawDue: "11", now: at("2026-08-21T09:00"))
        #expect(due?.isEmpty == false,
                "DUE came through EMPTY — this is #340's founding observation, unfixed")
        #expect(due?.contains("11:00") == true, "expected today's 11:00, got \(due ?? "nil")")
    }

    /// The branch 340-G proved the model cannot do, now measured through
    /// production rather than through the parser.
    @Test func aBareClockAlreadyPassedReachesTheCardAsTomorrow() async {
        let now = at("2026-08-21T18:21")
        let due = await stagedDue(rawDue: "4:30pm", now: now)
        let expected = DeviceActionParsing.displayDate(
            DeviceActionParsing.resolveBareClock(
                DeviceActionParsing.parseBareClock("4:30pm")!, now: now)!)
        #expect(due == expected, "expected tomorrow's 4:30 PM, got \(due ?? "nil")")
    }

    /// **340-H3 through the wiring.** An omitted due still stages an EMPTY
    /// card — route (a) resolves a time the model SENT and never invents one.
    /// Without this, a later "helpful" edit could default the field and the
    /// suite would applaud.
    @Test func anOmittedDueStillStagesAnEmptyCard() async {
        let due = await stagedDue(rawDue: "", now: at("2026-08-21T09:00"))
        #expect(due?.isEmpty == true,
                "the app invented a due date the model never sent — that is #180's family")
    }

    /// **340-H2 through the wiring, and it must reach a GUARD, not the card.**
    /// An explicit past date is #249's business: the tool returns its bounce
    /// text and stages nothing at all. If route (a) ever started rolling
    /// explicit dates forward, this would stage a card instead.
    @Test func anExplicitPastDateStillBouncesToTheGuardRatherThanRolling() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        let result = await ReminderCreateTool.performCreate(
            rawTitle: "Empty the dishwasher", rawDue: "2026-08-15T16:30", rawList: "",
            relay: relay, confirmations: center,
            now: at("2026-08-21T18:21"))
        #expect(center.pending == nil, "an explicit past date must not stage a card")
        #expect(result.contains("already passed"),
                "expected #249's past-due bounce, got: \(result)")
    }
}
