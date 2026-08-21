import Foundation
import Testing
@testable import Talaria

/// #29 — the deterministic layer of the action tools: date/duration parsing,
/// edited-field resolution, and the ToolConfirmationCenter gate mechanics.
/// EventKit/AlarmKit writes need permissions + a device and are verified
/// there, behind the same gate these tests pin down.
/// #373 (#224's residual): ONE bounded wait for a staged confirmation card.
///
/// The five call sites in this file each hand-rolled
/// `while center.pending == nil && attempts < 2000 { await Task.yield() }`.
/// That is a BUSY SPIN: 2000 unthrottled yields, measured **3.4 s past its own
/// budget on a loaded box**, five times per run — and today's gate work made
/// the cost of loaded boxes concrete. Worse, its failure mode is silent: the
/// loop simply falls through with `pending == nil`, and the assertion that
/// follows blames the tool for a card that was merely late.
///
/// A real sleep yields the CPU to the very work being waited on instead of
/// competing with it, so this both takes less wall-clock and stops spending a
/// core to do it. The timeout is generous because it is a backstop, not a
/// budget: nothing here should ever approach it, and if something does, the
/// message says the card never arrived rather than leaving a nil to be
/// misread downstream.
@MainActor
extension ToolConfirmationCenter {
    func awaitPendingCard(timeout: Duration = .seconds(5),
                          sourceLocation: SourceLocation = #_sourceLocation) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while pending == nil && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(pending != nil,
                "no confirmation card was staged within \(timeout) — the tool never reached requestConfirmation",
                sourceLocation: sourceLocation)
    }
}

@MainActor
struct DeviceActionToolsTests {

    // MARK: Date parsing

    @Test func parseDateTimeReadsISOAndHumanForms() {
        #expect(DeviceActionParsing.parseDateTime("2026-07-08T09:00") != nil)
        #expect(DeviceActionParsing.parseDateTime("2026-07-08T09:00:00") != nil)
        #expect(DeviceActionParsing.parseDateTime("2026-07-08T09:00:00Z") != nil)
        #expect(DeviceActionParsing.parseDateTime("2026-07-08 09:00") != nil)
        #expect(DeviceActionParsing.parseDateTime("2026-07-08") != nil)
    }

    @Test func parseDateTimeRefusesGarbageInsteadOfGuessing() {
        #expect(DeviceActionParsing.parseDateTime("") == nil)
        #expect(DeviceActionParsing.parseDateTime("tomorrow-ish") == nil)
        #expect(DeviceActionParsing.parseDateTime("99:99") == nil)
    }

    @Test func localWallClockFormMeansLocalTime() {
        let date = DeviceActionParsing.parseDateTime("2026-07-08T09:00")
        let components = Calendar.current.dateComponents([.hour, .minute], from: date!)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
    }

    // MARK: #233 wee-hour window

    @Test func isEarlyMorningCoversMidnightThroughSixFiftyNine() {
        #expect(DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T00:00")!))
        #expect(DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T04:00")!))
        #expect(DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T06:59")!))
        #expect(!DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T07:00")!))
        #expect(!DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T16:00")!))
        #expect(!DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T23:00")!))
    }

    @Test func timeOnlyRendersJustTheClockTime() {
        let four = DeviceActionParsing.parseDateTime("2026-08-05T04:00")!
        let rendered = DeviceActionParsing.timeOnly(four)
        // Locale-safe: no hardcoded "4:00 AM" — assert it is short (no date
        // parts) and that the full display form ends with it.
        #expect(!rendered.isEmpty)
        #expect(rendered.count < 12)
        #expect(DeviceActionParsing.displayDate(four).hasSuffix(rendered))
    }

    // MARK: Duration parsing

    @Test func parseDurationMinutesReadsIntegersAndSuffixes() {
        #expect(DeviceActionParsing.parseDurationMinutes("30") == 30)
        #expect(DeviceActionParsing.parseDurationMinutes("45 min") == 45)
        #expect(DeviceActionParsing.parseDurationMinutes("90m") == 90)
    }

    @Test func parseDurationMinutesClampsAndRefuses() {
        #expect(DeviceActionParsing.parseDurationMinutes("100000") == 24 * 60)
        #expect(DeviceActionParsing.parseDurationMinutes("0") == nil)
        #expect(DeviceActionParsing.parseDurationMinutes("soon") == nil)
    }

    // MARK: Edited-field resolution (edited values are what get created)

    @Test func resolveEditedDateKeepsOriginalWhenDisplayUnchanged() {
        let original = DeviceActionParsing.parseDateTime("2026-07-08T09:00")!
        let display = DeviceActionParsing.displayDate(original)
        #expect(ReminderCreateTool.resolveEditedDate(edited: display, original: original) == original)
    }

    @Test func resolveEditedDateReparsesEditsAndClearsOnNone() {
        let original = DeviceActionParsing.parseDateTime("2026-07-08T09:00")!
        let edited = ReminderCreateTool.resolveEditedDate(edited: "2026-07-09T10:30", original: original)
        #expect(edited != nil)
        #expect(edited != original)
        #expect(ReminderCreateTool.resolveEditedDate(edited: "None", original: original) == nil)
        #expect(ReminderCreateTool.resolveEditedDate(edited: "", original: original) == nil)
        // Unreadable edits resolve nil — the tool then refuses to create.
        #expect(ReminderCreateTool.resolveEditedDate(edited: "whenever", original: original) == nil)
    }

    // MARK: #233 the wee-hour bounce

    /// A local wall-clock due string N days out at the given hour — future
    /// at any suite run time, so `tool.call` wiring tests (which run on the
    /// real clock) cannot rot into the #249 past-due guard the way the old
    /// hardcoded 2026-08-05 dues did.
    private func futureDueString(daysFromNow: Int, hour: Int) -> String {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: daysFromNow, to: Date())!
        let comps = cal.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02dT%02d:00", comps.year!, comps.month!, comps.day!, hour)
    }

    @Test func weeHourDueBouncesOnceThenProceeds() async throws {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor()
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true   // resolves the gate instantly: no card, no EventKit, no hang
        let tool = ReminderCreateTool(relay: relay, confirmations: center)
        relay.beginTurn()
        let due = futureDueString(daysFromNow: 1, hour: 4)

        let first = try await tool.call(arguments: .init(
            title: "Call Shelley", due: due, list: nil))
        // 233-E device falsification (2026-08-03): the model mined the old
        // bounce string's displayDate for a FABRICATED "has been set" claim.
        // The hardened wording leads with the negative and carries NO
        // formatted date — nothing mineable before or after the instruction.
        #expect(first.hasPrefix("No reminder was created"))
        #expect(first.contains("Ask the user whether they meant AM or PM"))
        #expect(first.contains("early morning"))
        #expect(!first.contains(String(due.prefix(4))))   // no mineable date string, any format

        let second = try await tool.call(arguments: .init(
            title: "Call Shelley", due: due, list: nil))
        #expect(second == "The user declined — no reminder was created.")

        // 233-B: both attempts were EXECUTED calls — the bounce is tool
        // output, never a governor refusal, so #232's counter must not move.
        #expect(relay.executedCallsThisTurn == 2)
        #expect(relay.refusalsThisTurn == 0)
    }

    @Test func daytimeDueNeverBounces() async throws {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        let tool = ReminderCreateTool(relay: relay, confirmations: center)
        relay.beginTurn()
        let result = try await tool.call(arguments: .init(
            title: "Call Shelley", due: futureDueString(daysFromNow: 1, hour: 16), list: nil))
        #expect(result == "The user declined — no reminder was created.")
        #expect(relay.claimEarlyMorningAsk())   // latch untouched by a daytime due
    }

    @Test func noDueDateNeverBounces() async throws {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        let tool = ReminderCreateTool(relay: relay, confirmations: center)
        relay.beginTurn()
        let result = try await tool.call(arguments: .init(
            title: "Call Shelley", due: nil, list: nil))
        #expect(result == "The user declined — no reminder was created.")
        #expect(relay.claimEarlyMorningAsk())
    }

    // MARK: #233 the caution row (plumbing)

    @Test func earlyMorningCautionOnlyForWeeHours() {
        let four = DeviceActionParsing.parseDateTime("2026-08-05T04:00")!
        #expect(ReminderCreateTool.earlyMorningCaution(for: four)
            == "EARLY MORNING — \(DeviceActionParsing.timeOnly(four))")
        #expect(ReminderCreateTool.earlyMorningCaution(for: DeviceActionParsing.parseDateTime("2026-08-05T16:00")!) == nil)
        #expect(ReminderCreateTool.earlyMorningCaution(for: nil) == nil)
    }

    @Test func stagedCardCarriesTheCautionThroughTheGate() async {
        let center = ToolConfirmationCenter()
        let task = Task {
            await center.requestConfirmation(
                title: "Create this reminder?",
                caution: "EARLY MORNING — 4:00 AM",
                fields: [.init(key: "title", label: "Title", value: "Call Shelley")])
        }
        await center.awaitPendingCard()
        #expect(center.pending?.caution == "EARLY MORNING — 4:00 AM")
        center.decline()
        _ = await task.value
    }

    /// The re-call path end-to-end: latch already claimed, a wee-hour due
    /// stages a REAL card, and that card carries the caution (233-C).
    @Test func weeHourRecallStagesCardWithCaution() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        _ = relay.claimEarlyMorningAsk()
        // Explicit clock: 1 AM the same day, so the 4 AM due is FUTURE and
        // the #249 past-due guard stays out of this #233 path's way.
        let task = Task {
            await ReminderCreateTool.performCreate(
                rawTitle: "Call Shelley", rawDue: "2026-08-05T04:00", rawList: "",
                relay: relay, confirmations: center,
                now: DeviceActionParsing.parseDateTime("2026-08-05T01:00")!)
        }
        await center.awaitPendingCard()
        #expect(center.pending?.caution != nil)
        center.decline()
        let result = await task.value
        #expect(result == "The user declined — no reminder was created.")
    }

    // MARK: #249 the past-due + evening-clock guards

    @Test func isPastDueHasFiveMinuteGrace() {
        let now = DeviceActionParsing.parseDateTime("2026-08-05T21:00")!
        #expect(!DeviceActionParsing.isPastDue(now.addingTimeInterval(-120), now: now))
        #expect(DeviceActionParsing.isPastDue(now.addingTimeInterval(-360), now: now))
        #expect(!DeviceActionParsing.isPastDue(now.addingTimeInterval(3600), now: now))
    }

    @Test func isNextMorningRequiresEveningAskAndNextMorningDue() {
        let evening = DeviceActionParsing.parseDateTime("2026-08-05T21:30")!
        let afternoon = DeviceActionParsing.parseDateTime("2026-08-05T16:59")!
        let nextMorning = DeviceActionParsing.parseDateTime("2026-08-06T08:00")!
        #expect(DeviceActionParsing.isNextMorning(nextMorning, askedAt: evening))
        // 16:59 is not an evening ask.
        #expect(!DeviceActionParsing.isNextMorning(nextMorning, askedAt: afternoon))
        // Next-day 06:30 is the wee-hour net's, not this ask's.
        #expect(!DeviceActionParsing.isNextMorning(DeviceActionParsing.parseDateTime("2026-08-06T06:30")!, askedAt: evening))
        // Noon next day is not a morning.
        #expect(!DeviceActionParsing.isNextMorning(DeviceActionParsing.parseDateTime("2026-08-06T12:00")!, askedAt: evening))
        // The same evening is not the next morning.
        #expect(!DeviceActionParsing.isNextMorning(DeviceActionParsing.parseDateTime("2026-08-05T23:00")!, askedAt: evening))
        // Two days out is a deliberate date, not a half-day default.
        #expect(!DeviceActionParsing.isNextMorning(DeviceActionParsing.parseDateTime("2026-08-07T08:00")!, askedAt: evening))
    }

    @Test func newLatchesClaimOncePerConversationAndSurviveTurns() {
        let relay = ToolEventRelay()
        #expect(relay.claimPastDueAsk())
        #expect(!relay.claimPastDueAsk())
        #expect(relay.claimEveningClockAsk())
        #expect(!relay.claimEveningClockAsk())
        relay.beginTurn()   // a turn boundary must NOT reset conversation latches
        #expect(!relay.claimPastDueAsk())
        #expect(!relay.claimEveningClockAsk())
        relay.endConversationToolState()
        #expect(relay.claimPastDueAsk())
        #expect(relay.claimEveningClockAsk())
    }

    /// 249-B: Owen's stale cards — today 8:00 AM staged at 9:31 PM. First
    /// call is a question; the latched re-call proceeds to the gate. (The
    /// #232 executed-not-refused counter contract is pinned by the wee-hour
    /// tool.call test; these drive performCreate directly to inject the
    /// clock, which never touches the counters.)
    @Test func pastDueBouncesOnceThenProceeds() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        let now = DeviceActionParsing.parseDateTime("2026-08-04T21:31")!

        let first = await ReminderCreateTool.performCreate(
            rawTitle: "Call Shelley", rawDue: "2026-08-04T08:00", rawList: "",
            relay: relay, confirmations: center, now: now)
        #expect(first.hasPrefix("No reminder was created"))
        #expect(first.contains("already passed"))
        // #256 sharpening (249-E residue): steer the model toward the
        // nearest FUTURE reading of the same clock hour instead of the
        // open-ended "what future time" — "8" asked at 6:59 PM should come
        // back offering tonight.
        #expect(first.contains("next time that clock time comes around"))
        #expect(first.contains("later today or tomorrow"))
        #expect(!first.contains("2026"))   // 233-E: nothing mineable

        let second = await ReminderCreateTool.performCreate(
            rawTitle: "Call Shelley", rawDue: "2026-08-04T08:00", rawList: "",
            relay: relay, confirmations: center, now: now)
        #expect(second == "The user declined — no reminder was created.")
    }

    /// 249-A: Owen's exact shape — "at 8" asked 9:30 PM arrived as tomorrow
    /// 08:00. First call is a question, not an order.
    @Test func eveningNextMorningDueBouncesOnceThenProceeds() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        let now = DeviceActionParsing.parseDateTime("2026-08-05T21:30")!

        let first = await ReminderCreateTool.performCreate(
            rawTitle: "Call Shelley", rawDue: "2026-08-06T08:00", rawList: "",
            relay: relay, confirmations: center, now: now)
        #expect(first.hasPrefix("No reminder was created"))
        // 249F-A (2026-08-06): the 9:02 PM live firing showed the model
        // mining "the due time landed the next morning" into a fabricated
        // "was set for the next morning". The sharpened text hands the
        // model a VERBATIM quoted question to parrot (#200J) whose
        // negative requires word-deletion to flip, and carries no
        // set/landed phrasing outside the quote.
        #expect(first.contains("exactly this question"))
        #expect(first.contains("\"Nothing is scheduled yet — did you mean tonight or tomorrow morning?\""))
        #expect(!first.contains("was set"))
        #expect(!first.contains("landed"))
        #expect(!first.contains("2026"))   // 233-E: nothing mineable

        let second = await ReminderCreateTool.performCreate(
            rawTitle: "Call Shelley", rawDue: "2026-08-06T08:00", rawList: "",
            relay: relay, confirmations: center, now: now)
        #expect(second == "The user declined — no reminder was created.")
    }

    /// 249-B caution half: latch spent, the staged card carries IN THE PAST
    /// with the full date — the stale due may be yesterday's.
    @Test func pastDueRecallStagesCardWithInThePastCaution() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        _ = relay.claimPastDueAsk()
        let now = DeviceActionParsing.parseDateTime("2026-08-04T21:31")!
        let due = DeviceActionParsing.parseDateTime("2026-08-04T08:00")!
        let task = Task {
            await ReminderCreateTool.performCreate(
                rawTitle: "Call Shelley", rawDue: "2026-08-04T08:00", rawList: "",
                relay: relay, confirmations: center, now: now)
        }
        await center.awaitPendingCard()
        #expect(center.pending?.caution == "IN THE PAST — \(DeviceActionParsing.displayDate(due))")
        center.decline()
        _ = await task.value
    }

    /// 249-A caution half: latch spent, the staged card carries NEXT MORNING.
    @Test func eveningClockRecallStagesCardWithNextMorningCaution() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        _ = relay.claimEveningClockAsk()
        let now = DeviceActionParsing.parseDateTime("2026-08-05T21:30")!
        let due = DeviceActionParsing.parseDateTime("2026-08-06T08:00")!
        let task = Task {
            await ReminderCreateTool.performCreate(
                rawTitle: "Call Shelley", rawDue: "2026-08-06T08:00", rawList: "",
                relay: relay, confirmations: center, now: now)
        }
        await center.awaitPendingCard()
        #expect(center.pending?.caution == "NEXT MORNING — \(DeviceActionParsing.timeOnly(due))")
        center.decline()
        _ = await task.value
    }

    /// 249-C ordering pin: a due both past AND wee-hour gets the past-due
    /// ask — a stale wee-hour due is first a stale due.
    @Test func pastWeeHourDueGetsThePastDueAskFirst() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        let now = DeviceActionParsing.parseDateTime("2026-08-05T21:00")!
        let first = await ReminderCreateTool.performCreate(
            rawTitle: "Call Shelley", rawDue: "2026-08-05T04:00", rawList: "",
            relay: relay, confirmations: center, now: now)
        #expect(first.contains("already passed"))
        #expect(!first.contains("AM or PM"))
    }

    /// 249-C: ordinary future dues stage byte-identically — no bounce, nil
    /// caution, and neither new latch consumed on the way through.
    @Test func ordinaryFutureDueStagesWithNoCaution() async {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        let now = DeviceActionParsing.parseDateTime("2026-08-05T21:30")!
        let task = Task {
            await ReminderCreateTool.performCreate(
                rawTitle: "Call Shelley", rawDue: "2026-08-06T16:00", rawList: "",
                relay: relay, confirmations: center, now: now)
        }
        await center.awaitPendingCard()
        #expect(center.pending?.caution == nil)
        #expect(relay.claimPastDueAsk())        // untouched
        #expect(relay.claimEveningClockAsk())   // untouched
        center.decline()
        _ = await task.value
    }

    /// The caution row picks past-due over wee-hour over next-morning, and
    /// stays nil for ordinary dues (and for a next-day WEE-hour due on the
    /// evening path — that one is still #233's).
    @Test func dueCautionPicksPastThenWeeThenNextMorning() {
        let now = DeviceActionParsing.parseDateTime("2026-08-05T21:30")!
        let past = DeviceActionParsing.parseDateTime("2026-08-04T08:00")!
        #expect(ReminderCreateTool.dueCaution(for: past, now: now)
            == "IN THE PAST — \(DeviceActionParsing.displayDate(past))")
        let wee = DeviceActionParsing.parseDateTime("2026-08-06T04:00")!
        #expect(ReminderCreateTool.dueCaution(for: wee, now: now)
            == "EARLY MORNING — \(DeviceActionParsing.timeOnly(wee))")
        let nextMorning = DeviceActionParsing.parseDateTime("2026-08-06T08:00")!
        #expect(ReminderCreateTool.dueCaution(for: nextMorning, now: now)
            == "NEXT MORNING — \(DeviceActionParsing.timeOnly(nextMorning))")
        let ordinary = DeviceActionParsing.parseDateTime("2026-08-06T16:00")!
        #expect(ReminderCreateTool.dueCaution(for: ordinary, now: now) == nil)
        #expect(ReminderCreateTool.dueCaution(for: nil, now: now) == nil)
    }

    // MARK: ToolConfirmationCenter gate mechanics

    @Test func approveResolvesWithCurrentFieldValuesIncludingEdits() async {
        let center = ToolConfirmationCenter()
        async let decision = center.requestConfirmation(
            title: "Create this reminder?",
            fields: [
                .init(key: "title", label: "Title", value: "Call Shelley"),
                .init(key: "due", label: "Due", value: "Jul 8, 2026 at 9:00 AM"),
            ]
        )
        // Let the request suspend and stage the card.
        while center.pending == nil { await Task.yield() }

        // Edit a field in place, then approve — the edit must be delivered.
        let titleField = center.pending!.fields.first { $0.key == "title" }!
        center.updateField(id: titleField.id, value: "Call Shelley re: birthday")
        center.approve()

        let resolved = await decision
        guard case .approved(let values) = resolved else {
            Issue.record("expected approval")
            return
        }
        #expect(values["title"] == "Call Shelley re: birthday")
        #expect(values["due"] == "Jul 8, 2026 at 9:00 AM")
        #expect(center.pending == nil)
    }

    @Test func declineResolvesDeclinedAndClearsTheCard() async {
        let center = ToolConfirmationCenter()
        async let decision = center.requestConfirmation(
            title: "Schedule on this iPhone?",
            fields: [.init(key: "request", label: "Alarm", value: "6:30am")]
        )
        while center.pending == nil { await Task.yield() }
        center.decline()
        let resolved = await decision
        guard case .declined = resolved else {
            Issue.record("expected decline")
            return
        }
        #expect(center.pending == nil)
    }

    @Test func secondConcurrentRequestAutoDeclines() async {
        let center = ToolConfirmationCenter()
        async let first = center.requestConfirmation(
            title: "First?",
            fields: [.init(key: "a", label: "A", value: "1")]
        )
        while center.pending == nil { await Task.yield() }

        // The gate never queues silently — a second request declines at once
        // and the first card stays staged.
        let second = await center.requestConfirmation(
            title: "Second?",
            fields: [.init(key: "b", label: "B", value: "2")]
        )
        guard case .declined = second else {
            Issue.record("expected the second request to auto-decline")
            return
        }
        #expect(center.pending?.title == "First?")

        center.approve()
        _ = await first
    }

    // MARK: Battery auto-modes (#196 decline / #200 accept)

    @Test func batteryAutoDeclineResolvesDeclinedWithoutStagingACard() async {
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        let decision = await center.requestConfirmation(
            title: "Create this reminder?",
            fields: [.init(key: "title", label: "Title", value: "test Talaria")]
        )
        guard case .declined = decision else {
            Issue.record("expected auto-decline")
            return
        }
        #expect(center.pending == nil)
    }

    @Test func batteryAutoAcceptApprovesStagedValuesWithoutStagingACard() async {
        let center = ToolConfirmationCenter()
        center.autoAcceptForBattery = true
        let decision = await center.requestConfirmation(
            title: "Create this reminder?",
            fields: [
                .init(key: "title", label: "Title", value: "test Talaria"),
                .init(key: "due", label: "Due", value: "Jul 28, 2026 at 4:30 PM"),
                .init(key: "list", label: "List", value: ""),
            ]
        )
        guard case .approved(let values) = decision else {
            Issue.record("expected auto-accept")
            return
        }
        // Non-title fields pass through UNCHANGED — the tool must create
        // exactly what was staged, and the card is never rendered.
        #expect(values["due"] == "Jul 28, 2026 at 4:30 PM")
        #expect(values["list"] == "")
        #expect(center.pending == nil)
    }

    /// Every battery-created artifact must be reapable: titles carry the
    /// marker as a PREFIX; the alarm request carries it as a SUFFIX (the
    /// alarm grammar needs its time token first, and everything after the
    /// time is the label — so the marker lands in the alarm's label).
    @Test func batteryAutoAcceptTagsTitlesAndAlarmRequestsWithTheMarker() async {
        #expect(ToolConfirmationCenter.batteryArtifactMarker == "[T27-battery]")

        let center = ToolConfirmationCenter()
        center.autoAcceptForBattery = true

        let reminder = await center.requestConfirmation(
            title: "Create this reminder?",
            fields: [.init(key: "title", label: "Title", value: "test Talaria")]
        )
        guard case .approved(let reminderValues) = reminder else {
            Issue.record("expected auto-accept")
            return
        }
        #expect(reminderValues["title"] == "[T27-battery] test Talaria")

        let alarm = await center.requestConfirmation(
            title: "Schedule on this iPhone?",
            fields: [.init(key: "request", label: "Alarm", value: "6:30")]
        )
        guard case .approved(let alarmValues) = alarm else {
            Issue.record("expected auto-accept")
            return
        }
        #expect(alarmValues["request"] == "6:30 [T27-battery]")
        // The tagged request still parses through the alarm grammar, with
        // the marker as the label — reap-visible if it ever survives.
        let parsed = AlarmService.parse(alarmValues["request"] ?? "")
        #expect(parsed != nil)
        #expect(parsed?.label == "[T27-battery]")
    }

    // MARK: Unmarked-title echo (#200F)

    /// #200E leak: armed/haiku/t5's REPLY carried "[T27-battery] ," —
    /// the tool success text echoed the FINAL (marked) title back into
    /// the model's context. The marker rides only the store write; every
    /// echoed value is cleaned through this helper first. All three
    /// injection shapes strip; clean values pass through untouched.
    @Test func strippingBatteryMarkerRemovesEveryInjectionForm() {
        let strip = ToolConfirmationCenter.strippingBatteryMarker
        // The title injection form (prefix)…
        #expect(strip("[T27-battery] Call Shelley") == "Call Shelley")
        // …the alarm-request form (suffix)…
        #expect(strip("6:30 [T27-battery]") == "6:30")
        // …and mid-string, where the alarm SUMMARY embeds the marked label.
        #expect(strip("alarm “tea [T27-battery]” for 6:30 AM") == "alarm “tea” for 6:30 AM")
        // Identity on clean values — normal-mode echoes are untouched.
        #expect(strip("Call Shelley") == "Call Shelley")
        #expect(strip("") == "")
    }

    /// Roundtrip against the gate's REAL injection: whatever auto-accept
    /// marks, the echo cleaner recovers byte-for-byte — both keys.
    @Test func strippingBatteryMarkerInvertsTheAutoAcceptInjection() async {
        let center = ToolConfirmationCenter()
        center.autoAcceptForBattery = true

        let reminder = await center.requestConfirmation(
            title: "Create this reminder?",
            fields: [.init(key: "title", label: "Title", value: "test Talaria")]
        )
        guard case .approved(let reminderValues) = reminder else {
            Issue.record("expected auto-accept")
            return
        }
        #expect(ToolConfirmationCenter.strippingBatteryMarker(reminderValues["title"] ?? "") == "test Talaria")

        let alarm = await center.requestConfirmation(
            title: "Schedule on this iPhone?",
            fields: [.init(key: "request", label: "Alarm", value: "6:30")]
        )
        guard case .approved(let alarmValues) = alarm else {
            Issue.record("expected auto-accept")
            return
        }
        let cleaned = ToolConfirmationCenter.strippingBatteryMarker(alarmValues["request"] ?? "")
        #expect(cleaned == "6:30")
        // The alarm echo re-parses the CLEANED raw — recovering the
        // model-requested form exactly: no label here, so the echoed
        // summary reads "alarm for 6:30 AM", never a marker in quotes.
        let display = AlarmService.parse(cleaned)
        #expect(display != nil)
        #expect(display?.label == nil)
    }

    /// The two auto-modes are mutually exclusive by launcher discipline;
    /// if both are ever set, DECLINE wins — the fail-safe direction is
    /// never-create, matching the gate's default-closed design.
    @Test func batteryAutoDeclineWinsWhenBothFlagsAreSet() async {
        let center = ToolConfirmationCenter()
        center.autoDeclineForBattery = true
        center.autoAcceptForBattery = true
        let decision = await center.requestConfirmation(
            title: "Create this reminder?",
            fields: [.init(key: "title", label: "Title", value: "test Talaria")]
        )
        guard case .declined = decision else {
            Issue.record("expected decline to win over accept")
            return
        }
    }
}
