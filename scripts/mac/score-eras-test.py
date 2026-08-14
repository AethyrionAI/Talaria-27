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

if FAILS:
    print("FAIL"); [print("  " + f) for f in FAILS]; sys.exit(1)
print(f"score-eras-test: PASS ({RAN} checks)")
