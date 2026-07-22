import Foundation

/// #156a D4 — the structured schedule input. The point of this lane: instead
/// of hermex's type-cron-blind free-text field, presets emit one of the four
/// VERIFIED server grammar forms (`cron/jobs.py parse_schedule`, hermes-agent
/// 0.19.0):
///
///   interval   → "every 30m" / "every 2h" / "every 1d"
///   daily      → "0 9 * * *"          (cron, 5 fields)
///   weekly     → "0 9 * * 1"          (cron weekday 0=Sunday)
///   once-rel   → "30m" / "2h" / "1d"
///   once-abs   → ISO 8601 timestamp
///
/// Preview rule: presets humanize FROM OUR OWN INPUTS (we generated the
/// string, we know what it means). Advanced mode gets NO local preview —
/// no client-side cron parser, ever; after save the server's
/// `schedule_display` is the authority.
///
/// Timezone honesty: cron expressions evaluate on the HOST's configured
/// clock (naive → configured Hermes timezone, upstream #51021 comment), so
/// daily/weekly previews are labeled host time. The absolute one-shot embeds
/// this DEVICE's UTC offset in the emitted ISO string — `fromisoformat`
/// keeps an explicit offset as-is, so that time means what the phone showed.
struct ScheduleDraft: Equatable {
    /// Equality is SEMANTIC — two drafts are equal when they mean the same
    /// schedule. Mode-irrelevant leftovers (a stale interval value while in
    /// daily mode) and the wall-clock-seeded `onceDate` default must never
    /// make two same-meaning drafts unequal — the PATCH diff keys off this.
    static func == (lhs: ScheduleDraft, rhs: ScheduleDraft) -> Bool {
        guard lhs.mode == rhs.mode else { return false }
        switch lhs.mode {
        case .interval:
            return lhs.intervalValue == rhs.intervalValue && lhs.intervalUnit == rhs.intervalUnit
        case .daily:
            return lhs.hour == rhs.hour && lhs.minute == rhs.minute
        case .weekly:
            return lhs.hour == rhs.hour && lhs.minute == rhs.minute && lhs.weekday == rhs.weekday
        case .once:
            guard lhs.onceIsRelative == rhs.onceIsRelative else { return false }
            return lhs.onceIsRelative
                ? lhs.intervalValue == rhs.intervalValue && lhs.intervalUnit == rhs.intervalUnit
                : lhs.onceDate == rhs.onceDate
        case .advanced:
            return lhs.advancedText == rhs.advancedText
        }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case interval
        case daily
        case weekly
        case once
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .interval: "Repeat"
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .once: "Once"
            case .advanced: "Advanced"
            }
        }
    }

    enum IntervalUnit: String, CaseIterable, Identifiable {
        case minutes = "m"
        case hours = "h"
        case days = "d"

        var id: String { rawValue }

        var singular: String {
            switch self {
            case .minutes: "minute"
            case .hours: "hour"
            case .days: "day"
            }
        }

        func label(for value: Int) -> String {
            value == 1 ? singular : singular + "s"
        }
    }

    /// Cron weekday numbering (0 = Sunday … 6 = Saturday).
    enum Weekday: Int, CaseIterable, Identifiable {
        case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday

        var id: Int { rawValue }

        var name: String {
            switch self {
            case .sunday: "Sunday"
            case .monday: "Monday"
            case .tuesday: "Tuesday"
            case .wednesday: "Wednesday"
            case .thursday: "Thursday"
            case .friday: "Friday"
            case .saturday: "Saturday"
            }
        }
    }

    var mode: Mode = .interval

    // Interval + once-relative share the value/unit pair.
    var intervalValue: Int = 30
    var intervalUnit: IntervalUnit = .minutes

    // Daily / weekly.
    var hour: Int = 9
    var minute: Int = 0
    var weekday: Weekday = .monday

    // Once.
    var onceIsRelative = true
    var onceDate: Date = Date().addingTimeInterval(3600)

    // Advanced — exactly hermex's behaviour: raw text, non-empty gating,
    // the server is the validator.
    var advancedText: String = ""

    // MARK: - Emission

    /// The schedule string sent to the server. nil = not valid to send yet
    /// (the create/save button's gate).
    func emittedString(calendar: Calendar = .current) -> String? {
        switch mode {
        case .interval:
            guard intervalValue >= 1 else { return nil }
            return "every \(intervalValue)\(intervalUnit.rawValue)"
        case .daily:
            return "\(minute) \(hour) * * *"
        case .weekly:
            return "\(minute) \(hour) * * \(weekday.rawValue)"
        case .once:
            if onceIsRelative {
                guard intervalValue >= 1 else { return nil }
                return "\(intervalValue)\(intervalUnit.rawValue)"
            }
            return Self.isoWithDeviceOffset(from: onceDate, calendar: calendar)
        case .advanced:
            let trimmed = advancedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// ISO 8601 with the device's UTC offset spelled out — an explicit
    /// offset survives `datetime.fromisoformat` untouched, so the stored
    /// instant is exactly the wall-clock the phone displayed (no host-tz
    /// reinterpretation).
    static func isoWithDeviceOffset(from date: Date, calendar: Calendar = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    // MARK: - Preview

    /// Humanized description for preset modes — derived from our own inputs,
    /// never parsed back out of the emitted string. Advanced returns nil
    /// (honest silence; the server's `schedule_display` takes over after
    /// save).
    var localizedPreview: String? {
        switch mode {
        case .interval:
            guard intervalValue >= 1 else { return nil }
            return "Every \(intervalValue) \(intervalUnit.label(for: intervalValue))"
        case .daily:
            return "Every day at \(Self.clockLabel(hour: hour, minute: minute)) (host time)"
        case .weekly:
            return "Every \(weekday.name) at \(Self.clockLabel(hour: hour, minute: minute)) (host time)"
        case .once:
            if onceIsRelative {
                guard intervalValue >= 1 else { return nil }
                return "Once, \(intervalValue) \(intervalUnit.label(for: intervalValue)) from now"
            }
            let formatted = onceDate.formatted(date: .abbreviated, time: .shortened)
            return "Once at \(formatted) (this device's time)"
        case .advanced:
            return nil
        }
    }

    /// Whether the current mode's absolute time evaluates on the HOST's
    /// clock — drives the timezone caveat next to the time input. No
    /// endpoint exposes the host timezone (verified), so the UI states whose
    /// clock it is rather than pretending they match.
    var usesHostClock: Bool {
        switch mode {
        case .daily, .weekly, .advanced: true
        case .interval, .once: false
        }
    }

    private static func clockLabel(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Seeding from an existing job (edit flow)

    /// Best-effort re-hydration of the picker from a job's parsed schedule.
    /// Anything the presets can't round-trip lands in Advanced with the
    /// server's own text, so editing never silently rewrites a schedule the
    /// picker doesn't understand.
    static func from(job: CronJob) -> ScheduleDraft {
        var draft = ScheduleDraft()
        guard let schedule = job.schedule else {
            draft.mode = .advanced
            draft.advancedText = job.scheduleText ?? ""
            return draft
        }
        switch schedule.kind {
        case "interval":
            if let minutes = schedule.minutes, minutes >= 1 {
                draft.mode = .interval
                if minutes % 1440 == 0 {
                    draft.intervalValue = minutes / 1440
                    draft.intervalUnit = .days
                } else if minutes % 60 == 0 {
                    draft.intervalValue = minutes / 60
                    draft.intervalUnit = .hours
                } else {
                    draft.intervalValue = minutes
                    draft.intervalUnit = .minutes
                }
                return draft
            }
        case "cron":
            if let expr = schedule.expr, let parsed = Self.presetCronFields(expr) {
                draft.hour = parsed.hour
                draft.minute = parsed.minute
                if let weekday = parsed.weekday {
                    draft.mode = .weekly
                    draft.weekday = weekday
                } else {
                    draft.mode = .daily
                }
                return draft
            }
        case "once":
            if let runAt = schedule.runAt {
                if let date = CronDateParsing.instant(from: runAt) {
                    draft.mode = .once
                    draft.onceIsRelative = false
                    draft.onceDate = date
                    return draft
                }
                // A NAIVE run_at is host wall-clock the device picker can't
                // represent honestly — Advanced keeps the raw timestamp,
                // which is itself valid schedule grammar.
                draft.mode = .advanced
                draft.advancedText = runAt
                return draft
            }
        default:
            break
        }
        draft.mode = .advanced
        draft.advancedText = schedule.expr ?? job.scheduleText ?? ""
        return draft
    }

    /// Recognizes ONLY the exact shapes our own presets emit
    /// (`M H * * *` / `M H * * W`) — this is string matching against our
    /// own output format, not a cron parser. Anything else → Advanced.
    static func presetCronFields(_ expr: String) -> (minute: Int, hour: Int, weekday: Weekday?)? {
        let fields = expr.split(separator: " ").map(String.init)
        guard fields.count == 5,
              let minute = Int(fields[0]), (0 ..< 60).contains(minute),
              let hour = Int(fields[1]), (0 ..< 24).contains(hour),
              fields[2] == "*", fields[3] == "*" else {
            return nil
        }
        if fields[4] == "*" {
            return (minute, hour, nil)
        }
        guard let weekdayValue = Int(fields[4]), let weekday = Weekday(rawValue: weekdayValue) else {
            return nil
        }
        return (minute, hour, weekday)
    }
}

// MARK: - Job draft (D5)

/// One draft value type drives BOTH create and edit (#160 idea 1). Fields
/// are limited to what the HTTP surface accepts: the create set
/// (name/schedule/prompt/deliver/skills/repeat) and the PATCH whitelist
/// (those + enabled). `script`/`no_agent`/`workdir`/model stay read-only in
/// detail — the API cannot write them.
struct CronJobDraft: Equatable {
    var name = ""
    var prompt = ""
    var schedule = ScheduleDraft()
    /// Empty on create = omit, letting the server pick its default
    /// ("origin" for API-created jobs).
    var deliver = ""
    /// Free text, comma-separated — a picker fed from /v1/skills is 156b.
    var skillsText = ""
    /// nil = run forever (recurring). The server auto-sets 1 for one-shots.
    var repeatTimes: Int?
    var enabled = true

    /// nil = create; a job id = editing that job.
    var editingJobID: String?
    /// The record being edited, kept for change-diffing so the PATCH only
    /// carries what the user actually touched.
    private var original: CronJob?

    init() {}

    init(job: CronJob) {
        editingJobID = job.id
        original = job
        name = job.name ?? ""
        prompt = job.prompt ?? ""
        schedule = ScheduleDraft.from(job: job)
        deliver = job.deliver ?? ""
        skillsText = (job.skills ?? []).joined(separator: ", ")
        repeatTimes = job.repeatPolicy?.times
        enabled = job.isEnabled
    }

    static func == (lhs: CronJobDraft, rhs: CronJobDraft) -> Bool {
        lhs.name == rhs.name && lhs.prompt == rhs.prompt
            && lhs.schedule == rhs.schedule && lhs.deliver == rhs.deliver
            && lhs.skillsText == rhs.skillsText && lhs.repeatTimes == rhs.repeatTimes
            && lhs.enabled == rhs.enabled && lhs.editingJobID == rhs.editingJobID
    }

    var isEditing: Bool { editingJobID != nil }

    var parsedSkills: [String] {
        skillsText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Client-side gating is non-emptiness of the server's REQUIRED fields
    /// (name + schedule), exactly hermex's posture — everything richer is
    /// the server's verdict, rendered verbatim on rejection.
    var isSubmittable: Bool {
        !trimmedName.isEmpty && schedule.emittedString() != nil
    }

    // MARK: - Wire bodies

    func createBody() -> CronJobCreateBody? {
        guard !isEditing, isSubmittable, let scheduleString = schedule.emittedString() else {
            return nil
        }
        let trimmedDeliver = deliver.trimmingCharacters(in: .whitespacesAndNewlines)
        let skills = parsedSkills
        return CronJobCreateBody(
            name: trimmedName,
            schedule: scheduleString,
            prompt: prompt,
            deliver: trimmedDeliver.isEmpty ? nil : trimmedDeliver,
            skills: skills.isEmpty ? nil : skills,
            repeatCount: repeatTimes
        )
    }

    /// Diff against the record being edited — untouched fields stay out of
    /// the PATCH entirely so an edit can never clobber what it didn't show.
    func patchBody() -> CronJobPatchBody? {
        guard isEditing, isSubmittable, let original,
              let scheduleString = schedule.emittedString() else {
            return nil
        }
        var patch = CronJobPatchBody()
        if trimmedName != (original.name ?? "") {
            patch.name = trimmedName
        }
        if prompt != (original.prompt ?? "") {
            patch.prompt = prompt
        }
        // The schedule only travels when the DRAFT no longer matches what
        // the original record round-trips to — re-emitting an untouched
        // "every 30m" is harmless, but re-emitting an untouched cron/once is
        // how a no-op edit silently rewrites a schedule; diff on the draft.
        if schedule != ScheduleDraft.from(job: original) {
            patch.schedule = scheduleString
        }
        // An empty deliver has no server semantic — clearing the field
        // means "leave it alone", never "deliver to nowhere".
        let trimmedDeliver = deliver.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDeliver.isEmpty, trimmedDeliver != (original.deliver ?? "") {
            patch.deliver = trimmedDeliver
        }
        if parsedSkills != (original.skills ?? []) {
            patch.skills = parsedSkills
        }
        if repeatTimes != original.repeatPolicy?.times {
            patch.includeRepeat = true
            patch.repeatTimes = repeatTimes
            patch.repeatCompleted = original.repeatPolicy?.completed
        }
        if enabled != original.isEnabled {
            patch.enabled = enabled
        }
        return patch
    }
}
