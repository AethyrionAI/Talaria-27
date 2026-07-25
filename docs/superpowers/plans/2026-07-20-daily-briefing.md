# Daily Briefing (app half, #126) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render agent-cron "daily briefing" inbox items richly — full-screen markdown detail view (charts render free), read-aloud, a latest-briefing widget, and a `hermes://briefing` deep link — recognized by `category: "briefing"` in the item payload.

**Architecture:** A briefing is an ordinary relay inbox item (`kind: "notification"`) whose `payload` string-map carries `category: "briefing"` and optionally `speakable`. Recognition + content derivation are pure `InboxItem` extensions (new file). The detail view wraps the EXISTING `MarkdownContentView` (chart fences already parse/render — #100) and speaks through the EXISTING shared `SpeechOutputService` environment instance (audio-session law enforced inside the service). Widget data rides the existing `HermesWidgetData` app-group snapshot (two lockstep copies) stamped in `AppContainer.updateWidgetData()` — which already runs right after the push-wake inbox refresh. One additive connector change (discovered gap): `send_inbox_item` must forward `payload`, which the relay DTO/DB/serializer and app decoder already carry end-to-end.

**Tech Stack:** SwiftUI + swift-testing (`@Test`/`#expect`), WidgetKit `AppIntentConfiguration`, xcodegen, Python/pytest (connector).

## Global Constraints

- Toolchain: prefix every xcodebuild/xcodegen command with `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` (iOS 27 beta; release Xcode cannot build it).
- `xcodegen generate` is MANDATORY after adding Swift files; afterwards verify entitlements survived: `grep -E "aps-environment|weatherkit" Talaria/Talaria.entitlements` must show BOTH.
- Test destination is the CC sim by id: `-destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557'` (CC-M4a-Baseline). Do NOT pass `CODE_SIGNING_ALLOWED=NO` on test runs (strips sim HealthKit entitlements and kills keychain writes).
- Suite floor: ≥ 755 tests / 62 suites (dispatch). Current baseline ~913/80 (#137 lane) — full suite must stay green, no regressions.
- Connector suite must stay green (baseline 104 passed + 1 macOS-only skip).
- `kind` stays within the app enum (alert/approval/notification/reminder/suggestion). Tolerant decode (#58): unknown/missing payload fields → render what exists.
- Real data only: honest empty states, never mocked values.
- The BOTH copies of `HermesWidgetData.swift` (`Talaria/Models/` and `TalariaWidgets/Models/`) must stay byte-identical.
- Do not touch `managesAudioSession` ownership or any `AVAudioSession` call (#106 house law). No new voice/audio services.
- No relay changes. Connector change limited to the additive `payload` passthrough (flagged for Owen in the PR — the dispatch's "path exists" premise was wrong for this one field).
- Branch: `claude/t27-126-daily-briefing` off up-to-date `origin/main`. One PR. Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Full builds exceed the 4-min cap — run backgrounded (`nohup … &` or Bash run_in_background) and poll the log.

---

### Task 1: Briefing recognition + content helpers

**Files:**
- Create: `Talaria/Models/InboxBriefing.swift`
- Test: `TalariaTests/BriefingTests.swift`

**Interfaces:**
- Consumes: `InboxItem` (`Talaria/Models/InboxItem.swift` — `payload: [String: String]?`, `timestamp: Date`, `body: String`), `LocalIntelligenceService.firstMeaningfulLine(of:)` / `.condensedLine(_:limit:)` (nonisolated statics, `Talaria/Services/Live/LocalIntelligenceService.swift:455-495`).
- Produces: `InboxItem.isBriefing: Bool`, `InboxItem.briefingSpeakableText: String`, `InboxItem.latestBriefing(in:) -> InboxItem?`, `InboxItem.strippingFencedBlocks(from:) -> String` — used by Tasks 2, 3, 4.

- [ ] **Step 1: Branch off up-to-date origin/main**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
git fetch origin && git rev-list --left-right --count main...origin/main   # expect 0<TAB>0
git switch -c claude/t27-126-daily-briefing origin/main
```

- [ ] **Step 2: Write the failing tests**

Create `TalariaTests/BriefingTests.swift`:

```swift
import Foundation
import Testing
@testable import Talaria

// #126: a briefing is recognized by payload category alone — tolerant of the
// producer's kind, honest when fields are missing (#58 lesson).

@Suite("Briefing recognition")
struct BriefingRecognitionTests {

    private func item(
        type: InboxItemType = .notification,
        payload: [String: String]? = nil,
        timestamp: Date = .now,
        body: String = "Body"
    ) -> InboxItem {
        InboxItem(type: type, title: "Title", body: body, timestamp: timestamp, payload: payload)
    }

    @Test("notification + category briefing is a briefing")
    func recognizesBriefing() {
        #expect(item(payload: ["category": "briefing"]).isBriefing)
    }

    @Test("Absent category, absent payload, or another category is NOT a briefing")
    func rejectsNonBriefings() {
        #expect(!item(payload: nil).isBriefing)
        #expect(!item(payload: [:]).isBriefing)
        #expect(!item(payload: ["category": "digest"]).isBriefing)
        #expect(!item(payload: ["speakable": "hi"]).isBriefing)
    }

    @Test("Recognition keys on category alone — a briefing payload on another kind still renders richly")
    func toleratesUnexpectedKind() {
        #expect(item(type: .reminder, payload: ["category": "briefing"]).isBriefing)
    }

    @Test("latestBriefing picks the newest briefing and ignores non-briefings")
    func latestSelection() {
        let old = item(payload: ["category": "briefing"], timestamp: Date(timeIntervalSinceReferenceDate: 1_000))
        let new = item(payload: ["category": "briefing"], timestamp: Date(timeIntervalSinceReferenceDate: 2_000))
        let noise = item(payload: nil, timestamp: Date(timeIntervalSinceReferenceDate: 3_000))
        #expect(InboxItem.latestBriefing(in: [old, noise, new])?.id == new.id)
        #expect(InboxItem.latestBriefing(in: [noise]) == nil)
        #expect(InboxItem.latestBriefing(in: []) == nil)
    }
}

@Suite("Briefing speakable text")
struct BriefingSpeakableTests {

    private func briefing(speakable: String?, body: String) -> InboxItem {
        var payload = ["category": "briefing"]
        if let speakable { payload["speakable"] = speakable }
        return InboxItem(type: .notification, title: "T", body: body, payload: payload)
    }

    @Test("speakable wins when present, trimmed")
    func speakableWins() {
        #expect(briefing(speakable: "  Good morning.  ", body: "ignored").briefingSpeakableText == "Good morning.")
    }

    @Test("Blank speakable falls back to the fence-stripped body")
    func blankSpeakableFallsBack() {
        #expect(briefing(speakable: "   ", body: "Hello there.").briefingSpeakableText == "Hello there.")
        #expect(briefing(speakable: nil, body: "Hello there.").briefingSpeakableText == "Hello there.")
    }

    @Test("Fallback drops fenced blocks — markers AND contents (chart JSON is not speech)")
    func fallbackStripsFences() {
        let body = "Sleep was solid.\n```chart\n{\"type\":\"bar\"}\n```\nThree events today."
        #expect(briefing(speakable: nil, body: body).briefingSpeakableText == "Sleep was solid.\n\nThree events today.")
    }

    @Test("Unterminated fence drops the tail — parity with the parser, which keeps it a code block")
    func unterminatedFenceDropsTail() {
        let body = "Intro line.\n```chart\n{\"type\":"
        #expect(InboxItem.strippingFencedBlocks(from: body) == "Intro line.")
    }
}
```

- [ ] **Step 3: Run to verify failure (compile error — helpers don't exist)**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodegen generate
grep -E "aps-environment|weatherkit" Talaria/Talaria.entitlements   # both must appear
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' test -only-testing:TalariaTests/BriefingRecognitionTests 2>&1 | tail -20
```
Expected: BUILD FAILED — `value of type 'InboxItem' has no member 'isBriefing'`.

- [ ] **Step 4: Implement `Talaria/Models/InboxBriefing.swift`**

```swift
import Foundation

// #126: daily-briefing recognition + content derivation. A briefing is an
// ordinary inbox item whose payload carries `category: "briefing"`; every
// other contract field is optional and absence degrades gracefully (#58).
extension InboxItem {
    enum BriefingPayloadKey {
        static let category = "category"
        static let speakable = "speakable"
    }

    static let briefingCategoryValue = "briefing"

    /// Keys on the payload category alone — tolerant of the producer sending
    /// an unexpected `kind`; an absent category is a normal item.
    var isBriefing: Bool {
        payload?[BriefingPayloadKey.category] == Self.briefingCategoryValue
    }

    /// Read-aloud source: the producer's `speakable` when non-blank, else the
    /// body with fenced blocks removed (chart JSON read aloud is noise —
    /// SpeechOutputService only strips fence MARKERS, not contents).
    var briefingSpeakableText: String {
        if let speakable = payload?[BriefingPayloadKey.speakable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !speakable.isEmpty {
            return speakable
        }
        return Self.strippingFencedBlocks(from: body)
    }

    /// The widget shows the LATEST briefing regardless of how many arrive.
    static func latestBriefing(in items: [InboxItem]) -> InboxItem? {
        items.filter(\.isBriefing).max { $0.timestamp < $1.timestamp }
    }

    /// Removes fenced blocks — markers AND contents. Same line-based toggle
    /// as `LocalIntelligenceService.meaningfulLines`, but keeps prose lines
    /// verbatim (speech wants sentences, not title-trimmed fragments). An
    /// unterminated fence drops the tail, matching the parser's refusal to
    /// treat an open fence as prose.
    static func strippingFencedBlocks(from text: String) -> String {
        var kept: [Substring] = []
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if !inFence { kept.append(line) }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: Regen + run to verify pass**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' test -only-testing:TalariaTests/BriefingRecognitionTests -only-testing:TalariaTests/BriefingSpeakableTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Talaria/Models/InboxBriefing.swift TalariaTests/BriefingTests.swift Talaria.xcodeproj
git commit -m "feat(#126): briefing recognition + speakable derivation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Widget snapshot fields + briefing stamping

**Files:**
- Modify: `Talaria/Models/HermesWidgetData.swift` (after `var appearanceAccent: String?`)
- Modify: `TalariaWidgets/Models/HermesWidgetData.swift` (identical edit — lockstep)
- Modify: `Talaria/Models/InboxBriefing.swift` (append the stamping extension)
- Test: `TalariaTests/BriefingTests.swift` (append suite)

**Interfaces:**
- Consumes: `InboxItem.latestBriefing(in:)` (Task 1), `LocalIntelligenceService.firstMeaningfulLine(of:)` + `.condensedLine(_:limit:)`.
- Produces: `HermesWidgetData.briefingTitle/briefingFirstLine/briefingReceivedAt: String?/String?/Date?` and `mutating func stampBriefing(from items: [InboxItem])` — used by Tasks 3 and 5.

- [ ] **Step 1: Write the failing tests (append to `TalariaTests/BriefingTests.swift`)**

```swift
@Suite("Briefing widget snapshot")
struct BriefingWidgetSnapshotTests {

    @Test("Pre-#126 snapshot JSON (no briefing keys) still decodes")
    func oldSnapshotDecodes() throws {
        let old = #"{"hostOnline":true,"voiceSessionActive":false,"updatedAt":770000000}"#
        let data = try JSONDecoder().decode(HermesWidgetData.self, from: Data(old.utf8))
        #expect(data.briefingTitle == nil)
        #expect(data.briefingFirstLine == nil)
        #expect(data.briefingReceivedAt == nil)
    }

    @Test("Briefing fields round-trip through the app-group encoding")
    func roundTrip() throws {
        var data = HermesWidgetData.empty
        data.briefingTitle = "Morning briefing — Mon Jul 20"
        data.briefingFirstLine = "Sleep 7h 24m · 3 events today"
        data.briefingReceivedAt = Date(timeIntervalSinceReferenceDate: 770_000_000)
        let decoded = try JSONDecoder().decode(HermesWidgetData.self, from: JSONEncoder().encode(data))
        #expect(decoded.briefingTitle == data.briefingTitle)
        #expect(decoded.briefingFirstLine == data.briefingFirstLine)
        #expect(decoded.briefingReceivedAt == data.briefingReceivedAt)
    }

    @Test("Stamping fills title, condensed first line, and timestamp from the newest briefing")
    func stampsNewestBriefing() {
        let body = "## Sleep\n```chart\n{\"type\":\"bar\"}\n```\nYou slept 7h 24m — solid.\nMore detail."
        let older = InboxItem(
            type: .notification, title: "Old", body: "Old body",
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
            payload: ["category": "briefing"]
        )
        let newer = InboxItem(
            type: .notification, title: "Morning briefing — Mon Jul 20", body: body,
            timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
            payload: ["category": "briefing"]
        )
        var data = HermesWidgetData.empty
        data.stampBriefing(from: [older, newer])
        #expect(data.briefingTitle == "Morning briefing — Mon Jul 20")
        // First meaningful line: heading markers stripped → "Sleep" is the
        // first line that carries words; fences are skipped entirely.
        #expect(data.briefingFirstLine == "Sleep")
        #expect(data.briefingReceivedAt == Date(timeIntervalSinceReferenceDate: 2_000))
    }

    @Test("No briefing in the fetch leaves existing stamped values untouched — a mid-day empty fetch must not wipe the widget")
    func absentBriefingKeepsStampedValues() {
        var data = HermesWidgetData.empty
        data.briefingTitle = "Kept"
        data.briefingFirstLine = "Kept line"
        data.briefingReceivedAt = Date(timeIntervalSinceReferenceDate: 5)
        let noise = InboxItem(type: .alert, title: "A", body: "B")
        data.stampBriefing(from: [noise])
        #expect(data.briefingTitle == "Kept")
        #expect(data.briefingFirstLine == "Kept line")
        #expect(data.briefingReceivedAt == Date(timeIntervalSinceReferenceDate: 5))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Same xcodebuild as Task 1 Step 5 but `-only-testing:TalariaTests/BriefingWidgetSnapshotTests`. Expected: BUILD FAILED — `no member 'briefingTitle'`.

- [ ] **Step 3: Implement**

In BOTH `HermesWidgetData.swift` copies, immediately after `var appearanceAccent: String?`:

```swift
    // #126: latest daily briefing — stamped app-side from the inbox so the
    // widget renders with zero markdown work of its own.
    var briefingTitle: String?
    var briefingFirstLine: String?
    var briefingReceivedAt: Date?
```

Append to `Talaria/Models/InboxBriefing.swift` (app target only — the widget copy of `HermesWidgetData` must NOT gain this, it references `LocalIntelligenceService`):

```swift
// #126: widget stamping — app target only (LocalIntelligenceService is not
// compiled into the widget; the widget reads the pre-derived strings).
extension HermesWidgetData {
    /// Stamp the latest briefing into the snapshot. When no briefing is
    /// visible in `items`, existing values are KEPT — a failed or empty
    /// mid-day fetch must not wipe the morning briefing off the widget.
    /// (`.empty` on unpair still clears them like everything else.)
    mutating func stampBriefing(from items: [InboxItem]) {
        guard let briefing = InboxItem.latestBriefing(in: items) else { return }
        briefingTitle = briefing.title
        briefingFirstLine = LocalIntelligenceService.condensedLine(
            LocalIntelligenceService.firstMeaningfulLine(of: briefing.body) ?? "",
            limit: 90
        )
        briefingReceivedAt = briefing.timestamp
    }
}
```

- [ ] **Step 4: Verify lockstep + run tests**

```bash
diff Talaria/Models/HermesWidgetData.swift TalariaWidgets/Models/HermesWidgetData.swift && echo LOCKSTEP-OK
```
Expected: `LOCKSTEP-OK`. Then the Step 2 xcodebuild — expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Talaria/Models/HermesWidgetData.swift TalariaWidgets/Models/HermesWidgetData.swift Talaria/Models/InboxBriefing.swift TalariaTests/BriefingTests.swift
git commit -m "feat(#126): briefing fields on the widget snapshot + stamping mapper

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `InboxStore.markRead` + `AppContainer` stamp wiring

**Files:**
- Modify: `Talaria/Stores/InboxStore.swift` (after `func dismiss(_:)`, ~line 113)
- Modify: `Talaria/Stores/AppContainer.swift` — `updateWidgetData()` (~line 2112-2130): add one line before `SharedWidgetDataStore.write(data)`
- Test: `TalariaTests/BriefingTests.swift` (append suite)

**Interfaces:**
- Consumes: `InboxStore` internals (`localState.readItemIDs`, `items`, `stableIdentifier`), `HermesWidgetData.stampBriefing(from:)` (Task 2), the existing `makeStore` mock constellation (`MockSessionBootstrapService`, `MockSyncCoordinator`, `MockSecureStore`, `MockNotificationService` — app-target mocks, pattern from `TalariaTests/ConnectorOutageAlertTests.swift:147-161`).
- Produces: `InboxStore.markRead(_ item: InboxItem)` — used by Task 4's detail view.

- [ ] **Step 1: Write the failing tests (append to `TalariaTests/BriefingTests.swift`)**

```swift
@Suite("InboxStore markRead")
@MainActor
struct InboxStoreMarkReadTests {

    @MainActor
    private final class StubInboxService: InboxServiceProtocol {
        var stubbedItems: [InboxItem] = []
        func fetchInbox(accessToken: String?) async throws -> [InboxItem] { stubbedItems }
        func submitAction(itemID: UUID, actionID: String, accessToken: String?) async throws -> InboxActionResult {
            Issue.record("markRead must never round-trip the relay")
            throw URLError(.badServerResponse)
        }
    }

    @MainActor
    private final class MemoryPersistence: AppPersistenceStoreProtocol {
        var inboxState = InboxLocalState()
        func loadInboxState() -> InboxLocalState { inboxState }
        func saveInboxState(_ state: InboxLocalState) { inboxState = state }
        func clearInboxState() { inboxState = InboxLocalState() }
        // Unused protocol surface — inert.
        func loadUserSettings() -> UserSettings? { nil }
        func saveUserSettings(_ settings: UserSettings) {}
        func loadSessionState(profileScope: UUID?) -> AppSessionState? { nil }
        func saveSessionState(_ state: AppSessionState, profileScope: UUID?) {}
        func clearSessionState(profileScope: UUID?) {}
        func loadPairedRelayConfiguration(profileScope: UUID?) -> PairedRelayConfiguration? { nil }
        func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration, profileScope: UUID?) {}
        func clearPairedRelayConfiguration(profileScope: UUID?) {}
        func loadBackendProfilesState() -> BackendProfilesState? { nil }
        func saveBackendProfilesState(_ state: BackendProfilesState) {}
        func clearBackendProfilesState() {}
        func loadSessionProfileIndex() -> SessionProfileIndex { SessionProfileIndex() }
        func saveSessionProfileIndex(_ index: SessionProfileIndex) {}
        func clearSessionProfileIndex() {}
        func loadSessionUsageIndex() -> SessionUsageIndex { SessionUsageIndex() }
        func saveSessionUsageIndex(_ index: SessionUsageIndex) {}
        func clearSessionUsageIndex() {}
        func loadSensorOutboxState() -> SensorOutboxState { SensorOutboxState() }
        func saveSensorOutboxState(_ state: SensorOutboxState) {}
        func clearSensorOutboxState() {}
        func loadConversationCache() -> Conversation? { nil }
        func saveConversationCache(_ conversation: Conversation) {}
        func clearConversationCache() {}
        func loadConversationJournal() -> ConversationJournal? { nil }
        func saveConversationJournal(_ journal: ConversationJournal) {}
        func clearConversationJournal() {}
        func loadConversationListState() -> ConversationListState { ConversationListState() }
        func saveConversationListState(_ state: ConversationListState) {}
        func clearConversationListState() {}
        func loadComposeOutboxState() -> ComposeOutboxState { ComposeOutboxState() }
        func saveComposeOutboxState(_ state: ComposeOutboxState) {}
        func clearComposeOutboxState() {}
        func loadHealthQueryAnchorData(for identifier: String) -> Data? { nil }
        func saveHealthQueryAnchorData(_ data: Data?, for identifier: String) {}
        func clearHealthQueryAnchorData() {}
    }

    private func makeStore(
        service: StubInboxService = StubInboxService(),
        persistence: MemoryPersistence = MemoryPersistence()
    ) async -> InboxStore {
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development }
        )
        await sessionStore.bootstrap()
        return InboxStore(inboxService: service, persistence: persistence, sessionStore: sessionStore)
    }

    @Test("markRead flips the item read + non-actionable without a relay round-trip")
    func marksReadLocally() async {
        let service = StubInboxService()
        let briefing = InboxItem(
            type: .notification, title: "Briefing", body: "B",
            payload: ["category": "briefing"]
        )
        service.stubbedItems = [briefing]
        let store = await makeStore(service: service)
        await store.loadInbox(force: true)

        store.markRead(briefing)

        #expect(store.items.first?.isRead == true)
        #expect(store.items.first?.status == .opened)
        #expect(store.items.first?.isActionable == false)
        #expect(store.unreadCount == 0)
    }

    @Test("markRead persists — a reloaded store still shows the item read")
    func persistsAcrossReload() async {
        let service = StubInboxService()
        let persistence = MemoryPersistence()
        let briefing = InboxItem(
            type: .notification, title: "Briefing", body: "B",
            payload: ["category": "briefing"]
        )
        service.stubbedItems = [briefing]
        let store = await makeStore(service: service, persistence: persistence)
        await store.loadInbox(force: true)
        store.markRead(briefing)

        let reloaded = await makeStore(service: service, persistence: persistence)
        await reloaded.loadInbox(force: true)
        #expect(reloaded.items.first?.isRead == true)
    }

    @Test("markRead is idempotent")
    func idempotent() async {
        let service = StubInboxService()
        let briefing = InboxItem(type: .notification, title: "B", body: "B", payload: ["category": "briefing"])
        service.stubbedItems = [briefing]
        let store = await makeStore(service: service)
        await store.loadInbox(force: true)
        store.markRead(briefing)
        store.markRead(briefing)
        #expect(store.items.count == 1)
        #expect(store.items.first?.isRead == true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

`-only-testing:TalariaTests/InboxStoreMarkReadTests`. Expected: BUILD FAILED — `no member 'markRead'`.

- [ ] **Step 3: Implement `markRead` in `Talaria/Stores/InboxStore.swift`** (insert after `dismiss(_:)`)

```swift
    /// #126: opening a briefing detail marks it read — device-local
    /// bookkeeping only (same rules as `applyLocalState`), never a relay
    /// action round-trip.
    func markRead(_ item: InboxItem) {
        guard !localState.readItemIDs.contains(item.stableIdentifier) else { return }
        localState.readItemIDs.insert(item.stableIdentifier)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isRead = true
            if items[index].status == .pending { items[index].status = .opened }
            items[index].isActionable = items[index].status == .pending
        }
    }
```

- [ ] **Step 4: Wire the stamp into `AppContainer.updateWidgetData()`**

In `Talaria/Stores/AppContainer.swift` (~2112-2130), directly before `SharedWidgetDataStore.write(data)`:

```swift
        data.stampBriefing(from: inboxStore.items)   // #126: latest briefing for the widget
```

(The push-wake path already orders `inboxStore.loadInbox(force: true)` → `updateWidgetData()` at AppContainer.swift:1400-1410, so briefing delivery reaches the widget with no new call sites.)

- [ ] **Step 5: Run to verify pass**

Same command — expected `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Talaria/Stores/InboxStore.swift Talaria/Stores/AppContainer.swift TalariaTests/BriefingTests.swift
git commit -m "feat(#126): local markRead + widget stamp in the updateWidgetData funnel

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Briefing detail view + route + deep link + row wiring

**Files:**
- Create: `Talaria/Features/Inbox/BriefingDetailScreen.swift`
- Modify: `Talaria/Core/Router.swift:5-12` (`Route` enum — add case)
- Modify: `Talaria/ContentView.swift` (~199, the `Route` navigationDestination switch — add arm)
- Modify: `Talaria/AppEntry.swift` (`handleDeeplink`, ~322-360 — add `case "briefing"`)
- Modify: `Talaria/Features/Inbox/InboxScreen.swift:56-58` (replace the no-op `onOpenDetails`)

**Interfaces:**
- Consumes: `MarkdownContentView(content:isStreaming:)` (chart fences render + tap-through free), shared `SpeechOutputService` via `@Environment` (`speak(_:messageID:)`, `stop()`, `speakingMessageID`), `InboxStore.markRead` (Task 3), `InboxItem.isBriefing`/`.briefingSpeakableText`/`.latestBriefing(in:)` (Task 1), `TabRouter.navigate(to:)`.
- Produces: `Route.briefing(InboxItem?)` (`nil` = latest, for the widget deep link) and `BriefingDetailScreen(item: InboxItem?)` — Task 5's widget links to `hermes://briefing`.

- [ ] **Step 1: Add the route case** in `Talaria/Core/Router.swift`, inside `enum Route`:

```swift
    /// #126: briefing detail. `nil` = latest briefing (widget deep link);
    /// a value = the row the user tapped.
    case briefing(InboxItem?)
```

- [ ] **Step 2: Create `Talaria/Features/Inbox/BriefingDetailScreen.swift`**

```swift
import SwiftUI

// #126: full-screen render of a daily-briefing inbox item through the
// existing markdown pipeline — chart fences render + tap through free.
struct BriefingDetailScreen: View {
    @Environment(InboxStore.self) private var inboxStore
    @Environment(SpeechOutputService.self) private var speechOutput

    let item: InboxItem?

    private var briefing: InboxItem? {
        item ?? InboxItem.latestBriefing(in: inboxStore.items)
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if let briefing {
                content(for: briefing)
            } else if inboxStore.isLoading {
                ProgressView()
            } else {
                emptyState
            }
        }
        .navigationTitle("Briefing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let briefing {
                ToolbarItem(placement: .topBarTrailing) {
                    speakerToggle(for: briefing)
                }
            }
        }
        .task(id: briefing?.id) {
            // The deep link can land before any inbox fetch — resolve first,
            // then mark the rendered briefing read (local bookkeeping only).
            if item == nil, inboxStore.items.isEmpty {
                await inboxStore.loadInbox(force: true)
            }
            if let briefing {
                inboxStore.markRead(briefing)
            }
        }
    }

    private func content(for briefing: InboxItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                header(for: briefing)
                MarkdownContentView(content: briefing.body, isStreaming: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func header(for briefing: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Brand.accent, diameter: 7, blinks: false)
                MonoLabel(
                    "BRIEFING · \(briefing.timestamp.formatted(date: .abbreviated, time: .shortened).uppercased())",
                    size: 11,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.secondaryForeground
                )
            }
            Text(briefing.title)
                .font(Design.Typography.screenTitle2)
                .foregroundStyle(Design.Colors.foregroundBright)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Design.Spacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
        }
    }

    // Read-aloud through the SHARED chat instance — the audio-session house
    // law (#106) is enforced inside the service; this view only ever calls
    // speak/stop. Same toggle pattern as MessageBubble's speaker.
    private func speakerToggle(for briefing: InboxItem) -> some View {
        let isSpeakingThis = speechOutput.speakingMessageID == briefing.id
        return Button {
            if isSpeakingThis {
                speechOutput.stop()
            } else {
                speechOutput.speak(briefing.briefingSpeakableText, messageID: briefing.id)
            }
        } label: {
            Image(systemName: isSpeakingThis ? "speaker.slash.fill" : "speaker.wave.2")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeakingThis ? "Stop reading aloud" : "Read briefing aloud")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Briefing Yet")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "sunrise")
                    .foregroundStyle(Design.Brand.accent)
            }
        } description: {
            MonoLabel(
                "THE NEXT DAILY BRIEFING WILL APPEAR HERE",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }
}
```

- [ ] **Step 3: Add the navigationDestination arm** in `Talaria/ContentView.swift`, in the `Route` switch that currently ends with `case .inbox: InboxScreen()`:

```swift
        case .briefing(let item):
            BriefingDetailScreen(item: item)
```

- [ ] **Step 4: Add the deep-link route** in `Talaria/AppEntry.swift` `handleDeeplink`, mirroring the `case "health"` arm exactly (clear sheet → popToRoot → select chat tab), then:

```swift
        case "briefing":
            // #126: widget tap → the latest briefing's detail.
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
            container.router.navigate(to: .briefing(nil))
```
(Match the surrounding arms' exact property/call spellings when editing — copy the `health` arm and change the route.)

- [ ] **Step 5: Wire the row tap** in `Talaria/Features/Inbox/InboxScreen.swift` — replace the no-op:

```swift
                            onOpenDetails: {
                                // #126: briefings get the rich detail; other
                                // kinds keep the pre-existing no-op.
                                if item.isBriefing {
                                    router.navigate(to: .briefing(item))
                                }
                            }
```

- [ ] **Step 6: Regen + compile check + focused suites still green**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodegen generate
grep -E "aps-environment|weatherkit" Talaria/Talaria.entitlements
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` (the exhaustive `Route` switch forces the new arm — a miss is a compile error, which is the test).

- [ ] **Step 7: Commit**

```bash
git add Talaria/Features/Inbox/BriefingDetailScreen.swift Talaria/Core/Router.swift Talaria/ContentView.swift Talaria/AppEntry.swift Talaria/Features/Inbox/InboxScreen.swift Talaria.xcodeproj
git commit -m "feat(#126): briefing detail screen, hermes://briefing route, inbox row tap

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Latest-briefing widget

**Files:**
- Create: `TalariaWidgets/HermesBriefingWidget.swift`
- Modify: `TalariaWidgets/HermesWidgetBundle.swift` (register)
- Modify: `TalariaWidgets/HermesTimelineProvider.swift` (`.placeholder` — add briefing sample values)

**Interfaces:**
- Consumes: `HermesTimelineProvider()` (default init, no HealthKit), `HermesWidgetEntry.palette(for:)`, `WidgetEntryThemeBackground(entry:)`, `HermesWidgetConfigurationIntent`, snapshot fields from Task 2, `hermes://briefing` from Task 4.
- Produces: `HermesBriefingWidget` (kind `"HermesBriefing"`, `.systemSmall` + `.systemMedium`).

- [ ] **Step 1: Create `TalariaWidgets/HermesBriefingWidget.swift`**

```swift
import SwiftUI
import WidgetKit

// #126: latest-briefing widget — pre-derived title + first line from the
// app-group snapshot, deep-linking into the in-app briefing detail.
struct HermesBriefingWidget: Widget {
    let kind = "HermesBriefing"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HermesWidgetConfigurationIntent.self,
            provider: HermesTimelineProvider()
        ) { entry in
            HermesBriefingView(entry: entry)
                .containerBackground(for: .widget) { WidgetEntryThemeBackground(entry: entry) }
        }
        .configurationDisplayName("Daily Briefing")
        .description("The latest briefing from Hermes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HermesBriefingView: View {
    let entry: HermesWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = entry.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sunrise.fill")
                    .font(.caption)
                    .foregroundStyle(palette.forge)
                Text("BRIEFING")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.mutedForeground)
                Spacer()
                if let receivedAt = entry.data.briefingReceivedAt {
                    Text(receivedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(palette.mutedForeground)
                }
            }

            if let title = entry.data.briefingTitle {
                Text(title)
                    .font(family == .systemSmall ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(2)

                if let firstLine = entry.data.briefingFirstLine, !firstLine.isEmpty {
                    Text(firstLine)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryForeground)
                        .lineLimit(family == .systemSmall ? 2 : 3)
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                // Real data only: no briefing has ever arrived — say so.
                Text("No briefing yet")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryForeground)
                Spacer()
            }
        }
        .widgetURL(URL(string: "hermes://briefing"))
    }
}
```

- [ ] **Step 2: Register** in `TalariaWidgets/HermesWidgetBundle.swift` — add `HermesBriefingWidget()` after `HermesHealthWidget()`.

- [ ] **Step 3: Gallery placeholder** — in `TalariaWidgets/HermesTimelineProvider.swift`, extend `HermesWidgetEntry.placeholder`'s `HermesWidgetData(...)` init with (after `updatedAt: .now`):

```swift
            updatedAt: .now,
            briefingTitle: "Morning briefing — Sun Jul 20",
            briefingFirstLine: "Sleep 7h 24m · 3 events today · clear until 3pm",
            briefingReceivedAt: .now
```

- [ ] **Step 4: Regen + compile check**

Same regen + build commands as Task 4 Step 6. Expected: `** BUILD SUCCEEDED **` (app scheme builds the widget extension via the target dependency).

- [ ] **Step 5: Commit**

```bash
git add TalariaWidgets/HermesBriefingWidget.swift TalariaWidgets/HermesWidgetBundle.swift TalariaWidgets/HermesTimelineProvider.swift Talaria.xcodeproj
git commit -m "feat(#126): Daily Briefing widget (small/medium) with hermes://briefing deep link

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Connector `send_inbox_item` payload passthrough

**Files:**
- Modify: `connector/src/hermes_mobile_connector/mcp_server.py` (`send_inbox_item`, ~313-402)
- Test: `connector/tests/test_inbox_producer.py`

**Interfaces:**
- Consumes: existing `FakeHTTPClient`/`FakeResponse`/`connector_home`/`fake_http` fixtures in the test file; relay `InternalInboxCreateRequest` already accepts `payload: dict[str,str] | None` (`relay/app/schemas.py:286-294`).
- Produces: `send_inbox_item(..., payload: dict[str, str] | None = None)` forwarding `payload` in the create body — the delivery half of the #126 contract.

- [ ] **Step 1: Write the failing tests (append to `connector/tests/test_inbox_producer.py`)**

```python
def test_send_inbox_item_rejects_non_string_payload_values():
    result = json.loads(mcp_server.send_inbox_item("t", "b", payload={"count": 3}))
    assert "payload" in result["error"].lower()


def test_send_inbox_item_forwards_payload_when_given(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-9", "status": "pending"}}}),
        FakeResponse(payload={"data": {"sent": 1}}),
    ]

    result = json.loads(
        mcp_server.send_inbox_item(
            "Morning briefing — Thu Jul 17",
            "## Sleep\nYou slept 7h 24m.",
            payload={"category": "briefing", "speakable": "Good morning."},
        )
    )

    assert result["itemId"] == "item-9"
    create = fake_http.requests[0]
    assert create[3] == {
        "kind": "notification",
        "title": "Morning briefing — Thu Jul 17",
        "body": "## Sleep\nYou slept 7h 24m.",
        "priority": "normal",
        "payload": {"category": "briefing", "speakable": "Good morning."},
    }


def test_send_inbox_item_empty_payload_stays_omitted(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-2", "status": "pending"}}}),
        FakeResponse(payload={"data": {"sent": 1}}),
    ]
    mcp_server.send_inbox_item("t", "b", payload={})
    assert "payload" not in fake_http.requests[0][3]
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27/connector && python3 -m pytest tests/test_inbox_producer.py -q 2>&1 | tail -5
```
(If `python3 -m pytest` can't import the package, use the project venv — check for `connector/.venv/bin/python` and run `.venv/bin/python -m pytest`; #115 established the macOS venv.) Expected: 3 failures — `unexpected keyword argument 'payload'`.

- [ ] **Step 3: Implement** in `mcp_server.py`:

Signature — add the parameter after `notify`:

```python
def send_inbox_item(
    title: str,
    body: str,
    kind: str = "notification",
    priority: str = "normal",
    notify: str = "silent",
    payload: dict[str, str] | None = None,
) -> str:
```

Docstring — append to the Args block:

```
        payload: Optional flat string→string metadata map delivered verbatim
            to the app. The #126 daily-briefing contract rides here:
            {"category": "briefing", "speakable": "<short spoken version>"}.
```

Validation — after the `notify` check, before the internal-key lookup:

```python
    if payload is not None and not all(
        isinstance(k, str) and isinstance(v, str) for k, v in payload.items()
    ):
        return json.dumps({"error": "payload must be a flat string→string map"})
```

Create body — replace the hardcoded `json={...}` in the create POST:

```python
            create_body: dict[str, object] = {
                "kind": kind,
                "title": title,
                "body": body,
                "priority": priority,
            }
            if payload:
                create_body["payload"] = payload
            response = client.post(
                f"{root}/internal/inbox/create",
                headers=headers,
                json=create_body,
            )
```

- [ ] **Step 4: Run the FULL connector suite to verify pass + no regression**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27/connector && python3 -m pytest -q 2>&1 | tail -3
```
Expected: ≥ 107 passed, 1 skipped (104+3 new), 0 failed. (The pre-existing `test_send_inbox_item_posts_create_then_silent_push` pins the body WITHOUT payload — it must still pass, since payload is only added when truthy.)

- [ ] **Step 5: Commit**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
git add connector/src/hermes_mobile_connector/mcp_server.py connector/tests/test_inbox_producer.py
git commit -m "feat(#126): send_inbox_item forwards payload (briefing contract delivery)

The relay DTO/DB/serializer and the app decoder already carry payload
end-to-end; the tool's create body was the one gap. Additive + optional —
existing callers unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Final regen + entitlements check**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodegen generate
grep -E "aps-environment|weatherkit" Talaria/Talaria.entitlements    # BOTH must appear
git status --short    # project file changes only, commit if dirty
```

- [ ] **Step 2: Full app suite, backgrounded**

```bash
nohup env DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' test > /tmp/t27-126-suite.log 2>&1 &
```
Poll `tail -5 /tmp/t27-126-suite.log` until `** TEST SUCCEEDED **`. Then count:
```bash
grep -E "Executed [0-9]+ tests" /tmp/t27-126-suite.log | tail -3
```
Expected: total ≥ 913 tests (baseline) + ~14 new, 0 failures. If ANY pre-existing test fails, STOP and diagnose before proceeding — do not rationalize it as unrelated.

- [ ] **Step 3: Commit any regen residue**

```bash
git add -A && git diff --cached --quiet || git commit -m "chore(#126): xcodegen regen

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: OPEN_ITEMS note + PR

**Files:**
- Modify: `OPEN_ITEMS.md` (#126 entry — add a BUILT update note)

- [ ] **Step 1: Add the update note** under `## 126.` (above the dispatch-spec line), following the house format:

```markdown
> **BUILT in lane 2026-07-20 (`claude/t27-126-daily-briefing`, PR #<n>).** App half complete:
> recognition (`payload.category == "briefing"`, kind-tolerant), `BriefingDetailScreen` through
> the EXISTING MarkdownContentView (chart fences render + tap through free), read-aloud via the
> SHARED SpeechOutputService (speakable ?? fence-stripped body; #106 gate untouched), Daily
> Briefing widget (small/medium, `hermes://briefing` deep link, honest empty state), snapshot
> fields on BOTH HermesWidgetData copies, `InboxStore.markRead` (local, no relay round-trip).
> Suites: app <X>/<Y> green, connector <Z> passed + 1 skip. DISPATCH CORRECTION: the connector's
> `send_inbox_item` did NOT forward `payload` (relay DTO/DB/serializer + app decoder all did) —
> minimal additive passthrough shipped in its own commit, flagged for Owen in the PR.
> **Device pass owed:** hand-crafted payload through `send_inbox_item` → push → inbox row →
> detail renders markdown + inline chart → read-aloud speaks → widget shows it → widget tap
> deep-links back to detail. THEN wire the real cron with the PR's JSON example.
```

(Fill `<X>/<Y>/<Z>` with the real Task 7/6 counts.)

- [ ] **Step 2: Commit + push + PR**

```bash
git add OPEN_ITEMS.md
git commit -m "docs: OPEN_ITEMS #126 BUILT in lane — briefing app half, device pass owed

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin claude/t27-126-daily-briefing
gh pr create --repo AethyrionAI/Talaria-27 --base main --title "feat(#126): Daily briefing — app half" --body-file /private/tmp/claude-501/-Users-owenjones-Documents-Claude-Talaria-27/6d7c1e70-1f80-4a5a-8c11-a4f27bac8bf5/scratchpad/pr-126-body.md
```

The PR body (write to the scratchpad path above first) MUST contain:

1. **The copy-pasteable JSON contract example** for Owen's cron prompt:

````markdown
## Payload contract (for the host cron prompt)

The agent calls the `send_inbox_item` MCP tool:

```json
{
  "title": "Morning briefing — Thu Jul 17",
  "body": "## Sleep\nYou slept **7h 24m** — solid.\n\n```chart\n{\"type\":\"bar\",\"title\":\"Sleep, 7 nights\",\"x\":{\"label\":\"Night\",\"values\":[\"Fri\",\"Sat\",\"Sun\",\"Mon\",\"Tue\",\"Wed\",\"Thu\"]},\"series\":[{\"name\":\"hours\",\"values\":[6.9,7.8,7.1,6.5,7.4,8.0,7.4]}]}\n```\n\n## Today\n- 10:00 Standup\n- 14:00 Dentist\n\n## Open threads\n- Reply to Sam re: the relay PR",
  "kind": "notification",
  "priority": "normal",
  "notify": "alert",
  "payload": {
    "category": "briefing",
    "speakable": "Good morning. You slept seven hours twenty-four minutes. Two calendar items today: standup at ten, dentist at two. One open thread: reply to Sam."
  }
}
```

Every payload field beyond `category` is optional — the app renders what
exists. `speakable` missing → read-aloud falls back to the body with fenced
blocks stripped.
````

2. **Questions for Owen** (defaults stand unless answered):
   - **Connector passthrough (dispatch correction):** the dispatch said "no connector changes (the path exists)" — the path did NOT exist for `payload`: `send_inbox_item` dropped it (relay + app were ready). Shipped the minimal additive passthrough in its own commit (`feat(#126): send_inbox_item forwards payload`). Approve, or revert that commit and have the cron POST `/internal/inbox/create` directly with the internal key (raw-curl example included below the tool example).
   - **Notification tap → detail (dispatch default NOT implementable cleanly):** inbox alert pushes carry no identifying userInfo (`/v1/push/send` forwards only title/body; the APNs client underneath already supports `category`/`payload_extra`). Tap routing left UNCHANGED (→ chat); the detail is reachable via inbox row + widget. If tap→detail is wanted, it's a small relay+connector follow-up: expose `category`/`data` on `/v1/push/send`, send `category: "talaria.briefing"`, and branch in `userNotificationCenter(_:didReceive:)`.
   - **Widget persistence semantics:** the widget keeps the last-stamped briefing when a later fetch no longer lists one (mid-day empty fetch must not wipe the morning briefing). Unpair still clears. OK?
   - **Recommend `notify: "alert"`** for the cron so the briefing is visible; `"silent"` also works (item + widget still update on wake).
3. **Device check list** (from the dispatch): hand-crafted payload → push arrives → inbox row shows it → detail renders markdown + inline chart → read-aloud speaks (speakable, then fence-stripped fallback) → widget shows title + first line → widget tap deep-links to detail. THEN wire the real cron.
4. Test evidence: suite counts before/after, connector counts.
5. Footer: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`

---

## Self-review notes (already applied)

- Spec coverage: contract fields (title/body/speakable/category) ✓ Tasks 1-2; detail view via existing renderer ✓ Task 4; read-aloud via existing service, session law untouched ✓ Task 4; widget via existing store ✓ Tasks 2/5; recognition predicate ✓ Task 1; tolerant decode ✓ (payload already `[String:String]?` on the wire DTO — absent fields are nil, tests pin it); tests matrix ✓ Tasks 1/2/3/6; regen on file add ✓ Tasks 1/4/5/7; suite floor ✓ Task 7; JSON example in PR ✓ Task 8; embedded decisions surfaced ✓ Task 8.
- Constraint deviations, both deliberate and flagged for Owen (Task 8): the connector payload passthrough (dispatch premise wrong), and notification-tap→detail deferred (needs relay userInfo support the dispatch forbids adding).
- Type consistency: `Route.briefing(InboxItem?)` used in Router/ContentView/AppEntry/InboxScreen identically; `stampBriefing(from:)` defined app-side only (widget copy stays lockstep-identical); `markRead(_:)` name consistent across Task 3 and Task 4.
