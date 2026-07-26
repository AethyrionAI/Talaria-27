# OPUS-T27-117 — the backoff ladder resets every cycle, so it decays into a hammer

**Item:** OPEN_ITEMS #117 (touches #103, #113, #104, #27) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-117-cross-cycle-backoff` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** confirm the current green count before you start · `export GH_PAGER=cat` first

## The observation

Device pass 2026-07-25, **27-minute induced connector outage**:

- The intra-cycle ramp behaved correctly — 2 → 4 → 8 s, exactly as PR #103 built it
- The **rest between bursts collapsed from ~200 s to ~15 s**
- End state: **18.5 req/min while failing** vs **3.5 req/min while draining** — i.e. **126% of
  healthy baseline retry rate while delivering nothing**

Aggressive on failure, lazy on success. That is backwards.

**Verified correct, do not touch:** deferral, backlog integrity, and drain. 202 POSTs, **zero** false
"delivered", clean full drain on recovery.

## Mechanism — read this before writing code, it is already located

`SensorUploadService.drainOutboxIfPossible()`.

1. The busy ladder lives **inside one drain cycle**. `healthBusyRetries` is declared as a local at
   `:649`, so it starts at 0 on **every** cycle. `maxHealthBusyRetries = 3` (`:203`) with
   `delay = Double(1 << healthBusyRetries)` (`:729`) gives 2 + 4 + 8 = **~14 s of ladder per cycle**.
2. On exhaustion the loop breaks and leaves the rest "for the next trigger" — the comment at
   `:698–705` says so explicitly.
3. `drainOutboxIfPossible()` has **five triggers** (`:414`, `:447`, `:582`, `:593`, `:617`), and the
   enqueue-driven ones fire on sensor ticks. `isDraining` (`:645`) only prevents *concurrent* cycles,
   not *consecutive* ones.

So: during an outage the backlog is never empty, sensor ticks never stop, and the next trigger starts
a fresh cycle the instant the previous one exits — **with the ladder reset to zero**.

**The observed ~15 s floor is the ladder duration itself.** That is the tell, and it matches ~14 s
almost exactly. Early in an outage cycles are spaced by sensor cadence (~200 s); once the backlog is
continuously non-empty they run back-to-back.

**There is no cross-cycle backoff anywhere.** That is the entire defect.

## Scope

**Do not touch the intra-cycle ladder.** It works and it is #103's fix.

Add **cross-cycle** backoff:

- Persist backoff state across cycles — an "not before" instant on the service, escalating on
  **consecutive retry-exhausted cycles** and reset on **any delivery**.
- Gate at the top of `drainOutboxIfPossible()`, before `isDraining = true`, so a suppressed cycle is
  cheap and logs at most once.
- **`ConnectorOutageAlertPolicy` already tracks the consecutive-exhaustion streak** (`:770–787`,
  `.delivered` / `.retryExhausted` / `.inconclusive`). That is the natural home for the escalation
  state — reuse it rather than adding a second parallel streak counter. If it cannot host this
  cleanly, say why in the PR body.
- Choose a ceiling and **justify it**. It must satisfy: sustained-outage retry rate stays **well
  below** healthy-baseline drain rate, and recovery is still detected promptly. A cap in the low
  minutes is the obvious shape; the number matters less than the invariant.

**Preserve, explicitly:**

- Recovery latency. When the connector returns, the backlog must drain promptly — a long backoff must
  not strand a user for minutes after recovery. Consider clearing the gate on any signal that
  plausibly indicates recovery (foreground, pairing change, connectivity regain), not only on the
  timer expiring.
- `.inconclusive` cycles must not escalate. Only the dead-connector shape should.
- The #104 backlog cap and debounced persistence. Do not let a suppressed drain change write cadence.
- The #27 guarantee that a location failure does not starve health.

## Test method — this is not optional

**#117 PASSES under a 15-minute window and FAILS at 25.** The original close was scored on too short
a run. `busyBackoffWait` is already injected (`:245–248`, `:322`) specifically so retry-exhaustion
tests run deterministically instead of sleeping — use it. A test that cannot span multiple
consecutive exhausted cycles does not test this item.

Any re-check, automated or on device, **must state its duration**. A duration-free result on this
item is not a result.

## Definition of done

- Deterministic test: N consecutive retry-exhausted cycles produce a **strictly increasing** gap
  between cycles, up to the ceiling.
- Deterministic test: one delivery **resets** the escalation to baseline.
- Sustained-outage request rate is **below** healthy-baseline drain rate — assert the relationship,
  not a magic number.
- Recovery after a long outage drains promptly; assert the observed latency.
- Deferral, backlog integrity, and full-drain behavior unchanged — the 202-POST / zero-false-delivered
  result must still hold.
- Device verification is **owed by Owen** and must run **longer than 25 minutes**. State that
  explicitly in the PR body.

## House rules

Merge commits only, never squash. File-scoped commits. **OPEN_ITEMS.md edits in their own separate
commit.** `xcodegen generate` only when Swift files are added or removed; pbxproj regen as its own
commit; verify `aps-environment: development` survived.
