#if DEBUG
import EventKit
import Foundation
import Testing
@testable import Talaria

/// #331 — the PURE half of the dedicated-test-container bars. Nothing here
/// touches the shared EventKit store, so these run in parallel with
/// everything else; the store-mutating bars (331-A, 331-B, 331-D) live in
/// `BatteryReapEventKitProbeTests`, which is `.serialized` because two
/// suites mutating one calendar database race each other.
///
/// The predicate tests are the ones that matter most. This code's failure
/// mode is destroying real user data, and a reap that is too broad is worse
/// than no reap — so `isHarnessOwned` is exercised here against every way a
/// candidate could LOOK like the harness's container without being it.
struct BatteryTestContainerTests {

    // MARK: - 331-C: the scope guard

    private func facts(identifier: String = "owned-id",
                       title: String = BatteryTestContainer.calendarTitle,
                       source: String = "local-source",
                       isDefault: Bool = false,
                       modifiable: Bool = true) -> BatteryTestContainer.CalendarFacts {
        .init(identifier: identifier, title: title, sourceIdentifier: source,
              isDefaultForNewItems: isDefault, allowsContentModifications: modifiable)
    }

    /// The recorded identifier is the primary key: this is the ordinary
    /// case, a container the harness created in this install.
    @Test func aRecordedIdentifierOwnsTheContainer() {
        #expect(BatteryTestContainer.isHarnessOwned(
            facts(),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: "owned-id",
            harnessSourceIdentifier: "local-source"))
    }

    /// **The clause that is the whole item.** A DEFAULT container is never
    /// owned — not even when the identifier the harness recorded points at
    /// it, which is the state a corrupted record would produce. This clause
    /// is unconditional and first, so nothing downstream can reach past it.
    @Test func aDefaultContainerIsNeverOwnedEvenWhenEveryOtherSignalMatches() {
        #expect(!BatteryTestContainer.isHarnessOwned(
            facts(isDefault: true),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: "owned-id",
            harnessSourceIdentifier: "local-source"))
    }

    /// **The widening detector.** Title matching alone must never confer
    /// ownership. If someone later simplifies the predicate to
    /// `facts.title == expectedTitle`, this goes red: same title, wrong
    /// source, no recorded identifier.
    @Test func titleAloneIsNeverEnoughToOwnAContainer() {
        #expect(!BatteryTestContainer.isHarnessOwned(
            facts(identifier: "some-other-id", source: "a-source-we-never-created-on"),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: nil,
            harnessSourceIdentifier: "local-source"))
        // …and with no harness source resolvable at all, orphan adoption is
        // simply unavailable rather than falling back to title.
        #expect(!BatteryTestContainer.isHarnessOwned(
            facts(identifier: "some-other-id"),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: nil,
            harnessSourceIdentifier: nil))
        #expect(!BatteryTestContainer.isHarnessOwned(
            facts(identifier: "some-other-id"),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: nil,
            harnessSourceIdentifier: ""))
    }

    /// Orphan adoption — the path that cleans up after a run whose recorded
    /// identifier was lost — needs the exact title AND the source. A
    /// near-miss title (the user's own "Battery" calendar, a truncation, a
    /// case difference) is not the harness's container.
    @Test func orphanAdoptionNeedsTheExactTitleAndTheHarnessSource() {
        #expect(BatteryTestContainer.isHarnessOwned(
            facts(identifier: "recreated-by-a-crashed-run"),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: nil,
            harnessSourceIdentifier: "local-source"))

        for nearMiss in ["[T27-battery] TEST CALENDAR",
                         BatteryTestContainer.calendarTitle.lowercased(),
                         "Battery",
                         " \(BatteryTestContainer.calendarTitle)"] {
            #expect(!BatteryTestContainer.isHarnessOwned(
                facts(identifier: "recreated-by-a-crashed-run", title: nearMiss),
                expectedTitle: BatteryTestContainer.calendarTitle,
                recordedIdentifier: nil,
                harnessSourceIdentifier: "local-source"), "near-miss title owned: \(nearMiss)")
        }
    }

    /// A read-only calendar (a subscribed/holiday feed) is never ours:
    /// nothing could have been written there, and removing it is not the
    /// harness's business.
    @Test func aReadOnlyContainerIsNeverOwned() {
        #expect(!BatteryTestContainer.isHarnessOwned(
            facts(modifiable: false),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: "owned-id",
            harnessSourceIdentifier: "local-source"))
    }

    /// The two containers must not be able to adopt each other: the reminder
    /// sweep asks for the reminder title and vice versa.
    @Test func theTwoContainersDoNotAdoptEachOther() {
        #expect(!BatteryTestContainer.isHarnessOwned(
            facts(identifier: "unrecorded", title: BatteryTestContainer.reminderListTitle),
            expectedTitle: BatteryTestContainer.calendarTitle,
            recordedIdentifier: nil,
            harnessSourceIdentifier: "local-source"))
        #expect(BatteryTestContainer.expectedTitle(for: .event) == BatteryTestContainer.calendarTitle)
        #expect(BatteryTestContainer.expectedTitle(for: .reminder) == BatteryTestContainer.reminderListTitle)
        #expect(BatteryTestContainer.identifierKey(for: .event) != BatteryTestContainer.identifierKey(for: .reminder))
    }

    /// The contract's "identifiable at a glance as test data": the reap
    /// marker plus a plain-language disposal note, in both titles.
    @Test func containerTitlesAreObviouslyTestData() {
        for title in [BatteryTestContainer.calendarTitle, BatteryTestContainer.reminderListTitle] {
            #expect(title.contains(ToolConfirmationCenter.batteryArtifactMarker))
            #expect(title.contains("safe to delete"))
            #expect(title.uppercased().contains("TEST"))
        }
        #expect(BatteryTestContainer.calendarTitle != BatteryTestContainer.reminderListTitle)
    }

    // MARK: - 331-E: add-only access fails loudly

    /// Full access on both entity types is the only ready state. Everything
    /// else refuses WITH A REASON — a silent skip is the failure mode where
    /// residue accumulates while the suite reports success.
    @Test func readinessIsReadyOnlyForFullAccessOnBothEntities() {
        #expect(BatteryTestContainer.readiness(event: .fullAccess, reminder: .fullAccess) == .ready)

        let notReady: [EKAuthorizationStatus] = [.writeOnly, .denied, .restricted, .notDetermined]
        for status in notReady {
            #expect(BatteryTestContainer.readiness(event: status, reminder: .fullAccess) != .ready,
                    "event \(status.rawValue) must refuse")
            #expect(BatteryTestContainer.readiness(event: .fullAccess, reminder: status) != .ready,
                    "reminder \(status.rawValue) must refuse")
        }
    }

    /// The add-only trap by name: #186 leaves "Add Events Only" reachable,
    /// and that grant can WRITE while never being able to reap. The refusal
    /// says so, because the line a runner reads at 3 AM has to explain
    /// itself.
    @Test func readinessRefusalNamesTheAddOnlyTrap() {
        guard case .refuse(let why) = BatteryTestContainer.readiness(event: .writeOnly, reminder: .fullAccess) else {
            Issue.record("add-only calendar access must refuse")
            return
        }
        #expect(why.contains("add-only"))
        #expect(why.contains("calendar"))
        #expect(why.contains("never reap"))

        guard case .refuse(let reminderWhy) = BatteryTestContainer.readiness(event: .fullAccess, reminder: .denied) else {
            Issue.record("denied reminders access must refuse")
            return
        }
        #expect(reminderWhy.contains("reminders"))
        #expect(reminderWhy.contains("denied"))
    }

    /// The emitted grammar, both arms — a refusal has to be greppable in a
    /// capture log, and it must not be mistakable for a successful reap.
    @Test func containerReapLineGrammarIsStable() {
        var counts = BatteryTestContainer.ReapCounts()
        counts.eventCalendars = 1
        counts.reminderLists = 1
        counts.alarms = 3
        #expect(BatteryTestContainer.reapLine(reason: "start", outcome: .reaped(counts), outsideMarked: 2)
                == "battery: CONTAINER-REAP start calendars=1 lists=1 alarms=3 failures=0 outside-marked=2(not-deleted) (#331)")
        #expect(BatteryTestContainer.reapLine(reason: "finish", outcome: .refused("calendar access is denied"), outsideMarked: 0)
                == "battery: CONTAINER-REFUSED finish — calendar access is denied (#331)")
    }

    // MARK: - 331-F: the alarm ledger is DURABLE

    /// AlarmKit has no container, so the harness's substitute is a ledger of
    /// the IDs it created. The property that matters is DURABILITY: the old
    /// ledger was a process-lifetime `static var`, so a crashed run's alarms
    /// outlived every record of them. Written here, read back through a
    /// FRESH `UserDefaults` reader over the same suite — which is what
    /// "survives the process" reduces to in a test.
    @Test func theAlarmLedgerSurvivesAFreshReader() throws {
        let suiteName = "battery-test-container-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let original = BatteryTestContainer.defaults
        BatteryTestContainer.defaults = defaults
        defer { BatteryTestContainer.defaults = original }

        #expect(BatteryTestContainer.alarmLedger.isEmpty)
        let first = UUID()
        let second = UUID()
        BatteryTestContainer.alarmLedger = [first, second]

        // A different reader over the same persistent domain — the stand-in
        // for the next launch after a crash.
        let freshReader = try #require(UserDefaults(suiteName: suiteName))
        let persisted = freshReader.array(forKey: BatteryTestContainer.alarmLedgerKey) as? [String]
        #expect(persisted == [first.uuidString, second.uuidString])

        // And the API round-trips, in order.
        #expect(BatteryTestContainer.alarmLedger == [first, second])

        // Draining clears the key rather than leaving an empty array behind.
        BatteryTestContainer.alarmLedger = []
        #expect(BatteryTestContainer.alarmLedger.isEmpty)
        #expect(freshReader.array(forKey: BatteryTestContainer.alarmLedgerKey) == nil)
    }

    /// `AlarmService`'s tracked-ID list IS that ledger now — the schedule
    /// path appends through this property, so the durability above is the
    /// durability the alarm write path gets.
    @MainActor
    @Test func theAlarmServiceLedgerIsTheDurableOne() throws {
        let suiteName = "battery-test-container-alarms-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let original = BatteryTestContainer.defaults
        BatteryTestContainer.defaults = defaults
        defer { BatteryTestContainer.defaults = original }

        let id = UUID()
        AlarmService.batteryScheduledAlarmIDs = [id]
        #expect(BatteryTestContainer.alarmLedger == [id])
        #expect((defaults.array(forKey: BatteryTestContainer.alarmLedgerKey) as? [String]) == [id.uuidString])

        AlarmService.batteryScheduledAlarmIDs = []
        #expect(BatteryTestContainer.alarmLedger.isEmpty)
    }

    // MARK: - 331-F': alarm writes are attended-only

    /// **The re-scoped alarm bar (Owen's ruling, 2026-08-11).** Alarms ring
    /// through Silent mode and Focus and have no container to nuke, so the
    /// containment is a person: harness alarm writes are refused unless the
    /// attended flag is armed, and it is armed only by a tap.
    ///
    /// Default-CLOSED is the property that matters — an automated trigger
    /// that never touches the Developer screen cannot schedule one.
    @Test func harnessAlarmWritesAreRefusedUnlessAttended() {
        let marker = ToolConfirmationCenter.batteryArtifactMarker
        // A battery-marked request needs the attended flag.
        #expect(!BatteryTestContainer.alarmWriteIsPermitted(label: "\(marker)", attended: false))
        #expect(!BatteryTestContainer.alarmWriteIsPermitted(label: "wake up \(marker)", attended: false))
        #expect(BatteryTestContainer.alarmWriteIsPermitted(label: "\(marker)", attended: true))
        // A REAL user alarm is never governed by this gate, attended or not.
        #expect(BatteryTestContainer.alarmWriteIsPermitted(label: "wake up", attended: false))
        #expect(BatteryTestContainer.alarmWriteIsPermitted(label: nil, attended: false))
        #expect(BatteryTestContainer.alarmWriteIsPermitted(label: "", attended: false))
    }

    /// The refusal is LOUD: it surfaces as an error with a reason a runner
    /// can read, not as a silent no-op that leaves the run looking clean.
    @Test func theUnattendedAlarmRefusalExplainsItself() {
        let message = AlarmService.AlarmSchedulingError.unattendedHarnessWrite.errorDescription ?? ""
        #expect(message.contains("attended-only"))
        #expect(message.contains("#331"))
        #expect(message.contains("nothing was scheduled"))
    }

    // MARK: - 331-D: the start reap is structural

    /// The chokepoint check that no launcher can skip: `beginBatteryRun` is
    /// async precisely so the compiler forces every one of the battery
    /// wrappers through the reaping form. This exercises the mutex contract
    /// still holding across the added suspension — a claim/refuse race here
    /// would resurrect the #200B concurrent-run contamination.
    @MainActor
    @Test func beginBatteryRunStillHoldsTheMutexAcrossTheStartReap() async {
        LocalChatBackend.endBatteryRun()
        #expect(await LocalChatBackend.beginBatteryRun())
        #expect(!(await LocalChatBackend.beginBatteryRun()))
        LocalChatBackend.endBatteryRun()
        #expect(await LocalChatBackend.beginBatteryRun())
        LocalChatBackend.endBatteryRun()
    }

    /// The armed mirror the start gate reads. It has to track the flag the
    /// launchers actually set, or a writing run could start without the
    /// containment check.
    @MainActor
    @Test func theArmedMirrorTracksTheAutoAcceptFlag() {
        let center = ToolConfirmationCenter()
        center.autoAcceptForBattery = true
        #expect(ToolConfirmationCenter.batteryWritesArmed)
        center.autoAcceptForBattery = false
        #expect(!ToolConfirmationCenter.batteryWritesArmed)
    }
}
#endif
