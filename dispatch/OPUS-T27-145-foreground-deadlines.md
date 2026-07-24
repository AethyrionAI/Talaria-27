# OPUS-T27-145 — bound the foreground chain so an outage cannot wedge the app

**Item:** OPEN_ITEMS #145 (touches #136, #151, #104) · **Repo:** AethyrionAI/Talaria-27
**Base:** main · **Branch:** `claude/t27-145-foreground-deadlines`
**Toolchain:** Xcode-beta4, pinned sim `47F68496-24F9-45D9-93D3-1C778DB6B557`
**Baseline:** 1135 tests / 104 suites + 8 UI (post-PR #147)
**Staleness check:** `gh pr list --repo AethyrionAI/Talaria-27 --state all --limit 20` first.

## This lane does not need to investigate anything

The 2026-07-24 source read already named the mechanism precisely. **Do not re-derive it.** Read
#145's INVESTIGATION block, confirm the line numbers still match, and build. If a line number has
moved, adjust — do not treat it as a reason to re-open the diagnosis.

Established, and not up for re-litigation:

- **No timeout configuration exists on the chat/session plane.** `SessionsHermesClient` (`:8642`),
  `ModelsShimClient` (`:8765`), `CronJobService`, `SkillsService`, `InsightsService` all default to
  `URLSession.shared` — **60s request, 7 DAYS resource.** The only dedicated timeout in the app is
  `RelayAPIClient.bootstrapProbeRequestTimeout` (5s/10s), scoped to the #136 bootstrap probe alone.
- **`AppContainer.handleAppDidBecomeActive()` (`:1324-1357`) is the blocking path** — twelve
  strictly serial awaits, ~8 network-bound, no deadline, no concurrency, no cancellation. Under the
  #136 black-hole shape one activation costs **8+ minutes**, and
  `refreshDormantProfileTokensIfNeeded` (`:2348-2360`) adds N×60s inside it via its own serial loop.
- **The launch critical path is CLEAN. #136 stands.** Do not "fix" launch. This is foreground
  activation only.

## Why the obvious one-line fix is not enough

Adding timeouts alone does not close this. Twelve serial awaits at a 5s timeout is still a 60s
freeze. **The parts below are complementary, not alternatives** — and Parts B and C are what make
the bug *outlive the outage*, which is the property that forced a phone restart.

Each part is independently revertable. Ship what lands cleanly.

---

# PART A — give the chat plane a timeout budget

Configure a dedicated `URLSession` for the chat/session-plane clients rather than
`URLSession.shared`. **Follow the pattern `RelayAPIClient.bootstrapProbeRequestTimeout` already
establishes** (`RelayAPIClient.swift:132-143`) — that is house precedent and #151's Test Connection
just reused it.

Both knobs matter and they fail differently:

- `timeoutIntervalForRequest` — the per-request stall ceiling
- `timeoutIntervalForResource` — **currently 7 days.** This is the one that makes a wedge
  effectively permanent. Even a generous value here is a vast improvement.

**Pick the numbers deliberately and state them in the PR body with reasoning.** Interactive
foreground refreshes want single-digit seconds. **Streaming chat does NOT** — an SSE run legitimately
lasts minutes, so a blanket short `timeoutIntervalForResource` on the streaming path would kill
live runs. **Distinguish the streaming path from the polling/refresh path, or you will ship a
regression that looks like a network bug.** If one session cannot serve both, use two.

---

# PART B — the UI must not be gated behind the network

**This is the highest-value part of the lane.** `reconcileLiveActivities()` (`:1354`) and
`updateWidgetData()` (`:1356`) are sequenced **last**, behind all eight network awaits. The app
therefore cannot refresh its visible state until the whole chain drains — so it sits frozen on
stale content for minutes *after* the host is healthy again.

That is the difference between "the app is slow right now" and "the app is broken and I restarted
my phone."

**Move the UI-state writes so they do not depend on the network chain completing.** They should run
early, or independently, or both. If either genuinely needs data from an earlier network step,
identify which and say so — then give that specific dependency a short deadline and a stale-data
fallback rather than letting it gate the frame.

---

# PART C — the reconcile loop's budget is wrong by ~30×

`ChatStore.startReconcileLoopIfNeeded()` (`ChatStore.swift:1450-1464`) declares
`maxAttempts = 60 // 60 x 2s = ~2 min`. **The comment budgets only the `Task.sleep` and ignores the
network call.** Each `attemptReconcile` → `reconcileFromServer()` is an unbounded gateway fetch, so
against a black-holed host the real ceiling is 60 × (2s + 60s) ≈ **62 minutes**, not 2. The loop is
armed at step 9 of the foreground chain and keeps grinding long after the outage ends.

**Fix the budget to mean what it says** — bound the total elapsed wall time, not the attempt count.
A wall-clock deadline is the honest shape here; an attempt counter cannot bound a loop whose
per-attempt cost is unbounded.

**Correct the comment too.** A comment asserting a budget the code does not enforce is how this
survived review in the first place.

---

# PART D — activations must not stack

Every scene activation queues another full chain; background→foreground cycles stack them and
nothing coalesces or supersedes. Under an outage this multiplies the wedge by however many times
the user tried to wake the app — which is exactly what a person does when an app appears frozen.

**Make a new activation supersede an in-flight one**, or coalesce so at most one chain is live.
Cancellation is the natural mechanism; the chain currently has none.

---

# PART E — OPTIONAL, and do not attempt it casually

Parallelising the twelve awaits (`async let` / task group with a shared deadline) would cut the
worst case further. **It is also the riskiest change here**, because the current order may encode
real dependencies — `currentAccessToken` plainly must precede the authenticated calls, and others
may have quieter couplings.

**Only do this if you can first establish, from source, which steps are genuinely independent.**
Write that dependency map into the PR body. If the map is uncertain anywhere, **skip Part E and say
so** — a wrong parallelisation here would produce intermittent auth failures on foreground, which
is a far worse bug than a slow refresh and would be miserable to diagnose.

Parts A–D close the user-visible defect without this.

---

# Verification — and be honest about its limits

**There is no device reproduction, and staging an outage on OJAMD is OUT OF SCOPE** — it risks a
working backend for a bug we can reason about statically. So the suite is the evidence.

**Test with an injected client that never returns.** That is the whole point: assert that a hanging
dependency now produces a bounded, observable outcome instead of an unbounded wait.

- A hanging chat-plane client must not stall the activation past the chosen deadline
- The reconcile loop must terminate within its stated wall-clock budget against a hanging client
- A second activation while one is in flight must supersede or coalesce, not stack
- UI-state writes must occur even when a network step never completes ← **the Part B regression pin**

**Do not write a test that asserts on wall-clock timing of real network calls.** It will be flaky
on a loaded machine and would land straight in #183's masked/flaky territory. Inject and assert on
behaviour, not on stopwatch readings.

Full suite green on the pinned sim, `CODE_SIGNING_ALLOWED=NO`; report against **1135 / 104** and
account for the delta. `xcodegen generate` only if Swift files are added or removed — if run, verify
`aps-environment: development` survived and commit the regen separately.

**Device verification is owed and cannot be done in this lane.** State it as owed. The eventual
check is Owen's original scenario: enter the app during a host outage, confirm it stays responsive,
and confirm it recovers on its own once the host returns — **without a phone restart.**

---

# Commit discipline

File-scoped commits, one per part where possible so any part can be reverted alone. pbxproj regen
its own commit. **OPEN_ITEMS.md in a separate commit from code.** `gh pr merge --merge`, never
squash. `export GH_PAGER=cat` first.

# Out of scope

The launch critical path (#136 verified it clean — do not touch it). The relay, gateway, or
connector. #104's sensor outbox churn. #151's Test Connection (already shipped with its own 5s
budget). Staging any outage on a live host.
