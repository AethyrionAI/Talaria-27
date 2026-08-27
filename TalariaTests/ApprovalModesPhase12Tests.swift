import Foundation
import SwiftUI
import Testing
@testable import Talaria

// #224 Phases 1+2 — bars 224-1A … 224-1E and 224-2A … 224-2D, pre-registered
// in OPEN_ITEMS #224 on 2026-08-26 before any code was written.
//
// Phase 0 (2026-08-11) shipped the TYPE and the caution layer and left both
// unreachable. This lane makes `.smart` and `.off` real: the Privacy screen's
// `// Agent Actions` control, `.autoApprove`, and Off's floor.
//
// Three things these tests deliberately do NOT do, each because a ruling says
// so: they never construct a `LanguageModelSession` (ruling 5, and 224-2B is
// the pin), they never assert a transcript receipt for an auto-approved action
// (ruling 7 — DEFERRED, nothing of Phase 3 is built), and they never touch the
// HOST's `approvals.mode` (`ServerSettingsScreen`'s picker, #224-APP, a
// different actor with its own tests).

/// The same compile-time discriminator `Phase0ActionCautionTests` carries, for
/// the same reason (#332-a): a source-reading bar is scorable only where the
/// test process shares the Mac's filesystem.
private let repoSourcesAreReadable: Bool = {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
}()

// MARK: - Shared waiting machinery

/// A tool call whose outcome a test can OBSERVE without awaiting it.
///
/// Awaiting `Task.value` on a call that has parked on the confirm gate can
/// never return — a non-throwing `value` is not cancellation-responsive, so
/// even a racing task group hangs. Every RED run of this file's bars parks
/// exactly that way (the pre-change gate stages a card where the bar expects a
/// refusal), so the box is not a nicety: without it, witnessing RED means
/// hanging the suite, which is Phase 0's finding 3 happening again.
@MainActor
private final class Pending<T> {
    private(set) var outcome: T?
    private(set) var isSettled = false
    init(_ operation: @escaping @MainActor () async -> T) {
        Task { @MainActor in
            self.outcome = await operation()
            self.isSettled = true
        }
    }
}

/// Pumps on a WALL CLOCK — never a yield count — until the call settles.
/// Returns nil if it never did, and the caller must then NOT await it.
/// (Phase 0 measured a card arriving 3.4 s after a 2,000-yield budget expired
/// on a loaded host: a yield count is not a clock.)
@MainActor
private func settled<T: Sendable>(
    _ pending: Pending<T>, within timeout: Duration = .seconds(20)
) async -> T? {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !pending.isSettled, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
    return pending.isSettled ? pending.outcome : nil
}

/// Waits for a card, on the same wall clock, and reports whether one arrived.
@MainActor
private func stagedCardArrived(
    _ center: ToolConfirmationCenter, within timeout: Duration = .seconds(20)
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while center.pending == nil, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
    return center.pending != nil
}

/// Lets the tool's Task run far enough to have staged a card if it were going
/// to, where the assertion is that one did NOT.
@MainActor
private func quiesce(_ duration: Duration = .milliseconds(150)) async {
    try? await Task.sleep(for: duration)
}

// MARK: - 224-1A — the default survives the widening

@MainActor
struct ApprovalModeSettingsTests {

    /// 224-1A. `.manual` for a fresh install and for a blob written before the
    /// key existed. This half is UNCHANGED from Phase 0 and must stay so: the
    /// whole point of widening `selectable` is that it moves what a user can
    /// pick, not what an existing phone wakes up as.
    @Test func defaultIsManualOnAFreshInstallAndOnABlobThatPredatesTheKey() throws {
        #expect(UserSettings().approvalMode == .manual)
        #expect(ApprovalMode.defaultMode == .manual)

        let decoder = JSONDecoder()
        let legacy = try decoder.decode(
            UserSettings.self, from: Data(#"{"userName":"Owen"}"#.utf8))
        #expect(legacy.approvalMode == .manual)
    }

    /// 224-1A's behaviour CHANGE, and the one Phase 0 wrote a test against.
    /// A blob naming `off` or `smart` used to clamp to `.manual` — that was
    /// ruling 1's hold expressed in the DATA layer. With the control shipped,
    /// a user's pick has to survive a relaunch or the setting is a no-op.
    @Test func aChosenModeRoundTripsNowThatAllThreeAreSelectable() throws {
        let decoder = JSONDecoder()

        let off = try decoder.decode(
            UserSettings.self, from: Data(#"{"userName":"Owen","approvalMode":"off"}"#.utf8))
        #expect(off.approvalMode == .off)

        let smart = try decoder.decode(
            UserSettings.self, from: Data(#"{"userName":"Owen","approvalMode":"smart"}"#.utf8))
        #expect(smart.approvalMode == .smart)

        // Encode → decode, because the decoder is only half of a persisted
        // pick and a settings file nobody can write is the same as no setting.
        var chosen = UserSettings()
        chosen.approvalMode = .off
        let roundTripped = try decoder.decode(
            UserSettings.self, from: JSONEncoder().encode(chosen))
        #expect(roundTripped.approvalMode == .off)
    }

    /// The half of the clamp that must NOT have moved: junk still degrades to
    /// the default rather than failing the whole settings decode and resetting
    /// every other preference (the `appearanceTheme` precedent).
    @Test func junkStillDegradesToManualWithoutLosingTheRestOfTheBlob() throws {
        let junk = try JSONDecoder().decode(
            UserSettings.self,
            from: Data(#"{"userName":"Owen","approvalMode":"yolo","verboseLogging":true}"#.utf8))
        #expect(junk.approvalMode == .manual)
        #expect(junk.userName == "Owen")
        #expect(junk.verboseLogging)
    }

    /// The list the Privacy control renders, in render order. Spelled out
    /// rather than derived from `allCases` in production for a reason
    /// (a future case must not ship itself), so it is spelled out here too.
    @Test func allThreeModesAreSelectableInRenderOrder() {
        #expect(ApprovalMode.selectable == [.manual, .smart, .off])
        #expect(ApprovalMode.allCases.map(\.rawValue) == ["manual", "smart", "off"])
        // Bound out of the macro: `#expect` reads a key-path `allSatisfy` as a
        // possibly-throwing call and demands a `try` that cannot be written.
        let everyCaseIsSelectable = ApprovalMode.allCases.allSatisfy(\.isSelectable)
        #expect(everyCaseIsSelectable)
        // `resolved` is a no-op on everything this build produces, and stays
        // as the guard for the NEXT narrowing.
        for mode in ApprovalMode.allCases {
            #expect(ApprovalMode.resolved(mode) == mode)
        }
        #expect(ApprovalMode.resolved(nil) == .manual)
    }
}

// MARK: - 224-1B / 224-1C / 224-2A — the gate's three dispositions

@MainActor
struct ApprovalGateDispositionTests {

    private func fields() -> [ToolConfirmationCenter.Field] {
        [
            .init(key: "title", label: "Title", value: "Call Shelley"),
            .init(key: "due", label: "Due", value: "Aug 27, 2026 at 10:00 AM"),
        ]
    }

    /// 224-1B, first half: under `.off` a CLEAN action creates with no card.
    /// Scored at the gate seam because that is where the decision is made —
    /// and because a suite that drives a real EventKit save on every gate run
    /// buys no extra information about the decision and leaves artifacts in
    /// the pool simulator. What the tool does AFTER the decision is 224-1C(ii)'s
    /// bar, and it is proven by identity rather than by writing.
    @Test func offAutoApprovesACleanActionAndNeverStagesACard() async {
        let center = ToolConfirmationCenter()
        center.modeProvider = { .off }
        let staged = fields()
        let call = Pending {
            await center.requestConfirmation(
                title: "Create this reminder?", caution: nil, fields: staged)
        }
        let decision = await settled(call)
        #expect(center.pending == nil, "a card staged under Never ask on a clean action")
        guard case .approved(let values)? = decision else {
            Issue.record("clean action under .off resolved as \(String(describing: decision))")
            return
        }
        #expect(values == ["title": "Call Shelley", "due": "Aug 27, 2026 at 10:00 AM"])
    }

    /// 224-2A, the clean half: `.smart` behaves exactly like `.off` when
    /// nothing is flagged. If these two ever diverge on a clean action, the
    /// one-line difference between the modes has stopped being one line.
    @Test func smartAutoApprovesACleanActionToo() async {
        let center = ToolConfirmationCenter()
        center.modeProvider = { .smart }
        let call = Pending {
            await center.requestConfirmation(
                title: "Add this event to the calendar?", caution: nil, fields: self.fields())
        }
        guard case .approved? = await settled(call) else {
            Issue.record("clean action under .smart did not auto-approve")
            return
        }
        #expect(center.pending == nil)
    }

    /// 224-1C(ii) — **resumption identity**, and it is the reason no mode can
    /// bypass an OS permission.
    ///
    /// An auto-approval hands the tool the SAME `.approved(values)` a user's
    /// tap hands it, built from the same staged fields. The tool therefore
    /// resumes at exactly the point it resumes under `.manual`, which is
    /// upstream of every EventKit / AlarmKit authorization check it makes.
    /// Asserting the dictionaries are equal is asserting there is no second
    /// resumption path to audit.
    @Test func anAutoApprovalIsByteIdenticalToAUserApprove() async {
        let staged = fields()

        let auto = ToolConfirmationCenter()
        auto.modeProvider = { .off }
        let autoCall = Pending {
            await auto.requestConfirmation(title: "Create this reminder?", fields: staged)
        }
        let autoDecision = await settled(autoCall)

        let manual = ToolConfirmationCenter()
        manual.modeProvider = { .manual }
        let manualCall = Pending {
            await manual.requestConfirmation(title: "Create this reminder?", fields: staged)
        }
        #expect(await stagedCardArrived(manual))
        manual.approve()
        let manualDecision = await settled(manualCall)

        guard case .approved(let autoValues)? = autoDecision,
              case .approved(let manualValues)? = manualDecision else {
            Issue.record("expected two approvals, got \(String(describing: autoDecision)) / \(String(describing: manualDecision))")
            return
        }
        #expect(autoValues == manualValues)
    }

    /// 224-1B, second half, at the gate: `.off` + a flagged action REFUSES.
    /// Ruling 4 — not a card, because carding would make Off silently
    /// identical to Smart; and not a `.declined`, because the user answered
    /// nothing and a tool reporting "The user declined" would misattribute the
    /// decision.
    @Test func offRefusesAFlaggedActionInsteadOfCardingOrDeclining() async {
        let center = ToolConfirmationCenter()
        center.modeProvider = { .off }
        let refusal = ApprovalFloor.refusal(
            nothingHappened: "No alarm was scheduled.", flagged: "EARLY MORNING — CHECK AM/PM")
        let call = Pending {
            await center.requestConfirmation(
                title: "Schedule on this iPhone?",
                caution: "EARLY MORNING — CHECK AM/PM",
                floorRefusal: refusal,
                fields: [.init(key: "request", label: "Alarm", value: "4:00am wake up")])
        }
        let decision = await settled(call)
        #expect(center.pending == nil, "the floor staged a card — Off would be secretly Smart")
        guard case .refused(let text)? = decision else {
            Issue.record("flagged action under .off resolved as \(String(describing: decision))")
            return
        }
        #expect(text == refusal)
        #expect(center.declineCount == 0, "a refusal is not a decline and must not be counted as one")
    }

    /// 224-2A's DISCRIMINATOR at the gate: the identical flagged action cards
    /// under `.smart` and refuses under `.off`. This is the design's one-line
    /// difference — *Smart asks you about the unusual ones; Off refuses them* —
    /// stated as a test rather than as prose.
    @Test func smartCardsTheVeryActionOffRefuses() async {
        let staged = [ToolConfirmationCenter.Field(key: "request", label: "Alarm", value: "4:00am wake up")]
        let caution = "EARLY MORNING — CHECK AM/PM"
        let refusal = ApprovalFloor.refusal(nothingHappened: "No alarm was scheduled.", flagged: caution)

        let smart = ToolConfirmationCenter()
        smart.modeProvider = { .smart }
        let smartCall = Pending {
            await smart.requestConfirmation(
                title: "Schedule on this iPhone?", caution: caution,
                floorRefusal: refusal, fields: staged)
        }
        #expect(await stagedCardArrived(smart), "Smart must ASK about a flagged action, not refuse it")
        #expect(smart.pending?.caution == caution)
        smart.decline()
        _ = await settled(smartCall)

        let off = ToolConfirmationCenter()
        off.modeProvider = { .off }
        let offCall = Pending {
            await off.requestConfirmation(
                title: "Schedule on this iPhone?", caution: caution,
                floorRefusal: refusal, fields: staged)
        }
        let offDecision = await settled(offCall)
        #expect(off.pending == nil)
        guard case .refused? = offDecision else {
            Issue.record("Off did not refuse the action Smart carded: \(String(describing: offDecision))")
            return
        }
    }

    /// The fail-safe: a flagged action whose tool supplied NO floor text is
    /// still refused, with the unnamed refusal. Falling back to the card would
    /// make Off secretly Manual for whichever tool forgot — the same class of
    /// dishonesty ruling 4 rejected — so the direction is refuse, and the
    /// message still carries #409's clause.
    @Test func aFlaggedActionWithNoFloorTextIsStillRefused() async {
        let center = ToolConfirmationCenter()
        center.modeProvider = { .off }
        let call = Pending {
            await center.requestConfirmation(
                title: "Create this reminder?", caution: "IN THE PAST — Aug 1, 2026 at 9:00 AM",
                fields: [.init(key: "title", label: "Title", value: "Milk")])
        }
        let decision = await settled(call)
        #expect(center.pending == nil)
        guard case .refused(let text)? = decision else {
            Issue.record("an unnamed flagged action was not refused: \(String(describing: decision))")
            return
        }
        #expect(text == ApprovalFloor.unnamedRefusal)
        #expect(!text.contains("Aug"), "the fallback must not echo a row that may carry a formatted date")
    }

    /// #323-D still outranks every mode. The lock is read BEFORE the provider,
    /// so behind the cover nothing auto-resolves — not an approve, not a
    /// refuse. `AppLockGateTests` scores the ORDER on a spy; this scores the
    /// OUTCOME against the two modes that could have resolved it, which only
    /// became a real question when those modes gained real paths.
    @Test func theLockOutranksEveryModeIncludingOff() async {
        for mode in ApprovalMode.allCases {
            let center = ToolConfirmationCenter()
            center.modeProvider = { mode }
            center.lockStateProvider = { true }
            let call = Pending {
                await center.requestConfirmation(
                    title: "Schedule on this iPhone?",
                    caution: "EARLY MORNING — CHECK AM/PM",
                    floorRefusal: "unreachable while locked",
                    fields: [.init(key: "request", label: "Alarm", value: "4:00am")])
            }
            #expect(await stagedCardArrived(center),
                    "mode \(mode.rawValue) resolved behind the App Lock cover instead of staging")
            center.decline()
            _ = await settled(call)
        }
    }
}

// MARK: - 224-1B / 224-2A through the real tools

@MainActor
struct ApprovalFloorToolWiringTests {

    private func rawLocal(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// 224-1B through `createCalendarEvent`. The tool has no pre-gate bounce,
    /// so a wee-hour start reaches the gate directly and the whole path — the
    /// caution row, the floor text, the tool's own `.refused` branch — is
    /// exercised end to end. Nothing is created: the refusal returns before
    /// EventKit is ever touched.
    @Test func offRefusesAWeeHourCalendarEventAndCreatesNothing() async {
        let center = ToolConfirmationCenter()
        center.modeProvider = { .off }
        let start = Calendar.current.date(
            bySettingHour: 4, minute: 0, second: 0,
            of: Date().addingTimeInterval(24 * 3_600))!
        let call = Pending {
            await CalendarEventTool.performCreate(
                rawTitle: "Standup", rawStartsAt: self.rawLocal(start),
                rawMinutes: 30, rawLocation: "", confirmations: center)
        }
        let result = await settled(call)
        #expect(center.pending == nil, "Never ask staged a card")
        let text = try? #require(result)
        #expect(text?.hasPrefix("No calendar event was created.") == true,
                "got: \(String(describing: result))")
        #expect(text?.contains("EARLY MORNING START — CHECK AM/PM") == true)
        #expect(text?.contains(ApprovalFloor.doNotClaimClause) == true)
        #expect(text?.contains("The user declined") == false,
                "a refusal must never be reported as the user's decision")
    }

    /// 224-1B through `scheduleAlarm`, and 224-2A's discriminator through a
    /// REAL tool: the same request cards under Smart and refuses under Off.
    @Test func smartCardsTheWeeHourAlarmThatOffRefuses() async {
        let caution = "EARLY MORNING — CHECK AM/PM"

        let smartCenter = ToolConfirmationCenter()
        smartCenter.modeProvider = { .smart }
        let smartTool = AlarmTool(relay: ToolEventRelay(), confirmations: smartCenter,
                                  alarmService: AlarmService())
        let smartCall = Pending { try? await smartTool.call(arguments: .init(request: "4:00am wake up")) }
        #expect(await stagedCardArrived(smartCenter), "Smart must ASK about a wee-hour alarm")
        #expect(smartCenter.pending?.caution == caution)
        smartCenter.decline()
        let smartResult = await settled(smartCall)
        #expect(smartResult == "The user declined — no alarm was scheduled.")

        let offCenter = ToolConfirmationCenter()
        offCenter.modeProvider = { .off }
        let offTool = AlarmTool(relay: ToolEventRelay(), confirmations: offCenter,
                                alarmService: AlarmService())
        let offCall = Pending { try? await offTool.call(arguments: .init(request: "4:00am wake up")) }
        let offResult = await settled(offCall)
        #expect(offCenter.pending == nil, "Never ask staged a card for the alarm")
        let text = (offResult ?? nil) ?? ""
        #expect(text.hasPrefix("No alarm was scheduled."), "got: \(text)")
        #expect(text.contains(caution))
        #expect(text.contains(ApprovalFloor.doNotClaimClause))
    }

    /// 224-1B through `createReminder`, which is the interesting one: its card
    /// rows carry formatted dates (they predate the #233-E / #249-F rule and
    /// are #233/#249's shipped, device-validated surface), so the floor must
    /// carry the DIGIT-FREE twin instead of the row.
    ///
    /// The tool bounces the first wee-hour due per conversation BEFORE the gate
    /// (#233), so this calls twice on one relay: the first claims the latch and
    /// the second reaches the gate. That is production behaviour, not a test
    /// contrivance — a user who confirms "yes, 4 AM" takes exactly this path.
    @Test func offRefusesAWeeHourReminderWithADigitFreeReason() async {
        let center = ToolConfirmationCenter()
        center.modeProvider = { .off }
        let relay = ToolEventRelay()
        let due = Calendar.current.date(
            bySettingHour: 4, minute: 0, second: 0,
            of: Date().addingTimeInterval(24 * 3_600))!
        let raw = rawLocal(due)

        let bounce = Pending {
            await ReminderCreateTool.performCreate(
                rawTitle: "Call Shelley", rawDue: raw, rawList: "",
                relay: relay, confirmations: center)
        }
        #expect(await settled(bounce) != nil)

        let call = Pending {
            await ReminderCreateTool.performCreate(
                rawTitle: "Call Shelley", rawDue: raw, rawList: "",
                relay: relay, confirmations: center)
        }
        let result = await settled(call)
        #expect(center.pending == nil)
        let text = result ?? ""
        #expect(text.hasPrefix("No reminder was created."), "got: \(text)")
        #expect(text.contains("EARLY MORNING"))
        // The DIGIT check is the #233-E rule; an earlier draft also forbade a
        // colon and that was wrong — the template's own "flagged:" carries
        // one. Recorded rather than silently dropped, because the failing
        // assertion is what proved the refusal reads correctly.
        #expect(text.rangeOfCharacter(from: .decimalDigits) == nil,
                "the reminder floor carries a mineable number: \(text)")
    }

    /// The digit-free twin, directly: same predicates, same order, no clock
    /// text. A rule added to `dueCaution` without a twin shows up here as a
    /// row whose reason still carries its formatted tail.
    @Test func theReminderFloorReasonIsTheRowWithoutItsFormattedTail() {
        let now = DeviceActionParsing.parseDateTime("2026-08-26T21:00")!
        let cases: [(String, String)] = [
            ("2026-08-26T09:00", "IN THE PAST"),
            ("2026-08-27T04:00", "EARLY MORNING"),
            ("2026-08-27T08:00", "NEXT MORNING"),
        ]
        for (iso, expected) in cases {
            let date = DeviceActionParsing.parseDateTime(iso)!
            let row = ReminderCreateTool.dueCaution(for: date, now: now)
            let reason = ReminderCreateTool.dueCautionReason(for: date, now: now)
            #expect(reason == expected, "\(iso) → \(String(describing: reason))")
            #expect(row?.hasPrefix(expected) == true, "the twin drifted from the row: \(String(describing: row))")
            #expect(reason?.rangeOfCharacter(from: .decimalDigits) == nil)
        }
        // A clean due has no row and therefore no reason — a tool cannot hand
        // the gate a floor message that does not apply.
        let clean = DeviceActionParsing.parseDateTime("2026-08-27T14:00")!
        #expect(ReminderCreateTool.dueCaution(for: clean, now: now) == nil)
        #expect(ReminderCreateTool.dueCautionReason(for: clean, now: now) == nil)
    }

    /// Every refusal string this build can produce, in one place: #409's clause
    /// present, no digits anywhere, and the negative lead first (#233-E).
    @Test func everyFloorRefusalCarriesTheClauseAndNothingMineable() {
        let produced = [
            ApprovalFloor.refusal(nothingHappened: "No reminder was created.", flagged: "EARLY MORNING"),
            ApprovalFloor.refusal(nothingHappened: "No reminder was created.", flagged: "IN THE PAST"),
            ApprovalFloor.refusal(nothingHappened: "No reminder was created.", flagged: "NEXT MORNING"),
            ApprovalFloor.refusal(nothingHappened: "No calendar event was created.", flagged: "STARTS IN THE PAST"),
            ApprovalFloor.refusal(nothingHappened: "No calendar event was created.", flagged: "EARLY MORNING START — CHECK AM/PM"),
            ApprovalFloor.refusal(nothingHappened: "No alarm was scheduled.", flagged: "EARLY MORNING — CHECK AM/PM"),
            ApprovalFloor.refusal(nothingHappened: "No alarm was scheduled.", flagged: "ALREADY PASSED TODAY — RINGS TOMORROW"),
            ApprovalFloor.refusal(nothingHappened: "No timer was scheduled.", flagged: "EARLY MORNING — CHECK AM/PM"),
            ApprovalFloor.unnamedRefusal,
        ].compactMap { $0 }
        #expect(produced.count == 9)
        for text in produced {
            // #409, and the clause is asserted on its own literal rather than
            // by referencing the constant — a pin that reads the code it
            // guards is a tautology.
            #expect(text.contains("This action was refused and did not run — do not tell the user it happened."),
                    "missing the do-not-claim clause: \(text)")
            #expect(text.rangeOfCharacter(from: .decimalDigits) == nil,
                    "a refusal carries a mineable number: \(text)")
            #expect(text.hasPrefix("No"), "a refusal must lead with the negative (#233-E): \(text)")
            #expect(text.contains("Never ask"), "a refusal must say which setting produced it: \(text)")
        }
        // A clean action has no refusal at all.
        #expect(ApprovalFloor.refusal(nothingHappened: "No reminder was created.", flagged: nil) == nil)
        #expect(ApprovalFloor.refusal(nothingHappened: "No reminder was created.", flagged: "") == nil)
    }
}

// MARK: - 224-1C — reads and permissions are untouched

@MainActor
struct ApprovalModeReadToolIsolationTests {

    /// 224-1C(i). No read tool holds the confirm gate — the read belt's
    /// factory cannot even accept one — so no mode can change what a read
    /// does. Scored by reflection over the REAL belt rather than by reading
    /// the factory's signature, because a tool could acquire the gate some
    /// other way and the signature would still look clean.
    @Test func noReadToolHoldsTheConfirmationGate() {
        let belt = DeviceToolBelt.makeReadTools(
            relay: ToolEventRelay(),
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false })
        #expect(belt.count >= 12, "the read belt shrank — repoint this bar before trusting it")
        for tool in belt {
            for child in Mirror(reflecting: tool).children {
                #expect(!(child.value is ToolConfirmationCenter),
                        "read tool \(type(of: tool)) holds a ToolConfirmationCenter")
                #expect(!(child.value is ApprovalMode),
                        "read tool \(type(of: tool)) holds an ApprovalMode")
            }
        }

        // POSITIVE CONTROL: the same reflection DOES find the gate on the
        // action belt. Without it, a reflection that cannot see a stored
        // property would report a clean read belt for the wrong reason.
        let actions = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(), confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService())
        let gated = actions.filter { tool in
            Mirror(reflecting: tool).children.contains { $0.value is ToolConfirmationCenter }
        }
        #expect(gated.count == actions.count,
                "the reflection cannot see the gate it is supposed to detect")
        #expect(actions.count == 3)
    }

    /// 224-1C, the structural half: the mode is consulted in exactly ONE
    /// place. A second consult site is how a mode starts governing something
    /// nobody balloted — a read tool, a slash command, a background job.
    @Test(
        .enabled(
            if: repoSourcesAreReadable,
            """
            #332-a: this bar reads the repo's Swift sources at runtime, so it is \
            scorable only where the test process shares the Mac's filesystem — a \
            simulator. Off-simulator the sources do not exist and the read fails with \
            NSCocoaErrorDomain 260, which measures the sandbox and not the app.
            """
        )
    )
    func theGateIsTheOnlyPlaceAModeIsConsulted() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = repoRoot.appendingPathComponent("Talaria")
        let enumerator = try #require(
            FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))

        var consultSites: [String] = []
        var declarationSites: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            let code = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            // The leading dot is what separates a CALL from the declaration —
            // `func disposition(hasCaution:` matches the bare form too, and an
            // earlier draft of this bar failed for exactly that reason.
            if code.contains(".disposition(hasCaution:") {
                consultSites.append(url.lastPathComponent)
            }
            if code.contains("func disposition(hasCaution:") {
                declarationSites.append(url.lastPathComponent)
            }
        }
        #expect(scanned > 100, "scanned only \(scanned) files — an empty scan must fail, never pass")
        // POSITIVE CONTROL: the scan can still find something. A discriminator
        // that has never fired is indistinguishable from one that cannot.
        #expect(declarationSites == ["ApprovalModeCore.swift"],
                "the policy's declaration moved — repoint this bar: \(declarationSites)")
        #expect(Set(consultSites) == ["ToolConfirmationCenter.swift"],
                "the approval mode is consulted outside the gate: \(consultSites)")
    }
}

// MARK: - 224-1D — the Privacy control

@MainActor
struct AgentActionsSettingsCopyTests {

    /// 224-1D(iv). The copy is PRODUCTION (#218 — never a `#if DEBUG` string)
    /// and every clause is something the code does. Pinned verbatim, the
    /// `sensorStreamingCaptionText` precedent: a later edit that widens the
    /// claim has to go red here first.
    @Test func theSectionCaptionNamesItsRealBlastRadiusAndNoMore() {
        #expect(PrivacySettingsScreen.agentActionsCaption ==
                "Covers the reminders, calendar events, and alarms your agent stages on this phone. Reading your data always follows the permissions above, and an alarm you type yourself with /alarm always asks.")
        // The three writes, named.
        for artifact in ["reminders", "calendar events", "alarms"] {
            #expect(PrivacySettingsScreen.agentActionsCaption.contains(artifact))
        }
        // Reads are disclaimed (224-1C), and the SECOND door into AlarmKit is
        // named rather than left for the user to discover by being asked.
        #expect(PrivacySettingsScreen.agentActionsCaption.contains("permissions above"))
        #expect(PrivacySettingsScreen.agentActionsCaption.contains("/alarm"))
    }

    /// The three rows' titles and one-line consequences, pinned. "Never ask"
    /// must say that unusual actions are REFUSED — a row that promised only
    /// silence would be a claim the floor does not keep.
    @Test func everyRowStatesWhatThatModeActuallyDoes() {
        #expect(ApprovalMode.manual.displayLabel == "Ask every time")
        #expect(ApprovalMode.smart.displayLabel == "Ask when unusual")
        #expect(ApprovalMode.off.displayLabel == "Never ask")

        #expect(ApprovalMode.manual.rowDetail ==
                "Every reminder, event, and alarm waits for your approval.")
        #expect(ApprovalMode.smart.rowDetail ==
                "Goes ahead unless the action trips a caution — an early-morning hour, or a time that has already passed. Those still ask.")
        #expect(ApprovalMode.off.rowDetail ==
                "Goes ahead without asking. An action that trips a caution is refused instead of created.")
        #expect(ApprovalMode.off.rowDetail.contains("refused"),
                "Off's row must name the floor — the setting is only shippable because of it")
        // The word "ordinary" is banned from these two rows: this lane
        // measured an evening-set 7 AM alarm tripping #249's past-due rule,
        // and calling that case ordinary is a claim the code does not keep.
        for mode in [ApprovalMode.smart, .off] {
            #expect(!mode.rowDetail.lowercased().contains("ordinary"),
                    "\(mode.rawValue)'s row calls the caution-tripping set unusual: \(mode.rowDetail)")
            #expect(mode.rowDetail.contains("trips a caution"),
                    "\(mode.rawValue)'s row must name the real discriminator: \(mode.rowDetail)")
        }
    }

    /// 224-1D(iii). A VoiceOver label that is just the mode name tells a
    /// screen-reader user nothing about which mode refuses their 4 AM alarm.
    /// Every label names the mode AND its consequence, and is strictly longer
    /// than the name alone.
    @Test func voiceOverLabelsStateTheConsequenceNotTheNameAlone() {
        for mode in ApprovalMode.allCases {
            let label = mode.accessibilityLabel
            #expect(label.hasPrefix(mode.displayLabel), "\(mode.rawValue): \(label)")
            #expect(label.count > mode.displayLabel.count + 20,
                    "\(mode.rawValue)'s label is the name with nothing after it: \(label)")
            #expect(label.contains("without asking") || label.contains("waits for your approval"),
                    "\(mode.rawValue)'s label states no consequence: \(label)")
        }
        #expect(ApprovalMode.off.accessibilityLabel ==
                "Never ask. Actions go ahead without asking, and any that trip a caution are refused instead of created.")
        #expect(ApprovalMode.smart.accessibilityLabel ==
                "Ask when unusual. Actions go ahead without asking unless they trip a caution, and those still ask you first.")
        #expect(ApprovalMode.manual.accessibilityLabel ==
                "Ask every time. Every reminder, event, and alarm waits for your approval.")
    }

    /// 224-1D(ii). Off reads as FORGE — the theme's warning amber — in every
    /// theme and every accent slot, and never as danger. Danger is for actual
    /// danger, and Off still has a floor.
    @Test func offReadsAsForgeInEveryThemeAndNeverAsDanger() {
        var checked = 0
        for theme in ThemeID.allCases {
            for accent in AccentSlot.allCases {
                let palette = ThemePalette(theme: theme, accent: accent)
                checked += 1
                #expect(PrivacySettingsScreen.approvalRowTint(for: .off, in: palette) == palette.forgeText,
                        "\(theme)/\(accent): Off is not forge")
                #expect(PrivacySettingsScreen.approvalRowTint(for: .off, in: palette) != palette.dangerText,
                        "\(theme)/\(accent): Off reads as danger")
                for mode in [ApprovalMode.manual, .smart] {
                    #expect(PrivacySettingsScreen.approvalRowTint(for: mode, in: palette) == palette.accentText,
                            "\(theme)/\(accent): \(mode.rawValue) is not the hero hue")
                }
                // The claim "forge, not danger" is only meaningful where the
                // two are distinguishable — including on the LIGHT themes,
                // where Paper Tape's low glow scale makes them closest.
                #expect(palette.forgeText != palette.dangerText,
                        "\(theme)/\(accent): forge and danger are the same colour, so the bar is unscorable here")
            }
        }
        #expect(checked >= 12, "only \(checked) theme/accent pairs resolved — the sweep found nothing")
        // Paper Tape by name, because it is the theme the bar was written for.
        let paper = ThemePalette(theme: AppearanceTheme.paperTape.themeID, accent: .cyan)
        #expect(paper.isLight)
        #expect(PrivacySettingsScreen.approvalRowTint(for: .off, in: paper) == paper.forgeText)
    }

    /// 224-1D, ruling 6's POSITION. The ballot placed the control "between
    /// Location and App Lock" — after what the phone shares, before who can
    /// open the app, which is the right reading order for what the agent may
    /// do without asking. `locationSection` has not existed since #137
    /// (Location is a row inside Sensor Sharing), so the position resolves to
    /// between `sensorStreamingSection` and `appLockSection`.
    ///
    /// Pinned by reading `body`'s composition, because that ORDER is the whole
    /// ruling and nothing else can see it: the XCUITest proves the section
    /// renders, and a copy test proves what it says, but neither notices it
    /// drifting to the bottom of the screen.
    @Test(
        .enabled(
            if: repoSourcesAreReadable,
            """
            #332-a: reads PrivacySettingsScreen.swift at runtime, so it is scorable only \
            where the test process shares the Mac's filesystem — a simulator.
            """
        )
    )
    func theControlSitsBetweenSensorSharingAndAppLock() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Talaria/Features/Settings/PrivacySettingsScreen.swift"),
            encoding: .utf8)
        #expect(source.count > 500, "an unreadable source must fail, never pass")

        // The composition lines of `body`, in order: bare section names, one
        // per line, ignoring the comment block that explains the position.
        let composed = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { ["permissionsSection", "sensorStreamingSection", "agentActionsSection",
                       "appLockSection", "spotlightSection", "revokeSection",
                       "manageSection"].contains($0) }
        #expect(composed == ["permissionsSection", "sensorStreamingSection", "agentActionsSection",
                             "appLockSection", "spotlightSection", "revokeSection", "manageSection"],
                "the Privacy page's section order moved: \(composed)")
    }

    /// The structural half of the same bar, and the stronger one: an approval
    /// row cannot express danger because the ROLE TYPE has no such case. A
    /// comment saying "don't use danger here" is advice; this is a compile
    /// error for anyone who tries.
    @Test func anApprovalRowCannotExpressDangerAtAll() {
        #expect(ApprovalModeAccentRole.allCases == [.brand, .warning])
        #expect(ApprovalMode.off.accentRole == .warning)
        #expect(ApprovalMode.manual.accentRole == .brand)
        #expect(ApprovalMode.smart.accentRole == .brand)
    }
}

// MARK: - 224-2A(ii) — the wee-hour threshold, decided in writing

@MainActor
struct SmartThresholdDecisionTests {

    /// **THE DECISION, and it is deliberate rather than inherited.**
    ///
    /// Phase 0's finding 1 flagged that `isEarlyMorning` covers hours 0–6, so
    /// `"6:30am wake up"` — the canonical morning alarm, not a defect — carries
    /// `EARLY MORNING — CHECK AM/PM` on every card. Under Manual that is one
    /// amber line on a card the user is already tapping. Under Smart it means
    /// **every pre-07:00 alarm CARDS instead of auto-approving**, and Phase 0
    /// asked this lane to decide that in writing rather than discover it in use.
    ///
    /// **Decision: the threshold does NOT move.** It is #233's, it was
    /// balloted, and 224-0A's registered bar says "before 07:00 local" — a
    /// missed bar is a falsification and so is a quietly improved one. Smart
    /// is conservative in the safe direction here, and moving the threshold is
    /// a separate written decision with its own device evidence, not a detail
    /// this lane may fold into an unrelated election.
    ///
    /// This test exists so the behaviour is a CHOICE on the record: it names
    /// 6:30 AM explicitly and asserts the card.
    @Test func theCanonicalMorningAlarmStillCardsUnderSmart() {
        let now = DeviceActionParsing.parseDateTime("2026-08-26T21:00")!
        let request = try? #require(AlarmService.parse("6:30am wake up"))
        let caution = request.flatMap { AlarmTool.caution(for: $0, now: now) }
        #expect(caution == "EARLY MORNING — CHECK AM/PM",
                "the #233 threshold moved — that is a written decision, not a detail")
        #expect(ApprovalMode.smart.disposition(hasCaution: caution != nil) == .card)
        // …and the same alarm is REFUSED under Off, which is the cost of the
        // decision stated plainly rather than left implicit.
        #expect(ApprovalMode.off.disposition(hasCaution: caution != nil) == .refuse)

        // The contrast that makes it a threshold rather than a blanket: an
        // alarm later the same evening trips nothing and auto-approves under
        // both. So does a countdown, which has no clock hour to misread.
        let tonight = try? #require(AlarmService.parse("10:00pm reading"))
        #expect(tonight.flatMap { AlarmTool.caution(for: $0, now: now) } == nil)
        let countdown = try? #require(AlarmService.parse("25m tea"))
        #expect(countdown.flatMap { AlarmTool.caution(for: $0, now: now) } == nil)
        #expect(ApprovalMode.smart.disposition(hasCaution: false) == .autoApprove)
        #expect(ApprovalMode.off.disposition(hasCaution: false) == .autoApprove)
    }

    /// **A SECOND, LARGER instance of the same cost — found by this lane's own
    /// tests rather than anticipated by its bars, and NOT fixed here.**
    ///
    /// Phase 0's finding 1 named the wee-hour rule (hours 0–6). It did not
    /// name #249's past-due rule, which under Smart bites harder: an alarm set
    /// in the EVENING for the next morning has already passed *today*, so
    /// `AlarmTool.caution` stages `ALREADY PASSED TODAY — RINGS TOMORROW` and
    /// Smart therefore CARDS it. Setting tomorrow's 7 AM alarm at 9 PM is
    /// close to the single most common thing anyone does with an alarm, so in
    /// practice a large share of alarms card under *Ask when unusual* and are
    /// REFUSED under *Never ask*.
    ///
    /// **Deliberately left as-is, and this test is the record of that.** The
    /// registered bar is *caution ⇒ card*, one seam and no second risk model;
    /// carving an exception for one rule would be a redefinition of a bar
    /// mid-lane, and #249's row exists because a stale time is a real defect
    /// shape. The alarm DOES ring — correctly, tomorrow — so the honest
    /// question is whether the row should be a caution at all under Smart, and
    /// that is a written decision with device evidence behind it, not a
    /// detail this lane may fold into an unrelated election. Runbook card
    /// #224-2C asks Owen to report the friction directly.
    @Test func anEveningAskForTomorrowsAlarmAlsoCardsUnderSmart() {
        let evening = DeviceActionParsing.parseDateTime("2026-08-26T21:00")!
        let sevenAM = try? #require(AlarmService.parse("7:00am wake up"))
        let caution = sevenAM.flatMap { AlarmTool.caution(for: $0, now: evening) }
        #expect(caution == "ALREADY PASSED TODAY — RINGS TOMORROW")
        #expect(ApprovalMode.smart.disposition(hasCaution: caution != nil) == .card)
        #expect(ApprovalMode.off.disposition(hasCaution: caution != nil) == .refuse)

        // The same ask in the MORNING trips nothing — which is what makes this
        // a property of the clock rather than of the alarm.
        let morning = DeviceActionParsing.parseDateTime("2026-08-26T06:59")!
        #expect(sevenAM.flatMap { AlarmTool.caution(for: $0, now: morning) } == nil)
    }
}

// MARK: - 224-2B — the model-free pin, extended

@MainActor
struct ApprovalPathModelFreeExtensionTests {

    /// 224-2B, extending 224-0F's first half over the paths Phases 1+2 added.
    ///
    /// **The pin is the ABSENCE of `async` on this body**, not any expectation
    /// inside it. A `LanguageModelSession` turn is necessarily `await`ed, so
    /// putting the model anywhere in this chain — the disposition, the floor's
    /// text, the row's colour role, the settings clamp — means making one of
    /// them `async`, which stops this file compiling. Ruling 5 exists because
    /// the #200-series is a long record of this model mis-assessing intent and
    /// #297 measured a 7/20 miss; the safety path is the worst place to spend
    /// that reliability.
    @Test func everyPhase12ApprovalDecisionIsSynchronous() {
        for mode in ApprovalMode.allCases {
            _ = mode.disposition(hasCaution: true)
            _ = mode.disposition(hasCaution: false)
            _ = mode.accentRole
            _ = mode.rowDetail
            _ = mode.accessibilityLabel
            _ = ApprovalMode.resolved(mode)
        }
        _ = ApprovalFloor.refusal(nothingHappened: "No reminder was created.", flagged: "EARLY MORNING")
        _ = ApprovalFloor.unnamedRefusal
        _ = ReminderCreateTool.dueCautionReason(for: Date(), now: Date())
        #expect(ApprovalMode.off.disposition(hasCaution: true) == .refuse)
    }
}
