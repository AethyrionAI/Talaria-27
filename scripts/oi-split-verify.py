#!/usr/bin/env python3
"""#261 archive-split verifier — proves bars 261-A/B/C against the pre-split file.

Usage: python3 scripts/oi-split-verify.py [base-commit]   (default: 8077ecb,
the commit the 2026-08-06 split was cut from). Compares git's pre-split
OPEN_ITEMS.md against the working-tree OPEN_ITEMS.md + OPEN_ITEMS-ARCHIVE.md:

  261-A  every leading-✅ item is IN the archive, and every moved block is
         byte-identical to its pre-split text (in fact every block in both
         files is, except #261's live block, which may only differ by an
         appended update note — checked as a prefix match).
  261-B  live ∪ archive = the original item-number set, the two files are
         disjoint, zero renumbering.
  261-C  live count + archive count = original count.

Exit 0 = all bars pass. Any failure prints the item and exits 1.
"""
import re
import subprocess
import sys
from pathlib import Path

BASE = sys.argv[1] if len(sys.argv) > 1 else "8077ecb"
REPO = Path(__file__).resolve().parent.parent
HDR = re.compile(r"^## ([0-9]+[A-Z]?)\.")
LEAD = re.compile(r"^## [0-9]+[A-Z]?\. ✅")
NOTE_EXEMPT = "261"  # the split lane's own entry: an appended dated note is expected


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


orig = parse(subprocess.run(
    ["git", "-C", str(REPO), "show", f"{BASE}:OPEN_ITEMS.md"],
    capture_output=True, text=True, check=True).stdout)
live = parse((REPO / "OPEN_ITEMS.md").read_text(encoding="utf-8"))
arch = parse((REPO / "OPEN_ITEMS-ARCHIVE.md").read_text(encoding="utf-8"))

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
