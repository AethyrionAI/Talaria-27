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
