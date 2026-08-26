import Foundation
import Testing
@testable import Talaria

// #224 Phase 0 — bars 224-0A … 224-0F, pre-registered in OPEN_ITEMS #224
// before any code was written.
//
// Two halves:
//   * the CAUTION layer extended to `createCalendarEvent` and
//     `scheduleAlarm`, neither of which passed a `caution:` at all before
//     this lane;
//   * the MODE scaffold, which ships unreachable on purpose.

/// #332-a's discriminator. It is COMPILE-TIME on purpose: the test bundle is
/// built per destination, so this is decided by the build rather than sniffed
/// at runtime.
///
/// A simulator process shares the Mac's filesystem, so `#filePath` still
/// resolves to the real repo there and a test may read the project's own Swift
/// sources. On a device it cannot — the sources were never copied into the
/// bundle — and the read fails with `NSCocoaErrorDomain 260`. That is a
/// property of the sandbox, not of the code under test, so the bar it guards is
/// UNSCORABLE on a device rather than failed.
private let repoSourcesAreReadableAtRuntime: Bool = {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
}()

/// 224-0A / 224-0B / 224-0D — the caution rules the two un-cautioned action
/// tools gain, their boundaries, and the wording constraint.
@MainActor
struct Phase0ActionCautionTests {

    // MARK: Helpers

    private func at(_ iso: String) -> Date {
        DeviceActionParsing.parseDateTime(iso)!
    }

    /// The tool takes a raw string, so a runtime-computed date has to go back
    /// through the same wall-clock form the model would send.
    private func rawLocal(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Waits on a WALL CLOCK for the gate to stage a card, and reports whether
    /// one arrived.
    ///
    /// **Do not replace this with the `while center.pending == nil && attempts
    /// < 2_000 { await Task.yield() }` idiom the older suites use — it can
    /// HANG the whole run, and it did on 2026-08-11.** The failure is a race,
    /// not a flake: when the budget expires before the tool's Task has reached
    /// `requestConfirmation`, the test declines an EMPTY gate (a no-op that
    /// still logs "confirmation declined"), the tool stages a moment later,
    /// and it then suspends on a continuation nobody will ever answer — so
    /// `await task.value` never returns. Measured: the card arrived **3.4
    /// seconds** after the yield budget ran out, with three lanes building on
    /// the host. A yield count is not a clock, and 2,000 of them can be
    /// microseconds or minutes depending on what else holds the main actor.
    ///
    /// Callers must treat `false` as "do not decline and do not await the
    /// task" — leaking a suspended Task is bad; hanging the suite is worse.
    private func awaitStagedCard(
        _ center: ToolConfirmationCenter,
        timeout: Duration = .seconds(20)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while center.pending == nil, ContinuousClock.now < deadline {
            // Sleep rather than spin: a yield loop on the main actor starves
            // the very Task it is waiting for.
            try? await Task.sleep(for: .milliseconds(2))
        }
        return center.pending != nil
    }

    // MARK: 224-0B — createCalendarEvent

    /// 224-0B, THE WIRING, and 224-0C's RED. Written to fail at HEAD:
    /// `CalendarEventTool.performCreate` passed no `caution:` at all, so
    /// `pending?.caution` was nil for every event ever staged. Deliberately
    /// driven off the REAL clock through the production call site — tomorrow
    /// 04:00 is always both in the future (so the past-due rule stays out of
    /// the way) and inside the wee-hour window.
    @Test func weeHourEventStartStagesACautionRow() async {
        let center = ToolConfirmationCenter()
        let start = Calendar.current.date(
            bySettingHour: 4, minute: 0, second: 0,
            of: Date().addingTimeInterval(24 * 3_600))!
        let raw = rawLocal(start)
        let task = Task {
            await CalendarEventTool.performCreate(
                rawTitle: "Standup", rawStartsAt: raw,
                rawMinutes: 30, rawLocation: "", confirmations: center)
        }
        guard await awaitStagedCard(center) else {
            Issue.record("the confirmation card never staged — see awaitStagedCard")
            return   // deliberately NOT awaiting the task: see awaitStagedCard
        }
        #expect(center.pending?.caution == "EARLY MORNING START — CHECK AM/PM")
        center.decline()
        let result = await task.value
        #expect(result == "The user declined — no event was created.")
    }

    /// 224-0B, the other rule, same wiring: a start ten minutes stale.
    @Test func pastEventStartStagesACautionRow() async {
        let center = ToolConfirmationCenter()
        let raw = rawLocal(Date().addingTimeInterval(-600))
        let task = Task {
            await CalendarEventTool.performCreate(
                rawTitle: "Standup", rawStartsAt: raw,
                rawMinutes: 30, rawLocation: "", confirmations: center)
        }
        guard await awaitStagedCard(center) else {
            Issue.record("the confirmation card never staged — see awaitStagedCard")
            return   // deliberately NOT awaiting the task: see awaitStagedCard
        }
        #expect(center.pending?.caution == "STARTS IN THE PAST")
        center.decline()
        _ = await task.value
    }

    /// An ordinary future start stages byte-identically to pre-#224 — nil
    /// caution, so the common card is unchanged. (This one is GREEN at HEAD
    /// too; it is the control that says the two above fail for the right
    /// reason rather than because the harness never staged anything.)
    @Test func ordinaryEventStartStagesWithNoCaution() async {
        let center = ToolConfirmationCenter()
        let start = Calendar.current.date(
            bySettingHour: 14, minute: 0, second: 0,
            of: Date().addingTimeInterval(24 * 3_600))!
        let raw = rawLocal(start)
        let task = Task {
            await CalendarEventTool.performCreate(
                rawTitle: "Standup", rawStartsAt: raw,
                rawMinutes: 30, rawLocation: "", confirmations: center)
        }
        guard await awaitStagedCard(center) else {
            Issue.record("the confirmation card never staged — see awaitStagedCard")
            return   // deliberately NOT awaiting the task: see awaitStagedCard
        }
        #expect(center.pending?.caution == nil)
        center.decline()
        _ = await task.value
    }

    // MARK: 224-0A — scheduleAlarm

    /// 224-0A, THE WIRING, and 224-0C's other RED, through the production
    /// tool call. `AlarmTool.call` passed no `caution:` at HEAD. A 4 AM alarm
    /// is wee-hour against any clock, so this needs no injected `now`.
    @Test func weeHourAlarmStagesACautionRow() async throws {
        let relay = ToolEventRelay()
        let center = ToolConfirmationCenter()
        let tool = AlarmTool(relay: relay, confirmations: center, alarmService: AlarmService())
        let task = Task { try await tool.call(arguments: .init(request: "4:00am wake up")) }
        guard await awaitStagedCard(center) else {
            Issue.record("the confirmation card never staged — see awaitStagedCard")
            return   // deliberately NOT awaiting the task: see awaitStagedCard
        }
        #expect(center.pending?.caution == "EARLY MORNING — CHECK AM/PM")
        center.decline()
        let result = try await task.value
        #expect(result == "The user declined — no alarm was scheduled.")
    }

    /// 224-0D — the early-morning boundary for the calendar tool.
    /// `isEarlyMorning` is hours 0…6, so 06:59 trips and 07:00 does not.
    /// `now` sits at 05:00 so a 07:00 start is still ahead and the past-due
    /// rule cannot answer for it.
    @Test func eventStartCautionEarlyMorningBoundary() {
        let now = at("2026-08-11T05:00")
        #expect(CalendarEventTool.startCaution(for: at("2026-08-11T06:59"), now: now)
            == "EARLY MORNING START — CHECK AM/PM")
        #expect(CalendarEventTool.startCaution(for: at("2026-08-11T07:00"), now: now) == nil)
        #expect(CalendarEventTool.startCaution(for: at("2026-08-11T00:00"), now: at("2026-08-10T23:00"))
            == "EARLY MORNING START — CHECK AM/PM")
        #expect(CalendarEventTool.startCaution(for: nil, now: now) == nil)
    }

    /// 224-0D — both sides of #249's five-minute past-due grace, for the
    /// calendar tool. `isPastDue` is `date < now - 300`, so exactly five
    /// minutes stale is still inside the grace and one second more is not.
    @Test func eventStartCautionPastDueGraceBoundary() {
        let now = at("2026-08-11T14:00")
        #expect(CalendarEventTool.startCaution(for: now.addingTimeInterval(-299), now: now) == nil)
        #expect(CalendarEventTool.startCaution(for: now.addingTimeInterval(-300), now: now) == nil)
        #expect(CalendarEventTool.startCaution(for: now.addingTimeInterval(-301), now: now)
            == "STARTS IN THE PAST")
        #expect(CalendarEventTool.startCaution(for: now.addingTimeInterval(-3_600), now: now)
            == "STARTS IN THE PAST")
        #expect(CalendarEventTool.startCaution(for: now.addingTimeInterval(3_600), now: now) == nil)
    }

    /// Ordering pin for the calendar card, matching the reminder card's
    /// (#249-C): a start both stale AND wee-hour reads as stale first,
    /// because an event that starts in the past is a plain failure whichever
    /// hour it names.
    @Test func pastWeeHourEventStartReadsAsPastFirst() {
        #expect(CalendarEventTool.startCaution(for: at("2026-08-11T04:00"), now: at("2026-08-11T21:00"))
            == "STARTS IN THE PAST")
    }

    /// The common alarm still stages with no caution.
    @Test func afternoonAlarmStagesWithNoCautionWhenStillAhead() {
        #expect(AlarmTool.caution(for: AlarmService.parse("14:00 gym")!, now: at("2026-08-11T09:00")) == nil)
    }

    /// 224-0D — the alarm's early-morning boundary. The alarm grammar yields
    /// a clock time, not a date, so the rule resolves it against `now`'s day
    /// and reuses the SAME `isEarlyMorning` predicate the reminder card uses.
    @Test func alarmCautionEarlyMorningBoundary() {
        let now = at("2026-08-11T05:00")
        #expect(AlarmTool.caution(for: AlarmService.parse("6:59 wake")!, now: now)
            == "EARLY MORNING — CHECK AM/PM")
        #expect(AlarmTool.caution(for: AlarmService.parse("7:00 wake")!, now: now) == nil)
        #expect(AlarmTool.caution(for: AlarmService.parse("12:00am wake")!, now: now)
            == "EARLY MORNING — CHECK AM/PM")
    }

    /// 224-0D — both sides of the five-minute grace for the alarm. An 8 AM
    /// alarm asked at 08:05:01 will not ring today at all: `nextOccurrence`
    /// rolls it to tomorrow, and the card shows only the raw request string,
    /// so nothing else on it says which day it rings.
    @Test func alarmCautionPastDueGraceBoundary() {
        let request = AlarmService.parse("8:00 gym")!
        #expect(AlarmTool.caution(for: request, now: at("2026-08-11T08:04:59")) == nil)
        #expect(AlarmTool.caution(for: request, now: at("2026-08-11T08:05:00")) == nil)
        #expect(AlarmTool.caution(for: request, now: at("2026-08-11T08:05:01"))
            == "ALREADY PASSED TODAY — RINGS TOMORROW")
        #expect(AlarmTool.caution(for: request, now: at("2026-08-11T20:00"))
            == "ALREADY PASSED TODAY — RINGS TOMORROW")
        #expect(AlarmTool.caution(for: request, now: at("2026-08-11T07:00")) == nil)
    }

    /// A countdown trips neither rule: it is always in the future and has no
    /// clock hour to misread.
    @Test func countdownAlarmNeverCautions() {
        #expect(AlarmTool.caution(for: AlarmService.parse("25m tea")!, now: at("2026-08-11T04:00")) == nil)
        #expect(AlarmTool.caution(for: AlarmService.parse("1h30m bread")!, now: at("2026-08-11T23:30")) == nil)
    }

    /// Ordering pin for the alarm card, and it deliberately runs the OTHER
    /// way from the calendar card's. A 4 AM alarm asked at 6 AM is both
    /// wee-hour and two hours stale. The wee-hour row wins, because a
    /// past-due alarm still rings — one day later — while an AM/PM misread is
    /// the defect #233 exists to raise. The softer signal never masks the
    /// sharper one.
    @Test func weeHourAlarmOutranksAlreadyPassedToday() {
        #expect(AlarmTool.caution(for: AlarmService.parse("4:00am wake")!, now: at("2026-08-11T06:00"))
            == "EARLY MORNING — CHECK AM/PM")
    }

    // MARK: 224-0A / 224-0B — the wording constraint, pinned by assertion

    /// The #233-E / #249-F rule, pinned by ASSERTION and not by review. On
    /// 2026-08-03 (build 1870) the model mined a formatted timestamp out of a
    /// tool string into a fabricated "has been set for Aug 4, 2026 at 5:00
    /// AM" success claim; #249-F repeated the shape on 2026-08-06. Every
    /// caution row this lane adds is therefore DIGIT-FREE, which is strictly
    /// stronger than "no formatted date": every formatted date and time
    /// carries digits, so a digit check cannot be satisfied by one.
    ///
    /// Scope note, on the record rather than left to be discovered: the
    /// REMINDER card's rows (`ReminderCreateTool.dueCaution`) still carry
    /// `displayDate` / `timeOnly`. They predate the rule, they are #233 and
    /// #249's shipped and device-validated surface, and rewriting them is not
    /// what Owen balloted — so they are deliberately outside this assertion.
    @Test func phase0CautionRowsCarryNothingMineable() {
        let evening = at("2026-08-11T21:00")
        let rows: [String] = [
            CalendarEventTool.startCaution(for: at("2026-08-11T04:00"), now: evening)!,
            CalendarEventTool.startCaution(for: at("2026-08-12T04:00"), now: evening)!,
            AlarmTool.caution(for: AlarmService.parse("4:00am wake")!, now: evening)!,
            AlarmTool.caution(for: AlarmService.parse("8:00 gym")!, now: at("2026-08-11T09:00"))!,
        ]
        // All four rules produced a row — otherwise the loop below would be
        // asserting over an empty set, which is the shape that lets a check
        // pass by measuring nothing.
        #expect(rows.count == 4)
        for row in rows {
            #expect(row.rangeOfCharacter(from: .decimalDigits) == nil,
                    "caution row carries a mineable number: \(row)")
            #expect(row == row.uppercased(with: Locale(identifier: "en_US_POSIX")),
                    "caution rows are the card's all-caps forge row: \(row)")
        }
    }
}

/// 224-0E / 224-0F — the mode scaffold: present, global, and unreachable.
@MainActor
struct ApprovalModeScaffoldTests {

    /// 224-0E. All three cases exist so that every switch over an approval
    /// mode is exhaustive from day one (#306's C1 precedent — name the door
    /// before anyone walks through it), and exactly one is selectable.
    /// **If a later lane widens `selectable`, this test is what goes RED**:
    /// shipping a mode has to be a deliberate edit to the line that says so.
    @Test func approvalModeExposesOnlyManual() {
        #expect(ApprovalMode.allCases == [.manual, .smart, .off])
        #expect(ApprovalMode.selectable == [.manual])
        #expect(ApprovalMode.defaultMode == .manual)
        #expect(ApprovalMode.manual.isSelectable)
        #expect(!ApprovalMode.smart.isSelectable)
        #expect(!ApprovalMode.off.isSelectable)
        // Raw values are persisted; they are never renamed.
        #expect(ApprovalMode.allCases.map(\.rawValue) == ["manual", "smart", "off"])
    }

    /// The clamp, which is what makes "unreachable" true of DATA and not just
    /// of the UI: no persisted blob can arm a mode this build has no handling
    /// for.
    @Test func approvalModeClampsUnreachableValuesToManual() {
        #expect(ApprovalMode.resolved(nil) == .manual)
        #expect(ApprovalMode.resolved(.manual) == .manual)
        #expect(ApprovalMode.resolved(.smart) == .manual)
        #expect(ApprovalMode.resolved(.off) == .manual)
    }

    /// Ruling 2's negative half: the mode must NOT be per-profile. The gate
    /// governs this phone's own EventKit / AlarmKit writes, which happen
    /// identically whichever host a turn came from — and happen at all when
    /// no host is configured. Making the safety posture change when you
    /// switch hosts is a footgun with no upside.
    @Test func approvalModeIsNotAPerProfileSetting() throws {
        let profile = BackendProfile(
            name: "OJAMD", gatewayBaseURL: "http://ojamd:8642")
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(profile)) as? [String: Any]
        let keys = Set((json ?? [:]).keys)
        #expect(!keys.isEmpty)
        #expect(!keys.contains("approvalMode"))
        #expect(Mirror(reflecting: profile).children.allSatisfy { $0.label != "approvalMode" })
    }

    /// The design's §3.4 policy table, written down once as a pure function.
    /// Only the `.manual` row is reachable in this build; the other two are
    /// the contract Phases 1–2 must implement, and ruling 4 is the `.off` +
    /// caution cell — REFUSE, not card, or Off is secretly identical to
    /// Smart.
    @Test func dispositionTableMatchesTheBallotedPolicy() {
        #expect(ApprovalMode.manual.disposition(hasCaution: false) == .card)
        #expect(ApprovalMode.manual.disposition(hasCaution: true) == .card)
        #expect(ApprovalMode.smart.disposition(hasCaution: false) == .autoApprove)
        #expect(ApprovalMode.smart.disposition(hasCaution: true) == .card)
        #expect(ApprovalMode.off.disposition(hasCaution: false) == .autoApprove)
        #expect(ApprovalMode.off.disposition(hasCaution: true) == .refuse)
    }

    // MARK: 224-0F — the model-free pin

    /// 224-0F's second half, because the type system cannot see the gate
    /// itself: `requestConfirmation` is legitimately `async` (it suspends on
    /// the user's decision), so the synchronous pin cannot cover it. This
    /// reads the approval path's own sources and fails if the symbol appears.
    ///
    /// It fails LOUDLY when it cannot read a file rather than passing on an
    /// empty read — an empty result and a negative result are the same bytes,
    /// and treating one as the other is this project's most expensive
    /// recurring mistake. If a later lane MOVES one of these files, this test
    /// breaks on purpose: the list IS the definition of "the approval path".
    ///
    /// **#332-a (2026-08-12).** That loud failure is correct in a simulator and
    /// wrong on a device, where the sources are absent by construction and the
    /// read can only ever 260. As landed, this bar red-ed the FIRST device suite
    /// run this project ever did, on both devices, and would have red-ed every
    /// one after it — and a permanently red test is one people learn to skip
    /// past. So it is SKIPPED off-simulator, explicitly and with a reason,
    /// rather than failed. Nothing about the simulator arm changes: the
    /// positive control and all three scans run exactly as before, so #224's
    /// ruling-5 guarantee is as strong as it was and is scored on every gate
    /// run. What a device run no longer does is pretend to score it.
    @Test(
        .enabled(
            if: repoSourcesAreReadableAtRuntime,
            """
            #332-a: this bar proves ruling 5 by READING the repo's Swift sources at \
            runtime, so it can only be scored where the test process shares the Mac's \
            filesystem — a simulator. Off-simulator the sources do not exist and the \
            read fails with NSCocoaErrorDomain 260, which measures the sandbox and not \
            the approval path. Skipped rather than failed; the simulator arm (positive \
            control included) is unchanged and runs on every gate.
            """
        )
    )
    func approvalPathSourcesNeverReferenceALanguageModelSession() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root

        /// Whole-line `//` and `///` comments only — enough for these files,
        /// which carry no block comments and no `//` inside a string literal.
        /// A TRAILING comment is deliberately NOT stripped, so a line like
        /// `foo() // LanguageModelSession` still trips: this fails safe.
        func code(_ source: String) -> String {
            source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }

        // POSITIVE CONTROL, and it is the whole reason to trust the rest. A
        // scan that has never fired is indistinguishable from a scan that
        // CANNOT fire — the same false-green shape as a success marker a no-op
        // satisfies. This file really does construct sessions (the #200-series
        // intent router), so if this expectation ever fails, the check has
        // gone blind and must be repointed rather than believed.
        let control = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Talaria/Services/Live/LocalChatBackend+IntentRouting.swift"),
            encoding: .utf8)
        #expect(code(control).contains("LanguageModelSession("),
                "the positive control no longer constructs a LanguageModelSession — this scan can no longer prove it detects one")

        let approvalPath = [
            "Talaria/Services/Support/ApprovalModeCore.swift",
            "Talaria/Services/Live/DeviceTools/ToolConfirmationCenter.swift",
            "Talaria/Services/Live/DeviceTools/DeviceActionTools.swift",
        ]
        for path in approvalPath {
            let source = try String(
                contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
            #expect(source.count > 500,
                    "read \(path) as \(source.count) bytes — an unreadable source must fail, never pass")
            let stripped = code(source)
            // …and the stripping must not have eaten the file, or the check
            // below would pass by measuring nothing.
            #expect(stripped.count > 300,
                    "\(path) stripped to \(stripped.count) bytes — nothing was actually scanned")
            #expect(!stripped.contains("LanguageModelSession"),
                    "\(path) references a LanguageModelSession outside a comment — ruling 5: the on-device model never goes on the approval path")
        }
    }

    /// 224-0E, ruling 2: the key is GLOBAL — one value on `UserSettings`,
    /// defaulted for a fresh install and for an old blob that predates it,
    /// clamped for a blob that names an unreachable mode, and degrading
    /// rather than failing the whole settings decode on junk.
    @Test func approvalModeIsAGlobalUserSettingsKeyDefaultingToManual() throws {
        #expect(UserSettings().approvalMode == .manual)

        let decoder = JSONDecoder()
        let legacy = try decoder.decode(
            UserSettings.self, from: Data(#"{"userName":"Owen"}"#.utf8))
        #expect(legacy.approvalMode == .manual)

        // A blob that NAMES an unreachable mode is clamped, not honoured —
        // "unreachable" is true of the DATA, not just of the missing UI.
        let armed = try decoder.decode(
            UserSettings.self, from: Data(#"{"userName":"Owen","approvalMode":"off"}"#.utf8))
        #expect(armed.approvalMode == .manual)

        // Junk degrades to the default instead of failing the whole settings
        // decode and resetting every other preference (the `appearanceTheme`
        // precedent).
        let junk = try decoder.decode(
            UserSettings.self, from: Data(#"{"userName":"Owen","approvalMode":"yolo"}"#.utf8))
        #expect(junk.approvalMode == .manual)
        #expect(junk.userName == "Owen")

        let roundTripped = try decoder.decode(
            UserSettings.self, from: JSONEncoder().encode(UserSettings()))
        #expect(roundTripped.approvalMode == .manual)
    }

    /// The gate reads the mode through a provider (the provider-closure
    /// pattern #283's transport seam established) and behaves exactly as it did
    /// before #224: a card, every time.
    @Test func theGateStagesACardUnderTheOnlyReachableMode() async {
        let center = ToolConfirmationCenter()
        center.modeProvider = { .manual }
        let task = Task {
            await center.requestConfirmation(
                title: "Create this reminder?",
                fields: [.init(key: "title", label: "Title", value: "Call Shelley")])
        }
        var attempts = 0
        while center.pending == nil && attempts < 2_000 { await Task.yield(); attempts += 1 }
        #expect(center.pending != nil)
        center.decline()
        _ = await task.value
    }

    /// 224-0E's real teeth. A mode with no handling in this build cannot be
    /// reached through settings — but if a later lane wires one in anyway,
    /// the gate must not act on it. It stages the card regardless: the
    /// default-CLOSED direction the gate was designed around (#29 — if the
    /// app dies with a card pending, nothing was ever created). Nothing here
    /// auto-approves, and nothing here refuses.
    @Test func anUnreachableModeStillStagesTheCardRatherThanActing() async {
        for mode in [ApprovalMode.smart, .off] {
            let center = ToolConfirmationCenter()
            center.modeProvider = { mode }
            let task = Task {
                await center.requestConfirmation(
                    title: "Schedule on this iPhone?",
                    caution: "EARLY MORNING — CHECK AM/PM",
                    fields: [.init(key: "request", label: "Alarm", value: "4:00am")])
            }
            var attempts = 0
            while center.pending == nil && attempts < 2_000 { await Task.yield(); attempts += 1 }
            #expect(center.pending?.caution == "EARLY MORNING — CHECK AM/PM")
            center.decline()
            let decision = await task.value
            if case .approved = decision {
                Issue.record("mode \(mode.rawValue) auto-approved instead of staging the card")
            }
        }
    }

    /// 224-0F, ruling 5: the on-device model never goes on the approval path.
    /// **The pin is the ABSENCE of `async` on this test body**, not any
    /// expectation inside it. Every decision the approval layer makes is a
    /// pure synchronous function of the staged values and the clock; a
    /// `LanguageModelSession` turn is necessarily `await`ed, so putting one on
    /// this path means making one of these functions `async` — which stops
    /// this file compiling. Placed at scaffold time so Phase 2 inherits the
    /// pin instead of adding it.
    @Test func approvalPathDecisionsAreSynchronousAndModelFree() {
        let now = Date()
        _ = ApprovalMode.resolved(.off)
        _ = ApprovalMode.manual.displayLabel
        _ = ReminderCreateTool.earlyMorningCaution(for: now)
        _ = ReminderCreateTool.dueCaution(for: now, now: now)
        _ = CalendarEventTool.startCaution(for: now, now: now)
        _ = AlarmTool.caution(for: AlarmService.parse("4:00am")!, now: now)
        #expect(ApprovalMode.manual.disposition(hasCaution: true) == .card)
    }
}
