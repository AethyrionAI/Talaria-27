# OPUS T27 #296 — a tool you INTERRUPTED must not render as a tool that finished

**Tier that EXECUTES this lane: OPUS.** Written 2026-08-09 from a HEAD code read
(`t27-295-expiration-recovery`, `04af0a7`). No code was written for this brief.

**Goal:** give a tool call a third state — *interrupted* — distinct from *running*
and *completed*, so a turn the user stopped mid-tool stops claiming the tool
succeeded; and surface a host-reported tool error instead of parsing it and
throwing it away. Squarely inside #180's honest-degradation family: **the app
hiding its own degradation, one more time.**

---

## 1. Verified state

Line numbers from `t27-295-expiration-recovery` @ `04af0a7`.

### VERIFIED — every claim in #296's entry that I could check, plus what it omits

**The two-state rail — entry is CORRECT.**
- `Talaria/Features/Chat/MessageBubble.swift:566` —
  `isStreaming: message.isStreaming && group.contains(where: \.isActive)`.
  Exactly as filed, exactly at 566.
- `Talaria/Features/Chat/ToolActivityRail.swift:18-26` — `isStreaming` picks
  `liveIndicator` vs `finishedSummary`. **Two states, no third.**
- **The ✓ Owen photographed is `ToolActivityRail.swift:87`** —
  `Image(systemName: "checkmark")` in `finishedSummary`, with the accent tint at
  `:89`. The collapsed label beside it (`:72-77`) is the single tool's name, which
  is why the screenshot reads `✓ TERMINAL`.
- The expanded timeline's per-row icon is the same binary:
  `ToolActivityRail.swift:143-153` — `circle.dotted` in `Design.Brand.forge` while
  running, `circle.fill` in `Design.Brand.accent` otherwise. `:174-182` —
  `"running"` or a timestamp. **An interrupted call is indistinguishable from a
  successful one in both the collapsed chip and the expanded row.**

**`ToolCallEvent` — entry is CORRECT.**
- `Talaria/Models/StreamingUpdate.swift:7-23` — `struct ToolCallEvent`, exactly at
  line 7. `enum Phase { case started; case completed }` at `:8-11`. Fields:
  `name`, `phase`, `detail: String?`.

**`cancelStreaming` sets `isActive = false` on every activity — entry is CORRECT,
and here is the precise site it means.**
- `Talaria/Stores/ChatStore.swift:1267` — `func cancelStreaming(hardStopHost: Bool = true)`.
- `:1338-1368` — the `else` branch. When the placeholder is **not** empty
  (`stoppedPlaceholderHasNothingToShow` is false), it does
  `isStreaming = false`, `status = .delivered`, and then
  **`for i in …indices { toolActivities[i].isActive = false }` at `:1362-1364`.**
- `ChatStore.swift:1463-1468` — `stoppedPlaceholderHasNothingToShow` requires
  `message.toolActivities.isEmpty`, so **a stopped-mid-tool placeholder always
  takes the `else` branch** and is kept as a `.delivered` bubble. #294 made that
  deliberate ("tool activity with no prose is still something to keep"). #296 is
  the cost of that decision: kept, and mislabeled.
- **This is the whole mechanism, and it is entirely CLIENT-SIDE.** The client
  knows it stopped. No wire signal is required for the primary defect.

**Two OTHER sites also clear `isActive`, and neither is a bug** — name them so the
lane does not "fix" them:
- `ChatStore.swift:672-677` — a `.textDelta` resolves all in-flight chips (prose
  arrived, so the tool finished).
- `ChatStore.swift:704-709` — a new `tool.started` resolves its predecessor (tools
  run serially).
- `ChatStore.swift:722-726` — a named `tool.completed` resolves its own chip.

**The `error` field is parsed and discarded — entry is CORRECT, on the runs plane.**
- `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift:138` —
  `case toolCompleted(name: String, error: String?)`.
- `:180` — `return .toolCompleted(name: toolName, error: payload["error"] as? String)`.
- **`:472-473`** — `case .toolCompleted(let name, _):` →
  `ToolCallEvent(name: name, phase: .completed, detail: nil)`. **Parsed, bound to
  `_`, dropped.** The adversarial audit's dead-field finding reproduces exactly.

**The sessions plane has no equivalent, and its own comments say so.**
- `Talaria/Services/Live/SessionsHermesClient.swift:518-527` — `tool.started` and
  `tool.completed` share one arm; the comment reads *"`tool.completed` is usually
  empty (no result payload today — **verified against the live host**)."*
- `:1535-1545` — `parseToolCallEvent` reads `tool_name`, `args`, `preview`. **It
  never looks for an `error` key**, and for `.completed` it returns
  `ToolCallEvent(name:phase:)` with no detail at all.
- **So 296-C is runs-plane-only in the code as it stands.** See §4.2 for the
  correction this forces on the entry's framing.

**Which plane is even live.**
- `Talaria/Models/UserSettings.swift:414`, `:446`, `:551` — `useRunsTransport`
  defaults to **false**.
- `Talaria/Features/Settings/DeveloperSettingsScreen.swift:207-211` — a Developer
  flag, *"Runs Transport (Phase 3)"*.
- `AppContainer.swift:787` → `SessionsHermesClient.useRunsTransportProvider`.
- **296-A is plane-independent** (it lives in `cancelStreaming`). **296-C rides a
  default-off flag.**

**A stopped run's activities survive the finish and the relaunch.**
- `ChatStore.swift:788-793` — the `.finished` merge does
  `resolved.toolActivities = activities`, carrying the placeholder's list onto the
  final message. A new per-activity field set during streaming survives the turn.
- `ToolActivity` is `Codable` (`Talaria/Models/ToolActivity.swift:9`) and rides the
  conversation cache, so the marker survives relaunch — **subject to the decode
  trap in §6.**

**Existing test infrastructure this lane should reuse rather than rebuild.**
- `TalariaTests/AppStoresTests.swift:4401-4470` — `StoppableStreamingChatClient`,
  a `HermesClientProtocol` double that accepts a turn, streams its script, and
  **never finishes** — "which makes the Stop the test's own event rather than a
  race against a terminal frame." Script cases at `:4402-4412`, including
  `.toolActivityOnly(String)` at `:4408`.
- `TalariaTests/AppStoresTests.swift:1693-1716` —
  `stopDuringAToolCallKeepsTheActivityRow`, the #294-B test. **Line 1713 is
  `#expect(reply.toolActivities.allSatisfy { $0.isActive == false })`** — the
  assertion this lane must extend, in place. That test is the fixture 296-A needs;
  it already gets a chip on screen and taps Stop.
- `TalariaTests/RunsFrameParserTests.swift` — the home for a `parseRunsFrame`
  assertion on the `error` key.

### ASSUMED — flagged because the entry states one of these as settled fact

- **That the host ever populates `tool.completed`'s `error` on an interrupt.** See
  §4.1. The `{"output": "[Command interrupted]", "exit_code": 130}` capture is a
  **host log line**, not a client-side wire frame.
- **Which plane Owen's 291-D run was on.** The runs flag is default-off; the
  screenshot does not say. It does not matter for 296-A.
- **Whether a server-transcript reload preserves the marker.** It does not — see
  §6. Whether that is acceptable is a decision, not a finding.

---

## 2. The defect

A user taps Stop while a tool is in flight.

1. `ChatStore.cancelStreaming(hardStopHost: true)` runs (`:1267`).
2. The placeholder has a `ToolActivity`, so `stoppedPlaceholderHasNothingToShow`
   is false (`:1463-1468`) and the `else` branch keeps the row (`:1358-1365`).
3. That branch sets `isStreaming = false`, `status = .delivered`, and
   `isActive = false` on every activity (`:1362-1364`).
4. `MessageBubble.swift:566` computes `message.isStreaming && …isActive` →
   **false** → `ToolActivityRail` renders `finishedSummary`
   (`ToolActivityRail.swift:22-23`).
5. `finishedSummary` opens with `Image(systemName: "checkmark")`
   (`ToolActivityRail.swift:87`).

**And because the turn was stopped before any prose, that chip is the entire
message.** A checkmark is the whole content of the bubble, asserting that a
command completed which the user killed. Expanding it does not help: the expanded
row draws the same success-coloured `circle.fill` (`:149-152`).

**The information is not missing — it is discarded twice.** Once client-side
(`cancelStreaming` collapses "was running when the user stopped it" into the same
`isActive = false` that means "finished normally"), and once on the wire
(`RunsTransport.swift:472` binds the parsed `error` to `_`).

---

## 3. Pre-registered bars — 296-A/B/C VERIFIED AND REFINED

**296-A/B/C are already written in the `OPEN_ITEMS.md` #296 entry. They are sound.
The refinements below tighten them and add two the entry does not have; the
refinements must be written INTO the entry before any code**, per CLAUDE.md's
*"Where the BARS live."* **Do not edit `OPEN_ITEMS.md` from this brief's
authority** — the executing lane writes them, with Owen's routing.

---

**296-A — a tool in flight when Stop is tapped does NOT render a ✓.** *(entry's
wording; verified sound)*

*Refinement:* state it against the derived rail state, not against pixels, so it
is unit-testable: after `cancelStreaming()`, the surviving activity carries a
non-nil interrupted marker, **and** the pure state function that drives the rail's
glyph returns the interrupted case for it.

- *Evidence that settles it:* extend
  `AppStoresTests.stopDuringAToolCallKeepsTheActivityRow` (`:1693-1716`) — the
  fixture already exists — plus a pure-function test on the new rail-state
  derivation.
- *Device needed:* **no.** This is entirely client-side; the client knows it
  stopped.
- *Falsification:* if the marker cannot be set without changing what #294 kept
  (`reply.toolActivities.count == 1`, `status == .delivered`), the shape is wrong.

**296-B — a genuinely completed tool still renders a ✓.** *(entry's wording;
verified sound)*

*Refinement:* two rows, not one — (i) a tool resolved by a named `tool.completed`
(`ChatStore.swift:722-726`), and (ii) a tool resolved implicitly by prose arriving
(`:672-677`). Both are "completed" and both must keep the ✓; they take different
code paths and a fix that only handles one is a half-fix.

- *Evidence:* unit tests on the two resolution paths + the pure state function.
- *Device needed:* **no.**
- *This is the regression bar.* It is what stops the lane from "fixing" the ✓ by
  removing it.

**296-C — a host-reported tool error reaches the chip instead of being dropped.**
*(entry's wording; SOUND AS A CODE BAR, but its evidentiary basis needs correcting
— see §4.1)*

*Refinement, and this is the important one:* split it, because the two halves have
very different evidence costs.

- **296-C1 (code, no device):** when a runs-plane `tool.completed` frame carries a
  non-empty `error`, that text reaches `ToolCallEvent` and lands on the
  `ToolActivity`, instead of being bound to `_`.
  *Evidence:* a `parseRunsFrame` test in `RunsFrameParserTests.swift` (the parser
  already extracts it — `:180`) plus a transport-loop test that the value survives
  to the yielded `ToolCallEvent`. **Device needed: no.**
- **296-C2 (wire reality, device):** whether the host ever SENDS a non-empty
  `error` on `tool.completed` — on an interrupt or on an ordinary tool failure —
  is **unverified**. *Evidence:* one runs-plane device turn with the Developer
  flag ON, a deliberately failing tool call, and the frames read. **Device needed:
  yes.**
  **C1 must not be reported as C2.** Plumbing a field is not evidence the field
  arrives. If C2 comes back empty, C1 is still correct and still ships — it costs
  nothing and it is the honest place for the value if it ever appears.

**296-D (proposed, new) — the sessions plane is explicitly OUT of scope and the
entry says so.** With `useRunsTransport` off (the default), a stopped tool still
satisfies 296-A — because 296-A is client-side — but no host error text is
available at all, because `parseToolCallEvent` (`SessionsHermesClient.swift:1535-1545`)
never reads an `error` key and the wire carries no result payload
(`:520-522`, *"verified against the live host"*). **Bar: the entry records this in
writing** so a future reader does not conclude 296-C regressed on the default
transport.

- *Evidence:* the entry's own text. *Device needed:* no.

**296-E (proposed, new) — the marker must not cost anyone their history.**
Adding a field to `ToolActivity` must not break decoding of an existing cached
conversation. **Bar: a decode test against a JSON blob written by the CURRENT
schema (no new key) round-trips to a full conversation with its messages intact.**

- *Evidence:* a unit test in `TalariaTests/ChatStorePersistenceTests.swift` that
  decodes a fixture blob lacking the new key.
- *Device needed:* **no.**
- *Why it is a bar and not a note:* see §6. This is the one way this small lane
  can do real damage.

---

## 4. ⚠️ Tracker corrections

Small but real. Both go into `OPEN_ITEMS.md` #296 in the fix's own commit, per THE
CLOSE-OUT RULE.

### 4.1 "We already have the truth and throw it away" overstates the evidence

> #296 as written: *"The 3A-C device pass captured the host saying exactly what
> happened — `{"output": "[Command interrupted]", "exit_code": 130}` and `Turn
> ended: reason=interrupted_by_user`. On the runs plane the client receives
> `tool.completed` carrying an `error` field and parses it, then discards it."*

Two different things are welded together there.

- **The capture is a HOST LOG line.** `dispatch/DEVICE-PASS-RUNNING-LIST.md:295-297`
  says the 3A evidence came from *"`~/.hermes/logs/agent.log` watched live"*, and
  #283's device note (`OPEN_ITEMS.md:6519-6522`) reads *"the **host logged**
  `Tool terminal … {"output": "[Command interrupted]", "exit_code": 130}`"*.
  **Nobody observed those bytes arriving at the client.**
- **The discard is real and independently verified** —
  `RunsTransport.swift:138` declares `error`, `:180` parses it, `:472` drops it.
  That stands on its own.

So the correct sentence is: *the client parses an `error` field on the runs plane
and discards it; whether the host populates that field on an interrupt is
unverified, and the `exit_code 130` evidence is host-side.* **This matters
because it is the difference between "the fix is plumbing" and "the fix needs a
device turn to prove anything."** 296-A needs neither — which is the good news
this correction surfaces.

### 4.2 296-C's plane is not stated, and it is runs-plane-only

The entry says *"on the runs plane"* about the discard but leaves 296-C's bar
plane-neutral. On the sessions plane — **the default transport**
(`UserSettings.swift:446`) — there is no `error` key to surface:
`parseToolCallEvent` (`SessionsHermesClient.swift:1535-1545`) reads only
`tool_name`/`args`/`preview`, and `:520-522` records that `tool.completed` carries
no result payload at all, *verified against the live host*. **Say so in the entry**
(bar 296-D), or a future reader will read a green 296-C as a claim about the
transport the app actually ships with.

### 4.3 What the entry gets RIGHT and should not be second-guessed

`MessageBubble.swift:566`; `ToolCallEvent` at `StreamingUpdate.swift:7`;
`cancelStreaming` clearing `isActive` on every activity; "there is no interrupted
state"; the fix shape (a distinct state + `cancelStreaming` marking + surfacing
`error` into the chip). All four verified at HEAD. **This entry is in much better
shape than #280's** — the corrections above are refinements, not a rewrite.

---

## 5. Task breakdown

### Task 0 — write the refined bars into the entry (no code)

Add 296-A's rail-state refinement, 296-B's two rows, the 296-C1/C2 split, and
the new 296-D / 296-E to `OPEN_ITEMS.md` #296, plus §4's two corrections. Commit
alone: `docs(#296): bars refined + the interrupted evidence is host-side, and 296-C is runs-plane-only`.

### Task 1 — the model, decode-safely

`Talaria/Models/ToolActivity.swift`:

```swift
/// #296: why this call did NOT complete. `nil` = it completed, or is still
/// running (`isActive`). Non-nil = the user's Stop, or the host's own error
/// text. OPTIONAL on purpose: a non-optional field would make every cached
/// conversation written before this change fail to decode, and the cache
/// loader swallows decode failures (#42) — a silent transcript wipe.
var failure: String?
```

**Never a non-optional `Bool` or a non-optional enum.** Swift's synthesized
`init(from:)` does not apply property defaults; a missing key throws. See §6.

Test — `TalariaTests/ChatStorePersistenceTests.swift`:
`legacyToolActivityJSONStillDecodes()` (296-E) — decode a hand-written blob with
no `failure` key and assert a full conversation with its messages and activities.

**Mandatory RED step:** temporarily declare the field as `var failure: String = ""`
(non-optional), run that one test, and **watch it fail on a decode error**. That
is the proof the optional is load-bearing rather than a style choice. Restore.

### Task 2 — the pure state derivation (the testable seam)

The rail's glyph decision must stop being an inline boolean in view code.
`Talaria/Features/Chat/ToolActivityRail.swift`:

```swift
extension ToolActivityRail {
    /// #296: three states, not two. `interrupted` is what the rail was
    /// missing — a call the user stopped, or one the host reported an error
    /// for, is neither running nor done.
    enum StepState: Equatable { case running, completed, interrupted }

    nonisolated static func state(of activity: ToolActivity) -> StepState
    /// The collapsed chip's glyph: interrupted if ANY step is.
    nonisolated static func summaryState(of activities: [ToolActivity]) -> StepState
}
```

Wire `activityRow` (`:141-184`) and `finishedSummary`'s `Image` (`:87`) through it.
The interrupted glyph should be a non-success mark in `Design.Brand.forge`
(the warning slot; `Design.Colors.danger` reads as an app error, which this is
not — the user asked for it). Owen approves the visual.

Tests — new `TalariaTests/ToolActivityStateTests.swift` (**new file ⇒
`xcodegen generate`**):
- `runningActivityIsRunning()`
- `resolvedActivityWithNoFailureIsCompleted()` (296-B)
- `activityWithFailureIsInterrupted()` (296-A)
- `summaryIsInterruptedWhenAnyStepIs()` — one completed + one interrupted must
  not show a ✓.

### Task 3 — `cancelStreaming` marks rather than resolves

`ChatStore.swift:1362-1364` — for activities that were **still active**, set
`failure` before clearing `isActive`. Activities already inactive (resolved
normally earlier in the turn) must be left alone — that is 296-B's whole point.

```swift
for i in conv.messages[idx].toolActivities.indices
where conv.messages[idx].toolActivities[i].isActive {
    conv.messages[idx].toolActivities[i].failure = "Stopped"
}
for i in conv.messages[idx].toolActivities.indices {
    conv.messages[idx].toolActivities[i].isActive = false
}
```

**Read the `isActive` value BEFORE clearing it.** Collapsing this into one loop
that clears and then tests is the bug this ordering exists to prevent — and it is
the same class of read-before-clear ordering that #295 pinned with a dedicated
test (`4bcf182`, *"cancelStreaming must read before abandonActiveRun clears it"*).
Pin it here the same way.

Tests — extend `AppStoresTests.stopDuringAToolCallKeepsTheActivityRow`
(`:1693-1716`) **in place**; do not write a parallel test:
- keep `count == 1`, `allSatisfy { !$0.isActive }`, `status == .delivered`
  (#294-B must not regress);
- **add** `#expect(reply.toolActivities.first?.failure != nil, "296-A: a tool the user stopped is not a tool that finished")`.

Add a sibling using a script that yields `.toolActivity(started)` then
`.toolActivity(completed)` and THEN is stopped —
`stopAfterAToolCompletedLeavesThatToolCompleted()` (296-B). This needs a new
`StoppableStreamingChatClient.Script` case; add it beside `.toolActivityOnly`
(`AppStoresTests.swift:4408`).

**Mandatory RED step:** revert Task 3's marking loop, run, confirm the new
assertion fails **because `failure` is nil on a stopped-in-flight activity** — not
because of a count mismatch or a compile error. Restore. Record the observed
failure text in the commit message.

### Task 4 — surface the host's error (296-C1)

`SessionsHermesClient+RunsTransport.swift:472-473`:

```swift
case .toolCompleted(let name, let error):
    continuation.yield(.toolActivity(ToolCallEvent(name: name, phase: .completed, detail: error)))
```

…and in `ChatStore.swift:719-727`'s `case .completed:` arm, when the event carries a
detail, write it to the resolving activity's `failure` (not `detail` — `detail`
is the tool's INPUT summary, `ToolActivity.swift:15-17`, and overwriting it would
lose what the call touched).

Tests:
- `RunsFrameParserTests` — `toolCompletedCarriesTheHostError()` on
  `parseRunsFrame` (the parser already does this; the test pins it against a
  future "clean-up" that drops the field again).
- A transport-loop test that the yielded `ToolCallEvent` carries the text.
- A `ChatStore` test that the resolved activity's `failure` is the host string and
  its `detail` is untouched.

**RED step:** restore `case .toolCompleted(let name, _)`, watch the transport test
fail on a nil detail.

### Task 5 — the residual decision, in writing

Decide and RECORD (see §6): a server-transcript reload rebuilds `toolActivities`
with `isActive: false` and no failure (`SessionsHermesClient.swift:1005-1012`), so
an interrupted marker does **not** survive a history refetch. Either carry it
(cost: a merge rule that prefers the local row's `failure`) or accept it and write
the acceptance into #296. **Do not leave it undecided and unwritten.**

### Task 6 — device row + gate + PR

- Add ONE row to `dispatch/DEVICE-PASS-RUNNING-LIST.md` for 296-C2 (runs flag ON,
  force a tool error, read the frames). 296-A/B need no device.
- Gate (§7). PR:
  `fix(#296): a stopped tool stops claiming it finished — interrupted is a third state`.

---

## 6. Traps and interactions

**⚠️ THE ONE THAT CAN LOSE DATA: a non-optional field on `ToolActivity` wipes
cached conversations.** `ToolActivity` is `Codable`
(`Talaria/Models/ToolActivity.swift:9`) and rides the conversation cache through
`UserDefaultsAppPersistenceStore`, whose generic loader uses `try?` and returns
nil on failure — the **#42 silent-wipe** shape, named in that file's own comments
(`:65-69`, *"a divergence would present as the #42 silent-wipe decode failure"*).
Swift does **not** apply property defaults in a synthesized `init(from:)`, so
`var failure: Bool = false` makes every previously written blob throw
`keyNotFound`, and the whole conversation decodes to nil. **Optional, or a
hand-written `init(from:)` with `decodeIfPresent`. Bar 296-E and Task 1's RED step
exist to force this to be proven, not assumed.**

**Do not "fix" the three legitimate `isActive = false` sites.**
`ChatStore.swift:672-677` (prose arrived), `:704-709` (serial tool succession),
`:722-726` (named completion). All three mean *completed*. Only `:1362-1364` means
*stopped*.

**#294 owns the empty-placeholder branch; leave it alone.**
`stoppedPlaceholderHasNothingToShow` (`:1463-1468`) deletes a placeholder with no
content, **no tool activity**, no attachments and no reasoning. A stopped-mid-tool
turn never reaches it (it has an activity). That function's own doc comment
(`:1440-1450`) warns that adding a `Message` field populated outside the
`.finished` case will silently break it — **`ToolActivity.failure` is a field on an
activity, not on `Message`, so it does not trip that hazard.** Verify that claim
rather than trusting this sentence, and if the lane ever adds a `Message`-level
field, re-read those three bullets first.

**#295 just landed on this exact function.** `cancelStreaming` is 100+ lines of
recently-reasoned #291/#294/#295 logic with a documented capture-order
requirement. Merge carefully, and re-read the `armedRecovery` branch at
`:1307-1337` before editing anything above line 1358 — the expiration path
(`hardStopHost: false`) **removes** the placeholder via `armPendingRunRecovery`
rather than settling it, so it never reaches the marking loop. That is correct: a
turn the SYSTEM interrupted is being recovered, not stopped. **Do not mark
activities interrupted on the expiration path** — it would label a turn that is
about to resolve successfully.

**A server-transcript reload erases the marker.**
`SessionsHermesClient.swift:1005-1012` rebuilds activities as
`ToolActivity(label:startedAt:isActive: false, detail:)` — no failure, and the
sender test there is `== .hermes`. So a paired-mode history refetch of an
interrupted turn restores a ✓. **This is a real residual; Task 5 decides it and
writes it down.** Do not let 296-B be read as covering it.

**`useRunsTransport` is default-OFF** (`UserSettings.swift:446`). 296-A ships value
to every user on day one; 296-C only to a Developer-flag user. Say which is which
in the PR body.

**The `detail` field is INPUT, not output** (`ToolActivity.swift:15-17`, the
server's `preview` or a condensed `args` line). The host's error goes in the new
`failure` field. Overwriting `detail` would trade "what the call touched" for "why
it stopped" and lose the more useful of the two.

**`Conversation.dedupingAdoptedEchoes`** (`Conversation.swift:50-60`) keys
empty-content rows on `toolActivities.map(\.label)`. `failure` is not part of the
key and must not become part of it — two rows differing only in failure state are
still the same row.

**`xcodegen generate`** after adding `TalariaTests/ToolActivityStateTests.swift`.
`project.yml:64-74` lists directories, but XcodeGen bakes explicit file references
at generation time, so a new file is invisible until you regenerate.

**Owen approves the glyph.** The rail is HUD-system design surface
(`Design.Brand.forge` vs `Design.Colors.danger` is a semantic choice, not a color
pick). Show him the interrupted chip before the PR.

---

## 7. Close-out

**The gate.** `scripts/mac/lane-gate.sh` — Debug suite (units + XCUITest) **and** a
Release build, positive marker from each. Background it and poll with an `until`
loop; **never arm a Monitor, never wait for a notification.**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
nohup scripts/mac/lane-gate.sh > /tmp/lane-gate-296.log 2>&1 &
until grep -qE 'GATE: (PASS|FAIL)' /tmp/lane-gate-296.log; do :; done
grep -E 'GATE: (PASS|FAIL)' /tmp/lane-gate-296.log
```

`GATE: PASS`, literally, or the lane has not passed (`lane-gate.sh:18-25`:
absence of a failure marker is not success).

**Confirm the test count MOVED** — new files were added. If it did not, a stale
`.xctest` re-ran; purge `<dd>/Build/Intermediates.noindex` and run plain `test`.
Resolve the DerivedData hash from `info.plist`
(`Talaria-gzpowyfsuofejnbsytskngrskzkm` for this checkout; every worktree differs).

**Upstream text this lane's result FALSIFIES — corrected in the same commit:**

| Where | What becomes false | Correction owed |
|---|---|---|
| `OPEN_ITEMS.md` #296 | *"We already have the truth and throw it away"* reads as a client-side wire observation | The `exit_code 130` capture is a HOST LOG line (`DEVICE-PASS-RUNNING-LIST.md:295-297`); the discard at `RunsTransport.swift:472` is separately verified. Split the two claims |
| `OPEN_ITEMS.md` #296 | 296-C stated plane-neutrally | Runs-plane-only; the sessions plane carries no result payload (`SessionsHermesClient.swift:520-522`) and its parser reads no `error` key (`:1535-1545`) |
| `OPEN_ITEMS.md` #296 | *"the rail has only two states"* | True at filing; false after this lane. Mark it as the pre-fix state with the fix's date |
| `OPEN_ITEMS.md` #180 | the umbrella's instance list predates this | Add #296 as a named instance of the same default — it is the umbrella's thesis in one glyph |
| `TalariaTests/AppStoresTests.swift:1710-1713` | #294-B's assertions describe a two-state world | Extended in place, with a comment saying #296 added the third state and #294-B's guarantees still hold |
| `ToolActivityRail.swift:5-7` | doc comment *"**Finished**: shows a collapsed chip … completion status"* | It never showed completion status; now it does. Correct the comment |

**Nothing in `CLAUDE.md` is falsified by this lane.** Its runs-plane paragraph
(`:167-186`) is accurate and this lane adds nothing to the route table.

**The PR.** Branch off `main`. Body: bars MET with per-bar evidence, the literal
`GATE: PASS` line, each RED step and what it failed on, an explicit statement that
**296-C2 is unverified on the wire and is not claimed**, and the Task 5 residual
decision. Owen routes the merge.
