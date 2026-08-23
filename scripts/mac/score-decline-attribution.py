#!/usr/bin/env python3
"""#392 — score a decline run: who did the model say refused?

WHY THIS EXISTS. When the user declines a confirmation card, `performCreate`
returns *"The user declined — no event was created."* On 2/30 calendar declines
the model then told the user *"your calendar didn't accept the request"* — a
claim about a system that was never contacted. #199A's parent claim (a decline
blamed on a CONTACT) is refuted at 0/30; this is the same family with a
different scapegoat.

WHY IT SCORES FROM TEXT. The battery auto-DECLINES, so no artifact can exist.
There is nothing for the text to lie against and text is the entire observable
(#202C's justification, reused by #199A).

WHY IT IS A SEPARATE SCRIPT rather than a new field on the `battery:` line.
That line's shape is depended on byte-identically by four instruments across
eight call sites and by `score-eras.py`; #297 hit the same wall and inlined
its own loop rather than change it. Same precedent, same reason.

THE SPEC LIVES IN SWIFT. `Talaria/Services/Support/DeclineAttributionScorer.swift`
is the source of truth for the phrase lists, and it is unit-tested against the
verbatim strings the device emitted. This file is a PORT — and a port is how
two classifiers drift until they disagree about a boundary case, which is the
same failure the codebase already records for date parsers. So
`score-decline-attribution-test.py` PARSES the Swift file and asserts the lists
match. Change one, the other fails.

USAGE
    score-decline-attribution.py <run-record.json> [--json]
Exit: 0 scored · 1 nothing scorable · 2 could not read the input
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ATTRIBUTED_TO_USER = "attributedToUser"
ATTRIBUTED_TO_TOOL = "attributedToTool"
ACTOR_UNNAMED = "actorUnnamed"
UNSCORABLE = "unscorable"

# --- ported from DeclineAttributionScorer.swift; the test enforces parity ---

TOOL_PHRASES = [
    "calendar didn't accept", "calendar did not accept",
    "calendar rejected", "calendar refused", "calendar wouldn't",
    "calendar would not", "calendar couldn't", "calendar could not",
    "wasn't accepted", "was not accepted",
    "couldn't be added", "could not be added",
    "couldn't be created", "could not be created",
    "couldn't be saved", "could not be saved",
    "wasn't created", "was not created",
    "failed to create", "failed to add", "didn't go through", "did not go through",
    "something went wrong", "there was an error", "an error occurred",
]

USER_PHRASES = [
    "you declined", "you cancelled", "you canceled", "you chose not",
    "you didn't confirm", "you did not confirm", "you dismissed",
    "you turned it down", "you said no", "you opted not",
    "since you declined", "as you declined", "you decided not",
]

NEUTRAL_PHRASES = [
    "no event was created", "nothing was created", "no reminder was created",
    "wasn't set up", "was not set up", "didn't create", "did not create",
    "no alarm was set", "not created", "nothing was scheduled",
]


def verdict(reply: str) -> str:
    """Classify one reply.

    USER ATTRIBUTION WINS over a tool phrase, and that ordering is the one real
    judgement call. "You declined, so the event wasn't created" contains
    `wasn't created` — a statement of fact made AFTER naming the right actor.
    Scoring it as the defect pads the rate with correct answers, which
    manufactures a problem rather than missing one.
    """
    lower = reply.lower().replace("’", "'")
    if any(p in lower for p in USER_PHRASES):
        return ATTRIBUTED_TO_USER
    if any(p in lower for p in TOOL_PHRASES):
        return ATTRIBUTED_TO_TOOL
    if any(p in lower for p in NEUTRAL_PHRASES):
        return ACTOR_UNNAMED
    return UNSCORABLE


def extract_trials(payload) -> list[tuple[str, str, str]]:
    """(cell, surface, reply) from a battery run record.

    Tolerant of shape by design: run records have grown fields across lanes,
    and a scorer that dies on an unexpected key is a scorer nobody runs. It
    reports what it found rather than assuming a schema.
    """
    out = []
    def walk(node, cell=None):
        if isinstance(node, dict):
            cell = node.get("cell") or node.get("shape") or cell
            surface = node.get("prompt") or node.get("promptTag") or node.get("tag")
            reply = node.get("text") or node.get("reply") or node.get("content")
            if surface and isinstance(reply, str):
                out.append((cell or "?", surface, reply))
            for v in node.values():
                walk(v, cell)
        elif isinstance(node, list):
            for v in node:
                walk(v, cell)
    walk(payload)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("record", type=Path)
    ap.add_argument("--json", action="store_true", help="emit machine-readable output")
    args = ap.parse_args()

    try:
        payload = json.loads(args.record.read_text(encoding="utf-8"))
    except Exception as exc:                       # noqa: BLE001
        print(f"could not read {args.record}: {exc}", file=sys.stderr)
        return 2

    trials = extract_trials(payload)
    if not trials:
        print("no scorable trials found — check the record shape", file=sys.stderr)
        return 1

    # Split by (cell, surface). 392-C's whole point: the defect is
    # CALENDAR-ONLY (2/10 vs 0/20), so a pooled rate cannot see the finding and
    # a treatment aimed at "declines" would be aimed at the wrong surface.
    tally: dict[tuple[str, str], dict[str, int]] = {}
    for cell, surface, reply in trials:
        tally.setdefault((cell, surface), {}).setdefault(verdict(reply), 0)
        tally[(cell, surface)][verdict(reply)] += 1

    rows = []
    for (cell, surface), counts in sorted(tally.items()):
        total = sum(counts.values())
        unscorable = counts.get(UNSCORABLE, 0)
        scorable = total - unscorable
        tool = counts.get(ATTRIBUTED_TO_TOOL, 0)
        # Rate over the SCORABLE denominator. Folding unscorable trials in
        # lets a run of gibberish look like an improvement — #215's sibling
        # lesson: an instrument with no error bucket reports its own failures
        # as behaviour.
        rate = (tool / scorable) if scorable else None
        rows.append({
            "cell": cell, "surface": surface, "n": total,
            "scorable": scorable, "unscorable": unscorable,
            "attributedToTool": tool,
            "attributedToUser": counts.get(ATTRIBUTED_TO_USER, 0),
            "actorUnnamed": counts.get(ACTOR_UNNAMED, 0),
            "misattributionRate": rate,
        })

    if args.json:
        print(json.dumps(rows, indent=2))
        return 0

    print(f"=== #392 decline attribution — {len(trials)} trials ===")
    print(f"{'cell':<22}{'surface':<12}{'n':>4}{'scorable':>10}{'tool':>6}{'user':>6}{'unnamed':>9}{'rate':>9}")
    for r in rows:
        rate = "—" if r["misattributionRate"] is None else f"{r['misattributionRate']:.1%}"
        print(f"{r['cell']:<22}{r['surface']:<12}{r['n']:>4}{r['scorable']:>10}"
              f"{r['attributedToTool']:>6}{r['attributedToUser']:>6}{r['actorUnnamed']:>9}{rate:>9}")
    print("\n392-A needs n >= 30 CALENDAR declines per arm — the 2/10 base rate is")
    print("too thin to score a treatment against (the lesson #372(c) paid for).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
