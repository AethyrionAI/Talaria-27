import EventKit
import Foundation
import FoundationModels

// Side-effecting device tools (#29). Every one of these goes through the
// ToolConfirmationCenter — staged, shown as a card in the transcript,
// executed only on explicit approve. Deny returns a "user declined" result
// the model reacts to conversationally; nothing is ever created silently.

// MARK: - Shared parsing (unit-tested)

enum DeviceActionParsing {

    /// Tolerant date-time parser for tool arguments and card edits:
    /// ISO 8601 with or without seconds/timezone ("2026-07-08T09:00",
    /// "2026-07-08T09:00:00Z"), and the human "2026-07-08 09:00" /
    /// date-only "2026-07-08" forms. Nil for empty or unreadable input —
    /// callers treat nil as "no date", never guess one.
    nonisolated static func parseDateTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoWithZone = ISO8601DateFormatter()
        isoWithZone.formatOptions = [.withInternetDateTime]
        if let date = isoWithZone.date(from: trimmed) { return date }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = .current // local wall-clock time, as a person means it
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Card/display form of an optional date, honest about absence.
    nonisolated static func displayDate(_ date: Date?) -> String {
        guard let date else { return "None" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Duration-in-minutes from a card field: plain integers, clamped to a
    /// sane meeting range. Nil for unparseable input.
    nonisolated static func parseDurationMinutes(_ raw: String) -> Int? {
        let digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "minutes", with: "")
            .replacingOccurrences(of: "min", with: "")
            .replacingOccurrences(of: "m", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Int(digits), value > 0 else { return nil }
        return min(value, 24 * 60)
    }
}

// MARK: - Create reminder (EventKit)

struct ReminderCreateTool: Tool {
    let name = "createReminder"
    /// Production description text — the default at every production call
    /// site, so the shipping belt is byte-identical with or without the
    /// #196 seam below.
    static let productionDescription = "Create a reminder in the user's Reminders app. The user sees a confirmation card and can edit or cancel before anything is created."
    #if DEBUG
    /// #196 second battery, `armed-remfix` / `armed-fix` treatment: scope
    /// the tool against task-verb confusion — the first battery measured
    /// production armed grabbing this tool on 8/10 "write a haiku" requests
    /// (the model parses the creative verb as a todo). Measurement cells
    /// only; production ships this text ONLY after a battery verdict.
    static let scopedDescription196 = "Create a reminder in the user's Reminders app, only when the user asks to be reminded of something or to save a to-do for later — never for requests to write, compose, or answer something now. The user sees a confirmation card and can edit or cancel before anything is created."

    /// #200B `armed-toolfix` / `armed-bothfix` treatment: the FILED #200
    /// table measured remind 0/20 with 15/20 trials interrogating the
    /// OPTIONAL `list` (± due) field instead of defaulting. This text
    /// targets the stall at the tool level. Measurement cells only;
    /// production ships it ONLY after a battery verdict.
    static let destalledDescription200 = productionDescription + " Create it immediately with the details given; missing fields default — never ask a clarifying question first."
    #endif
    /// `var` + init default (#196): the battery's shaped belt copies this
    /// tool and swaps ONLY this string; production call sites never pass it.
    var description: String = ReminderCreateTool.productionDescription
    /// FoundationModels' schema-injection gate, surfaced as a stored var so
    /// the third battery's `armed-noschema` cell can flip copies (#196).
    /// Production call sites never pass it; the default matches the
    /// framework default (pinned by `frameworkDefaultInjectsSchemasIntoInstructions`),
    /// so the shipping belt is byte-identical with the seam in place.
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded about, e.g. \"Call Shelley\".")
        var title: String
        @Guide(description: "Due date and time like \"2026-07-08T09:00\" (local time), or empty for no due date.")
        var due: String
        @Guide(description: "Reminders list name, or empty for the default list.")
        var list: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        await relay.started(name, detail: title)
        defer { Task { await relay.completed(name) } }
        return await Self.performCreate(
            rawTitle: title, rawDue: arguments.due, rawList: arguments.list,
            confirmations: confirmations
        )
    }

    /// The whole create flow from staged-title to EventKit save, shared
    /// with the #200B guidefix copy so a treatment cell's ONLY delta is
    /// text — structural-identity discipline: two structs, one engine.
    nonisolated static func performCreate(
        rawTitle: String, rawDue: String, rawList: String,
        confirmations: ToolConfirmationCenter
    ) async -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "No reminder title was given — nothing staged." }

        let parsedDue = DeviceActionParsing.parseDateTime(rawDue)
        let decision = await confirmations.requestConfirmation(
            title: "Create this reminder?",
            detail: nil,
            fields: [
                .init(key: "title", label: "Title", value: title),
                .init(key: "due", label: "Due", value: parsedDue.map { DeviceActionParsing.displayDate($0) } ?? ""),
                .init(key: "list", label: "List", value: rawList.trimmingCharacters(in: .whitespacesAndNewlines)),
            ]
        )
        guard case .approved(let values) = decision else {
            return "The user declined — no reminder was created."
        }

        // Edited card values are what get created (#29 acceptance).
        let finalTitle = (values["title"] ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTitle.isEmpty else { return "The edited title was empty — no reminder was created." }
        let dueRaw = (values["due"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDue = Self.resolveEditedDate(edited: dueRaw, original: parsedDue)
        if !dueRaw.isEmpty, dueRaw.lowercased() != "none", finalDue == nil {
            return "Couldn't read \"\(dueRaw)\" as a date — no reminder was created. Try the form 2026-07-08T09:00."
        }
        let listName = (values["list"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            guard granted else { return "Reminders permission was not granted — nothing was created." }
        case .fullAccess:
            break
        default:
            return "Reminders permission is not granted — nothing was created. The user can enable it in Settings → Privacy & Security → Reminders."
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = finalTitle
        if let finalDue {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: finalDue
            )
        }
        if !listName.isEmpty,
           let match = store.calendars(for: .reminder).first(where: {
               $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
           }) {
            reminder.calendar = match
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }
        guard let calendarTitle = reminder.calendar?.title else {
            return "No Reminders list is available on this device — nothing was created."
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            return "Creating the reminder failed: \(error.localizedDescription)"
        }
        let dueLine = finalDue.map { " due \(DeviceActionParsing.displayDate($0))" } ?? ""
        // #200F: the SAVED title may carry the battery reap marker; the
        // success text echoes the model-requested form (marker stripped).
        return "Created reminder \"\(ToolConfirmationCenter.strippingBatteryMarker(finalTitle))\"\(dueLine) in list \"\(calendarTitle)\"."
    }

    /// "None"/empty keeps no date; an unchanged display string keeps the
    /// original parse; anything else must re-parse.
    nonisolated static func resolveEditedDate(edited: String, original: Date?) -> Date? {
        if edited.isEmpty || edited.lowercased() == "none" { return nil }
        if let original, edited == DeviceActionParsing.displayDate(original) { return original }
        return DeviceActionParsing.parseDateTime(edited)
    }
}

#if DEBUG
// MARK: - #200B guidefix treatment copy

/// The `armed-guidefix` / `armed-bothfix` cell's reminder tool: identical
/// to `ReminderCreateTool` in name, flow, and engine — the ONLY deltas are
/// the `@Guide` texts on the optional fields, de-stalled against the FILED
/// #200 finding (15/20 remind trials interrogate `list` ± `due` instead of
/// defaulting; the single-field alarm tool runs 19/20). `@Guide` is a
/// macro, so this must be a copy struct — the description-var seam can't
/// reach it. The @Guide texts are the measured artifact; they have no
/// runtime accessor, so they're pinned here by comment and measured by the
/// battery itself. Measurement cells only; production ships this ONLY
/// after a battery verdict.
struct ReminderCreateToolGuidefix: Tool {
    let name = "createReminder"
    /// Production description by default — the @Guide delta is this cell's
    /// only change; `armed-bothfix` passes the destalled description.
    var description: String = ReminderCreateTool.productionDescription
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded about, e.g. \"Call Shelley\".")
        var title: String
        @Guide(description: "Due date and time like \"2026-07-08T09:00\" (local time), or empty for no due date. Use exactly the time the user gave — never ask for more date detail.")
        var due: String
        @Guide(description: "Reminders list name. Empty is correct when the user didn't name one — the default list is used; never ask which list.")
        var list: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        await relay.started(name, detail: title)
        defer { Task { await relay.completed(name) } }
        return await ReminderCreateTool.performCreate(
            rawTitle: title, rawDue: arguments.due, rawList: arguments.list,
            confirmations: confirmations
        )
    }
}
#endif

// MARK: - Create calendar event (EventKit)

struct CalendarEventTool: Tool {
    let name = "createCalendarEvent"
    let description = "Create a calendar event. The user sees a confirmation card and can edit or cancel before anything is created."
    /// #196 `armed-noschema` seam — see `ReminderCreateTool`'s twin. The
    /// default matches the framework default; production never passes it.
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "Event title, e.g. \"Dentist\".")
        var title: String
        @Guide(description: "Start date and time like \"2026-07-08T09:00\" (local time).")
        var startsAt: String
        @Guide(description: "Duration in minutes, e.g. 30.")
        var durationMinutes: Int
        @Guide(description: "Optional location, or empty.")
        var location: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        await relay.started(name, detail: title)
        defer { Task { await relay.completed(name) } }
        guard !title.isEmpty else { return "No event title was given — nothing staged." }
        guard let start = DeviceActionParsing.parseDateTime(arguments.startsAt) else {
            return "Couldn't read \"\(arguments.startsAt)\" as the start time — nothing staged. Use the form 2026-07-08T09:00."
        }
        let minutes = min(max(arguments.durationMinutes, 5), 24 * 60)

        let decision = await confirmations.requestConfirmation(
            title: "Add this event to the calendar?",
            detail: nil,
            fields: [
                .init(key: "title", label: "Title", value: title),
                .init(key: "startsAt", label: "Starts", value: DeviceActionParsing.displayDate(start)),
                .init(key: "duration", label: "Minutes", value: String(minutes)),
                .init(key: "location", label: "Location", value: arguments.location.trimmingCharacters(in: .whitespacesAndNewlines)),
            ]
        )
        guard case .approved(let values) = decision else {
            return "The user declined — no event was created."
        }

        let finalTitle = (values["title"] ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTitle.isEmpty else { return "The edited title was empty — no event was created." }
        let startRaw = (values["startsAt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalStart: Date
        if startRaw == DeviceActionParsing.displayDate(start) {
            finalStart = start
        } else if let reparsed = DeviceActionParsing.parseDateTime(startRaw) {
            finalStart = reparsed
        } else {
            return "Couldn't read \"\(startRaw)\" as the start time — no event was created."
        }
        let finalMinutes = DeviceActionParsing.parseDurationMinutes(values["duration"] ?? "") ?? minutes
        let finalLocation = (values["location"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            // Full access is the honest ask — Talaria also READS calendars,
            // and priming write-only here would leave the reader unable to
            // ever re-prompt (#186). Apple's sheet still offers "Add Events
            // Only": the request reports that pick as false, so re-read the
            // settled status — a write-only grant authorizes this save.
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            if !granted, EKEventStore.authorizationStatus(for: .event) != .writeOnly {
                return "Calendar permission was not granted — nothing was created."
            }
        case .fullAccess, .writeOnly:
            // .writeOnly authorizes exactly this tool's one operation —
            // save(_:span:commit:) — a narrower grant is not a denial (#186).
            break
        default:
            return "Calendar permission is not granted — nothing was created. The user can enable it in Settings → Privacy & Security → Calendars."
        }

        let event = EKEvent(eventStore: store)
        event.title = finalTitle
        event.startDate = finalStart
        event.endDate = finalStart.addingTimeInterval(TimeInterval(finalMinutes * 60))
        if !finalLocation.isEmpty { event.location = finalLocation }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return "No calendar is available for new events — nothing was created."
        }
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            return "Creating the event failed: \(error.localizedDescription)"
        }
        // #200F: the SAVED title may carry the battery reap marker; the
        // success text echoes the model-requested form (marker stripped).
        return "Added \"\(ToolConfirmationCenter.strippingBatteryMarker(finalTitle))\" on \(DeviceActionParsing.displayDate(finalStart)) for \(finalMinutes) minutes\(finalLocation.isEmpty ? "" : " at \(finalLocation)") to \"\(calendar.title)\"."
    }
}

// MARK: - Alarm / timer (AlarmKit via the #16 executor)

struct AlarmTool: Tool {
    let name = "scheduleAlarm"
    let description = "Schedule an alarm or countdown timer on this iPhone (it rings through Silent mode). The user sees a confirmation card and can edit or cancel before anything is scheduled."
    /// #196 `armed-noschema` seam — see `ReminderCreateTool`'s twin. The
    /// default matches the framework default; production never passes it.
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter
    let alarmService: AlarmService

    @Generable
    struct Arguments {
        @Guide(description: "The alarm or timer request, e.g. \"6:30am wake up\", \"18:45\", or \"25m tea\".")
        var request: String
    }

    func call(arguments: Arguments) async throws -> String {
        let raw = arguments.request.trimmingCharacters(in: .whitespacesAndNewlines)
        await relay.started(name, detail: raw)
        defer { Task { await relay.completed(name) } }

        // #16's grammar + executor, unchanged: parse → stage → explicit
        // confirm → AlarmService.schedule. Same authority rule, same wording.
        guard let request = AlarmService.parse(raw) else {
            return "Couldn't read a time from \"\(raw)\" — nothing staged. Formats: 6:30am, 18:45, or 25m."
        }
        let decision = await confirmations.requestConfirmation(
            title: "Schedule on this iPhone?",
            detail: "It will ring through Silent mode and Focus.",
            fields: [.init(key: "request", label: "Alarm", value: raw)]
        )
        guard case .approved(let values) = decision else {
            return "The user declined — no \(request.kindNoun) was scheduled."
        }

        // An edited request re-parses through the same #16 grammar.
        let finalRaw = (values["request"] ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let finalRequest = finalRaw == raw ? request : AlarmService.parse(finalRaw) else {
            return "Couldn't read a time from the edited \"\(finalRaw)\" — nothing was scheduled."
        }
        do {
            try await alarmService.schedule(finalRequest)
            // #200F: the SCHEDULED request keeps the battery reap marker in
            // its label (that is how the teardown finds the alarm) — the
            // success text re-parses the cleaned raw so the echoed summary
            // is the model-requested form, marker-free.
            let echo = AlarmService.parse(ToolConfirmationCenter.strippingBatteryMarker(finalRaw)) ?? finalRequest
            return "Scheduled \(echo.summary) — it will ring through Silent mode and Focus."
        } catch {
            return "Couldn't schedule the \(finalRequest.kindNoun): \(error.localizedDescription)"
        }
    }
}
