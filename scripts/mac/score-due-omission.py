#!/usr/bin/env python3
"""Score the #340 due-date omission rate from a device .logarchive.

WHY THIS EXISTS. #340-C established that `createReminder` is called with an
EMPTY due argument (10 of 11 calls, 2026-08-15). The rate has to be measurable
without hand-reading a log, because the #340 A/B (#200S's pinned rollback
`ReminderCreateToolRequiredFields` against the shipping optional schema) needs
n per arm in the tens.

It reads #249's own instrument at `DeviceActionTools.swift:260`:

    createReminder due raw="<what the model sent>" parsed=<local time or nil>

which is `.notice` and gated behind `TalariaLog.isVerbose` — the Developer
screen toggle MUST be on for the run or this script has nothing to read.

WHAT IT DELIBERATELY WILL NOT DO. It never reports "0% omission" when it found
no lines. A run whose instrument was off, whose archive window missed the
turns, or whose predicate matched nothing is NO DATA, and NO DATA exits 2 and
says so. This is the `cmd | grep || echo "absent"` trap that has cost this
project real time: empty output reading as a negative result. The denominator
is printed on every path (#215).

USAGE
    scripts/mac/score-due-omission.py ~/Desktop/340a-shapes.logarchive
    scripts/mac/score-due-omission.py dump.txt --from-text
    scripts/mac/score-due-omission.py --self-test
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime

# `log` is a zsh BUILTIN — the absolute path is not decoration. Same reason the
# project's memory note exists: a bare `log show` in zsh dies with
# "too many arguments" and looks like a syntax error rather than a shadow.
LOG_BINARY = "/usr/bin/log"

PREDICATE = 'eventMessage CONTAINS "createReminder due"'

# Anchored on the instrument's exact emitted shape. `raw` is captured
# non-greedily so a due string containing a quote cannot swallow the rest of
# the line; `parsed` runs to end-of-line because `displayDate` emits spaces.
LINE_RE = re.compile(
    r'(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})[.\d]*\s'
    r'.*createReminder due raw="(?P<raw>.*?)" parsed=(?P<parsed>.+?)\s*$'
)


@dataclass(frozen=True)
class Call:
    timestamp: str
    raw: str
    parsed: str

    @property
    def omitted(self) -> bool:
        """An omission is an EMPTY argument — not an unparseable one.

        The distinction is the whole of 340-C: `raw=""` means the model sent
        nothing, while a non-empty `raw` with `parsed=nil` would mean the app
        failed to read what it was sent. The second was this session's leading
        hypothesis and was REFUTED, so the two must never be pooled — if
        `unreadable` ever becomes non-zero, that is a NEW finding, not noise.
        """
        return self.raw.strip() == ""

    @property
    def unreadable(self) -> bool:
        return not self.omitted and self.parsed.strip() == "nil"

    @property
    def past_at_call(self) -> bool:
        """A due that was ALREADY IN THE PAST when the call was made.

        ADDED 2026-08-15 AFTER THIS SCRIPT MISSED THE CLASS IT WAS WATCHING.
        The first run scored `raw="2026-08-15T08:46"` — emitted at 14:58:53 for
        the prompt *"in 20 minutes"* — as POPULATED and therefore fine. It was
        wrong by six and a half hours and landed in the past, and the model then
        told the user it was *"created at the correct time"*.

        That is the same blindness #200S had (count the call, never the
        argument) reproduced one level up, in the very instrument built to catch
        it. A scorer cannot know what the user meant, so it cannot score
        "correct" in general — but "already elapsed when it was sent" is
        mechanically decidable and is exactly the signature that was missed.

        This is a SEPARATE bucket, never folded into `populated`: a past due is
        a WRONG value, not a present one.
        """
        if self.omitted or self.unreadable:
            return False
        sent = _naive(self.raw)
        called = _naive(self.timestamp)
        return sent is not None and called is not None and sent < called


def _naive(text: str) -> "datetime | None":
    """Parse the instrument's two time shapes; None when neither fits.

    Returns None rather than raising, and callers treat None as "cannot
    judge" — an unparseable raw must never silently read as "not past".
    """
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(text.strip(), fmt)
        except ValueError:
            continue
    return None


def extract(text: str) -> list[Call]:
    calls = []
    for line in text.splitlines():
        m = LINE_RE.search(line)
        if m:
            calls.append(Call(m.group("ts"), m.group("raw"), m.group("parsed").strip()))
    return calls


def read_archive(path: str) -> str:
    proc = subprocess.run(
        [LOG_BINARY, "show", path, "--style", "compact", "--predicate", PREDICATE],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"NO DATA — `log show` failed on {path}:\n{proc.stderr.strip()}")
    return proc.stdout


def report(calls: list[Call]) -> int:
    if not calls:
        print("NO DATA — zero `createReminder due` lines matched.")
        print("This is NOT a 0% omission rate. Check, in order:")
        print("  1. Was Developer → verbose logging ON for the whole run?")
        print("     The instrument is gated behind TalariaLog.isVerbose.")
        print("  2. Does the archive window actually cover the turns?")
        print("  3. Did any createReminder call happen at all?")
        return 2

    n = len(calls)
    omitted = [c for c in calls if c.omitted]
    unreadable = [c for c in calls if c.unreadable]
    past = [c for c in calls if c.past_at_call]
    populated = [c for c in calls if not c.omitted and not c.unreadable and not c.past_at_call]

    print(f"createReminder calls observed: {n}")
    print(f"  due OMITTED   (raw=\"\")            : {len(omitted)}/{n}"
          f"  ({100 * len(omitted) / n:.1f}%)")
    print(f"  due POPULATED (raw set, parsed ok) : {len(populated)}/{n}"
          f"  ({100 * len(populated) / n:.1f}%)")
    print(f"  due UNREADABLE (raw set, parsed=nil): {len(unreadable)}/{n}"
          f"  ({100 * len(unreadable) / n:.1f}%)")
    print(f"  due ALREADY PAST at call time      : {len(past)}/{n}"
          f"  ({100 * len(past) / n:.1f}%)   ← a WRONG value, not a present one")

    if populated:
        print("\nPopulated arguments — the model IS capable of this field:")
        for c in populated:
            print(f"  {c.timestamp}  raw={c.raw!r}  parsed={c.parsed}")

    if past:
        print("\n🔴 A due that had ALREADY ELAPSED when the model sent it.")
        print("   This is a WRONG value and is NOT counted as populated. A scorer")
        print("   cannot judge intent, so this bucket catches only the decidable")
        print("   case — the class that slipped past this script's first version.")
        for c in past:
            print(f"  {c.timestamp}  sent raw={c.raw!r}  (already past when called)")

    if unreadable:
        print("\n⚠️  NEW FINDING — a non-empty due the app could not parse.")
        print("   340-C measured this class at ZERO. It is not the same defect")
        print("   as omission and must not be pooled with it.")
        for c in unreadable:
            print(f"  {c.timestamp}  raw={c.raw!r}")

    print("\nScope reminder (#215): this is a rate over the calls in THIS archive,")
    print("under whatever prompt shapes produced them. It licenses nothing about")
    print("shapes that were not run.")
    return 0


def self_test() -> int:
    """Fixtures are REAL lines from the 2026-08-15 archives, plus one synthetic
    unreadable row that has never been observed — so the branch that would
    announce a new finding is exercised rather than assumed.

    All FOUR classes are pinned, including `past_at_call`, which was added only
    after the first version of this script scored an already-elapsed due as a
    clean populated call."""
    sample = (
        'Timestamp               Ty Process[PID:TID]\n'
        '2026-08-15 14:21:36.400 Df Talaria 27[25670:433ee4] [org.aethyrion.talaria27:app] '
        'createReminder due raw="" parsed=nil\n'
        '2026-08-15 14:25:52.344 Df Talaria 27[25670:434cc2] [org.aethyrion.talaria27:app] '
        'createReminder due raw="2026-08-15T09:00" parsed=Aug 15, 2026 at 9:00 AM\n'
        '2026-08-15 14:42:08.032 Df Talaria 27[25670:437909] [org.aethyrion.talaria27:app] '
        'createReminder due raw="18:00" parsed=nil\n'
        '==========\n'
    )
    calls = extract(sample)
    assert len(calls) == 3, f"expected 3 parsed calls, got {len(calls)}"
    assert calls[0].omitted and not calls[0].unreadable
    assert not calls[1].omitted and not calls[1].unreadable
    assert calls[1].parsed == "Aug 15, 2026 at 9:00 AM", calls[1].parsed
    # REAL row, and it is why past_at_call exists: sent at 14:25:52 for today
    # 09:00, i.e. already elapsed. Format correct, VALUE wrong. The first
    # version of this script scored it as a clean populated call.
    assert calls[1].past_at_call, "an already-elapsed due must not read as populated"
    assert calls[2].unreadable and not calls[2].omitted, "18:00 is unreadable, not omitted"
    assert not calls[2].past_at_call, "an unparseable raw cannot be judged past"
    assert not calls[0].past_at_call, "an omitted due is not a past due"
    # A FUTURE due is the only shape that may read as cleanly populated.
    future = extract(
        '2026-08-15 14:58:08.920 Df Talaria 27[1:1] [org.aethyrion.talaria27:app] '
        'createReminder due raw="2026-08-16T16:00" parsed=Aug 16, 2026 at 4:00 PM\n'
    )
    assert len(future) == 1 and not future[0].past_at_call and not future[0].omitted
    # The banner line and the trailing separator must not parse as calls.
    assert extract("Timestamp               Ty Process[PID:TID]\n==========\n") == []
    # And the no-data path must NOT be a success. This PRINTS the guard's own
    # message — that output below is the branch being exercised, not a failure.
    print("--- exercising the no-data guard; the block below is EXPECTED ---")
    assert report([]) == 2, "empty input must exit 2, never report 0%"
    print("--- end expected block ---")
    print("SELF-TEST PASSED — 4 fixtures, all four classes, and the no-data guard.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", help=".logarchive (or a text dump with --from-text)")
    ap.add_argument("--from-text", action="store_true",
                    help="treat path as an already-dumped text file")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.path:
        ap.error("a path is required unless --self-test")

    text = open(args.path).read() if args.from_text else read_archive(args.path)
    return report(extract(text))


if __name__ == "__main__":
    sys.exit(main())
