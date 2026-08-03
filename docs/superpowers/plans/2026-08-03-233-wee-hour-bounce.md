# #233 Wee-Hour Bounce Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "Tomorrow at 4" must stop becoming a 4:00 AM reminder — the first wee-hour due per conversation bounces back to the model as an ask-AM/PM question, and any wee-hour card that does stage carries a forge-amber caution.

**Architecture:** A pure wee-hour predicate on `DeviceActionParsing`; a conversation-scoped latch on `ToolEventRelay` (NOT reset per turn, cleared by `clearConversation()`); a bounce in the shared `ReminderCreateTool.performCreate` engine returning ordinary tool output before any card stages; a `caution` field threaded through `ToolConfirmationCenter` into `ToolConfirmationCard`.

**Tech Stack:** Swift / SwiftUI, FoundationModels `Tool` protocol, swift-testing (`@Test`/`#expect`), xcodebuild against the Xcode-beta4 toolchain.

**Spec:** `docs/superpowers/specs/2026-08-03-233-bare-hour-reminders-design.md` (approved by Owen 2026-08-03).

## Global Constraints

- Every shell that builds or tests: `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`
- Branch: `claude/t27-233-bare-hour` (exists, rebased on main — work here, do not branch again)
- NO new Swift files (tests land in existing files) → **no `xcodegen` run needed**
- The bounce is tool OUTPUT, never a throw — #197's rule; the only sanctioned tool-path throw stays `ToolPhaseCutError` (#232)
- Wee-hour window: hours 0–6 inclusive = 00:00–06:59 local, exactly as in the spec
- Four-space indent, no force-unwraps on network code; comment style matches the surrounding `#NNN`-referenced idiom
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Test iteration: use plain `test` (never `test-without-building` — stale-.xctest trap), targeted with `-only-testing:`; background anything long and poll the log
- Test-run boilerplate (matches the gate's own sim resolution):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer
SIM_NAME="${TALARIA_SIM_NAME:-iPhone 17 Pro Max}"
SIM_UDID="$(xcrun simctl list devices available | grep -F "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
```

---

### Task 1: Wee-hour predicate + time-only formatter (pure, `DeviceActionParsing`)

**Files:**
- Modify: `Talaria/Services/Live/DeviceTools/DeviceActionTools.swift` (inside `enum DeviceActionParsing`, after `displayDate`, ~line 44)
- Test: `TalariaTests/DeviceActionToolsTests.swift` (add to the parsing section near the `parseDateTime` tests)

**Interfaces:**
- Consumes: `DeviceActionParsing.parseDateTime(_:) -> Date?` (existing)
- Produces: `DeviceActionParsing.isEarlyMorning(_ date: Date) -> Bool` and `DeviceActionParsing.timeOnly(_ date: Date) -> String` — Tasks 3 and 4 call both.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func isEarlyMorningCoversMidnightThroughSixFiftyNine() {
    #expect(DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T00:00")!))
    #expect(DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T04:00")!))
    #expect(DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T06:59")!))
    #expect(!DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T07:00")!))
    #expect(!DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T16:00")!))
    #expect(!DeviceActionParsing.isEarlyMorning(DeviceActionParsing.parseDateTime("2026-08-05T23:00")!))
}

@Test func timeOnlyRendersJustTheClockTime() {
    let four = DeviceActionParsing.parseDateTime("2026-08-05T04:00")!
    let rendered = DeviceActionParsing.timeOnly(four)
    // Locale-safe: no hardcoded "4:00 AM" — assert it is short (no date parts)
    // and that the full display form ends with it.
    #expect(!rendered.isEmpty)
    #expect(rendered.count < 12)
    #expect(DeviceActionParsing.displayDate(four).hasSuffix(rendered))
}
```

- [ ] **Step 2: Run to verify they fail (missing members = the failure)**

```bash
nohup env DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination "platform=iOS Simulator,id=$SIM_UDID" -only-testing:TalariaTests/DeviceActionToolsTests > /tmp/t233-task1-red.log 2>&1 &
```

Poll `tail -5 /tmp/t233-task1-red.log`. Expected: **BUILD FAILURE** — `type 'DeviceActionParsing' has no member 'isEarlyMorning'` (and `timeOnly`). A compile failure IS the watched RED here.

- [ ] **Step 3: Implement in `DeviceActionParsing` (after `displayDate`)**

```swift
    /// #233: the wee-hour window — hours 0–6 (00:00–06:59 local). A due
    /// time here is at least as likely the model's half-day default as the
    /// user's actual ask ("tomorrow at 4" arrived as T04:00), so the create
    /// tool treats the first one per conversation as a question.
    nonisolated static func isEarlyMorning(_ date: Date) -> Bool {
        Calendar.current.component(.hour, from: date) <= 6
    }

    /// Time-only display form for the card's caution row.
    nonisolated static func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
```

- [ ] **Step 4: Re-run the same command; expected: both tests PASS, prior test count for the file unchanged otherwise**

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/DeviceTools/DeviceActionTools.swift TalariaTests/DeviceActionToolsTests.swift
git commit -m "#233: wee-hour predicate + time-only formatter (pure, pinned)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Conversation-scoped latch on `ToolEventRelay`

**Files:**
- Modify: `Talaria/Services/Live/DeviceTools/DeviceToolBelt.swift` (inside `final class ToolEventRelay`, after the `refusalsThisTurn` declaration ~line 127, and note `beginTurn()` at ~line 138 must NOT touch it)
- Modify: `Talaria/Services/Live/LocalChatBackend.swift` (`clearConversation()` at ~line 680)
- Test: `TalariaTests/ToolCallInstrumentTests.swift` (the file that already owns relay/governor/backend seams and has `makeBackend()` at ~line 136)

**Interfaces:**
- Consumes: `ToolEventRelay.beginTurn()` (existing), `LocalChatBackend.clearConversation()` (existing), `LocalChatBackend.installTools(_:relay:)` (existing), test helper `makeBackend()` (existing in this test file)
- Produces: `ToolEventRelay.claimEarlyMorningAsk() -> Bool` and `ToolEventRelay.endConversationToolState()` — Task 3 calls `claimEarlyMorningAsk()`; `clearConversation()` calls `endConversationToolState()`.

- [ ] **Step 1: Write the failing tests (in ToolCallInstrumentTests.swift)**

```swift
// MARK: - #233 conversation latch

@Test func earlyMorningAskClaimsExactlyOncePerConversation() {
    let relay = ToolEventRelay()
    #expect(relay.claimEarlyMorningAsk())
    #expect(!relay.claimEarlyMorningAsk())
}

/// The ask/answer round-trip spans two turns — a turn boundary must not
/// re-arm the bounce, or the model asks again after the user answers.
@Test func beginTurnDoesNotClearTheEarlyMorningLatch() {
    let relay = ToolEventRelay()
    _ = relay.claimEarlyMorningAsk()
    relay.beginTurn()
    #expect(!relay.claimEarlyMorningAsk())
}

@Test func clearConversationResetsTheEarlyMorningLatch() async throws {
    let backend = makeBackend()
    let relay = ToolEventRelay()
    backend.installTools([], relay: relay)
    #expect(relay.claimEarlyMorningAsk())
    _ = try await backend.clearConversation()
    #expect(relay.claimEarlyMorningAsk())
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
nohup env DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination "platform=iOS Simulator,id=$SIM_UDID" -only-testing:TalariaTests/ToolCallInstrumentTests > /tmp/t233-task2-red.log 2>&1 &
```

Expected: BUILD FAILURE — `no member 'claimEarlyMorningAsk'`.

- [ ] **Step 3: Implement the latch on `ToolEventRelay` (after `refusalsThisTurn`)**

```swift
    /// #233: conversation-scoped — deliberately NOT reset in beginTurn(),
    /// because the ask/answer round-trip spans two turns. Cleared only by
    /// endConversationToolState() (fresh chat) and process launch.
    private(set) var earlyMorningAskIssued = false

    /// #233: true exactly once per conversation. The reminder tool bounces
    /// on true and proceeds on false — so a user-confirmed "yes, 4 AM"
    /// re-call cannot loop, and a model that ignores the ask degrades to
    /// staging the card, where the caution row is the backstop.
    func claimEarlyMorningAsk() -> Bool {
        if earlyMorningAskIssued { return false }
        earlyMorningAskIssued = true
        return true
    }

    /// #233: the conversation-boundary reset. Turn-scoped state belongs in
    /// beginTurn(); anything conversation-scoped resets here instead.
    func endConversationToolState() {
        earlyMorningAskIssued = false
    }
```

- [ ] **Step 4: Wire the fresh-chat clear in `LocalChatBackend.clearConversation()` (after `escalationOfferDismissed = false`)**

```swift
        // #233: the wee-hour AM/PM ask is per-conversation.
        toolRelay?.endConversationToolState()
```

- [ ] **Step 5: Re-run the same command; expected: all three PASS**

- [ ] **Step 6: Commit**

```bash
git add Talaria/Services/Live/DeviceTools/DeviceToolBelt.swift Talaria/Services/Live/LocalChatBackend.swift TalariaTests/ToolCallInstrumentTests.swift
git commit -m "#233: conversation-scoped wee-hour latch on the relay, cleared by clearConversation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: The bounce in `performCreate` (bars 233-A and 233-B)

**Files:**
- Modify: `Talaria/Services/Live/DeviceTools/DeviceActionTools.swift` — `ReminderCreateTool.call` (~line 111), `performCreate` (~line 126), and the two DEBUG twin call sites: `ReminderCreateToolRequiredFields.call` (~line 218 area) and `ReminderCreateToolGuidefix.call` (~line 256 area) — find both with `grep -n "performCreate" Talaria/Services/Live/DeviceTools/DeviceActionTools.swift`
- Test: `TalariaTests/DeviceActionToolsTests.swift`

**Interfaces:**
- Consumes: `DeviceActionParsing.isEarlyMorning(_:)` (Task 1), `ToolEventRelay.claimEarlyMorningAsk()` (Task 2), `ToolConfirmationCenter.autoDeclineForBattery` (existing, DEBUG)
- Produces: `performCreate(rawTitle:rawDue:rawList:relay:confirmations:) -> String` — the new `relay:` parameter, which Task 4's end-to-end test also uses. Bounce string constant shape: `"The due time reads as <displayDate> — early morning. Ask the user whether they meant AM or PM, then create the reminder with the time they confirm."`

- [ ] **Step 1: Write the failing tests**

```swift
// MARK: - #233 the wee-hour bounce

@Test func weeHourDueBouncesOnceThenProceeds() async throws {
    let relay = ToolEventRelay()
    relay.governor = ToolCallGovernor()
    let center = ToolConfirmationCenter()
    center.autoDeclineForBattery = true   // resolves the gate instantly: no card, no EventKit, no hang
    let tool = ReminderCreateTool(relay: relay, confirmations: center)
    relay.beginTurn()

    let first = try await tool.call(arguments: .init(
        title: "Call Shelley", due: "2026-08-05T04:00", list: nil))
    #expect(first.contains("Ask the user whether they meant AM or PM"))
    #expect(first.contains("early morning"))

    let second = try await tool.call(arguments: .init(
        title: "Call Shelley", due: "2026-08-05T04:00", list: nil))
    #expect(second == "The user declined — no reminder was created.")

    // 233-B: both attempts were EXECUTED calls — the bounce is tool output,
    // never a governor refusal, so #232's counter must not move.
    #expect(relay.executedCallsThisTurn == 2)
    #expect(relay.refusalsThisTurn == 0)
}

@Test func daytimeDueNeverBounces() async throws {
    let relay = ToolEventRelay()
    let center = ToolConfirmationCenter()
    center.autoDeclineForBattery = true
    let tool = ReminderCreateTool(relay: relay, confirmations: center)
    relay.beginTurn()
    let result = try await tool.call(arguments: .init(
        title: "Call Shelley", due: "2026-08-05T16:00", list: nil))
    #expect(result == "The user declined — no reminder was created.")
    #expect(relay.claimEarlyMorningAsk())   // latch untouched by a daytime due
}

@Test func noDueDateNeverBounces() async throws {
    let relay = ToolEventRelay()
    let center = ToolConfirmationCenter()
    center.autoDeclineForBattery = true
    let tool = ReminderCreateTool(relay: relay, confirmations: center)
    relay.beginTurn()
    let result = try await tool.call(arguments: .init(
        title: "Call Shelley", due: nil, list: nil))
    #expect(result == "The user declined — no reminder was created.")
    #expect(relay.claimEarlyMorningAsk())
}
```

- [ ] **Step 2: Run to verify they fail**

Same `-only-testing:TalariaTests/DeviceActionToolsTests` invocation, log `/tmp/t233-task3-red.log`. Expected: tests COMPILE (tool.call's surface is unchanged) and **FAIL on the first `#expect`** — current code auto-declines to "The user declined — no reminder was created." instead of bouncing.

- [ ] **Step 3: Implement — signature + bounce + call sites**

`performCreate` gains `relay:` and the bounce goes immediately after `parsedDue` is computed (before `requestConfirmation`):

```swift
    nonisolated static func performCreate(
        rawTitle: String, rawDue: String, rawList: String,
        relay: ToolEventRelay,
        confirmations: ToolConfirmationCenter
    ) async -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "No reminder title was given — nothing staged." }

        let parsedDue = DeviceActionParsing.parseDateTime(rawDue)
        // #233: the model qualifies bare hours before the tool ever runs
        // ("tomorrow at 4" arrived here as T04:00), so the ambiguity is
        // invisible by now — the first wee-hour due per conversation is
        // treated as a question, not an order. Ordinary tool OUTPUT, never
        // a throw (#197); an EXECUTED call, not a governor refusal (#232's
        // counter must not move). The latch admits the re-call, so a
        // user-confirmed "yes, 4 AM" cannot loop.
        if let parsedDue, DeviceActionParsing.isEarlyMorning(parsedDue),
           await relay.claimEarlyMorningAsk() {
            return "The due time reads as \(DeviceActionParsing.displayDate(parsedDue)) — early morning. Ask the user whether they meant AM or PM, then create the reminder with the time they confirm."
        }
```

(The rest of the body is unchanged.) Then update all three call sites to pass the relay — each already has `relay` in scope:

```swift
        return await Self.performCreate(
            rawTitle: title, rawDue: arguments.due ?? "", rawList: arguments.list ?? "",
            relay: relay, confirmations: confirmations
        )
```

(In the two DEBUG twins the receiver is `ReminderCreateTool.performCreate` and the argument spellings differ slightly — keep each site's existing raw-argument expressions, add only `relay: relay`.)

- [ ] **Step 4: Re-run; expected: all three new tests PASS and every pre-existing DeviceActionToolsTests test still PASSES (count must MOVE up by 3 from the last green run of this file)**

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/DeviceTools/DeviceActionTools.swift TalariaTests/DeviceActionToolsTests.swift
git commit -m "#233: the wee-hour bounce — first 00:00-06:59 due per conversation returns ask-AM/PM (233-A/B)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Caution plumbing through the confirmation center (bar 233-C, sim half)

**Files:**
- Modify: `Talaria/Services/Live/DeviceTools/ToolConfirmationCenter.swift` — `PendingConfirmation` (~line 28), `requestConfirmation` (~line 104, and its staging at ~line 137)
- Modify: `Talaria/Services/Live/DeviceTools/DeviceActionTools.swift` — `ReminderCreateTool` (new pure static) and `performCreate`'s `requestConfirmation` call (~line 134)
- Test: `TalariaTests/DeviceActionToolsTests.swift`

**Interfaces:**
- Consumes: `DeviceActionParsing.isEarlyMorning(_:)` / `timeOnly(_:)` (Task 1), `performCreate(...relay:confirmations:)` (Task 3)
- Produces: `PendingConfirmation.caution: String?`; `requestConfirmation(title:detail:caution:fields:)` with `caution: String? = nil`; `ReminderCreateTool.earlyMorningCaution(for: Date?) -> String?`. Task 5's card renders `confirmation.caution`.

- [ ] **Step 1: Write the failing tests**

```swift
// MARK: - #233 the caution row (plumbing)

@Test func earlyMorningCautionOnlyForWeeHours() {
    let four = DeviceActionParsing.parseDateTime("2026-08-05T04:00")!
    #expect(ReminderCreateTool.earlyMorningCaution(for: four)
        == "EARLY MORNING — \(DeviceActionParsing.timeOnly(four))")
    #expect(ReminderCreateTool.earlyMorningCaution(for: DeviceActionParsing.parseDateTime("2026-08-05T16:00")!) == nil)
    #expect(ReminderCreateTool.earlyMorningCaution(for: nil) == nil)
}

@Test func stagedCardCarriesTheCautionThroughTheGate() async {
    let center = ToolConfirmationCenter()
    let task = Task {
        await center.requestConfirmation(
            title: "Create this reminder?",
            caution: "EARLY MORNING — 4:00 AM",
            fields: [.init(key: "title", label: "Title", value: "Call Shelley")])
    }
    var attempts = 0
    while center.pending == nil && attempts < 2000 { await Task.yield(); attempts += 1 }
    #expect(center.pending?.caution == "EARLY MORNING — 4:00 AM")
    center.decline()
    _ = await task.value
}

/// The re-call path end-to-end: latch already claimed, a wee-hour due
/// stages a REAL card, and that card carries the caution (233-C).
@Test func weeHourRecallStagesCardWithCaution() async {
    let relay = ToolEventRelay()
    let center = ToolConfirmationCenter()
    _ = relay.claimEarlyMorningAsk()
    let task = Task {
        await ReminderCreateTool.performCreate(
            rawTitle: "Call Shelley", rawDue: "2026-08-05T04:00", rawList: "",
            relay: relay, confirmations: center)
    }
    var attempts = 0
    while center.pending == nil && attempts < 2000 { await Task.yield(); attempts += 1 }
    #expect(center.pending?.caution != nil)
    center.decline()
    let result = await task.value
    #expect(result == "The user declined — no reminder was created.")
}
```

- [ ] **Step 2: Run to verify they fail** (`/tmp/t233-task4-red.log`). Expected: BUILD FAILURE — `no member 'earlyMorningCaution'`, `extra argument 'caution'`, `no member 'caution'`.

- [ ] **Step 3: Implement**

`ToolConfirmationCenter.PendingConfirmation` — add after `detail`:

```swift
        /// #233: forge-amber warning line, e.g. "EARLY MORNING — 4:00 AM".
        /// Nil on every card that stages nothing unusual.
        let caution: String?
```

`requestConfirmation` — new defaulted parameter, threaded into the staging:

```swift
    func requestConfirmation(title: String, detail: String? = nil, caution: String? = nil, fields: [Field]) async -> Decision {
```

and at the staging line:

```swift
            pending = PendingConfirmation(title: title, detail: detail, caution: caution, fields: fields)
```

`ReminderCreateTool` — new pure static next to `resolveEditedDate`:

```swift
    /// #233: the card's last line of defense for a wee-hour due — the case
    /// where the model ignored the bounce, or the user confirmed AM. Nil
    /// for daytime dues so normal cards render byte-identically to today.
    nonisolated static func earlyMorningCaution(for date: Date?) -> String? {
        guard let date, DeviceActionParsing.isEarlyMorning(date) else { return nil }
        return "EARLY MORNING — \(DeviceActionParsing.timeOnly(date))"
    }
```

`performCreate`'s gate call gains the caution:

```swift
        let decision = await confirmations.requestConfirmation(
            title: "Create this reminder?",
            detail: nil,
            caution: Self.earlyMorningCaution(for: parsedDue),
            fields: [
```

- [ ] **Step 4: Re-run; expected: the three new tests PASS, file count moved up by 3, no other center test regressed** (the memberwise-init change is confined to `requestConfirmation` — `PendingConfirmation` is constructed nowhere else; verify with `grep -rn "PendingConfirmation(" Talaria TalariaTests`)

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/DeviceTools/ToolConfirmationCenter.swift Talaria/Services/Live/DeviceTools/DeviceActionTools.swift TalariaTests/DeviceActionToolsTests.swift
git commit -m "#233: caution threaded through the confirm gate; wee-hour re-call cards carry it (233-C sim half)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: The forge-amber caution row on the card

**Files:**
- Modify: `Talaria/Features/Chat/ToolConfirmationCard.swift` (insert between the fields `VStack` closing at ~line 51 and the `detail` block at ~line 53)

**Interfaces:**
- Consumes: `confirmation.caution: String?` (Task 4), `Design.Brand.forge`, `MonoLabel(_:size:weight:tracking:color:)`, `Design.Spacing.xs`, `Design.Size.iconSmall` (all existing)
- Produces: the rendered row — no API.

- [ ] **Step 1: Insert the row**

```swift
            if let caution = confirmation.caution {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: Design.Size.iconSmall))
                        .foregroundStyle(Design.Brand.forge)
                    MonoLabel(caution.uppercased(), size: 11, weight: .semibold,
                              tracking: Design.Tracking.mono, color: Design.Brand.forge)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Caution: \(caution)")
            }
```

- [ ] **Step 2: Compile check (Debug, backgrounded, poll the log)**

```bash
nohup env DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO > /tmp/t233-task5-build.log 2>&1 &
```

Expected: `** BUILD SUCCEEDED **` in the log. (View-only change; 233-C's plumbing test from Task 4 pins the data path, the visual is bar 233-D/E's device half.)

- [ ] **Step 3: Commit**

```bash
git add Talaria/Features/Chat/ToolConfirmationCard.swift
git commit -m "#233: forge-amber EARLY MORNING caution row on the confirm card

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: OPEN_ITEMS record, the gate, the PR

**Files:**
- Modify: `OPEN_ITEMS.md` (#233 entry header + a built-note blockquote under the bars)

**Interfaces:**
- Consumes: everything above, `scripts/mac/lane-gate.sh`
- Produces: the PR.

- [ ] **Step 1: Update the #233 entry** — header suffix becomes `— **BOUNCE BUILT 2026-08-03; 233-A/B/C green in suite; device bars 233-D/E owed to the next OTA**`, plus a short dated blockquote under the bars block stating: mechanical bars met by tests written first (name the test functions), device bars NOT claimed, and the OTA test script for Owen (evening send of trial 3's prompt verbatim; explicit "5 AM" probe).

- [ ] **Step 2: Run the gate (backgrounded — it takes minutes), poll until verdict**

```bash
nohup env DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer scripts/mac/lane-gate.sh > /tmp/t233-gate.log 2>&1 &
```

Poll `tail -5 /tmp/t233-gate.log`. Required: the gate's own **positive** markers — `GATE: PASS` (which internally requires the Debug suite marker AND the Release build marker). Also verify the suite's reported test count MOVED vs main's 1537 (expected: 1537 + 9 = 1546; if the count did not move, purge `<derived-data>/Build/Intermediates.noindex` and re-run — resolve the DD hash from `info.plist`, never from memory).

- [ ] **Step 3: Commit OPEN_ITEMS, push, open the PR**

```bash
git add OPEN_ITEMS.md
git commit -m "OPEN_ITEMS #233: bounce built, mechanical bars green, device bars owed

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
gh pr create --title "#233: the wee-hour bounce and the loud card (OPEN_ITEMS numbering)" --body "$(cat <<'EOF'
The first wee-hour (00:00-06:59) reminder due per conversation now bounces back to the model as an ask-AM/PM question before any card stages; the latch admits the re-call so a confirmed "yes, 4 AM" cannot loop; and any wee-hour card that does stage carries a forge-amber EARLY MORNING caution. Spec: docs/superpowers/specs/2026-08-03-233-bare-hour-reminders-design.md (approved by Owen 2026-08-03).

**Verification:** TDD, RED watched per task. Bars 233-A/B/C green in the suite; gate PASS (Debug suite + Release build). **Device bars NOT claimed:** 233-D (evening "tomorrow at 4" gets asked AM or PM) and 233-E (explicit "5 AM" completes with one bounce, caution on card) are owed to the next OTA.

Owen routes the merge; the branch is stageable for OTA as-is.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review (run after writing — completed 2026-08-03)

1. **Spec coverage:** bounce (Task 3), latch + fresh-chat clear (Task 2), predicate/window (Task 1), caution plumbing (Task 4), card row (Task 5), bars/OPEN_ITEMS/gate (Task 6). Device bars 233-D/E are explicitly out of the sim's reach — recorded as owed, not a gap.
2. **Placeholders:** none — every step carries code or an exact command.
3. **Type consistency:** `claimEarlyMorningAsk()` / `endConversationToolState()` / `earlyMorningCaution(for:)` / `performCreate(rawTitle:rawDue:rawList:relay:confirmations:)` spelled identically at definition and every use site; `PendingConfirmation.caution` matches the card's `confirmation.caution`.
