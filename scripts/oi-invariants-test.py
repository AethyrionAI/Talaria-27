#!/usr/bin/env python3
"""Fast validation for oi-invariants.py. Runs in well under a second; run this,
not a tracker-wide sweep, after touching a check.

WHY THIS EXISTS (#373, executing #342's real residual). `oi-invariants.py` has
policed the tracker since 2026-08-15 and has never had a test. Its checks are
regexes over prose, which is the exact material that fails quietly: the
archived #300 classifier keyed on a diagnostic shape one of its two frameworks
never prints, and so announced the same wrong verdict for every Swift Testing
failure in this project's history. Nothing about that failure was visible from
reading the code — it took feeding it two recorded logs.

So this file feeds the checks CRAFTED TRACKER SNIPPETS and asserts the verdict.
Two rules it holds itself to:

  * **Every check gets a POSITIVE case** — one snippet it must FAIL on. A check
    that has never fired is indistinguishable from a check that cannot fire, and
    a narrowing that blinds one would otherwise land green.
  * **Fixtures never touch the real tracker.** `LIVE`/`ARCHIVE` are pointed at
    temp files and `git`/`gh` are stubbed, so a run here says nothing about
    today's OPEN_ITEMS.md and cannot be confused with `oi-invariants.py`'s own
    output.

MUTATION NOTE. When re-running this against a hand-mutated script, clear
bytecode first — a byte-length-identical edit can be served from a stale
`__pycache__`:

    rm -rf scripts/__pycache__ && PYTHONDONTWRITEBYTECODE=1 scripts/oi-invariants-test.py
"""

import importlib.util
import os
import sys
import tempfile

sys.dont_write_bytecode = True  # see MUTATION NOTE above

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "oi", os.path.join(HERE, "oi-invariants.py"))
oi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(oi)

FAILS: list[str] = []
RAN = 0


def check(name, got, want):
    """Counts itself — a hand-maintained check total is a miscount waiting to
    happen (borrowed from `score-eras-test.py`)."""
    global RAN
    RAN += 1
    if got != want:
        FAILS.append(f"{name}: got {got!r} want {want!r}")


# --------------------------------------------------------------------------
# Fixture plumbing. The checks read module-level paths and call module-level
# `git`/`_open_prs`, so a fixture is a rebind plus a temp file.
# --------------------------------------------------------------------------

_TMP = tempfile.TemporaryDirectory()


def with_tracker(live: str, archive: str = ""):
    """Point the module at crafted tracker text. Returns nothing; the caller
    then invokes the check under test."""
    live_path = os.path.join(_TMP.name, "OPEN_ITEMS.md")
    arch_path = os.path.join(_TMP.name, "OPEN_ITEMS-ARCHIVE.md")
    with open(live_path, "w", encoding="utf-8") as f:
        f.write(live)
    with open(arch_path, "w", encoding="utf-8") as f:
        f.write(archive)
    oi.LIVE = oi.Path(live_path)
    oi.ARCHIVE = oi.Path(arch_path)


def stub_git(merged_refs=(), known_refs=()):
    """A `git` that answers only what these checks ask.

    `known_refs` exist; `merged_refs` are additionally ancestors of main. The
    real function returns None for "cannot answer", and the checks lean on that
    distinction, so the stub reproduces it exactly rather than returning "".
    """
    def _git(*args):
        if args[:2] == ("rev-parse", "--git-dir"):
            return ".git\n"
        if args[:1] == ("rev-parse",):
            ref = args[-1]
            return "sha\n" if ref in known_refs or ref in merged_refs else None
        if args[:1] == ("merge-base",):
            ref = args[2]
            return "" if ref in merged_refs else None
        return None
    oi.git = _git


def stub_prs(prs):
    oi._open_prs = lambda: (list(prs), None)


def stub_prs_unavailable(reason="gh unavailable or timed out"):
    oi._open_prs = lambda: ([], reason)


def verdict(fn):
    """(ok, is_nodata, detail-count) — the three things a caller of a check
    actually branches on."""
    ok, summary, detail = fn()
    return ok, summary.startswith("NO DATA"), len(detail)


# --------------------------------------------------------------------------
# 1 · duplicate item numbers
# --------------------------------------------------------------------------

with_tracker("## 10. one\n\n## 11. two\n", "## 12. three\n")
check("dupes: clean board passes", verdict(oi.check_duplicate_numbers), (True, False, 0))

# POSITIVE CASE — the #316/#317/#318 shape, and the collision that mattered
# spanned the two FILES, which is the arm a live-board-only `uniq -d` missed.
with_tracker("## 10. one\n\n## 11. two\n", "## 11. two again\n")
check("dupes: cross-file collision caught",
      verdict(oi.check_duplicate_numbers), (False, False, 1))

with_tracker("## 198. legacy\n\n## 198. legacy again\n"
             "\n## 199. legacy\n\n## 199. legacy again\n")
check("dupes: 198/199 legacy double-headings ignored",
      verdict(oi.check_duplicate_numbers), (True, False, 0))

with_tracker("## 10. one\n")
oi.LIVE = oi.Path(os.path.join(_TMP.name, "no-such-file.md"))
check("dupes: a missing tracker is NO DATA, not a pass",
      verdict(oi.check_duplicate_numbers), (False, True, 0))


# --------------------------------------------------------------------------
# 2 · claimed merge state vs git — the check #409 false-positived
# --------------------------------------------------------------------------

MERGED = "409-do-not-claim-clause"

# POSITIVE CASE — #321/#322/#327/#328's shape, four days stale.
with_tracker(f"## 409. a thing — **NOT MERGED — awaiting review.**\n\n"
             f"Branch `{MERGED}`.\n")
stub_git(merged_refs=(MERGED,))
check("merge: a plain NOT MERGED over a merged branch is caught",
      verdict(oi.check_claimed_merge_state), (False, False, 1))

# THE #409 FALSE POSITIVE, verbatim in sense: a TOPIC merge, not a git one.
with_tracker(f"## 409. a thing\n\nBranch `{MERGED}`.\n"
             f"Deliberately NOT merged with: Owen's 2026-08-12 hand-run "
             f"fabrication (do not collapse the two findings).\n")
stub_git(merged_refs=(MERGED,))
check("merge: 'not merged with: <a topic>' is not a git claim",
      verdict(oi.check_claimed_merge_state), (True, False, 0))

# ...and the narrowing must NOT blind the git sense of the same three words.
with_tracker(f"## 409. a thing\n\nBranch `{MERGED}` is not merged with main.\n")
stub_git(merged_refs=(MERGED,))
check("merge: 'not merged with main' IS a git claim and still fires",
      verdict(oi.check_claimed_merge_state), (False, False, 1))

# Emphasis markers between the two words hid a real claim from this check —
# which is why #409 had to write `**NOT** merged` to WORK AROUND it. A
# discriminator that markdown can switch off is the #300 shape.
with_tracker(f"## 409. a thing — **NOT** MERGED, awaiting Owen.\n\n"
             f"Branch `{MERGED}`.\n")
stub_git(merged_refs=(MERGED,))
check("merge: emphasis between the words does not hide a real claim",
      verdict(oi.check_claimed_merge_state), (False, False, 1))

# A RETRACTED claim is not a claim.
with_tracker(f"## 409. a thing — ~~NOT MERGED — awaiting review.~~ "
             f"**MERGED as `abc1234`.**\n\nBranch `{MERGED}`.\n")
stub_git(merged_refs=(MERGED,))
check("merge: a struck retraction does not fire",
      verdict(oi.check_claimed_merge_state), (True, False, 0))

# An unmerged branch with an honest claim is the normal, correct shape.
with_tracker("## 409. a thing — **NOT MERGED — awaiting review.**\n\n"
             "Branch `409-live-branch`.\n")
stub_git(known_refs=("409-live-branch",))
check("merge: an honest not-merged claim passes",
      verdict(oi.check_claimed_merge_state), (True, False, 0))

# A branch git has never heard of is not judged either way.
with_tracker("## 409. a thing — **NOT MERGED.**\n\nBranch `409-long-deleted`.\n")
stub_git()
check("merge: an unknown branch is skipped, not guessed",
      verdict(oi.check_claimed_merge_state), (True, False, 0))

_real_git = oi.git
oi.git = lambda *a: None
check("merge: no git is NO DATA, not a pass",
      verdict(oi.check_claimed_merge_state), (False, True, 0))
oi.git = _real_git


# --------------------------------------------------------------------------
# 3 · headers claiming an open PR
# --------------------------------------------------------------------------

# POSITIVE CASE — #349/#350's shape: the header said it for four days after
# the merge, and every other check here passed the whole time.
with_tracker("## 350. a thing — **PR open; merge is Owen's review.**\n")
stub_prs([])
check("open-pr: a header claiming a PR nobody has is caught",
      verdict(oi.check_open_pr_claims), (False, False, 1))

with_tracker("## 350. a thing — **PR open; merge is Owen's review.**\n")
stub_prs([{"number": 1, "title": "#350 the thing", "headRefName": "x"}])
check("open-pr: a header whose PR exists by number passes",
      verdict(oi.check_open_pr_claims), (True, False, 0))

with_tracker("## 350. a thing — **PR #329 OPEN.**\n")
stub_prs([{"number": 329, "title": "something", "headRefName": "350-the-thing"}])
check("open-pr: matched by branch name as well as title",
      verdict(oi.check_open_pr_claims), (True, False, 0))

# Scoped to the header LINE: an entry body legitimately discusses PRs that
# opened and closed months ago.
with_tracker("## 350. a thing — done.\n\nBack in July the PR open then was #1.\n")
stub_prs([])
check("open-pr: body prose about old PRs is out of scope",
      verdict(oi.check_open_pr_claims), (True, False, 0))

with_tracker("## 350. a thing — ~~PR open.~~ **MERGED.**\n")
stub_prs([])
check("open-pr: a struck retraction does not fire",
      verdict(oi.check_open_pr_claims), (True, False, 0))

stub_prs_unavailable()
with_tracker("## 350. a thing — **PR open.**\n")
check("open-pr: no gh is NO DATA, not a pass",
      verdict(oi.check_open_pr_claims), (False, True, 0))


# --------------------------------------------------------------------------
# 4 · bar verdicts filed under their own item
# --------------------------------------------------------------------------

# POSITIVE CASE — #389's whole result block sat under #372, 14,000 lines from
# home, both halves internally consistent.
with_tracker("## 372. a thing\n\n> **✅ 2026-08-22 — 389-A/B/C ALL MET.**\n")
check("bar-locus: a foreign bar verdict is caught",
      verdict(oi.check_bar_results_live_under_their_own_item), (False, False, 1))

with_tracker("## 389. a thing\n\n> **✅ 2026-08-22 — 389-A/B/C ALL MET.**\n")
check("bar-locus: a verdict under its own item passes",
      verdict(oi.check_bar_results_live_under_their_own_item), (True, False, 0))

with_tracker("## 372. a thing\n\nThis lane cites 310-E as background.\n")
check("bar-locus: a plain cross-reference is not a verdict",
      verdict(oi.check_bar_results_live_under_their_own_item), (True, False, 0))

with_tracker("## 389A. a sub-item\n\n> **✅ 389-A MET.**\n")
check("bar-locus: a lettered sub-item owns its parent's bars",
      verdict(oi.check_bar_results_live_under_their_own_item), (True, False, 0))


# --------------------------------------------------------------------------
# 5 · headers claiming NOT STARTED over a recorded result
# --------------------------------------------------------------------------

# POSITIVE CASE — a session read this shape and began rebuilding merged work.
with_tracker("## 389. a thing — **NOT STARTED.**\n\n> **✅ 2026-08-21 BUILT.**\n")
check("not-started: a header contradicting its own body is caught",
      verdict(oi.check_headers_claiming_not_started), (False, False, 1))

with_tracker("## 389. a thing — **NOT STARTED.** Bars below.\n\nBars: 389-A …\n")
check("not-started: genuinely unstarted with bars is the correct shape",
      verdict(oi.check_headers_claiming_not_started), (True, False, 0))

with_tracker("## 269. a thing — **NOT STARTED.** "
             "⟵ 269-A MERGED 2026-08-16; the remainder is unbuilt.\n"
             "\n> **✅ 2026-08-16 BUILT.**\n")
check("not-started: a correction that acknowledges the build is exempt",
      verdict(oi.check_headers_claiming_not_started), (True, False, 0))

# #340's 2026-08-23 shape: a correction that was itself wrong, exempting the
# check by existing. The narrowing that catches it is why `CLEARED` and `RAN`
# are not build words.
with_tracker("## 340. a thing — **NOT STARTED.** "
             "⟵ the artifact was CLEARED 2026-08-22; route (a) is NOT STARTED.\n"
             "\n> **✅ 2026-08-21 MERGED as `abc1234`.**\n")
check("not-started: a correction claiming absence over a build is caught",
      verdict(oi.check_headers_claiming_not_started), (False, False, 1))


# --------------------------------------------------------------------------
# 6 · headers awaiting a decision already made
# --------------------------------------------------------------------------

# POSITIVE CASE — a night build list booked five items and four were not
# buildable, because it was assembled from headers.
with_tracker("## 365. a thing — the fix is unrouted and is Owen's call.\n"
             "\n> **RULED 2026-08-18: build it.**\n")
check("decision: a header awaiting a made ruling is caught",
      verdict(oi.check_headers_awaiting_a_decision_already_made), (False, False, 1))

with_tracker("## 365. a thing — Owen routes.\n\nNo ruling yet.\n")
check("decision: a genuinely open routing question passes",
      verdict(oi.check_headers_awaiting_a_decision_already_made), (True, False, 0))

with_tracker("## 365. a thing — Owen routes. ⟵ RULED 2026-08-18, see below.\n"
             "\n> **RULED 2026-08-18: build it.**\n")
check("decision: a reconciled header is exempt",
      verdict(oi.check_headers_awaiting_a_decision_already_made), (True, False, 0))


# --------------------------------------------------------------------------
# 7 · open PRs vs entries (report only)
# --------------------------------------------------------------------------

stub_git(merged_refs=())
stub_prs([])
check("report: no open PRs is a pass with nothing to read",
      verdict(oi.check_open_prs_against_entries), (True, False, 0))

stub_prs([{"number": 304, "title": "#282 the thing", "headRefName": "x"}])
check("report: open PRs are reported, one row each",
      verdict(oi.check_open_prs_against_entries), (True, False, 1))

stub_prs_unavailable()
check("report: no gh is NO DATA, not a pass",
      verdict(oi.check_open_prs_against_entries), (False, True, 0))


# --------------------------------------------------------------------------
# Structural: every check the script runs has at least one case above.
# A check added without a fixture is the gap this file exists to close.
# --------------------------------------------------------------------------

_covered = {
    "check_duplicate_numbers", "check_claimed_merge_state",
    "check_open_pr_claims", "check_bar_results_live_under_their_own_item",
    "check_headers_claiming_not_started",
    "check_headers_awaiting_a_decision_already_made",
    "check_open_prs_against_entries",
}
check("coverage: every registered check has fixtures here",
      sorted(fn.__name__ for _, fn in oi.CHECKS if fn.__name__ not in _covered), [])

if FAILS:
    print("FAIL")
    for f in FAILS:
        print("  " + f)
    sys.exit(1)
print(f"oi-invariants-test: PASS ({RAN} checks)")
