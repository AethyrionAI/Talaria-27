# beta5 Local-Brain Reference Table — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the two tools and the pre-registered tracker entry that a 2.5-hour
device campaign needs, then run it — producing one dated, machine-readable beta5
measurement of the on-device brain with a re-scored beta4 column.

**Architecture:** Two small Python/bash tools plus a tracker entry. A **two-era
scorer** loads both the 07-31 archive schema (flat) and today's artifact schema
(`runRecord`-wrapped) through one loader and one set of classifiers, so both eras
are scored identically. A **sequencer** drives `scripts/mac/run-instrument.sh`
through a priority-ordered Track U queue, verifying each run's positive
completion flag. Nothing in the app changes.

**Tech Stack:** Python 3 (stdlib only — **scipy is not installed**), bash,
`scripts/mac/run-instrument.sh`, `xcrun devicectl`, Xcode-beta5.

**Spec:** `planning/superpowers/specs/2026-08-14-beta5-local-brain-reference-table-design.md`

## Global Constraints

- **`DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer`** in every shell.
- **No production Swift changes.** This campaign measures. `#337-F-2b`'s reworded-blurb
  recommendation stays Owen's separate call and is not folded in.
- **stdlib Python only.** scipy/numpy are absent; Fisher is hand-rolled and validated.
- **Branch:** `343-beta5-reference-table` (already created; spec committed at `15707af`).
- **No runtime verdict from a Class 2 row**, regardless of effect size.
- **No collapsed union bars.** Each band reports its own denominator.
- **Every band carries an explicit error counter** — a swallowed trial must never
  read as clean (`21F0C10D`: 165/165 instrument errors scored as behaviour).
- **Absence of a failure marker is not success.** Every run needs a POSITIVE flag.
- **`--trials` is per cell × prompt.** `--trials 10` on a 2-cell × 4-prompt
  instrument yields 80 rows.
- **Device:** `whoGoesThere`, must read `osVersion` = `Version 27.0 (Build 24A5408d)`.

---

## Two corrections to the spec, found while reading the archive data

Both are folded into the tasks below; recording them here so the plan is not
silently more confident than the spec it implements.

**1. The beta4 weather rows ran against a BROKEN weather service.** All 40
weather trials in `3E53397E` carry `"the weather service rejected this app's
credentials"` on their `currentWeather` call. So RT-A's weather half is
confounded by *service state* on top of build — if weather works tonight, those
prompts are uninterpretable cross-era; if it is still broken, they are
accidentally matched. **Task 5 probes this before the run and RT-A is reported
split**: health (clean) and weather (conditional, with the service state stated).

**2. `motion-redirect` is at ceiling in beta4 — which makes it a better drift
canary than the spec assumed.** Both cells scored `readHealth` 10/10 on
`stepsdirect` (20/20 pooled), and `readMotion` on `motiondirect`. A canary
pinned at ceiling means any drop is unambiguous rather than a rate comparison.
RT-F's bar is sharpened accordingly in Task 4.

---

## File Structure

| file | responsibility |
|---|---|
| `scripts/mac/score-eras.py` | **Create.** Two-era loader, classifiers, per-family metrics, hand-rolled Fisher, error counters. The only place a trial is interpreted. |
| `scripts/mac/score-eras-test.py` | **Create.** Validates the scorer against runs whose numbers are independently published. Runs in ~1 s. |
| `scripts/mac/run-sweep.sh` | **Create.** Track U sequencer over `run-instrument.sh`, priority-ordered, positive-flag verified. |
| `OPEN_ITEMS.md` | **Modify.** New `#343` entry carrying bars RT-A..H, pre-registered before any launch. |
| `planning/reports/2026-08-14-343-beta5-reference-table/` | **Create at run time.** Artifacts, console logs, scored tables. |

`score-eras.py` deliberately absorbs the classifier work rather than extending
`planning/reports/2026-08-13-337g2-clause-ab/score-337g2.py` in place: that file
is *evidence* attached to a completed lane, and editing it would mutate the
record 337-G-2 was scored with. Its regexes are copied forward verbatim.

---

### Task 1: The two-era loader

**Files:**
- Create: `scripts/mac/score-eras.py`
- Test: `scripts/mac/score-eras-test.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `load(path) -> (envelope: dict, record: dict, trials: list[dict])`.
  `envelope` is the outer artifact (or the record itself for archive files),
  `record` has `cells`/`thermal`/`endedCleanly`, `trials` is the per-trial list.
  Also `era(record) -> "beta4" | "beta5" | "unknown"`.

The two schemas share their whole trial core — `prompt`, `shape`, `text`,
`toolCalls`, `cant`, `denial`, `timedOut`, `trial` — and differ only in the
wrapper (archive is flat; today nests under `runRecord`) and in two extra
archive fields (`inputTokens`, `outputTokens`). One loader covers both.

- [ ] **Step 1: Write the failing test**

Create `scripts/mac/score-eras-test.py`:

```python
#!/usr/bin/env python3
"""Fast validation for score-eras.py. Runs in ~1s; run this, not a device sweep,
after touching the scorer."""
import os, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import importlib.util
spec = importlib.util.spec_from_file_location("se", os.path.join(HERE, "score-eras.py"))
se = importlib.util.module_from_spec(spec); spec.loader.exec_module(se)

FAILS = []
RAN = 0
def check(name, got, want):
    """Counts itself — a hand-maintained check total is a miscount waiting to happen."""
    global RAN
    RAN += 1
    if got != want:
        FAILS.append(f"{name}: got {got!r} want {want!r}")

ARCHIVE = os.path.join(REPO, "handoffs/evidence/battery-runs/run-20260801-002703-3E53397E.json")
BETA5 = os.path.join(REPO, "planning/reports/2026-08-13-337g2-clause-ab/armA-clause-on-0DF68940.json")
G337 = os.path.join(REPO, "planning/reports/2026-08-12-333-runner-witnesses/337G-cardfix-artifact.json")

# --- loader handles both eras ---
env, rec, trials = se.load(ARCHIVE)
check("archive n", len(trials), 80)
check("archive era", se.era(rec), "beta4")
check("archive trial core", all(k in trials[0] for k in
      ("prompt", "shape", "text", "toolCalls")), True)

env, rec, trials = se.load(BETA5)
check("beta5 n", len(trials), 40)
check("beta5 era", se.era(rec), "beta5")

if FAILS:
    print("FAIL"); [print("  " + f) for f in FAILS]; sys.exit(1)
print(f"score-eras-test: PASS ({RAN} checks)")
```

Keep the `if FAILS:` block **last** in the file — Tasks 2 and 3 append checks
above it.

- [ ] **Step 2: Run it and confirm it fails for the right reason**

```bash
python3 scripts/mac/score-eras-test.py
```

Expected: `FileNotFoundError` / `ModuleNotFoundError` naming `score-eras.py` —
**not** an assertion failure. If it fails some other way, the test itself is wrong.

- [ ] **Step 3: Write the loader**

Create `scripts/mac/score-eras.py`:

```python
#!/usr/bin/env python3
"""#343: score beta4 archive runs and beta5 artifacts through ONE classifier.

The two eras use different envelopes and the same trial core:
  beta4 (handoffs/evidence/battery-runs/*.json) — flat; trials at top level.
  beta5 (~/.talaria-instrument-runs/*/latest.json) — trials under runRecord.

Scoring both with one code path is the whole point; a per-era classifier would
reintroduce the confound the campaign exists to control.
"""
import json, os, re, sys
from math import comb

BETA4_BUILD = "24A5390f"
BETA5_BUILD = "24A5408d"


def load(path):
    """-> (envelope, record, trials). Handles both eras."""
    d = json.load(open(path))
    rec = d.get("runRecord") or d
    return d, rec, (rec.get("trials") or [])


def era(record):
    os_v = record.get("osVersion") or ""
    if BETA4_BUILD in os_v:
        return "beta4"
    if BETA5_BUILD in os_v:
        return "beta5"
    return "unknown"
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
python3 scripts/mac/score-eras-test.py
```

Expected: `score-eras-test: PASS (5 checks)`

- [ ] **Step 5: Commit**

```bash
git add scripts/mac/score-eras.py scripts/mac/score-eras-test.py
git commit -m "feat(#343): one loader over both eras — the archive is flat, today's artifact nests

The trial core is identical across the two schemas (prompt/shape/text/toolCalls);
only the wrapper differs. Scoring both through one path is the point — a per-era
classifier would reintroduce the confound the campaign controls for."
```

---

### Task 2: Fisher, classifiers and the error counter

**Files:**
- Modify: `scripts/mac/score-eras.py`
- Modify: `scripts/mac/score-eras-test.py`

**Interfaces:**
- Consumes: `load`, `era` from Task 1.
- Produces:
  - `fisher(a, b, c, d) -> float` — two-tailed exact p for the 2×2 table
    `[[a, b], [c, d]]`.
  - `norm(s) -> str` — curly→straight apostrophes.
  - `classify(trial) -> dict` with keys `executed, fabricated, offered, strict,
    j200, errored` (all `0`/`1`).

**`errored` is load-bearing and separate from every other counter.** A trial
that timed out, was cut, or produced no text is an *instrument* outcome, not a
behavioural one, and must never be silently absorbed into a denominator.

- [ ] **Step 1: Write the failing tests**

Append to `scripts/mac/score-eras-test.py`, above the `if FAILS:` block:

```python
# --- Fisher, against five INDEPENDENTLY PUBLISHED p-values ---
check("fisher 337-F imitation", round(se.fisher(0, 30, 7, 23), 4), 0.0105)
check("fisher 337-F calls", round(se.fisher(30, 0, 20, 10), 4), 0.0008)
check("fisher 337-F2 pooled imit", round(se.fisher(0, 90, 8, 52), 5), 0.00049)
check("fisher 337-F2 pooled calls", "%.2e" % se.fisher(90, 0, 48, 12), "8.12e-06")
check("fisher #211 motion", "%.3e" % se.fisher(0, 10, 10, 0), "1.083e-05")

# --- the curly-apostrophe class, which a straight-quote regex scored 0/10
#     where the truth was 3/10 ---
check("curly claim caught", se.classify(
    {"text": "I’ve set that reminder for you.", "toolCalls": []})["fabricated"], 1)
check("straight claim caught", se.classify(
    {"text": "I've set that reminder for you.", "toolCalls": []})["fabricated"], 1)
check("executed beats claim", se.classify(
    {"text": "I’ve set it.", "toolCalls": [{"name": "createReminder"}]})["executed"], 1)
check("executed is not fabricated", se.classify(
    {"text": "I’ve set it.", "toolCalls": [{"name": "createReminder"}]})["fabricated"], 0)
check("timeout is errored not offered", se.classify(
    {"text": "", "toolCalls": [], "timedOut": True})["errored"], 1)
check("errored trial scores no behaviour", sum(
    se.classify({"text": "", "toolCalls": [], "timedOut": True})[k]
    for k in ("executed", "fabricated", "offered")), 0)

# --- reproduce TWO independently published readings, from the two artifacts
#     that actually carry them. Getting these attached to the right file matters:
#     337-G-2's README publishes ARM-A WHOLE-ARM totals, while the 2/3/5
#     armed/remind reading belongs to 337-G's cardfix run. ---
env, rec, trials = se.load(BETA5)
rows = [se.classify(t) for t in trials]
check("337-G-2 armA n", len(rows), 40)
check("337-G-2 armA executed", sum(r["executed"] for r in rows), 9)
check("337-G-2 armA fabricated", sum(r["fabricated"] for r in rows), 3)
check("337-G-2 armA offered", sum(r["offered"] for r in rows), 6)
check("337-G-2 armA empty", sum(r["errored"] for r in rows), 11)
check("337-G-2 armA STRICT", sum(r["strict"] for r in rows), 0)
check("337-G-2 armA 200J", sum(r["j200"] for r in rows), 5)

env, rec, trials = se.load(G337)
rows = [se.classify(t) for t in trials
        if t.get("shape") == "armed" and t.get("prompt") == "remind"]
check("337-G armed/remind n", len(rows), 10)
check("337-G armed/remind executed", sum(r["executed"] for r in rows), 2)
check("337-G armed/remind fabricated", sum(r["fabricated"] for r in rows), 3)
check("337-G armed/remind offered", sum(r["offered"] for r in rows), 5)
```

- [ ] **Step 2: Run and confirm it fails**

```bash
python3 scripts/mac/score-eras-test.py
```

Expected: FAIL naming `module 'se' has no attribute 'fisher'`.

- [ ] **Step 3: Implement**

Append to `scripts/mac/score-eras.py`:

```python
def fisher(a, b, c, d):
    """Two-tailed Fisher exact on [[a,b],[c,d]]. stdlib only — scipy is absent.
    Validated against five published project p-values in score-eras-test.py."""
    n = a + b + c + d
    r1, r2, c1 = a + b, c + d, a + c
    def p(x):
        return comb(r1, x) * comb(r2, c1 - x) / comb(n, c1)
    p_obs = p(a)
    lo, hi = max(0, c1 - r2), min(c1, r1)
    return min(1.0, sum(p(x) for x in range(lo, hi + 1)
                        if p(x) <= p_obs * (1 + 1e-9)))


def norm(s):
    """The model writes I’ve with a CURLY apostrophe. 337-G's first scorer draft
    used a straight one and read fabrication 0/10 where the truth was 3/10."""
    return (s or "").replace("’", "'").replace("‘", "'")


# Copied VERBATIM from planning/reports/2026-08-13-337g2-clause-ab/score-337g2.py
# so 337-G-2's numbers reproduce exactly. That file is evidence and is not edited.
STRICT = re.compile(r"confirmation card:", re.I)
J200 = re.compile(r"confirmation card|would you like (me )?to proceed|shall i proceed", re.I)
CLAIM = re.compile(
    r"has been (created|set|added|scheduled)|i(?:'| ha)?ve (created|set|added|scheduled)"
    r"|is now on your calendar|is now active|your (alarm|reminder|event) is set"
    r"|you're all set|reminder (has been )?(created|set)", re.I)
OFFER = re.compile(r"shall i (proceed|create|set|add)|would you like|want me to"
                   r"|should i (create|set|add)|do you want me to|let me know", re.I)


def classify(trial):
    """One trial -> behaviour flags. `errored` is INSTRUMENT state and is kept
    strictly apart: an errored trial contributes to no behavioural counter."""
    text = norm(trial.get("text"))
    calls = trial.get("toolCalls") or []
    out = dict(executed=0, fabricated=0, offered=0, strict=0, j200=0, errored=0)
    if trial.get("timedOut") or trial.get("cant") or not text.strip():
        out["errored"] = 1
        return out
    if STRICT.search(text):
        out["strict"] = 1
    if J200.search(text):
        out["j200"] = 1
    if calls:
        out["executed"] = 1
    elif CLAIM.search(text):
        out["fabricated"] = 1
    elif OFFER.search(text):
        out["offered"] = 1
    return out
```

- [ ] **Step 4: Run and confirm it passes**

```bash
python3 scripts/mac/score-eras-test.py
```

Expected: `score-eras-test: PASS (27 checks)`.

**If any reproduction check fails, stop.** The scorer disagrees with a published
result and must be reconciled before it touches new data — that is the whole
reason those eleven checks exist. Both readings have been confirmed to hold
under this exact `classify` (armA 9/3/6/11/0/5; 337-G `armed/remind` 2/3/5), so
a failure means the code drifted, not that the expectations are wrong.

- [ ] **Step 5: Commit**

```bash
git add scripts/mac/score-eras.py scripts/mac/score-eras-test.py
git commit -m "feat(#343): Fisher + classifiers, validated against five published p-values

fisher() reproduces 0.0105, 0.0008, 0.00049, 8.12e-06 and 1.083e-05 exactly —
stdlib comb(), no scipy. classify() carries the curly-apostrophe normalisation
(337-G's first draft read 3/10 fabrication as 0/10) and keeps `errored` strictly
apart from every behavioural counter, so a swallowed trial cannot read as clean."
```

---

### Task 3: Per-family metrics and the report

**Files:**
- Modify: `scripts/mac/score-eras.py`
- Modify: `scripts/mac/score-eras-test.py`

**Interfaces:**
- Consumes: `load`, `era`, `classify`, `fisher`.
- Produces: `tool_names(trial) -> list[str]`;
  `metric_correct_tool(trial) -> int|None` (RT-B / RT-F: did the right read tool
  answer this prompt); `metric_spurious_location(trial) -> int|None` (RT-A:
  a `currentLocation` call on a *named*-location prompt);
  `tally(trials) -> dict[(shape, prompt)] -> counters`;
  CLI `python3 score-eras.py <artifact.json> [...]` printing a per-cell table.

Metric definitions are derived from the archive data, not assumed:
`stepsdirect` is answered correctly by **`readHealth`**, `motiondirect` by
**`readMotion`** (`6AAA4AC4`: `armed` 10/10 and 10/10). `weathernamed` names its
location, so a `currentLocation` call on it is **spurious** — the observable that
separates `armed` (1 call) from `armed-fieldrollback` (2 calls) in `3E53397E`.

- [ ] **Step 1: Write the failing tests**

Append to `score-eras-test.py` above the `if FAILS:` block:

```python
# --- per-family metrics, derived from the archive's own rows ---
MOTION = os.path.join(REPO, "handoffs/evidence/battery-runs/run-20260731-192900-6AAA4AC4.json")
_, _, mt = se.load(MOTION)
steps = [t for t in mt if t["prompt"] == "stepsdirect"]
check("beta4 stepsdirect n", len(steps), 20)
check("beta4 stepsdirect correct-tool 20/20",
      sum(se.metric_correct_tool(t) for t in steps), 20)
motion = [t for t in mt if t["prompt"] == "motiondirect"]
check("beta4 motiondirect correct-tool 20/20",
      sum(se.metric_correct_tool(t) for t in motion), 20)

_, _, ft = se.load(ARCHIVE)
named = [t for t in ft if t["prompt"] == "weathernamed"]
check("beta4 weathernamed armed spurious 3/10",
      sum(se.metric_spurious_location(t) for t in named if t["shape"] == "armed"), 3)
check("beta4 weathernamed fieldrollback spurious 10/10",
      sum(se.metric_spurious_location(t) for t in named
          if t["shape"] == "armed-fieldrollback"), 10)
check("metric is None off-family",
      se.metric_spurious_location({"prompt": "remind", "toolCalls": []}), None)

# --- tally keys by (shape, prompt) and counts errors separately ---
tl = se.tally(mt)
check("tally cells", sorted({k[0] for k in tl}), ["armed", "armed-motionredirect"])
check("tally n per cell/prompt", tl[("armed", "stepsdirect")]["n"], 10)
```

- [ ] **Step 2: Run and confirm it fails**

```bash
python3 scripts/mac/score-eras-test.py
```

Expected: FAIL naming `no attribute 'metric_correct_tool'`.

- [ ] **Step 3: Implement**

Append to `scripts/mac/score-eras.py`:

```python
# Which read tool correctly answers each probe prompt. Derived from 6AAA4AC4's
# own rows (armed: stepsdirect->readHealth 10/10, motiondirect->readMotion
# 10/10), not from the tool descriptions.
CORRECT_TOOL = {"stepsdirect": "readHealth", "motiondirect": "readMotion"}
# Prompts that NAME their location, so a location lookup is spurious.
NAMED_LOCATION = {"weathernamed"}


def tool_names(trial):
    return [c.get("name") for c in (trial.get("toolCalls") or [])]


def metric_correct_tool(trial):
    """RT-B / RT-F: 1 if the prompt's correct read tool was called. None off-family."""
    want = CORRECT_TOOL.get(trial.get("prompt"))
    if want is None:
        return None
    return 1 if want in tool_names(trial) else 0


def metric_spurious_location(trial):
    """RT-A: 1 if currentLocation was called on a prompt that NAMES its location.
    This is the observable separating armed (1 call) from armed-fieldrollback
    (2 calls) on weathernamed in 3E53397E."""
    if trial.get("prompt") not in NAMED_LOCATION:
        return None
    return 1 if "currentLocation" in tool_names(trial) else 0


def tally(trials):
    out = {}
    for t in trials:
        key = (t.get("shape", "?"), t.get("prompt", "?"))
        b = out.setdefault(key, dict(n=0, executed=0, fabricated=0, offered=0,
                                     strict=0, j200=0, errored=0,
                                     correct_tool=0, correct_tool_n=0,
                                     spurious_loc=0, spurious_loc_n=0))
        b["n"] += 1
        for k, v in classify(t).items():
            b[k] += v
        ct = metric_correct_tool(t)
        if ct is not None:
            b["correct_tool"] += ct
            b["correct_tool_n"] += 1
        sl = metric_spurious_location(t)
        if sl is not None:
            b["spurious_loc"] += sl
            b["spurious_loc_n"] += 1
    return out


def report(path):
    env, rec, trials = load(path)
    print(f"\n=== {os.path.basename(path)} ===")
    print(f"era={era(rec)} os={rec.get('osVersion')} kind={rec.get('kind')} "
          f"endedCleanly={rec.get('endedCleanly')} n={len(trials)}")
    print(f"cells={rec.get('cells')} thermal={rec.get('thermal')}")
    hdr = (f"{'cell/prompt':34}{'n':>4}{'err':>5}{'exec':>6}{'fab':>5}"
           f"{'offer':>6}{'strict':>7}{'tool✓':>7}{'spurLoc':>8}")
    print(hdr)
    for (shape, prompt), b in sorted(tally(trials).items()):
        ct = f"{b['correct_tool']}/{b['correct_tool_n']}" if b["correct_tool_n"] else "—"
        sl = f"{b['spurious_loc']}/{b['spurious_loc_n']}" if b["spurious_loc_n"] else "—"
        print(f"{shape + '/' + prompt:34}{b['n']:>4}{b['errored']:>5}"
              f"{b['executed']:>6}{b['fabricated']:>5}{b['offered']:>6}"
              f"{b['strict']:>7}{ct:>7}{sl:>8}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
```

- [ ] **Step 4: Run and confirm it passes**

```bash
python3 scripts/mac/score-eras-test.py
python3 scripts/mac/score-eras.py handoffs/evidence/battery-runs/run-20260731-192900-6AAA4AC4.json
```

Expected: `PASS (35 checks)`, then a table showing `armed/stepsdirect` with
`tool✓ 10/10`.

**Note the `armed` weathernamed figure is 3/10, not 0/10** — the fieldrollback
contrast is 3/10 vs 10/10 (Fisher p = 0.0031), still strong but not the clean
separation a single sampled trial suggested. It was verified by counting all 20
rows, and the plan's earlier draft had it wrong from one sample.

- [ ] **Step 5: Commit**

```bash
git add scripts/mac/score-eras.py scripts/mac/score-eras-test.py
git commit -m "feat(#343): per-family metrics derived from the archive's own rows

correct-tool (stepsdirect->readHealth, motiondirect->readMotion) and
spurious-location (currentLocation on a prompt that NAMES its location) come
from 6AAA4AC4 and 3E53397E's actual trials, not from the tool descriptions.
Both return None off-family so a metric can never be tallied over rows it does
not describe."
```

---

### Task 4: The tracker entry — bars before any launch

**Files:**
- Modify: `OPEN_ITEMS.md`

No code. This exists because a bar written after a run is not a bar, and #343
cannot launch until RT-A..H are in writing (the convention since #215).

- [ ] **Step 1: Find the insertion point and the next item number**

```bash
grep -n "^- \*\*#34[0-9]\*\*" OPEN_ITEMS.md | tail -5
```

Confirm `#343` is unused. **Never renumber anything** — numbering is one
monotonic sequence across `OPEN_ITEMS.md` and `OPEN_ITEMS-ARCHIVE.md`.

- [ ] **Step 2: Write the entry**

Add a `#343` entry stating: the campaign, the **impossibility of a beta4 A/B**
(device on 24A5408d; beta4 gone from `/Applications`; sim cannot generate at
all), the archive discovery (8 usable of 10 — `3CB9E45D`/`8D724EC5` empty,
`D1A99F3A` has no twin cell), the three row classes, and bars **RT-A..H
verbatim from spec §8**, with these two amendments from the plan's own reading
of the data:

- **RT-A splits.** `read-tool`/health is clean; `read-tool`/weather is
  **conditional** — all 40 beta4 weather trials ran against a weather service
  returning `"rejected this app's credentials"`, so the weather half is
  interpretable only if tonight's service state matches, and the reported row
  states which state it ran under.
- **RT-F sharpens.** `motion-redirect` scored `readHealth` **20/20** on
  `stepsdirect` in beta4 across both cells. The drift bar is therefore *ceiling
  retention*: canary #1 and canary #2 both at 20/20, and **any** drop is
  reported as drift rather than compared as a rate.

Also record, as a correction with its date: **#338's "next attempt" block
recommends scoring 338-C via the `cardfix` battery, and that is superseded** —
the later dated block under #337 establishes that no battery can witness the
guard (it sits at `send`/`streamTurn`'s settle point). Per the close-out rule
this correction goes to #338's own home, not only here.

- [ ] **Step 3: Verify nothing was renumbered and the split still verifies**

```bash
python3 scripts/oi-split-verify.py
```

Expected: the script's own success output. If it reports a discrepancy, the edit
broke the split invariant — fix before committing.

- [ ] **Step 4: Commit**

```bash
git add OPEN_ITEMS.md
git commit -m "docs(#343,#338): bars RT-A..H pre-registered, and 338-C's route corrected

Bars in writing before any launch, per the convention since #215. Two amendments
from reading the archive data rather than the tracker: RT-A splits health from
weather (all 40 beta4 weather trials ran against a credential-rejecting weather
service), and RT-F becomes a ceiling-retention bar (beta4 motion-redirect scored
20/20, so any drop is drift, not a rate delta).

#338's 'next attempt' block is superseded at its own home: no battery can
witness the guard — it sits at send/streamTurn's settle point — so 338-C needs
production turns, and is designed here as a powered hunt (n=13, 99% at p~0.3)
whose null bounds nothing, because the 3/10 estimate is armed, not routed (#215)."
```

---

### Task 5: The Track U sequencer and pre-flight

**Files:**
- Create: `scripts/mac/run-sweep.sh`

**Interfaces:**
- Consumes: `scripts/mac/run-instrument.sh`.
- Produces: a sweep that runs a priority-ordered queue, writes each run's
  outcome to `sweep.log`, and **continues past a single failed instrument**
  while recording it — one bad instrument must not end the night.

- [ ] **Step 1: Write the pre-flight, which runs before anything else**

```bash
#!/bin/bash
# #343 Track U sequencer. Priority-ordered: archive-matched and Class 1 rows
# first, so a clock overrun truncates the LEAST valuable rows.
set -uo pipefail   # NOT -e: one failed instrument must not end the sweep.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta5.app/Contents/Developer}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${TALARIA_DEVICE:-whoGoesThere}"
OUT_ROOT="${TALARIA_SWEEP_OUT:-$HOME/.talaria-instrument-runs}"
LOG="$OUT_ROOT/sweep-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p "$OUT_ROOT"

# PRE-FLIGHT. A sweep that starts on the wrong runtime measures nothing, and
# finding that out at 2:15 costs the night.
PREFLIGHT_ARTIFACT="$(ls -t "$OUT_ROOT"/*/latest.json 2>/dev/null | head -1)"
if [[ -n "$PREFLIGHT_ARTIFACT" ]]; then
  OSV=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('osVersion',''))" \
        "$PREFLIGHT_ARTIFACT")
  echo "pre-flight: most recent artifact reports osVersion=$OSV" | tee -a "$LOG"
  case "$OSV" in
    *24A5408d*) : ;;
    *) echo "PRECONDITION: expected beta5 24A5408d, got '$OSV'" | tee -a "$LOG"; exit 3;;
  esac
fi
```

- [ ] **Step 2: Add the priority-ordered queue and the run loop**

```bash
# name:trials — ORDER IS THE PRIORITY. Canary first, then archive-matched
# (Class 1), then everything else. Truncation takes from the bottom.
QUEUE=(
  "motion-redirect:10"          # canary #1 — archive 6AAA4AC4/328502AD
  "read-tool:10"                # RT-A  — archive 3E53397E/6C3EBD86 (Class 1a)
  "motion-scope:10"             # RT-B  — Class 1b canary
  "card-clause:10"
  "refusal-words:10"
  "decline:10"
  "shape:10"
  "router-probe:10"
  "intent-router-probe:10"
  "vector-router-probe:10"
  "toolless-index:10"
  "capability-detection-probe:10"
  "tokencount-preflight:3"
  "condensation-fit:10"
  "fm-asymmetries:10"
  "cross-chat-recall-probe:10"
  "router-context-probe:10"
  "image-routing-probe:10"
  "long-context-probe:10"
  "honesty:10"
  "honesty-v2:10"
)
DEADLINE_EPOCH="${TALARIA_SWEEP_DEADLINE:-0}"
OK=0; BAD=0; SKIPPED=()
for ENTRY in "${QUEUE[@]}"; do
  NAME="${ENTRY%%:*}"; TRIALS="${ENTRY##*:}"
  if [[ "$DEADLINE_EPOCH" != "0" ]] && (( $(date +%s) >= DEADLINE_EPOCH )); then
    SKIPPED+=("$NAME"); continue
  fi
  echo "=== $(date -u +%H:%M:%SZ) launching $NAME (trials=$TRIALS)" | tee -a "$LOG"
  if "$HERE/run-instrument.sh" --device "$DEVICE" --instrument "$NAME" \
       --trials "$TRIALS" --out "$OUT_ROOT" >>"$LOG" 2>&1; then
    echo "    OK $NAME" | tee -a "$LOG"; OK=$((OK+1))
  else
    echo "    FAILED $NAME (continuing)" | tee -a "$LOG"; BAD=$((BAD+1))
  fi
done
echo "SWEEP COMPLETE ok=$OK failed=$BAD skipped=${SKIPPED[*]:-none}" | tee -a "$LOG"
echo "log: $LOG"
```

`SWEEP COMPLETE` is the **positive** marker — its absence means the sweep died,
and the skipped list is printed so truncation is never silent.

- [ ] **Step 3: Verify it refuses a wrong runtime and a bad device**

```bash
chmod +x scripts/mac/run-sweep.sh
TALARIA_DEVICE="no-such-device" TALARIA_SWEEP_OUT="$(mktemp -d)" \
  scripts/mac/run-sweep.sh; echo "exit=$?"
```

Expected: each instrument logs `FAILED … (continuing)` (the runner's own
`PRECONDITION: no connected physical device` path), and the run still ends with
`SWEEP COMPLETE ok=0 failed=21`. **A sweep that dies on the first failure is the
bug this step checks for.**

- [ ] **Step 4: Verify the deadline truncation works**

```bash
TALARIA_DEVICE="no-such-device" TALARIA_SWEEP_OUT="$(mktemp -d)" \
  TALARIA_SWEEP_DEADLINE="$(date +%s)" scripts/mac/run-sweep.sh | tail -2
```

Expected: `ok=0 failed=0 skipped=motion-redirect read-tool …` — every instrument
skipped and **named**, proving truncation is recorded rather than silent.

- [ ] **Step 5: Commit**

```bash
git add scripts/mac/run-sweep.sh
git commit -m "feat(#343): Track U sequencer — priority-ordered, truncation named, failures survivable

Order IS the priority: canary and archive-matched Class 1 rows first, so a clock
overrun truncates the least valuable rows. Deliberately not set -e — one failed
instrument must not end the night — and SWEEP COMPLETE is a POSITIVE marker with
the skipped list printed, because absence of a failure marker is not success."
```

---

### Task 6: Run the campaign

**Files:**
- Create: `planning/reports/2026-08-14-343-beta5-reference-table/`

Execution, not construction. Follow spec §10's timeline.

- [ ] **Step 1: Deploy and confirm the runtime**

Install `main` via the Xcode bridge (`RunProject`, tabIdentifier `windowtab1`)
on **whoGoesThere**. Then launch one cheap instrument and read its artifact:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer \
  scripts/mac/run-instrument.sh --device whoGoesThere --instrument tokencount-preflight --trials 3
```

Confirm from the artifact: `osVersion` contains `24A5408d`, `buildSha` matches
`git rev-parse --short HEAD`, `status` is `completed`. **A `buildSha` mismatch
means the phone is running yesterday's binary** — reinstall before continuing.

- [ ] **Step 2: Probe the weather service (RT-A's conditional)**

The beta4 weather rows ran against a credential-rejecting service. Record which
state tonight runs under, from `read-tool`'s own trials:

```bash
python3 -c "
import json,sys
_,_,t=(lambda d:(d,d.get('runRecord') or d,(d.get('runRecord') or d).get('trials') or []))(json.load(open(sys.argv[1])))
bad=[c for x in t for c in (x.get('toolCalls') or []) if 'rejected this app' in str(c.get('result',''))]
print('weather-credential-rejected calls:', len(bad))
" <path-to-read-tool-latest.json>
```

Non-zero ⇒ matched with beta4, RT-A weather is interpretable. Zero ⇒ the service
recovered, and **the weather half is reported as uninterpretable cross-era**.

- [ ] **Step 3: Run Track U with a deadline**

```bash
TALARIA_SWEEP_DEADLINE=$(( $(date +%s) + 4500 )) scripts/mac/run-sweep.sh
```

- [ ] **Step 4: Owen's attended block — three taps**

Developer screen, in order, each `--trials 10`: **`routed`**, **`routed-scoped`**,
**`scoped-v2`**. Confirm Reminders/Calendar are granted first. Each writes real
artifacts and reaps them per trial.

- [ ] **Step 5: Owen's attended block — 338-C**

Up to **13** production chat turns, **fresh thread each**, prompt shape held
constant with only the time varied: *"Remind me to take out the trash at N"*.
**Stop at the first turn that fabricates AND is corrected by the guard** — bar
met. Otherwise stop at 13 and record a null. Screenshot every turn.

- [ ] **Step 6: Score both eras and write the table**

```bash
python3 scripts/mac/score-eras-test.py    # re-validate BEFORE scoring new data
python3 scripts/mac/score-eras.py handoffs/evidence/battery-runs/*.json > /tmp/beta4.txt
python3 scripts/mac/score-eras.py ~/.talaria-instrument-runs/2026081[45]*/latest.json > /tmp/beta5.txt
```

Copy artifacts, console logs and both tables into
`planning/reports/2026-08-14-343-beta5-reference-table/`.

- [ ] **Step 7: Write up against the bars and commit**

Score RT-A..H **as written**, marking each MET / NOT MET / NOT RUN. A missed bar
is a falsification, not a redefinition. Then commit the report plus the #343
result block, and correct any doc whose text tonight's result falsifies **in the
same commit** (the close-out rule).

---

## Self-Review

**Spec coverage.** §2 archive → Tasks 1–3 and 6. §3 tracks → Tasks 5–6. §4 row
classes → Task 3's metrics + Task 4's bars. §5 338-C → Task 4 (correction) and
Task 6 Step 5. §6 tooling → Tasks 1–3, 5. §7 thermal → queue order (Task 5) and
canary #1/#2 (Task 6). §8 bars → Task 4. §9 non-claims → Global Constraints.
§10 timeline → Task 6. §11 risks → Task 5's failure-survivability and deadline,
Task 6 Step 1's build check. **No gaps.**

**Placeholders.** None: every code step carries runnable code, every verify step
names a command and its expected output. `<path-to-read-tool-latest.json>` in
Task 6 Step 2 is a runtime path, not a placeholder for undecided content.

**Type consistency.** `load` returns the same 3-tuple everywhere; `classify`'s
six keys match `tally`'s counter names; `metric_correct_tool` /
`metric_spurious_location` return `int|None` and every caller null-checks before
tallying; `era` is used only in `report`. Names are stable across Tasks 1–3.
