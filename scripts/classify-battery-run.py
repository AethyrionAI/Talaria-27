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


def main(path):
    run = json.load(open(path))
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
