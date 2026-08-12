# Plan — the unattended instrument runner (triage build #1)

**Written 2026-08-11 at Owen's request.** Target: ready to dispatch tomorrow after work.

> **✅ FILED AND ADJUSTED 2026-08-12 — this is now tracker #333; read that entry for the
> current design.** Four deltas, decided after a code-map pass and approved by Owen the
> same day: (1) §3b's serializer is mostly BUILT — `BatteryRunStore` already writes atomic
> JSON with an `endedCleanly` completion flag; the build adds header fields + a fixed-path
> result envelope, and **`TALARIA_RESULT_PATH` is dropped** in favour of a fixed
> `Documents/InstrumentRuns/` path. (2) §3a's trigger generalizes #196's shipped
> `runAutoBatteryIfArmed` precedent through an instrument REGISTRY with capability flags,
> and env delivery on device is already proven (`DEVICECTL_CHILD_*`,
> `HANDOFF-2026-07-28-OVERNIGHT.md`). (3) §5's device refusal is sharpened: alarm-flagged
> instruments refuse under the trigger unconditionally; EventKit-flagged refuse on any
> iPad; a refusal writes a REFUSED artifact. (4) a Mac-side harness script
> (`scripts/mac/run-instrument.sh`) with a hard timeout is a first-class deliverable.
> Bars 333-A..H pre-registered at the entry supersede §4's sketch.

**What it is not.** This is **not** #331. #331 is data *containment* — a dedicated
calendar/reminders list, wholesale reap, and the alarm answer; it makes writes safe. This
plan makes the instruments **reachable**. Neither substitutes for the other, and after
Owen's 2026-08-11 data ruling they are independent: calendar and reminder writes on his
phone are already contained by a setting he made, so **this build no longer waits on #331**.

---

## 1. The problem, stated precisely

Every measurement instrument this project needs **already exists and already persists its
results.** `runActionBattery` and ~20 siblings live in `LocalChatBackend+Battery.swift`;
`BatteryRunStore.swift` persists per-trial records (`shape`, `prompt`, `trial`, `text`,
`cant`, `denial`, `toolCalls`, `route`, `routeFailed`, `error`) and
`BatteryResultsScreen.swift` reads them back for a human.

**What is missing is only the two ends of the pipe:**

1. **No way in.** Each instrument is a SwiftUI `Button` in `DeveloperSettingsScreen.swift`
   with no accessibility identifier. A UI test cannot press what it cannot find, and there
   is no non-UI entry point at all.
2. **No way out.** `BatteryRunStore` is read by a screen, not by a process. Nothing emits a
   machine-readable artifact a test or a script can assert on, and nothing signals
   completion.

So the instruments are unreachable, not unbuilt. This is plumbing.

## 2. What one build unlocks

**~13 device bars**, per `DEVICE-BACKLOG-TRIAGE-2026-08-11.md` §2: **#199A, #205E, #208,
#210 residual, #210A, #211A, #225 B1–B4, #257's never-built tokenCount pre-flight, #279-F**
— plus every future battery, which is the part that compounds.

Post-ruling, most of these can run on **Shelley's iPad** (verified generating, §9a of the
triage) rather than Owen's phone — **except** any cell that writes calendar, reminders or
alarms, which is barred on that device absolutely. #225's B4 and #199A therefore stay on
`whoGoesThere`.

## 3. Design

### 3a. The way in — a launch-environment trigger
On launch, in `#if DEBUG` only, read:

- `TALARIA_RUN_INSTRUMENT=<name>` — the instrument, by a stable string
- `TALARIA_TRIALS=<n>` — trial count
- `TALARIA_RESULT_PATH=<path>` — where to write the artifact (see 3b)

and dispatch to the same call the button makes. **The button and the trigger must share
one code path**, not two — a trigger that reimplements a button is a second thing to keep
in sync, and this project has paid for that shape before.

Copy the buttons' existing discipline exactly rather than inventing it: they already set
`autoAcceptForBattery` / `autoDeclineForBattery` explicitly (never inheriting), set
`UIApplication.shared.isIdleTimerDisabled = true`, hold a `batteryRunning` mutual-exclusion
guard, and **clear all of it at run end whatever the run armed**. The idle-timer line means
half of "plugged in and never sleeps" is already solved in shipped code.

### 3b. The way out — an artifact plus a completion signal
At run end write ONE JSON file to `TALARIA_RESULT_PATH` containing the run's
`BatteryRunStore` records plus a header: instrument name, trial count, start/end timestamps,
build sha, device model, OS build, and — importantly — **whether the run completed or
aborted**.

Completion must be **positively signalled**, never inferred from the file existing. A file
that exists because a run started is exactly the "absence of a failure marker is not
success" trap the lane gate was built to prevent. Write to a temp path and atomically move
on success, so a partial file cannot be mistaken for a finished one.

### 3c. The way to fetch it
`xcrun devicectl device copy from` pulls the artifact off the device after the run. The
harness asserts on the JSON; a human never reads a Console log to score a bar again.

## 4. Bars — to be pre-registered in the tracker entry before any code

Sketch only; the lane writes the real ones.

- **A** — the trigger runs the instrument and produces an artifact, on device, with no UI
  interaction and nobody watching.
- **B** — **the button and the trigger drive the same code path**, asserted structurally
  rather than by inspection.
- **C** — an aborted run is distinguishable from a completed one *in the artifact*, and a
  partial file is never mistaken for a finished one. **Witness this by killing a run
  mid-flight**, not by reasoning about it.
- **D** — the auto-accept / auto-decline flags are set explicitly on every path and cleared
  on every exit including the abort path. This is the one that protects real data.
- **E** — production is unchanged: no trigger surface outside `#if DEBUG`, and the Release
  build proves it (#218's rule — a green Debug suite cannot see a mis-set gate).
- **F** — `GATE: PASS`, count moved.

## 5. Hazards to build against, all previously measured

- **`tokenCount` concurrent with a live streaming turn KILLS the turn** (recorded in the FM
  surfaces memory). #257's pre-flight must run outside a turn, and the runner must not
  schedule it during one.
- **Auto-accept performs real writes.** Clearing the flags on the abort path is bar D for
  this reason; the buttons only clear them on the normal path today.
- **A device suite HANGS rather than fails when TCC has no record.** Any unattended run
  needs its grants verified first, and a hang must be detected by a timeout in the harness
  rather than by a human noticing a log stopped growing (measured: ~20 min parked, and the
  only tell was a log that stopped moving).
- **Model wall-clock on this hardware is not stable** — the same test measured 123.0 s,
  20.9 s and 16.9 s across three runs on two devices. Never pin a bar to elapsed time.
- **Shelley's iPad: no calendar, reminder or alarm cells, ever.** The runner should refuse
  by device, not by convention — if it can identify the host, it should hard-fail such a
  request rather than trusting the caller.

## 6. Sequencing

1. This build (trigger + artifact + fetch). Independent of #331 post-ruling.
2. Point it at the iPad for the write-free FM cluster; the phone keeps the write cells.
3. #331 lands in parallel and adds containment plus the alarm rule.
4. Then the ~13 bars become a queue rather than a plan.

**Estimated size:** small. Two entry points, one serializer, one fetch step, and the
discipline to make the button and the trigger share a path. The risk is not difficulty —
it is building a second code path that drifts from the first.
