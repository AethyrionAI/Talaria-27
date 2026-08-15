# #343 — the beta5 local-brain reference table

**Run 2026-08-15, 04:00–07:40 UTC**, `whoGoesThere` (iPhone 17 Pro Max), iOS 27.0
**24A5408d** (beta5), Xcode-beta5, Debug build of branch `343-beta5-reference-table`.
Campaign directory `~/.talaria-instrument-runs/343-campaign`, verified empty at start.

**Totals: 29 accepted artifacts · 970 trials · 599 probes · 5 fabrications · 1 STRICT specimen.**
Bars RT-A..H were pre-registered in `OPEN_ITEMS.md` #343 **before the first launch**.

---

## 1. The finding that reframes the campaign, and it is not about beta5

**#225's tool-call governor (`5e919269`, 2026-08-02) caps a tool at 4 calls per turn — and the
batteries never start a turn.** `LocalChatBackend+Refusal.swift:39`: they call `session.respond`
directly and never call `beginTurn()`, so every trial in a run counted as ONE turn. After four
`readHealth` calls the tool was refused for the remainder of the launch.

Measured, before the fix: canary #1 returned **31 of 40 trials dead**, both sensor tools failing
together (14 `DeviceHealthTool` + 17 `MotionTool`). `ToolCallGovernor.beginTurn()`'s own doc
comment predicts precisely this — *"a budget that leaked across turns would silently strangle a
long conversation … the obvious way this fix becomes worse than the bug it fixes."*

**The dates are the whole story. The beta4 archive is dated 07-31 and 08-01; the governor landed
08-02.** The archive's 20/20 was measured with no governor in existence, so no build carrying it
can reproduce that — on any runtime. Every cross-era row in this campaign would have been
measuring our own governor and attributing it to beta5.

**Two hypotheses were falsified on the way** and are recorded because the elimination is the
evidence: *permissions lost in the reinstall* (wrong — successful trials were perfect), and *the
screen auto-locked mid-run* (wrong — with Auto-Lock set to Never the re-run was identical
trial-for-trial; identical counts are deterministic, not timing).

**Fix:** `toolRelay?.beginTurn()` per trial in `runActionBattery` (`:974`) and `runShapeBattery`
(`:228`). DEBUG harness only; no production change; it makes the harness *more* production-like,
since production opens every turn with `beginToolTurn()` → `relay.beginTurn()`. Proven twice
before tonight (337-D `turn-reset` 0/30 cuts vs `leaked` 9/30; 337-F 0 cuts in 90 trials), and
tonight: **31/40 dead → 0/40 dead from one line.** `runHonestyBattery` deliberately unchanged —
empty belt, no tools registered, governor unreachable.

**Consequence beyond this campaign: every battery rate measured between 2026-08-02 and this fix
is governor-strangled.** That is a fact about the project's measurement record, not just tonight.

---

## 2. Bars, scored as written

| bar | verdict | result |
|---|---|---|
| **RT-A** Class 1a | **MEASURED** | pinned `armed-fieldrollback` **20/20 → 0/10** spurious location, **p = 3.33e-08** |
| **RT-B** Class 1b canary | **MET** | promoted 10/10 vs rollback 0/10, **p = 1.083e-05** — reproduces #211's published 1.08e-05 |
| **RT-C** Class 2 | measured | `armed` 22/30 (p=0.005), `routed-production` 25/30 (p=0.052) vs beta4 30/30 |
| **RT-D** Class 2 + noise floor | **MET, and it constrains the rest of the table** | see §4 |
| **RT-E** Class 2 | measured | `armed` 28/30 (p=0.49), `armed-scopedv2` 22/30 (p=0.005) vs beta4 30/30 |
| **RT-F** drift | **MET** | canary #1 == canary #2 == **20/20**, no drift, no level shift |
| **RT-G** 338-C | **NOT RUN** | needs production chat turns; owed to Owen |
| **RT-H** Track U completeness | **MET** | 21/21 eventually completed; 2 required a re-run, reported with cause |

### RT-A — and the direction is one nobody predicted

`metric_spurious_location` on `weathernamed` (a **tool** metric: was `currentLocation` called on
a prompt that already names its location):

| cell | beta4 pooled | beta5 | Fisher |
|---|---|---|---|
| `armed-fieldrollback` — **pinned, frozen text** | **20/20** | **0/10** | **3.33e-08** |
| `armed` — production text, which moved | 5/20 | 0/10 | 0.14 |

Confounds addressed rather than asserted: the rollback cell's text is byte-identical across eras;
the run is **thermally matched** (beta5 `armed` nominal→fair, `fieldrollback` fair→fair; beta4
`3E53397E` identical); the weather service was **working** tonight (0 credential rejections, so
the service-matched twin is `6C3EBD86`), and the metric reads the tool list rather than the reply
text — with both beta4 twins scoring 10/10 under *opposite* service states, confirming that
immunity empirically. The governor is present but behaviourally inert here (0 errors, 80/80
executed, never trips under `beginTurn`-per-trial).

**No directional prediction was registered for RT-A** — deliberately, so that a result in either
direction would read as a measurement. The #209 field-omission defect the rollback preserves is
gone on beta5.

### RT-B — the row that makes RT-A credible

`stepsdirect`: promoted **10/10**, rollback **0/10**, p = 1.083e-05, against #211's published
0/10 vs 10/10 at p = 1.08e-05 (run `63C0EF12`). Motion questions unaffected, 10/10 in both cells
(#211 recorded 9/9).

**The pair matters more than either row alone.** RT-B reproducing its beta4 effect *exactly*
demonstrates the apparatus is sound on this runtime, so RT-A's change cannot be dismissed as a
broken instrument. One row holds, one moves, same night, same harness.

---

## 3. RT-F — no drift, and a ceiling that ignores thermal

| run | errors | motiondirect | stepsdirect | thermal |
|---|---|---|---|---|
| canary #1 04:17 | 0 | 20/20 | 20/20 | nominal |
| sweep re-run 05:34 | 0 | 20/20 | 20/20 | nominal |
| canary #2 07:02 | 0 | 20/20 | 20/20 | **serious** |

canary #1 == canary #2 ⇒ **no within-night drift, so every late-night row stands.** Both equal
beta4's 20/20 ⇒ no cross-era level shift. Holding at `serious` independently confirms the
thermal-insensitivity implied by the beta4 twins (`6AAA4AC4` nominal, `328502AD` serious, both
20/20).

**This bar is why the night has a result at all.** Pinned at a ceiling, 31/40 dead was
unmistakably an apparatus failure. On any unpinned metric it would have read as a catastrophic
beta5 regression. RT-F exists because the final whole-branch review caught that plan Task 6 had
no step that ran the canary.

---

## 4. RT-D — the noise floor, and what it forbids

`routed-production` was measured **twice tonight**, same cell, ~7 minutes apart:

| | alarm | calendar | remind | total |
|---|---|---|---|---|
| RT-C's copy | 9/10 | 9/10 | **7/10** | 25/30 |
| RT-D's copy | 10/10 | 8/10 | **3/10** | 21/30 |

p = 0.36 between them — but the consequence is sharp: **the same cell against the same beta4
baseline yields p = 0.052 (RT-C) or p = 0.002 (RT-D) depending on which of tonight's two runs you
pick.** On `remind` alone the swing is 7/10 vs 3/10.

**So no Class 2 delta in this table may be read as a runtime effect.** The design forbade that on
principle; RT-D converts it into a measurement. This row existed only because Owen claimed the
spare attended slot — without it the table would carry six significant-looking p-values and no
way to know they were unstable.

**Convergence worth keeping:** tonight's 83% and 70% **bracket** 337-F's 23/30 = 77%. Three
independent leak-free measurements of the production-like create rate agree. beta4's 30/30 is a
100% ceiling that no leak-free measurement has ever reproduced — a hint that the ceiling, not the
drop, is the anomaly.

---

## 5. Honesty numbers

**0 fabrications in the 240 attended trials.** Campaign-wide: **5 fabrications / 970 trials**
(card-clause 1, refusal-words 3, honesty 1 — the refusal-words and card-clause instruments run
auto-DECLINE, so those are #199's claim-after-decline shape) and **1 STRICT `Confirmation card:`
specimen** (RT-C `armed/remind` t4, an offer with no tool call), against #200J's beta4 0/40 and
337-G's beta5 2/120.

---

## 6. Defects found, and they are ours

1. **The governor leak** (§1) — fixed tonight.
2. **🔴 The calendar reap under-deletes, silently.** `createReminder` 36 → reaped 39 (+3, exactly
   +1/run, #336(b)'s warmup signature ✓); `scheduleAlarm` 54 → 57 (+3 ✓); **`createCalendarEvent`
   42 → reaped 25 (−17)**, with `failures=0` reported every run. Reminders and alarms reconcile
   exactly, so the reaper works — calendar does not. **Up to 17 "Lunch with Sam" test events may
   remain on the real calendar.** Not cleaned up: deleting from Owen's calendar is his call.
3. **My `--timeout 600` truncated two honest probes.** `intent-router-probe` and
   `vector-router-probe` were SIGTERM'd at ~608s; the re-run shows `intent-router-probe` needs
   **~14 minutes**. The registry already noted "~585 generations is ~10 minutes". Both are Class
   3, so nothing cross-era was lost; both re-ran clean (116 and 31 probes).
4. **A bug in the scoring code, caught by an implausible number.** The first sweep table reported
   `intent-router-probe` — a read-only probe registering no tools — as 40 trials / 40 tool
   executions. `run-instrument.sh`'s `baseline_copy()` places the *previous* instrument's artifact
   in each new run directory before launch, and the scorer keyed off the directory NAME. Fixed by
   `provenance()`, which rejects non-terminal artifacts and instrument/directory mismatches, and
   was **proven falsifiable both ways** — a real artifact planted in a wrong-named directory is
   rejected with the mismatch reason; the same artifact in its own directory is accepted.
5. **Plan Task 6 Step 1's build check cannot fail.** It compares the artifact's `buildSha` against
   `git rev-parse HEAD`, but `run-instrument.sh:137` stamps that value FROM the repo's HEAD and
   `InstrumentConductor.swift:71` merely passes it through. The same script computes both sides.
   There is no compiled-in build identity anywhere in the app. Worked around by rebuilding and
   reinstalling rather than trusting the check.

---

## 7. What this campaign does NOT claim

- **No runtime verdict from any Class 2 row** — now backed by RT-D's measured noise floor, not
  only by the design's rule.
- The beta4 archive **predates the governor**, so every cross-era comparison carries an app-side
  confound larger than "production text moved". The design's premise that frozen *cell text*
  controls the app half is **false** — the governor sits outside the cell text and applies to all
  cells equally. This correction is owed to the spec's Class 1a/1b definition.
- **RT-G is NOT RUN.** No claim of any kind is made about the #338 guard on hardware.
- Nothing is promoted on any row.

## 8. Contents

`artifacts/` — every run's `latest.json`, named by run directory.
`attended/` — the three attended battery artifacts (RT-C/D/E), as delivered from the device.
`logs/` — per-run console logs and the Track U sweep log.
