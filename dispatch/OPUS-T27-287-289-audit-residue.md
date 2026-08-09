# OPUS T27 #287+#289 — audit residue: a launch-contract ghost and a dormant field-drop

**Label `OPUS`: this names the tier that EXECUTES the lane, not the tier that wrote this
dispatch.** Bundled as one PR — precedent per the routing note (#291+#294+#293 shipped
bundled). Both items are small, self-contained, non-interacting fixes surfaced by the same
2026-08-07 gpt-sol-xhigh audit sweep; neither touches the other's files in any way that
creates merge risk, and splitting them into two PRs buys nothing.

**Goal:** delete the `pushTokenRegistration` launch-contract ghost (#287) and stop
`MessageAttachment.staged(atLocalPath:)` from silently dropping `anchorOffset` (#289), each
landing with a test that fails for the stated reason before the fix and passes after.

---

## Verified state

Everything below was re-read against the working tree at HEAD (branch `main`, through the
#297 merge — `35c6234`). The OPEN_ITEMS entries for #287 and #289 date from 2026-08-07;
five-plus lanes (#283, #285, #291/294/293, #295, #297) have merged into `ChatStore.swift`
and `AppContainer.swift` since, and several of the entries' own line citations have drifted
as a result. Drift is called out under **Tracker corrections** below rather than silently
fixed in place.

### #287 — VERIFIED

- `Talaria/Stores/AppContainer.swift:234` — `enum LaunchInitStep: CaseIterable, Sendable`.
- `:249` — `case pushTokenRegistration` exists.
- `:259-269` — `touchesNetwork`: the case sits in the network-touching arm (`:266`).
- `:273-276` — `static let criticalPath` (6 local-only steps, no push case).
- `:281-285` — `static let backgroundBootstrap` (8 steps); `pushTokenRegistration` is
  listed at `:283`.
- `:1389-1436` — `private func runBackgroundBootstrap(generation:)`, the function that
  actually executes the background-bootstrap half of launch. **Read top to bottom, it
  calls, in order:** `sessionStore.bootstrap()` (`:1394`), `pairingStore.
  validateRestoredIdentity()` (`:1400`), `hostStore.refresh()` (`:1414`), `inboxStore.
  loadInbox()` (`:1417`), `refreshCommandCatalog(force: true)` (`:1419`),
  conditionally `seedActiveModelFromGateway()` (`:1425`), `sensorUploadService?.
  handleAppDidBecomeActive()` (`:1433`), `updateWidgetData()` (`:1435`). **There is no
  call anywhere in this function, or anywhere else in the file, that performs push-token
  registration.** The claim that `runBackgroundBootstrap` no longer performs the step it
  still declares is CONFIRMED — this is a real ghost, not a stale filing.
- `:1407-1408` — the stale degraded-mode comment: `// ...Relay-backed features (sensor
  upload, inbox, push) stay // degraded until a valid session is restored...`. Confirmed
  present verbatim, and it is the ONLY "push" reference anywhere in `AppContainer.swift`
  besides the enum machinery itself (checked: `:63` and `:390` are unrelated — pre-existing
  design-doc and #144 device-row comments that use the word "push" for a different concept
  and don't need touching).
- `grep -rn "pushTokenRegistration"` across `Talaria/`, `TalariaTests/`, `TalariaUITests/`
  returns **only** the three `AppContainer.swift` lines above. Every other hit is a stale
  copy of `AppContainer.swift` inside an unrelated `.claude/worktrees/*` checkout (other
  branches' snapshots) — not part of this build and not touched by this lane.
- `TalariaTests/AppStoresTests.swift:4680-4705` — `launchCriticalPathIsLocalOnly()` is the
  one test that exercises `LaunchInitStep`. It asserts (a) every `criticalPath` step is
  `!touchesNetwork`, (b) `.drainShareInbox` is on the critical path, (c) `sessionBootstrap`
  precedes `validateRestoredIdentity` in `backgroundBootstrap`, and (d) `criticalPath +
  backgroundBootstrap` is a total, non-overlapping partition of `allCases`. **This test does
  NOT catch the ghost today and will not catch its removal either** — it checks the
  partition is total against `allCases`, and `allCases` shrinks by exactly one case the
  moment the fix removes it, so the assertion is trivially true both before and after.
  Nothing in the existing suite literal-pins the *contents* of `backgroundBootstrap`. A new
  test is required to make this a real regression pin (see Task breakdown).
- No `xcodegen generate` is needed — the fix deletes an enum case and edits a comment; no
  Swift file is added or removed.

### #289 — VERIFIED

- `Talaria/Models/Message.swift:4-36` — `struct MessageAttachment` has exactly 10 stored
  properties: `id, kind, fileName, mimeType, thumbnailBase64, localStoragePath,
  voiceMemoAudioPath, remotePath, remoteProfileID, anchorOffset`. `anchorOffset` is declared
  `var Int?` at `:36`.
- `:38-60` — the memberwise `init` takes all 10, `anchorOffset` defaulting to `nil` and
  assigned at `:59`.
- `:355-366` — `static func fetchableAgentFile(name:remotePath:profileID:)`, the factory
  the test uses, also never sets `anchorOffset` (defaults `nil`) — consistent with the
  claimed invariant that a Tier-2 chip starts life with a nil anchor.
- `:371-383` — `func staged(atLocalPath:) -> MessageAttachment`. **Confirmed: rebuilds with
  9 of the 10 properties, `anchorOffset` is not named, so it silently resets to the
  init's default `nil`.** This is the defect, exactly as filed, at the exact line range
  the entry cites (`:371-383`).
- Non-nil `anchorOffset` assignment, re-traced against `ChatStore.swift` at HEAD (line
  numbers have moved — see Tracker corrections): exactly **two** sites touch it non-nil-ly,
  not three:
  - `ChatStore.swift:751` — inside the SSE event handler's `.artifactProduced` case
    (`:737-754`). Comment at `:738-740` confirms this only fires when "the agent wrote a
    file and its bytes are already staged" — i.e. Tier 1, inline content, never a Tier-2
    fetchable.
  - `ChatStore.swift:2810` — inside `nonisolated static func mergeAttachments(...)`
    (`:2775-2813`), `anchorOffset: remote.anchorOffset ?? match.anchorOffset` — a
    carry-forward of whatever the local copy already had, not a fresh mint. Comment at
    `:2806-2809` confirms "the server never echoes one," so `remote.anchorOffset` is always
    nil in practice and this line only ever propagates a value that itself originated from
    the `:751` Tier-1 site (or stays nil).
  - A third grep hit, `ChatStore.swift:715`, is a same-named but **unrelated** property —
    `ToolActivity.anchorOffset` (a different struct, `Talaria/Models/ToolActivity.swift`),
    not `MessageAttachment.anchorOffset`. A plain `grep anchorOffset` conflates the two;
    the executor should `grep "MessageAttachment"` or check the receiver type before
    trusting a hit.
  - **The invariant holds under re-verification:** because `staged(atLocalPath:)` is only
    ever called (`ChatStore.swift:1501`, inside `fetchAgentFile`, guarded by
    `attachment.localStoragePath == nil` — a not-yet-downloaded Tier-2 chip) on an
    attachment whose `anchorOffset` can only have come from the two sites above, and both
    trace back to Tier 1, a Tier-2 chip's `anchorOffset` is always nil when `staged()` runs
    today. **NOT a live bug today** is confirmed, independently of the exact site count.
- `TalariaTests/AgentFileFetchTests.swift:10` — `struct AgentFileFetchTests`.
  `:49-60` — `func stagedCopyKeepsIdentityAndFetchPointer()`, exactly the line range the
  entry cites. It builds an attachment via `fetchableAgentFile`, calls `.staged(...)`, and
  asserts 6 of the struct's 10 properties (`id, localStoragePath, remotePath,
  remoteProfileID, fileName, mimeType`). It omits `kind`, `thumbnailBase64`,
  `voiceMemoAudioPath`, and `anchorOffset`. Of those four, only `anchorOffset` is actually
  dropped by `staged()` today — the other three ARE carried correctly by the current
  implementation, they're just untested. Bar 289-B's own wording ("asserts the full
  property set, so the **next** field added ... fails loudly") calls for closing the test
  gap generally, not only for `anchorOffset` — see the recommended test design below.
- The entry's second half — `mergeConversationMetadata`'s `Conversation(...)` rebuild,
  filed as FRAGILE-BUT-COMPLETE, deliberately not a defect. Re-verified: the function is
  `ChatStore.swift:2578-2711` (private, not `nonisolated static` like `mergeAttachments`);
  the rebuild itself is at `:2696-2703`, gated by `if refreshedConversation.id !=
  localConversation.id`. It carries exactly **6 of 6** of `Conversation`'s stored
  properties (`Conversation.swift:9-17`: `id, title, messages, lastActivity, latestUsage,
  generatedPreview` — verified against the struct declaration and its own memberwise init
  at `:19-33`). **FRAGILE-BUT-COMPLETE is confirmed current: nothing is dropped today.**
  Unlike `mergeAttachments` (which carries a "if you add a field, add it here" comment at
  `ChatStore.swift:2765-2771`, added by the #276 fix), this rebuild site has **no such
  guard comment**. See the recommendation under Pre-registered bars / Task breakdown.
- No `xcodegen generate` is needed — the fix adds one named argument to an existing
  function and extends an existing test; no Swift file is added or removed.

---

## The defect

**#287 — contract fiction.** `LaunchInitStep` exists so a test can machine-check "nothing
before `isInitialized = true` touches the network" and "the background half runs in this
exact order" (see the doc comment at `AppContainer.swift:227-233`, which itself says
`initialize()` and `runBackgroundBootstrap(generation:)` "mirror these lists step for
step — a new init step belongs in exactly one list"). `pushTokenRegistration` is declared,
partitioned into `backgroundBootstrap`, and marked network-touching — but
`runBackgroundBootstrap` does not perform it (push registration was deleted wholesale by
#238's notification removal, 2026-08-03). The enum's whole reason to exist is to be an
honest machine-checkable mirror of what launch actually does; this case makes it lie about
one thing. Nothing runtime-breaks — the case is inert — but the stale comment at `:1407-
1408` actively misdescribes degraded-mode behavior to the next reader, and the test suite
has a blind spot exactly where it should be strictest (a launch-order regression could add
a NEW ghost the same way and nothing would catch it, because nothing pins list contents).

**#289 — silent field drop under the #276 shape.** `staged(atLocalPath:)` is a
field-by-field reconstruction of an immutable-by-convention value (`MessageAttachment`
is a `struct` with `let` fields except `anchorOffset`, which is `var`). Because
`anchorOffset` is `Optional` with a default of `nil` in the initializer, omitting it from
the rebuild compiles clean and reads as "no anchor," indistinguishable from "correctly
still nil." The type system provides zero protection — this is verbatim the #276 lesson,
which the sibling function `mergeAttachments` already shipped and fixed once (comment at
`ChatStore.swift:2765-2771`, `git blame` traces to the `fad619a` commit,
`fix(#275,#276,#278,#274)`). It is not live today only because every current call site
happens to hand `staged()` an attachment whose `anchorOffset` is nil — an invariant that is
true by construction of the current SSE/merge flow, not by anything the function itself
enforces or the test verifies.

---

## ⚠️ Tracker corrections

Corrections go upstream (THE CLOSE-OUT RULE) — these are for whoever files the close-out
commit to fold back into the OPEN_ITEMS entries, not something this dispatch edits.

1. **#289's `ChatStore.swift` line citations have drifted and one count is off.** The entry
   says the non-nil `anchorOffset` assignment sites were "traced (`ChatStore.swift:690,
   :762, :2439`)" and that `mergeAttachments` is at `:2404-2442` with its fix comment "still
   at `ChatStore.swift:2394-2400`." **None of those four line numbers match HEAD.**
   Re-verified current locations: the Tier-1 assignment is at `:751` (inside the
   `.artifactProduced` handler, `:737-754`), `mergeAttachments` is at `:2775-2813` with its
   fix-comment block at `:2762-2774`, and the carry-forward assignment is at `:2810`. This
   is drift from the five-plus lanes that have touched `ChatStore.swift` since 2026-08-07
   filing (`#283`, `#285`, the #291/294/293 bundle, `#295`), not a wrong claim at filing
   time — but a further point: **re-verification finds exactly 2 sites that ever write a
   non-nil `anchorOffset`, not 3.** The entry's "3" may have counted a read (`chip.
   anchorOffset.map { ... }` at what is now `:817`, which only reads and forwards an
   existing value into a dictionary — not a new assignment) as a site, or may reflect code
   shape that has since consolidated. Either way, the invariant the entry actually depends
   on ("a Tier-2 chip's `anchorOffset` is always nil when `staged()` runs") is unaffected
   and re-confirmed independently above — this correction is about the citation, not the
   verdict.
2. **#289's `mergeConversationMetadata` location has drifted.** The entry cites
   `ChatStore.swift:2325-2332` for the `Conversation(...)` rebuild; the function containing
   it is now `:2578-2711` and the rebuild itself is at `:2696-2703`. Verdict
   (FRAGILE-BUT-COMPLETE, 6-of-6 properties carried) is unchanged.
3. **Not a correction, a confirmation with a caveat:** #287's filing text already says its
   static shape was "VERIFIED same day" at `AppContainer.swift:249/:266/:283`, and those
   three line numbers **still match exactly** at HEAD — that part of the entry has not
   drifted at all. Only the dynamic claim ("`runBackgroundBootstrap` no longer performs
   it") needed a fresh trace, which this dispatch did (see Verified state above) — it holds.

---

## Pre-registered bars

**These must be written into the OPEN_ITEMS #287 and #289 entries before any code is
touched.** This dispatch does not edit `OPEN_ITEMS.md`.

### 287-A — no live launch-contract entry claims push registration exists

*As filed, unchanged.* Evidence: `grep -n "push" Talaria/Stores/AppContainer.swift`
returns zero hits inside the `LaunchInitStep` block or the degraded-mode comment (the two
unrelated hits at `:63`/`:390` pre-date this case and are out of scope — leave them). Text
review, not a device requirement. Settled by code inspection + the diff itself; no
automated test can grep its own source file for a removed word in any principled way, so
this bar is a review checkpoint, not a CI assertion.

### 287-B — `backgroundBootstrap` mirrors actual execution order

*As filed, refined with a concrete mechanism because the existing test doesn't pin list
contents (see Verified state).* Evidence: a **new** literal-pin test asserting
`LaunchInitStep.backgroundBootstrap == [.sessionBootstrap, .validateRestoredIdentity,
.hostRefresh, .inboxLoad, .commandCatalogRefresh, .gatewayModelSeed,
.sensorForegroundRefresh]` (7 steps, `pushTokenRegistration` gone) in
`TalariaTests/AppStoresTests.swift`. No device — runs in the Debug unit-test suite.

### 287-C — launch partition tests green

*As filed, unchanged.* Evidence: `launchCriticalPathIsLocalOnly()` plus the new 287-B test
both green, inside `scripts/mac/lane-gate.sh`'s Debug suite. No device.

### 289-A — `staged(atLocalPath:)` preserves every property of its input including `anchorOffset`

*As filed, unchanged in substance.* Evidence: the extended
`stagedCopyKeepsIdentityAndFetchPointer` test (see Task breakdown for the recommended
design — a whole-struct equality check, not a longer field list) passes. No device — unit
test.

### 289-B — its test asserts the full property set, so the next field added to `MessageAttachment` fails loudly here instead of silently defaulting

*As filed, refined.* The entry's literal ask ("asserts the full property set") is best met
by comparing the WHOLE staged struct against an expected value built by copying the input
and changing only `localStoragePath` — `MessageAttachment` already conforms to `Hashable`
(and therefore synthesized `Equatable`) with every stored property Hashable, so this
compiles today with no new conformance work. This is stronger than a field-by-field
`#expect` list: a future field added to the struct is caught automatically (the copy
carries it, the rebuild won't, equality fails) rather than only when someone remembers to
add a new line to the test. If the executor prefers the literal field-by-field style
instead (matching the existing test's current idiom), that also satisfies the bar — but
must include `anchorOffset` explicitly, seeded non-nil on the input, not left at its
always-nil-today default (a nil-vs-nil comparison proves nothing — this is precisely the
"tests written after a defect" trap: the property must be given a value the current bug
would visibly lose). No device.

### Not a bar, a recommendation on the entry's second half — `mergeConversationMetadata`'s `Conversation(...)` rebuild

**Leave the mechanism as-is; add a one-line guard comment, nothing else.** The rebuild
(`ChatStore.swift:2696-2703`) is verified complete today (6-of-6 properties) and gating it
behind an assertion or refactoring it into a copy-and-mutate form is not warranted — it
would touch working code with no bug to fix, purely to guard against a hypothetical future
`Conversation` field. That said, `mergeAttachments` already carries a "if you add a field,
add it here" comment (`ChatStore.swift:2765-2771`) for exactly this shape, added by the
#276 fix — this rebuild site has no equivalent. Copying that one comment onto
`mergeConversationMetadata`'s rebuild (above `:2696`) costs nothing, changes no behavior,
and directly answers the risk the filer wrote down ("the next instance of this shape to
bite if `Conversation` grows a 7th property"). Do this in the same PR since it's a one-line
addition already scoped by the audit that found it; do not expand it into a refactor.

---

## Task breakdown

Work on a fresh branch off `main` at HEAD (`35c6234` or later) — e.g. `t27-287-289-audit-residue`.

**1. #287 — RED.** In `TalariaTests/AppStoresTests.swift`, inside `struct AppStoresTests`
   near `launchCriticalPathIsLocalOnly()` (`:4680-4705`), add a new test:
   ```swift
   @Test @MainActor
   func backgroundBootstrapHasNoGhostSteps() {
       // #287: LaunchInitStep.backgroundBootstrap must literal-match what
       // runBackgroundBootstrap(generation:) actually executes — a case can sit
       // in this list forever without anything catching that it's never run.
       #expect(AppContainer.LaunchInitStep.backgroundBootstrap == [
           .sessionBootstrap, .validateRestoredIdentity, .hostRefresh, .inboxLoad,
           .commandCatalogRefresh, .gatewayModelSeed, .sensorForegroundRefresh,
       ])
   }
   ```
   Run it (`xcodebuild test` targeting `AppStoresTests/backgroundBootstrapHasNoGhostSteps`,
   or the whole suite) against the current tree — **confirm it FAILS**, and confirm the
   failure message shows the actual array still containing `.pushTokenRegistration` at
   index 6. That is "restore the bug and watch RED for the stated reason" — the bug is
   already at HEAD, so this step is just proving the new test actually exercises it before
   touching production code.

**2. #287 — GREEN.** In `Talaria/Stores/AppContainer.swift`:
   - Delete `case pushTokenRegistration` (`:249`).
   - Remove `.pushTokenRegistration` from the `touchesNetwork` network-touching switch arm
     (`:266`).
   - Remove `.pushTokenRegistration` from `backgroundBootstrap` (`:283`).
   - Edit the stale comment at `:1407-1408` — delete "push" from "Relay-backed features
     (sensor upload, inbox, push) stay degraded..." (becomes "sensor upload, inbox").
   Re-run `backgroundBootstrapHasNoGhostSteps` and `launchCriticalPathIsLocalOnly` —
   **confirm both GREEN.** No `xcodegen generate` needed (no file added/removed).

**3. #289 — RED.** In `TalariaTests/AgentFileFetchTests.swift`, replace
   `stagedCopyKeepsIdentityAndFetchPointer()` (`:49-60`) with:
   ```swift
   @Test func stagedCopyKeepsIdentityAndFetchPointer() {
       var attachment = MessageAttachment.fetchableAgentFile(
           name: "report.pdf", remotePath: "reports/report.pdf", profileID: UUID()
       )
       // #289: seed a non-nil anchorOffset so a dropped field is actually visible —
       // every real call site hands staged() a nil anchor today, so a nil-vs-nil
       // comparison here would prove nothing about the bug this test exists to catch.
       attachment.anchorOffset = 42

       let staged = attachment.staged(atLocalPath: "/tmp/staged/report.pdf")

       // Whole-struct comparison, not a field list: the ONLY thing staging is
       // allowed to change is localStoragePath. This makes the next field added
       // to MessageAttachment fail here by construction, not by someone
       // remembering to extend a field-by-field list (bar 289-B).
       var expected = attachment
       expected.localStoragePath = "/tmp/staged/report.pdf"
       #expect(staged == expected)
   }
   ```
   Run it against the current tree — **confirm it FAILS**, and confirm the failure is
   specifically an `anchorOffset` mismatch (`staged.anchorOffset == nil`,
   `expected.anchorOffset == 42`) — not, say, a `localStoragePath` mismatch from a typo.
   This is the "watch RED for the stated reason" checkpoint for #289.

**4. #289 — GREEN.** In `Talaria/Models/Message.swift`, add `anchorOffset: anchorOffset` to
   the rebuild in `staged(atLocalPath:)` (`:371-383`). Re-run the test — **confirm GREEN.**
   No `xcodegen generate` needed.

**5. #289 — the recommended comment-only addition.** In `Talaria/Stores/ChatStore.swift`,
   above the `Conversation(...)` rebuild in `mergeConversationMetadata` (`:2696`), add a
   comment mirroring `mergeAttachments`' guard (`:2765-2771`): something like "If you add a
   field to `Conversation`, add it here too — see #276/#289." No behavior change, no test
   required (nothing to assert about a comment) — just confirm the build still compiles
   and no test's line-number-sensitive assertions moved unexpectedly.

**6. Full local suite.** Run the whole `TalariaTests` target once (not just the two new/
   changed tests) to catch any incidental breakage from the enum-case deletion (e.g. an
   exhaustive `switch` over `LaunchInitStep` elsewhere that the compiler would already have
   caught, but confirm no test hardcodes `LaunchInitStep.allCases.count` — checked, none
   does; `RouterIntentTests.swift:80`, `DeviceToolBeltTests.swift:1078`, and
   `RevokeRowStateTests.swift:99` count *different* enums entirely).

**7. Gate.** `scripts/mac/lane-gate.sh` — Debug suite (units + XCUITest) + Release build.
   It takes minutes; **background it and poll the log with an `until` loop, never a
   Monitor call and never a wait-for-notification**:
   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer \
     nohup scripts/mac/lane-gate.sh > /tmp/t27-287-289-gate.log 2>&1 &
   until grep -q "GATE: PASS\|GATE: FAIL" /tmp/t27-287-289-gate.log 2>/dev/null; do sleep 15; done
   tail -60 /tmp/t27-287-289-gate.log
   ```
   Require the literal `GATE: PASS` marker — nothing short of it counts, per the gate's own
   documented history of false positives (`scripts/mac/lane-gate.sh` header, and the
   `xcodebuild-beta4-stale-incrementals` memory note: stale incrementals, a no-op-satisfied
   marker, and an all-Debug blind spot have each separately produced a confident wrong
   PASS on this project before).

---

## Traps and interactions

- **Do not confuse `ToolActivity.anchorOffset` with `MessageAttachment.anchorOffset`** when
  grepping — they're different structs in different files that happen to share a field
  name (`ChatStore.swift:715` is the `ToolActivity` one; leave it alone).
- **The `:817`/`:822`/`:823` region of `ChatStore.swift`** (inside the `.finished` handler,
  transferring a streamed chip's anchor onto its final-message twin) reads `anchorOffset`
  but does not independently mint a value — do not "fix" it as a third assignment site; it
  is a read-and-forward, already covered by the `:751` origin.
- **`backgroundBootstrapHasNoGhostSteps` is a literal-order pin** — the next lane that adds
  a REAL background-bootstrap step must update this array in the same commit, or the new
  test fails for the RIGHT reason (a step present in the list that this test doesn't know
  about — which is exactly what should happen; don't loosen the assertion to `Set` equality
  to make that friction go away, order already matters per `:3/:46`'s ordering rule for
  `sessionBootstrap`/`validateRestoredIdentity`).
- **`MessageAttachment == ` synthesis depends on every stored property staying Hashable.**
  If a future field is a non-Hashable type, the compiler will refuse to synthesize
  `Equatable`/`Hashable` for the whole struct — a loud compile error, not a silent gap, so
  this is a feature of the chosen test design, not a risk to flag defensively.
- **#287 and #289 touch disjoint files** (`AppContainer.swift`+`AppStoresTests.swift` vs.
  `Message.swift`+`AgentFileFetchTests.swift`, plus the one-line `ChatStore.swift` comment
  for #289's recommendation) — there is no merge-order dependency between the two halves of
  this bundle; they can be done in either order or interleaved.
- **Neither item needs a device.** Both are pure unit-test-level static/struct assertions;
  the gate's Debug suite (simulator) and Release build are sufficient. Do not schedule
  device time for this lane.

---

## Close-out

**The gate:** `scripts/mac/lane-gate.sh` must print the literal `GATE: PASS` marker
(Debug suite green with MOVED test counts on both new tests, plus a clean Release build)
before opening the PR.

**What this result falsifies upstream, per THE CLOSE-OUT RULE (corrections happen in the
same commit, not left for later):**
- **#287's OPEN_ITEMS entry** — once the fix lands, the "STATIC SHAPE VERIFIED" preamble
  should gain a dated line noting the fix landed and the ghost is gone (mirroring how #286
  and #288 already carry dated `>` update blocks in this file). The bars stated in the
  entry (287-A/B/C) are met as refined above — record 287-B's refinement (the new
  literal-pin test) in the close-out note, since the entry as filed didn't specify a
  mechanism and the existing suite turned out not to already cover it.
- **#289's OPEN_ITEMS entry** — same treatment: dated close-out line, bars 289-A/B met via
  the whole-struct-equality test design (record the design choice, since it differs from
  "just add an `anchorOffset` expect line" that a literal reading of the entry might
  suggest). The `mergeConversationMetadata` FRAGILE-BUT-COMPLETE finding stays recorded
  verbatim as a non-defect — note only that a guard comment was added alongside, not that
  anything was fixed there.
- **This dispatch's own Tracker corrections section** (line-number drift on both items,
  the 2-vs-3-site recount for #289) is itself upstream correction material — fold it into
  the entries' close-out notes rather than treating this dispatch file as the permanent
  record. Dispatches are ephemeral routing documents; OPEN_ITEMS is where corrections live.

**The PR:** one PR, title referencing both `#287` and `#289` (matching the `#291,#294,#293`
bundling precedent), body listing the four bars and the gate's `GATE: PASS` output.
