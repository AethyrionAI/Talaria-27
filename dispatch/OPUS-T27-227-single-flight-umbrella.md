# OPUS — #227: the single-flight umbrella, re-opened

**Label:** `OPUS`
**Item:** OPEN_ITEMS #227 (UMBRELLA — no single-flight on launch/foreground fan-out)
**Goal:** the three filed instances are closed, but the *class* is not — find every surviving
member at HEAD, state the design default as a rule a reviewer can apply, and decide whether the
fix is one shared primitive or N local guards.

**Verification date:** 2026-08-09, against `main` @ `35c6234` (the repo checkout, not the
worktrees under `.claude/worktrees/`, which are other lanes' copies and were excluded from every
grep).

---

## 0. The premise correction, stated first

The dispatch brief says #227 "has never been given a lane." **It has.** The entry carries a
`✅ RESOLVED 2026-08-04 early AM (goal run)` block closing all three instances, and all three
dispositions are true at HEAD (verified below). What was *not* closed is the class: the entry
resolved three members and recorded the convention, and since then **six more sites of the same
shape are live**, two of them on the exact connector leg §D1 measured.

So this is not "give #227 its lane." It is: **#227 closed its instances and left its default
standing.** That is worth saying plainly, because it is the same failure mode #180 hit (fixed
instance-by-instance, entry not annotated) and the same one the close-out rule exists to catch.

---

## 1. The instance register

Legend — **status**: LIVE (defect present at HEAD) · FIXED · MOOT · NOT-A-MEMBER (with reason).
"Same pass?" = can two call sites be in flight simultaneously in one cold launch or one
foreground transition.

### 1a. The three originally filed

| # | leg | mechanism at HEAD | user-visible cost | status | shares a fix with |
|---|---|---|---|---|---|
| 1 | command-catalog fetch | `AppContainer.refreshCommandCatalog` `Talaria/Stores/AppContainer.swift:1833` now holds `commandCatalogRefreshTask` (`:178`); concurrent callers `await running.value` at `:1842-1845`. Four sites (`:1290`, `:1419`, `:1620`, `:2285`) all join. | was: 2 extra `/v1/commands` starving 5s each as −1001 | **FIXED** (join) | reference impl |
| 2 | `registerPushToken` ×2 | zero references at HEAD — grep for `registerPushToken` across `Talaria/`, `Shared/`, tests returns nothing. #238 deleted the surface. | — | **MOOT** | see M8: the *class* survives at `reportAppStateIfNeeded` |
| 3 | run-completion reconcile | `ChatStore.reconcilePendingRuns` `Talaria/Stores/ChatStore.swift:2338` holds `reconcileInFlight` (`:340`); three sites (`AppContainer.swift:1613`, `:1706`, `ChatScreen.swift:404`) join. | was: the third of §D4's ×3 banners | **FIXED** (join, `0b8aad4`) | reference impl |

### 1b. Live members found in this sweep

| # | leg | mechanism with `file:line` | user-visible cost | status | shares a fix with |
|---|---|---|---|---|---|
| **M4** | **talk readiness** | `LiveVoiceSessionService.refreshReadiness` `Talaria/Services/Live/LiveVoiceSessionService.swift:183`. The gate at `:185` excludes only `.connected`/`.connecting`; the method then sets `connectionState = .checking` at `:188` — **`.checking` is not in the exclusion set**, so a second caller passes the same gate. No task handle. Reached via `TalkStore.refreshReadiness` `Talaria/Stores/TalkStore.swift:61`. **8 call sites**, of which two are launch-path and unavoidable: `AppContainer.swift:1670` (`handleSystemLaunch`, driven by `AppEntry.swift:86`) and `:1631` (`runForegroundActivation`, driven by `AppEntry.swift:177`). Plus `:1729` (pairing activated), `:2289` (profile switch), `SettingsChannelsScreen.swift:50`, `VoiceSettingsScreen.swift:66`, `TalkModeScreen.swift:73`, `CarPlayVoiceManager.swift:81`. | **The heaviest cost in the register.** `GET /v1/talk/readiness` is *not* relay-local: `relay/app/main.py:1221` ends in `send_connector_rpc(auth.user.id, method="talk.prewarm")` at `:1254`, and the relay's own comment at `:1249-1251` says *"the prewarm RPC can run to the full connector timeout (~30s)"*. Two of these ride the connector leg per cold launch, un-coalesced — **§D1's exact starvation mechanism, on a route 3× heavier than the catalog fetch that produced it.** | **LIVE** | M5 (same primitive) |
| **M5** | **sessions list** | `ChatStore.loadSessions` `Talaria/Stores/ChatStore.swift:2064`. Guard is a 15s TTL read at `:2065-2070` against `lastSessionsLoadAt`, **stamped only on success at `:2075`** — the literal clause #227's entry wrote ("a timestamp stamped only on success is not a guard"). At cold launch the stamp is `nil`, so every concurrent caller misses and fetches. Mount-time callers: `ChatScreen.swift:485` (`configureChatSeams` → `Task { refreshSessions() }`) and `SessionsDrawer.swift:571` (`ConversationListPane.onAppear` → `onRefreshRequest`, wired at `ChatScreen.swift:477`); both panes mount together in the regular split. Also `SettingsChannelsScreen.swift:47`, `SessionsSettingsScreen.swift:391`, `AppContainer.swift:1681`. | duplicate `listSessions()` round-trips at launch **and** duplicate `onSessionsLoaded` fan-out (`ChatStore.swift:2076` → `AppContainer.swift:1261` → `spotlightIndexing.donateSessions`), so the Spotlight donation pass runs twice per launch too | **LIVE** | M4 (same primitive) |
| **M6** | **direct-health probe** | `ChatStore.refreshDirectHealth` `Talaria/Stores/ChatStore.swift:1925`. Only guard is `guard !isStreaming` — a *state* check, not an in-flight one. Calls `hermesClient.connect()` (→ `GET /v1/models` on `:8642`) and writes `directConnectionStatus`. Sites: `ChatScreen.swift:508` (mount), `:530` (the ~10s poll loop), `AboutSettingsContent.swift:58`, `AppContainer.swift:2290`. | duplicate gateway probes; two writers racing one published status. Guaranteed-concurrent pair: About/Settings mounted over a live chat screen. Chat-mount vs poll-loop overlaps only when a probe outlives the poll interval — i.e. exactly the degraded case that matters. | **LIVE** | M7, M8 |
| **M7** | **model-catalog seed** | `AppContainer.seedActiveModelFromGateway` `Talaria/Stores/AppContainer.swift:1984`. No guard of its own; both callers gate on `chatStore.activeModelName == nil` (`:1424`, `:1624`) — a *result* check that stays true until one of them lands. Bootstrap (`:1425`) and foreground activation (`:1625`) are both live at cold launch. | 2 × `fetchModelCatalog()` on `:8642` per cold launch, **for users with no persisted model pick only** — `:1986` short-circuits on `activeModelSelection`, so a user who has ever chosen a model pays nothing. That is the default (hostless-first) user paying, per the launch-pivot memo. | **LIVE** | M6, M8 |
| **M8** | **app-state report** | `AppContainer.reportAppStateIfNeeded` `Talaria/Stores/AppContainer.swift:2008`. No guard, no key. `POST /v1/device/app-state` (`relay/app/main.py:1926`). Sites: `:1672` (`handleSystemLaunch`) and `:1644` (end of `runForegroundActivation`) — **both send the string `"foreground"` on every cold launch** — plus `AppEntry.swift:183` (`"background"`). | duplicate relay writes at launch. **This is the surviving twin of instance 2**: instance 2 closed MOOT because #238 deleted `registerPushToken`, which removed a member, not the class. | **LIVE** | M6, M7 |
| **M9** | **sensor outbox drain** | `SensorUploadService.drainOutboxIfPossible` `Talaria/Services/Live/SensorUploadService.swift:672`. `guard !isDraining` at **`:673`**, but `isDraining = true` at **`:713`** — with `guard let accessToken = await accessTokenProvider()` at **`:704`** in between. On the MainActor that await yields, so two callers can both pass `:673` while parked at `:704` and both run a full drain cycle. Concurrency sources: `AppContainer.swift:1433` (bootstrap) vs `:1628` (foreground) vs `:1669` (system launch), all reaching it through `handleAppDidBecomeActive`/`handleSystemLaunch`. | duplicate relay uploads and a duplicate #117 cross-cycle bookkeeping pass — feeds #104's churn from the other end | **LIVE** | nobody: **different fix** (move the flag, don't add a Task) |

### 1c. Same default, opposite symptom — NOT members of #227

These share the root cause exactly, but their guards are written *before* the first `await`, so on
the MainActor they are real mutual exclusion. They do not duplicate work; **they silently drop
it**, and the losing caller cannot tell. That is #180's subject, not #227's, and they are listed
here so lane four does not "fix" them into joins by accident (see Traps).

| leg | mechanism | what actually happens | route to |
|---|---|---|---|
| `HermesHostStore.refresh` `Talaria/Stores/HermesHostStore.swift:51` | `guard !isLoading` (`:52`) → `isLoading = true` (`:54`), no await between | 10 call sites; at cold launch the loser returns instantly having fetched nothing, and `runForegroundActivation` then reads `hostStore.isHostOnline` at `AppContainer.swift:1619` as if it had just refreshed | **#180** |
| `InboxStore.loadInbox` `Talaria/Stores/InboxStore.swift:32` | `isLoading = true` at `:35`, pre-await | 7 sites incl. `InboxScreen.swift:60` `.refreshable` — **pull-to-refresh can complete instantly having done nothing**, which is a user-visible honesty defect | **#180** |
| `AppSessionStore.bootstrap` `Talaria/Stores/AppSessionStore.swift:100` | `isBootstrapping = true` at `:103`, pre-await | drop, not join — and `AppContainer.swift:1354-1357` already names this short-circuit as a hazard it had to work around with `supersededBootstrapDrain` | **#136 / #180** |
| `PermissionsStore.reloadCapabilities` `Talaria/Stores/PermissionsStore.swift:28` | no guard at all, 9 call sites, 2 launch-path | genuinely duplicated work, but **local only** (HealthKit / AVFoundation / Speech status reads) — no network, no connector leg | member by shape, **lowest priority**; fold in only if a lane is already in the file |
| `AppContainer.initialize` `:1303` | `isInitialized = true` at `:1335`, **after** awaits at `:1312`/`:1324`/`:1325` | flag-after-await, same shape as M9 — but only two callers (`AppEntry.swift:126`, `:1720` `handlePairingActivated`) and no evidence they overlap | **ASSUMED risk, not filed** — needs a trigger before it is worth code |

---

## 2. Verified state

### VERIFIED (read at HEAD today, `main` @ `35c6234`)

- Instances 1 and 3 hold real task-join single-flights; instance 2's symbol is gone from the tree.
- Every `file:line` in §1 was opened and read, not grepped-and-assumed.
- `GET /v1/talk/readiness` performs a connector RPC with a ~30s ceiling (`relay/app/main.py:1221`,
  `:1249-1254`) — read from the relay source in this repo.
- The MainActor reentrancy argument for M9 is structural, not inferred: `:673` guard, `:704`
  await, `:713` set, in one function.
- **Five hand-rolled join implementations exist** and are near-identical:
  `AppContainer.commandCatalogRefreshTask` (`:178`), `ChatStore.reconcileInFlight` (`:340`),
  `AppSessionStore.tokenRefreshTasks` (`:36`), `AppSessionStore.sessionRecoveryTask`,
  `ProfileRelaySession.refreshTasks`. Two clear the handle with an identity check
  (`if handle == task`), two clear unconditionally, one is keyed. **Plus three other guard
  dialects in the same codebase**: supersede-with-generation (`#145 Part D`
  `foregroundActivationTask` `:1455`; `#136` `bootstrapGeneration` `:158`), pre-await bool, and
  the `loadGeneration` reset token that #180's lane added to `SkillsStore`/`CronJobsStore`/
  `InsightsStore`. **Four dialects for one problem is the finding.**
- Test seams for the proposed bars already exist: `TalariaTests/IdlePollingTests.swift:66`
  (`CountingSessionClient` with `listSessionsCalls`), `TalariaTests/AppStoresTests.swift:2765-2830`
  (`StubURLProtocol` + `MutableBox` request counter, already constructing
  `LiveVoiceSessionService` with an injectable `accessTokenProvider`), and
  `TalariaTests/SensorOutboxChurnTests.swift:68` (`DebounceGate`) / `:139` (`waitUntilParked`).
- The cold-launch fan-out is three independent chains, each single-flight against **itself only**:
  `AppEntry.swift:86` → `handleSystemLaunch` (`:1648`), `AppEntry.swift:126` → `initialize`
  (`:1303`) → `startBackgroundBootstrap` (`:1346`), `AppEntry.swift:177` →
  `handleAppDidBecomeActive` (`:1516`). Their step lists **overlap on four resources**
  (`hostStore.refresh`, `refreshCommandCatalog`, `seedActiveModelFromGateway`, sensor
  `handleAppDidBecomeActive`) and system-launch adds two more (`talkStore.refreshReadiness`,
  `reportAppStateIfNeeded("foreground")`).

### ASSUMED (mechanism established, magnitude not measured)

- **That the two launch-path `talk/readiness` calls actually overlap in wall time.** Verified: no
  guard, two launch-path call sites, a 30s-capable connector RPC. Not verified: that chain A is
  still inside its prewarm when chain B reaches `:1631`. A call that can take 30s makes overlap
  likely, and §D1 proved concurrent connector RPCs starve — but nobody has watched two prewarms
  race. **This is the one thing a device pass should confirm before the lane, and it is cheap:
  one verbose cold launch, count `talk/readiness` lines.**
- Launch-latency cost in seconds. §D1's measured number (2 extra fetches × 5s, catalog) is the
  only quantified duplicate in the record, and that member is fixed. No number is claimed here.
- The ChatScreen-mount vs poll-loop overlap for M6 (requires a probe outliving the interval).
- Whether duplicate `talk.prewarm` has a host-side cost beyond the round trip.

---

## 3. ⚠️ Tracker corrections

Corrections go upstream, to each stale claim's own home, per the close-out rule.

1. **`OPEN_ITEMS.md` #227 header** — "*THREE instances found in ONE sitting*" plus the `RESOLVED`
   block reads as a closed item. Three *instances* are closed; the *class* has six live members
   at HEAD. The header should say so, and the entry should carry the register above. **The
   resolution note is otherwise accurate and should not be rewritten.**
2. **`TalariaTests/IdlePollingTests.swift:110` `independentAppearancesCoalesceOntoOneFetch`** —
   the name says single-flight; the test pins the **TTL snapshot**. Its three `loadSessions()`
   calls are sequential `await`s, so caller 1 fetches and stamps and callers 2–3 hit the cache.
   **It passes on the defect and cannot go RED on it.** Worse, its stub never suspends, so even
   rewriting it with `async let` would still pass — three MainActor calls into a non-suspending
   stub run to completion serially. Rename to `appearancesInsideTheSnapshotWindowServeTheCache`,
   or leave it and add the parked-stub test beside it; either way the comment must stop implying
   coalescing coverage that does not exist.
3. **`Talaria/Stores/ChatStore.swift:2328`** — the `reconcilePendingRuns` doc says "*Four call
   sites invoke this (`AppContainer.swift:1573,1682,1699,1776`)*". At HEAD there are **three**,
   at `AppContainer.swift:1613`, `:1706`, and `ChatScreen.swift:404`. Line-number citations in
   comments rot; prefer symbol names.
4. **`dispatch/DEVICE-PASS-RUNNING-LIST.md` §D1** — "*Candidate app-side fix… FILED as instance 1
   of the #227 umbrella*" is stale in the good direction: it shipped. §D1 should say FIXED and
   should carry the follow-on that **the same relay mechanism it diagnosed is still live on
   `talk/readiness` (M4)** — §D1 is the only place that mechanism is written down.
5. **`Talaria/Stores/AppContainer.swift:174-177`** — the `#227` comment block instructs "copy,
   don't invent a third shape." At HEAD the codebase holds four dialects. If §6's recommendation
   is taken, this comment must point at the primitive instead.

---

## 4. THE SHARED DESIGN DEFAULT

> **A guard is written as published state, not as a handle to the work.**

Every non-guard in this register is a `Bool`, a `Date`, or a status enum. Those answer *"is
something happening?"* and *"when did it last happen?"* — they cannot answer *"give me the result
of the one that is already happening,"* which is the only answer that deduplicates. So a
state-guard has exactly two possible failure modes, and this codebase has both:

- **written before the first `await`** → mutual exclusion, and the loser **silently drops**
  (`HermesHostStore.refresh`, `InboxStore.loadInbox`, `AppSessionStore.bootstrap`) → #180's class;
- **written after the first `await`, or only on success** → no exclusion, and the loser
  **duplicates** (`loadSessions`, `drainOutboxIfPossible`) → #227's class.

And a second axis, which is why the class regenerates faster than it is fixed:

> **Guards get installed at the entry point, and the entry points are irreducibly plural.**

iOS hands us three launch callbacks (`didFinishLaunching`, the root `.task`, `scenePhase → .active`)
and SwiftUI gives every screen its own `.task`/`.onAppear`/`.refreshable`. `handleAppDidBecomeActive`
is single-flight against *itself*; `startBackgroundBootstrap` is single-flight against *itself*;
neither can see the other, and neither can see `ChatScreen`'s `.task`. **A guard that lives in an
entry point is structurally incapable of deduplicating, no matter how correct it is.** The guard
has to live on the resource.

### The reviewable rule

**For any `async func` that performs network or expensive I/O:**

1. **Count its call sites.** If two can be reached in one cold launch or one foreground
   transition — and with three launch chains plus per-screen `.task`s, the default answer is
   yes — it needs a concurrency guard.
2. **The guard must be a stored `Task` handle that concurrent callers `await`.** A `Bool`, a
   `Date`, a status enum, or a `force:` flag is never one. Neither is a caller-side result check
   (`if activeModelName == nil`).
3. **The guard belongs to the function that does the fetch**, not to any caller and not to any
   lifecycle hook. If you can name an entry point in the guard's variable name, it is in the
   wrong place.
4. **Choose join or supersede deliberately, and write down which and why.** Join when the
   in-flight result is the result the new caller wants (catalogs, lists, health, readiness).
   Supersede when the newest caller carries fresher intent and the old work is worthless
   (#145 Part D's activation chain — *"a chain parked on a dead host has nothing useful left to
   deliver"*). **Getting this backwards is silent both ways.**
5. **If you write a `Bool`, prove where you set it.** Set before the first `await` = a drop guard,
   and you now owe the caller an honest signal that nothing happened (#180). Set after = not a
   guard at all.

**How a reviewer catches instance ten:** in any diff that adds a `.task`, an `.onAppear`, or a
lifecycle step, follow it to the function it calls and ask rule 2. In any diff that adds
`private var isSomethingLoading = false`, ask rule 5.

---

## 5. Shared primitive: **YES** — one, narrow, join-only

**Decision: build `SingleFlight` and adopt it at the new sites. Do not migrate the five existing
hand-rolls in the same lane, and never offer supersede through it.**

### Why yes

- **The count crossed the line.** #227's entry said "copy, don't invent a third shape" — a good
  instruction at three sites. There are **five hand-rolls plus four dialects** at HEAD, and this
  register adds four more join sites (M4–M8, minus M9 which is a different fix). Nine to eleven
  copies of a six-line shape with a subtle detail in it (`if handle == task { handle = nil }`) is
  where copying stops being cheaper than a type.
- **The copy does not cover the next case.** Every hand-roll is `Task<Void, Never>`. `loadSessions`
  (M5) must hand the joiner `[HermesSessionInfo]`, so a copy has to be *adapted* — and adapting a
  concurrency idiom by hand is exactly where the next defect enters.
- **The twin umbrella already answered this the same way.** #180's lane did not write four
  patches; it wrote `Talaria/Core/HostFedListPresentation.swift` — *"THE CONVENTION, written
  down"*, with the four rules on the type's doc comment — and replaced three hand-rolled,
  identically-wrong gates with one decision. #184's lane did the same with one
  `abandonPendingRun()` that all three teardown paths call. **This umbrella's deliverable is a
  convention; a type is how this codebase has twice made a convention enforceable.**
- **It gives the rule a home.** §4's five rules belong on `SingleFlight`'s doc comment, where the
  next author meets them at the moment of choosing.

### Why narrow, and what it must refuse

- **Join only.** A primitive that offers `.join` and `.supersede` as options is a policy menu, and
  §4 rule 4 says picking wrong is silent in both directions. `#145 Part D`'s activation task and
  `#136`'s `bootstrapGeneration` + `supersededBootstrapDrain` stay bespoke; `SingleFlight`'s doc
  comment must **name them and say why they must not adopt it**.
- **`@MainActor`, value-returning, optionally keyed** — the shape the register actually needs:

  ```
  @MainActor final class SingleFlight<Value: Sendable> {
      func run(key: String = "", _ work: @escaping @MainActor () async -> Value) async -> Value
  }
  ```

  Keyed because `reportAppStateIfNeeded` dedupes per state string ("foreground" must not
  coalesce with "background") and `tokenRefreshTasks` is already keyed by credential scope.

### Why not migrate the five now

Each hand-roll is pinned by its own tests and each has bespoke neighbours (a success-only
throttle in front of the catalog fetch, a 60s floor on session recovery, a generation counter next
to the bootstrap). Rewriting five working, tested concurrency sites for uniformity is churn with
real risk and no user-visible benefit. **The honest cost of deferring:** the tree carries two
join spellings until a later mechanical lane. Pay it down cheaply in the same commit by pointing
each hand-roll's doc comment at the primitive (comment-only, zero behavior) — which also
discharges correction §3.5.

**The counterfactual that would flip this:** if the lane's own reading finds only two sites that
genuinely need a join, three local guards win and the primitive is over-engineering. The lane is
authorized to make that call from the code, and to report it as a finding rather than build the
type anyway.

---

## 6. Lane proposal

**227-A — the primitive and the two that cost something.** Build
`Talaria/Core/SingleFlight.swift` (needs `xcodegen generate` — new file). Adopt at **M4**
(`LiveVoiceSessionService.refreshReadiness`) and **M5** (`ChatStore.loadSessions`). These two
carry the register's only real costs — a 30s-capable connector RPC and a duplicated Spotlight
donation pass — and both already have call-count seams in the suite. Bars 227-A, 227-B, 227-E,
227-F.

**227-B — the cheap launch-path triple.** **M6** `refreshDirectHealth`, **M7**
`seedActiveModelFromGateway`, **M8** `reportAppStateIfNeeded` (keyed by state). Mechanical once
the primitive exists. Bar 227-C. **Must follow 227-A**; folding it in is acceptable if the diff
stays reviewable, but do not let three files' worth of adoption hide the primitive's design.

**227-C — the flag-after-await hole.** **M9** `SensorUploadService.drainOutboxIfPossible`. **This
is not a `SingleFlight` adoption** — the fix is to make the existing flag real (set `isDraining`
before the first `await`, or hoist the token fetch above it), which is smaller and touches #117's
cross-cycle machinery rather than the launch chains. Different file, different test harness
(`DebounceGate`), no dependency on 227-A: **runs in parallel from day one.** Bar 227-D.

**227-D — routing, not building.** The drop-class members in §1c go to #180 (or a new sibling
entry) with the mechanism written down. **Do not convert them in this umbrella** — see Traps.
Owen's call; the deliverable is a filing, not a diff.

**Ordering:** 227-C parallel with everything. 227-A → 227-B. 227-D any time, costs nothing.
**Sequence against #287:** let #287 land first if it is close — it is a five-line enum edit and
227-A/B touch different regions of the same file, so second-in rebases trivially either way.

**Optional, explicitly deferred:** 227-E, the mechanical migration of the five hand-rolls onto the
primitive. Zero behavior change, real diff size. Not part of this umbrella's close-out.

---

## 7. Proposed bars

Pre-registered here for the orchestrator to file **in the OPEN_ITEMS entry before any code**
(bars live in the entry; this doc is not the filing).

**The rule that shapes every bar below:** *for a single-flight defect, the honest test asserts a
call count, and the stub must actually suspend.* An outcome test passes on the defect (all callers
get the right data either way — that is what makes the defect invisible). And a **non-suspending**
stub also passes on the defect: three MainActor callers into a stub that never awaits run to
completion serially, so the first one finishes and stamps before the second starts. Every bar
below requires the stub to **park on an injected gate** (`DebounceGate`, `SensorOutboxChurnTests.swift:68`)
and the test to confirm N callers are parked (`waitUntilParked`, `:139`) **before** releasing.

| bar | assertion | how it goes RED on the defect |
|---|---|---|
| **227-A** — talk readiness coalesces | Park inside `LiveVoiceSessionService`'s injected `accessTokenProvider` (already a test seam, `AppStoresTests.swift:2814`). Start 3 concurrent `refreshReadiness()`, confirm all 3 parked, release. **`StubURLProtocol` request count == 1**; all 3 callers return `.ready`. | With the join removed the count is **3** — `.checking` (`LiveVoiceSessionService.swift:188`) is not in the `:185` exclusion set, so every caller proceeds. Restore that line and watch it go RED before accepting the test. |
| **227-B** — sessions list coalesces | Extend `CountingSessionClient` (`IdlePollingTests.swift:66`) to increment **on entry** then park. 3 concurrent `loadSessions()` on a **cold** store (`lastSessionsLoadAt == nil`), all parked, release. **`listSessionsCalls == 1`**, all 3 receive the real list (not `[]`), and `onSessionsLoaded` fired **once**. | Count is **3** on the defect: the TTL stamp at `:2075` is success-only, so all three read it unstamped. The `onSessionsLoaded` half is what pins the duplicate Spotlight donation. |
| **227-B2** — the join did not become a cache | After release and after the TTL window, `loadSessions(force: true)` fetches for real (count 2). | A join implemented as "return the last result" would keep the count at 1 — this is the guard against fixing a duplicate by introducing a staleness bug (#180's class). |
| **227-C** — the launch chains do not double-fetch | **The integration bar, and the one that catches instance ten.** One container, parked stubs, `handleSystemLaunch()` and `handleAppDidBecomeActive()` started concurrently. Per-route counts: `talk/readiness` **== 1**, `device/app-state` **== 1**, model catalog **== 1**, `commands` **== 1**. | Every count is **2** at HEAD except `commands` (already fixed — it is the built-in positive control: if `commands` is ever ≠ 1 the harness itself is wrong). Route-level, so a future member added to either chain fails it without anyone writing a new test. |
| **227-D** — the drain flag is a real guard | Park `accessTokenProvider` (`SensorUploadService.swift:704`), fire 2 concurrent `drainOutboxIfPossible()`, confirm both parked, release. **Exactly one drain cycle** (one `recordDrain` / one upload batch). | Two cycles at HEAD: `:673` guard, `:713` set, one await between. Verify by restoring the ordering after the fix and watching it go RED. |
| **227-E** — supersede sites are untouched | `peakConcurrentForegroundActivations` stays **1** and the existing #145 Part D / #136 bootstrap tests stay green. | If a lane "unifies" the foreground chain or the bootstrap onto `SingleFlight`, the supersede semantics invert (old chains would be joined instead of cancelled) and these fail. |
| **227-F** — no drop-class site was converted to a join | For `HermesHostStore.refresh`, `InboxStore.loadInbox`, `AppSessionStore.bootstrap`: park the first call, start a second, assert **the second returns while the first is still parked**. | A join makes the second caller wait — the test hangs to timeout. This bar exists because converting a drop to a join **lengthens the #145 foreground chain against its 45s budget**, and that regression is invisible in every other check. |
| **227-G** — close-out | The commit that closes any 227-x lane also corrects: #227's header, `IdlePollingTests`' misnamed coalesce test, `ChatStore.swift:331-334`'s stale line numbers, §D1's stale "candidate fix" note, and (if the primitive ships) `AppContainer.swift:174-177`'s "copy, don't invent" instruction. | The close-out rule: a lane does not close until every claim its result falsifies is corrected in the same commit, upstream at the claim's own home. |

**Gate:** `scripts/mac/lane-gate.sh` (Debug suite + XCUITest + **Release build**), literal
`GATE: PASS`. Background it and poll the log with an `until` loop — never arm a Monitor, never
wait on a notification. Release matters here for the ordinary #218 reason and because a new file
plus `xcodegen generate` is exactly the shape that builds Debug and not Release.

---

## 8. Traps and interactions

- **#287 is editing `AppContainer.swift` right now** (removing `LaunchInitStep.pushTokenRegistration`
  from the enum at `:249`, from `touchesNetwork` at `:266`, from `backgroundBootstrap` at `:283`,
  plus the stale "sensor upload, inbox, push" comment at `~:1407` and the partition tests at
  `AppStoresTests.swift:4684-4704`). 227-A/B touch `:178` (new stored property region), `:1984`,
  `:2008`, `:1631`/`:1670`, `:1425`/`:1625` — **no overlapping hunks**, so this is a rebase, not a
  conflict. **Do not add a `LaunchInitStep` case for anything in this umbrella**: the partition
  test asserts `criticalPath + backgroundBootstrap == allCases`, and a coalescing change is not a
  launch step.
- **Join is not free — it converts an instant no-op into a wait.** This is the single most
  dangerous move available to this lane. Today a launch-path caller that loses a drop-guard race
  returns immediately; make it join and the **foreground activation chain now waits out the
  background bootstrap's fetch**, spending #145 Part E(a)'s 45s budget and possibly incrementing
  `foregroundActivationsCutShort` (`AppContainer.swift:1492`). Bar 227-F exists for exactly this.
  Every adoption in 227-A/B is on a site that currently **duplicates** (so the join replaces work
  with a wait of the same duration); none is on a site that currently **drops**.
- **#136's partition is non-negotiable.** The critical path is local-only and the splash drops on
  local-state-ready. Nothing in this umbrella may put a network wait in front of
  `isInitialized = true` (`:1335`). All the adoption sites are on the background/foreground side.
- **#145 Part D chose supersede on purpose**, with the reasoning written at
  `AppContainer.swift:1502-1507`. Read it before touching anything named `foregroundActivation`.
- **#264 (the gateway `:8642` bind race)** is the environment these duplicates land in: a bounced
  gateway can come up without the chat plane, which is precisely when N duplicate probes each burn
  a full timeout. It is upstream Hermes behavior and an ops rule — **do not treat it as a reason
  to add retries or hardening app-side**, and note that #227's whole point is that the duplicates
  are avoidable app-side with zero relay change (the no-hardening rule is satisfied by
  construction here).
- **#54 — concurrent connector RPCs stalling** is the mechanism that makes M4 expensive rather
  than merely untidy. The fix is app-side only. **Do not touch the relay or the connector.**
- **MainActor reentrancy is the entire subject.** Every store and service in the register is
  `@MainActor`-isolated. That is why the pre-await bools are real guards and why M9's is not. Any
  review of this lane should read *where the flag is set relative to the first `await`*, nothing
  else.
- **#104/#117** own the sensor drain's backoff ladder; 227-C must not disturb
  `crossCycleBackoffDeadline` semantics while moving the flag.
- **#285 landed on `main` 2026-08-08 (PR #281)** touching `ProfileRelaySession` and activation
  serialization — one of the five hand-rolled joins lives there. Rebase before assuming the
  hand-roll inventory is unchanged.

---

## 9. Close-out

**What the lane owes when it closes**, beyond green bars:

1. **#227's entry rewritten around the register**, with the class explicitly left OPEN until M4–M9
   are dispositioned, and the `RESOLVED 2026-08-04` block preserved verbatim beneath it (it is
   accurate about what it did).
2. **The five corrections in §3 applied at their own homes**, in the same commit as the fix that
   falsifies them — §D1 in `dispatch/DEVICE-PASS-RUNNING-LIST.md`, the two source comments, the
   test name, the entry header.
3. **`SingleFlight`'s doc comment carries §4's rule**, including the two sites that must never
   adopt it and why — the `HostFedListPresentation` precedent, where the type's doc comment *is*
   the convention.
4. **If the primitive is judged unnecessary from the code** (§6's counterfactual), that is a
   finding to report, not a silent substitution of three local guards.
5. **One verbose cold launch** to settle the register's only ASSUMED-magnitude claim: count
   `talk/readiness` lines. If it is 1, M4 drops to the cheap tier and this doc says so.

**CLAUDE.md:** nothing here contradicts it. If §4's rule survives review, the one-line form —
*"a guard is a Task handle, not a Bool; and it belongs to the resource, not the entry point"* —
is a candidate for the conventions section, and that is Owen's call, not a lane's.
