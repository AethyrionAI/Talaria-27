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
        print(f"  lenrule (REPORTED, NOT GATED — inheritance needs a two-turn run): "
              + "  ".join(parts))

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


def main(path):
    run = json.load(open(path))
    if run.get("probes") and not run.get("trials"):
        return probe_report(run)
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
