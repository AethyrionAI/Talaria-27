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

# --------------------------------------------------------------------------
# 0 · entry headers at a line start (#416)
# --------------------------------------------------------------------------
# The POSITIVE case is the real 2026-08-27 defect, reproduced verbatim in
# shape: a header glued to the tail of a blockquote line. Every `^## ` tool —
# this script, oi-split-verify.py, the sweep scripts — was blind to #211A for
# as long as it looked like this, and reported PASS over a set that silently
# excluded it.
with_tracker("## 10. one\n\n## 11. two\n")
check("headers: all at line start passes",
      verdict(oi.check_headers_not_at_line_start), (True, False, 0))

with_tracker("## 10. one\n\n> evidence standing as its verification.)## 11A. two\n")
check("headers: a glued header FAILS (the #211A defect)",
      verdict(oi.check_headers_not_at_line_start), (False, False, 1))

# The counting rules QUOTE `## 216A.` as the canonical form. That is
# documentation, not an entry, and it must not trip the check — which is why
# the pattern requires non-whitespace glue rather than merely "not at column 0".
with_tracker("> > **CANONICAL HEADER FORM — `## N.` or `## NL.` for lanes\n"
             "> > (`## 216A.`). There is exactly one form.**\n\n## 10. one\n")
check("headers: the counting-rules example is not a finding",
      verdict(oi.check_headers_not_at_line_start), (True, False, 0))

oi.LIVE = oi.Path(os.path.join(_TMP.name, "absent-tracker.md"))
check("headers: a missing tracker is NO DATA, not a pass",
      verdict(oi.check_headers_not_at_line_start), (False, True, 0))

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
# 8 · the entry SET vs the git baseline — an entry may MOVE, never disappear
# --------------------------------------------------------------------------
# POSITIVE CASE is the 2026-09-02 event: a squash deleted one entry and its
# 9,402 bytes from OPEN_ITEMS.md during a tracker rebase, and this script
# returned PASS on that commit and on the nine after it. Every check above
# validates the text it is GIVEN, so an entry that is simply absent was not a
# violation of anything.


def stub_baseline(live: str, archive: str | None = "", refs=("HEAD",)):
    """A `git` that also serves `git show <ref>:<file>` from crafted text, so a
    fixture can pose a BASELINE without committing anything.

    `archive=None` means the archive file does not exist at that commit — the
    real pre-split shape, and the one case where git legitimately answers None
    for a path while being perfectly healthy.
    """
    def _git(*args):
        if args[:2] == ("rev-parse", "--git-dir"):
            return ".git\n"
        if args[:1] == ("show",):
            ref, _, path = args[1].partition(":")
            if ref not in refs:
                return None
            if path == "OPEN_ITEMS.md":
                return live
            if path == "OPEN_ITEMS-ARCHIVE.md":
                return archive
        return None
    oi.git = _git


BASE_LIVE = "## 10. one\n\n## 11. two\n"
BASE_ARCH = "## 12. three\n"

with_tracker(BASE_LIVE, BASE_ARCH)
stub_baseline(BASE_LIVE, BASE_ARCH)
check("entry-set: an unchanged tracker passes",
      verdict(oi.check_entry_set_against_baseline), (True, False, 0))

# POSITIVE CASE — the drop, exactly as it happened: gone from live, and not in
# the archive either.
with_tracker("## 10. one\n", BASE_ARCH)
stub_baseline(BASE_LIVE, BASE_ARCH)
check("entry-set: an entry dropped from BOTH files is caught",
      verdict(oi.check_entry_set_against_baseline), (False, False, 1))

# 424-C — sweep 14 moves ~30 entries live -> archive in ONE commit. A move is
# not a drop, and a check that cannot tell them apart would be turned off the
# first time a sweep ran.
with_tracker("## 10. one\n", "## 12. three\n\n## 11. two\n")
stub_baseline(BASE_LIVE, BASE_ARCH)
check("entry-set: a live -> archive MOVE is not a drop",
      verdict(oi.check_entry_set_against_baseline), (True, False, 0))

# ...and the reverse move, which #261's rules explicitly allow: a reopened item
# moves its block back to the live board.
with_tracker("## 10. one\n\n## 11. two\n\n## 12. three\n", "")
stub_baseline(BASE_LIVE, BASE_ARCH)
check("entry-set: an archive -> live move is not a drop either",
      verdict(oi.check_entry_set_against_baseline), (True, False, 0))

# A lane filing a NEW item is the normal case: the invariant is a superset, not
# equality.
with_tracker(BASE_LIVE + "\n## 13. new\n", BASE_ARCH)
stub_baseline(BASE_LIVE, BASE_ARCH)
check("entry-set: filing a new item is not a violation",
      verdict(oi.check_entry_set_against_baseline), (True, False, 0))

# Several at once are reported one row each — a sweep that loses three entries
# must not read as one problem.
with_tracker("## 10. one\n", "")
stub_baseline(BASE_LIVE, BASE_ARCH)
check("entry-set: every dropped entry gets its own row",
      verdict(oi.check_entry_set_against_baseline), (False, False, 2))

# An archive that did not exist at the baseline is the pre-split shape, not an
# error: git answers None for the path while being entirely healthy.
with_tracker(BASE_LIVE, "")
stub_baseline(BASE_LIVE, None)
check("entry-set: no archive at the baseline is a clean baseline, not NO DATA",
      verdict(oi.check_entry_set_against_baseline), (True, False, 0))

# The fallback: HEAD unreadable, origin/main answers.
with_tracker(BASE_LIVE, BASE_ARCH)
stub_baseline(BASE_LIVE, BASE_ARCH, refs=("origin/main",))
check("entry-set: falls back to origin/main when HEAD cannot be read",
      verdict(oi.check_entry_set_against_baseline), (True, False, 0))

# NO DATA IS NOT A PASS — the whole file's posture. A baseline nothing can read
# must not silently become an empty set, which would pass over any drop at all.
with_tracker(BASE_LIVE, BASE_ARCH)
stub_baseline(BASE_LIVE, BASE_ARCH, refs=())
check("entry-set: an unreadable baseline is NO DATA, not a pass",
      verdict(oi.check_entry_set_against_baseline), (False, True, 0))

oi.git = lambda *a: None
check("entry-set: no git is NO DATA, not a pass",
      verdict(oi.check_entry_set_against_baseline), (False, True, 0))

stub_baseline(BASE_LIVE, BASE_ARCH)
with_tracker(BASE_LIVE, BASE_ARCH)
oi.LIVE = oi.Path(os.path.join(_TMP.name, "absent-tracker.md"))
check("entry-set: a missing tracker is NO DATA, not a pass",
      verdict(oi.check_entry_set_against_baseline), (False, True, 0))


# --------------------------------------------------------------------------
# 9 · index lines resolve to entries
# --------------------------------------------------------------------------
# The index line for the dropped entry SURVIVED the squash, so the top-of-file
# map advertised a live item that no longer existed. This check needs no
# baseline at all — it is internally decidable — which is why it catches the
# same event in a fresh clone, where the drop check has nothing to compare to.

with_tracker("- **#10** a thing\n- **#12** an archived thing\n\n## 10. one\n",
             "## 12. three\n")
check("index: every line resolving to an entry passes",
      verdict(oi.check_index_lines_resolve), (True, False, 0))

# POSITIVE CASE — the surviving index line over a deleted entry.
with_tracker("- **#10** a thing\n- **#99** a thing that is not here\n\n## 10. one\n")
check("index: a line pointing at no entry in EITHER file is caught",
      verdict(oi.check_index_lines_resolve), (False, False, 1))

# A line pointing INTO the archive is correct, not an orphan — two live index
# lines do exactly this today, and reading them as orphans would make the
# check's first run a false alarm.
with_tracker("- **#10** a thing\n- **#118** an archived thing\n\n## 10. one\n",
             "## 118. archived\n")
check("index: a line pointing into the archive resolves",
      verdict(oi.check_index_lines_resolve), (True, False, 0))

# An entry with NO index line is ADVISORY, not a failure. Measured before
# writing this: the index is a regenerated map and two live entries filed after
# the last regeneration have no line — including at the commit this lane must
# PASS on. A FAIL here would fail that historical control for the wrong reason.
with_tracker("- **#10** a thing\n\n## 10. one\n\n## 11. filed after the regen\n")
check("index: an entry with no index line is advisory, not a failure",
      verdict(oi.check_index_lines_resolve), (True, False, 1))

# ...and an orphan still FAILS while advisory rows are present, rather than
# either one hiding the other.
with_tracker("- **#99** not here\n\n## 10. one\n")
check("index: an orphan fails even alongside advisory rows",
      verdict(oi.check_index_lines_resolve), (False, False, 2))

oi.LIVE = oi.Path(os.path.join(_TMP.name, "absent-tracker.md"))
check("index: a missing tracker is NO DATA, not a pass",
      verdict(oi.check_index_lines_resolve), (False, True, 0))


# --------------------------------------------------------------------------
# Structural: every check the script runs has at least one case above.
# A check added without a fixture is the gap this file exists to close.
# --------------------------------------------------------------------------

_covered = {
    "check_headers_not_at_line_start",
    "check_entry_set_against_baseline", "check_index_lines_resolve",
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
