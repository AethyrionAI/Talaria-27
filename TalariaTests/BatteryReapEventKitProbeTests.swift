#if DEBUG
import EventKit
import Testing
@testable import Talaria

/// #200 crash probe: every crashed action battery died inside the teardown
/// reap, and on-device elimination (42 AlarmKit cancels survived via the
/// sweep; the reminders fetch is byte-for-byte what readReminders ran
/// successfully in the same processes) left the EVENTS step — the 62-day
/// enumeration plus the app's ONLY EventKit REMOVE — as the suspect.
/// These tests exercise those exact framework operations on the sim's
/// 27.0 runtime. TCC must be pre-granted (`simctl privacy grant
/// calendar/reminders org.aethyrion.talaria27`); without access the
/// probes fail their #require visibly rather than fake-passing.
@MainActor
struct BatteryReapEventKitProbeTests {

    /// The reap's events step, verbatim: seed a marked event the way an
    /// accepted createCalendarEvent does, enumerate the −2d…+60d window
    /// across all calendars, remove every marked hit, verify clean.
    @Test func reapEventOperationsSurviveOnThisRuntime() async throws {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        try #require(granted, "calendar access not granted — pre-grant with simctl privacy")

        let event = EKEvent(eventStore: store)
        event.title = "\(ToolConfirmationCenter.batteryArtifactMarker) Probe lunch"
        event.startDate = Date().addingTimeInterval(3 * 86_400)
        event.endDate = event.startDate.addingTimeInterval(3_600)
        let calendar = try #require(store.defaultCalendarForNewEvents)
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)

        // The reap's exact narrowed query (2026-07-28 crash lane): writable
        // calendars only, −1d…+14d — pinned here so the probe always
        // exercises what the reap actually runs.
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        let predicate = store.predicateForEvents(
            withStart: Date().addingTimeInterval(-1 * 86_400),
            end: Date().addingTimeInterval(14 * 86_400),
            calendars: writable
        )
        let marked = store.events(matching: predicate).filter {
            ($0.title ?? "").contains(ToolConfirmationCenter.batteryArtifactMarker)
        }
        #expect(!marked.isEmpty)

        for found in marked {
            try store.remove(found, span: .thisEvent, commit: true)
        }

        let after = store.events(matching: predicate).filter {
            ($0.title ?? "").contains(ToolConfirmationCenter.batteryArtifactMarker)
        }
        #expect(after.isEmpty)
    }

    /// The reap's reminders step, verbatim: the incomplete-reminders fetch
    /// with marker filtering across the continuation boundary.
    @Test func reapReminderFetchSurvivesOnThisRuntime() async throws {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        try #require(granted, "reminders access not granted — pre-grant with simctl privacy")

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let ids: [String] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: (found ?? [])
                    .filter { ($0.title ?? "").contains(ToolConfirmationCenter.batteryArtifactMarker) }
                    .map(\.calendarItemIdentifier))
            }
        }
        #expect(ids.isEmpty)
    }
}
#endif
