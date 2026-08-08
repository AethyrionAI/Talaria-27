# #285 — RED report: a backend-profile switch is not an atomic transport boundary

> **⚠️ HISTORICAL EVIDENCE — the defect described below is FIXED as of
> 2026-08-08** (same branch, the fix commits following the RED ones:
> `TurnContext` + turn epoch in `TalariaPlatformLink`, serialized
> cancel-superseding activation dispatch, runs-driver `ResolvedEndpoint`
> pin). **The repro tests were INVERTED IN PLACE** — same choreography,
> same gates and parks, opposite assertions — and each inverted test was
> first observed FAILING against the unfixed code (rebased onto
> post-#283 `main`, where the RED suite still passed 6/6) before the fix
> landed. This file is kept verbatim as the record of the pre-fix
> behavior and its traces; the bar-by-bar close-out lives in
> `OPEN_ITEMS.md` #285.

**Branch:** `claude/t27-285-profile-atomicity` (worktree, based on `main` @ `c4067a3`)
**Test file:** `TalariaTests/ProfileSwitchAtomicityTests.swift` (new; no production code touched)
**Date:** 2026-08-07

---

## Verdict summary

| # | Repro | Verdict |
|---|-------|---------|
| 0 | The scope moves *before* the switch handler runs (provenance) | **REPRODUCED** (and it falsifies a comment in `AppContainer`) |
| 1 | One `ensurePaired()` straddling two profiles' Keychain slots | **REPRODUCED** |
| 2 | Profile A's credentials POSTed to profile B's gateway | **REPRODUCED** |
| 3 | `stop()` neither unwinds nor contains an in-flight turn | **REPRODUCED** |
| 3b | A stopped turn deletes the *new* profile's credential | **REPRODUCED** |
| — | Control: same gate, no switch → one profile throughout | **PASSES** (harness is not manufacturing the defect) |

The hypothesis is **confirmed in full**. `TalariaPlatformLink` re-resolves profile-scoped
values across `await` points, and one logical pair/drain turn can and does mix profile A's
credentials with profile B's endpoint and Keychain slots.

One sub-claim was **measured and partly refuted** — see "What did NOT hold" below. It is the
only place where the static audit over-reached, and correcting it made the tests
deterministic rather than flaky.

---

## The blocker, and how it was cleared

`SecureStoreProtocol`'s methods are `async`, but **both** shipping conformers
(`KeychainSecureStore`, `MockSecureStore`) are synchronous underneath. Awaiting them never
yields to the scheduler, so with either of them **no interleaving can be expressed at all**
and every "race" test would pass vacuously.

`GatedSecureStore` (in the new test file) genuinely parks on a `CheckedContinuation` — the
`GatedCronJobService` idiom from `CronJobsStoreTests.swift:349-374` — and records every
`(operation, key)` pair in call order. Every repro asserts `pendingCount == 1` **before**
flipping the scope, and asserts the flip landed **before** releasing. That pair of guards is
what makes these tests non-vacuous: a repro that never parked would prove nothing.

Calls are logged at **entry**, before any parking, because the key was computed by the
caller *before* the call — so entry order is the order in which the caller resolved its
credential scope.

---

## Repro 0 — the scope moves first, the handler runs later

`BackendProfilesStore.setActiveProfile` (`BackendProfilesStore.swift:148-156`):

```swift
updated.activeProfileID = id
state = updated                                  // ← scope moves, synchronously
profilesLog.notice(...)
Task { await onActiveProfileChanged?(target) }   // ← handler runs on a LATER turn
```

`AppContainer.handleActiveProfileChanged` is what calls `talariaPlatformLink?.stop()`. So on
a real profile switch the credential scope has **already moved** by the time `stop()` gets a
turn to run. Every repro below flips the scope while a turn is parked; this test proves that
is a faithful model of a user tapping a different profile, not a contrivance.

It also falsifies the comment sitting directly above that `stop()` call
(`AppContainer.swift` ~:2184):

> "park the drain before the scope moves"

The scope moves first. `stop()` is not, and cannot be, a barrier ahead of it.

---

## Repro 1 — one `ensurePaired()` straddling two profiles — REPRODUCED

**Target** (`TalariaPlatformLink.swift:87-94`):

```swift
func ensurePaired() async -> Bool {
    let tokenKey = tokenKey                                  // scope resolved ONCE
    if await secureStore.retrieve(key: tokenKey) != nil,     // ← suspends here
       await secureStore.retrieve(key: deviceIDKey) != nil { // ← scope resolved AGAIN
```

`deviceIDKey` is a computed var calling `credentialScopeID()` fresh. It is read *after* the
first retrieve has already suspended.

**Forced interleaving:** scope = A (A fully paired, B unpaired) → call `ensurePaired()` →
gate parks the first `retrieve` → assert `pendingCount == 1` → flip the box to B → assert the
flip landed → `release()`.

**Recorded (operation, key) sequence — verbatim:**

```
#285 repro1 keychain trace: ["retrieve(A.deviceToken)", "retrieve(B.deviceID)", "retrieve(B.apiKey)", "store(A.deviceToken)", "store(B.deviceID)"]
#285 repro1 wire trace: ["POST gateway-b.local {\"install_id\":\"install-abc\",\"type\":\"pair\",\"auth\":\"apikey-B\",\"device_name\":\"TestPhone\"}"]
```

**Control (identical gate and park, no switch) — verbatim:**

```
#285 control trace: ["retrieve(A.deviceToken)", "retrieve(A.deviceID)", "retrieve(A.apiKey)", "store(A.deviceToken)", "store(A.deviceID)"]
```

**Reading.** One `ensurePaired()` call read profile A's token slot, profile B's device-id
slot, minted with profile B's API key against profile B's gateway, and then wrote the two
halves of that one credential into **two different profiles' slots**. The resulting Keychain
state is corrupted in both directions:

- **Profile A**: its device token is overwritten by one minted by **profile B's host**, while
  it keeps its own old device id (`dev-A`). A now looks "paired" to `ensurePaired` while its
  two halves come from different servers — a state that will 401 forever until the self-repair
  path fires.
- **Profile B**: got a device id but **no token** — half-paired, precisely the state
  `ensurePaired`'s own doc comment says must never persist ("a half-written pair is unusable
  and should be re-minted rather than wedging every later drain").

The control run rules out the harness: same gate, same park, same release, no switch → every
key resolves under A and both writes land in A's slots.

---

## Repro 2 — profile A's credentials against profile B's endpoint — REPRODUCED

**Target.** `post()` calls `endpointURL()` → `gatewayBaseURL()` on **every** request
(`TalariaPlatformLink.swift:296-309`), while the token and device id it carries were read
from the Keychain earlier in the same turn (`:139-149`).

**Forced interleaving:** scope = A, A fully paired → `drainOnce(wait: false)` → gate parks the
**second** read of A's device id (the last credential read before the POST) → assert
`pendingCount == 1` **and** `wire.all.isEmpty` (nothing has gone out yet, so the switch
genuinely precedes the POST rather than racing it) → flip to B → `release()`.

**Recorded sequences — verbatim:**

```
#285 repro2 keychain trace: ["retrieve(A.deviceToken)", "retrieve(A.deviceID)", "retrieve(A.deviceToken)", "retrieve(A.deviceID)"]
#285 repro2 wire trace: ["POST gateway-b.local {\"device_id\":\"dev-A\",\"type\":\"drain\",\"auth\":\"tok-A\",\"wait\":false}"]
```

(JSON key order within the body varies run to run — `JSONSerialization` does not stabilise it
— so the assertions match on `"auth":"tok-A"` / `"device_id":"dev-A"` substrings and on the
host, never on whole-body equality.)

**Reading.** All four credential reads resolved under profile A. The single POST that carried
them went to **`gateway-b.local`** — profile B's gateway — presenting profile A's device token
`tok-A` and device id `dev-A`, with `Authorization: Bearer tok-A`. Profile A's device
credential is disclosed to profile B's host. The outcome was `.idle`, so from the app's point
of view nothing looked wrong.

---

## Repro 3 — `stop()` neither unwinds nor contains an in-flight turn — REPRODUCED

**Target.** `stop()` (`TalariaPlatformLink.swift:282-286`) sets `isRunning = false` and cancels
`loopTask`, but `isRunning` is consulted only at the **top** of each loop iteration
(`:261`), and a `CheckedContinuation` is not cancellation-aware.

This is the load-bearing repro: that `stop()` is the app's **only** defence against a
cross-profile turn.

**Forced interleaving:** scope = A → `link.start()` (the production entry point, not a
hand-rolled `Task`) → gate parks the drain's own token read → flip the box to B, **then**
`link.stop()` (the real order, per Repro 0) → assert `isRunning == false` **and**
`pendingCount == 1` → `release()`.

**Recorded sequence — verbatim:**

```
#285 repro3 trace at stop(): ["retrieve(A.deviceToken)", "retrieve(A.deviceID)", "retrieve(A.deviceToken)"]
#285 repro3 keychain trace after release: ["retrieve(A.deviceToken)", "retrieve(A.deviceID)", "retrieve(A.deviceToken)", "retrieve(B.deviceID)"]
#285 repro3 wire trace after release: []
#285 repro3 items delivered after stop(): []
```

**Reading.** `stop()` returned and the link reported `isRunning == false` while the turn was
still parked mid-flight, untouched. On release the turn **resumed** and issued a fresh
credential read that resolved under the **new** profile: one `drain` call read
`A.deviceToken` and `B.deviceID`. `stop()` neither unwound the turn nor contained its scope.

Here the mis-scoped read misses (B is unpaired) so the turn bails before its POST — which is
exactly what makes this variant deterministic. Repro 2 is the same interleaving one step
later, where the read *hits* and the turn posts.

---

## Repro 3b — a stopped turn deletes the *new* profile's credential — REPRODUCED

**Target.** The 401 self-repair path (`TalariaPlatformLink.swift:151-160`) captures `tokenKey`
at turn start but re-resolves `deviceIDKey` fresh:

```swift
await secureStore.delete(key: tokenKey)      // captured under profile A
await secureStore.delete(key: deviceIDKey)   // re-resolved → profile B
```

Keychain work is the half of a turn that **no** cancellation can suppress, which is what makes
this the strongest form of the `stop()` claim.

**Forced interleaving:** profile A stale-paired, **profile B fully and validly paired** →
`link.start()` → the drain POSTs to A's gateway and gets a real 401 → gate parks the first
self-repair `delete` (so the network exchange is real and already complete) → flip to B →
`link.stop()` → `release()`.

**Recorded sequences — verbatim:**

```
#285 repro3b keychain trace: ["retrieve(A.deviceToken)", "retrieve(A.deviceID)", "retrieve(A.deviceToken)", "retrieve(A.deviceID)", "delete(A.deviceToken)", "delete(B.deviceID)", "retrieve(B.deviceToken)", "retrieve(B.deviceID)", "retrieve(B.apiKey)"]
#285 repro3b wire trace: ["POST gateway-a.local {\"type\":\"drain\",\"auth\":\"stale-A\",\"device_id\":\"dev-A\",\"wait\":true}", "POST gateway-b.local {\"type\":\"pair\",\"auth\":\"apikey-B\",\"device_name\":\"TestPhone\",\"install_id\":\"install-abc\"}"]
```

(The keychain trace is identical in all four runs and is what the test asserts. The wire
trace's **second** entry is the race-dependent post-`stop()` dispatch — printed for evidence,
deliberately **not** asserted. JSON key order within a body varies per run.)

**Reading.** A **stopped** turn belonging to profile A deleted **profile B's device id** —
`delete(A.deviceToken)` followed by `delete(B.deviceID)`. Note what is *absent*:
`delete(A.deviceID)` never happens, so:

- **Profile B** is left half-paired: token intact, device id destroyed — by a turn that had
  nothing to do with it, after the app had already called `stop()`.
- **Profile A** is left with an orphaned device id and no token.

The turn then went on to attempt a re-pair **against profile B's gateway using profile B's API
key**, on behalf of a drain that started life as profile A's.

---

## What did NOT hold — the one sub-claim that was refuted

The static audit's phrasing — "an in-flight `drain` runs to completion including its keychain
writes **and POSTs**" — is **half right, and the POST half is not deterministic.**

`stop()` calls `loopTask?.cancel()`. `URLSession.data(for:)` *is* cancellation-aware, so
there is a genuine race between the request being dispatched and the cancellation being
delivered. Measured across runs of the very same test binary:

- First run: repro 3's post-`stop()` drain POST **did** reach the stub server
  (`POST gateway-b.local … "auth":"tok-A"`).
- Second run: the identical test recorded `#285 repro3 wire trace after release: []` — the
  POST **did not** go out.

So an assertion either way would have been a flaky test dressed up as a finding. Two things
*are* stable and are what the committed tests assert:

1. **Keychain work after `stop()` always happens** — it is not cancellable at all. That is
   Repro 3 and Repro 3b, and 3b's `delete(B.deviceID)` is a destructive, irreversible side
   effect landing after `stop()` returned.
2. **The response is reliably discarded even when the request goes out.** In every run where
   a post-`stop()` POST was dispatched, `try? await session.data(for:)` still threw on the
   cancelled task, so `post` returned nil and no item was ever delivered
   (`items delivered after stop(): []`). Cancellation does not un-send a request — the host on
   the other end saw it and served it — it only throws the answer away.

Point 2 has a real-world consequence worth filing separately: in Repro 3b the re-pair request
reached profile B's gateway and would have **minted a device row the client then discarded** —
an orphan registration on the host, invisible to the phone.

Because both repro 3 and 3b originally asserted on that racy POST, they were re-targeted onto
the non-cancellable keychain observables and 3b's post-`stop()` re-pair is now refused (500)
by the stub, so the final Keychain state is a function of the deletes alone. Stability was
then re-measured (below).

---

## Commands and output

New file → `xcodegen generate` was required. It also drifts
`Talaria.xcodeproj/xcshareddata/xcschemes/Talaria.xcscheme` (`BuildableName` `Talaria 27.app`
→ `Talaria.app`, plus scheme-version noise); that file was reverted before committing, leaving
only the intended 4-line `project.pbxproj` addition.

```bash
xcodegen generate
git checkout -- Talaria.xcodeproj/xcshareddata/xcschemes/Talaria.xcscheme

DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer \
  xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug \
  -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' \
  -only-testing:TalariaTests/ProfileSwitchAtomicityTests test
```

Suite-level selector only (a method-level selector silently runs 0 tests under
`** TEST SUCCEEDED **`). Plain `test`, never `test-without-building`, never
`CODE_SIGNING_ALLOWED=NO`. **The executed count was read on every run: 6 tests.**

**Final result (run 4 of 4, all identical):**

```
◇ Test run started.
✔ Test activeProfileMovesSynchronouslyBeforeTheSwitchHandlerRuns() passed.
✔ Test ensurePairedStraddlesTwoProfilesAcrossItsFirstAwait() passed.
✔ Test withoutASwitchTheSameGatedTurnStaysOnOneProfile() passed.
✔ Test profileACredentialsArePostedToProfileBsGateway() passed.
✔ Test stopDoesNotUnwindOrContainAnInFlightTurn() passed.
✔ Test aStoppedTurnStillDeletesTheNewProfilesCredential() passed.
✔ Suite ProfileSwitchAtomicityTests passed.
✔ Test run with 6 tests in 1 suite passed.
** TEST SUCCEEDED **
```

### Determinism was measured, not assumed

The suite was run **four consecutive times**. All four: `6 tests … passed`,
`** TEST SUCCEEDED **`. The recorded **keychain traces are byte-identical across all four
runs** (verified by diff). The only cross-run variation anywhere is the **key order inside
serialized JSON bodies** — `JSONSerialization` does not guarantee dictionary key order, a
trait `TalariaPlatformLinkTests` already documents — so every wire assertion here matches on
`"auth":"tok-A"`-style substrings rather than on whole-body equality.

This mattered: an **earlier draft of repro 3 was flaky and was caught by this step**, not by
reasoning. It asserted that the post-`stop()` POST reaches the wire; run 1 agreed, run 2
recorded `[]`. That is the refuted sub-claim documented above, and it is the reason repro 3
now parks one step earlier, on a keychain read that cancellation cannot touch.

### No interference with the existing suite

The new suite carries its own `URLProtocol` stub because `TalariaPlatformLinkTests`' is
`private` to that file and a shared static handler across two suites would be a race. Run
together to confirm they do not disturb each other:

```bash
… -only-testing:TalariaTests/ProfileSwitchAtomicityTests \
  -only-testing:TalariaTests/TalariaPlatformLinkTests test
→ Test run with 19 tests in 2 suites passed
→ ** TEST SUCCEEDED **   (0 test failures)
```

---

## Where the defect lives (for whoever fixes it — no fix attempted here)

`Talaria/Services/Live/TalariaPlatformLink.swift`:

- `:72-82` — `tokenKey` / `deviceIDKey` each call `credentialScopeID()` fresh on every read.
- `:87-94` — `ensurePaired()` captures `tokenKey` but re-reads `deviceIDKey` after a suspension.
- `:96-118` — `pair()` re-reads `deviceIDKey` after the network round trip (Repro 1's mixed write).
- `:128-179` — `drain()` captures `tokenKey` once, re-resolves `deviceIDKey` at three later sites.
- `:156-157` — the 401 self-repair deletes a captured key and a re-resolved key (Repro 3b).
- `:290-309` — `post()` re-resolves `gatewayBaseURL()` on every call (Repro 2).
- `:282-286` — `stop()` cancels the loop task but cannot unwind a turn parked on a
  non-cancellable await, and `isRunning` is only checked between iterations.

The shape of the defect is that **the profile is re-read per-operation instead of per-turn**.
Nothing here is a threading bug — everything is `@MainActor` and there is no parallelism. Every
one of these is an ordinary `await` suspension in a single-threaded actor, which is why all
five repros are deterministic once the store can actually suspend.
