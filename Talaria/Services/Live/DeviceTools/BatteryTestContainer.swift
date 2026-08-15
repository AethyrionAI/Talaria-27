#if DEBUG
import EventKit
import Foundation
import os

/// #331 — THE DEDICATED TEST CONTAINER for battery calendar / reminder /
/// alarm writes. DEBUG-only in every byte: this whole file compiles out of
/// Release, so production behaviour is unchanged by construction.
///
/// **Why this exists.** `runActionBattery` and ~20 siblings arm
/// `autoAcceptForBattery` and perform REAL EventKit and AlarmKit writes,
/// reaped only at the DONE line. An interrupted run — a crash, a dropped
/// cable, a killed test host, an overnight reboot — therefore left residue in
/// the owner's own calendar and reminders. That is survivable while a human
/// watches and is not survivable unattended, and it is the one thing gating
/// unattended device running (`planning/DEVICE-BACKLOG-TRIAGE-2026-08-11.md`
/// §5).
///
/// **The shape Owen ruled.** Test writes land in a dedicated calendar and a
/// dedicated reminders list, created here if absent and obviously test data
/// at a glance. The reap nukes the CONTAINER wholesale — one
/// `removeCalendar`, never item-by-item, because per-item reaping is exactly
/// what fails when a run dies mid-flight. It runs on START as well as on
/// finish: start-of-run cleanup is the half that makes a *previous* crashed
/// run harmless, and abort-time reaping cannot provide it.
///
/// **The safety property, which is the whole item.** The user's default
/// calendar and default reminders list are never written to and never deleted
/// from. That is asserted, not assumed: `isHarnessOwned` is a pure predicate
/// over explicit facts whose FIRST clause rejects any default container
/// unconditionally, and `BatteryTestContainerTests` seeds a marker-carrying
/// item in the real default calendar and proves it survives a reap. A reap
/// that is too broad is worse than no reap.
enum BatteryTestContainer {

    private static let log = Logger(subsystem: "org.aethyrion.talaria",
                                    category: "BatteryTestContainer")

    // MARK: - Identity

    /// The dedicated calendar's title. Carries the same `[T27-battery]`
    /// marker the artifacts do, plus a plain-language disposal note — the
    /// contract's "identifiable at a glance as test data".
    static let calendarTitle = "\(ToolConfirmationCenter.batteryArtifactMarker) TEST CALENDAR — safe to delete"

    /// The dedicated reminders list's title. Same rules.
    static let reminderListTitle = "\(ToolConfirmationCenter.batteryArtifactMarker) TEST REMINDERS — safe to delete"

    /// Where the harness records the identity of what it created. These are
    /// the STABLE IDENTIFIERS the reap keys on; title is never sufficient on
    /// its own (see `isHarnessOwned`).
    static let calendarIdentifierKey = "battery.testContainer.eventCalendarIdentifier"
    static let reminderListIdentifierKey = "battery.testContainer.reminderListIdentifier"
    /// #331 alarm answer: AlarmKit has no container, so the harness keeps a
    /// DURABLE ledger of the alarm IDs it created (see `alarmLedger`).
    static let alarmLedgerKey = "battery.testContainer.alarmIDs"

    /// Injectable so tests can round-trip the ledger and the recorded
    /// identifiers through a throwaway suite instead of the app's real
    /// defaults. Production (such as it is — this file is DEBUG-only) uses
    /// `.standard`.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    // MARK: - Readiness (the add-only trap)

    /// The reap needs FULL access: `.writeOnly` ("Add Events Only", which
    /// #186 leaves reachable) can save an event but can never enumerate or
    /// remove one. A harness that wrote under add-only access would
    /// accumulate residue while the suite reported success — so this maps the
    /// auth state to a decision, and the callers REFUSE rather than skip.
    enum Readiness: Equatable {
        case ready
        /// Carries the reason, so the refusal line names what is wrong.
        case refuse(String)
    }

    /// Pure. `.fullAccess` on BOTH entity types is the only ready state:
    /// the harness writes events and reminders alike, and a container it can
    /// create but not delete is worse than no container.
    static func readiness(event: EKAuthorizationStatus,
                          reminder: EKAuthorizationStatus) -> Readiness {
        if let why = refusalReason(status: event, entity: "calendar") { return .refuse(why) }
        if let why = refusalReason(status: reminder, entity: "reminders") { return .refuse(why) }
        return .ready
    }

    private static func refusalReason(status: EKAuthorizationStatus, entity: String) -> String? {
        switch status {
        case .fullAccess:
            return nil
        case .writeOnly:
            // The specific trap this bar exists for: add-only CAN write and
            // CANNOT reap, which is the residue-accumulating combination.
            return "\(entity) access is add-only — the harness could write but never reap"
        case .denied:
            return "\(entity) access is denied"
        case .restricted:
            return "\(entity) access is restricted"
        case .notDetermined:
            return "\(entity) access is not determined"
        @unknown default:
            return "\(entity) access is in an unknown state"
        }
    }

    /// The live readiness, read from `EKEventStore`'s CLASS-level status.
    /// Deliberately never calls `requestFullAccess…`: a prompt from inside a
    /// reap would block a headless run forever (the fresh-simulator hang), so
    /// the harness asks only what it can answer without a UI.
    static func liveReadiness() -> Readiness {
        readiness(event: EKEventStore.authorizationStatus(for: .event),
                  reminder: EKEventStore.authorizationStatus(for: .reminder))
    }

    // MARK: - Ownership — the provably-scoped predicate

    /// Everything the ownership decision is allowed to read, as plain
    /// values. Passing facts rather than an `EKCalendar` is what makes the
    /// predicate testable without a store, and what makes a widening of the
    /// predicate visible in a diff.
    struct CalendarFacts: Equatable {
        let identifier: String
        let title: String
        let sourceIdentifier: String
        /// True when this calendar is the store's default for new events or
        /// new reminders — the user's own container.
        let isDefaultForNewItems: Bool
        let allowsContentModifications: Bool
    }

    /// **The scope guard.** True only for a container the harness itself owns.
    ///
    /// Clause order is load-bearing:
    /// 1. a DEFAULT container is never owned, whatever else matches — this is
    ///    unconditional and comes first, so no later clause can reach past it;
    /// 2. a read-only container is never owned (nothing could have been
    ///    written there, and removing it is not ours to do);
    /// 3. the primary key is the identifier the harness RECORDED at creation;
    /// 4. orphan adoption — for a container left by a run whose recorded
    ///    identifier was lost — requires an EXACT title match against our own
    ///    constant **and** a source match. Title alone is never sufficient,
    ///    and `BatteryTestContainerTests` fails if it ever becomes so.
    static func isHarnessOwned(_ facts: CalendarFacts,
                               expectedTitle: String,
                               recordedIdentifier: String?,
                               harnessSourceIdentifier: String?) -> Bool {
        guard !facts.isDefaultForNewItems else { return false }
        guard facts.allowsContentModifications else { return false }
        if let recordedIdentifier, facts.identifier == recordedIdentifier { return true }
        guard let harnessSourceIdentifier, !harnessSourceIdentifier.isEmpty else { return false }
        return facts.title == expectedTitle && facts.sourceIdentifier == harnessSourceIdentifier
    }

    /// Lifts a live `EKCalendar` into the facts the predicate reads. The
    /// default-ness question is asked of BOTH default slots, because a
    /// reminders list and an events calendar come out of the same type.
    static func facts(for calendar: EKCalendar, in store: EKEventStore) -> CalendarFacts {
        let defaultEvent = store.defaultCalendarForNewEvents?.calendarIdentifier
        let defaultReminder = store.defaultCalendarForNewReminders()?.calendarIdentifier
        let identifier = calendar.calendarIdentifier
        return CalendarFacts(
            identifier: identifier,
            title: calendar.title,
            sourceIdentifier: calendar.source?.sourceIdentifier ?? "",
            isDefaultForNewItems: identifier == defaultEvent || identifier == defaultReminder,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    // MARK: - Provisioning

    enum ProvisioningError: LocalizedError {
        case notReady(String)
        case noUsableSource(EKEntityType)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .notReady(let why): return why
            case .noUsableSource(let type):
                return "no writable source is available for \(type == .event ? "calendars" : "reminder lists")"
            case .saveFailed(let message): return message
            }
        }
    }

    /// The source the harness creates on. Local first (a container that lives
    /// only on this device is the honest home for throwaway test data); the
    /// default container's own source as the fallback, because a device with
    /// only a CalDAV account has no local source at all.
    static func preferredSource(for entity: EKEntityType, in store: EKEventStore) -> EKSource? {
        if let local = store.sources.first(where: { $0.sourceType == .local }) { return local }
        let fallback = entity == .event
            ? store.defaultCalendarForNewEvents?.source
            : store.defaultCalendarForNewReminders()?.source
        if let fallback { return fallback }
        return store.sources.first { !$0.calendars(for: entity).isEmpty }
    }

    /// Returns the harness's container for `entity`, creating it if absent.
    /// Idempotent: an existing owned container is returned untouched, so the
    /// per-trial write path pays a lookup and not a create.
    static func ensureContainer(for entity: EKEntityType,
                                in store: EKEventStore) throws -> EKCalendar {
        if case .refuse(let why) = liveReadiness() { throw ProvisioningError.notReady(why) }
        if let existing = existingContainer(for: entity, in: store) { return existing }

        guard let source = preferredSource(for: entity, in: store) else {
            throw ProvisioningError.noUsableSource(entity)
        }
        let calendar = EKCalendar(for: entity, eventStore: store)
        calendar.title = entity == .event ? calendarTitle : reminderListTitle
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw ProvisioningError.saveFailed(error.localizedDescription)
        }
        defaults.set(calendar.calendarIdentifier, forKey: identifierKey(for: entity))
        log.notice("#331 created test container \(calendar.title, privacy: .public) id=\(calendar.calendarIdentifier, privacy: .public)")
        return calendar
    }

    static func identifierKey(for entity: EKEntityType) -> String {
        entity == .event ? calendarIdentifierKey : reminderListIdentifierKey
    }

    static func expectedTitle(for entity: EKEntityType) -> String {
        entity == .event ? calendarTitle : reminderListTitle
    }

    /// Every live container the harness owns for `entity` — normally one, but
    /// a plural result is what makes orphan adoption able to clean up after a
    /// run whose recorded identifier was lost.
    static func ownedContainers(for entity: EKEntityType, in store: EKEventStore) -> [EKCalendar] {
        let recorded = defaults.string(forKey: identifierKey(for: entity))
        let sourceIdentifier = preferredSource(for: entity, in: store)?.sourceIdentifier
        return store.calendars(for: entity).filter {
            isHarnessOwned(facts(for: $0, in: store),
                           expectedTitle: expectedTitle(for: entity),
                           recordedIdentifier: recorded,
                           harnessSourceIdentifier: sourceIdentifier)
        }
    }

    static func existingContainer(for entity: EKEntityType, in store: EKEventStore) -> EKCalendar? {
        ownedContainers(for: entity, in: store).first
    }

    // MARK: - The wholesale reap

    struct ReapCounts: Equatable {
        /// Containers removed, by entity. One `removeCalendar` each; the
        /// items inside go with them.
        var eventCalendars = 0
        var reminderLists = 0
        var alarms = 0
        var failures = 0

        var summary: String {
            "calendars=\(eventCalendars) lists=\(reminderLists) alarms=\(alarms) failures=\(failures)"
        }
    }

    enum ReapOutcome: Equatable {
        case reaped(ReapCounts)
        /// The harness cannot clean up. Callers that are about to WRITE must
        /// treat this as a hard stop, never as a skip.
        case refused(String)

        var counts: ReapCounts? {
            if case .reaped(let counts) = self { return counts }
            return nil
        }
    }

    /// **The reap.** Removes every container the harness owns, WHOLESALE —
    /// `removeCalendar` takes the calendar and everything in it in one store
    /// operation, so a run that died mid-flight leaves nothing that has to be
    /// enumerated to be cleaned. Also drains the alarm ledger.
    ///
    /// Nothing outside an owned container is ever removed. Items the harness
    /// finds outside one are COUNTED and reported (see
    /// `markedEventsOutsideContainers`), never deleted — residue from a
    /// pre-#331 build is a thing to tell the owner about, not a licence to
    /// delete from their calendar.
    ///
    /// `includeAlarms` is false at the FINISH site only, where #200's
    /// `reapBatteryArtifacts` already runs the alarm step and folds its
    /// counts into the pinned `REAP` line — draining the ledger twice would
    /// make that line silently under-report.
    @MainActor
    static func reap(reason: String, includeAlarms: Bool = true) -> ReapOutcome {
        if case .refuse(let why) = liveReadiness() { return .refused(why) }
        let store = EKEventStore()
        var counts = ReapCounts()

        for entity in [EKEntityType.event, .reminder] {
            for container in ownedContainers(for: entity, in: store) {
                do {
                    try store.removeCalendar(container, commit: true)
                    if entity == .event { counts.eventCalendars += 1 } else { counts.reminderLists += 1 }
                } catch {
                    log.notice("#331 reap failed for \(container.title, privacy: .public): \(String(describing: error), privacy: .public)")
                    counts.failures += 1
                }
            }
            defaults.removeObject(forKey: identifierKey(for: entity))
        }

        if includeAlarms {
            let alarmSweep = AlarmService.reapBatteryAlarms()
            counts.alarms = alarmSweep.cancelled
            counts.failures += alarmSweep.failed
        }

        log.notice("#331 reap(\(reason, privacy: .public)) \(counts.summary, privacy: .public)")
        return .reaped(counts)
    }

    /// Read-only census of `[T27-battery]`-marked EVENTS living outside the
    /// harness's containers — pre-#331 residue, or an artifact that escaped.
    /// **Counts, never deletes.** The count is what the run reports so the
    /// owner can clear them by hand; deleting from their calendar is the
    /// thing this whole item exists to prevent.
    static func markedEventsOutsideContainers(in store: EKEventStore) -> Int {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return 0 }
        let owned = Set(ownedContainers(for: .event, in: store).map(\.calendarIdentifier))
        let writable = store.calendars(for: .event).filter {
            $0.allowsContentModifications && !owned.contains($0.calendarIdentifier)
        }
        guard !writable.isEmpty else { return 0 }
        let predicate = store.predicateForEvents(
            withStart: Date().addingTimeInterval(-1 * 86_400),
            end: Date().addingTimeInterval(14 * 86_400),
            calendars: writable
        )
        return store.events(matching: predicate)
            .filter { ($0.title ?? "").contains(ToolConfirmationCenter.batteryArtifactMarker) }
            .count
    }

    /// The #331 line the run emits. Separate from #200's `REAP` line, whose
    /// grammar is pinned byte-for-byte by `BatteryRunStoreTests`.
    static func reapLine(reason: String, outcome: ReapOutcome, outsideMarked: Int) -> String {
        switch outcome {
        case .reaped(let counts):
            return "battery: CONTAINER-REAP \(reason) \(counts.summary) outside-marked=\(outsideMarked)(not-deleted) (#331)"
        case .refused(let why):
            return "battery: CONTAINER-REFUSED \(reason) — \(why) (#331)"
        }
    }

    // MARK: - The alarm answer: a durable ID ledger

    /// #331 — **alarms have no container, and this does not pretend one
    /// exists.** AlarmKit has no per-list concept, and — re-verified against
    /// the beta5 SDK rather than recalled — `public struct Alarm` carries
    /// `id` / `schedule` / `countdownDuration` / `state` and no label or
    /// metadata, so enumeration cannot tell a battery alarm from a real
    /// `/alarm` one. Name-based sweeping is therefore impossible, and
    /// `sweepAllTalariaAlarms` (which kills the user's real alarms too) stays
    /// nuclear and user-invoked.
    ///
    /// What replaces the container is a DURABLE ledger of the IDs the
    /// harness created: written BEFORE the schedule call and drained at the
    /// start reap and the finish reap. The old ledger was a process-lifetime
    /// `static var`, so a crashed run's alarms outlived every record of them
    /// and had to be cleaned by hand.
    ///
    /// **The ledger is residue HYGIENE and it is not a safety story — read
    /// `alarmWritesAttended` for the actual containment.** A sweep at the
    /// next run's start cannot un-ring an alarm that fires before that
    /// start, and an AlarmKit alarm rings through Silent mode and Focus. No
    /// amount of cleverness in the sweep closes that; only a person present
    /// does.
    static var alarmLedger: [UUID] {
        get { (defaults.array(forKey: alarmLedgerKey) as? [String] ?? []).compactMap(UUID.init(uuidString:)) }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: alarmLedgerKey)
            } else {
                defaults.set(newValue.map(\.uuidString), forKey: alarmLedgerKey)
            }
        }
    }

    /// **#331 re-scoped, 2026-08-11 — the alarm containment, and it is a
    /// person rather than a predicate.**
    ///
    /// Owen's ruling narrowed this item the day it was built: on his phone,
    /// test reminders and test calendar writes are FINE (he has already
    /// pointed the app at a calendar he does not care about, unshared, and
    /// "I'm not worried about stragglers"). Alarms are the one live
    /// constraint — *"please don't have surprise alarms for me while I'm at
    /// work"* — and they are different in kind from the other two for two
    /// reasons that no engineering closes:
    ///
    /// 1. **An alarm rings through Silent mode and Focus.** A stray calendar
    ///    event is invisible until someone looks; a stray alarm interrupts a
    ///    meeting.
    /// 2. **There is no container to nuke** (see `alarmLedger`), so the only
    ///    cleanup is a sweep at the NEXT run's start — which is too late by
    ///    definition for any alarm that fires in between.
    ///
    /// So the rule is not "sweep harder", it is **harness alarm writes never
    /// run unattended**. This flag is default-CLOSED and is armed only by a
    /// tap in the Developer screen — a tap being the one signal in this app
    /// that a human is present. `AlarmService.schedule` throws
    /// `unattendedHarnessWrite` for any battery-marked request while it is
    /// false, so an automated trigger cannot schedule one by accident, and
    /// the refusal is loud rather than silent.
    nonisolated(unsafe) static var alarmWritesAttended = false

    /// Pure form of the rule above, so it is pinned by test rather than
    /// only by reading `AlarmService.schedule`. A REAL user alarm is always
    /// permitted — this gate governs the harness and nothing else; the
    /// discriminator is the reap marker the auto-accept gate injects into
    /// the label.
    static func alarmWriteIsPermitted(label: String?, attended: Bool) -> Bool {
        guard label?.contains(ToolConfirmationCenter.batteryArtifactMarker) == true else { return true }
        return attended
    }
}
#endif
