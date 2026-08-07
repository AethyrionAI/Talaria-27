#!/usr/bin/env python3
"""#261 archive-split verifier — a ONE-SHOT PROOF OF A HISTORICAL COMMIT RANGE.

    pre-split  8077ecb  docs(#261): file the OI cleanup lane; move security
                        mechanics to an out-of-repo addendum
    split      af59ea7  docs(#261): the archive split — 163 closed/terminal
                        items move VERBATIM to OPEN_ITEMS-ARCHIVE.md

**This is NOT a live invariant check and it does NOT read the working tree.**
Both sides are read from git at the two pinned commits above, so the proof is
re-runnable forever and cannot rot as the tracker evolves.

Usage: python3 scripts/oi-split-verify.py [pre-split-commit [split-commit]]

Bars proved (pre-registered for the #261 lane, all green at af59ea7):

  261-A  every leading-✅ item is IN the archive, and every moved block is
         byte-identical to its pre-split text (in fact every block in both
         files is, except #261's own live block, which may differ only by an
         appended update note — checked as a prefix match).
  261-B  live ∪ archive = the original item-number set, the two files are
         disjoint, zero renumbering.
  261-C  live count + archive count = original count.

WHY IT IS PINNED AND NOT LIVE (2026-08-07). The base was never wrong —
8077ecb is af59ea7's parent, i.e. the real pre-split commit — but this script
used to compare that base against the WORKING TREE, which made it decay into
a false alarm the moment the tracker moved on. Since the split, items #262+
were filed and the 2026-08-06 reconciliation audit amended entries in BOTH
files, including eight ARCHIVED ones (#34, #55, #83, #90, #203, #258, #259,
#260). That is THE CLOSE-OUT RULE working exactly as intended — corrections
go UPSTREAM, to the stale claim's own home — so byte-identity between the
pre-split text and today's files is permanently unsatisfiable BY DESIGN.
Measured on an unmodified checkout of main: the old working-tree form
reported 27 failures (26 × 261-A, 1 × 261-C, 12 items "invented") while
nothing whatsoever was wrong with the tracker. A verifier that cries wolf on
a clean tree is worse than no verifier, so the range is now pinned at both
ends. Do not "restore" the working-tree comparison — it is falsified.

(The properties that ARE durable — the two files staying disjoint, and no
item ever being lost or renumbered — held at the 2026-08-07 check. Proving
them going forward would be a different, live script; it is not this one.)

Exit 0 = the historical split is proved. Any failure prints the item, exits 1.
"""
import re
import subprocess
import sys
from pathlib import Path

# Both ends pinned: this verifies a historical commit range, not the worktree.
BASE = sys.argv[1] if len(sys.argv) > 1 else "8077ecb"   # pre-split
SPLIT = sys.argv[2] if len(sys.argv) > 2 else "af59ea7"  # the split itself
REPO = Path(__file__).resolve().parent.parent
HDR = re.compile(r"^## ([0-9]+[A-Z]?)\.")
LEAD = re.compile(r"^## [0-9]+[A-Z]?\. ✅")
NOTE_EXEMPT = "261"  # the split lane's own entry: an appended dated note is expected


def show(commit, path):
    """Read a file's bytes-as-text from git at `commit` (never the worktree)."""
    r = subprocess.run(["git", "-C", str(REPO), "show", f"{commit}:{path}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"cannot read {path} at {commit}: {r.stderr.strip()}")
    return r.stdout


def parse(text):
    """Return ordered [(item_id, block_bytes_verbatim)]."""
    lines = text.splitlines(keepends=True)
    starts = [i for i, ln in enumerate(lines) if HDR.match(ln)]
    out = []
    for j, s in enumerate(starts):
        e = starts[j + 1] if j + 1 < len(starts) else len(lines)
        out.append((HDR.match(lines[s]).group(1), "".join(lines[s:e])))
    return out


def blocks_by_id(blocks):
    d = {}
    for item_id, text in blocks:
        d.setdefault(item_id, []).append(text)
    return d


orig = parse(show(BASE, "OPEN_ITEMS.md"))
live = parse(show(SPLIT, "OPEN_ITEMS.md"))
arch = parse(show(SPLIT, "OPEN_ITEMS-ARCHIVE.md"))

orig_by, live_by, arch_by = blocks_by_id(orig), blocks_by_id(live), blocks_by_id(arch)
failures = []

# 261-B — set identity, disjointness, zero renumbering
overlap = set(live_by) & set(arch_by)
if overlap:
    failures.append(f"261-B: items in BOTH files: {sorted(overlap)}")
union = set(live_by) | set(arch_by)
if union != set(orig_by):
    failures.append(f"261-B: lost={sorted(set(orig_by) - union)} "
                    f"invented={sorted(union - set(orig_by))}")

# 261-A — every leading-✅ item archived; every block byte-identical
for item_id, texts in orig_by.items():
    if all(LEAD.match(t) for t in texts) and item_id not in arch_by:
        failures.append(f"261-A: leading-✅ item #{item_id} missing from archive")

for item_id, texts in orig_by.items():
    dest = arch_by if item_id in arch_by else live_by
    new_texts = dest.get(item_id, [])
    if len(new_texts) != len(texts):
        failures.append(f"261-A: #{item_id} block count {len(texts)} -> {len(new_texts)}")
        continue
    for k, (old, new) in enumerate(zip(texts, new_texts)):
        if old == new:
            continue
        if item_id == NOTE_EXEMPT and dest is live_by and new.startswith(old.rstrip("\n")):
            continue  # the one permitted change: a note appended to #261 itself
        failures.append(f"261-A: #{item_id} block {k + 1} NOT byte-identical")

# 261-C — counts
if len(live_by) + len(arch_by) != len(orig_by):
    failures.append(f"261-C: {len(live_by)} live + {len(arch_by)} archived "
                    f"!= {len(orig_by)} original")

print("HISTORICAL RANGE CHECK — this verifies the 2026-08-06 #261 split as it")
print("was committed. It does NOT inspect the working tree; a dirty or evolved")
print("tracker cannot affect this result.")
print(f"  pre-split {BASE}:OPEN_ITEMS.md")
print(f"  split     {SPLIT}:OPEN_ITEMS.md + OPEN_ITEMS-ARCHIVE.md\n")
print(f"original: {len(orig_by)} items / {len(orig)} blocks")
print(f"live:     {len(live_by)} items / {len(live)} blocks")
print(f"archive:  {len(arch_by)} items / {len(arch)} blocks")
if failures:
    print("\nFAIL")
    for f in failures:
        print(" -", f)
    sys.exit(1)
print("\nPASS — 261-A (verbatim, every ✅ archived), 261-B (set identity, "
      "disjoint, no renumbering), 261-C (counts).")
print("The 2026-08-06 split is proved. This says nothing about today's tracker.")
