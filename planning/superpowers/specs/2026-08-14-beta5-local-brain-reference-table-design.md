# Design — the beta5 local-brain reference table

**Date:** 2026-08-14 · **Base:** `main` @ `23bb69a` · **Device:** `whoGoesThere`,
iOS 27.0 **24A5408d** (beta5) · **Toolchain:** Xcode-beta5 27A5237l

A 2.5-hour attended device campaign: one dated, machine-readable measurement of
the on-device brain on beta5, carrying a *measured* beta4 column wherever a
pinned control makes one honest — plus a powered second attempt at 338-C.

---

## 1. Why this exists, and what it cannot be

Since beta5 landed we have accumulated observations that *look* like runtime
regressions — #337's fabrication, the under-calling, #200J's clause losing its
grip — without ever measuring the runtime as such. This campaign measures it.

**But a true beta4-vs-beta5 A/B is not available, and no part of this design
pretends otherwise.** Three facts close it off:

1. `whoGoesThere` is on **24A5408d** (beta5), confirmed from every recent
   artifact's `osVersion`.
2. **Beta4 is gone from `/Applications`** (verified 2026-08-12) — there is no
   toolchain to build a beta4-targeted binary with.
3. **The simulator cannot generate with FoundationModels at all** (#324:
   `LanguageModelError -1` wrapping `ModelManagerError 1026`, `contextSize = 0`),
   so the retained 24A5390f beta4 sim runtime cannot run a single trial.

Every comparison against a pre-08-11 number is therefore **today's build on
beta5 vs an older build on beta4** — runtime and application changes confounded,
in the same direction, with no control that separates them. The design's entire
job is to make that confound *visible per row* rather than discovered later.

## 2. The discovery this design is built on

`handoffs/evidence/battery-runs/` holds **ten machine-readable beta4 runs** —
per-trial JSON with prompt, cell, tool calls, verbatim text, tokens and latency,
every one stamped `Version 27.0 (Build 24A5390f)`, dated 07-31 / 08-01.

**Every cell they used still exists in today's build** and is individually
selectable via `TALARIA_CELLS` (#341). So the beta4 column can be **re-scored
with tonight's classifier** instead of quoted out of tracker prose — the
difference between a measurement and a borrowed fact.

| archive run | n | cells | prompts | today's instrument | track |
|---|---|---|---|---|---|
| `6AAA4AC4` | 40 | `armed`, `armed-motionredirect` | motiondirect, stepsdirect | `motion-redirect` | U |
| `328502AD` | 40 | `armed`, `armed-motionredirect` | motiondirect, stepsdirect | `motion-redirect` | U |
| `3E53397E` | 80 | `armed`, `armed-fieldrollback` | health/weather × bare/named | `read-tool` | U |
| `6C3EBD86` | 80 | `armed`, `armed-fieldrollback` | health/weather × bare/named | `read-tool` | U |
| `F486F103` | 80 | `armed`, `routed-production` | alarm, calendar, haiku, remind | `routed` | **A** |
| `5EE6ADBD` | 80 | `routed-production`, `routed-scoped` | alarm, calendar, haiku, remind | `routed-scoped` | **A** |
| `1835BBF9` | 80 | `armed`, `armed-scopedv2` | alarm, calendar, haiku, remind | `scoped-v2` | **A** |
| `D1A99F3A` | 13 | `armed` | alarm, remind | partial — no twin cell | — |
| `3CB9E45D` | 0 | — | — | `intent`, **empty** | — |
| `8D724EC5` | 0 | — | — | `intent`, **empty** | — |

Two of the ten carry **zero trials**. ~~Recorded here so a future reader does not
count ten baselines where there are eight.~~ `D1A99F3A` has no twin cell, so it
supports no contrast and is excluded.

> **⚠️ CORRECTED 2026-08-14 (#343, fix round 1) — THE STRUCK SENTENCE COMMITS THE
> ERROR IT WARNS AGAINST.** It says "eight" directly above a table that excludes
> three of the ten. Two definitions were in play and they give different numbers:
> ***has trials*** → **eight**; ***supports a cross-era contrast*** → **SEVEN**.
> **Seven is the figure the bars depend on**, so that is the operative one, and
> the term for it is **contrastable baseline**. `D1A99F3A` is the entire
> difference — it has trials and no twin cell, so it is counted in the eight and
> excluded from the seven. **Ten runs · eight with trials · SEVEN contrastable.**
> Every occurrence in `OPEN_ITEMS.md` #343 uses the seven, and this doc should be
> read the same way.

**Every one of the three attended instruments is cell-for-cell identical to its
archive twin**, verified in source rather than assumed:
`routedActionBatteryCells = [.armed, .routedProduction]`,
`routedScopedBatteryCells = [.routedProduction, .routedScoped]`,
`scopedV2BatteryCells = [.armed, .armedScopedv2]`.

## 3. Two tracks

**Track U — unattended, continuous.** `scripts/mac/run-instrument.sh` launches
back to back, no taps: the 17 read-only probes plus `shape`, `decline`,
`refusal-words`, `card-clause`. Measured throughput is **≈4 s/trial**
(`decline` 40 in 1m51s; `refusal-words` 60 in 3m00s; `card-clause` 90 in 4m56s,
120 in 8m02s).

**Track U is a priority-ordered queue, not a fixed list.** It runs until the
clock says stop, archive-matched and Class 1 rows first. A time overrun then
truncates the *least* valuable rows instead of an arbitrary set, and the
published table names what did not run.

**Track A — attended.** `InstrumentConductor.swift:83` refuses any `writesAlarms`
instrument when `unattended == true`, and every launch-env run is unattended by
definition (~~`AppContainer.swift:2509`~~ → **`Talaria/Stores/AppContainer.swift:2510`**,
corrected 2026-08-14 by re-reading the file at bar pre-registration: the call site
`await conductor.run(… unattended: true)` is line **2510**, and the original
citation also omitted the `Stores/` path). That is Owen's 2026-08-11 ruling and this
campaign does not ask for an exception.

Track A carries four items: `routed`, `routed-scoped` and `scoped-v2` at
`--trials 10` (80 rows each, matching their archive twins), plus **338-C**.

`--trials` is **per cell × prompt**, verified against three known runs
(`card-clause` 4 arms × 3 prompts × 10 = 120; 337-F 3 × 3 × 10 = 90), so
`--trials 10` reproduces each archive n exactly.

## 4. Three row classes

The classes differ in what they license, and the published table labels every
row with its class.

**Class 1a — pinned control, beta4 re-scorable.** Cell text frozen by
definition *and* a beta4 archive JSON exists, so both sides run through one
classifier. **`read-tool` / `armed-fieldrollback`** (`3E53397E`, `6C3EBD86`).
The app half is controlled; the runtime is the residual. Strongest rows in the
table.

**Class 1b — pinned control, beta4 quoted.** Frozen text, but the beta4 number
survives only as a figure in the cell's own doc comment.
**`motion-scope` / `armed-motionrollback`** — run `63C0EF12`: rollback text 0/10,
promoted 10/10, p = 1.08e-05. An effect that large either reproduces or it does
not, which makes it the best regression *canary* we own; but its beta4 side
cannot be re-scored, and the row says so.

**Class 2 — same cell, cross-build.** `armed`, `routed-production`,
`routed-scoped`, `armed-scopedv2`, `armed-motionredirect`. Cell *name* and
prompts pinned; production text moved since 07-31. Deltas reported with the
confound named in the row and **never** stated as a runtime verdict.

**Class 3 — beta5-only.** Probes with no beta4 archive. Pure forward baseline —
and the class that makes tonight pay off later, because beta6 will need a
same-build reference and one cannot be retro-fitted.

## 5. 338-C — a powered hunt, not another attempt

**A correction to #338's own guidance, followed here.** #338's "next attempt"
block recommends scoring 338-C by running 337-G's `cardfix` battery. A later
dated block under #337 overturns that: *"THE BATTERIES CANNOT WITNESS THE
GUARD"* — it sits at `send`/`streamTurn`'s settle point and no battery goes
through it. **338-C can only be scored by real production chat turns.**

**Attempt 1 failed for a structural reason, not bad luck.** It was a single turn
against an intermittent defect; at the working estimate it had a ~70% chance of
proving nothing. The fix is power, not repetition-and-hope.

**Design:** up to **13 turns**, fresh thread each, 337-A's prompt shape held
constant with only the time varied (*"Remind me to take out the trash at N"*).
At p ≈ 0.3, `1 − 0.7ⁿ ≥ 0.99` at n = 13. **Stopping rule:** stop at the first
turn that fabricates *and* is corrected by the guard — that is the bar met — or
at 13 with a null.

**The honest caveat, and it is load-bearing (#215).** The ~3-in-10 estimate
comes from 337-F's `armed/remind` cell, which is **armed, not routed** — so it
is *not* a production rate and this design does not treat it as one. It sizes
the attempt; it does not bound the result. **A null at n = 13 therefore does not
establish that production fabricates below any particular rate**, and the
write-up will say exactly that rather than implying a measured ceiling.

## 6. What gets built first

Both are risk controls, not features.

**One scorer over both eras.** Extend the 337-G scorer
(`planning/reports/2026-08-13-337g2-clause-ab/`, already validated against a run
with independently known numbers) to read the 07-31 archive schema. **It is
re-validated against a known run before being pointed at anything new.** This is
the curly-apostrophe lesson: 337-G's first scorer draft read fabrication at 0/10
where the truth was 3/10, because the model writes `I've` with a curly
apostrophe and the regex carried a straight one. A counter that silently reads
zero is #300's failure shape.

**A sequencer** around `run-instrument.sh`: launches Track U back to back,
verifies the **positive** completion flag per run, and enforces a hard per-run
timeout so a TCC hang is *detected* rather than parking the night silently.

## 7. Thermal is a variable, not noise

Recent runs climb `nominal → fair → serious` inside ~8 minutes, and cell order
interacts with it — 337-F's best arm ran last at `serious`, which is precisely
what made that result credible.

~~**The 07-31 archive predates the `thermal` field entirely**, so thermal is
itself part of the cross-build confound and cannot be matched, only recorded.~~

> **🔴 SUPERSEDED 2026-08-14 — BOTH HALVES OF THE STRUCK SENTENCE ARE FALSE.**
> Falsified by direct measurement of the archive JSON while pre-registering the
> bars (#343, fix round 1): **all SEVEN contrastable archive runs carry per-cell
> thermal, start AND end, in today's exact shape** — e.g. `6AAA4AC4`
> `['armed:start=nominal', 'armed:end=nominal',
> 'armed-motionredirect:start=nominal', 'armed-motionredirect:end=nominal']`.
> `D1A99F3A` (trials, no twin cell) carries `['armed:start=nominal']` — start
> only, one cell, because it died 13 trials in — and only the two **empty** runs
> (`3CB9E45D`, `8D724EC5`) carry `thermal: null`, with no trials to attach it to.
>
> **So thermal CAN be matched between eras, at cell granularity, across every run
> any bar actually uses.** It is not an unmeasurable residual of the cross-build
> confound.
>
> **The consequence runs past the sentence itself, and this is the part worth
> following through: the mitigations below were designed around an inability that
> does not exist.** They remain correct as run-hygiene, but they are no longer
> the *only* available answer — a cross-era row can now **report and compare both
> sides' thermal** rather than merely ordering the night to hold it roughly
> constant. **Every cross-era row must therefore state both eras' thermal.**
>
> **And one row inherits a named confound that this sentence had hidden:
> `1835BBF9` ran start-to-finish at `serious` in BOTH cells** — so **RT-E**'s
> beta5 twin, which the timeline runs early at `nominal`, is **not thermally
> matched**, and the published row must say so rather than presenting the
> contrast as like-for-like. Recorded in `OPEN_ITEMS.md` #343 under the thermal
> correction and RT-E.

Mitigations (still run, now as hygiene rather than as the only recourse):
archive-matched instruments run **first**, while thermal is
`nominal`; cell order fixed and declared before the run; thermal recorded per
cell (already in the artifact schema) **and compared against the archive's**; and
**`motion-redirect` runs twice — once
at the top of the night and once at the end** — so within-night drift is
measured rather than assumed. It is the canary because it is short (40 trials,
~2 min) and has the most beta4 replication (two archive runs).

## 8. Bars — pre-registered, before any launch

Per the convention since #215, these are written before the run and a missed bar
is a falsification, not a redefinition. They land in the OPEN_ITEMS entry.

> **📌 THESE BARS WERE PRE-REGISTERED 2026-08-14 IN `OPEN_ITEMS.md` #343, AND
> TWO OF THEM WERE AMENDED THERE BEFORE ANY LAUNCH. THE TRACKER ENTRY IS THE
> OPERATIVE TEXT** — this section is the design that produced it, kept for the
> reasoning. The amendments, both measured against the archive rather than
> reasoned: **RT-A splits health from weather** (see the note under RT-A below),
> and **RT-F becomes a ceiling-retention bar with a drift-vs-level-shift
> discriminator** (see the note under RT-F below).

- **RT-A (Class 1a).** `read-tool`/`armed-fieldrollback`, re-scored both eras
  through one classifier. Bar: report the beta4→beta5 delta per prompt with a
  two-tailed p. **No directional prediction is registered** — this is the row
  that measures, and pre-committing a direction would invite reading noise as
  confirmation.

  > **⚠️ AMENDED 2026-08-14 — RT-A IS REPORTED AS TWO ROWS, health and weather.**
  > The plan justified this as *"all 40 beta4 weather trials ran against a
  > weather service returning `rejected this app's credentials`"*. **Measured at
  > pre-registration, that is 40 of 80, not 40 of 40**: `3E53397E` (00:27Z) has
  > 40/40 weather replies failure-shaped, while `6C3EBD86` **65 minutes later**
  > has 40/40 returning real data. The beta4 weather column is **bimodal across
  > the archive, not uniformly poisoned.**
  >
  > **The split survives in a sharper form, because the confound does not reach
  > RT-A's own observable.** `currentWeather` fired **10/10 in all four weather
  > cells of both runs** regardless of service state — so service state moves
  > **text-derived** metrics only, while RT-A's primary metric
  > (`metric_spurious_location`, `scripts/mac/score-eras.py:107`) reads the tool
  > list. **Weather is reported as its own row; its TEXT metrics are
  > interpretable only against a declared service state, which the row states;
  > its TOOL metrics are not confounded by it.** No direction is registered — the
  > clause above stands unchanged.

- **RT-B (Class 1b canary).** `motion-scope`. Bar: the promoted-vs-rollback
  contrast reproduces at p < 0.01. **Failure to reproduce a p = 1.08e-05 effect
  is itself the headline finding** and escalates immediately, pausing the sweep.
- **RT-C (Class 2, attended).** `routed`, n=80, cells and prompts identical to
  `F486F103`. Bar: publish `armed` and `routed-production` create rates beside
  beta4's, each tagged cross-build. Explicitly **not** a runtime claim.
- **RT-D (Class 2, attended).** `routed-scoped`, n=80, matching `5EE6ADBD`.
  Bar: the `routed-production` cell appears in **both** RT-C and RT-D, so its
  two beta5 measurements are reported against each other as an internal
  consistency check. A gap between them bounds this campaign's own noise floor
  and is published whichever way it falls.
- **RT-E (Class 2, attended).** `scoped-v2`, n=80, matching `1835BBF9`. Bar:
  report the `armed` vs `armed-scopedv2` contrast against beta4's. #214 closed
  this cell on a composition cost that #215 later showed was structurally void
  once routing is in front — so this row is re-measurement, not revival, and
  **nothing is promoted on it**.
- **RT-F (drift).** `motion-redirect` start-of-night vs end-of-night. Bar: the
  two runs' ~~rates~~ **counts** reported with their thermal states.
  ~~A significant gap~~ **A gap between the two canaries** invalidates
  late-night rows and that invalidation is published, not quietly dropped.

  > **⚠️ AMENDED 2026-08-14 — CEILING RETENTION, AND A DISCRIMINATOR.**
  > **(a) There is no rate to compare.** In beta4 this instrument is at ceiling:
  > `stepsdirect` → `readHealth` scored **10/10 in every cell of both archive
  > runs** (20/20 per cell, 40/40 pooled), and `motiondirect` → `readMotion`
  > likewise 40/40 — **and the ceiling is thermal-insensitive**, since `6AAA4AC4`
  > ran entirely at `nominal` and `328502AD` entirely at `serious` and both sat at
  > 20/20. So the bar is **retention**: each canary must read 20/20, and **any
  > drop — one trial — is reported rather than absorbed into a rate.** The
  > struck *"significant gap"* wording is retired: **a significance test on a
  > ceiling metric is the wrong instrument**, and leaving it beside the retention
  > rule would have governed one observation with two rules.
  >
  > **(b) A drop is TWO different findings and the row must say which**, because
  > filing one as the other either invalidates the night wrongly or buries a real
  > beta5 result under the wrong heading:
  > **canary #1 ≠ canary #2 ⇒ within-night DRIFT** (the row's purpose; this is
  > what invalidates late rows); **canary #1 == canary #2, both below 20/20 ⇒ a
  > CROSS-ERA LEVEL SHIFT, not drift** — the night is internally consistent, the
  > late rows stand, and the finding escalates on its own terms alongside RT-B.
  > **Only the first-vs-second comparison separates them, which is why this
  > instrument runs twice.**
- **RT-G (338-C).** Up to 13 production chat turns. Bar: one turn that
  fabricates *and* is corrected by the guard. A null at 13 is reported as a
  null **with the explicit statement that it bounds nothing**, per §5.
- **RT-H (Class 3).** Every remaining Track U instrument completes with
  `endedCleanly` and a positive completion flag, or is reported as not-run with
  its reason. **Absence of a failure marker is not success.**

## 9. What this campaign will not claim

Stated now so it cannot drift later:

- **No runtime verdict from a Class 2 row.** Ever, regardless of effect size.
- **No collapsed union bars.** Each band reports its own denominator.
- **An explicit error counter on every band**, so swallowed trials cannot read
  as clean — `21F0C10D`'s 165/165 instrument errors scored as behaviour is the
  standing example.
- **No production text is edited.** #337-F-2b's reworded-blurb recommendation
  stays Owen's separate call and is not folded into this campaign.
- **No promotion on any row.** This campaign measures; promotions are separate
  decisions with their own bars.

## 10. Timeline

| window | work | whose hands |
|---|---|---|
| 0:00–0:20 | Pre-flight: install `23bb69a` via the Xcode bridge (`RunProject`); confirm `osVersion` 24A5408d and `buildSha`; confirm Reminders/Calendar grants; re-validate the scorer against a known run | mine |
| 0:20–0:35 | `motion-redirect` canary #1, then Class 1 rows (`read-tool`, `motion-scope`) at `nominal` thermal | mine |
| 0:35–1:00 | **Track A batteries** — `routed`, `routed-scoped`, `scoped-v2` (~19 min device + launches) | Owen taps ×3 |
| 1:00–1:20 | **338-C** — up to 13 production chat turns, fresh thread each | Owen, ~20 min |
| 1:20–2:05 | Track U continuous, priority-ordered | mine |
| 2:05–2:15 | `motion-redirect` canary #2 | mine |
| 2:15–2:30 | Fetch, score both eras, write the table + tracker entry | mine |

Owen's total hands-on time is ~25 minutes of the 150, in two contiguous blocks
so it can be done in one sitting rather than as scattered interruptions.

## 11. Risks

- **338-C's block is the schedule's soft spot.** If it runs long it eats Track
  U, which is why Track U is priority-ordered and truncatable. 338-C is capped
  at 13 turns and stops early on success.
- **A TCC hang parks the night.** Mitigated by the runner's hard timeout, which
  detects rather than waits. Pre-flight confirms grants.
- **Thermal saturation flattens late rows.** Mitigated by canary #2, and by
  putting every archive-matched row early. Track A's three batteries run
  back-to-back and will heat the device — RT-D's internal consistency check on
  the repeated `routed-production` cell is the instrument that catches it.
- **The scorer is wrong in the same way on both eras.** Partly mitigated by
  re-validation against a known run; noted as residual, because a symmetric
  scorer bug cancels in the delta but corrupts the absolute rates.
- **The phone is not at the Mac Mini.** The Xcode-bridge deploy assumes a cable.
  OTA (`scripts/mac/ota-stage.sh`) is the fallback and costs ~10–15 min up front.
