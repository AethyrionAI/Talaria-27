#!/usr/bin/env python3
"""Test for #392's scorer — and the ANTI-DRIFT check that is its whole point.

Two implementations of one classifier is how they drift until they disagree
about a boundary case. The codebase already records that failure for date
parsers (*"a second date parser is how two decoders drift"*), and #300 records
the version where a classifier could not match the text it policed.

So this does two things:

 1. Behaviour, against the VERBATIM strings the device emitted.
 2. **PARITY — it parses `DeclineAttributionScorer.swift` and asserts the three
    phrase lists match Python's, element for element.** Change one side and
    this fails. That is cheaper and more reliable than a shared fixture file,
    which can itself go stale against both.

Run: scripts/mac/score-decline-attribution-test.py   (~1 s, no build)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import importlib
scorer = importlib.import_module("score-decline-attribution".replace("-", "_")) \
    if False else None  # noqa: E501  (hyphenated module: loaded explicitly below)

import importlib.util
_spec = importlib.util.spec_from_file_location(
    "score_decline_attribution", Path(__file__).parent / "score-decline-attribution.py")
scorer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scorer)

SWIFT = Path(__file__).resolve().parents[2] / "Talaria/Services/Support/DeclineAttributionScorer.swift"

failures: list[str] = []


def check(label: str, got, want):
    if got != want:
        failures.append(f"{label}: got {got!r}, want {want!r}")


# --- 1. behaviour, on the two real device replies -----------------------------

DEVICE_1 = ("It looks like the event wasn't created — your calendar didn't accept "
            "the request. Let me know if you'd like to try again or adjust something.")
DEVICE_2 = ("It seems the event couldn't be added — let me know if you'd like to "
            "try again or adjust anything.")

check("device instance 1", scorer.verdict(DEVICE_1), scorer.ATTRIBUTED_TO_TOOL)
check("device instance 2", scorer.verdict(DEVICE_2), scorer.ATTRIBUTED_TO_TOOL)

# The ordering rule: naming the user wins over an incidental outcome phrase.
check("user wins over outcome phrase",
      scorer.verdict("You declined, so the event wasn't created."),
      scorer.ATTRIBUTED_TO_USER)
check("user wins over tool phrase",
      scorer.verdict("You cancelled — the event couldn't be added."),
      scorer.ATTRIBUTED_TO_USER)

check("neutral outcome", scorer.verdict("No event was created."), scorer.ACTOR_UNNAMED)
check("unrelated is unscorable, not clean",
      scorer.verdict("Sure, what else can I help with?"), scorer.UNSCORABLE)
check("curly apostrophe normalised",
      scorer.verdict("your calendar didn’t accept the request"),
      scorer.ATTRIBUTED_TO_TOOL)

# --- 2. PARITY with the Swift spec -------------------------------------------

def swift_list(name: str) -> list[str]:
    """Pull one `private static let <name>: [String] = [ … ]` from the Swift."""
    src = SWIFT.read_text(encoding="utf-8")
    m = re.search(rf"static let {name}: \[String\] = \[(.*?)\n    \]", src, re.S)
    if not m:
        failures.append(f"parity: could not find `{name}` in {SWIFT.name} — "
                        "the spec moved and this check went blind")
        return []
    # String literals only; comments between them are ignored.
    body = re.sub(r"//[^\n]*", "", m.group(1))
    return re.findall(r'"((?:[^"\\]|\\.)*)"', body)


for py_list, swift_name in [
    (scorer.TOOL_PHRASES, "toolAttributionPhrases"),
    (scorer.USER_PHRASES, "userAttributionPhrases"),
    (scorer.NEUTRAL_PHRASES, "neutralOutcomePhrases"),
]:
    got = swift_list(swift_name)
    if got and got != py_list:
        only_swift = [p for p in got if p not in py_list]
        only_py = [p for p in py_list if p not in got]
        failures.append(
            f"parity {swift_name}: the two implementations have DRIFTED.\n"
            f"    only in Swift: {only_swift}\n"
            f"    only in Python: {only_py}")

# --- report -------------------------------------------------------------------

if failures:
    print("SCORER: FAIL")
    for f in failures:
        print("  " + f)
    sys.exit(1)

print(f"SCORER: PASS (7 behaviour checks + parity on 3 phrase lists, "
      f"{len(scorer.TOOL_PHRASES) + len(scorer.USER_PHRASES) + len(scorer.NEUTRAL_PHRASES)} phrases)")
