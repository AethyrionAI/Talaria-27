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

# BOTH shapes, because #340-H4's denominator is TRIALS and a trial that made no
# call emits no `createReminder` line at all. Scoring over calls is how 340-F1
# came to say ">=16/20" without saying of what, and had to be reported both
# ways after the fact.
PREDICATE = ('eventMessage CONTAINS "createReminder due" '
             'OR eventMessage CONTAINS "battery: BEGIN shape="')

# Anchored on the instrument's exact emitted shape. `raw` is captured
# non-greedily so a due string containing a quote cannot swallow the rest of
# the line; `parsed` runs to end-of-line because `displayDate` emits spaces.
# ⚠️ `parsed` runs GREEDILY to end-of-line, so ANY field appended after it is
# silently swallowed into this group. #340 route (a) added `bareClock=` for
# exactly that reason placed it BEFORE `parsed`, and this pattern was updated in
# the same commit — a trailing field would have made every `parsed` read
# `nil bareClock=no`, which is not "nil", which would have zeroed the
# `unreadable` bucket without a single test noticing.
LINE_RE = re.compile(
    r'(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})[.\d]*\s'
    r'.*createReminder due raw="(?P<raw>.*?)"'
    r'(?: bareClock=(?P<bareclock>\S+))?'
    r' parsed=(?P<parsed>.+?)\s*$'
)

# One TRIAL. The battery emits this before every turn, unconditionally, and it
# carries the cell — which is what lets one archive score both arms of an A/B.
TRIAL_RE = re.compile(
    r'(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})[.\d]*\s'
    r'.*battery: BEGIN shape=(?P<cell>\S+) p=(?P<prompt>\S+) t=(?P<trial>\d+)'
)


@dataclass(frozen=True)
class Call:
    timestamp: str
    raw: str
    parsed: str
    # None on a pre-#340 archive: the field did not exist, and "absent" must
    # not read as "no". Three live values: resolved / unresolvable / no.
    bareclock: "str | None" = None

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


@dataclass(frozen=True)
class Trial:
    timestamp: str
    cell: str
    prompt: str
    trial: str


def extract(text: str) -> list[Call]:
    calls = []
    for line in text.splitlines():
        m = LINE_RE.search(line)
        if m:
            calls.append(Call(m.group("ts"), m.group("raw"),
                              m.group("parsed").strip(), m.group("bareclock")))
    return calls


def extract_trials(text: str) -> list[Trial]:
    trials = []
    for line in text.splitlines():
        m = TRIAL_RE.search(line)
        if m:
            trials.append(Trial(m.group("ts"), m.group("cell"),
                                m.group("prompt"), m.group("trial")))
    return trials


def attribute(calls: list[Call], trials: list[Trial]) -> "dict[str, list]":
    """Attach each call to the trial it happened inside — the most recent
    `BEGIN` at or before its timestamp.

    Returns {cell: [(Trial, Call|None), ...]}, so a trial that made NO call is
    represented rather than absent. That absence IS the `no-call` bucket, and
    it is the bucket the call-denominated version of this script could not see.

    A call before any BEGIN belongs to no trial and is dropped from the
    per-cell view — reported separately rather than silently attributed to
    whatever ran first.
    """
    ordered = sorted(trials, key=lambda t: t.timestamp)
    by_cell: "dict[str, list]" = {}
    for index, trial in enumerate(ordered):
        end = ordered[index + 1].timestamp if index + 1 < len(ordered) else None
        matched = None
        for call in calls:
            if call.timestamp < trial.timestamp:
                continue
            if end is not None and call.timestamp >= end:
                continue
            matched = call
            break
        by_cell.setdefault(trial.cell, []).append((trial, matched))
    return by_cell


def read_archive(path: str, start: "str | None" = None, end: "str | None" = None) -> str:
    """#416-G, 2026-08-27. `--start`/`--end` pass straight through to `log show`.

    WHY. Cells are what let one archive score both arms of an A/B — but a cell
    name is not unique across INSTRUMENTS. On 2026-08-27 a single 45-minute
    archive covered #340's A/B (cells `armed` + `armed-bareclock`) AND #392's
    decline run, whose cell is ALSO called `armed`. Scored whole, the `armed`
    arm read **160 trials** instead of #340's 40 — a 4x contamination by a
    different instrument — while `armed-bareclock` stayed clean at 40. Comparing
    those two arms would have produced a confident, precise, WRONG A/B, and
    nothing in the output would have hinted at it.

    Back-to-back device runs into one archive is now the normal shape (it is
    what a chained session produces), so the window is the fix.
    """
    cmd = [LOG_BINARY, "show", path, "--style", "compact", "--predicate", PREDICATE]
    if start:
        cmd += ["--start", start]
    if end:
        cmd += ["--end", end]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"NO DATA — `log show` failed on {path}:\n{proc.stderr.strip()}")
    return proc.stdout


def bucket(call: "Call | None") -> str:
    """#340-H4's four buckets, over TRIALS.

    `no-call` is the one the previous version could not express: it scored over
    calls, so a trial where the model never invoked the tool simply vanished
    from the denominator. 340-G4 flagged exactly that risk from the other side
    — the treatment arm made 14 calls to the control's 19 — and a scorer blind
    to it reports an arm that stopped calling as an arm that stopped omitting.

    `wrong-value` pools UNREADABLE with ALREADY-PAST deliberately: both are a
    populated field the user cannot use, and 340-H5's bar is on the union
    `omitted + wrong-value`. The two stay separately COUNTED below so the pool
    is a reporting choice and never a lost distinction.
    """
    if call is None:
        return "no-call"
    if call.omitted:
        return "omitted"
    if call.unreadable or call.past_at_call:
        return "wrong-value"
    return "populated-future"


def report_by_cell(by_cell: "dict[str, list]") -> int:
    """The per-arm view 340-H5 is scored on.

    **`populated-future` is NOT called `correct`, and that is not pedantry.**
    A scorer cannot know what the user meant, so it cannot certify a value as
    the right one; what it can decide mechanically is that the field was filled
    with an instant that has not already elapsed. Naming that "correct" is how
    the first version of this script scored an 8:46 AM answer to a 2:58 PM ask
    as fine.
    """
    if not by_cell:
        print("NO DATA — zero `battery: BEGIN shape=` lines matched.")
        print("This is NOT a clean run. Check, in order:")
        print("  1. Was Developer -> verbose logging ON for the whole run?")
        print("  2. Does the archive window actually cover the battery?")
        print("  3. Did the battery start at all?")
        return 2

    order = ["populated-future", "omitted", "wrong-value", "no-call"]
    exit_code = 0
    for cell in sorted(by_cell):
        rows = by_cell[cell]
        n = len(rows)
        counts = {name: 0 for name in order}
        for _, call in rows:
            counts[bucket(call)] += 1
        unreadable = sum(1 for _, c in rows if c is not None and c.unreadable)
        past = sum(1 for _, c in rows if c is not None and c.past_at_call)
        resolved = sum(1 for _, c in rows
                       if c is not None and c.bareclock == "resolved")

        print(f"\ncell {cell} — {n} TRIALS (denominator is trials, not calls)")
        for name in order:
            print(f"  {name:<18}: {counts[name]}/{n}  ({100 * counts[name] / n:.1f}%)")
        union = counts["omitted"] + counts["wrong-value"]
        print(f"  UNION omitted+wrong-value: {union}/{n}  ({100 * union / n:.1f}%)"
              "   <- 340-H5's non-decomposable bar")
        print(f"    of which unreadable={unreadable}, already-past={past}")
        print(f"  app-resolved a bare clock: {resolved}/{n}"
              "   <- #340 route (a) actually firing")
        if counts["no-call"] == n:
            print("  ⚠️  EVERY trial made no call — this arm measured nothing about due dates.")
            exit_code = 2
    print("\nScope reminder (#215): rates over the trials in THIS archive, under")
    print("whatever prompt shapes produced them. Licenses nothing about shapes")
    print("that were not run. Cross-run comparison of the already-past bucket is")
    print("NOT admissible — the battery's fixed prompt is a moving target against")
    print("the wall clock (340-G's own instrument flaw).")
    return exit_code


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
        # ⚠️ CHANGED BY #340 ROUTE (a), 2026-08-21. This fixture used to be
        # `raw="18:00" parsed=nil` and asserted that a bare clock time is
        # UNREADABLE. That is now FALSE by construction: `performCreate`
        # resolves a bare clock itself, so 18:00 parses. A synthetic fixture
        # that encodes the old behaviour would keep passing while describing a
        # product that no longer exists — the close-out rule (#317) applied to
        # a test's fixture rather than to prose.
        '2026-08-15 14:42:08.032 Df Talaria 27[25670:437909] [org.aethyrion.talaria27:app] '
        'createReminder due raw="sometime later" bareClock=no parsed=nil\n'
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
    assert calls[2].unreadable and not calls[2].omitted, "prose is unreadable, not omitted"
    assert not calls[2].past_at_call, "an unparseable raw cannot be judged past"
    assert calls[2].bareclock == "no"
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

    # ---- #340-H4: the FOUR BUCKETS, on hand-built rows. ----
    #
    # Hand-built on purpose. A scorer first exercised on a real archive cannot
    # be told apart from that archive — if the run happened to contain no
    # `no-call` trial, the bucket that exists to catch 340-G4's shape would
    # never have executed and would still read as working.
    #
    # Two cells, four trials each, one trial per bucket, so every branch of
    # `bucket()` runs and the ATTRIBUTION is proved too: each call must land in
    # the trial whose window contains it, and the fourth trial of each cell has
    # no call at all.
    ab = (
        'Timestamp               Ty Process[PID:TID]\n'
        # --- control arm ---
        '2026-08-21 09:00:00.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed p=remind t=1\n'
        '2026-08-21 09:00:01.100 Df Talaria 27[1:1] [x] createReminder due raw="" bareClock=no parsed=nil\n'
        '2026-08-21 09:00:02.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed p=remind t=2\n'
        '2026-08-21 09:00:03.100 Df Talaria 27[1:1] [x] createReminder due raw="2026-08-21T08:00" bareClock=no parsed=Aug 21, 2026 at 8:00 AM\n'
        '2026-08-21 09:00:04.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed p=remind t=3\n'
        '2026-08-21 09:00:05.100 Df Talaria 27[1:1] [x] createReminder due raw="2026-08-22T16:30" bareClock=no parsed=Aug 22, 2026 at 4:30 PM\n'
        '2026-08-21 09:00:06.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed p=remind t=4\n'
        # --- treatment arm; note the app-resolved bare clock ---
        '2026-08-21 09:10:00.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed-bareclock p=remind t=1\n'
        '2026-08-21 09:10:01.100 Df Talaria 27[1:1] [x] createReminder due raw="16:30" bareClock=resolved parsed=Aug 21, 2026 at 4:30 PM\n'
        '2026-08-21 09:10:02.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed-bareclock p=remind t=2\n'
        '2026-08-21 09:10:03.100 Df Talaria 27[1:1] [x] createReminder due raw="nonsense" bareClock=no parsed=nil\n'
        '2026-08-21 09:10:04.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed-bareclock p=remind t=3\n'
        '==========\n'
    )
    by_cell = attribute(extract(ab), extract_trials(ab))
    assert set(by_cell) == {"armed", "armed-bareclock"}, by_cell.keys()

    control = [bucket(c) for _, c in by_cell["armed"]]
    assert control == ["omitted", "wrong-value", "populated-future", "no-call"], control

    treatment = [bucket(c) for _, c in by_cell["armed-bareclock"]]
    assert treatment == ["populated-future", "wrong-value", "no-call"], treatment

    # A trial that made NO call must be PRESENT with None, never dropped — the
    # whole reason the denominator moved from calls to trials.
    assert by_cell["armed"][3][1] is None
    assert len(by_cell["armed"]) == 4 and len(by_cell["armed-bareclock"]) == 3

    # Attribution is by WINDOW, not by proximity: t=2's call must be t=2's.
    assert by_cell["armed"][1][1].raw == "2026-08-21T08:00"
    assert by_cell["armed-bareclock"][0][1].bareclock == "resolved"

    # The union bar's two halves stay separable even though the bucket pools
    # them — 340-H5 reports the union, but a lane must still be able to see
    # WHICH kind of wrong value it bought.
    assert by_cell["armed"][1][1].past_at_call and not by_cell["armed"][1][1].unreadable
    assert by_cell["armed-bareclock"][1][1].unreadable

    print("--- exercising the by-cell no-data guard; the block below is EXPECTED ---")
    assert report_by_cell({}) == 2, "no trials must exit 2, never report clean buckets"
    print("--- end expected block ---")

    print("SELF-TEST PASSED — 4 call fixtures, all four classes, the no-data")
    print("guard, and #340-H4's four buckets attributed across a two-arm A/B.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?", help=".logarchive (or a text dump with --from-text)")
    ap.add_argument("--from-text", action="store_true",
                    help="treat path as an already-dumped text file")
    ap.add_argument("--start", help="log show --start (e.g. '2026-08-27 21:00:00') — "
                                    "scope a multi-run archive to ONE instrument's window; "
                                    "cell names are NOT unique across instruments (#416-G)")
    ap.add_argument("--end", help="log show --end")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.path:
        ap.error("a path is required unless --self-test")

    text = open(args.path).read() if args.from_text else read_archive(args.path, args.start, args.end)
    calls = extract(text)
    trials = extract_trials(text)
    if trials:
        # Trials present => an instrumented battery run => score #340-H4's four
        # buckets per arm. The call-denominated report still runs underneath,
        # because the two answer different questions and the older one is what
        # every earlier #340 measurement is written in.
        code = report_by_cell(attribute(calls, trials))
        print("\n--- per-CALL view (the pre-340-H4 report, for comparability) ---")
        return max(code, report(calls))
    print("NOTE: no `battery: BEGIN` lines — scoring over CALLS only.")
    print("      `no-call` is UNMEASURABLE without them (340-H4), so an arm")
    print("      that stopped calling will not be visible in what follows.")
    return report(calls)


if __name__ == "__main__":
    sys.exit(main())
