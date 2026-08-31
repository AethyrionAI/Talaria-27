# #417 read-only code audit — can any production path reach the model with a silently-empty tool result?

**Repo:** `/Users/owenjones/Documents/Claude/Talaria-27` @ `main` (working tree clean at start; nothing was modified).
**Method:** static read of every FoundationModels `Tool` conformance in the tree, plus the belt-assembly,
routing, relay, governor and confirmation layers. No build, no simulator, no test run.

---

## VERDICT

**PARTIALLY — YES, exactly one production tool can return a content-free result, and it is
`LocationTool` (`currentLocation`). Every other production tool is structurally incapable of it.**

`LocationTool.performLocationRead` returns the literal string **`"Current location: "`** — a label,
a colon, and nothing else — when MapKit hands back a map item whose `name`, `cityName` and
`regionName` are all nil (or whose `name` is an empty string). The `guard let parts` on
`DeviceReadTools.swift:131` only catches a **nil** return; `reverseGeocodedParts` returns a
**non-nil empty array** in that case, so the guard passes and the empty array is joined into the
answer. There is no data and no failure string — the model receives an affirmative-sounding
label with nothing behind it. All three MapKit properties are `nullable` in the iOS 27 SDK
(verified against `MKMapItem.h:36` and `MKAddressRepresentations.h:36,45`), so the path is real in
the type system, not hypothetical.

**Confidence:** HIGH that the code path exists and is not guarded (the composition is provable by
reading; no test pins it). **MEDIUM** on how often MapKit actually produces such an item —
that is the one part a device/sim probe would have to settle, and this lane was not permitted to
run one.

**Caveat that sharpens the verdict:** the returned string is *content-free*, not *literally empty*.
#417's dangerous condition was stated as "no data AND no failure string" — this qualifies on both
counts, but whether the model treats a bare `"Current location: "` the way it treats an empty belt
(50% fabrication) or the way it treats an honest no-data string (0%) is **unmeasured**. It sits
between the two arms #417 has already run, which is precisely why it is worth measuring rather
than arguing about.

A second, structurally different exposure is filed below: **production reaches an EMPTY BELT on
three real paths** (routed-toolless turns, the #232 tool-phase-cut retry, the #229 overflow retry).
That is the #211A-E condition — but production pairs it with the *toolless* instruction set,
whereas the 50%-fabrication cell used the *armed* instructions. Those are different cells, and the
production one has never been measured.

---

## Scope: the production belt

`AppContainer.swift:949-984` is the **only** `installTools` call site. The belt is exactly
`DeviceToolBelt.makeReadTools` (12 tools) + `DeviceToolBelt.makeActionTools` (3 tools) = **15
installed**; `DeviceToolBelt.offeredTools` drops the two `ImageDependentTool`s on an imageless
turn → **13 offered**, matching #417's recorded `beltSize 13`.

**Instrument-only tools cannot leak into a production belt.** Verified:
- `LocalChatBackend+ToolFailure.swift` is `#if DEBUG` from line 23 (the three `Failing*Tool` twins).
- `LocalChatBackend+Battery.swift` is `#if DEBUG` from line 19 to line 4095 — the *only* place the
  pinned-rollback twins (`WeatherToolRequiredPlace`, `DeviceHealthToolRequiredMetric`,
  `ReminderCreateToolRequiredFields`, `CalendarEventToolRequiredFields`, and the four
  `ReminderCreateTool*` variants) are ever constructed.
- The rollback twins themselves are compiled into Release (they are not `#if DEBUG`-gated in
  `DeviceReadTools.swift:516` / `DeviceHealthTool.swift:152`), but nothing in Release constructs
  them. They are dead weight, not a leak.
- `LocalChatBackend.effectiveOfferedTools` (`:1541-1556`): the shaped-belt seam is `#if DEBUG`;
  the `#else` branch is the plain production expression.
  ⚠️ **In a DEBUG build** (which is what the device runs — builds 3131/3134 were Debug)
  `Self.activeSessionShape` can empty or reshape the belt via the Diagnostics picker. That is an
  operator-driven instrument, not a user-reachable path.

---

## Table — every production tool × its content-free risk

| # | Tool (`name`) | File:line of `call` | Return paths that could be content-free | Class |
|---|---|---|---|---|
| 1 | `DeviceHealthTool` (`readHealth`) | `DeviceHealthTool.swift:43` (engine `:53`) | `lines` is empty only when the metric matched nothing → guarded at `:121` with "Unknown health metric …". Every metric branch appends either a value **or** an explicit "no data recorded." line, and an all-empty read appends the HealthKit-denial caveat (`:127-129`). | **CLEAN** |
| 2 | `LocationTool` (`currentLocation`) | `DeviceReadTools.swift:103` (engine `:111`) | `reverseGeocodedParts` returns `[]` (non-nil) when name+city+region are all nil → guard at `:131` passes → `"Current location: "`. | **CONFIRMED-EMPTY-PATH** (see below) |
| 3 | `MotionTool` (`readMotion`) | `DeviceReadTools.swift:217` (engine `:224`) | `lines` always gets ≥1 element: steps or `"No pedometer data recorded today."` (`:254-258`). Joined result never empty. *(Separate honesty nit at `:245-258`, below.)* | **CLEAN** |
| 4 | `CalendarReadTool` (`readCalendar`) | `DeviceCalendarTools.swift:22` (engine `:30`) | Empty event set guarded at `:63`; non-empty set → `prefix(25)` is non-empty; each line carries a day + time + title-or-"Untitled event". | **CLEAN** |
| 5 | `ReminderReadTool` (`readReminders`) | `DeviceCalendarTools.swift:110` (engine `:116`) | Empty set guarded at `:157` ("No open reminders."); each line is `"• <title>"` with `title ?? "Untitled reminder"` at `:148`. | **CLEAN** |
| 6 | `WeatherTool` (`currentWeather`) | `DeviceReadTools.swift:333` (engine `:384`/`:418`) | Every branch returns prose: unsupported day `:392-396`, no permission `:424`, no fix `:427`, geocode miss `:438`, no tomorrow entry `:455`, auth reject `:496`, generic failure `:499`. Success path always ≥2 formatted lines (`:469-477`). | **CLEAN** |
| 7 | `PlacesTool` (`searchPlaces`) | `DeviceReadTools.swift:548` | Empty query `:552`; zero results guarded `:608-610`; each line ≥ `item.name ?? "Unnamed place"` (`:595`); timeout arrives as `TimedOut` and is rendered by the `catch` at `:617`. | **CLEAN** |
| 8 | `ContactsTool` (`lookupContact`) | `DeviceReadTools.swift:671` | No name `:675`; permission `:682`/`:687`; no match `:706-709`. A contact with a blank name **and** no org **and** no phone/email still emits `"  (no phone or email on file)"` (`:723-725`), so the result is never blank — though its first line can be. Timeout → `DeviceToolTimeout.timeoutText`, non-empty. | **CLEAN** (blank *first line* possible; result never content-free) |
| 9 | `DeviceStatusTool` (`deviceStatus`) | `DeviceReadTools.swift:25` (engine `:37`) | Always appends battery, storage and thermal lines — 3 minimum, unconditionally (`:52/54`, `:63`, `:76`). `storageLine` is nil-safe on both sides (`DeviceToolBelt.swift:523-529`). | **CLEAN** |
| 10 | `ImageTextTool` (`readImageText`) | `DeviceMediaTools.swift:88` | No image `:93`; undecodable `:96`; zero recognized lines guarded `:115-117`. **Residual:** if Vision returns observations whose `topCandidates(1).first?.string` are all empty strings, `lines` is non-empty but its contents are blank → `"Text recognized in \"x\":\n"` + blanks. | **SUSPECT** (low likelihood; needs a Vision-behaviour probe) |
| 11 | `BarcodeReaderTool` (`readBarcode`) | `DeviceMediaTools.swift:142` | No image `:147`; undecodable `:150`; zero codes guarded `:164-165`. A blank payload still yields `"<symbology>: "` behind a header. | **CLEAN** |
| 12 | `ConversationSearchTool` (`searchConversations`) | `DeviceMediaTools.swift:302` (report `:326`) | Empty term `:306`; no sections guarded `:355-361` with a Spotlight-aware "No matches" string. Snippets are non-nil only when the term matched, so they contain at least the term. | **CLEAN** |
| 13 | `ReminderCreateTool` (`createReminder`) | `DeviceActionTools.swift:363` (engine `:378`) | Every exit is prose: empty title `:385`, three #233/#249 bounces `:421`/`:438`/`:453`, floor refusal `:471`, decline `:473`, empty edited title `:478`, unparsable due `:486`, permission `:494`/`:498`, no list `:539`, save failure `:544`, success `:549`. | **CLEAN** |
| 14 | `CalendarEventTool` (`createCalendarEvent`) | `DeviceActionTools.swift:891` (engine `:951`) | Same shape — `:957`, `:959`, `:979`, `:981`, `:985`, `:993`, `:1008`, `:1015`, `:1037`/`:1041`, `:1049`, success `:1053`. | **CLEAN** |
| 15 | `AlarmTool` (`scheduleAlarm`) | `DeviceActionTools.swift:1187` | Unparsable request `:1195`, floor refusal `:1211`, decline `:1213`, unparsable edit `:1219`, schedule failure `:1230`, success `:1228`. | **CLEAN** |

---

## The one confirmed finding, quoted

`Talaria/Services/Live/DeviceTools/DeviceReadTools.swift:131-138`

```swift
        guard let parts = await Self.reverseGeocodedParts(for: fix) else {
            return "Got a location fix, but reverse geocoding failed (this usually needs a network connection). Accuracy ±\(Int(fix.horizontalAccuracy))m."
        }
        var uniqueParts: [String] = []
        for part in parts where !uniqueParts.contains(part) {
            uniqueParts.append(part)
        }
        return "Current location: \(uniqueParts.joined(separator: ", "))"
```

`Talaria/Services/Live/DeviceTools/DeviceReadTools.swift:155-161`

```swift
    @MainActor
    private static func reverseGeocodedParts(for fix: CLLocation) async -> [String]? {
        guard let request = MKReverseGeocodingRequest(location: fix),
              let item = try? await request.mapItems.first else { return nil }
        let address = item.addressRepresentations
        return [item.name, address?.cityName, address?.regionName].compactMap { $0 }
    }
```

**Why the guard misses it.** The function's `nil` return means *"no map item at all"* — that case is
handled honestly. Its `[]` return means *"a map item with nothing on it"*, and `[]` is not `nil`, so
`guard let parts` admits it. `compactMap` then keeps an empty-string `name` as well, producing the
same output by a second route. SDK nullability (Xcode-beta6 iOS SDK, read directly):

- `MKMapItem.h:36` — `@property (nonatomic, copy, nullable) NSString *name;`
- `MKMapItem.h:34` — `addressRepresentations` is `nullable`
- `MKAddressRepresentations.h:36,45` — `cityName` and `regionName` are both `nullable`

**Nothing pins this.** `grep` for `"Current location:"` across the tree finds only fixtures
(`AppLockGateTests.swift:416,575`, `PhoneQueryResponderTests.swift:25,79,138,186`) that hard-code
`"Current location: Home"` — no test exercises `reverseGeocodedParts` at all.

**Second consumer, same defect.** `LivePhoneQueryReader.location` (`PhoneQueryResponder.swift:42-44`)
calls the *same* static, and `PhoneQueryResponder.answer` returns it as `.success(text:)`
(`:139`, `:161`) with no non-empty check. So a content-free `"Current location: "` would also reach
the **Hermes** agent over the talaria plugin's phone-query path, where the same fabrication
question applies to a different model. That path is explicitly designed to relay honest failure
prose as `.success` ("Prose out", `:83-88`) — which is right, and is exactly why an empty prose
string slips through it.

---

## The relay / governor / confirmation layer

**No production code wraps, truncates or rewrites a tool's returned String.** `Tool.call` returns
`String` and FoundationModels consumes it directly; there is no `ToolOutput` or `GeneratedContent`
construction anywhere in production (`grep` finds only two comment mentions). The one place a tool
result is captured — `ToolEventRelay.completed(_:result:)`, `DeviceToolBelt.swift:288-295` — writes
to the DEBUG battery store only and never touches the transcript or the model (#212/#197).

| Layer | Can it hand the model empty/absent content? | Evidence |
|---|---|---|
| `ToolEventRelay.started` admission | No. Refusal strings are non-empty constants. | `DeviceToolBelt.swift:240-282` |
| `ToolCallGovernor.admit` | No. Both refusal branches compose ≥3 sentences including #409's do-not-claim clause. | `ToolCallGovernor.swift:164-198` |
| Governor 4th-refusal cut | **Throws** `ToolPhaseCutError` — the one sanctioned tool-path throw. #417 measured a throwing tool as fatal to the turn; here it is **caught** and retried. | `DeviceToolBelt.swift:249-251`, `LocalChatBackend.swift:1313-1316`, `:597-609`, `:875-886` |
| `ToolConfirmationCenter` decisions | No. `.refused` carries `ApprovalFloor.refusal(...)` or `unnamedRefusal`; `.declined` and `.approved` are rendered by the tool. `ApprovalFloor.refusal` returns nil only when nothing was flagged, and a nil there means the card stages normally. | `ToolConfirmationCenter.swift:225-308`, `ApprovalModeCore.swift:236-256` |
| `DeviceToolTimeout.run` | No. Returns `timeoutText(...)` — an explicit "timed out … returned nothing" sentence. | `DeviceMediaTools.swift:222-241` |
| `DeviceToolTimeout.runThrowing` | No. Throws `TimedOut`, rendered by the call site's own `catch` (only `PlacesTool` uses it, `:616-618`). | `DeviceMediaTools.swift:246-267` |
| `#338` honesty guard | Detects **unfulfilled ACTION claims** only (`ActionClaimDetector`). It has no notion of a fabricated sensor *reading*. | `LocalChatBackend.swift:1762-1796` |
| `LocalChatBackend+FabricationScorer` | `#if DEBUG` from line 11. **There is no production detector for an asserted reading.** | `LocalChatBackend+FabricationScorer.swift:11` |

### The empty-belt paths that DO exist in production

Not the question #417 asks, but the same hazard class, and it is reachable:

```
LocalChatBackend.swift:1546   if turnRoutedToolless { return [] }        // effectiveOfferedTools
LocalChatBackend.swift:604    turnRoutedToolless = true                  // #232 tool-phase-cut retry (send)
LocalChatBackend.swift:881    turnRoutedToolless = true                  // #232 tool-phase-cut retry (streamTurn)
LocalChatBackend.swift:1224   turnRoutedToolless = true                  // #229 overflow retry
```

The two retry paths are the sharper ones: the router had already classified the turn as
**needing a device tool**, the tools were reached, and the turn is then re-run with **zero tools**,
its prior tool results discarded with the dead session (`:600-602`).

**But the configuration is not the one that measured 50%.** `effectiveInstructionsText`
(`:1588-1594`) checks `turnRoutedToolless` first and swaps in
`productionToollessInstructions` — so production's empty belt always ships with the *toolless*
instruction set. #211A-E's toolless cell used `SessionShape.armedRouted`, i.e. the **armed**
instructions with an emptied belt (`LocalChatBackend+OfferRead.swift:324-334`, and the #417
tool-failure runner does the same at `+ToolFailure.swift:204-212`).

**Consequence, stated carefully:** the armed-instructions × empty-belt cell that fabricated 20/40
is **not reachable in production** (an empty offered belt implies `turnRoutedToolless`, which
implies toolless instructions; and `hasTools` reads the *installed* belt, which is always 15).
Production's toolless-instructions × empty-belt cell — including the #232/#229 retries of a turn the
router armed — has **never been measured** in either direction.

### Honesty nit found in passing (not an empty path)

`MotionTool` maps a **timeout** onto a **no-data assertion**:

```swift
// DeviceReadTools.swift:245-258
let stepsText = await DeviceToolTimeout.run(label: name) { ... return steps.map(String.init) ?? "" }
let steps = Int(stepsText)
if let steps { lines.append("Steps today (pedometer): \(steps)") }
else         { lines.append("No pedometer data recorded today.") }
```

On expiry `DeviceToolTimeout.run` returns the *sentence* `"The readMotion tool timed out after
12s and returned nothing…"`; `Int(...)` of that is nil, so the tool tells the model there is **no
pedometer data today** when in fact the read never completed. Non-empty, so it is protective
against #417's mechanism — but it is an affirmative claim the tool cannot support, and it is the
inverse of the contract in `DeviceReadTools.swift`'s own header.

---

## NOT AUDITED

1. **Runtime reachability of the `LocationTool` empty path.** Whether MapKit ever returns a map
   item with nil `name` + nil/blank address representations for a real fix. Requires a device or
   simulator probe; this lane was barred from running one.
2. **Vision's `topCandidates(1).first?.string` emptiness guarantee** — the `ImageTextTool` SUSPECT
   row rests on it.
3. **The DEBUG session-shape belts** (`Self.activeSessionShape` / `Self.shapedBelt`) beyond
   confirming they are Diagnostics-picker-driven and `#if DEBUG`. Individual shapes were not
   audited for content-free results; the device runs Debug builds, so an operator can reach them.
4. **Hermes-side (server) tools.** Only the on-device local-brain belt was in scope.
5. **`LocalIntelligenceService`, `GenerativeUI`, condensation and voice paths** — confirmed to
   contain no `Tool` conformances, but not otherwise read.
6. **No build, test, `xcodegen`, `simctl` or gate run** (per the lane's constraints), so nothing
   here is compile-verified; every claim is a source read.
7. **Whether the model actually fabricates on `"Current location: "`.** That is a measurement, not
   a code fact, and it is the follow-up this audit points at.

---

## Tracker-ready block for #417

```
> **🔎 CODE AUDIT 2026-08-30 (read-only, no build) — THE OPEN QUESTION HAS ONE ANSWER AND IT IS
> `currentLocation`.** All 15 production tools traced through every return path of `call`
> (12 read + 3 action; 13 offered on an imageless turn, matching the run's `beltSize`).
> **14 of 15 are structurally incapable of a content-free result** — every guard-else exit
> composes a prose sentence, every list builder is guarded on `isEmpty`, and no production
> code wraps or truncates a tool's returned String.
> - **The exception:** `LocationTool.performLocationRead` returns the literal `"Current location: "`
>   — label, colon, nothing — when the reverse geocode yields a map item with nil `name`,
>   `cityName` and `regionName`. `reverseGeocodedParts` returns a NON-NIL EMPTY ARRAY there and
>   the `guard let parts` at `DeviceReadTools.swift:131` only catches nil, so `[]` flows to the
>   join at `:138`. All three properties are `nullable` in the iOS 27 SDK (`MKMapItem.h:34,36`,
>   `MKAddressRepresentations.h:36,45`). No test touches `reverseGeocodedParts`.
> - **Same string reaches a SECOND model:** `PhoneQueryResponder` relays it to the Hermes agent as
>   `.success(text:)` with no non-empty check (`PhoneQueryResponder.swift:139,161`).
> - **Relay/governor layer is CLEAN:** governor refusals, `ApprovalFloor`, `DeviceToolTimeout` and
>   the confirmation gate all emit non-empty prose; `relay.completed(result:)` is DEBUG-only and
>   never reaches the model; the instrument twins are `#if DEBUG` and cannot leak onto a belt.
> - **Adjacent, and NOT the question asked:** production DOES reach an empty belt on three paths —
>   routed-toolless turns, and the #232 tool-phase-cut / #229 overflow retries of a turn the router
>   ARMED (`LocalChatBackend.swift:604, 881, 1224, 1546`). Production pairs those with the TOOLLESS
>   instructions, whereas #211A-E's 50%-fabrication cell used ARMED instructions with an emptied
>   belt (`+OfferRead.swift:324`). Those are different cells; the production one is unmeasured.
> - **No production detector exists for an asserted reading**: `+FabricationScorer.swift` is
>   `#if DEBUG`, and the #338 honesty guard only detects unfulfilled ACTION claims.
> **What a follow-up would measure, not fix:** (a) whether MapKit can actually produce such an item
> on a real fix; (b) whether the model fabricates on `"Current location: "` — it sits between the
> empty-belt arm (50%) and the honest-no-data arm (0%) and belongs to neither; (c) the production
> toolless-instructions × empty-belt cell reached by the #232/#229 retries.
```
