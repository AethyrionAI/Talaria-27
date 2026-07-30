#!/usr/bin/env python3
"""Classify a Talaria action-battery run from its persisted JSON.

The run JSON is the SYSTEM OF RECORD, not the console. #200W proved that the
hard way: the debug console session expired mid-run and the first verdict
wrongly claimed the confirmations and reap seal were lost. Both were in the
record all along — `reapSummary` on the run, `confirmation` on every tool call.
This script exists so the counts stop being derived by hand.

Usage:
    python3 scripts/classify-battery-run.py run-YYYYMMDD-HHMMSS-XXXX.json
    python3 scripts/classify-battery-run.py run.json --anchors "Saucier,Crestwick,MS"

Classification law it enforces (the standing #200 rules):
  * a CREATE is `confirmation == "accepted"` on that intent's create tool —
    never the reply text, which lies in both directions
  * ERROR and TIMEOUT trials are EXCLUDED from rates and listed explicitly
  * reap arithmetic is checked against `reapSummary`, and any residual is
    attributed (discarded warm-up trials are recorder-inert but ARE reaped)
"""

import json
import re
import sys
from collections import Counter

CREATOR = {
    "remind": "createReminder",
    "alarm": "scheduleAlarm",
    "calendar": "createCalendarEvent",
}
ACTION_TOOLS = ("createReminder", "createCalendarEvent", "scheduleAlarm")
# The battery's calendar prompt names no place, so ANY location in the reply of a
# create was invented by the model — the #200W/#200X finding.
#
# Hermes's 2026-07-29 audit (F5) caught the first version of this keyed to Owen's
# home anchors (Saucier / Crestwick / MS): correct on whoGoesThere, silently blind
# on any other device or geography. The check is now structural — the create's
# reply mentions a PLACE where the prompt named none — with device anchors kept
# only as an optional extra via --anchors.
#
# Structural form: the success text reads "… for N minutes at <PLACE> …" / the
# model's own phrasings read "in <Place>, <REGION>". Both are "at/in" followed by
# a capitalised place phrase, after the duration.
INVENTED_LOCATION = re.compile(
    r"(?:minutes|noon|[APap]\.?[Mm]\.?)[^.]{0,20}?\b(?:at|in)\s+"
    r"(?!the\b|your\b|a\b|an\b)"
    r"(\d+\s+)?[A-Z][\w'’.-]*(?:[ ,]+(?:[A-Z][\w'’.-]*|[A-Z]{2}\b))*"
)
DEAD_END = re.compile(r"find a contact|locate a contact|contact named", re.I)
CARD_NARRATION = re.compile(r"confirmation card|would you like to (proceed|edit)", re.I)


# Extra device-specific anchors, e.g. --anchors "Saucier,Crestwick,MS". Optional:
# the structural check above stands on its own.
EXTRA_ANCHORS = None


def invented_location(text):
    """True when a create's reply cites a place the prompt never supplied."""
    if EXTRA_ANCHORS and EXTRA_ANCHORS.search(text):
        return True
    return bool(INVENTED_LOCATION.search(text))


def tool_names(trial):
    return [c["name"] for c in trial.get("toolCalls", [])]


def accepted(trial, tool):
    return any(
        c["name"] == tool and c.get("confirmation") == "accepted"
        for c in trial.get("toolCalls", [])
    )


# #202A pre-registered bars, as RATES so a different n stays comparable.
# They live here rather than in a reader's head: the dispatch doc wrote them
# before the run, and encoding them means the verdict is computed, not judged.
MECHANISM_CONFIRM = 0.75   # control misroutes affirmatives at or above this
MECHANISM_REFUTE = 0.20    # below this the FILING is wrong and #202 re-derives
BASELINE_GATE = 0.95       # the #196 grid must still hold on the control
CAND_ACCEPT = 0.90         # candidate fixes the accepts
CAND_WORDS_ONLY = 0.95     # ...without routing everything armed
CAND_DEVICE = 0.95         # ...and without regressing explicit device turns


def probe_report(run):
    """#202A: the context-blind-router probe. Rows carry variant/band/context,
    so every number below is a summation over the record — nothing is tallied
    by eye (that mistake has cost this program two corrected verdicts)."""
    probes = run["probes"]
    print(f"run {run['id'][:8]}  build={run.get('appBuild')}  os={run.get('osVersion')}")
    print(f"kind={run.get('kind')}  variants={run['cells']}  n={run['trialsPerCell']}"
          f"  endedCleanly={run.get('endedCleanly')}\n")

    # variant -> band -> [correct, trials]
    totals = {}
    for p in probes:
        variant = p.get("variant") or "unlabelled"
        band = p.get("band") or "unlabelled"
        slot = totals.setdefault(variant, {}).setdefault(band, [0, 0])
        slot[0] += p["correct"]
        slot[1] += p["trials"]

    def rate(variant, band):
        c, t = totals.get(variant, {}).get(band, [0, 0])
        return (c / t if t else 0.0), c, t

    print("=== rows (correct = routed the way the row says is RIGHT)")
    for variant in totals:
        print(f"--- {variant}")
        for p in [q for q in probes if (q.get("variant") or "unlabelled") == variant]:
            pct = 100.0 * p["correct"] / p["trials"] if p["trials"] else 0.0
            ctx = (p.get("context") or "")[:44]
            print(f"  [{(p.get('band') or '?'):<10}] {p['correct']:>3}/{p['trials']:<3} {pct:5.1f}%"
                  f"  want={str(p['expected']):<5} {p['probe'][:28]:<28} ctx={ctx}")

    print("\n=== bars (pre-registered in dispatch/OPUS-T27-202A-router-context.md)")

    acc, c, t = rate("control", "accept")
    misroute = 1.0 - acc
    if t == 0:
        print("  !! no control accept rows — the mechanism cannot be read")
    else:
        verdict = ("CONFIRMED" if misroute >= MECHANISM_CONFIRM
                   else "REFUTED — the filing is wrong; re-derive #202 from this run"
                   if misroute < MECHANISM_REFUTE
                   else "INCONCLUSIVE — between the confirm and refute bars")
        print(f"  MECHANISM: control misroutes accepts {misroute:.1%} ({t - c}/{t}) — {verdict}")

    base, c, t = rate("baseline", "baseline")
    if t == 0:
        print("  !! no baseline rows — the regression gate cannot be read")
    else:
        print(f"  BASELINE GATE: {base:.1%} ({c}/{t}) — "
              f"{'HOLDS' if base >= BASELINE_GATE else 'DRIFTED — every other number here is SUSPECT'}")

    for variant in [v for v in totals if v.startswith("ctx")]:
        a, ac, at = rate(variant, "accept")
        w, wc, wt = rate(variant, "words-only")
        d, dc, dt = rate(variant, "device")
        checks = [("accepts", a, CAND_ACCEPT, ac, at),
                  ("words-only", w, CAND_WORDS_ONLY, wc, wt),
                  ("device", d, CAND_DEVICE, dc, dt)]
        parts = [f"{name} {val:.1%} ({cc}/{tt}) {'PASS' if val >= bar else 'FAIL'}"
                 for name, val, bar, cc, tt in checks]
        passed = all(val >= bar for _, val, bar, _, _ in checks)
        print(f"  {variant}: " + " | ".join(parts))
        if not passed and a >= CAND_ACCEPT and w < CAND_WORDS_ONLY:
            print(f"    → fixed the accepts by routing words-only turns ARMED. That is the"
                  f" DEGENERATE named in the dispatch — it re-opens #196. NOT a fix.")
        print(f"    → {variant} {'PASSES all three' if passed else 'FAILS'}")

    if "lenrule" in totals:
        parts = [f"{b} {totals['lenrule'][b][0]}/{totals['lenrule'][b][1]}"
                 for b in totals["lenrule"]]
        print(f"  lenrule (REPORTED, NOT GATED — inheritance needs a two-turn run;"
              f" scored only where the rule FIRES, deferrals are not its answers): "
              + "  ".join(parts))

    # Greedy decode + an identical prompt is deterministic, so repeats of one
    # row are NOT independent samples. When every row saturates, the honest n
    # is the ROW COUNT — say so loudly, because the pooled trial denominators
    # above will otherwise read as far more evidence than the run contains.
    generating = [p for p in probes if (p.get("variant") or "") != "lenrule"]
    split = [p for p in generating if 0 < p["correct"] < p["trials"]]
    if generating and not split:
        rows_by = {}
        for p in generating:
            key = (p.get("variant"), p.get("band"))
            slot = rows_by.setdefault(key, [0, 0])
            slot[0] += 1 if p["correct"] == p["trials"] else 0
            slot[1] += 1
        print(f"\n=== !! ZERO within-row variance across all {len(generating)} generating rows")
        print("  The router decodes GREEDILY, so repeating one prompt re-measures one")
        print("  sample. The effective n is the number of DISTINCT ROWS, not trials:")
        for (variant, band), (good, total) in rows_by.items():
            print(f"    {variant:<9} {band:<11} {good}/{total} rows")
        print("  Report row counts as the evidence. Future probe runs should spend the")
        print("  budget on MORE DISTINCT ROWS rather than on repeats.")

    thermal = run.get("thermal") or []
    if thermal:
        print("\n=== thermal")
        print("  " + "  ".join(thermal))
        starts = {}
        for entry in thermal:
            cell, _, rest = entry.partition(":")
            moment, _, state = rest.partition("=")
            if moment == "start":
                starts[cell] = state
        if len(set(starts.values())) > 1:
            print(f"  !! VARIANTS STARTED AT DIFFERENT THERMAL STATES {starts} — read the"
                  f" DIRECTION of the bias before calling it a confound (#201B lesson 1)")


TWO_TURN_PRIMARY = 0.80    # ctx-a creates on evaluable trials
TWO_TURN_ROUTE_GATE = 0.90  # ...and its turn 2 must actually be routed ARMED


def two_turn_report(run):
    """#202B: the offer→accept shape. The control's zero is STRUCTURAL (a
    routed-toolless turn has no belt), so it is reported as a falsification
    check and never as evidence for the fix. The measured arm is scored
    against an ABSOLUTE bar."""
    trials = run["trials"]
    print(f"run {run['id'][:8]}  build={run.get('appBuild')}  os={run.get('osVersion')}")
    print(f"kind={run.get('kind')}  arms={run['cells']}  n={run['trialsPerCell']}"
          f"  endedCleanly={run.get('endedCleanly')}")
    print(f"reapSummary: {run.get('reapSummary')}\n")

    for cell in run["cells"]:
        rows = [t for t in trials if t["shape"] == cell]
        if not rows:
            continue
        excluded = [t["trial"] for t in rows if t.get("timedOut") or t.get("error")]
        valid = [t for t in rows if t["trial"] not in excluded]
        made = [t for t in valid if accepted(t, "createReminder")]
        armed = [t for t in valid if t.get("route") == "armed"]
        # #199: the reply CLAIMS a create that no artifact backs. Counted
        # separately — never instead of the artifact.
        fabricated = [t for t in valid if t not in made
                      and claims_creation(t.get("text") or "")]
        print(f"=== {cell}")
        print(f"  creates   {len(made)}/{len(valid)}"
              f"{'  EXCLUDED ' + str(excluded) if excluded else ''}")
        print(f"  routed armed on turn 2: {len(armed)}/{len(valid)}")
        if fabricated:
            print(f"  !! FABRICATED CLAIM (reply says created, no artifact): "
                  f"{len(fabricated)} {[t['trial'] for t in fabricated]} — #199")
        for t in [x for x in valid if x not in made]:
            text = (t.get("text") or "").replace("\n", " ")
            print(f"       miss t{t['trial']} [route={t.get('route')}] {text[:110]}")

    print("\n=== bars (pre-registered in dispatch/OPUS-T27-202B-two-turn.md)")
    for cell in run["cells"]:
        rows = [t for t in trials if t["shape"] == cell
                and not (t.get("timedOut") or t.get("error"))]
        if not rows:
            continue
        made = sum(1 for t in rows if accepted(t, "createReminder"))
        armed = sum(1 for t in rows if t.get("route") == "armed")
        rate = made / len(rows)
        if cell == "twoturn-control":
            print(f"  STRUCTURAL CHECK: control creates {made}/{len(rows)} — "
                  + ("HOLDS (zero, as predicted BY CONSTRUCTION — not evidence for the fix)"
                     if made == 0 else
                     "!! VIOLATED — a routed-toolless turn CREATED. The no-belt claim in"
                     " #202 is WRONG and that is a larger finding than this lane"))
        elif cell == "twoturn-ctxa":
            gate = armed / len(rows)
            print(f"  ROUTE GATE: turn 2 armed {gate:.1%} ({armed}/{len(rows)}) — "
                  f"{'HOLDS' if gate >= TWO_TURN_ROUTE_GATE else 'FAILS — the arm is not testing what it claims; PRIMARY IS VOID'}")
            print(f"  PRIMARY: creates {rate:.1%} ({made}/{len(rows)}) vs bar {TWO_TURN_PRIMARY:.0%} — "
                  + ("PASS" if rate >= TWO_TURN_PRIMARY else
                     "FAIL — the route was NECESSARY but NOT SUFFICIENT; #202 needs a second seam"))
        else:
            print(f"  {cell} (diagnostic, ungated): creates {made}/{len(rows)},"
                  f" armed {armed}/{len(rows)}")

    spread = [t for t in trials if t["shape"] in ("twoturn-ctxa", "twoturn-control")]
    by_arm = {}
    for t in spread:
        by_arm.setdefault(t["shape"], []).append(accepted(t, "createReminder"))
    saturated = [a for a, v in by_arm.items() if v and (all(v) or not any(v))]
    if saturated:
        print(f"\n  note: {saturated} saturated (every trial identical). Turn 2 uses"
              f" temperature 0.7, so this is NOT the #202A determinism trap — but with"
              f" no within-arm spread, n is again unproven. Say so in the verdict.")

    thermal = run.get("thermal") or []
    if thermal:
        print("\n=== thermal")
        print("  " + "  ".join(thermal))


def claims_creation(text):
    """Mirrors LocalChatBackend.claimsCreation — a denial that contains 'set'
    is not a claim."""
    lower = text.lower()
    denials = ["can't access", "cannot access", "don't have access", "no access",
               "can't create", "cannot create", "i can't", "i cannot"]
    if any(d in lower for d in denials):
        return False
    return any(c in lower for c in
               ["i've set", "i have set", "i've created", "i have created",
                "i've added", "i have added", "reminder created", "reminder is set",
                "reminder set", "done —", "all set"])


def main(path):
    run = json.load(open(path))
    if run.get("probes") and not run.get("trials"):
        return probe_report(run)
    if run.get("kind") == "twoturn":
        return two_turn_report(run)
    trials = run["trials"]
    print(f"run {run['id'][:8]}  build={run.get('appBuild')}  os={run.get('osVersion')}")
    print(f"cells={run['cells']}  n={run['trialsPerCell']}  endedCleanly={run.get('endedCleanly')}")
    print(f"reapSummary: {run.get('reapSummary')}\n")

    artifacts = Counter()
    for cell in run["cells"]:
        print(f"=== {cell}")
        for prompt in ("remind", "alarm", "calendar", "haiku"):
            rows = [t for t in trials if t["shape"] == cell and t["prompt"] == prompt]
            if not rows:
                continue
            excluded = [t["trial"] for t in rows if t.get("timedOut") or t.get("error")]
            valid = [t for t in rows if t["trial"] not in excluded]

            if prompt == "haiku":
                grabs = [t["trial"] for t in valid
                         if any(accepted(t, tool) for tool in ACTION_TOOLS)]
                print(f"  haiku      grabs {len(grabs)}/{len(valid)} {grabs}"
                      f"{'  EXCLUDED ' + str(excluded) if excluded else ''}")
            else:
                tool = CREATOR[prompt]
                made = [t["trial"] for t in valid if accepted(t, tool)]
                print(f"  {prompt:<10} {len(made)}/{len(valid)}"
                      f"{'  EXCLUDED ' + str(excluded) if excluded else ''}")
                misses = [t for t in valid if t["trial"] not in made]
                for t in misses:
                    text = (t.get("text") or "").replace("\n", " ")
                    kind = ("dead-end" if DEAD_END.search(text)
                            else "card-narration" if CARD_NARRATION.search(text)
                            else "other")
                    print(f"       miss t{t['trial']} [{kind}] {text[:110]}")

            if prompt == "calendar":
                spiral = Counter()
                for t in valid:
                    for name in set(tool_names(t)):
                        if name in ("currentLocation", "searchPlaces"):
                            spiral[name] += 1
                invented = [t["trial"] for t in valid
                            if accepted(t, "createCalendarEvent")
                            and invented_location(t.get("text") or "")]
                print(f"       spiral currentLocation={spiral['currentLocation']}"
                      f"/{len(valid)} searchPlaces={spiral['searchPlaces']}/{len(valid)}")
                print(f"       INVENTED LOCATION in create: {len(invented)} {invented}")

            for t in rows:
                for c in t.get("toolCalls", []):
                    if c.get("confirmation") == "accepted" and c["name"] in ACTION_TOOLS:
                        artifacts[c["name"]] += 1

    thermal = run.get("thermal") or []
    if thermal:
        print("\n=== thermal (#201B)")
        print("  " + "  ".join(thermal))
        starts = {}
        for entry in thermal:
            cell, _, rest = entry.partition(":")
            moment, _, state = rest.partition("=")
            if moment == "start":
                starts[cell] = state
        if len(set(starts.values())) > 1:
            print(f"  !! CELLS STARTED AT DIFFERENT THERMAL STATES {starts} —"
                  f" the comparison is COMPROMISED; say so in the verdict")

    print("\n=== reap arithmetic")
    counted = dict(artifacts)
    print(f"accepted creates in counted trials: {counted} total={sum(counted.values())}")
    seal = run.get("reapSummary") or ""
    reaped = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", seal)}
    if reaped:
        total_reaped = reaped.get("reminders", 0) + reaped.get("events", 0) + reaped.get("alarms", 0)
        residual = total_reaped - sum(counted.values())
        print(f"reaped total={total_reaped}  residual={residual}"
              f"  (discarded warm-up trials are reaped but not recorded)")
        if reaped.get("failures"):
            print(f"  !! reap failures={reaped['failures']} — investigate before trusting rates")
    else:
        print("  !! no reapSummary on this run — arithmetic cannot be sealed")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--anchors" in args:
        i = args.index("--anchors")
        names = [n.strip() for n in args[i + 1].split(",") if n.strip()]
        EXTRA_ANCHORS = re.compile("|".join(re.escape(n) for n in names))
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    main(args[0])
