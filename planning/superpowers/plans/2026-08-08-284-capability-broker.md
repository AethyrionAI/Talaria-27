# #284 CapabilityBroker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One registry describing every device-belt tool, an honest registry-generated
capability self-description (#257 fix), and a probe-gated Bool-vector router extension
that — only if it clears pre-registered bars — arms armed turns with just the capability
groups the turn needs.

**Architecture:** Three stages from the approved spec
(`planning/superpowers/specs/2026-08-08-284-capability-broker-design.md`). Stage 1
(registry + armed-blurb generation + budget contrast) ships unconditionally. Stage 2 is a
measured DEBUG probe with bars pre-registered in OPEN_ITEMS #284 **before** the device
run; Owen routes the verdict. Stage 3 (selective arming) executes **only on a cleared
verdict** — its tasks are in this plan so the promotion shape is fixed now, but a failed
probe ends the lane after Task 10 with a close-out instead.

**Tech Stack:** Swift 6 / SwiftUI, FoundationModels (iOS 27 beta 4), swift-testing
(`@Test` / `#expect`), xcodegen, Xcode-beta4 toolchain.

## Global Constraints

- **Toolchain:** every build/test shell needs
  `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`.
- **`xcodegen generate` is mandatory after adding any Swift file** (explicit source
  listings). Run it in the task that creates the file, before building.
- **Test runs:** `-only-testing` is SUITE-level only — a method selector silently runs 0
  tests under `** TEST SUCCEEDED **`. Always read the executed-test count and confirm it
  moved. Pinned sim UDID: `47F68496-24F9-45D9-93D3-1C778DB6B557`.
- **Branch:** all work on `t27-284-capability-broker` (create via the using-git-worktrees
  skill at execution start). Never commit to `main`; Owen pushes and merges. Commit
  trailers (`Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`) go on at commit
  time — they cannot be retrofitted.
- **Promoted code lives outside `#if DEBUG`** (#218). Stage 3's promotion commit must be
  verified with a **Release build**; the lane gate (`scripts/mac/lane-gate.sh`) runs
  before any PR.
- **`tokenCount()` must never run concurrently with a live streaming turn** — it kills
  the turn on device (ModelManagerError 1001). All measurement rides the existing
  post-turn flush.
- **Measured text is never edited silently.** The armed enumeration change (Task 3) is
  the spec-approved exception, done once, with its pin tests updated in the same commit.
  The toolless payload changes only via Task 12's measured arm.
- Standard test command (Debug suite, one suite):

  ```bash
  DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' -only-testing:TalariaTests/CapabilityRegistryTests test 2>&1 | tail -30
  ```

---

## Stage 1 — CapabilityRegistry + #257 armed fix (ships unconditionally)

### Task 1: Registry types and mechanics

**Files:**
- Create: `Talaria/Services/Live/DeviceTools/CapabilityRegistry.swift`
- Test: `TalariaTests/CapabilityRegistryTests.swift` (new file)

**Interfaces:**
- Produces: `CapabilityGroup` (enum, 11 cases), `CapabilitySource`, `CapabilityRiskClass`,
  `CapabilityDescriptor` (struct), `CapabilityDescribing` (protocol),
  `CapabilityRegistry` with `init(belt:)`, `descriptors: [CapabilityDescriptor]`,
  `static func toolNames(for groups: Set<CapabilityGroup>, in catalog: [CapabilityDescriptor]) -> Set<String>`,
  and `static func armedCapabilityEnumeration(families: [CapabilityGroup]) -> String`.
  Task 2 conforms the tools; Tasks 3/9/11 consume the enumeration and mapping.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Talaria

struct CapabilityRegistryTests {

    // Doubles: two minimal descriptor-carrying types, no FoundationModels needed.
    private struct StubDescribedA: CapabilityDescribing {
        static let capabilityDescriptor = CapabilityDescriptor(
            id: "stubA", semanticDescription: "stub A", source: .device,
            group: .calendar, riskClass: .read, permissions: ["Calendars"],
            argumentSummary: "none")
    }
    private struct StubDescribedB: CapabilityDescribing {
        static let capabilityDescriptor = CapabilityDescriptor(
            id: "stubB", semanticDescription: "stub B", source: .device,
            group: .health, riskClass: .write, permissions: [],
            argumentSummary: "none")
    }

    @Test func groupToolNameMappingFiltersTheCatalog() {
        let catalog = [StubDescribedA.capabilityDescriptor, StubDescribedB.capabilityDescriptor]
        #expect(CapabilityRegistry.toolNames(for: [.calendar], in: catalog) == ["stubA"])
        #expect(CapabilityRegistry.toolNames(for: [.calendar, .health], in: catalog) == ["stubA", "stubB"])
        #expect(CapabilityRegistry.toolNames(for: [], in: catalog).isEmpty)
    }

    @Test func enumerationIsDeterministicAndOxfordJoined() {
        // Order follows the CaseIterable declaration order, not the input order.
        let sentence = CapabilityRegistry.armedCapabilityEnumeration(
            families: [.reminders, .health, .calendar])
        #expect(sentence == "their health and activity, calendar, and reminders")
        #expect(CapabilityRegistry.armedCapabilityEnumeration(families: [.weather]) == "the weather")
    }

    @Test func everyGroupHasADisplayPhrase() {
        for group in CapabilityGroup.allCases {
            #expect(!group.displayPhrase.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run the standard test command (Global Constraints). Expected: build FAILS —
`CapabilityRegistry` undefined. (A new test file also needs `xcodegen generate` first —
run it now.)

- [ ] **Step 3: Implement `CapabilityRegistry.swift`**

```swift
import Foundation

/// #284: capability metadata for every tool the local brain can be armed
/// with. ONE registry — native device tools now; `.hermes`/`.mcp`/`.skill`
/// are cases only, the shape #150/#163 land into later. Descriptors are
/// declared BY the tool types (`CapabilityDescribing`) and the registry is
/// built FROM live belt instances, so it structurally cannot describe a
/// tool the belt doesn't carry. Bidirectional drift pins live in
/// `CapabilityRegistryTests` (the #200 `actionToolNames` pattern).
enum CapabilityGroup: String, CaseIterable, Sendable {
    case health          // readHealth, readMotion
    case location        // currentLocation
    case weather         // currentWeather
    case places          // searchPlaces
    case calendar        // readCalendar, createCalendarEvent
    case reminders       // readReminders, createReminder
    case alarms          // scheduleAlarm
    case contacts        // lookupContact
    case conversations   // searchConversations
    case deviceStatus    // deviceStatus
    /// Image tools. NEVER in the router vector — armed by the #176 image
    /// gate, union'd over any narrowing (spec §6 rule V).
    case vision          // readImageText, readBarcode

    /// The phrase the armed instructions enumeration uses for this family.
    var displayPhrase: String {
        switch self {
        case .health: return "their health and activity"
        case .location: return "their location"
        case .weather: return "the weather"
        case .places: return "nearby places"
        case .calendar: return "calendar"
        case .reminders: return "reminders"
        case .alarms: return "alarms"
        case .contacts: return "contacts"
        case .conversations: return "past conversations"
        case .deviceStatus: return "device status"
        case .vision: return "text and barcodes in the attached image"
        }
    }
}

enum CapabilitySource: String, Sendable {
    case device
    // Unpopulated this lane — the #150/#163 landing shape (spec §3.2).
    case hermes, mcp, skill
}

enum CapabilityRiskClass: String, Sendable {
    case read
    /// Write == confirmation-gated: every action tool shows the card first.
    case write
}

struct CapabilityDescriptor: Sendable {
    let id: String                    // == Tool.name
    let semanticDescription: String
    let source: CapabilitySource
    let group: CapabilityGroup
    let riskClass: CapabilityRiskClass
    let permissions: [String]         // user-facing framework names; [] = none
    let argumentSummary: String
}

/// A tool type that carries its own capability descriptor. Static, so the
/// nonisolated instructions builder can read catalog data without touching
/// MainActor tool instances.
protocol CapabilityDescribing {
    static var capabilityDescriptor: CapabilityDescriptor { get }
}

struct CapabilityRegistry {
    let descriptors: [CapabilityDescriptor]

    /// Built from live belt instances — a tool whose type does not conform
    /// is simply absent, and the pin test fails on the count mismatch.
    init(belt: [Any]) {
        descriptors = belt.compactMap {
            (type(of: $0) as? any CapabilityDescribing.Type)?.capabilityDescriptor
        }
    }

    nonisolated static func toolNames(
        for groups: Set<CapabilityGroup>, in catalog: [CapabilityDescriptor]
    ) -> Set<String> {
        Set(catalog.filter { groups.contains($0.group) }.map(\.id))
    }

    /// The armed blurb's enumeration, generated so it can never go stale
    /// (#257's root cause was a hand-written copy of this list). Order is
    /// the `CapabilityGroup` declaration order — deterministic, pinned.
    nonisolated static func armedCapabilityEnumeration(families: [CapabilityGroup]) -> String {
        let ordered = CapabilityGroup.allCases.filter { families.contains($0) }
        let phrases = ordered.map(\.displayPhrase)
        switch phrases.count {
        case 0: return ""
        case 1: return phrases[0]
        case 2: return "\(phrases[0]) and \(phrases[1])"
        default:
            return phrases.dropLast().joined(separator: ", ") + ", and " + phrases.last!
        }
    }
}
```

Note `init(belt: [Any])` — `[any Tool]` would import FoundationModels here; `[Any]`
keeps this file framework-free and unit-testable. The belt call site passes its
`[any Tool]` directly (it bridges to `[Any]`).

- [ ] **Step 4: Run tests to verify pass**

Standard test command. Expected: PASS, executed count = 3 (confirm it moved from the
previous run).

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/DeviceTools/CapabilityRegistry.swift TalariaTests/CapabilityRegistryTests.swift Talaria.xcodeproj/project.pbxproj
git commit -m "feat(#284): CapabilityRegistry types — groups, descriptors, enumeration generator

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Descriptor conformances for all 15 belt tools + bidirectional pins

**Files:**
- Modify: `Talaria/Services/Live/DeviceTools/DeviceHealthTool.swift` (readHealth)
- Modify: `Talaria/Services/Live/DeviceTools/DeviceReadTools.swift` (deviceStatus,
  currentLocation, readMotion, currentWeather, searchPlaces, lookupContact)
- Modify: `Talaria/Services/Live/DeviceTools/DeviceCalendarTools.swift` (readCalendar,
  readReminders)
- Modify: `Talaria/Services/Live/DeviceTools/DeviceActionTools.swift` (createReminder,
  createCalendarEvent, scheduleAlarm)
- Modify: `Talaria/Services/Live/DeviceTools/DeviceMediaTools.swift` (readImageText,
  readBarcode, searchConversations)
- Test: `TalariaTests/CapabilityRegistryTests.swift` (extend)

**Interfaces:**
- Consumes: `CapabilityDescribing`, `CapabilityDescriptor` (Task 1).
- Produces: every production belt tool type conforms; `TalariaTests` gains the
  belt↔registry pin. Task 3+ can rely on: **the full device catalog = the descriptors of
  a freshly built read+action belt, and every descriptor's `id` equals its tool's
  runtime `name`.**

- [ ] **Step 1: Write the failing pin tests** (extend `CapabilityRegistryTests.swift`)

```swift
    // MARK: - Belt pins (#200 actionToolNames pattern, bidirectional)

    @MainActor private static func fullBelt() -> [any Tool] {
        let relay = ToolEventRelay()
        var belt = DeviceToolBelt.makeReadTools(
            relay: relay,
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false })
        belt += DeviceToolBelt.makeActionTools(
            relay: relay,
            confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService())
        return belt
    }

    @Test @MainActor func everyBeltToolHasADescriptorWhoseIdIsItsName() {
        let belt = Self.fullBelt()
        let registry = CapabilityRegistry(belt: belt)
        #expect(registry.descriptors.count == belt.count)  // no undescribed tool
        for tool in belt {
            let descriptor = registry.descriptors.first { $0.id == tool.name }
            #expect(descriptor != nil, "no descriptor for \(tool.name)")
        }
    }

    @Test @MainActor func everyGroupMapsToAtLeastOneToolAndEveryToolToExactlyOneGroup() {
        let registry = CapabilityRegistry(belt: Self.fullBelt())
        let groups = Set(registry.descriptors.map(\.group))
        #expect(groups == Set(CapabilityGroup.allCases))   // no orphan group
        // "exactly one group" is structural (group is a single field), but
        // duplicate descriptors would double-count — pin id uniqueness.
        #expect(Set(registry.descriptors.map(\.id)).count == registry.descriptors.count)
    }

    @Test @MainActor func actionToolsAreWriteClassAndReadToolsAreReadClass() {
        let registry = CapabilityRegistry(belt: Self.fullBelt())
        for d in registry.descriptors {
            let isAction = DeviceToolBelt.actionToolNames.contains(d.id)
            #expect((d.riskClass == .write) == isAction, "\(d.id) risk class wrong")
        }
    }

    @Test @MainActor func visionGroupIsExactlyTheImageDependentTools() {
        let belt = Self.fullBelt()
        let registry = CapabilityRegistry(belt: belt)
        let visionIds = Set(registry.descriptors.filter { $0.group == .vision }.map(\.id))
        let imageDependent = Set(belt.filter { $0 is any ImageDependentTool }.map(\.name))
        #expect(visionIds == imageDependent)  // rule V's precondition (spec §6)
    }
```

If `ToolConfirmationCenter()` or `AlarmService()` need arguments, copy the construction
used at `TalariaTests/DeviceToolBeltTests.swift:2262`'s
`actionToolNamesMatchTheActionBelt` — that test builds the action belt already; reuse
its exact helper shape.

- [ ] **Step 2: Run to verify failure**

Standard test command. Expected: `everyBeltToolHasADescriptorWhoseIdIsItsName` FAILS
(0 descriptors ≠ 15 tools).

- [ ] **Step 3: Add one conformance per tool type**

(three semanticDescription values corrected 2026-08-08 during execution — review
caught the plan's strings misdescribing the tools; tools govern)

Extension goes next to each tool. The 15 descriptors, verbatim (id must equal the
tool's `let name` exactly; before writing each `permissions` value, open that tool's
own permission-failure strings in the same file and match the framework it actually
names):

```swift
// DeviceHealthTool.swift
extension DeviceHealthTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "readHealth",
        semanticDescription: "Reads the user's HealthKit data: steps, sleep, workouts, heart rate.",
        source: .device, group: .health, riskClass: .read,
        permissions: ["Health"], argumentSummary: "metric + optional day range")
}

// DeviceReadTools.swift
extension DeviceStatusTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "deviceStatus",
        semanticDescription: "Reads battery level, charging state, storage, thermal state, and Low Power Mode.",
        source: .device, group: .deviceStatus, riskClass: .read,
        permissions: [], argumentSummary: "none")
}
extension LocationTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "currentLocation",
        semanticDescription: "Reads the user's current location as a place name (no raw coordinates).",
        source: .device, group: .location, riskClass: .read,
        permissions: ["Location"], argumentSummary: "none")
}
extension MotionTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "readMotion",
        semanticDescription: "Reads current motion activity: walking, running, stationary, step cadence.",
        source: .device, group: .health, riskClass: .read,
        permissions: ["Motion & Fitness"], argumentSummary: "none")
}
extension WeatherTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "currentWeather",
        semanticDescription: "Reads current conditions and forecast for the user's location.",
        source: .device, group: .weather, riskClass: .read,
        permissions: ["Location"], argumentSummary: "optional day offset")
}
extension PlacesTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "searchPlaces",
        semanticDescription: "Searches for nearby places and points of interest around the user.",
        source: .device, group: .places, riskClass: .read,
        permissions: ["Location"], argumentSummary: "search term")
}
extension ContactsTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "lookupContact",
        semanticDescription: "Looks up a person in the user's contacts: phone numbers and email addresses.",
        source: .device, group: .contacts, riskClass: .read,
        permissions: ["Contacts"], argumentSummary: "name")
}

// DeviceCalendarTools.swift
extension CalendarReadTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "readCalendar",
        semanticDescription: "Reads the user's calendar events for a day or range.",
        source: .device, group: .calendar, riskClass: .read,
        permissions: ["Calendars"], argumentSummary: "day or range")
}
extension ReminderReadTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "readReminders",
        semanticDescription: "Reads the user's reminders and their due dates.",
        source: .device, group: .reminders, riskClass: .read,
        permissions: ["Reminders"], argumentSummary: "optional list filter")
}

// DeviceActionTools.swift
extension ReminderCreateTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "createReminder",
        semanticDescription: "Creates a reminder, behind the user's confirmation card.",
        source: .device, group: .reminders, riskClass: .write,
        permissions: ["Reminders"], argumentSummary: "title + due date")
}
extension CalendarEventTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "createCalendarEvent",
        semanticDescription: "Creates a calendar event, behind the user's confirmation card.",
        source: .device, group: .calendar, riskClass: .write,
        permissions: ["Calendars"], argumentSummary: "title + start/end")
}
extension AlarmTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "scheduleAlarm",
        semanticDescription: "Schedules an alarm, behind the user's confirmation card.",
        source: .device, group: .alarms, riskClass: .write,
        permissions: ["Alarms"], argumentSummary: "time + optional label")
}

// DeviceMediaTools.swift
extension ImageTextTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "readImageText",
        semanticDescription: "Reads printed or handwritten text out of the image attached to the conversation.",
        source: .device, group: .vision, riskClass: .read,
        permissions: [], argumentSummary: "none — uses the attached image")
}
extension BarcodeReaderTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "readBarcode",
        semanticDescription: "Reads barcodes and QR codes in the image attached to the conversation.",
        source: .device, group: .vision, riskClass: .read,
        permissions: [], argumentSummary: "none — uses the attached image")
}
extension ConversationSearchTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "searchConversations",
        semanticDescription: "Searches the user's past Talaria conversations.",
        source: .device, group: .conversations, riskClass: .read,
        permissions: [], argumentSummary: "search term")
}
```

If any extension fails to compile because the tool type's actual name differs
(e.g. `DeviceStatusTool` vs another spelling), the authoritative list of type names is
`DeviceToolBelt.makeReadTools`/`makeActionTools` (`DeviceToolBelt.swift:33-67`) — match
those, never rename a tool.

- [ ] **Step 4: Run tests to verify pass**

Standard test command. Expected: PASS, executed count = 7.

- [ ] **Step 5: Commit**

```bash
git add -A Talaria/Services/Live/DeviceTools/ TalariaTests/CapabilityRegistryTests.swift
git commit -m "feat(#284): all 15 belt tools declare capability descriptors; bidirectional belt pins

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Registry-generated armed enumeration (#257 armed surface)

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend.swift:1699` (`instructionsText`
  signature) and `:1847` (the armed blurb sentence)
- Modify: `TalariaTests/DeviceToolBeltTests.swift:117` and `:193` (the two pins on the
  old sentence)
- Test: `TalariaTests/CapabilityRegistryTests.swift` (extend)

**Interfaces:**
- Consumes: `CapabilityRegistry.armedCapabilityEnumeration(families:)`,
  `CapabilityGroup` (Task 1).
- Produces: `instructionsText` gains
  `armedCapabilityFamilies: [CapabilityGroup] = CapabilityGroup.allCases.filter { $0 != .vision }`
  — callers that pass nothing get the full non-vision catalog (today's behavior,
  enumeration now complete and staleness-proof). `hasImageTools: true` appends the
  vision phrase. Stage 3 (Task 11) passes the armed subset.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func armedEnumerationCoversEveryNonVisionFamilyByDefault() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone.", hasTools: true)
        // The #257 fix: families the hand-written sentence missed.
        #expect(armed.contains("device status"))
        #expect(armed.contains("their health and activity"))
        // The frame sentence survives verbatim around the generated list.
        #expect(armed.contains("Use the tools for the user's own data"))
        #expect(armed.contains("instead of guessing at it"))
        // No image in context → no vision phrase (#176 invariant).
        #expect(!armed.contains("attached image"))
    }

    @Test func armedEnumerationAddsVisionOnlyWithImageTools() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone.", hasTools: true, hasImageTools: true)
        #expect(armed.contains("text and barcodes in the attached image"))
    }

    @Test func armedEnumerationHonorsANarrowedFamilyList() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone.", hasTools: true,
            armedCapabilityFamilies: [.reminders])
        #expect(armed.contains("reminders"))
        #expect(!armed.contains("their health and activity"))  // never advertise an absent tool
    }
```

- [ ] **Step 2: Run to verify failure**

Run with `-only-testing:TalariaTests/CapabilityRegistryTests`. Expected: compile FAILS —
no `armedCapabilityFamilies` parameter.

- [ ] **Step 3: Implement**

In `instructionsText` (`LocalChatBackend.swift:1699`), add the parameter after
`hasImageTools`:

```swift
        hasImageTools: Bool = false,
        // #284: the armed blurb's capability list, generated from the
        // registry so it can never go stale again (#257's root cause was a
        // hand-written copy). Default = the full non-vision catalog; stage 3
        // passes the turn's armed subset. Vision joins via hasImageTools —
        // the #176 image gate, not the caller's list.
        armedCapabilityFamilies: [CapabilityGroup] = CapabilityGroup.allCases.filter { $0 != .vision },
```

Then replace the sentence at `:1847`. Old:

```swift
                + "Use the tools for the user's own data — their health, location, schedule, reminders, contacts, and past conversations — instead of guessing at it. Every action tool shows the user a confirmation card first; if they decline, accept it gracefully."
```

New:

```swift
                + "Use the tools for the user's own data — \(Self.armedEnumeration(families: armedCapabilityFamilies, hasImageTools: hasImageTools)) — instead of guessing at it. Every action tool shows the user a confirmation card first; if they decline, accept it gracefully."
```

with one small helper next to `instructionsText` (nonisolated static, same file):

```swift
    /// #284: the armed blurb's generated enumeration. Vision is appended
    /// here (never via the families list) so the persona mentions image
    /// reading exactly when the session was actually given those tools.
    nonisolated static func armedEnumeration(
        families: [CapabilityGroup], hasImageTools: Bool
    ) -> String {
        var all = families.filter { $0 != .vision }
        if hasImageTools { all.append(.vision) }
        return CapabilityRegistry.armedCapabilityEnumeration(families: all)
    }
```

Update the two pins in `DeviceToolBeltTests.swift` (`:117`, `:193`): both check
`contains("Use the tools for the user's own data")` — the frame survives, so **they
should still pass unchanged**; run them and only touch them if the assertion text
overlaps the replaced list portion.

- [ ] **Step 4: Run both suites**

`-only-testing:TalariaTests/CapabilityRegistryTests` then
`-only-testing:TalariaTests/DeviceToolBeltTests`. Expected: PASS both; registry suite
executed count = 10.

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/LocalChatBackend.swift TalariaTests/CapabilityRegistryTests.swift TalariaTests/DeviceToolBeltTests.swift
git commit -m "feat(#284): armed capability enumeration is registry-generated — #257's staleness class closed structurally

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Full-belt contrast line in the session budget flush

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend.swift:963-1000`
  (`recordSessionBudgetIfVerbose`, `flushSessionBudgetMeasurements`,
  `sessionBudgetLogLine`)
- Test: wherever `sessionBudgetLogLine` is currently pinned — grep
  `sessionBudgetLogLine` in `TalariaTests/`; extend that test file.

**Interfaces:**
- Consumes: the backend's full belt (`tools` property) and the existing post-turn flush.
- Produces: the verbose budget line additionally reports
  `fullBelt=<n>tok` so a narrowed (or toolless) turn shows what the full belt would
  have cost — #101's freed-budget number, measured per turn (spec §7).

- [ ] **Step 1: Write the failing test** (in the file that pins `sessionBudgetLogLine`)

```swift
    @Test func budgetLineCarriesTheFullBeltContrast() {
        let line = LocalChatBackend.sessionBudgetLogLine(
            toolCount: 2, toolTokens: 300, transcriptTokens: 1200,
            window: 8192, fullBeltTokens: 1470)
        #expect(line.contains("fullBelt=1470tok"))
        // Unknown stays honest — "—", never a fabricated 0 (real-data rule).
        let unknown = LocalChatBackend.sessionBudgetLogLine(
            toolCount: 2, toolTokens: 300, transcriptTokens: 1200,
            window: 8192, fullBeltTokens: nil)
        #expect(unknown.contains("fullBelt=—"))
    }
```

- [ ] **Step 2: Run to verify failure** (compile error: no `fullBeltTokens` parameter).

- [ ] **Step 3: Implement**

**(count-equality reuse removed 2026-08-08 during execution — review proved DEBUG
shaped cells make it lie; measure the full belt directly)** The shape below replaces
the original count-equality-reuse snippet, which is WRONG: `effectiveOfferedTools`
runs the offered set through `shapedBelt` in DEBUG, and the `.armedRemfix`/
`.armedFix`/`.armedNoschema` cells map tools to modified copies with the SAME count
and SAME names but different description/schema content — a count- or name-based
equality check silently mislabels that shaped belt's cost as the full belt's,
corrupting the contrast for exactly the cells built to test description/schema
changes.

Add `fullBeltTokens: Int?` to `sessionBudgetLogLine` and insert
`" fullBelt=\(fullBeltTokens.map { "\($0)tok" } ?? "—")"` into the line BEFORE the
trailing `" (#228)"` tag — every line in this file ends on the tag, tag-last is the
file's convention (read the current implementation and match its exact style). In
`flushSessionBudgetMeasurements`, measure the full belt directly, ONCE per flush,
hoisted above the `for entry in pending` loop (the installed belt doesn't change
between queued entries):

```swift
            let fullBelt = await MainActor.run { self.tools }
            let fullBeltTokens: Int?
            if fullBelt.isEmpty {
                fullBeltTokens = 0
            } else {
                fullBeltTokens = try? await model.tokenCount(for: fullBelt)
            }
            for entry in pending {
                ...
```

and pass the same `fullBeltTokens` through to every entry's log line. Keep the
honesty rule: unknown (`nil`) renders "—", never a fabricated 0. (`self.tools` is
the backend's full installed belt; if the property is named differently, it is the
one `effectiveOfferedTools` filters at `LocalChatBackend.swift:1224` — use that
exact name.)

- [ ] **Step 4: Run tests to verify pass.** Expected: PASS, count moved.

- [ ] **Step 5: Commit**

```bash
git add -A Talaria/ TalariaTests/
git commit -m "feat(#284): session budget line carries a full-belt contrast — #101's freed-budget number, measured per turn

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Stage 2 — the Bool-vector probe (DEBUG; bars before run; Owen routes)

### Task 5: `ToolIntentRouteVector` schema + `routeVector` probe function

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend+IntentRouting.swift` (DEBUG section,
  next to `routeIntent` at `:281`)
- Test: `TalariaTests/CapabilityRegistryTests.swift` (extend — schema mapping only; the
  generation itself is device-measured, not unit-tested)

**Interfaces:**
- Consumes: the production router session shape (`toolIntentRouterInstructions`,
  `routerPrompt`, `toolIntentRouterOptions`, `productionRouterVariant`) — reuse
  verbatim, zero copies, exactly as `routeIntent` does.
- Produces: `@Generable struct ToolIntentRouteVector` (gate Bool + 10 domain Bools),
  `armedGroups` mapping to `Set<CapabilityGroup>`, and
  `func routeVector(prompt:context:hasImage:) async -> (needsDeviceTool: Bool, groups: Set<CapabilityGroup>, raw: ToolIntentRouteVector?)`.
  Task 7's runner and Task 9's promotion consume these.

- [ ] **Step 1: Write the failing mapping test**

```swift
    @Test func vectorMapsTrueFieldsToGroups() {
        let vector = ToolIntentRouteVector(
            needsDeviceTool: true,
            wantsCalendar: true, wantsReminders: false, wantsAlarms: false,
            wantsHealth: true, wantsWeather: false, wantsPlaces: false,
            wantsContacts: false, wantsConversations: false,
            wantsDeviceStatus: false, wantsLocation: false)
        #expect(vector.armedGroups == [.calendar, .health])
        let none = ToolIntentRouteVector(
            needsDeviceTool: true,
            wantsCalendar: false, wantsReminders: false, wantsAlarms: false,
            wantsHealth: false, wantsWeather: false, wantsPlaces: false,
            wantsContacts: false, wantsConversations: false,
            wantsDeviceStatus: false, wantsLocation: false)
        #expect(none.armedGroups.isEmpty)   // all-false = abstention = full belt (O1)
    }
```

(This test compiles in DEBUG test builds; the type is `#if DEBUG` until Task 9
promotes it — mark the test `#if DEBUG` the way existing harness tests in the suite
are.)

- [ ] **Step 2: Run to verify failure** (type undefined).

- [ ] **Step 3: Implement** (inside the existing `#if DEBUG` region of
  `+IntentRouting.swift`; **this whole block moves outside DEBUG in Task 9's promotion
  commit if the probe clears — note that in the doc comment now**)

```swift
    /// #284: the Bool-vector route — #217B's own surviving hypothesis. Ten
    /// INDEPENDENT binaries instead of one multiway intent, because this
    /// model abstains on binaries (200/200 lifetime) and never on a
    /// multiway choice (zero safe misses in 380 classifications). Guides
    /// follow the v2 tactic — a positive test each, certainty framing, no
    /// exclusion lists, and none of the trap domains named (teach-to-the-
    /// test discipline, #217B).
    ///
    /// DEBUG-only until the #284 probe clears its pre-registered bars; the
    /// promotion commit moves this type out of `#if DEBUG` (#218).
    @Generable
    struct ToolIntentRouteVector {
        @Guide(description: "true only if replying needs to read from or act on this user's device right now")
        let needsDeviceTool: Bool
        @Guide(description: "true only if certain the user is asking about their calendar events or schedule, or to put something on the calendar")
        let wantsCalendar: Bool
        @Guide(description: "true only if certain the user is asking about their reminders or to-dos, or to create one")
        let wantsReminders: Bool
        @Guide(description: "true only if certain the user is asking to set, change, or ask about an alarm or wake-up time")
        let wantsAlarms: Bool
        @Guide(description: "true only if certain the user is asking about their own body or activity data: steps, sleep, workouts, heart rate")
        let wantsHealth: Bool
        @Guide(description: "true only if certain the user is asking about current or upcoming weather")
        let wantsWeather: Bool
        @Guide(description: "true only if certain the user is asking to find a place, business, or point of interest near them")
        let wantsPlaces: Bool
        @Guide(description: "true only if certain the user is asking about a person in their contacts: phone, email, address")
        let wantsContacts: Bool
        @Guide(description: "true only if certain the user is asking about something said in their own past conversations here")
        let wantsConversations: Bool
        @Guide(description: "true only if certain the user is asking about this device itself: battery, storage, network")
        let wantsDeviceStatus: Bool
        @Guide(description: "true only if certain the user is asking where they are right now")
        let wantsLocation: Bool

        var armedGroups: Set<CapabilityGroup> {
            var groups: Set<CapabilityGroup> = []
            if wantsCalendar { groups.insert(.calendar) }
            if wantsReminders { groups.insert(.reminders) }
            if wantsAlarms { groups.insert(.alarms) }
            if wantsHealth { groups.insert(.health) }
            if wantsWeather { groups.insert(.weather) }
            if wantsPlaces { groups.insert(.places) }
            if wantsContacts { groups.insert(.contacts) }
            if wantsConversations { groups.insert(.conversations) }
            if wantsDeviceStatus { groups.insert(.deviceStatus) }
            if wantsLocation { groups.insert(.location) }
            return groups
        }
    }

(vectorRouterOptions added 2026-08-08 after device run 21F0C10D — the production
64-token cap truncated every 11-field generation)

```swift
    /// #284: the vector probe's options. Same greedy determinism as
    /// production's router options, but the 11-field JSON needs ~90-110
    /// response tokens — the production cap of 64 truncated EVERY vector
    /// generation on device (run 21F0C10D: 165/165 errors), so the vector
    /// carries its own cap. Production's `toolIntentRouterOptions` is a
    /// measured artifact and stays untouched.
    nonisolated static var vectorRouterOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256)
    }

    /// #284 probe: one generation, the production router's exact session,
    /// instructions, prompt envelope, and options — modeled on `routeIntent`
    /// (#217), which proved a second field costs the gate nothing. Fails
    /// safe the same way production does: error → armed, no groups → full
    /// belt (O2).
    func routeVector(prompt: String, context: String = "",
                     hasImage: Bool = false) async
        -> (needsDeviceTool: Bool, groups: Set<CapabilityGroup>, raw: ToolIntentRouteVector?) {
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.routerInstructions(
                for: Self.productionRouterVariant,
                includeImageGuide: Self.productionIncludesImageGuide)))
        do {
            let route = try await session.respond(
                to: Prompt(Self.routerPrompt(context: context, prompt: prompt,
                                             variant: Self.productionRouterVariant,
                                             hasImage: hasImage)),
                generating: ToolIntentRouteVector.self,
                options: Self.vectorRouterOptions
            ).content
            return (route.needsDeviceTool, route.armedGroups, route)
        } catch {
            Self.logger.notice("routeVector: classification failed — failing safe to armed + full belt (\(String(String(describing: error).prefix(80)), privacy: .public)) (#284)")
            Self.routerFailureTally += 1
            return (true, [], nil)
        }
    }
```

- [ ] **Step 4: Run the mapping test to verify pass.**

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/LocalChatBackend+IntentRouting.swift TalariaTests/CapabilityRegistryTests.swift
git commit -m "feat(#284): ToolIntentRouteVector schema + routeVector probe fn — the Bool-vector hypothesis, DEBUG until bars clear

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: The vector probe grid

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend+Battery.swift` (next to
  `intentProbeGrid` at `:1790`)
- Test: `TalariaTests/CapabilityRegistryTests.swift` (extend)

**Interfaces:**
- Consumes: `CapabilityGroup`, `CapabilityRegistry.toolNames(for:in:)`.
- Produces: `vectorProbeGrid: [(text: String, expectedArmed: Bool, expectedGroups: Set<CapabilityGroup>, expectedTools: Set<String>)]`
  and `vectorMetaRows: [String]`. Task 7's runner iterates both.

**Do NOT add rows to `intentProbeGrid` or `routerBaselineProbes`** — both are closed
series with pre-registered histories (the #205 lesson, recorded at
`+Battery.swift:1776-1789`). The vector grid is a NEW list that copies row text.

- [ ] **Step 1: Write the failing consistency tests**

```swift
    #if DEBUG
    @Test @MainActor func vectorGridExpectationsAreInternallyConsistent() {
        let catalog = CapabilityRegistry(belt: Self.fullBelt()).descriptors
        for row in LocalChatBackend.vectorProbeGrid {
            // A toolless row expects no groups and no tools.
            if !row.expectedArmed {
                #expect(row.expectedGroups.isEmpty && row.expectedTools.isEmpty)
                continue
            }
            // Every expected tool is reachable from the expected groups —
            // otherwise the danger bar is unsatisfiable by construction.
            let reachable = CapabilityRegistry.toolNames(for: row.expectedGroups, in: catalog)
            #expect(row.expectedTools.isSubset(of: reachable),
                    "row '\(row.text)': expected tools unreachable from expected groups")
        }
    }

    @Test func vectorGridKeepsTheTrapRows() {
        let texts = LocalChatBackend.vectorProbeGrid.map(\.text)
        // #217B's falsifiability traps survive verbatim (spec §5.2).
        #expect(texts.contains("Play some music"))
        #expect(texts.contains("How long will it take me to drive to the airport?"))
        #expect(texts.contains("Read the label on this bottle for me"))
    }
    #endif
```

- [ ] **Step 2: Run to verify failure** (grid undefined).

- [ ] **Step 3: Implement the grid** (in `+Battery.swift`, `#if DEBUG`, right after
  `intentProbeGrid`)

(calendar-create row widened 2026-08-08 during execution — #215's measured residue;
lookupContact deliberately unprotected per Owen's protect-the-answer ruling)

```swift
    /// #284: the Bool-vector grid. A NEW list — `intentProbeGrid` (#217B)
    /// and `routerBaselineProbes` are closed series and never grow (#205).
    /// Row text for the first 19 rows is copied verbatim from
    /// `intentProbeGrid` so the two probes remain comparable.
    /// `expectedTools` is the danger-bar annotation, written BEFORE the run:
    /// the tools full-belt production behavior uses on that prompt. A trial
    /// is DANGEROUS iff the model armed a non-empty group set whose tools
    /// don't cover expectedTools (all-false is safe by construction — O1
    /// arms the full belt).
    nonisolated static let vectorProbeGrid: [(text: String, expectedArmed: Bool,
                                              expectedGroups: Set<CapabilityGroup>,
                                              expectedTools: Set<String>)] = [
        ("Remind me to buy milk tomorrow at 9am", true, [.reminders], ["createReminder"]),
        ("Add pick up dry cleaning to my reminders", true, [.reminders], ["createReminder"]),
        ("Set an alarm for 6:30", true, [.alarms], ["scheduleAlarm"]),
        ("Wake me up at 7 tomorrow", true, [.alarms], ["scheduleAlarm"]),
        // #215 (run F486F103) measured this exact prompt at create 10/10 +
        // readCalendar 7/10 + lookupContact 7/10. lookupContact is DELIBERATELY
        // unprotected — #215 names that chain over-serving, and #200W's un-routed
        // run saw the chain invent a place on 5/8 creates; the bar protects the
        // answer path, not the spiral (Owen, 2026-08-08).
        ("Put lunch with Sam on my calendar Friday at noon", true, [.calendar], ["createCalendarEvent", "readCalendar"]),
        ("Do I have anything on my calendar Friday?", true, [.calendar], ["readCalendar"]),
        ("What's the weather like right now?", true, [.weather], ["currentWeather"]),
        ("Is it going to rain this afternoon?", true, [.weather], ["currentWeather"]),
        ("How many steps have I taken today?", true, [.health], ["readHealth"]),
        ("How did I sleep last night?", true, [.health], ["readHealth"]),
        ("When did I last text Sam about the boat?", true, [.conversations], ["searchConversations"]),
        ("How much battery do I have left?", true, [.deviceStatus], ["deviceStatus"]),
        ("What's Sam's phone number?", true, [.contacts], ["lookupContact"]),
        ("Find a coffee shop near me", true, [.places], ["searchPlaces"]),
        // The out-of-vocabulary traps, kept verbatim (#217B). Correct vector
        // answer: armed, ALL BOOLS FALSE → full belt. No belt tool serves
        // them, so expectedTools is empty and only a spurious non-empty
        // group set can be dangerous here — exactly the failure #217B's
        // enum could not avoid.
        ("Play some music", true, [], []),
        ("How long will it take me to drive to the airport?", true, [], []),
        ("Read the label on this bottle for me", true, [], []),
        // Toolless rows, verbatim.
        ("Write a haiku about sledding", false, [], []),
        ("What's 2+2?", false, [], []),
        // #284 NEW: multi-intent rows — the union case the enum could not
        // express at all.
        ("What's my day look like tomorrow?", true, [.calendar, .reminders, .weather],
         ["readCalendar", "readReminders", "currentWeather"]),
        ("Anything due today, and do I need an umbrella?", true, [.reminders, .weather],
         ["readReminders", "currentWeather"]),
    ]

    /// #284: measurement-only rows — no bar, no expectation. Where does a
    /// capability-meta question ROUTE? (Spec §4's open question: if these
    /// route toolless, Task 12 adds the toolless capability index as its own
    /// measured arm.)
    nonisolated static let vectorMetaRows: [String] = [
        "What can you do?",
        "What kinds of things can you help me with?",
    ]
```

- [ ] **Step 4: Run tests to verify pass.**

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/LocalChatBackend+Battery.swift TalariaTests/CapabilityRegistryTests.swift
git commit -m "feat(#284): vector probe grid — 19 rows copied verbatim + 2 multi-intent + 2 meta rows; danger annotations pre-written

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Probe runner + Developer screen trigger

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend+Battery.swift` (next to
  `runIntentRouterProbe` at `:2033`)
- Modify: `Talaria/Features/Settings/DeveloperSettingsScreen.swift:897` (add a button
  beside the intent-probe trigger, same UI pattern)
- Test: none new (the runner is a DEBUG harness; its scoring helper gets a unit test)

**Interfaces:**
- Consumes: `routeVector` (Task 5), `vectorProbeGrid`/`vectorMetaRows` (Task 6),
  `batteryEmit`/`batteryRecorder`/`beginBatteryRun` (existing harness plumbing —
  model every call on `runIntentRouterProbe`, `+Battery.swift:2033-2095`).
- Produces: `runVectorRouterProbe(trials:)`, log lines greppable by
  `router: [vector]`, and the pure scorer
  `static func vectorTrialIsDangerous(armed:groups:expectedArmed:expectedTools:catalog:) -> Bool`.

- [ ] **Step 1: Write the failing scorer test**

```swift
    #if DEBUG
    @Test @MainActor func dangerScoringMatchesTheSpecDefinition() {
        let catalog = CapabilityRegistry(belt: Self.fullBelt()).descriptors
        // Narrowed to reminders when the prompt needed the calendar read → dangerous.
        #expect(LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [.reminders], expectedArmed: true,
            expectedTools: ["readCalendar"], catalog: catalog))
        // All-false → full belt → never dangerous (O1).
        #expect(!LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [], expectedArmed: true,
            expectedTools: ["readCalendar"], catalog: catalog))
        // Right group → covered → safe.
        #expect(!LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [.calendar], expectedArmed: true,
            expectedTools: ["readCalendar"], catalog: catalog))
        // Spurious arming on a trap row (no expected tools) → dangerous:
        // the belt narrowed for no reason on a prompt no belt tool serves.
        #expect(LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [.reminders], expectedArmed: true,
            expectedTools: [], catalog: catalog))
    }
    #endif
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement scorer + runner**

```swift
    /// #284: the danger-bar scorer, pure so it is unit-pinned. Dangerous ==
    /// the narrowed belt would lack a tool production uses on this prompt
    /// (spec §5.3), scored against the row's pre-written annotation.
    nonisolated static func vectorTrialIsDangerous(
        armed: Bool, groups: Set<CapabilityGroup>, expectedArmed: Bool,
        expectedTools: Set<String>, catalog: [CapabilityDescriptor]
    ) -> Bool {
        guard expectedArmed, armed, !groups.isEmpty else { return false }
        if expectedTools.isEmpty { return true }   // spurious narrowing on a trap row
        let offered = CapabilityRegistry.toolNames(for: groups, in: catalog)
        return !expectedTools.isSubset(of: offered)
    }

    func runVectorRouterProbe(trials: Int) async {
        guard Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let catalog = CapabilityRegistry(belt: tools).descriptors
        let baseline = Self.routerBaselineProbes
        let grid = Self.vectorProbeGrid
        Self.batteryEmit("router: VECTOR PROBE START trials=\(trials) baseline=\(baseline.count) grid=\(grid.count) meta=\(Self.vectorMetaRows.count) (#284)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: ["vector"], kind: "vector")

        // Band 1 — the regression gate: the pinned ten through the vector
        // schema. The gate bar (≥95%) reads from these lines.
        for probe in baseline {
            var correct = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                let route = await routeVector(prompt: probe.text)
                if route.needsDeviceTool == probe.expected { correct += 1 }
            }
            Self.batteryEmit("router: [vector] baseline \(correct)/\(trials) expected=\(probe.expected) probe=\(probe.text)")
            Self.batteryRecorder.recordProbe(
                probe: probe.text, expected: probe.expected, correct: correct,
                trials: trials, variant: "vector", band: "baseline",
                errors: Self.routerFailureTally - failuresBefore, intentTally: [:])
        }

        // Band 2 — the vector grid: gate accuracy, group accuracy, danger.
        for row in grid {
            var boolCorrect = 0, groupsExact = 0, dangerous = 0
            var tally: [String: Int] = [:]
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                let route = await routeVector(prompt: row.text)
                if route.needsDeviceTool == row.expectedArmed { boolCorrect += 1 }
                if route.groups == row.expectedGroups { groupsExact += 1 }
                if Self.vectorTrialIsDangerous(
                    armed: route.needsDeviceTool, groups: route.groups,
                    expectedArmed: row.expectedArmed,
                    expectedTools: row.expectedTools, catalog: catalog) { dangerous += 1 }
                let key = route.groups.map(\.rawValue).sorted().joined(separator: "+")
                tally[key.isEmpty ? "∅" : key, default: 0] += 1
            }
            Self.batteryEmit("router: [vector] grid armed=\(boolCorrect)/\(trials) groups=\(groupsExact)/\(trials) DANGEROUS=\(dangerous)/\(trials) want=\(row.expectedGroups.map(\.rawValue).sorted().joined(separator: "+")) tally=\(tally) probe=\(row.text)")
            Self.batteryRecorder.recordProbe(
                probe: row.text, expected: row.expectedArmed, correct: boolCorrect,
                trials: trials, variant: "vector", band: "grid",
                errors: Self.routerFailureTally - failuresBefore,
                expectedIntent: row.expectedGroups.map(\.rawValue).sorted().joined(separator: "+"),
                intentTally: tally)
        }

        // Band 3 — meta rows: measurement only, no bar (spec §4).
        // (META failure tracking added 2026-08-08 during execution — review
        // caught fail-safe noise polluting the measurement band.)
        for text in Self.vectorMetaRows {
            var armedCount = 0
            var tally: [String: Int] = [:]
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                let route = await routeVector(prompt: text)
                if route.needsDeviceTool { armedCount += 1 }
                let key = route.groups.map(\.rawValue).sorted().joined(separator: "+")
                tally[key.isEmpty ? "∅" : key, default: 0] += 1
            }
            Self.batteryEmit("router: [vector] META armed=\(armedCount)/\(trials) tally=\(tally) errors=\(Self.routerFailureTally - failuresBefore) probe=\(text)")
        }
        Self.batteryEmit("router: VECTOR PROBE DONE (#284)")
        Self.batteryRecorder.endRun()
    }
```

If `recordProbe`'s signature differs (e.g. `expectedIntent` optionality), match the
call at `+Battery.swift:2086-2090` exactly — that call is the template.

In `DeveloperSettingsScreen.swift`, duplicate the intent-probe button block around
`:897`, retitled "Vector router probe (#284)", calling
`await backend.runVectorRouterProbe(trials: trials)`.

- [ ] **Step 4: Run the scorer test to verify pass; build the app target**
  (CLI compile check from CLAUDE.md) to prove the Developer screen edit compiles.

- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/LocalChatBackend+Battery.swift Talaria/Features/Settings/DeveloperSettingsScreen.swift TalariaTests/CapabilityRegistryTests.swift
git commit -m "feat(#284): vector probe runner + Developer trigger — gate/groups/danger bands, meta rows measured barless

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Pre-register the bars in OPEN_ITEMS #284 — BEFORE the device run

**Files:**
- Modify: `OPEN_ITEMS.md` (the #284 entry, after the 2026-08-08 API-answer note)

**This commit must land before Task 9's run happens.** A missed bar is a
falsification, not a redefinition.

- [ ] **Step 1: Append to the #284 entry** (dated note, matching the entry's style):

```markdown
> **#284 BARS PRE-REGISTERED <date> — before the vector probe run, per the
> post-#215 convention. Spec: `planning/superpowers/specs/2026-08-08-284-capability-broker-design.md` §5.**
> Vehicle: `runVectorRouterProbe(trials: 5)`, Developer screen, on device.
> - **Gate:** armed/toolless Bool ≥95% across the pinned baseline ten AND the
>   grid rows (#217B measured 100% with a second field; ten fields is what
>   this run tests).
> - **Dangerous ≤2%** of grid trials, scored by `vectorTrialIsDangerous`
>   against each row's pre-written `expectedTools` annotation. Dangerous =
>   the narrowed belt lacks a tool full-belt production uses on that prompt;
>   all-false is safe by construction (fails open to the full belt).
> - **In-scope groups ≥90%:** on rows with a non-empty expectedGroups, the
>   exact expected set at ≥90% of trials.
> - **Meta rows:** measurement only, no bar — they answer spec §4's routing
>   question for Task 12.
> - **Reclaim (reported, not barred):** measured narrowed-vs-full belt token
>   delta via the #284 budget contrast line.
> **Pre-registered responses:** danger bar missed → selective arming does NOT
> ship; lane closes at stages 1–2 (registry, #257 armed fix, verdict filed) —
> #217B's shape. Gate bar missed → the vector schema is abandoned outright
> (it would be degrading the 200/200 Bool). Owen routes the verdict either way.
> - **Chain stance (Owen, 2026-08-08):** the danger bar protects the answer path,
>   not tool-chaining residue — lookupContact on the calendar-create row is
>   deliberately unprotected (#215's named over-serving).
```

- [ ] **Step 2: Commit**

```bash
git add OPEN_ITEMS.md
git commit -m "docs(#284): vector-probe bars pre-registered before the run

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Device run + verdict — CHECKPOINT, Owen routes

**Files:**
- Modify: `OPEN_ITEMS.md` (#284 entry — verdict note with the numbers)

- [ ] **Step 1: Deploy the probe build to the device.** Corded: Xcode MCP
  `RunProject` when available. Uncorded: `scripts/mac/ota-stage.sh t27-284-capability-broker`
  on the Mac Mini, install from Safari (the proven OTA path). The probe needs the
  DEBUG Developer screen, so the build must be a Debug/dev-signed build.
- [ ] **Step 2: Owen (or a driven session) runs "Vector router probe (#284)" at
  trials=5.** Collect the `router: [vector]` lines from Console
  (subsystem `org.aethyrion.talaria`, category `LocalChatBackend`; `.notice` level —
  Console's default view hides `.info`).
- [ ] **Step 3: Score against the Task 8 bars. File the verdict in the #284 entry**
  with per-row numbers, the run id, and the meta-row routing answer. **STOP: Owen
  routes.** Cleared bars + his go → Stage 3. Missed danger/gate bar → skip Tasks
  10–12, go to Task 13 (close-out; pre-registered response applies).

---

## Stage 3 — promotion (ONLY on a cleared verdict + Owen's go)

### Task 10: Promote the vector route into production arming

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend+IntentRouting.swift` (move
  `ToolIntentRouteVector` + `routeVector` out of `#if DEBUG`; add the flag)
- Modify: `Talaria/Services/Live/LocalChatBackend.swift` (`preparedSession:867`,
  `effectiveOfferedTools:1215`, new stored property beside `turnRoutedToolless:134`)
- Test: `TalariaTests/CapabilityRegistryTests.swift` (extend — the O1/O2/O3/V pins)

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: `turnArmedGroups: Set<CapabilityGroup>` (per-turn, `[]` = full belt),
  `nonisolated static let selectiveArmingEnabled = true` (the one-flag rollback,
  `turnRoutingEnabled`'s pattern at `+IntentRouting.swift:29`), and the narrowed
  `effectiveOfferedTools`.

- [ ] **Step 1: Write the failing fail-open pins**

```swift
    // Fail-open pins (spec §6). These drive effectiveOfferedTools directly —
    // the same entry point production calls. Construction is the
    // ContextOverflowGuardTests.swift:97 pattern + the Task 2 belt helper.
    @MainActor private func makeArmedBackend() -> LocalChatBackend {
        let backend = LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "capability-registry-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
        backend.installTools(Self.fullBelt(), relay: ToolEventRelay())
        return backend
    }

    @Test @MainActor func o1AllFalseVectorArmsTheFullBelt() {
        let backend = makeArmedBackend()
        backend.setTurnArming(routedToolless: false, groups: [])   // O1
        let offered = backend.effectiveOfferedTools(hasImageInContext: false)
        #expect(offered.count == backend.installedToolCountForTesting - 2)  // full minus the 2 image-gated vision tools
    }

    @Test @MainActor func narrowedBeltIsExactlyTheArmedGroupsTools() {
        let backend = makeArmedBackend()
        backend.setTurnArming(routedToolless: false, groups: [.reminders])
        let offered = Set(backend.effectiveOfferedTools(hasImageInContext: false).map(\.name))
        #expect(offered == ["readReminders", "createReminder"])
    }

    @Test @MainActor func ruleVImagePresenceUnionsVisionOverNarrowing() {
        let backend = makeArmedBackend()
        backend.setTurnArming(routedToolless: false, groups: [.reminders])
        let offered = Set(backend.effectiveOfferedTools(hasImageInContext: true).map(\.name))
        #expect(offered.contains("readImageText"))
        #expect(offered.contains("readBarcode"))
        #expect(offered.contains("readReminders"))
        #expect(!offered.contains("readHealth"))
    }
```

(Note O1's expectation: with no image in context, `DeviceToolBelt.offeredTools`
already withholds the 2 vision tools — the full-belt baseline for a no-image turn is
13, not 15. That is today's #176 behavior, not a narrowing effect.)

(`setTurnArming` and `installedToolCountForTesting` are small `// harness-visible`
setters added in Step 3 — the existing pattern for exactly this, per the #216 tag
convention. O2/O3 are covered by construction: `routeVector`'s catch returns `[]`,
and routing-disabled launches never set groups — assert both in a comment referencing
`routeVector`'s catch block rather than simulating a model error in unit tests.)

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

1. Move `ToolIntentRouteVector` + `routeVector` outside `#if DEBUG`. Add:

```swift
    /// #284: one-flag rollback (spec §6). Off → armed turns get the full
    /// belt — byte-identical to pre-promotion behavior.
    nonisolated static let selectiveArmingEnabled = true
```

2. In `LocalChatBackend.swift` beside `turnRoutedToolless` (`:134`):

```swift
    /// #284: the groups the vector armed for THIS turn. Empty = full belt
    /// (O1/O2/O3 all land here). Set only when routing is enabled and the
    /// promotion flag is on; reset per turn in preparedSession.
    private var turnArmedGroups: Set<CapabilityGroup> = []
```

3. In `preparedSession` (`:867`), replace the `routeNeedsDeviceTool` call:

```swift
            if Self.selectiveArmingEnabled {
                let route = await routeVector(
                    prompt: nextPrompt, context: priorAssistantTurn, hasImage: hasImage)
                turnRoutedToolless = !route.needsDeviceTool
                turnArmedGroups = route.groups
            } else {
                turnRoutedToolless = !(await routeNeedsDeviceTool(
                    prompt: nextPrompt, context: priorAssistantTurn, hasImage: hasImage))
                turnArmedGroups = []
            }
```

(and set `turnArmedGroups = []` in the `else` branch of the routing-enabled check at
`:871` — O3.) Extend the `:869` log line with
`groups=\(self.turnArmedGroups.map(\.rawValue).sorted().joined(separator: "+"))`.

4. In `effectiveOfferedTools` (`:1215`), after the `turnRoutedToolless` early return,
narrow the production expression (both the DEBUG-shaped and Release branches feed
through `DeviceToolBelt.offeredTools` — apply the narrowing to its result):

```swift
        var offered = DeviceToolBelt.offeredTools(from: tools, hasImageInContext: hasImage)
        if Self.selectiveArmingEnabled, !turnArmedGroups.isEmpty {
            let armedNames = CapabilityRegistry.toolNames(
                for: turnArmedGroups, in: CapabilityRegistry(belt: tools).descriptors)
            // Rule V: an image in context always unions vision on top —
            // the vector can narrow everything else, never vision.
            offered = offered.filter { armedNames.contains($0.name) || $0 is any ImageDependentTool }
        }
        return offered
```

5. Add the harness-visible test setters:

```swift
    func setTurnArming(routedToolless: Bool, groups: Set<CapabilityGroup>) {  // harness-visible
        turnRoutedToolless = routedToolless
        turnArmedGroups = groups
    }
    var installedToolCountForTesting: Int { tools.count }  // harness-visible
```

- [ ] **Step 4: Run the full registry suite + DeviceToolBeltTests. Then the Release
  build** (the #218 command in CLAUDE.md) — the promotion moved code across a
  `#if DEBUG` boundary, which is exactly the class of edit Debug suites cannot see.

- [ ] **Step 5: Commit**

```bash
git add -A Talaria/ TalariaTests/
git commit -m "feat(#284): PROMOTE Bool-vector selective arming — probe cleared bars; O1-O3+V fail-open pinned; one-flag rollback

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Armed blurb enumerates the offered subset

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend.swift` (the armed branch of
  `effectiveInstructionsText`, `:1254` region)
- Test: `TalariaTests/CapabilityRegistryTests.swift` (extend)

**Interfaces:**
- Consumes: `turnArmedGroups` (Task 10), `armedCapabilityFamilies:` (Task 3).
- Produces: instructions and belt cannot disagree on a narrowed turn.

- [ ] **Step 1: Failing test** — build instructions for a narrowed turn via the
  harness-visible path and assert the absent family is absent:

```swift
    @Test @MainActor func narrowedTurnInstructionsEnumerateOnlyOfferedFamilies() {
        let backend = makeArmedBackend()   // Task 10's helper, same file
        backend.setTurnArming(routedToolless: false, groups: [.reminders])
        let text = backend.effectiveInstructionsText(hasImageInContext: false)
        #expect(text.contains("reminders"))
        #expect(!text.contains("their health and activity"))
    }
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** — in the armed branch, pass the families:

```swift
        let families: [CapabilityGroup] = (Self.selectiveArmingEnabled && !turnArmedGroups.isEmpty)
            ? CapabilityGroup.allCases.filter { turnArmedGroups.contains($0) }
            : CapabilityGroup.allCases.filter { $0 != .vision }
        // …pass `armedCapabilityFamilies: families` into the production
        // armed instructionsText call in this branch.
```

- [ ] **Step 4: Run tests to verify pass.**
- [ ] **Step 5: Commit** (same trailer discipline).

---

### Task 12: The toolless capability index — ONLY if Task 9's meta rows routed toolless

**Files:**
- Modify: `Talaria/Services/Live/LocalChatBackend.swift` (the `toolless-lic2` branch,
  `:1865`)
- Modify: `OPEN_ITEMS.md` (#284 — the mini-arm's bar, pre-registered before ITS run)

**Skip this task entirely if the meta rows routed armed** — the registry-generated
armed blurb already answers them (spec §4).

- [ ] **Step 1: Pre-register the mini-arm in OPEN_ITEMS #284:** device A/B, the
  toolless-lic2 payload ± one appended sentence:
  `"You can also read the user's health and activity, location, the weather, nearby places, calendar, reminders, alarms, contacts, past conversations, and device status when asked — offer to, rather than saying you can't."`
  (generated via `CapabilityRegistry.armedCapabilityEnumeration(families:)` at the
  call site, never hand-written). Bars: the #257 bar ("what can you do?" names every
  family) AND no regression on the toolless canaries (composition + math rows clean,
  the toolless-lic2 heritage rows).
- [ ] **Step 2: Implement behind the same pattern as the other toolless clauses** — a
  new `includeToollessCapabilityIndex: Bool = false` parameter on `instructionsText`,
  appended after `toollessHonestyClauseV2`; production passes `true` only after the
  mini-arm clears.
- [ ] **Step 3: Run the mini-arm on device, file numbers, Owen routes promotion.**
- [ ] **Step 4: Commit** (implementation and promotion as separate commits, each with
  the trailer).

---

### Task 13: Lane gate + close-out

- [ ] **Step 1: `scripts/mac/lane-gate.sh`** on the branch — Debug suite + XCUITest +
  Release build, positive markers from each; background it and poll (it exceeds the
  4-minute tool cap).
- [ ] **Step 2: Device pass:** one fresh conversation asking "What can you do?" — the
  #257 bar, host-log/screenshot evidence into the entry. If Stage 3 shipped: one
  narrowed turn (e.g. "remind me to buy milk") verifying the `groups=` log line and
  the narrowed `fullBelt=` contrast in the budget line — **verify the mechanism fired,
  not just that the outcome looked right** (the 3A-F lesson).
- [ ] **Step 3: THE CLOSE-OUT RULE.** In the same closing commit, correct every line
  this lane's results falsified. Known upstream homes to check: the #284 entry itself
  (stage outcomes, probe verdict), #257 (root cause fixed — close or note), #229
  (belt-cost note gains the per-turn measured line), #216A/#217 archive entries (a
  dated supersession note: the Bool-vector hypothesis was run, with outcome), #101
  (the measured freed-budget number it was waiting for), CLAUDE.md's measurement
  section if selective arming shipped (the routed-production cell description), and
  the spec doc (an outcome note at top). New decisions or named-but-unstarted work get
  tracker numbers the day they are made (#268).
- [ ] **Step 4: PR** via `gh pr create` from the branch (body ends with the
  🤖 Generated with [Claude Code](https://claude.com/claude-code) line); hand Owen the
  push/merge. No external submission without his read of the exact text.

---

## Self-review record (per the writing-plans skill)

- **Spec coverage:** §3 registry → Tasks 1–2; §4 armed surface → Task 3, toolless →
  Task 12 (conditional, as specced); §5 probe → Tasks 5–9; §6 arming + fail-open +
  rule V → Task 10, blurb subset → Task 11; §7 budgets → Task 4; §8 testing → in-task
  TDD + Task 13 gate; §9 exclusions → nothing in this plan builds them; §10
  sequencing → stage structure + Task 9 checkpoint.
- **Placeholder scan:** clean — Tasks 10/11's backend construction is inlined
  (`makeArmedBackend`, modeled on the verified `ContextOverflowGuardTests.swift:97`
  pattern + Task 2's `fullBelt()` helper).
- **Type consistency:** `CapabilityGroup`/`CapabilityDescriptor`/`toolNames(for:in:)`/
  `armedCapabilityEnumeration(families:)`/`routeVector`/`turnArmedGroups`/
  `selectiveArmingEnabled` used identically across tasks. `init(belt: [Any])` is
  consumed with `[any Tool]` arguments throughout (bridges).
