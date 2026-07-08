#!/usr/bin/env bash
#
# orphan-audit.sh — heuristic audit for built-but-unreferenced Swift surfaces (#49).
#
# Walks the app-side Swift tree (Talaria/, TalariaWidgets/, Shared/), extracts
# top-level type declarations, and reports the ones nothing else references.
# The dead Inbox shipped in every build for months because nothing did this.
#
# Output is a REVIEW LIST, NOT A DELETE LIST. Known false-positive sources:
# `@main` entry points (excluded), `#Preview`-only refs, protocol-only usage,
# string/reflection instantiation, `widgetURL`/intent-reached views, generated
# code. Some real orphans are intentional (dead-but-wanted): StatusCardView,
# and the Inbox until #45 wires it. The audit informs — it never auto-removes.
#
# Usage:
#   tools/orphan-audit.sh                  # print markdown report to stdout
#   tools/orphan-audit.sh -o report.md     # write the report to a file
#   tools/orphan-audit.sh --self-test      # exit non-zero unless the known
#                                          # Field Notes §5 graveyard is re-flagged
#                                          # (list pinned at the introducing commit;
#                                          # expect churn as those items get fixed)
#
# Tiers, strongest signal first (private/fileprivate types are skipped —
# file-scoped by design):
#   ORPHAN      — zero references anywhere: not in other files, not in tests,
#                 not even in the defining file outside the declaration and
#                 #Preview blocks (comments/strings stripped).
#   TEST-ONLY   — referenced only from TalariaTests/TalariaUITests.
#   SINGLE-SITE — all non-test references come from one file, on <=2 lines.
#                 Low signal (single-use views are normal SwiftUI) but this is
#                 the tier that catches dead gates: a route case nothing pushes,
#                 a fallback nothing exercises, a boolean that inits false.
#   FILE-LOCAL  — non-private but used only inside its own file; candidates
#                 for `private`, listed compactly for completeness.
#
# No dependencies beyond bash + python3 (present on the Mac Mini and OJAMD).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec python3 - "$REPO_ROOT" "$@" <<'PYEOF'
import argparse
import os
import re
import subprocess
import sys
from collections import defaultdict

APP_DIRS = ["Talaria", "TalariaWidgets", "Shared"]
TEST_DIRS = ["TalariaTests", "TalariaUITests"]
TYPE_KEYWORDS = ("struct", "class", "enum", "actor", "protocol")

# Field Notes §5 graveyard, pinned at the commit that introduced this script.
# --self-test asserts these still surface; expect churn as items get fixed
# (e.g. #45 wires InboxScreen and guts MockInboxService).
SELF_TEST_ORACLE = [
    "TalkModeScreen",
    "VoiceAttachmentSheet",
    "CaptureScreen",
    "LiveHermesClient",
    "MockInboxService",
]

DECL_RE = re.compile(
    r"^\s*"
    r"(?:@[A-Za-z_]\w*(?:\s*\([^)]*\))?\s+)*"          # attributes
    r"((?:(?:public|open|internal|fileprivate|private|final|indirect|dynamic)\s+)*)"
    r"(struct|class|enum|actor|protocol)\s+"
    r"([A-Za-z_]\w*)"
)
DECL_LINE_RE = re.compile(
    r"^\s*(?:@[A-Za-z_]\w*(?:\s*\([^)]*\))?\s+)*"
    r"(?:(?:public|open|internal|fileprivate|private|final|indirect|dynamic)\s+)*"
    r"(?:struct|class|enum|actor|protocol|extension)\s+"
)
IDENT_RE = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")


def strip_swift(text):
    """Blank comments and string-literal contents, preserving newlines and
    string-interpolation code (`"\\(expr)"` keeps expr). Handles nested block
    comments, triple-quoted strings, and raw #"…"# strings."""
    out = []
    i, n = 0, len(text)
    # Each stack frame: ("code", paren_depth) for interpolation code,
    # or a string frame ("str", terminator, hashes).
    stack = []
    mode = "code"
    block_depth = 0
    terminator = ""
    hashes = 0

    def emit(ch):
        out.append(ch if ch == "\n" else ch)

    while i < n:
        ch = text[i]
        if mode == "code":
            two = text[i : i + 2]
            if two == "//":
                mode = "line_comment"
                out.append("  ")
                i += 2
            elif two == "/*":
                mode = "block_comment"
                block_depth = 1
                out.append("  ")
                i += 2
            elif ch == "#" and re.match(r'#+"', text[i:]):
                m = re.match(r'(#+)(")', text[i:])
                hashes = len(m.group(1))
                if text[i + hashes : i + hashes + 3] == '"""':
                    terminator = '"""' + "#" * hashes
                    i += hashes + 3
                else:
                    terminator = '"' + "#" * hashes
                    i += hashes + 1
                out.append(" " * (len(terminator)))
                stack.append(("code_resume", 0))
                mode = "string"
            elif text[i : i + 3] == '"""':
                terminator = '"""'
                hashes = 0
                out.append("   ")
                i += 3
                stack.append(("code_resume", 0))
                mode = "string"
            elif ch == '"':
                terminator = '"'
                hashes = 0
                out.append(" ")
                i += 1
                stack.append(("code_resume", 0))
                mode = "string"
            elif ch == ")" and stack and stack[-1][0] == "interp":
                kind, depth, term, hsh = stack[-1]
                if depth == 0:
                    stack.pop()
                    out.append(" ")
                    i += 1
                    terminator, hashes = term, hsh
                    mode = "string"
                else:
                    stack[-1] = (kind, depth - 1, term, hsh)
                    out.append(ch)
                    i += 1
            elif ch == "(" and stack and stack[-1][0] == "interp":
                kind, depth, term, hsh = stack[-1]
                stack[-1] = (kind, depth + 1, term, hsh)
                out.append(ch)
                i += 1
            else:
                out.append(ch)
                i += 1
        elif mode == "line_comment":
            if ch == "\n":
                out.append("\n")
                mode = "code"
            else:
                out.append(" ")
            i += 1
        elif mode == "block_comment":
            two = text[i : i + 2]
            if two == "/*":
                block_depth += 1
                out.append("  ")
                i += 2
            elif two == "*/":
                block_depth -= 1
                out.append("  ")
                i += 2
                if block_depth == 0:
                    mode = "code"
            else:
                out.append("\n" if ch == "\n" else " ")
                i += 1
        elif mode == "string":
            esc = "\\" + "#" * hashes
            if text[i : i + len(esc) + 1] == esc + "(":
                # Interpolation: keep the inner expression as code.
                out.append(" " * (len(esc) + 1))
                i += len(esc) + 1
                stack.append(("interp", 0, terminator, hashes))
                mode = "code"
            elif hashes == 0 and ch == "\\":
                out.append("  ")
                i += 2
            elif text[i : i + len(terminator)] == terminator:
                out.append(" " * len(terminator))
                i += len(terminator)
                if stack and stack[-1][0] == "code_resume":
                    stack.pop()
                mode = "code"
            else:
                out.append("\n" if ch == "\n" else " ")
                i += 1
    return "".join(out)


def swift_files(root, dirs):
    found = []
    for d in dirs:
        base = os.path.join(root, d)
        for dirpath, _dirnames, filenames in os.walk(base):
            for f in sorted(filenames):
                if f.endswith(".swift"):
                    found.append(os.path.relpath(os.path.join(dirpath, f), root))
    return sorted(found)


def top_level_decls(stripped):
    """Yield (name, kind, is_private) for type declarations at brace depth 0."""
    depth = 0
    for line in stripped.splitlines():
        if depth == 0:
            m = DECL_RE.match(line)
            if m:
                mods = m.group(1)
                yield m.group(3), m.group(2), ("private" in mods or "fileprivate" in mods)
        depth += line.count("{") - line.count("}")
        depth = max(depth, 0)


def preview_lines(stripped):
    """Line numbers inside top-level #Preview blocks (a preview ref is not a
    real call site)."""
    inside, depth, in_preview = set(), 0, False
    for lineno, line in enumerate(stripped.splitlines(), 1):
        if not in_preview and depth == 0 and re.match(r"\s*#Preview\b", line):
            in_preview = True
        if in_preview:
            inside.add(lineno)
        depth += line.count("{") - line.count("}")
        depth = max(depth, 0)
        if in_preview and depth == 0 and "}" in line:
            in_preview = False
    return inside


def head_sha(root):
    try:
        return subprocess.run(
            ["git", "-C", root, "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "unknown"


def main():
    parser = argparse.ArgumentParser(prog="orphan-audit.sh")
    parser.add_argument("root")
    parser.add_argument("-o", "--output", help="write the markdown report here")
    parser.add_argument("--self-test", action="store_true",
                        help="fail unless the known Field Notes §5 graveyard is flagged")
    args = parser.parse_args()
    root = args.root

    app_files = swift_files(root, APP_DIRS)
    test_files = swift_files(root, TEST_DIRS)

    stripped = {}
    for rel in app_files + test_files:
        with open(os.path.join(root, rel), encoding="utf-8") as fh:
            stripped[rel] = strip_swift(fh.read())

    # name -> {kind, files}; private/fileprivate types are file-scoped by
    # design and never audited.
    decls = defaultdict(lambda: {"kind": "", "files": []})
    roots = set()  # names in @main files — entry points, never orphans
    skipped_private = 0
    for rel in app_files:
        is_main = "@main" in stripped[rel]
        for name, kind, is_private in top_level_decls(stripped[rel]):
            if is_private:
                skipped_private += 1
                continue
            decls[name]["kind"] = kind
            decls[name]["files"].append(rel)
            if is_main:
                roots.add(name)

    # file -> name -> [line numbers]
    ref_lines = {}
    previews = {rel: preview_lines(text) for rel, text in stripped.items()}
    declared = set(decls)
    for rel, text in stripped.items():
        per = defaultdict(list)
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in IDENT_RE.finditer(line):
                if m.group(0) in declared:
                    per[m.group(0)].append(lineno)
        ref_lines[rel] = per

    orphans, test_only, single_site, file_local = [], [], [], []
    for name in sorted(decls):
        if name in roots:
            continue
        defining = set(decls[name]["files"])
        app_refs = {f: ls for f, ls in ((f, ref_lines[f].get(name, [])) for f in app_files)
                    if f not in defining and ls}
        test_refs = {f: ls for f, ls in ((f, ref_lines[f].get(name, [])) for f in test_files)
                     if ls}
        # Same-file aliveness: refs in the defining file that are not the
        # declaration/extension line itself and not inside a #Preview block.
        own_refs = []
        for f in defining:
            lines = stripped[f].splitlines()
            for lineno in ref_lines[f].get(name, []):
                if lineno in previews[f]:
                    continue
                if DECL_LINE_RE.match(lines[lineno - 1]):
                    continue
                own_refs.append(lineno)
        entry = {
            "name": name,
            "kind": decls[name]["kind"],
            "defined": sorted(defining),
            "app_refs": app_refs,
            "test_refs": test_refs,
        }
        if not app_refs and not test_refs:
            (file_local if own_refs else orphans).append(entry)
        elif not app_refs:
            test_only.append(entry)
        elif len(app_refs) == 1 and len(next(iter(app_refs.values()))) <= 2:
            single_site.append(entry)

    lines = []
    lines.append("# Orphan-surface audit")
    lines.append("")
    lines.append(f"Generated by `tools/orphan-audit.sh` at commit `{head_sha(root)}`.")
    lines.append(f"Scanned {len(app_files)} app files ({', '.join(APP_DIRS)}) and "
                 f"{len(test_files)} test files ({', '.join(TEST_DIRS)}); "
                 f"{len(decls)} auditable top-level types "
                 f"({skipped_private} private/fileprivate types skipped — "
                 f"file-scoped by design).")
    lines.append("")
    lines.append("**This is a review list, not a delete list.** Known false positives:")
    lines.append("`#Preview`-only refs, protocol-only usage, string/reflection instantiation,")
    lines.append("`widgetURL`/intent-reached views, generated code. Some orphans are")
    lines.append("intentional (dead-but-wanted). Nothing here is removed automatically.")
    lines.append("")

    def section(title, blurb, entries, show_refs):
        lines.append(f"## {title} ({len(entries)})")
        lines.append("")
        lines.append(blurb)
        lines.append("")
        if not entries:
            lines.append("_None._")
            lines.append("")
            return
        for e in entries:
            where = ", ".join(f"`{f}`" for f in e["defined"])
            lines.append(f"- **{e['name']}** ({e['kind']}) — defined in {where}")
            if show_refs:
                refs = {**e["app_refs"], **e["test_refs"]} if e["app_refs"] else e["test_refs"]
                for f, ls in sorted(refs.items()):
                    locs = ", ".join(str(l) for l in ls[:6])
                    more = "…" if len(ls) > 6 else ""
                    lines.append(f"  - referenced from `{f}` line(s) {locs}{more}")
        lines.append("")

    section(
        "ORPHAN — zero references anywhere",
        "Nothing references these — not other files, not tests, not even their "
        "own file outside the declaration and `#Preview` blocks (comments and "
        "string literals stripped). Strongest signal.",
        orphans, False,
    )
    section(
        "TEST-ONLY — referenced only from tests",
        "No app-side call sites; kept alive only by the test target.",
        test_only, True,
    )
    section(
        "SINGLE-SITE — one referencing file, ≤2 lines",
        "Low signal on its own (single-use views are normal SwiftUI), but this "
        "tier catches dead gates: a route case nothing pushes, a fallback "
        "nothing exercises, a flag that inits `false` and never flips. "
        "Check the call site, not just the type.",
        single_site, True,
    )

    lines.append(f"## FILE-LOCAL — non-private, used only in its own file ({len(file_local)})")
    lines.append("")
    lines.append("Alive, but only within the defining file — candidates for `private`.")
    lines.append("")
    if file_local:
        lines.append(", ".join(f"`{e['name']}`" for e in file_local))
    else:
        lines.append("_None._")
    lines.append("")

    report = "\n".join(lines)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(report + "\n")
        print(f"wrote {args.output}")
    else:
        print(report)

    if args.self_test:
        flagged = {e["name"] for e in orphans + test_only + single_site}
        missing = [n for n in SELF_TEST_ORACLE if n not in flagged]
        if missing:
            print(f"\nSELF-TEST FAILED — not re-flagged: {', '.join(missing)}",
                  file=sys.stderr)
            sys.exit(1)
        print(f"\nself-test OK — all {len(SELF_TEST_ORACLE)} known graveyard types re-flagged",
              file=sys.stderr)


main()
PYEOF
