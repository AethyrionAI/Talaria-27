#!/usr/bin/env python3
"""#342 — a READ-ONLY Kanban view of OPEN_ITEMS.md.

Deliberately additive: this reads the board lines and prints columns. It never
writes to the tracker, so it cannot corrupt the one file this project trusts,
and it can be deleted with no trace.

The point is NOT the pretty output. It is the UNCLASSIFIED column: every item
this cannot place is an item whose state lives only in prose a human must read.
That count is the actual measurement of whether the tracker is Kanban-able, and
it is what #342 exists to decide.

Usage:  python3 scripts/oi-kanban.py [--unclassified] [--column NAME]
"""
import re
import sys
import pathlib

TRACKER = pathlib.Path(__file__).resolve().parent.parent / "OPEN_ITEMS.md"

# Ordered: the FIRST rule that matches wins, so the strongest signal is first.
# Each rule is (column, regex over the board line, why-this-signal).
RULES = [
    ("Done (merge landed)",
     r"✅\s*(BUILT,\s*)?(WITNESSED,\s*)?MERGED|MERGED\s*(\(|—|:)|CLOSES\b|entry CLOSES",
     "an explicit merge/close claim"),
    ("In review / not merged",
     r"NOT MERGED|awaiting review|merge authority",
     "built but explicitly not merged"),
    ("In progress (built, unrun)",
     r"BUILT[^.]*UNRUN|built \(unrun\)|instruments built|BUILT sim\+unit",
     "code exists, measurement does not"),
    ("Blocked",
     r"\bblocked on\b|\bgated on\b|\bSTAYS OPEN\b|\bowed\b.*\bOwen\b|OWEN'S CALL|Owen's call|needs Owen",
     "waiting on a person or another item"),
    ("Ready (bars written)",
     r"bars? .*pre-?registered|READY TO DISPATCH|bars? [A-Z0-9-]+\.\.[A-Z]",
     "bars exist, so a lane can start"),
    ("Measured / needs a decision",
     r"MEASURED|RULED|CONFIRMED IN PRODUCTION|SCORED",
     "evidence exists; the next move is a ruling"),
    ("Backlog",
     r"NOT STARTED|no lane|NO LANE",
     "filed, nothing started"),
]

CARD = re.compile(r"^- \*\*#(\d+[A-Za-z]?)\*\*\s*(.*)$")


def board_lines(text):
    """Board cards are the bullet list BEFORE the first full '## ' entry."""
    out = []
    for line in text.splitlines():
        if line.startswith("## ") and out:
            break
        m = CARD.match(line)
        if m:
            out.append((m.group(1), m.group(2)))
    return out


def classify(body):
    for column, pattern, _why in RULES:
        if re.search(pattern, body):
            return column
    return "UNCLASSIFIED"


def title_of(body, width=96):
    # Strip markdown emphasis and collapse to one readable line.
    t = re.sub(r"\*\*|`|~~", "", body)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:width] + ("…" if len(t) > width else "")


def main():
    args = sys.argv[1:]
    only_unclassified = "--unclassified" in args
    wanted = None
    if "--column" in args:
        wanted = args[args.index("--column") + 1]

    cards = board_lines(TRACKER.read_text(encoding="utf-8"))
    columns = {}
    for num, body in cards:
        columns.setdefault(classify(body), []).append((num, body))

    order = [c for c, _, _ in RULES] + ["UNCLASSIFIED"]
    total = len(cards)
    print(f"OPEN_ITEMS.md — {total} open cards\n")

    for column in order:
        items = columns.get(column, [])
        if not items:
            continue
        if only_unclassified and column != "UNCLASSIFIED":
            continue
        if wanted and wanted.lower() not in column.lower():
            continue
        print(f"── {column}  ({len(items)})")
        for num, body in items:
            print(f"   #{num:<5} {title_of(body)}")
        print()

    unc = len(columns.get("UNCLASSIFIED", []))
    print(f"UNCLASSIFIED: {unc}/{total} ({unc * 100 // max(total, 1)}%) — "
          "these have no machine-readable state; that number is #342's real input.")


if __name__ == "__main__":
    main()
