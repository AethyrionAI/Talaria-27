#!/usr/bin/env python3
"""Read-only invariant checks over the tracker. Never writes to it.

WHY THIS EXISTS. On 2026-08-15 three staleness failures surfaced in one
afternoon, and **not one was caught by reading the tracker**:

  1. Six items claimed "NOT MERGED — awaiting review" while sitting in main,
     stale for four days. Found by `git branch --merged`.
  2. PR #304 sat open marked "decision owed" five days past the ruling that
     superseded it — a ruling written inside its own entry.
  3. Three numbers (#316/#317/#318) were used for six different items. The
     branch AUTO-MERGED CLEAN; nothing conflicted. Found by `uniq -d`.

Each is a one-line mechanical check. This script is those checks, in the spirit
of `oi-kanban.py` (#342): additive, read-only, decides nothing about format.

WHAT IT DELIBERATELY DOES NOT DO. It does not propose or write a status field.
Two of the three failures above are not status problems at all — merge state is
DERIVABLE from git (a field asserting it can be wrong; a computed answer
cannot), and number collision is an ALLOCATION problem. Recording state a human
maintains would reproduce the very failure mode it claims to fix.

NO DATA IS NOT A PASS. A check that cannot run says so and exits non-zero,
rather than printing a clean result it did not earn.

USAGE
    scripts/oi-invariants.py            # all checks
    scripts/oi-invariants.py --quiet    # exit code only
Exit: 0 all passed · 1 a check FAILED · 2 a check could not run
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIVE = ROOT / "OPEN_ITEMS.md"
ARCHIVE = ROOT / "OPEN_ITEMS-ARCHIVE.md"

HEADER = re.compile(r"^## (\d+[A-Z]?)\.", re.M)
# Branch names as they appear in entry prose: `t27-321-322-stop-completes`
BRANCH = re.compile(r"`(claude/[a-zA-Z0-9._/-]+|t27-[a-zA-Z0-9._-]+|probe/[a-zA-Z0-9._/-]+)`")
STALE_MERGE = re.compile(r"NOT MERGED|awaiting review", re.I)


def git(*args: str) -> str | None:
    """Run git read-only; None when it cannot answer (never an empty string,
    which a caller could mistake for 'no results')."""
    try:
        p = subprocess.run(["git", "-C", str(ROOT), *args],
                           capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return p.stdout if p.returncode == 0 else None


def check_duplicate_numbers() -> tuple[bool, str, list[str]]:
    """#316/#317/#318, 2026-08-15. Two concurrent lanes each allocate 'the next
    free number' from their own view; the merge is CLEAN and keeps both."""
    if not LIVE.exists():
        return False, "NO DATA — OPEN_ITEMS.md not found", []
    nums: list[str] = []
    for f in (LIVE, ARCHIVE):
        if f.exists():
            nums += HEADER.findall(f.read_text())
    dupes = sorted({n for n in nums if nums.count(n) > 1})
    # #261's counting rules record 198/199 as a KNOWN legacy double-heading.
    known = {"198", "199"}
    real = [d for d in dupes if d not in known]
    if real:
        return False, f"{len(real)} number(s) used by more than one item", real
    note = " (198/199's known legacy double-headings ignored)" if dupes else ""
    return True, f"no duplicate item numbers across {len(set(nums))} items{note}", []


def check_claimed_merge_state() -> tuple[bool, str, list[str]]:
    """#321/#322/#327/#328, 2026-08-15 — four days stale. An entry that names a
    branch AND says NOT MERGED is checked against git, because merge state is a
    fact to be DERIVED rather than a field to be asserted."""
    if git("rev-parse", "--git-dir") is None:
        return False, "NO DATA — not a git repo / git unavailable", []
    if not LIVE.exists():
        return False, "NO DATA — OPEN_ITEMS.md not found", []
    text = LIVE.read_text()
    bad: list[str] = []
    # Split into entries so a branch is attributed to the item that names it.
    parts = re.split(r"^## (\d+[A-Z]?)\.", text, flags=re.M)
    for i in range(1, len(parts) - 1, 2):
        num, body = parts[i], parts[i + 1]
        if not STALE_MERGE.search(body):
            continue
        for br in set(BRANCH.findall(body)):
            # Only judge branches that still exist somewhere git can see.
            if git("rev-parse", "--verify", "--quiet", br) is None and \
               git("rev-parse", "--verify", "--quiet", f"origin/{br}") is None:
                continue
            ref = br if git("rev-parse", "--verify", "--quiet", br) else f"origin/{br}"
            if git("merge-base", "--is-ancestor", ref, "main") is not None:
                bad.append(f"#{num} says NOT MERGED but `{br}` is an ancestor of main")
    if bad:
        return False, f"{len(bad)} entr(y/ies) claim NOT MERGED while merged", bad
    return True, "no entry claims NOT MERGED for a branch that is in main", []


def check_open_prs_against_entries() -> tuple[bool, str, list[str]]:
    """PR #304, 2026-08-15 — open five days past the ruling that superseded it.
    This one cannot be decided mechanically: it REPORTS open PRs and the tracker
    items they name, for a human to eyeball. Reporting is the honest ceiling."""
    out = git("rev-parse", "--git-dir")
    if out is None:
        return False, "NO DATA — git unavailable", []
    try:
        p = subprocess.run(["gh", "pr", "list", "--state", "open",
                            "--json", "number,title", "-q",
                            '.[] | "\\(.number)\t\\(.title)"'],
                           capture_output=True, text=True, timeout=30, cwd=ROOT)
    except (OSError, subprocess.TimeoutExpired):
        return False, "NO DATA — gh unavailable or timed out", []
    if p.returncode != 0:
        return False, f"NO DATA — gh failed: {p.stderr.strip()[:80]}", []
    rows = [r for r in p.stdout.strip().split("\n") if r.strip()]
    if not rows:
        return True, "no open PRs to reconcile", []
    return True, f"{len(rows)} open PR(s) — verify each against its entry's LATEST dated block", rows


CHECKS = [
    ("duplicate item numbers", check_duplicate_numbers),
    ("claimed merge state vs git", check_claimed_merge_state),
    ("open PRs vs entries (report only)", check_open_prs_against_entries),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    failed = nodata = 0
    for name, fn in CHECKS:
        ok, summary, detail = fn()
        if summary.startswith("NO DATA"):
            nodata += 1
            label = "NODATA"
        elif ok:
            label = "PASS  "
        else:
            failed += 1
            label = "FAIL  "
        if not args.quiet:
            print(f"  {label} {name} — {summary}")
            for d in detail:
                print(f"           {d}")

    if not args.quiet:
        print()
        if failed:
            print(f"INVARIANTS: FAIL ({failed} check(s))")
        elif nodata:
            print(f"INVARIANTS: INCOMPLETE ({nodata} could not run) — not a pass")
        else:
            print("INVARIANTS: PASS")
        print("Read-only: this script never writes to the tracker (#342).")
    return 1 if failed else (2 if nodata else 0)


if __name__ == "__main__":
    sys.exit(main())
