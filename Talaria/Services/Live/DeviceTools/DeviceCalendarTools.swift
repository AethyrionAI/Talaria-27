import EventKit
import Foundation
import FoundationModels

// EventKit READ tools (#28) — pulls main-repo #33 forward device-side. The
// write side (create reminder / create event) lands in #29 behind the
// ToolConfirmationCenter; nothing here mutates anything.

// MARK: - Calendar (read)

struct CalendarReadTool: Tool {
    let name = "readCalendar"
    let description = "Read the user's calendar: events happening today or in the next several days, with times and locations."
    let relay: ToolEventRelay

    @Generable
    struct Arguments {
        @Guide(description: "How many days ahead to look, from 1 (today only) to 14.")
        var daysAhead: Int
    }

    func call(arguments: Arguments) async throws -> String {
        try await Self.performRead(rawDaysAhead: arguments.daysAhead, relay: relay, name: name)
    }

    /// #251-2A: `call`'s body, lifted verbatim — clamp included, so the
    /// window bounds live in exactly one place for both callers. `daysAhead`
    /// is a required `Int` in the schema, so the extraction takes an `Int`
    /// (the signature follows the body).
    static func performRead(rawDaysAhead: Int, relay: ToolEventRelay, name: String) async throws -> String {
        let days = min(max(rawDaysAhead, 1), 14)
        if case .refused(let refusal) = try await relay.started(name, detail: "next \(days) day\(days == 1 ? "" : "s")") { return refusal }
        defer { Task { await relay.completed(name) } }

        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            // Contextual priming (#31): prompt on the first calendar question.
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            guard granted else {
                return "Calendar permission was not granted, so events can't be read."
            }
        case .fullAccess:
            break
        case .writeOnly:
            // Reachable from Apple's full-access sheet ("Add Events Only"),
            // and there is no re-prompt path once primed — reading genuinely
            // needs the wider grant, so name the grant the user actually
            // holds and how to widen it (#186). "Enable it in Settings" to
            // someone who granted what they were shown reads as a lie.
            return "Calendar access is add-only, so events can't be read. To let Hermes read the calendar, choose Full Access for it in Settings → Privacy & Security → Calendars."
        default:
            return "Calendar permission is not granted, so events can't be read. The user can enable it in Settings → Privacy & Security → Calendars."
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else {
            return "Couldn't compute the date range."
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else {
            return "No calendar events in the next \(days) day\(days == 1 ? "" : "s")."
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        let lines = events.prefix(25).map { event -> String in
            let day = dayFormatter.string(from: event.startDate)
            let when = event.isAllDay
                ? "all day"
                : "\(timeFormatter.string(from: event.startDate))–\(timeFormatter.string(from: event.endDate))"
            var line = "\(day) \(when) — \(event.title ?? "Untitled event")"
            if let where_ = event.location, !where_.isEmpty {
                line += " @ \(where_)"
            }
            return line
        }
        var result = lines.joined(separator: "\n")
        if events.count > 25 {
            result += "\n(+\(events.count - 25) more)"
        }
        return result
    }
}

// MARK: - Reminders (read)

struct ReminderReadTool: Tool {
    let name = "readReminders"
    let description = "Read the user's open reminders (incomplete to-dos), including due dates and which list they're on."
    let relay: ToolEventRelay

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        try await Self.performRead(relay: relay, name: name)
    }

    /// #251-2A: `call`'s body, lifted verbatim. `Arguments` is empty — there
    /// is no list filter to thread through, so the extraction takes none.
    static func performRead(relay: ToolEventRelay, name: String) async throws -> String {
        if case .refused(let refusal) = try await relay.started(name) { return refusal }
        defer { Task { await relay.completed(name) } }

        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            guard granted else {
                return "Reminders permission was not granted, so reminders can't be read."
            }
        case .fullAccess:
            break
        default:
            return "Reminders permission is not granted, so reminders can't be read. The user can enable it in Settings → Privacy & Security → Reminders."
        }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        // Snapshot Sendable fields inside the completion handler — EKReminder
        // is not Sendable and must not cross the continuation boundary.
        struct ReminderSnapshot: Sendable {
            let title: String
            let due: Date?
            let hasTime: Bool
            let calendarTitle: String
        }
        let reminders: [ReminderSnapshot] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                let snapshots = (found ?? []).map { reminder in
                    ReminderSnapshot(
                        title: reminder.title ?? "Untitled reminder",
                        due: reminder.dueDateComponents?.date,
                        hasTime: reminder.dueDateComponents?.hour != nil,
                        calendarTitle: reminder.calendar.title
                    )
                }
                continuation.resume(returning: snapshots)
            }
        }
        guard !reminders.isEmpty else { return "No open reminders." }

        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .none
        let timedFormatter = DateFormatter()
        timedFormatter.dateStyle = .medium
        timedFormatter.timeStyle = .short

        // Due-dated reminders first (soonest first), then the undated pile.
        let sorted = reminders.sorted { lhs, rhs in
            switch (lhs.due, rhs.due) {
            case (let l?, let r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.title < rhs.title
            }
        }
        let lines = sorted.prefix(25).map { reminder -> String in
            var line = "• \(reminder.title)"
            if let due = reminder.due {
                line += " — due \((reminder.hasTime ? timedFormatter : dayFormatter).string(from: due))"
            }
            line += " [\(reminder.calendarTitle)]"
            return line
        }
        var result = lines.joined(separator: "\n")
        if reminders.count > 25 {
            result += "\n(+\(reminders.count - 25) more)"
        }
        return result
    }
}
