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
        let days = min(max(arguments.daysAhead, 1), 14)
        await relay.started(name, detail: "next \(days) day\(days == 1 ? "" : "s")")
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
        await relay.started(name)
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
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: found ?? [])
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
            switch (lhs.dueDateComponents?.date, rhs.dueDateComponents?.date) {
            case (let l?, let r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (lhs.title ?? "") < (rhs.title ?? "")
            }
        }
        let lines = sorted.prefix(25).map { reminder -> String in
            var line = "• \(reminder.title ?? "Untitled reminder")"
            if let components = reminder.dueDateComponents, let due = components.date {
                let hasTime = components.hour != nil
                line += " — due \((hasTime ? timedFormatter : dayFormatter).string(from: due))"
            }
            line += " [\(reminder.calendar.title)]"
            return line
        }
        var result = lines.joined(separator: "\n")
        if reminders.count > 25 {
            result += "\n(+\(reminders.count - 25) more)"
        }
        return result
    }
}
