import Foundation
import Testing
@testable import Talaria

/// #29 — the deterministic layer of the action tools: date/duration parsing,
/// edited-field resolution, and the ToolConfirmationCenter gate mechanics.
/// EventKit/AlarmKit writes need permissions + a device and are verified
/// there, behind the same gate these tests pin down.
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
