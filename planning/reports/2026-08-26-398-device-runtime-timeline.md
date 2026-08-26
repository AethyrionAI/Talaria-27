# The device runtime timeline — measured, not inferred (item 398-A)

**Date:** 2026-08-26 · **Lane:** 398 (runtime probes) · **Host:** Mac Mini M4

This is the evidence behind 398-A. The bar asked that a battery rate carry the
runtime it was measured on. It turned out that most of them already do, and the
ones that do not can be resolved by date — so what was missing was never an
annotation campaign, it was **the resolution path**. This file is that path.

---

## 1. The founding worry, answered

Owen raised item 398 as *"we based everything on beta 2 stuff and not what it's
evolved to."* **Measured: no battery in this project's history ran on a beta-2
or beta-3 device build.** The battery instrument did not exist yet.

The earliest battery of any kind is `runShapeBattery`, commit `b9094ea3`,
**2026-07-27** (#196's in-process rate battery); `runActionBattery` followed on
**2026-07-28** (`a6accab2`). By 07-27 the device had been on `24A5390f` for a
week. So the earliest battery rate that exists was measured on a build we
**still hold as a simulator runtime today**.

⚠️ **One-day seam worth knowing.** `BatteryRunStore` — the record that carries
`osVersion` — landed **2026-07-28** (`801e8728`), a day *after* the shape
battery. A run from 07-27 therefore has a rate and **no runtime field**; resolve
it by date against §2 like any pre-artifact run. (This correction is the lane's
own discipline applied to itself: the first draft of this file dated the earliest
battery to 07-28 by reading the wrong instrument's origin.)

The worry was reasonable and the answer is better than the worry. What is
genuinely true is narrower and is in §4.

## 2. The timeline

Two independent sources, cross-checked against each other. Neither was
inferred.

| device build | window (measured) | evidence | twin runtime held? |
|---|---|---|---|
| `24A5355q` | 2026-06-08 → 06-13 | logd | no |
| `24A5370h` | 2026-06-23 → 07-05 | logd | no |
| `24A5380h` | 2026-07-06 → 07-20 21:24 | logd | no |
| `24A5390f` | 2026-07-20 21:42 → 08-11 06:25 | logd | **yes — beta4 runtime** |
| `24A5408d` | 2026-08-11 07:21 → 08-15 | logd + 53 artifacts | **yes — beta5 runtime** |
| `24A5418b` | ≤2026-08-17 15:55 → 08-24 | logd + 4 artifacts | **no** |
| iOS 27 beta 7 | 2026-08-24 PM → now | Owen's word only | `24A5423a` held; **string unconfirmed** |

**Source A — `Extra/logd.0.log` inside a collected device logarchive.** It is a
rolling log that survives OS updates, and every `assertion failed: <build>` line
stamps the build the device was running at that moment. **71** such lines span
June to August, collapsing to **22** distinct date+build rows. *(An earlier draft
said 37, which was the count of unique full-TIMESTAMP rows — a different
question, and the kind of number that reads as a measurement while answering
something else.)*

**Source B — the run artifacts themselves.** `BatteryRunStore` and
`InstrumentConductor` both record
`ProcessInfo.processInfo.operatingSystemVersionString`, which on iOS renders as
`"Version 27.0 (Build 24A5408d)"` — **the build is in there**. Across
`planning/reports/`, 53 files carry `24A5408d` and 4 carry `24A5418b`. No other
build appears in any artifact.

**They agree.** Source B puts the device on `24A5408d` through 2026-08-15;
source A puts it on `24A5418b` by 2026-08-17 15:55. Neither contradicts the
other, and together they bound the beta-6 transition to a **two-day window,
2026-08-15 → 08-17**.

### The control

An archive collected on **2026-08-15** (`340g`) contains the whole history up to
`24A5408d` and **no `24A5418b` line**. An archive collected on **2026-08-22**
(`talaria-138e`) contains the identical history **plus** the `24A5418b` line. An
archive that predates a transition cannot see it and one that postdates it can —
so the extraction is reading real history rather than pattern-matching noise.

## 3. Two corrections to item 398's own header

Both are provenance errors, and both matter because the header is what the next
reader trusts.

1. **The source is not `callservicesd`'s `BuildVersion`.** It is
   `Extra/logd.0.log`'s `assertion failed:` line. A predicate query against
   `callservicesd` returns nothing on the very archive the entry cites. This is
   the house rule about confirming which logger emits a line before making it a
   bar — a verification step keyed on a marker its component cannot emit is a
   step that always fails.
2. **The date is not 2026-08-22.** That is when the archive was *collected*. The
   `24A5418b` line inside it is stamped **2026-08-17 15:55:40**. So the skew
   opened on **Aug 17** and was noticed on Aug 22 — a **seven-day** window
   (Aug 17 → Aug 24), not the "unknown number of days" the entry recorded.

## 4. What is actually true about the skew

Stated precisely, because the loose version has been repeated:

- **The device and the simulators were an EXACT match for most of the
  measurement era.** Jul 20 → Aug 11 the device ran `24A5390f`; Aug 11 → Aug 15
  it ran `24A5408d`. Both are runtimes still on this Mac. Every battery rate from
  those windows was measured against a build we hold.
- **The real skew is one seven-day window**, Aug 17 → Aug 24, on `24A5418b` —
  a build we never held and cannot obtain.
- **It is not closed now, only narrowed.** The device is on beta 7 by Owen's
  word; the sim runtime `24A5423a` is beta-7 vintage. **Nobody has compared the
  two build strings**, and the device's current build is unmeasured because the
  newest logarchive on this Mac (Aug 22) predates the upgrade.

## 5. The resolution path (this is the deliverable)

To attach a runtime to any battery rate:

1. **Run dated 2026-07-28 or later, artifact still present** — read it out of the
   artifact. The field is `osVersion` and it contains the build:
   ```bash
   grep -rhoE '"osVersion" : "[^"]+"' planning/reports/<run>
   ```
2. **Artifact gone, or run predates the artifacts** — resolve the run's date
   against the table in §2.
3. **No battery predates 2026-07-28.** If a rate seems to, it is not a battery
   rate.

To measure the device's build directly from a fresh logarchive:

```bash
grep -hoE "^[0-9-]{10}.*assertion failed: 24A5[0-9A-Za-z]{3,4}" \
    <archive>.logarchive/Extra/logd.0.log | sort -u | tail -3
```

Require the `assertion failed:` prefix. A bare `24A5[0-9A-Za-z]{3,4}` grep also
matches 8-character hex addresses — `24A52CBE` and `24A5DF4E` both turned up in
this sweep and neither is a build.

## 6. Consequence for the two rates 398-B names

- **The #343 canary is resolved: `24A5408d`.** All 30-plus artifacts of that
  2026-08-15 campaign carry it. An earlier reading of this lane put the canary
  inside the unresolved Aug-11-to-Aug-17 window; the artifacts close it, and the
  logd line does not contradict them.
- **The #215 routing contrast (run `F486F103`, 2026-08-01) resolves to
  `24A5390f`** by date — inside the Jul-20-to-Aug-11 window. Note that this run
  also predates the governor (2026-08-02), so it is governor-free, which is the
  separate axis the measurement-discipline rule already covers.

Both therefore have a known runtime, and **neither was measured on the runtime
the device runs today**. That is what 398-B is for.
