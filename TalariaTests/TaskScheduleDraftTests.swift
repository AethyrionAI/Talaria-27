import Foundation
import Testing
@testable import Talaria

/// #156a D4/D6 — schedule-string emission for every preset (table-driven —
/// the highest-value test in the lane: these strings ARE the contract with
/// `parse_schedule`), plus draft validation gating and PATCH diffing.
struct TaskScheduleDraftTests {

    // MARK: - Emission tables

    @Test(arguments: [
        (1, ScheduleDraft.IntervalUnit.minutes, "every 1m"),
        (30, .minutes, "every 30m"),
        (2, .hours, "every 2h"),
        (12, .hours, "every 12h"),
        (1, .days, "every 1d"),
        (7, .days, "every 7d"),
    ] as [(Int, ScheduleDraft.IntervalUnit, String)])
    func intervalEmission(value: Int, unit: ScheduleDraft.IntervalUnit, expected: String) {
        var draft = ScheduleDraft()
        draft.mode = .interval
        draft.intervalValue = value
        draft.intervalUnit = unit
        #expect(draft.emittedString() == expected)
    }

    @Test(arguments: [
        (9, 0, "0 9 * * *"),
        (0, 0, "0 0 * * *"),
        (23, 59, "59 23 * * *"),
        (7, 5, "5 7 * * *"),
    ] as [(Int, Int, String)])
    func dailyEmission(hour: Int, minute: Int, expected: String) {
        var draft = ScheduleDraft()
        draft.mode = .daily
        draft.hour = hour
        draft.minute = minute
        #expect(draft.emittedString() == expected)
    }

    @Test(arguments: [
        (ScheduleDraft.Weekday.sunday, 9, 0, "0 9 * * 0"),
        (.monday, 9, 30, "30 9 * * 1"),
        (.wednesday, 18, 15, "15 18 * * 3"),
        (.saturday, 6, 0, "0 6 * * 6"),
    ] as [(ScheduleDraft.Weekday, Int, Int, String)])
    func weeklyEmission(weekday: ScheduleDraft.Weekday, hour: Int, minute: Int, expected: String) {
        var draft = ScheduleDraft()
        draft.mode = .weekly
        draft.weekday = weekday
        draft.hour = hour
        draft.minute = minute
        #expect(draft.emittedString() == expected)
    }

    @Test(arguments: [
        (45, ScheduleDraft.IntervalUnit.minutes, "45m"),
        (2, .hours, "2h"),
        (1, .days, "1d"),
    ] as [(Int, ScheduleDraft.IntervalUnit, String)])
    func onceRelativeEmission(value: Int, unit: ScheduleDraft.IntervalUnit, expected: String) {
        var draft = ScheduleDraft()
        draft.mode = .once
        draft.onceIsRelative = true
        draft.intervalValue = value
        draft.intervalUnit = unit
        #expect(draft.emittedString() == expected)
    }

    /// The absolute one-shot embeds THIS device's UTC offset so
    /// `fromisoformat` stores the exact instant the phone displayed — no
    /// host-timezone reinterpretation (the #51021 footgun sidestepped).
    @Test func onceAbsoluteEmissionCarriesOffsetAndRoundTrips() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var draft = ScheduleDraft()
        draft.mode = .once
        draft.onceIsRelative = false
        let date = Date(timeIntervalSince1970: 1_770_000_000)
        draft.onceDate = date

        let unwrapped = try #require(draft.emittedString(calendar: calendar))

        // Shape: full ISO with an explicit numeric offset (New York is
        // never Z).
        #expect(unwrapped.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}/) != nil)
        // Round-trip: the emitted string parses back to the same instant.
        #expect(CronDateParsing.instant(from: unwrapped) == date)
    }

    @Test func advancedEmissionIsTrimmedVerbatim() {
        var draft = ScheduleDraft()
        draft.mode = .advanced
        draft.advancedText = "  */5 9-17 * * 1-5  "
        #expect(draft.emittedString() == "*/5 9-17 * * 1-5")
    }

    // MARK: - Emission gating (non-empty, exactly hermex's posture)

    @Test func emptyAdvancedEmitsNil() {
        var draft = ScheduleDraft()
        draft.mode = .advanced
        draft.advancedText = "   "
        #expect(draft.emittedString() == nil)
    }

    @Test func nonPositiveIntervalEmitsNil() {
        var draft = ScheduleDraft()
        draft.mode = .interval
        draft.intervalValue = 0
        #expect(draft.emittedString() == nil)
    }

    // MARK: - Preview rule

    @Test func presetPreviewsAreHumanizedFromInputs() {
        var interval = ScheduleDraft()
        interval.mode = .interval
        interval.intervalValue = 30
        interval.intervalUnit = .minutes
        #expect(interval.localizedPreview == "Every 30 minutes")

        var single = ScheduleDraft()
        single.mode = .interval
        single.intervalValue = 1
        single.intervalUnit = .hours
        #expect(single.localizedPreview == "Every 1 hour")

        var daily = ScheduleDraft()
        daily.mode = .daily
        daily.hour = 9
        daily.minute = 0
        let dailyPreview = daily.localizedPreview
        #expect(dailyPreview?.hasPrefix("Every day at ") == true)
        #expect(dailyPreview?.hasSuffix("(host time)") == true)

        var weekly = ScheduleDraft()
        weekly.mode = .weekly
        weekly.weekday = .friday
        let weeklyPreview = weekly.localizedPreview
        #expect(weeklyPreview?.hasPrefix("Every Friday at ") == true)
        #expect(weeklyPreview?.hasSuffix("(host time)") == true)
    }

    /// Advanced gets NO local preview — no client-side cron parser, ever.
    /// The server's schedule_display is the authority after save.
    @Test func advancedHasNoLocalPreview() {
        var draft = ScheduleDraft()
        draft.mode = .advanced
        draft.advancedText = "0 9 * * *"
        #expect(draft.localizedPreview == nil)
    }

    /// The host-clock caveat shows exactly where absolute times evaluate on
    /// the host: daily/weekly (cron) and advanced. Intervals and one-shots
    /// don't need it.
    @Test func hostClockFlag() {
        var draft = ScheduleDraft()
        draft.mode = .daily
        #expect(draft.usesHostClock)
        draft.mode = .weekly
        #expect(draft.usesHostClock)
        draft.mode = .advanced
        #expect(draft.usesHostClock)
        draft.mode = .interval
        #expect(!draft.usesHostClock)
        draft.mode = .once
        #expect(!draft.usesHostClock)
    }

    // MARK: - Hydration from an existing job (edit flow)

    private func job(_ json: String) throws -> CronJob {
        try JSONDecoder().decode(CronJob.self, from: Data(json.utf8))
    }

    @Test func intervalHydration() throws {
        let ninety = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "interval", "minutes": 90}}"#
        ))
        #expect(ninety.mode == .interval)
        #expect(ninety.intervalValue == 90)
        #expect(ninety.intervalUnit == .minutes)

        let twoHours = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "interval", "minutes": 120}}"#
        ))
        #expect(twoHours.intervalValue == 2)
        #expect(twoHours.intervalUnit == .hours)

        let daily = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "interval", "minutes": 1440}}"#
        ))
        #expect(daily.intervalValue == 1)
        #expect(daily.intervalUnit == .days)
    }

    @Test func presetCronHydration() throws {
        let daily = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "cron", "expr": "30 7 * * *"}}"#
        ))
        #expect(daily.mode == .daily)
        #expect(daily.hour == 7)
        #expect(daily.minute == 30)

        let weekly = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "cron", "expr": "0 9 * * 1"}}"#
        ))
        #expect(weekly.mode == .weekly)
        #expect(weekly.weekday == .monday)
    }

    /// A cron the presets can't express lands in Advanced with the server's
    /// own text — editing never silently rewrites what the picker doesn't
    /// understand.
    @Test func complexCronHydratesToAdvanced() throws {
        let draft = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "cron", "expr": "*/5 9-17 * * 1-5"}}"#
        ))
        #expect(draft.mode == .advanced)
        #expect(draft.advancedText == "*/5 9-17 * * 1-5")
    }

    @Test func onceWithOffsetHydratesToAbsolute() throws {
        let draft = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "once", "run_at": "2026-08-01T09:00:00+00:00"}}"#
        ))
        #expect(draft.mode == .once)
        #expect(!draft.onceIsRelative)
        #expect(draft.onceDate == CronDateParsing.instant(from: "2026-08-01T09:00:00+00:00"))
    }

    @Test func naiveOnceHydratesToAdvanced() throws {
        // A naive run_at can't be represented in the device date picker
        // honestly — Advanced keeps the raw truth… via the schedule text.
        let draft = ScheduleDraft.from(job: try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "once", "run_at": "2026-08-01T09:00:00", "display": "once at 2026-08-01 09:00"}}"#
        ))
        #expect(draft.mode == .advanced)
        // The raw run_at (valid grammar), not the human display text.
        #expect(draft.advancedText == "2026-08-01T09:00:00")
    }

    @Test func hydratedDraftEqualsItsOwnRehydration() throws {
        // The patch diff keys off this: untouched draft == from(job:) means
        // no schedule in the PATCH.
        let record = try job(
            #"{"id": "aaa111aaa111", "schedule": {"kind": "cron", "expr": "0 9 * * *"}}"#
        )
        #expect(ScheduleDraft.from(job: record) == ScheduleDraft.from(job: record))
    }

    // MARK: - CronJobDraft gating + wire bodies

    @Test func draftGatesOnNameAndSchedule() {
        var draft = CronJobDraft()
        #expect(!draft.isSubmittable) // no name
        draft.name = "Brief"
        #expect(draft.isSubmittable) // default interval schedule is valid
        draft.schedule.mode = .advanced
        draft.schedule.advancedText = ""
        #expect(!draft.isSubmittable) // empty advanced schedule
        draft.schedule.advancedText = "every 30m"
        #expect(draft.isSubmittable)
        draft.name = "   "
        #expect(!draft.isSubmittable) // whitespace name
    }

    @Test func createBodyCarriesTheDraft() {
        var draft = CronJobDraft()
        draft.name = "  Brief  "
        draft.prompt = "Summarize"
        draft.schedule.mode = .interval
        draft.schedule.intervalValue = 30
        draft.schedule.intervalUnit = .minutes
        draft.deliver = "telegram"
        draft.skillsText = "one, two,,  three  "
        draft.repeatTimes = 5

        let body = draft.createBody()
        #expect(body?.name == "Brief")
        #expect(body?.schedule == "every 30m")
        #expect(body?.prompt == "Summarize")
        #expect(body?.deliver == "telegram")
        #expect(body?.skills == ["one", "two", "three"])
        #expect(body?.repeatCount == 5)
    }

    @Test func createBodyOmitsEmptyOptionals() {
        var draft = CronJobDraft()
        draft.name = "Brief"
        let body = draft.createBody()
        #expect(body?.deliver == nil)   // server picks its default
        #expect(body?.skills == nil)
        #expect(body?.repeatCount == nil)
    }

    private func fullJob() throws -> CronJob {
        try job("""
        {"id": "aaa111aaa111", "name": "Brief", "prompt": "Summarize",
         "schedule": {"kind": "cron", "expr": "0 9 * * *"},
         "deliver": "telegram", "skills": ["one"],
         "repeat": {"times": 5, "completed": 2}, "enabled": true}
        """)
    }

    @Test func untouchedEditPatchesNothing() throws {
        let draft = CronJobDraft(job: try fullJob())
        let patch = try #require(draft.patchBody())
        #expect(patch.isEmpty)
    }

    @Test func patchCarriesOnlyChangedFields() throws {
        var draft = CronJobDraft(job: try fullJob())
        draft.name = "Evening brief"
        let patch = try #require(draft.patchBody())
        #expect(patch.name == "Evening brief")
        #expect(patch.prompt == nil)
        #expect(patch.schedule == nil)
        #expect(patch.deliver == nil)
        #expect(patch.skills == nil)
        #expect(!patch.includeRepeat)
        #expect(patch.enabled == nil)
    }

    @Test func scheduleChangeTravels() throws {
        var draft = CronJobDraft(job: try fullJob())
        draft.schedule.mode = .interval
        draft.schedule.intervalValue = 2
        draft.schedule.intervalUnit = .hours
        let patch = try #require(draft.patchBody())
        #expect(patch.schedule == "every 2h")
    }

    /// Clearing deliver means "leave it alone" — an empty deliver has no
    /// server semantic; a legacy value must never be clobbered by omission.
    @Test func clearedDeliverDoesNotTravel() throws {
        var draft = CronJobDraft(job: try fullJob())
        draft.deliver = ""
        let patch = try #require(draft.patchBody())
        #expect(patch.deliver == nil)
        #expect(patch.isEmpty)
    }

    @Test func enabledToggleTravels() throws {
        var draft = CronJobDraft(job: try fullJob())
        draft.enabled = false
        let patch = try #require(draft.patchBody())
        #expect(patch.enabled == false)
    }

    /// Repeat PATCHes in the record's dict shape with `completed` preserved —
    /// upstream's update is `{**job, **updates}` with no repeat
    /// normalization, so a bare int would corrupt the stored record.
    @Test func repeatPatchEncodesDictWithPreservedCompleted() throws {
        var draft = CronJobDraft(job: try fullJob())
        draft.repeatTimes = 9
        let patch = try #require(draft.patchBody())
        #expect(patch.includeRepeat)

        let data = try JSONEncoder().encode(patch)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let repeatDict = try #require(object["repeat"] as? [String: Any])
        #expect(repeatDict["times"] as? Int == 9)
        #expect(repeatDict["completed"] as? Int == 2)
        // Only repeat traveled.
        #expect(object.keys.sorted() == ["repeat"])
    }

    @Test func repeatClearedToForeverEncodesNullTimes() throws {
        var draft = CronJobDraft(job: try fullJob())
        draft.repeatTimes = nil
        let patch = try #require(draft.patchBody())
        let data = try JSONEncoder().encode(patch)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let repeatDict = try #require(object["repeat"] as? [String: Any])
        #expect(repeatDict["times"] is NSNull)
    }

    @Test func skillsChangeTravelsIncludingClearing() throws {
        var draft = CronJobDraft(job: try fullJob())
        draft.skillsText = ""
        let patch = try #require(draft.patchBody())
        #expect(patch.skills == [])
    }
}
