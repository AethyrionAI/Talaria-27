# Running list — work since the Hermes audit of #218–#238

**Audit tip: `d869af1` (2026-08-02).** This file is the successor record: everything
merged after the audit's range, kept current so the next audit has a starting point
instead of a git archaeology problem.

**Range as of 2026-08-03: `d869af1..main` — 31 non-merge commits, 20 files,
+2,913 / −98.** Suite **1497 → 1523** (+26). Board **230 → 233 items · 141 ✅ · 86 open**.

---

## Merged PRs

| PR | lane | suite | notes |
|---|---|---|---|
| **#239** | Audit response + **a retraction of my own finding** + Fable's #223 plan | 1497 | see "the retraction" below |
| **#240** | **#183 Phase 1** — suite clean; the **gate** was what couldn't fail | 1497 | +0 tests: script + tracker only |
| **#241** | **#133/#143** — durable installation identity | **1503** | +6 |
| **#242** | **#145 E(a)** — one shared foreground deadline | **1499** → 1505 merged | +2 |
| **#243** | **#226** — the run-completion watch was a structural no-op | **1513** | +8 |
| **#244** | **#225** — bound the tool-call spiral | **1523** | +10; **B2 failed on device, see below** |

Post-merge gate on `main` after #240–#242 landed **exactly 1505** — the predicted
1497 + 6 + 2 + 0 — so three parallel lanes composed cleanly.

---

## What the audit found, and what happened to it

**Method was re-execution, not re-reading** — its own gate run, §E1 recompiled, board
recount, live probes. Load-bearing claims held. Three findings, all fixed in #239:

1. **#145's header was stale** — claimed "Parts A + D owed" while its own body recorded
   both merged, and **survived the two PRs that edited that body.** The exact failure
   #230 (Phase 0) indicted, committed the same weekend by #230's author.
2. **`ChatStore`'s poll-loop comment** was wrong by ~11× after Part A changed its
   arithmetic.
3. Three addendum nits annotated in place.

### The retraction — the audit and I shared a wrong cause

**My "the gateway already serves files/models/config" discovery was WRONG.** Those
routes are the **dashboard app's (`:9119`)**, not `gateway/platforms/api_server.py`,
whose `_http_route_table()` is the complete `:8642` list.

I blamed the 404s on a stale gateway process — real (PID 28104 from Jul 29) — and **the
audit recorded the same cause as its Bad #2.** Owen force-restarted the gateway; a
**68-second-old 0.19.1 process returned identical 404s**, falsifying both of us.
**Running the audit's own recommended experiment produced the truth.**

Then a correction to the correction: my first retraction said CLAUDE.md had warned me
and I ignored it. `git log` shows that warning was written **47 minutes after** my
mistake, by the session that caught it. I had read *current* CLAUDE.md and assumed it
always said so.

**What survived:** `/api/model/options` (200, verified twice). **What died:** the
file-migration half, and #21's supersede watch — **#21's founding fact stands.**

---

## Lanes shipped

### #183 Phase 1 — the suite is clean; the gate wasn't
Four static criteria over 1,504 test functions: **1 vacuous** (`testLaunch`, a
legitimate smoke test, kept), 0 silent early-returns, 0 `withKnownIssue`, 0 constant
assertions.

**The finding was in our own gate.** `CondenserFidelityTests` printed
`✔ Suite … passed` while **both** its tests skipped, and `lane-gate.sh` had no concept
of a skip — the headline read `tests run — 1497` with no hint two subjects went
unexercised. Now it counts and names them (**report, not failure** — #93 owns making
them run; expected steady state **2**).

**The sweep tool needed FOUR corrections** and returned 22 → 6 → 3 → 1, confident each
time. Only a count that wouldn't reconcile caught it. **A masked masked-test detector.**

### #133/#143 — one root cause, proven by arithmetic
**99 device rows / 99 distinct `installation_id`s** — a perfect 1:1. The relay upserted
correctly per identity; **the app minted 99 of them**, because the id lived inside
profile-scoped session state that unpair deletes. Fixed app-side, **zero relay change**.

Fixing `init` alone passed 5 of 6 tests — `rebindToCurrentScope()` still adopted a stale
identity on **profile switch**, a quieter path nobody would connect to duplicate Siri
notifications.

### #145 E(a) — one shared deadline
45s around the whole foreground chain, implemented by **cancelling Part D's existing
task** rather than racing it (a non-throwing `Task.value` can't be timeout-raced without
stranding the waiter). Generous on purpose; every cut is counted.
**#145 is now A–D + E(a) complete**, and its device pass **CLOSED CLEAN** the same
evening. Only E(b) remains, tabled behind written triggers.

### #226 — the run-completion watch was a structural no-op
Background mid-run → **nothing** (short run) or **three identical banners** (long run).
Never one. Three legs: arm on stream-in-flight, stable notification id, single-flight the
reconcile. All app-side.

Carries **the instrumentation trap**: a live Xcode session **never suspends**, so the
`.interrupted` branch is unreachable corded and "no banner" is *correct* there for any
run length. Verification must be **uncorded** — now §F8 in the running list.

### #225 — bound the tool-call spiral, and the bars caught the fix short
Per-turn budget 12, same-tool cap 4, wired into all 18 tool call sites by script under a
byte-level invariant. **Bars were pre-registered before the lane ran, per the standing
rule — and that is what made the device result legible.**

**On device: B2 FAILED.** 4m34s, no reply text, ending in
`PROVIDED 8,218 TOKENS, BUT THE MAXIMUM ALLOWED IS 8,192`. Three findings re-frame it:
**#26's condense-and-retry fired and did not help** (it rebuilt the session with all 13
tools re-armed, then overflowed again); **the ceiling is the 8,192 window, not the call
count**; and **the cap's own refusal strings are ~45 tokens each into that window.**
Routed to `dispatch/FABLE-T27-LOCAL-BRAIN-DEVICE-RUN.md`.

---

## The device pass (Owen, same day)

**Closed seven, opened three.** #144 (both relays), #145, #151 (all three shapes), #146,
#180 instance 4, plus twelve §F1 verdicts. Filed: **#225** (the 64-call spiral),
**#226** (the push-watch no-op), **#227** (the single-flight umbrella — three instances
found in ONE sitting).

**§C5 — PARTIAL, honestly recorded.** `1835BBF9` rescued and it **confirms the 0/10**;
**#200F's run was already evicted.** The ordering rule that escalated across four
handoffs was guarding something half-gone before the rule existed. Whole store now
archived off-device.

---

## Standing decisions taken in this range

- **⛔ DO NOT HARDEN THE RELAY OR CONNECTOR** (Owen, standing). Hardening buys
  reliability in a component with a planned end-of-life (#223) and pays permanent update
  friction. **Declined under it:** #188's watchdog, #133's partial unique index,
  `send_push` dedup — kept as findings. **Still allowed:** one-time chores, read-only
  measurement, deleting relay surface.
- **Doc-commit policy:** pre-launch, docs may go **direct to main**; post-launch,
  everything through PR with branch protection on.
- **Tracker canonicalised to ONE header form** (`## N.`). `#N` retired because it reads
  as a GitHub reference — a collision that has misfired twice. **Count corrected
  136 → 134 ✅**: #198/#199 were double-counted.

---

## Open, and who owns it

**Owen — device:** the Fable local-brain run (Lane 0 first: **there is no production
tool-call instrument**), §F8 uncorded (#226, #81), §A1b/§A2b Tuesday with Shelley,
#117's own evening (sensors are off deliberately), OJAMD's row counts.

**Owen — decisions:** D2, #164, #170, #47, #173, **#183 Phase 2** (its deferral reason
expired; the condition Owen set has not been met), #224.

**Solo:** #227 instances 1–2 (cheap, not user-visible). **#223 belongs to the
investigation session.** Phase 7's carve-out (privacy-policy URL, App Store Connect
records) is startable any time — external latency, never invalidated by app work.
