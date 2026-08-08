# #285 bar 285-C — the AppContainer full-chain arm, OBSERVED

**Branch:** `claude/t27-285-profile-atomicity` (worktree), on top of `519d364`
**Date:** 2026-08-08
**Scope:** TEST-ONLY. No production code changed — see "The neutered-guard run" for the
one temporary, reverted, byte-verified exception.

---

## The gap this closes

The lane's close-out recorded, in `OPEN_ITEMS.md` #285:

> the store-level serialization arm is unit-proven (the two tests above); the
> AppContainer chain arm holds BY CONSTRUCTION — serialized handlers cannot
> interleave, so C's handler writes every one of those after B's has exited —
> plus code-reviewed checkpoints; there is no AppContainer unit harness to pin
> it directly.

Everything else in the lane was proven by an inverted RED test; that one arm rested on an
argument. It now rests on a trace.

**New test:** `aLateResumingSupersededActivationCannotOverwriteTheWinnersState()` in
`TalariaTests/ProfileSwitchAtomicityTests.swift`.

It lives in the lane's existing atomicity file rather than a new one because the harness it
needs — `GatedSecureStore`, `waitForPark`, `waitUntil`, `InvocationsBox` — is `private` to
that file; a new file would have meant duplicating all four (and an `xcodegen` regen).
No new file, no project regen, no scheme drift.

---

## What the harness forces

A REAL `BackendProfilesStore` wired to a REAL `AppContainer.handleActiveProfileChanged`
— the same edge `makeDefault` builds at `AppContainer.swift:852` — with exactly two
substitutions:

1. the container's secure store is the lane's `GatedSecureStore`, so the handler's **only
   pre-write await** (the profile's gateway-key read, `AppContainer.swift:2209`) can be
   parked on demand. Both shipping conformers (`KeychainSecureStore`, `MockSecureStore`)
   are synchronous underneath, so with either of them this interleaving cannot be
   expressed at all and the test would pass vacuously;
2. the handler invocation is wrapped to record `enter`/`exit` plus `Task.isCancelled` at
   exit.

The credential-scoped stores get **production's own provider closures**
(`activeProfile?.credentialScopeID` for `AppSessionStore`, `resolvedProfile(id:)` for
`PairingStore`), so "which profile did the stores rebind to" is a live read of the same
truth production reads, not a test-local mirror. Distinct per-profile credentials
(`apikey-A/B/C`) and distinct per-profile persisted state (`host-A/B/C`, `session-A/B/C`)
mean every "ended on C" assertion names *which* host it ended on. All gateway URLs are
refused loopback ports so the #247 verdict probe the handler fires can never become a
timing dependency.

**The choreography** — deterministic; no sleep is in the load path, every step is gated on
an observed condition:

| step | action | asserted |
|---|---|---|
| 1 | switch to **B** | B's handler entered and **PARKED** on the gateway-key read: `pendingCount == 1`, trace `["retrieve(B.apiKey)"]`, events `["enter(B)"]`, `hermesAPIKey` still empty, and the scoped stores *have* already moved to B (`host-B` / `session-B`) |
| 2 | switch to **C** while B is parked | scope moves synchronously to C; after a 150 ms settle C's handler has **not** entered (events unchanged, trace unchanged) — the drain-the-corpse wait, observed |
| 3 | release B | B **resumed inside the handler**, saw `Task.isCancelled`, and returned before its writes. C then entered and parked at *its own* key read — which is what makes the window observable at all |
| 4 | release C | C ran to its own exit |

**The load-bearing observation is step 3's `hermesAPIKey`.** At that moment B has provably
resumed and exited (its `exit(B cancelled=true)` event exists), and C has provably not yet
written (it is parked one statement short of its write). The box must still be EMPTY.

Final state asserted at step 4: active profile = C and its gateway URL = C's;
`container.hermesAPIKey == "apikey-C"`; `pairingStore.pairedRelayConfiguration
?.hostDisplayName == "host-C"`; `sessionStore.state.displayName == "session-C"`; the whole
switch touched exactly two credential slots, once each, and wrote none of them (B's key
byte-untouched); events exactly
`["enter(B)", "exit(B cancelled=true)", "enter(C)", "exit(C cancelled=false)"]`.

### Observed trace (fixed code)

```
#285 chain events after B's release: ["enter(B)", "exit(B cancelled=true)", "enter(C)"]
#285 chain keychain trace after B's release: ["retrieve(B.apiKey)", "retrieve(C.apiKey)"]
#285 chain hermesAPIKey in the window: ''
#285 chain events at settle: ["enter(B)", "exit(B cancelled=true)", "enter(C)", "exit(C cancelled=false)"]
#285 chain keychain trace at settle: ["retrieve(B.apiKey)", "retrieve(C.apiKey)"]
✔ Test aLateResumingSupersededActivationCannotOverwriteTheWinnersState() passed after 1.090 seconds.
```

---

## The neutered-guard run — non-vacuity, measured

The `#285 checkpoint` at `AppContainer.swift:2212` (`guard !Task.isCancelled else
{ return }`, immediately after the gateway-key read and immediately before the
`gatewayKeyCache` / `hermesAPIKey` / `chatAPIKeyBox` writes) was **temporarily replaced by
a comment**, the suite re-run, then the file restored with `git checkout --`.

Byte-identical restore, verified by hash rather than by eye:

```
before: dd7be289670bc5a93bf2381f737e04289c73722a3dd001c272b29f8a7c1e38d7  Talaria/Stores/AppContainer.swift
after:  dd7be289670bc5a93bf2381f737e04289c73722a3dd001c272b29f8a7c1e38d7  Talaria/Stores/AppContainer.swift
```

**Failure output with the guard neutered** (`-only-testing:TalariaTests/ProfileSwitchAtomicityTests`):

```
#285 chain events after B's release: ["enter(B)", "exit(B cancelled=true)", "enter(C)"]
#285 chain keychain trace after B's release: ["retrieve(B.apiKey)", "retrieve(C.apiKey)"]
#285 chain hermesAPIKey in the window: 'apikey-B'
✘ Test aLateResumingSupersededActivationCannotOverwriteTheWinnersState() recorded an issue
  at ProfileSwitchAtomicityTests.swift:1041:9: Expectation failed: container.hermesAPIKey.isEmpty
↳ a superseded B handler wrote its own key after resuming: 'apikey-B'
↳ container.hermesAPIKey.isEmpty → false
↳   container.hermesAPIKey → "apikey-B"
↳   isEmpty → false
✘ Test aLateResumingSupersededActivationCannotOverwriteTheWinnersState() failed after 1.088 seconds with 1 issue.
✘ Suite ProfileSwitchAtomicityTests failed after 2.037 seconds with 1 issue.
✘ Test run with 9 tests in 1 suite failed after 2.037 seconds with 1 issue.
```

The test can fail, it fails for exactly the right reason, and it fails at exactly the
assertion designed to catch it. The other 8 tests in the suite were unaffected.

### A finding worth keeping: what the checkpoint actually buys

Under the neutered guard, **only one** expectation failed. Every *final-state* assertion
still passed — active profile C, `hermesAPIKey == "apikey-C"`, stores on `host-C` /
`session-C`.

That is not a weakness of the harness; it is the mechanism, made visible. The
drain-the-corpse serialization alone (`await predecessor?.value` in
`BackendProfilesStore.setActiveProfile`) already guarantees the *settled* state ends on
the last writer, because C's handler cannot start until B's has exited. What the
`Task.isCancelled` checkpoints add is that a superseded handler writes **nothing at all**
in the window before it exits — so no other reader of the shared boxes (the chat key box's
consumers, the cron/skills/insights services' `apiKeyProvider`, the platform link) can
observe a transient B-keyed value while C is still coming. A test that only inspected the
settled state would have been green against unguarded code, which is precisely the trap
this harness had to avoid.

---

## What is observed, and what is still inferred

**Observed directly:** active profile ends on C; `container.hermesAPIKey` ends on C's key
and is never transiently B's; the credential-scoped stores (`AppSessionStore`,
`PairingStore`) move B → C through production's own scope providers; the superseded
handler genuinely parks, genuinely resumes, and exits cancelled without writing; the winner
provably does not start until the corpse has exited; the winner runs to its own exit.

**Not directly observed — and honestly so:**

- **The chat API-key box and the gateway key cache.** `chatAPIKeyBox` is `fileprivate` and
  `gatewayKeyCache` is `fileprivate`, both assigned only inside `makeDefault`, so a bare
  test container has neither and a test file cannot inject one. Reading them would require
  widening production access, which this task forbade. What the harness *does* pin is that
  `hermesAPIKey`, `gatewayKeyCache.set(...)` and `chatAPIKeyBox?.value` are three
  consecutive statements in one straight-line block behind a single checkpoint
  (`AppContainer.swift:2213-2215`) — so `hermesAPIKey` cannot hold C's key unless the other
  two were written from the same `gatewayKey` local in the same turn, and cannot be empty
  in the window unless neither was written.
- **The platform-link restart.** `talariaPlatformLink` is `private(set)` with no injection
  seam on a bare container. What is observed instead: B returned at its FIRST checkpoint
  (evidenced by the untouched key box), so the straight-line statements after it —
  including `talariaPlatformLink?.start()` — provably did not execute for B; and C ran to
  its own exit, so it evaluated that line under C's profile. "The link, if restarted, was
  restarted for C" therefore holds by reachability, which is an observation about which
  code ran, not an argument about what interleaving is possible.

If Owen wants those two arms nailed rather than inferred, the cost is one production edit:
a `// harness-visible` internal setter for `chatAPIKeyBox` and `talariaPlatformLink`, in
the shape `cronJobsStore` / `skillsStore` / `insightsStore` already use for the #180 wiring
test. **Not built** — out of scope for a test-only lane, and it is a decision, not a
correction.

---

## Test counts

Suite selector: `ProfileSwitchAtomicityTests` + `AppStoresTests` + `TalariaPlatformLinkTests`
+ `RunsPlaneTransportTests`, one invocation, plain `test` (never
`test-without-building`), Debug, sim `iPhone 17 Pro Max` `47F68496-…B557`,
`DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`.

| run | code | result |
|---|---|---|
| 1 | fixed | `Test run with 157 tests in 4 suites passed` · `** TEST SUCCEEDED **` |
| 2 | guard neutered (atomicity suite only) | `Test run with 9 tests in 1 suite failed … with 1 issue` |
| 3 | restored (hash-verified) | `Test run with 157 tests in 4 suites passed` · `** TEST SUCCEEDED **` |

**The count MOVED: 156 → 157**, exactly the one new test.
`ProfileSwitchAtomicityTests` went 8 → 9 `@Test`s (`git show HEAD:…` = 8; run 2's own
verdict line reads `9 tests in 1 suite`), and the run log names the new test executing:
`◇ Test aLateResumingSupersededActivationCannotOverwriteTheWinnersState() started.`
(The four files hold 161 `@Test`s in total; the 4-test `RunsHistoryMappingTests` shares
`RunsPlaneTransportTests.swift` but is a separate suite and is excluded by a suite-level
selector — 161 − 4 = 157.)

---

## Verdict

**285-C is now OBSERVED, not by-construction** — for the active profile, `hermesAPIKey`,
the credential-scoped stores, the serialization order, and the negative ("a late-resuming B
cannot overwrite C's state", proven by a run in which it *does* when the guard is removed).
The chat key box and the platform link remain **inferred from straight-line reachability**,
with the exact reason and the exact cost of closing them written above rather than left
implicit.
