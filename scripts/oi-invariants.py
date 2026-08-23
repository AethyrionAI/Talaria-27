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
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIVE = ROOT / "OPEN_ITEMS.md"
ARCHIVE = ROOT / "OPEN_ITEMS-ARCHIVE.md"

HEADER = re.compile(r"^## (\d+[A-Z]?)\.", re.M)
# Branch names as they appear in entry prose: `t27-321-322-stop-completes`
#
# 2026-08-19: the bare `<item>-<slug>` form (`350-link-honesty`,
# `3d-artifact-mirror-app`) was INVISIBLE here — this pattern knew only the
# older `t27-` convention, while every lane since 2026-08-17 has used the bare
# one. Together with the STALE_MERGE gap below, the check could not see a
# single one of this week's lanes. The `[a-z]` after the dash is what keeps
# dates out: `2026-08-19`'s next segment starts with a digit.
BRANCH = re.compile(
    r"`(claude/[a-zA-Z0-9._/-]+|t27-[a-zA-Z0-9._-]+|probe/[a-zA-Z0-9._/-]+"
    r"|\d+[A-Za-z]?-[a-z][a-zA-Z0-9._-]*)`"
)
# 2026-08-19: "PR open" / "merge is Owen's review" IS this tracker's standard
# way of saying not-merged — it is what #349, #350 and #367 each said for four
# days while sitting in main — and neither phrase contains "NOT MERGED" or
# "awaiting review". A discriminator that cannot match the text it polices is
# the archived #300 shape, arriving here instead of in the gate.
STALE_MERGE = re.compile(r"NOT MERGED|awaiting review|PR open|merge is Owen's review", re.I)
# This tracker RETRACTS a claim by striking it through and writing the
# correction beside it — `~~NOT MERGED — awaiting review.~~ **✅ MERGED as …**`
# is the house idiom (#328, archived #322, #368 all use it). A struck span is
# a claim that is no longer being made, so it must not trip the check below.
# Deliberately SINGLE-LINE (no DOTALL): a span that opens on one line and
# closes on another is not stripped, so an unbalanced `~~` can only produce a
# FALSE ALARM, never a missed one. Fail safe, same posture as the gate's
# failure-advice classifier.
STRUCK = re.compile(r"~~.+?~~")


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
        if not STALE_MERGE.search(STRUCK.sub("", body)):
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


def _open_prs() -> tuple[list[dict], str | None]:
    """Open PRs as dicts, or (…, reason) when gh cannot answer."""
    try:
        p = subprocess.run(["gh", "pr", "list", "--state", "open",
                            "--json", "number,title,headRefName"],
                           capture_output=True, text=True, timeout=30, cwd=ROOT)
    except (OSError, subprocess.TimeoutExpired):
        return [], "gh unavailable or timed out"
    if p.returncode != 0:
        return [], f"gh failed: {p.stderr.strip()[:80]}"
    try:
        return json.loads(p.stdout or "[]"), None
    except json.JSONDecodeError:
        return [], "gh returned unparseable JSON"


def check_open_pr_claims() -> tuple[bool, str, list[str]]:
    """2026-08-19. #349 and #350 said "PR open; merge is Owen's review" in their
    HEADERS for four days after their branches merged, and every check here
    passed the whole time — `check_claimed_merge_state` needs the entry to name
    a BRANCH in backticks, and the house style records a merge by commit SHA
    instead, so there was nothing for it to resolve.

    This check needs no branch and no SHA: a header that claims an open PR is
    checked against the open PRs GitHub actually has. Scoped to the header LINE
    on purpose — an entry body legitimately discusses PRs that opened and
    closed months ago, and matching those is how a checker earns its ignored
    status."""
    if not LIVE.exists():
        return False, "NO DATA — OPEN_ITEMS.md not found", []
    prs, why = _open_prs()
    if why:
        return False, f"NO DATA — {why}", []
    haystack = " ".join(f"{pr.get('title', '')} {pr.get('headRefName', '')}" for pr in prs)
    bad: list[str] = []
    for line in LIVE.read_text().split("\n"):
        m = HEADER.match(line)
        if not m:
            continue
        num = m.group(1)
        if not STALE_MERGE.search(STRUCK.sub("", line)):
            continue
        if re.search(rf"#{num}\b", haystack) or re.search(rf"(^|\s|/){num}-", haystack):
            continue
        bad.append(f"#{num} header claims an open PR; no open PR on GitHub names it")
    if bad:
        return False, f"{len(bad)} header(s) claim a PR that is not open", bad
    return True, "every header claiming an open PR has one", []



# A RESULT block announcing bars met — `✅ … 389-A/B/C ALL MET …`. Deliberately
# narrow: it requires a verdict marker, a bar reference, and a MET/MISSED word
# on the SAME line, because entries legitimately mention other items' bars in
# prose all the time (#383 cites 310-E; #392 cites #372(c)). Cross-references
# are not what this hunts. A block claiming an item's OWN bars are discharged is.
BAR_RESULT = re.compile(
    r"(✅|🟡|🔴|❌).*?\b(\d+)-[A-Z]\b.*?\b(ALL MET|MET|MISSED|NOT MET)\b"
)


def check_bar_results_live_under_their_own_item() -> tuple[bool, str, list[str]]:
    """A result block must sit under the item whose bars it discharges.

    WHY: on 2026-08-22 #389's entire result block was found inside #372 —
    complete, correct, and 14,000 lines from home. #389's header still read
    "NOT STARTED", so a reader arriving at #389 saw unfinished work and no
    result, and began rebuilding it. Nothing else in this file could see that:
    both halves were internally consistent, and the item numbers never
    collided. A misfiled block is not a staleness bug (the text was current)
    and not an allocation bug (the number was fine) — it is a LOCATION bug,
    which is a third kind this script had no check for.

    Fails safe, same posture as the rest of the file: a legitimate mention of
    another item's bar in a verdict-shaped sentence will trip this. The fix
    for a false alarm is to reword the sentence or move the block — both of
    which leave the tracker easier to read than the sentence that tripped it.
    """
    text = LIVE.read_text(encoding="utf-8")
    lines = text.splitlines()
    current: str | None = None
    offenders: list[str] = []
    for n, line in enumerate(lines, 1):
        header = HEADER.match(line)
        if header:
            current = header.group(1)
            continue
        if current is None:
            continue
        m = BAR_RESULT.search(line)
        if not m:
            continue
        owner = m.group(2)
        if owner != current.rstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZ") and owner != current:
            offenders.append(
                f"line {n}: a #{owner} bar verdict sits under #{current} — "
                f"move the block to #{owner}, or reword if it is a cross-reference"
            )
    if offenders:
        return False, f"{len(offenders)} bar verdict(s) filed under the wrong item", offenders
    return True, "every bar verdict sits under the item whose bars it discharges", []



# A header still claiming the work has not begun.
NOT_STARTED = re.compile(r"NOT STARTED|NOT BUILT", re.I)
# A dated result INSIDE the entry: a ✅ verdict, or an explicit merge.
HAS_RESULT = re.compile(
    r"✅[^\n]{0,80}(MET|BUILT|DONE|FIXED|MERGED|SHIPPED|CLOSED)|\bMERGED (as|20)"
)
# The sweep's own correction marker — an entry that has been reconciled says so
# in its header, and must not re-trip the check forever after.
RECONCILED = re.compile(r"HEADER CORRECTED", re.I)
# ...but the exemption is NOT unconditional, and 2026-08-23 is why.
#
# The 08-23 sweep appended a clause to #340 claiming route (a) was "genuinely
# unbuilt" when it had merged two days earlier — and because the exemption was
# granted by the MARKER'S PRESENCE rather than by what it said, the check the
# same sweep added could never fire on it. A wrong correction silenced the
# check permanently, which is worse than no check: the entry then READS as
# reconciled.
#
# The discriminator is what the three CORRECT partial corrections all do and
# the wrong one did not: they acknowledge what WAS built before scoping what
# is not ("269-A MERGED 2026-08-16; the remainder ... is still unbuilt").
# So a correction clause may scope an absence, but not assert one over a body
# that records a build while acknowledging nothing.
CORRECTION_CLAUSE = re.compile(r"HEADER CORRECTED.*$", re.I)
# Build/completion words ONLY. `RAN` and `CLEARED` were in this set for one
# revision and the mutation test caught them: #340's wrong clause opened with
# "the artifact was CLEARED 2026-08-22", which is a device chore, not a build,
# and it exempted the very text this check was narrowed to catch. `\bBUILT\b`
# deliberately does not match "unbuilt" — no word boundary inside it.
ACKNOWLEDGES_BUILD = re.compile(
    r"\b(BUILT|MERGED|SHIPPED|DEPLOYED|FIXED|DONE|MET)\b", re.I
)


def check_headers_claiming_not_started() -> tuple[bool, str, list[str]]:
    """A header saying NOT STARTED over an entry that records a result.

    WHY: on 2026-08-22 a session read #389, saw "NOT STARTED" with
    pre-registered bars, and began REBUILDING work that had merged the day
    before. It stopped only because it read the code first. The result block
    existed — it was filed under #372 — but the header is what a reader
    believes, and the header was wrong.

    The sweep that followed found **14** headers in this state. That is not a
    stale-claim problem of the kind the merge check already catches (those are
    about git), nor an allocation problem: it is a header disagreeing with its
    own body, which nothing here could see.

    Deliberately narrow. It requires BOTH a not-started claim in the header AND
    a dated verdict in the body, so an entry that is genuinely unstarted with
    bars pre-registered — the normal, correct shape — does not trip it. An
    entry whose header carries the sweep's `HEADER CORRECTED` marker is
    reconciled and exempt: some items are legitimately part-done, and the
    honest fix there is a corrected header, not a rewritten one.

    **The exemption is CONDITIONAL, and 2026-08-23 is why.** That sweep's own
    #340 correction claimed the fix was "genuinely unbuilt" when it had merged
    two days earlier, and the exemption — keyed on the marker's presence —
    made this check permanently blind to it. A correction clause that claims
    NOT STARTED must now also acknowledge the build the body records; the
    three correct partial corrections already did exactly that, so the
    narrowing costs them nothing.
    """
    text = LIVE.read_text(encoding="utf-8")
    lines = text.splitlines()
    offenders: list[str] = []
    current: str | None = None
    header_line: str = ""
    body: list[str] = []

    def flush() -> None:
        if current is None:
            return
        if not NOT_STARTED.search(header_line):
            return
        if not HAS_RESULT.search("\n".join(body)):
            return
        clause_match = CORRECTION_CLAUSE.search(header_line)
        if clause_match:
            clause = clause_match.group(0)
            # A correction that acknowledges the build is doing its job, even
            # when it also scopes what remains unbuilt. One that claims absence
            # and acknowledges nothing is the #340 shape.
            if ACKNOWLEDGES_BUILD.search(clause):
                return
            if not NOT_STARTED.search(clause):
                return
            offenders.append(
                f"#{current}: the HEADER CORRECTED clause claims NOT STARTED over an "
                f"entry that records a build, and acknowledges no build itself — this "
                f"is #340's 2026-08-23 shape, a correction that was itself wrong and "
                f"exempted the check by existing"
            )
            return
        offenders.append(
            f"#{current}: header says NOT STARTED but the entry records a result — "
            f"correct the header, or say why the result does not close it"
        )

    for line in lines:
        m = HEADER.match(line)
        if m:
            flush()
            current, header_line, body = m.group(1), line, []
            continue
        if current is not None:
            body.append(line)
    flush()

    if offenders:
        return False, f"{len(offenders)} header(s) claim NOT STARTED over a recorded result", offenders
    return True, "no header claims NOT STARTED over an entry that records a result", []


CHECKS = [
    ("duplicate item numbers", check_duplicate_numbers),
    ("claimed merge state vs git", check_claimed_merge_state),
    ("headers claiming an open PR", check_open_pr_claims),
    ("bar verdicts filed under their own item", check_bar_results_live_under_their_own_item),
    ("headers claiming NOT STARTED over a result", check_headers_claiming_not_started),
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
