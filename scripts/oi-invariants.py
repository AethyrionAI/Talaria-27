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

A fourth surfaced on 2026-09-02, and it is the one this script was blindest to:

  4. An entry — its header, its 9,402 bytes, all of it — was DELETED from
     OPEN_ITEMS.md by a squash during a tracker rebase. Its index line
     survived, so the top-of-file map still advertised a live item. This
     script returned PASS on that commit and on the nine after it. Every check
     here validated the text it was GIVEN; none had any notion of the entry
     SET, so an entry that is simply absent violated nothing.

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
    scripts/oi-invariants.py                        # all checks, baseline HEAD
    scripts/oi-invariants.py --baseline origin/main # before opening a PR
    scripts/oi-invariants.py --quiet                # exit code only
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
# 2026-08-23 (Opus-week audit): the house also writes "PR #329 OPEN" — the PR
# NUMBER between the words — and that spelling sat stale on two corrected
# headers for 2+ days while this check PASSed. The number is now optional
# inside the phrase. Same #300 shape, one spelling further out.
STALE_MERGE = re.compile(
    r"NOT MERGED|awaiting review|PR(?: #\d+[A-Za-z]?)? open|merge is Owen's review", re.I)
# This tracker RETRACTS a claim by striking it through and writing the
# correction beside it — `~~NOT MERGED — awaiting review.~~ **✅ MERGED as …**`
# is the house idiom (#328, archived #322, #368 all use it). A struck span is
# a claim that is no longer being made, so it must not trip the check below.
# Deliberately SINGLE-LINE (no DOTALL): a span that opens on one line and
# closes on another is not stripped, so an unbalanced `~~` can only produce a
# FALSE ALARM, never a missed one. Fail safe, same posture as the gate's
# failure-advice classifier.
STRUCK = re.compile(r"~~.+?~~")
# 2026-08-26 (#373, executing #342's residual). Markdown BOLD could switch this
# check off, and #409 found that out by using it as a workaround: `**NOT**
# merged` renders identically to `NOT merged` and matches nothing, because the
# asterisks sit between the two words in the raw bytes. That is the archived
# #300 shape — a discriminator that cannot match the text it polices — and it
# cuts the dangerous way here: a real stale claim written `**NOT** MERGED`
# would sail past. Stripped before matching so the check reads what a human
# reads. ASTERISKS ONLY: `_` is emphasis in markdown but it is also every
# `route_source`-shaped identifier in this tracker, and mangling those buys
# nothing.
EMPHASIS = re.compile(r"\*{1,3}")
# ...and the same lane fixes the FALSE POSITIVE that made that workaround
# necessary. "Deliberately not merged with: <a finding>" is a TOPIC merge —
# English, not git — and #409 tripped this check twice with it, once in the
# entry and once in the paragraph describing the trip. Both halves of the
# check's reasoning were true and the conclusion was false.
#
# The narrowing is scoped to the sense, not to the words: `not merged with
# main` / `with origin/x` / ``with `branch` `` are GIT claims and still fire.
# That matters more than the false positive did — a narrowing that blinds a
# real catch is the only way this edit could be worse than the bug, and it is
# pinned in `oi-invariants-test.py` in both directions.
TOPIC_MERGE = re.compile(
    r"\bnot\s+merged\s+with\b(?!\s+(?:main\b|origin/|`))", re.I)


def claimable(text: str) -> str:
    """What is left of `text` once the spans that are not live git claims are
    removed: retracted (struck) prose, markdown emphasis, and the English
    'merged with <a topic>' sense."""
    return TOPIC_MERGE.sub("", EMPHASIS.sub("", STRUCK.sub("", text)))


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


# --------------------------------------------------------------------------
# The entry SET. 2026-09-02.
# --------------------------------------------------------------------------
# Deliberately a BROADER header shape than `HEADER` above. `HEADER` polices the
# canonical form; this one asks only "is this number present anywhere", and a
# header the canonical pattern cannot see must read as PRESENT-but-malformed
# (which `check_headers_not_at_line_start` and the counting rules already
# police) rather than as DROPPED. Broader here fails safe; narrower would
# manufacture phantom drops out of formatting.
SET_HEADER = re.compile(r"(?m)^## (\d+[A-Za-z]?)[.:]")
# A line of the live board's INDEX section: `- **#420** 🔧 …`.
INDEX_LINE = re.compile(r"(?m)^- \*\*#(\d+[A-Za-z]?)\*\*")
# Rebound by `--baseline`. HEAD by default; see `_baseline_numbers`.
BASELINE_REF = "HEAD"
BASELINE_FALLBACK = "origin/main"


def _numeric(item: str) -> tuple[int, str]:
    """Sort `420`, `216A`, `9` the way a reader expects."""
    m = re.match(r"(\d+)([A-Za-z]?)", item)
    return int(m.group(1)), m.group(2)


def _tree_numbers() -> tuple[set[str], set[str], set[str]] | None:
    """(live entries, archived entries, index lines) from the WORKING TREE, or
    None when the live board cannot be read."""
    if not LIVE.exists():
        return None
    live_text = LIVE.read_text(encoding="utf-8")
    arch_text = ARCHIVE.read_text(encoding="utf-8") if ARCHIVE.exists() else ""
    return (set(SET_HEADER.findall(live_text)),
            set(SET_HEADER.findall(arch_text)),
            set(INDEX_LINE.findall(live_text)))


def _baseline_numbers() -> tuple[set[str] | None, str]:
    """The entry-number set at a git commit, and the ref it came from.

    WHY `HEAD` BY DEFAULT. It exists in every clone with no network and no
    remote configured; it is the last state a human reviewed; and it is what an
    UNCOMMITTED edit is measured against, which is the moment a drop is
    cheapest to undo. `origin/main` is the fallback only for a checkout where
    HEAD cannot be read at all.

    WHY A LANE SHOULD PASS `--baseline origin/main` ANYWAY. The drop this check
    exists for happened inside a SQUASH of a branch: the branch's own
    HEAD-vs-tree was clean at every step, and only branch-vs-main was not. A
    default that is always available and a flag that asks the sharper question
    is the honest split — so the printed summary always names the ref it used,
    and never lets a reader assume the sharper one was asked.

    An archive that does not exist at the baseline is the pre-split shape and
    contributes an empty set: git answering None for that ONE path while the
    live file read fine is a healthy git reporting an absent path, not a broken
    one — a broken git would have failed the live read first.
    """
    for ref in dict.fromkeys((BASELINE_REF, BASELINE_FALLBACK)):
        live = git("show", f"{ref}:{LIVE.name}")
        if live is None:
            continue
        arch = git("show", f"{ref}:{ARCHIVE.name}")
        return (set(SET_HEADER.findall(live))
                | set(SET_HEADER.findall(arch or "")), ref)
    return None, BASELINE_REF


def check_entry_set_against_baseline() -> tuple[bool, str, list[str]]:
    """An entry may MOVE between the two files. It may never disappear.

    WHY: on 2026-09-02 a squash deleted one entry and its 9,402 bytes from
    OPEN_ITEMS.md during a tracker rebase — the lane was appending blocks to
    its neighbours and the union resolution dropped the block between them.
    The entry was in neither file afterwards. Nine consecutive commits then
    passed this script, because every check it had reads the text it is given
    and asks whether that text is self-consistent. It was: an absent entry
    contradicts nothing.

    The archive-split verifier has exactly this notion and cannot help — it is
    pinned to a historical commit pair BY DESIGN, so that its proof cannot rot
    as the tracker evolves, and it never reads the working tree. This is the
    live complement, not a replacement: same property, opposite time axis.

    A SUPERSET, not equality. Filing new items is the normal case, and a sweep
    moving thirty entries from the live board to the archive must not read as
    thirty drops — the union is what is conserved, never either file alone.
    """
    if git("rev-parse", "--git-dir") is None:
        return False, "NO DATA — not a git repo / git unavailable", []
    tree = _tree_numbers()
    if tree is None:
        return False, "NO DATA — OPEN_ITEMS.md not found", []
    live, arch, _ = tree
    base, ref = _baseline_numbers()
    if base is None:
        return False, (f"NO DATA — cannot read the tracker at `{BASELINE_REF}` "
                       f"or `{BASELINE_FALLBACK}`"), []
    dropped = sorted(base - (live | arch), key=_numeric)
    if dropped:
        return False, f"{len(dropped)} entr(y/ies) at `{ref}` are now in NEITHER file", [
            f"#{n} exists at `{ref}` and in neither OPEN_ITEMS.md nor "
            f"OPEN_ITEMS-ARCHIVE.md — an entry may move between the two files, "
            f"never vanish; recover its block with "
            f"`git show {ref}:OPEN_ITEMS.md` (or the archive) and re-file it"
            for n in dropped]
    return True, (f"all {len(base)} entries at `{ref}` survive "
                  f"({len(live)} live + {len(arch)} archived)"), []


def check_index_lines_resolve() -> tuple[bool, str, list[str]]:
    """The live board's INDEX must point at entries that exist.

    WHY: when the 2026-09-02 squash deleted the entry, its index line survived.
    A reader of the map saw a live item; the item was gone. That half of the
    defect is decidable from the file ALONE, with no git and no baseline — so
    it still fires in a fresh clone of the offending commit, where the set
    check has nothing to compare against. Two independent detectors for one
    event is the point, not redundancy.

    An index line pointing INTO the archive resolves and is not a finding: two
    do exactly that today, for items closed after the last regeneration.

    AN ENTRY WITH NO INDEX LINE IS ADVISORY, NOT A FAILURE — and that was
    measured before it was decided, not assumed. The index announces itself as
    a regenerated map rather than a guarantee, and two live entries filed after
    the last regeneration have no line. They also had none at the commit this
    check's own historical control must PASS on, so failing them would have
    failed that control for a reason unrelated to the defect. Advisory rows are
    printed under a PASS, the same shape the open-PR reporter uses.
    """
    tree = _tree_numbers()
    if tree is None:
        return False, "NO DATA — OPEN_ITEMS.md not found", []
    live, arch, index = tree
    orphans = sorted(index - (live | arch), key=_numeric)
    unlisted = sorted(live - index, key=_numeric)
    advisory = [
        f"advisory: #{n} is a live entry with no index line — the index is a "
        f"regenerated map, so this is drift to fold into the next sweep, not a "
        f"defect" for n in unlisted]
    if orphans:
        rows = [
            f"#{n} has an index line but no entry in either file — restore the "
            f"entry, or drop the index line if the item never existed"
            for n in orphans]
        return False, (f"{len(orphans)} index line(s) point at an entry that is "
                       f"in neither file"), rows + advisory
    if unlisted:
        return True, (f"all {len(index)} index lines resolve; "
                      f"{len(unlisted)} live entr(y/ies) not in the index "
                      f"(advisory)"), advisory
    return True, (f"all {len(index)} index lines resolve, and every live entry "
                  f"has one"), []


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
        if not STALE_MERGE.search(claimable(body)):
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
    items they name, for a human to eyeball. Reporting is the honest ceiling.

    2026-08-26 (#373): this used to shell out to `gh` itself, with its own
    argument list and its own error handling, while `_open_prs()` sat three
    functions away doing the same thing. Two call sites meant two behaviours to
    keep in step and — the reason it mattered here — the second one could not be
    reached by a fixture at all, so the only check in this file with no test was
    the one duplicating code. Same output, one `gh` call site."""
    if git("rev-parse", "--git-dir") is None:
        return False, "NO DATA — git unavailable", []
    prs, why = _open_prs()
    if why:
        return False, f"NO DATA — {why}", []
    rows = [f"{pr.get('number')}\t{pr.get('title', '')}" for pr in prs]
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
        if not STALE_MERGE.search(claimable(line)):
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
# `⟵` is the house marker for a clause APPENDED to a header rather than a
# rewrite of it — every correction and every late verdict uses it. Keying on
# the marker rather than on one phrase ("HEADER CORRECTED") means a header
# updated with "⟵ ✅ BUILT" is recognised too; keying on the phrase alone
# flagged exactly that shape twice on 2026-08-23.
CORRECTION_CLAUSE = re.compile(r"⟵.*$", re.I)
# Build/completion words ONLY. `RAN` and `CLEARED` were in this set for one
# revision and the mutation test caught them: #340's wrong clause opened with
# "the artifact was CLEARED 2026-08-22", which is a device chore, not a build,
# and it exempted the very text this check was narrowed to catch. `\bBUILT\b`
# deliberately does not match "unbuilt" — no word boundary inside it.
ACKNOWLEDGES_BUILD = re.compile(
    r"\b(BUILT|MERGED|SHIPPED|DEPLOYED|FIXED|DONE|MET|CLOSED|MOOT)\b", re.I
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


# A header still saying the decision is Owen's, over a body that records his
# ruling. Sibling of NOT_STARTED-over-a-result: same failure (the header
# disagrees with its own body), different word.
AWAITING_DECISION = re.compile(
    r"Owen routes|Owen'?s call|decision owed|Owen must route|awaiting Owen|Owen'?s decision",
    re.I,
)
DECISION_MADE = re.compile(r"\bRULED\b|Owen (?:ruled|elected|granted)", re.I)


def check_headers_awaiting_a_decision_already_made() -> tuple[bool, str, list[str]]:
    """A header saying a decision is owed, over a body that records it made.

    WHY: on 2026-08-23 a night build list booked five items and **four were not
    buildable**. Two of them — #365 and #381 — had headers reading "the FIX is
    unrouted and is Owen's call" and "a follow-up affordance is Owen's call"
    over bodies where Owen had ruled days earlier. The list was assembled from
    headers, so it elected work that did not exist, and the session that ran it
    discovered this one entry at a time.

    That is the same disagreement `check_headers_claiming_not_started` catches,
    wearing a different word: NOT STARTED is about BUILD state, this is about
    DECISION state, and a tracker that tells you a call is owed when it was
    already made wastes exactly as much time.

    Its first run flagged three more (#308/#378/#379), so this is not a
    one-off shape.

    Exempt, same rule as its sibling: a header carrying the house `⟵` clause
    has been reconciled deliberately — some items are legitimately part-ruled,
    and the honest fix is an appended clause, not a rewritten header.
    """
    if not LIVE.exists():
        return False, "NO DATA — OPEN_ITEMS.md not found", []
    text = LIVE.read_text(encoding="utf-8")
    parts = re.split(r"^## (\d+[A-Z]?)\.", text, flags=re.M)
    offenders: list[str] = []
    for i in range(1, len(parts) - 1, 2):
        num, body = parts[i], parts[i + 1]
        header, _, rest = body.partition("\n")
        if not AWAITING_DECISION.search(header):
            continue
        if CORRECTION_CLAUSE.search(header):
            continue
        if DECISION_MADE.search(rest):
            offenders.append(
                f"#{num}: header says the decision is owed, but the body records a "
                f"ruling — correct the header, or say which part is still open"
            )
    if offenders:
        return False, f"{len(offenders)} header(s) await a decision the body records as made", offenders
    return True, "no header awaits a decision its own body records as made", []


def check_headers_not_at_line_start() -> tuple[bool, str, list[str]]:
    """#416, 2026-08-27. #211A's header was GLUED to the end of a blockquote
    line — `...as its verification.)## 211A. offer-instead-of-act...` — so it
    was not at a line start, and `^## ` under re.M is the anchor EVERY tool
    here uses: this script, oi-split-verify.py, and the sweep scripts. The
    entry was therefore invisible to all of them. It was never counted, and
    every check above silently skipped it for as long as the glue existed.

    That is the worst shape a tracker defect can take: the file reads fine to a
    human, the verifier says PASS, and the PASS is over a smaller set than
    anyone believes. A check that cannot see part of its own subject is not a
    check — so the blind spot gets its own invariant.

    Deliberately scoped to the LIVE file's ENTRY headers. The counting-rules
    prose quotes `## 216A.` as its example of the canonical form, and that is
    documentation, not an entry — so a bare occurrence is only a finding when
    it is glued to NON-WHITESPACE text, which is what the real defect looked
    like and what an example never does.
    """
    if not LIVE.exists():
        return False, "NO DATA — OPEN_ITEMS.md not found", []
    text = LIVE.read_text()
    # A header preceded on its own line by other, non-whitespace content.
    glued = re.findall(r"(?m)^.*\S+(## \d+[A-Z]?\. )", text)
    if glued:
        return (
            False,
            f"{len(glued)} entry header(s) not at a line start — invisible to every ^## tool",
            [g.strip() for g in glued],
        )
    n = len(re.findall(r"(?m)^## \d+[A-Z]?\.", text))
    return True, f"all {n} live entry headers start their own line", []


CHECKS = [
    ("duplicate item numbers", check_duplicate_numbers),
    ("entry headers at a line start", check_headers_not_at_line_start),
    ("entry set vs the git baseline", check_entry_set_against_baseline),
    ("index lines resolve to entries", check_index_lines_resolve),
    ("claimed merge state vs git", check_claimed_merge_state),
    ("headers claiming an open PR", check_open_pr_claims),
    ("bar verdicts filed under their own item", check_bar_results_live_under_their_own_item),
    ("headers claiming NOT STARTED over a result", check_headers_claiming_not_started),
    ("headers awaiting a decision already made", check_headers_awaiting_a_decision_already_made),
    ("open PRs vs entries (report only)", check_open_prs_against_entries),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument(
        "--baseline", default=BASELINE_REF, metavar="REF",
        help="git ref the entry set must be a superset of (default: HEAD). "
             "Pass origin/main before opening a PR — a squash of a branch is "
             "where an entry has actually been lost, and HEAD cannot see that.")
    args = ap.parse_args()
    globals()["BASELINE_REF"] = args.baseline

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
