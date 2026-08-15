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
///
/// **`.serialized` since #331.** Every test in here MUTATES the one shared
/// EventKit database, and several of them seed a `[T27-battery]`-marked item
/// and then run a sweep that matches on that marker. Run in parallel they
/// delete each other's fixtures — a failure that looks exactly like the
/// product defect #331's negative bar exists to detect. Any future test that
/// writes to the real store belongs in THIS suite for the same reason.
@Suite(.serialized)
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
        // @Sendable mirrors the reap's real completion shape — the fix for
        // the device-only isolation trap (the sim runtime doesn't enforce
        // the check, so this probe cannot RED on it; run-5 on device is
        // the fix's verifier, this pins the op shape).
        let ids: [String] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { @Sendable found in
                continuation.resume(returning: (found ?? [])
                    .filter { ($0.title ?? "").contains(ToolConfirmationCenter.batteryArtifactMarker) }
                    .map(\.calendarItemIdentifier))
            }
        }
        #expect(ids.isEmpty)
    }

    // MARK: - #331: the dedicated test container, against the real store

    /// Grants both entity types or skips the bar visibly. Never a silent
    /// pass: a container test that cannot see the store proves nothing.
    private func requireFullAccess(_ store: EKEventStore) async throws {
        try #require((try? await store.requestFullAccessToEvents()) ?? false,
                     "calendar access not granted — pre-grant with simctl privacy")
        try #require((try? await store.requestFullAccessToReminders()) ?? false,
                     "reminders access not granted — pre-grant with simctl privacy")
    }

    /// Removes whatever the harness owns, so each bar starts from a known
    /// state and leaves none behind.
    private func clearContainers() {
        _ = BatteryTestContainer.reap(reason: "test-fixture")
    }

    /// **331-B — THE NEGATIVE BAR, and the whole point of this item.**
    ///
    /// Seed the worst case: a `[T27-battery]`-marked event in the user's
    /// DEFAULT calendar and a marked reminder in the DEFAULT list. That is
    /// precisely what the pre-#331 teardown deleted — its sweep matched the
    /// marker across every writable calendar — so this test is RED against
    /// the old behaviour and green only because the destroying step is now
    /// scoped to containers the harness owns.
    ///
    /// Then run the COMPLETE destroying surface a real run runs at teardown,
    /// through the shipped functions rather than copies of them, and assert
    /// both canaries are still there.
    @Test func defaultCalendarAndListSurviveTheWholeDestroyingSurface() async throws {
        let store = EKEventStore()
        try await requireFullAccess(store)
        clearContainers()
        defer { clearContainers() }

        let marker = ToolConfirmationCenter.batteryArtifactMarker

        // The default-calendar canary.
        let defaultCalendar = try #require(store.defaultCalendarForNewEvents)
        let canaryEvent = EKEvent(eventStore: store)
        canaryEvent.title = "\(marker) #331 default-calendar canary"
        canaryEvent.startDate = Date().addingTimeInterval(2 * 86_400)
        canaryEvent.endDate = canaryEvent.startDate.addingTimeInterval(1_800)
        canaryEvent.calendar = defaultCalendar
        try store.save(canaryEvent, span: .thisEvent, commit: true)
        let canaryEventID = canaryEvent.eventIdentifier
        defer { if let stale = store.event(withIdentifier: canaryEventID ?? "") {
            try? store.remove(stale, span: .thisEvent, commit: true)
        } }

        // The default-list canary.
        let defaultList = try #require(store.defaultCalendarForNewReminders())
        let canaryReminder = EKReminder(eventStore: store)
        canaryReminder.title = "\(marker) #331 default-list canary"
        canaryReminder.calendar = defaultList
        try store.save(canaryReminder, commit: true)
        let canaryReminderID = canaryReminder.calendarItemIdentifier
        defer { if let stale = store.calendarItem(withIdentifier: canaryReminderID) as? EKReminder {
            try? store.remove(stale, commit: true)
        } }

        // Give the reap real work to do inside its own container, so a green
        // result cannot be "the reap did nothing at all".
        let container = try BatteryTestContainer.ensureContainer(for: .event, in: store)
        #expect(container.calendarIdentifier != defaultCalendar.calendarIdentifier)
        let disposable = EKEvent(eventStore: store)
        disposable.title = "\(marker) #331 disposable"
        disposable.startDate = Date().addingTimeInterval(2 * 86_400)
        disposable.endDate = disposable.startDate.addingTimeInterval(1_800)
        disposable.calendar = container
        try store.save(disposable, span: .thisEvent, commit: true)
        let disposableID = disposable.eventIdentifier

        // The complete destroying surface, through the SHIPPED functions.
        _ = await LocalChatBackend.sweepMarkedRemindersAndEvents(emitSteps: false)
        let outcome = BatteryTestContainer.reap(reason: "test")
        #expect(outcome.counts != nil, "the reap refused — the bar cannot be scored")

        // THE BAR: neither default-container canary was touched.
        let after = EKEventStore()
        #expect(after.event(withIdentifier: canaryEventID ?? "") != nil,
                "the reap deleted an event from the user's DEFAULT calendar")
        #expect(after.calendarItem(withIdentifier: canaryReminderID) != nil,
                "the reap deleted a reminder from the user's DEFAULT list")
        // …and the default containers themselves are still standing.
        #expect(after.defaultCalendarForNewEvents?.calendarIdentifier == defaultCalendar.calendarIdentifier)
        #expect(after.defaultCalendarForNewReminders()?.calendarIdentifier == defaultList.calendarIdentifier)
        // …while the harness's own artifact is gone, container and all.
        #expect(after.event(withIdentifier: disposableID ?? "") == nil)
        #expect(BatteryTestContainer.ownedContainers(for: .event, in: after).isEmpty)
    }

    /// **331-C (live) — the delete is WHOLESALE.** Several items go into the
    /// container; ONE `removeCalendar` takes the calendar and every item in
    /// it. Per-item reaping is the thing that fails when a run dies
    /// mid-flight, so "the items are gone because the container is gone" is
    /// the property, not "the items were each found and removed".
    @Test func theContainerReapRemovesTheCalendarAndEverythingInIt() async throws {
        let store = EKEventStore()
        try await requireFullAccess(store)
        clearContainers()
        defer { clearContainers() }

        let container = try BatteryTestContainer.ensureContainer(for: .event, in: store)
        var ids: [String] = []
        for index in 0..<3 {
            let event = EKEvent(eventStore: store)
            // Deliberately UNMARKED: only the container membership can
            // explain their removal, so a marker sweep cannot take credit.
            event.title = "#331 wholesale \(index)"
            event.startDate = Date().addingTimeInterval(Double(index + 1) * 86_400)
            event.endDate = event.startDate.addingTimeInterval(900)
            event.calendar = container
            try store.save(event, span: .thisEvent, commit: true)
            ids.append(try #require(event.eventIdentifier))
        }

        let outcome = BatteryTestContainer.reap(reason: "test")
        #expect(outcome.counts?.eventCalendars == 1)

        let after = EKEventStore()
        for id in ids {
            #expect(after.event(withIdentifier: id) == nil, "unmarked container item survived: \(id)")
        }
        #expect(after.calendars(for: .event).allSatisfy { $0.calendarIdentifier != container.calendarIdentifier })
    }

    /// **331-A — harness writes land in the container, never in the
    /// default.** Drives the SHIPPED create engines with the gate armed, and
    /// reads back where the artifact actually landed.
    @Test func harnessWritesLandInTheContainerAndNotInTheDefault() async throws {
        let store = EKEventStore()
        try await requireFullAccess(store)
        clearContainers()
        defer { clearContainers() }

        let center = ToolConfirmationCenter()
        center.autoAcceptForBattery = true
        defer { center.autoAcceptForBattery = false }

        let eventReply = await CalendarEventTool.performCreate(
            rawTitle: "#331 armed event", rawStartsAt: "2026-12-01T12:00",
            rawMinutes: 30, rawLocation: "", confirmations: center)
        #expect(eventReply.hasPrefix("Added"), "create failed: \(eventReply)")

        // The reminder engine's list argument names a REAL list on purpose:
        // containment a generated argument can steer out of is not
        // containment, so the container has to beat the requested list.
        let defaultList = try #require(store.defaultCalendarForNewReminders())
        let reminderReply = await ReminderCreateTool.performCreate(
            rawTitle: "#331 armed reminder", rawDue: "", rawList: defaultList.title,
            relay: ToolEventRelay(), confirmations: center)
        #expect(reminderReply.hasPrefix("Created reminder"), "create failed: \(reminderReply)")

        let after = EKEventStore()
        let eventContainer = try #require(BatteryTestContainer.existingContainer(for: .event, in: after))
        let listContainer = try #require(BatteryTestContainer.existingContainer(for: .reminder, in: after))
        #expect(eventContainer.calendarIdentifier != after.defaultCalendarForNewEvents?.calendarIdentifier)
        #expect(listContainer.calendarIdentifier != after.defaultCalendarForNewReminders()?.calendarIdentifier)
        #expect(listContainer.calendarIdentifier != defaultList.calendarIdentifier)

        // The event is IN the container. The window brackets the staged
        // start narrowly: EventKit's event predicate is documented to work
        // over spans of a few years, and a decades-wide one comes back
        // empty rather than erroring — a false negative that reads exactly
        // like a containment failure.
        let staged = try #require(DeviceActionParsing.parseDateTime("2026-12-01T12:00"))
        let predicate = after.predicateForEvents(
            withStart: staged.addingTimeInterval(-86_400),
            end: staged.addingTimeInterval(86_400),
            calendars: [eventContainer])
        #expect(after.events(matching: predicate).contains { ($0.title ?? "").contains("#331 armed event") })

        // …and the reminder is in the container list, not the real one.
        let reminderPredicate = after.predicateForReminders(in: [listContainer])
        let titles: [String] = await withCheckedContinuation { continuation in
            after.fetchReminders(matching: reminderPredicate) { @Sendable found in
                continuation.resume(returning: (found ?? []).map { $0.title ?? "" })
            }
        }
        #expect(titles.contains { $0.contains("#331 armed reminder") })
    }

    /// **331-G — production is unchanged with the harness off.** Same
    /// engines, gate NOT armed: the event resolves the user's default
    /// calendar exactly as before, and no container is provisioned.
    @Test func writesWithTheHarnessOffStillLandInTheDefaultCalendar() async throws {
        let store = EKEventStore()
        try await requireFullAccess(store)
        clearContainers()
        defer { clearContainers() }

        let center = ToolConfirmationCenter()
        #expect(!center.autoAcceptForBattery)
        // The gate is not armed, so approve the card the engine stages.
        let create = Task { @MainActor in
            await CalendarEventTool.performCreate(
                rawTitle: "#331 production event", rawStartsAt: "2026-12-02T12:00",
                rawMinutes: 30, rawLocation: "", confirmations: center)
        }
        while center.pending == nil { await Task.yield() }
        center.approve()
        let reply = await create.value
        let defaultCalendar = try #require(store.defaultCalendarForNewEvents)
        #expect(reply.contains("to \"\(defaultCalendar.title)\"."), "unexpected reply: \(reply)")
        #expect(BatteryTestContainer.existingContainer(for: .event, in: EKEventStore()) == nil,
                "the harness provisioned a container on a production write")

        // Clean up the production canary we just made in the real calendar.
        let staged = try #require(DeviceActionParsing.parseDateTime("2026-12-02T12:00"))
        let after = EKEventStore()
        let predicate = after.predicateForEvents(
            withStart: staged.addingTimeInterval(-86_400),
            end: staged.addingTimeInterval(86_400),
            calendars: [try #require(after.defaultCalendarForNewEvents)])
        for stale in after.events(matching: predicate)
        where (stale.title ?? "").contains("#331 production event") {
            try? after.remove(stale, span: .thisEvent, commit: true)
        }
    }

    /// **331-D — reap on START, so a CRASHED previous run is harmless.**
    /// Provision a container and abandon it, exactly as a run killed
    /// mid-flight would; then start the next run through the same chokepoint
    /// every battery passes through, and find it gone before the first
    /// trial.
    @Test func aCrashedRunsContainerIsGoneAfterTheNextRunBegins() async throws {
        let store = EKEventStore()
        try await requireFullAccess(store)
        clearContainers()
        defer { clearContainers() }

        let container = try BatteryTestContainer.ensureContainer(for: .event, in: store)
        let stranded = EKEvent(eventStore: store)
        stranded.title = "\(ToolConfirmationCenter.batteryArtifactMarker) #331 stranded by a crash"
        stranded.startDate = Date().addingTimeInterval(86_400)
        stranded.endDate = stranded.startDate.addingTimeInterval(900)
        stranded.calendar = container
        try store.save(stranded, span: .thisEvent, commit: true)
        let strandedID = try #require(stranded.eventIdentifier)
        // …and an alarm ID the crashed run never got to cancel.
        AlarmService.batteryScheduledAlarmIDs = [UUID()]

        // No teardown ran. The next run simply starts.
        LocalChatBackend.endBatteryRun()
        #expect(await LocalChatBackend.beginBatteryRun())
        LocalChatBackend.endBatteryRun()

        let after = EKEventStore()
        #expect(after.event(withIdentifier: strandedID) == nil, "the stranded event survived the start reap")
        #expect(BatteryTestContainer.ownedContainers(for: .event, in: after).isEmpty)
        #expect(AlarmService.batteryScheduledAlarmIDs.isEmpty, "the stranded alarm ledger survived the start reap")
    }

    /// Residue OUTSIDE a container is counted and reported, never deleted.
    /// A pre-#331 build's leftovers are something to tell the owner about;
    /// deleting from their calendar is the thing this item exists to
    /// prevent.
    @Test func markedResidueOutsideTheContainerIsCountedAndLeftAlone() async throws {
        let store = EKEventStore()
        try await requireFullAccess(store)
        clearContainers()
        defer { clearContainers() }

        let defaultCalendar = try #require(store.defaultCalendarForNewEvents)
        let residue = EKEvent(eventStore: store)
        residue.title = "\(ToolConfirmationCenter.batteryArtifactMarker) #331 pre-container residue"
        residue.startDate = Date().addingTimeInterval(3 * 86_400)
        residue.endDate = residue.startDate.addingTimeInterval(900)
        residue.calendar = defaultCalendar
        try store.save(residue, span: .thisEvent, commit: true)
        let residueID = try #require(residue.eventIdentifier)
        defer { if let stale = EKEventStore().event(withIdentifier: residueID) {
            try? EKEventStore().remove(stale, span: .thisEvent, commit: true)
        } }

        #expect(BatteryTestContainer.markedEventsOutsideContainers(in: EKEventStore()) >= 1)
        _ = BatteryTestContainer.reap(reason: "test")
        #expect(EKEventStore().event(withIdentifier: residueID) != nil,
                "outside-container residue was deleted — it must only be counted")
    }
}
#endif
