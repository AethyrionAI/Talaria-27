# Talaria-27 Recent Work Audit — Claude Code Handoff

**Audit date:** 2026-08-07  
**Repository:** `AethyrionAI/Talaria-27`  
**Requested by:** Owen  
**Purpose:** Independent review of work landed since the last substantive audit, with actionable reproduction/fix instructions for Claude Code.

> **Claude: read `CLAUDE.md` first. It is the standing source of truth for repo rules.**
>
> This document is an audit handoff, **not authorization to blindly patch every observation**. Reproduce each new candidate before fixing it, search both `OPEN_ITEMS.md` and `OPEN_ITEMS-ARCHIVE.md` for duplicates, pre-register bars per repo convention, and preserve the project's verification-first discipline.

---

## 0. Audit boundary and confidence

### Previous clean anchor

The repo itself records the last independent work audit as:

- **2026-08-02**
- PRs **#218–#238**
- commit range **`70c8536..d869af1`**
- fresh-clone lane gate: **PASS**
- **1497 + 8** tests
- **Release green**
- targeted simulator and live HTTP probes re-run

That is the clean baseline for this review.

### Review window

Treat this audit as covering work landed from approximately:

**2026-08-03 through 2026-08-07**

At the time of this static review, the public `main` history observed an Aug-7 tip around:

**`d2e6421`**

Do **not** assume that is still HEAD when you begin. Fetch first and include any intervening commits in your own reconciliation.

### Audit method / limitation

This review was performed by reading:

- current public `main`
- recent commit history
- `CLAUDE.md`
- `OPEN_ITEMS.md`
- relevant Swift production code
- relevant tests
- Phase 3 / plugin work already reflected in repo state

I did **not** execute Xcode, the lane gate, or device tests from this environment.

Therefore:

- findings below are **static-code audit candidates**
- Candidate 1 is backed by a particularly strong control-flow mechanism
- Claude Code should produce the RED witness before claiming runtime impact
- if a proposed failure cannot be reproduced, **document that honestly rather than forcing a fix**

---

# 1. Executive verdict

The recent work is generally strong.

There is **no evidence here supporting a broad revert** or architectural retreat.

The strongest positive signal is the development process itself:

- several recent fixes use explicit RED → GREEN sequencing
- device-only failures have been separated from simulator claims rather than blurred together
- transcript/reconciliation defects have generally been filed rather than hidden
- the new Phase 3 run-plane thinking is more explicit about cancellation, steering, and authority than the older chat transport
- `AppContainer` already contains a good generation/supersession pattern for background bootstrap that can be reused elsewhere

The biggest current risk is not “bad recent work” broadly.

It is that **profile switching and the new Talaria platform transport cross an async ownership boundary without one immutable per-turn profile context**.

## New audit candidates

| ID | Severity | Area | Candidate | Confidence |
|---|---|---|---|---|
| **A1** | **P1 / High** | Profile switching + Talaria platform transport | Active profile mutation is not an atomic transport boundary; in-flight work can observe mixed profile context and rapid switches can overlap | **High static confidence; reproduce before filing/fix** |
| **A2** | **P2 / Medium** | Talaria platform settlement | Failed ACK / `query_result` posts can still cause the drain to report `.delivered` | **High static confidence** |
| **A3** | **P3 / Low-Medium** | Launch architecture contract | `LaunchInitStep` still advertises deleted push registration even though bootstrap no longer executes it | **Very high static confidence** |

---

# 2. A1 — P1 HIGH
# Profile activation is not an atomic transport boundary

## Summary

The new Talaria platform link correctly tries to stop its drain when the active backend profile changes.

However, the implementation currently has a sequencing mismatch:

1. `BackendProfilesStore.setActiveProfile(_:)` mutates the active profile **immediately**.
2. It then launches the async `onActiveProfileChanged` callback in an unstructured `Task`.
3. `AppContainer.handleActiveProfileChanged(to:)` calls `talariaPlatformLink.stop()`.
4. But by the time that callback begins, the closures inside `TalariaPlatformLink` already resolve the **new active profile**.
5. An in-flight drain can continue through suspended `await`s and perform side effects before the polling loop reaches its next `isRunning` check.
6. Several values inside one drain/pair operation are re-resolved dynamically at different times rather than captured as one immutable profile/host context.

This means the comment in `AppContainer` saying the drain is parked **“before the scope moves”** cannot literally be true with the current call order.

This is a correctness boundary and potentially a privacy boundary when multiple Hermes hosts are configured.

Do **not** treat this as an exploit finding; treat it as cross-profile state/credential isolation.

---

## Primary evidence

### A. `BackendProfilesStore` moves the profile first

File:

`Talaria/Stores/BackendProfilesStore.swift`

Current shape of `setActiveProfile(_:)`:

```swift
func setActiveProfile(_ id: UUID) -> Bool {
    guard let target = state.profile(id: id), state.activeProfile?.id != id else { return false }
    var updated = state
    updated.activeProfileID = id
    state = updated
    profilesLog.notice("active profile → '\(target.name, privacy: .public)'")
    Task { await onActiveProfileChanged?(target) }
    return true
}
```

The critical ordering is:

```text
state.activeProfileID = new profile
            ↓
state published
            ↓
async Task scheduled
            ↓
AppContainer callback eventually begins
            ↓
platform link stop()
```

So an after-change callback cannot stop the transport before `activeProfile` moves.

---

### B. `TalariaPlatformLink` deliberately reads live profile state

File:

`Talaria/Services/Live/TalariaPlatformLink.swift`

The link receives dynamic closures for:

- `gatewayBaseURL`
- `apiKey`
- `credentialScopeID`

`AppContainer` wires those closures to `profilesStore.activeProfile`.

That makes sense for the **next** turn after a switch.

The problem is that the same dynamic values are also re-read **during** an existing async turn.

Example:

```swift
private var tokenKey: String {
    BackendProfileScopedKeys.talariaDeviceToken(credentialScopeID())
}

private var deviceIDKey: String {
    BackendProfileScopedKeys.talariaDeviceID(credentialScopeID())
}
```

`ensurePaired()` freezes one key but not the other:

```swift
let tokenKey = tokenKey

if await secureStore.retrieve(key: tokenKey) != nil,
   await secureStore.retrieve(key: deviceIDKey) != nil {
    return true
}
```

After the first `await`, `deviceIDKey` can resolve against a different active profile.

Likewise, `pair(tokenKey:)` receives a captured token key, but after network suspension it stores:

```swift
await secureStore.store(key: tokenKey, value: paired.deviceToken)
await secureStore.store(key: deviceIDKey, value: paired.deviceID)
```

The second key is live/dynamic.

That creates a possible split credential pair.

---

### C. `drain()` mixes captured and live context

Current shape:

```swift
let tokenKey = tokenKey

guard await ensurePaired() else { ... }

guard let token = await secureStore.retrieve(key: tokenKey),
      let deviceID = await secureStore.retrieve(key: deviceIDKey)
else { ... }

...

guard let (status, data) = await post(body, bearer: token) else { ... }
```

`post()` calls `endpointURL()` at invocation time.

`endpointURL()` reads `gatewayBaseURL()` dynamically.

Therefore a single logical drain can potentially combine:

```text
captured token key from profile A
+
live device ID key from profile B
+
live endpoint from profile B
```

depending on where the active profile changes relative to suspension points.

The exact observed failure will depend on timing and stored credential state.

---

### D. `stop()` does not invalidate side effects already inside `drain()`

Current comment:

```swift
/// Stops the loop. Cancels the in-flight sleep (if any) promptly; an
/// in-flight network call finishes naturally and its result is discarded
/// by the `isRunning` check on the loop's next iteration.
```

Current implementation:

```swift
func stop() {
    isRunning = false
    loopTask?.cancel()
    loopTask = nil
}
```

The loop checks `isRunning` only around the **next iteration**.

But the current `drain()` performs side effects before returning to that loop:

```swift
onItemsReceived(drained.items)
await ack(...)
await answer(...)
```

It can also store/delete pairing credentials during repair.

Therefore “discarded on the next loop iteration” does not protect those current-turn effects.

Cancellation is useful, but cancellation without an explicit generation/currentness guard is not a state-write barrier.

---

### E. Rapid profile switches are not serialized

`BackendProfilesStore` does:

```swift
Task { await onActiveProfileChanged?(target) }
```

for every switch.

That means:

```text
A → B
```

can start a B rebind task.

Before B's awaited Keychain/network work finishes:

```text
B → C
```

can start a C rebind task.

There is no obvious `profileSwitchGeneration`, serialized predecessor chain, or “last switch wins” guard around `handleActiveProfileChanged(to:)`.

That is especially concerning because the handler writes shared global/in-memory state such as:

```swift
hermesAPIKey = gatewayKey
chatAPIKeyBox?.value = gatewayKey
lastActivatedProfile = profile
```

and resets/reloads multiple stores around suspension points.

A late B completion after C has become active must not be allowed to win.

---

## Why this deserves P1

This is not primarily about a harmless extra 401.

The desired invariant is:

> **A logical operation belongs to exactly one backend profile/host, and after a newer profile activation supersedes it, old-profile asynchronous completion must not mutate current-profile state.**

The current implementation does not obviously enforce that invariant.

Possible manifestations include:

- split token/device-ID pairing slots
- stale profile credentials written after a newer activation
- requests using credentials/context from different profiles
- stale drained items landing after a profile switch
- stale phone queries answered after the switch
- B→C rapid switch ending with part of the app rebound to B
- unnecessary re-pairs and confusing host-switch state
- intermittent bugs that disappear when switching hosts slowly

Again: **reproduce before asserting which of those actually occurs.**

---

# 3. A1 required RED tests

Do not begin with a refactor.

Begin with deterministic suspension points.

## RED 1 — Pairing uses one credential scope for the whole turn

Create a test seam where:

1. active scope begins as **A**
2. `ensurePaired()` starts
3. suspend the first Keychain/network step
4. change live active scope to **B**
5. resume
6. inspect all keys read/written and the endpoint hit

### Required invariant

A single pair/drain turn must never produce:

```text
token key A + device ID key B
```

or:

```text
credential A + endpoint B
```

Pick one policy:

- **snapshot A and complete as A**, or
- **invalidate A and perform no settlement/state write**

Either policy is defensible.

A mixed turn is not.

---

## RED 2 — Stop/invalidate prevents stale drain settlement

Arrange:

1. profile A drain starts
2. server response is delayed
3. call transport stop/invalidate because profile changes
4. release the response
5. assert the superseded turn does **not**:
   - deliver inbox items
   - ACK them
   - answer phone queries
   - delete/store active pairing state
   - affect the next host's failure/backoff state

The current `stop()` test appears to validate the boolean/lifecycle shape, not stale side-effect suppression.

This test should target the actual invariant.

---

## RED 3 — Rapid A→B→C profile switch is last-writer-wins

Use delayed secure-store reads or another deterministic hook.

Sequence:

```text
A active
setActiveProfile(B)
B handler reaches an await and pauses
setActiveProfile(C)
C handler proceeds
B resumes late
```

Final assertions should prove:

- active profile = C
- `hermesAPIKey` = C's key
- `chatAPIKeyBox` = C's key
- session/pairing/profile-scoped stores point at C
- stale B handler cannot reset or overwrite C state
- platform link runs against C only
- any switch notice corresponds to the current/superseding state, not a stale completion

This is the most important AppContainer-level regression.

---

# 4. A1 likely fix shape

Do not cargo-cult this exact implementation. Preserve the invariant, not the wording.

There are two places to improve.

## Part A — Serialize/supersede profile activation

`AppContainer` already has a proven pattern nearby:

```text
bootstrapGeneration
+
cancel old Task
+
retain predecessor
+
wait for old task to unwind
+
guard every state write with generation/currentness
```

See:

- `startBackgroundBootstrap()`
- `cancelBackgroundBootstrap()`
- `runBackgroundBootstrap(generation:)`

A profile switch deserves a comparable ownership model.

Possible shape:

```swift
private var profileSwitchGeneration = 0
private var profileSwitchTask: Task<Void, Never>?
private var supersededProfileSwitchDrain: Task<Void, Never>?
```

Every async state write in the switch path should be guarded by something equivalent to:

```swift
guard generation == profileSwitchGeneration,
      profilesStore.activeProfileID == profile.id,
      !Task.isCancelled
else { return }
```

Do not allow late B work to land after C.

---

## Part B — Give each platform-link turn an immutable context

Rather than repeatedly calling live profile closures across `await`s, consider an immutable per-turn snapshot such as:

```swift
struct TalariaPlatformLinkContext {
    let profileID: UUID?
    let gatewayBaseURL: String
    let credentialScopeID: UUID?
    let gatewayAPIKey: String
    let tokenKey: String
    let deviceIDKey: String
    let generation: Int
}
```

Exact fields are negotiable.

The invariant is not.

Within one pair/drain/ack/query-result transaction:

- endpoint
- credential scope
- token slot
- device ID slot
- profile identity

must all refer to the same context.

Before any side effect after an `await`, verify the turn is still current.

That includes:

- `secureStore.store`
- `secureStore.delete`
- `onItemsReceived`
- ACK
- `query_result`

---

## Part C — Consider a “will change” transport invalidation hook

Because `BackendProfilesStore.setActiveProfile(_:)` changes state before scheduling `onActiveProfileChanged`, an after-change callback cannot literally satisfy:

> stop before the scope moves

Possible options:

1. change the activation API so AppContainer coordinates the transition
2. add a synchronous pre-change invalidation hook
3. make the transport generation/context model strong enough that order no longer matters

Option 3 may be the cleanest if transport turns are genuinely snapshot-based and invalidatable.

But do not leave a source comment claiming an ordering guarantee the code does not provide.

---

## A1 acceptance bars

Pre-register these in the tracker before running if the repo's lane discipline calls for a new item.

Minimum:

- [ ] one transport turn cannot mix profile A/B keys or endpoints
- [ ] superseded drain completion cannot deliver/ACK/answer after invalidation
- [ ] rapid A→B→C switch is deterministically last-writer-wins
- [ ] stale B completion cannot overwrite C credentials or scoped stores
- [ ] existing platform-link pair/repair tests stay green
- [ ] existing profile-switch tests stay green
- [ ] full Debug suite green
- [ ] Release build green
- [ ] `scripts/mac/lane-gate.sh` PASS
- [ ] device bar added only if the fix depends on behavior simulator tests cannot establish

If the RED cannot be produced after a good deterministic harness, record the falsification and do not force a patch.

---

# 5. A2 — P2 MEDIUM
# ACK/query settlement failures are reported as `.delivered`

## Summary

`TalariaPlatformLink.DrainOutcome.delivered` is documented as:

> got items and/or queries, all handled

But `ack(...)` and `answer(...)` currently discard the result of `post(...)`.

Current shape:

```swift
private func ack(...) async {
    ...
    _ = await post(body, bearer: token)
}
```

and:

```swift
private func answer(...) async {
    ...
    _ = await post(body, bearer: token)
}
```

Then `drain()` does:

```swift
if !drained.items.isEmpty {
    onItemsReceived(drained.items)
    await ack(...)
    didWork = true
}

for query in drained.queries {
    await answer(...)
    didWork = true
}

return didWork ? .delivered : .idle
```

So:

```text
drain 200
ACK 500 / timeout
```

can still become:

```text
.delivered
```

Likewise:

```text
query_result 500 / timeout
```

can still become:

```text
.delivered
```

The loop then resets its failure count as if settlement succeeded.

---

## Why this is not a P1

Inbox item redelivery is intentionally deduped by `platformID` in:

`Talaria/Services/Live/TalariaPlatformInboxService.swift`

That is good.

An ACK failure can therefore cause upstream redelivery without necessarily duplicating the visible inbox row.

That lowers the user-facing severity.

The remaining problems are:

- false success semantics
- lost observability
- failure backoff resets when settlement is unhealthy
- remote query resolution may remain pending or be retried unexpectedly
- tests cannot distinguish “received” from “settled”

---

## Required RED tests

### RED 1 — ACK failure is not `.delivered`

Arrange:

```text
drain → 200 with one item
ack → 500
```

Assert:

- item cache behavior remains intentional
- final outcome is **not** `.delivered`
- non-2xx is logged/classified
- retry/backoff policy is explicit

### RED 2 — ACK transport failure is not `.delivered`

Arrange:

```text
drain → 200 with one item
ack → no response / transport failure
```

Same requirement.

### RED 3 — `query_result` failure is not `.delivered`

Arrange:

```text
drain → 200 with one query
phone responder succeeds
query_result → 500
```

Assert the turn is not reported as cleanly delivered.

---

## Fix considerations

Do **not** blindly make every failed settlement replay everything.

First establish server/plugin semantics.

Useful shape:

```swift
enum SettlementOutcome {
    case settled
    case unauthorized
    case failed
}
```

or simply make `ack`/`answer` return `Bool`/typed result.

Then let `drain()` honestly classify the turn.

Preserve the current desirable property:

> received inbox rows are persisted/deduped before ACK, so at-least-once upstream delivery does not duplicate visible items.

For queries, inspect plugin behavior before deciding whether the phone should recompute the answer on redelivery or cache a result by query ID.

That is a protocol decision, not something to guess during a small client fix.

---

## A2 acceptance bars

- [ ] ACK 500 cannot report `.delivered`
- [ ] ACK transport failure cannot report `.delivered`
- [ ] query-result 500 cannot report `.delivered`
- [ ] happy path remains `.delivered`
- [ ] item redelivery remains deduped
- [ ] 401 behavior is explicitly tested/defined
- [ ] no hot-loop introduced
- [ ] lane gate + Release green

---

# 6. A3 — P3 LOW/MEDIUM
# Launch partition still advertises deleted push registration

## Summary

`AppContainer.LaunchInitStep` is explicitly documented as a pure architectural contract:

> `initialize()` and `runBackgroundBootstrap(generation:)` mirror these lists step for step — a new init step belongs in exactly one list.

But the enum currently still contains:

```swift
case pushTokenRegistration
```

and `backgroundBootstrap` still includes:

```swift
.pushTokenRegistration
```

while the actual `runBackgroundBootstrap(generation:)` no longer performs any push registration.

The background-bootstrap failure comment also still says:

```text
Relay-backed features (sensor upload, inbox, push) stay degraded...
```

This appears to be residue from the notification/APNs teardown around Aug 3.

The tracker already records that the push-registration surface was deleted.

---

## Why it matters

This is small production impact but meaningful **test-contract drift**.

The purpose of `LaunchInitStep` is to make the launch partition machine-checkable.

If the pure-data contract contains a ghost step that execution no longer performs, tests around that contract stop being reliable documentation.

This repo has explicitly adopted a same-commit close-out rule for prose/contracts that a change falsifies.

This is exactly the sort of stale assertion that rule is meant to catch.

---

## Required check

Before changing anything:

```bash
rg -n "pushTokenRegistration|registerPushToken|push registration|sensor upload, inbox, push" \
  Talaria TalariaTests OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md CLAUDE.md
```

Separate:

- live iOS launch-contract references
- historical tracker/archive text that should remain historical

Do not rewrite history merely because an old item accurately describes the system that existed at the time.

---

## Likely fix

If no live call path remains:

- remove `LaunchInitStep.pushTokenRegistration`
- remove it from `touchesNetwork`
- remove it from `backgroundBootstrap`
- update the stale degraded-mode comment
- update any tests whose expected list still includes the deleted step

No source-file addition/removal is expected, so `xcodegen generate` should not be required solely for this cleanup.

---

## A3 acceptance bars

- [ ] no live launch-contract entry claims push registration exists
- [ ] `LaunchInitStep.backgroundBootstrap` mirrors actual execution order
- [ ] launch partition tests green
- [ ] historical tracker records remain historically accurate
- [ ] Release + lane gate green

---

# 7. Known work deliberately NOT re-filed

Claude: **do not create duplicate items for these merely because this audit mentions them.**

Search the live board and archive before assigning any number.

## #282 — Content-claim demand side is unbounded/order-keyed

Already filed.

The remaining transcript reconciliation issue where a `.failed` row can consume a later identical prompt's content claim is known and not started.

Do not create “audit finding: duplicate-prompt reconciliation” as a new item.

---

## #279 — `retryMessage` adoption/duplication issue

Already filed.

Do not duplicate it.

---

## #280 — Dictated-only conversation-card title

Already filed.

Do not duplicate it.

---

## #272 — App Lock re-prompt loop

Critical, but already known.

This audit does not claim to have discovered it.

---

## #251 — Platform inbox persistence/scoping decisions

The plugin venture already records known transport/inbox decisions, including profile/global persistence concerns.

Do not automatically turn every platform-link observation into a second #251 clone.

For **A1**, search #251 carefully first.

If #251 already contains the *specific* active-profile-before-callback / mixed-live-context / rapid-switch invariant with bars, append there.

If it does not, file according to current tracker convention.

---

## #263 and other platform transport history

There is already recent transport-specific failure/reload history.

Do not conflate that upstream/plugin wake/reload issue with A1's **app-side profile transition ownership**.

Different mechanism, even if symptoms can look similar.

---

## #78 local-brain follow-up

The live board still carries the local-brain/device follow-up.

Do not close it merely because related transcript work landed.

---

# 8. Watch seam — ChatStore reconciliation remains high-churn

I am **not filing a new defect here** from static inspection.

However, the Aug 3–7 history shows repeated fixes around:

- dropped final answers
- transcript reconciliation
- attachment preservation
- agent-generated-file chips
- surplus content claims
- retry/adoption behavior

The process has been good — failures were reproduced and filed — but this is now a high-churn seam.

## Architectural caution for future edits

If a message model gains a field, any field-by-field reconstruction/merge helper becomes suspect.

Before adding another message/transcript property, audit:

```bash
rg -n "ChatMessage\(" Talaria TalariaTests
rg -n "mergeAttachments|reconcile|adopt|claim" Talaria TalariaTests
```

Specifically inspect code that creates a new message from an old one rather than mutating/preserving the whole value.

Recent attachment/file-chip regressions are a reminder that:

> a merge routine that manually reconstructs a model silently becomes incomplete when the model evolves.

This is a **review heuristic**, not a request to refactor ChatStore today.

Do not start a cleanup lane without a failing behavior or an explicitly routed design task.

---

# 9. What went well in the recent work

The audit should preserve good process, not merely find faults.

## A. RED → GREEN discipline is visible

Recent history includes examples where regression tests were landed/witnessed before fixes, including the reachability/connect teardown lanes.

Keep doing this.

For A1 especially, deterministic RED harnesses are more valuable than a speculative concurrency rewrite.

---

## B. Device evidence is being treated honestly

Several transcript/UI issues were only closed after device evidence, and successor defects were filed rather than allowing a “mostly fixed” story to hide them.

That is the correct standard for this repo.

---

## C. The project already has a concurrency pattern worth copying

`AppContainer`'s background bootstrap now does several things correctly:

```text
generation
→ cancel
→ retain superseded task
→ await unwind
→ currentness guard
→ state write
```

The audit is not recommending a brand-new concurrency philosophy.

It is recommending applying an already-proven Talaria pattern to profile activation / platform transport ownership.

---

## D. Platform inbox dedupe is well designed

The new platform inbox path persists the row before ACK and dedupes redelivery on `platformID`.

That materially reduces the severity of A2.

Do not damage that property while making settlement reporting more honest.

---

## E. The close-out rule is valuable

`CLAUDE.md` now says a lane does not close until docs/contracts it falsified are corrected in the same commit.

A3 is exactly the sort of small drift that rule should eliminate over time.

Keep the rule.

---

# 10. Claude Code execution plan

## Phase 0 — Establish exact starting state

1. Read `CLAUDE.md`.
2. Confirm repo/worktree.
3. Fetch current `origin/main`.
4. Record:
   - local HEAD
   - `origin/main`
   - commits since `d869af1`
5. If current main is newer than the audit's observed Aug-7 tip, read those new commits before touching findings.
6. Search both tracker files for every candidate mechanism.

Suggested:

```bash
git status --short
git fetch origin
git rev-parse HEAD
git rev-parse origin/main
git log --oneline --decorate d869af1..origin/main
```

Then:

```bash
rg -n "profile switch|active profile|TalariaPlatformLink|platform link|credentialScope|settlement|ack|query_result" \
  OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md
```

Do not assign a tracker number until duplicate search is complete.

---

## Phase 1 — Baseline gate

Use the repo's canonical toolchain:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer
```

Run the canonical gate from `CLAUDE.md`:

```bash
scripts/mac/lane-gate.sh
```

The gate is expected to take time; follow the repo's normal background/poll pattern.

Record the positive success markers and test counts.

If baseline main is red before your changes:

- stop
- characterize the baseline failure
- do not attribute it to an audit fix

---

## Phase 2 — Reproduce A1 first

Priority order:

1. mixed per-turn context
2. stale drain side effects after invalidation
3. rapid B→C last-writer-wins

Use deterministic test seams.

Avoid timing sleeps as the main proof if an injected continuation/gate/actor can make the interleaving exact.

### Decision point

If RED reproduces:

- pre-register bars
- file/append tracker item
- implement smallest architecture-correct fix

If RED does not reproduce:

- inspect why
- determine whether actor isolation/current APIs make the proposed sequence impossible
- document the falsification
- do not manufacture a patch just because the audit predicted one

---

## Phase 3 — Fix A1

Preferred properties:

- one immutable transport context per turn
- one current generation/epoch
- every post-await side effect guards currentness
- profile switch is serialized or superseding
- rapid switch is last-writer-wins
- source comments describe actual ordering

Run focused tests first, then broader suite.

---

## Phase 4 — A2 settlement truthfulness

After A1 is stable:

- add ACK-failure RED
- add query-result-failure RED
- inspect plugin retry semantics
- make drain outcome honest
- preserve inbox dedupe

Do not accidentally turn a settlement outage into an aggressive hot loop.

---

## Phase 5 — A3 launch ghost cleanup

This should be small.

Use `rg`, remove only live stale contract/docs, run launch partition tests.

Do not rewrite archived historical statements.

---

## Phase 6 — Full verification

At minimum:

```bash
scripts/mac/lane-gate.sh
```

Must include:

- Debug suite positive success marker
- XCUITest positive success marker
- Release build positive success marker

Per `CLAUDE.md`, remember that `test-without-building` can replay stale bundles; if tests changed, verify the count moved.

Only add a physical-device bar if the behavior under test genuinely requires a device.

---

# 11. Deliverable back to Owen

At completion, report a compact table:

| Candidate | Reproduced? | Disposition | Tracker item | Commit/PR |
|---|---|---|---|---|
| A1 profile/transport ownership | yes/no | fixed / falsified / already tracked | #? | SHA |
| A2 settlement truthfulness | yes/no | fixed / deferred / already tracked | #? | SHA |
| A3 launch ghost | yes/no | fixed / already fixed upstream | #? / n/a | SHA |

Then include:

### Verification

- focused RED test names
- GREEN test names/counts
- Release result
- `scripts/mac/lane-gate.sh` result
- device verification, if any
- any owed device bar

### Reconciliation

State which of these changed:

- `OPEN_ITEMS.md`
- `OPEN_ITEMS-ARCHIVE.md`
- `CLAUDE.md`
- source comments
- design docs

Apply the repo close-out rule: if the result falsifies an existing live claim, correct the claim in the same lane.

---

# 12. Questions / decisions that should come back to Owen rather than be guessed

Only raise these if the RED/fix actually reaches them.

## Q1 — What should a superseded transport turn do?

Preferred technical answer is likely:

> invalidate and perform no post-switch side effects

rather than letting an old-profile turn finish.

But if the plugin protocol requires old-profile ACK settlement after a profile switch, that becomes a product/protocol decision.

Do not invent cross-host semantics.

---

## Q2 — Query-result retry semantics

Before changing A2 query behavior, establish:

- whether the plugin redelivers an unanswered query
- whether query IDs are stable
- whether duplicate `query_result` is idempotent
- whether recomputing a phone query is safe

If the upstream behavior is unclear, measure/read the plugin.

Do not patch Hermes core.

---

# 13. Standing repo rules relevant to this audit

Pulled from current `CLAUDE.md`; follow the live file if it has changed.

- **Read `CLAUDE.md` before work.**
- `OPEN_ITEMS.md` = live board.
- `OPEN_ITEMS-ARCHIVE.md` = closed history, verbatim.
- Search both before filing duplicates.
- Bars are written in the tracker **before** the run.
- `xcodegen generate` is mandatory after adding/removing Swift files.
- Use **Xcode-beta4**.
- Run **`scripts/mac/lane-gate.sh`** before PR.
- Verify **Release**, not only Debug.
- Do not trust stale `test-without-building` bundles after test edits.
- Do not harden the legacy relay/connector unless Owen explicitly routes it.
- Do not modify a live Hermes install for an experiment without Owen's per-experiment go.
- Keep chat and relay/sensor planes conceptually separate.
- Correct falsified live docs/contracts in the same close-out commit.
- Verification-first: a falsified audit hypothesis is a good result.

---

# 14. Source map for this handoff

Primary public sources reviewed:

- Repository:
  - `https://github.com/AethyrionAI/Talaria-27`
- Standing Claude instructions:
  - `https://raw.githubusercontent.com/AethyrionAI/Talaria-27/main/CLAUDE.md`
- Live tracker:
  - `https://raw.githubusercontent.com/AethyrionAI/Talaria-27/main/OPEN_ITEMS.md`
- Profile store:
  - `https://raw.githubusercontent.com/AethyrionAI/Talaria-27/main/Talaria/Stores/BackendProfilesStore.swift`
- App container:
  - `https://raw.githubusercontent.com/AethyrionAI/Talaria-27/main/Talaria/Stores/AppContainer.swift`
- Talaria platform link:
  - `https://raw.githubusercontent.com/AethyrionAI/Talaria-27/main/Talaria/Services/Live/TalariaPlatformLink.swift`
- Platform link tests:
  - `https://raw.githubusercontent.com/AethyrionAI/Talaria-27/main/TalariaTests/TalariaPlatformLinkTests.swift`
- Platform inbox service:
  - `https://raw.githubusercontent.com/AethyrionAI/Talaria-27/main/Talaria/Services/Live/TalariaPlatformInboxService.swift`

---

# Bottom line

Recent Talaria work does **not** look like it needs a cleanup rollback.

The audit's strongest new concern is very specific:

> **Profile switching currently changes the live profile before the async rebind/transport-stop callback runs, while `TalariaPlatformLink` re-resolves profile-scoped context across suspension points. Cancellation alone does not prevent current-turn side effects.**

Prove that with deterministic RED tests first.

If reproduced, the best direction is to make profile activation explicitly superseding and make every platform-link turn operate on one immutable profile/host context with a current-generation guard.

After that, make platform settlement failures report honestly, then clean the stale push-registration launch contract.

Everything else identified during this review is either already tracked or better treated as a watch seam rather than another speculative refactor.
