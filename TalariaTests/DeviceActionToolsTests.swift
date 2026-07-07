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
}
