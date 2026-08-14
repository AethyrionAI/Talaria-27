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
# NOTE: the check below is satisfied by a NO-OP — an empty-text timed-out trial
# scores zero behaviour whether or not the short-circuit exists. It is kept
# because it states the intent, but it proves nothing on its own; the checks
# that actually exercise the branch are in the `cant` section further down,
# added 2026-08-14 after a mutation test showed this one green against BOTH
# the old buggy condition and a classify() with no `return` at all.
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

# --- `cant` is BEHAVIOUR, not instrument state (#343 final review, 2026-08-14).
#     The app sets it by prefix-matching the MODEL'S OWN reply
#     (LocalChatBackend+Battery.swift:318), so folding it into `errored` deleted
#     real counts. Every check below is drawn from the cell where the deletion
#     was worst — 1835BBF9's armed-scopedv2/haiku, which IS the archived #214
#     composition-denial result RT-E exists to re-measure — and every one of
#     them goes RED against the old condition. That is the property the previous
#     "errored trial scores no behaviour" check could not have: it fed an
#     empty-text trial, which scores zero on every counter either way, so it
#     passed 35/35 against the bug it was supposed to guard. ---
CANT = os.path.join(REPO, "handoffs/evidence/battery-runs/run-20260731-223158-1835BBF9.json")
_, _, ct = se.load(CANT)
cant_cell = [t for t in ct if t.get("shape") == "armed-scopedv2"
             and t.get("prompt") == "haiku"]
# The fixture's own preconditions, asserted so a future data change cannot turn
# these checks into no-ops the way the one above became one.
check("cant fixture cell n", len(cant_cell), 10)
check("cant fixture is all-cant WITH real text",
      (sum(1 for t in cant_cell if t.get("cant")),
       sum(1 for t in cant_cell if (t.get("text") or "").strip()),
       sum(1 for t in cant_cell if t.get("timedOut"))), (10, 10, 0))
crows = [se.classify(t) for t in cant_cell]
check("cant is counted", sum(r["cant"] for r in crows), 10)
check("cant is NOT errored", sum(r["errored"] for r in crows), 0)
check("cant trials still score behaviour: offered 7/10",
      sum(r["offered"] for r in crows), 7)
check("whole run: cant does not delete offers",
      sum(se.classify(t)["offered"] for t in ct), 8)
check("whole run: cant does not delete executions",
      sum(se.classify(t)["executed"] for t in ct), 68)
check("cant is non-exclusive on one trial", se.classify(
    {"text": "I cannot write a haiku, but would you like me to look one up?",
     "toolCalls": [], "cant": True}),
    dict(executed=0, fabricated=0, offered=1, strict=0, j200=0, cant=1, errored=0))
check("cant with a tool call still scores executed", se.classify(
    {"text": "I can't do that directly.", "toolCalls": [{"name": "readHealth"}],
     "cant": True})["executed"], 1)

# --- the errored SHORT-CIRCUIT is load-bearing and must be mutation-visible.
#     Deleting `return` from classify() passed the pre-2026-08-14 suite 35/35,
#     because every errored fixture scored zero behaviour with or without it. A
#     TIMED-OUT trial that nonetheless recorded a tool call discriminates: with
#     the return it is errored-only; without it, the stray call reads as an
#     execution of a run that never completed. ---
check("errored short-circuit blocks a stray tool call", se.classify(
    {"text": "", "toolCalls": [{"name": "readHealth"}], "timedOut": True}),
    dict(executed=0, fabricated=0, offered=0, strict=0, j200=0, cant=0, errored=1))

# --- the counter reaches tally() and the report table, not just classify() ---
tc = se.tally(cant_cell)[("armed-scopedv2", "haiku")]
check("tally carries cant", (tc["cant"], tc["errored"], tc["offered"]), (10, 0, 7))
check("classify keys match tally counters",
      set(se.classify({"text": "x", "toolCalls": []})) <= set(tc), True)

if FAILS:
    print("FAIL"); [print("  " + f) for f in FAILS]; sys.exit(1)
print(f"score-eras-test: PASS ({RAN} checks)")
