#!/usr/bin/env python3
"""Score the #340 due-date omission rate from a device .logarchive.

WHY THIS EXISTS. #340-C established that `createReminder` is called with an
EMPTY due argument (10 of 11 calls, 2026-08-15). The rate has to be measurable
without hand-reading a log, because the #340 A/B (#200S's pinned rollback
`ReminderCreateToolRequiredFields` against the shipping optional schema) needs
n per arm in the tens.

It reads #249's own instrument in `ReminderCreateTool.performCreate`:

    createReminder due raw="<what the model sent>" bareClock=<…> source=<…> candidates=<n> parsed=<local time or nil>

which is `.notice` and gated behind `TalariaLog.isVerbose` — the Developer
screen toggle MUST be on for the run or this script has nothing to read.

`source=` (#340 Task 3, 2026-09-04) says WHERE the date came from — `model`
(the argument the model sent), `userText` (the fallback read it out of the
user's own sentence), or `none` (the card stayed dateless). It is what makes
bar 340-U-C decidable: a `populated-future` rate that rose because the fix is
working and one that rose because the model got lucky are the same number
without it. **Absent on every pre-2026-09-04 archive**, and absent must not
read as `none` — those rows are reported as `legacy`.

`candidates=` (#340's final fix wave, 2026-09-04) is the second clause of
Owen's decision 2 — *"take the EARLIEST future date and LOG THE CANDIDATE
COUNT"* — and it is the only way an archive can show the two-date edge that
ruling is about. It counts the FALLBACK's own candidates, so it is `0` on the
model path by construction. **Absent is not `0`**, same rule as `source=`.

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
import io
import re
import subprocess
import sys
from contextlib import redirect_stdout
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
# #340 Task 3 added `source=` under the same rule and in the same place, and the
# app side is now PINNED: `theInstrumentLineCarriesSourceAheadOfParsed` fails if
# anyone ever appends a field after `parsed=`.
# #340's final fix wave added `candidates=` (2026-09-04) as the THIRD field to
# land in front of `parsed` under the same rule, and the app-side pin was
# extended to the whole chain rather than to `source=` alone.
# All THREE trailing groups stay OPTIONAL so pre-#340 archives keep parsing.
LINE_RE = re.compile(
    r'(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})[.\d]*\s'
    r'.*createReminder due raw="(?P<raw>.*?)"'
    r'(?: bareClock=(?P<bareclock>\S+))?'
    r'(?: source=(?P<source>\S+))?'
    r'(?: candidates=(?P<candidates>\d+))?'
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
    # None on any archive collected before #340 Task 3 (2026-09-04). Three live
    # values: model / userText / none.
    source: "str | None" = None
    # None on any archive collected before #340's final fix wave (2026-09-04):
    # how many FUTURE date candidates the user's own sentence carried, and the
    # second clause of Owen's decision 2 ("take the earliest future date and LOG
    # THE CANDIDATE COUNT"). Kept as the raw string so `None` and `"0"` stay
    # distinguishable at the field level — see `candidate_count`.
    candidates: "str | None" = None

    @property
    def candidate_count(self) -> "int | None":
        """The candidate count as a number, or None when the field is ABSENT.

        Absent is not zero, for the same reason `source_label` says `legacy`
        rather than `none`: `0` is the positive claim that the fallback ran and
        the sentence carried no future date, and an archive collected before
        2026-09-04 makes no such claim. Every consumer must branch on None
        before it reports a rate.
        """
        return int(self.candidates) if self.candidates is not None else None

    @property
    def source_label(self) -> str:
        """`source=` for reporting, with absence named rather than guessed.

        An archive that predates the field carries no opinion about where its
        due dates came from, and reporting that as `none` would say the exact
        opposite of the truth — `none` means the card was DATELESS. `legacy`
        is the honest third answer, and it is the same rule as `bareclock`'s:
        absent is not "no".
        """
        return self.source if self.source is not None else "legacy"

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
    def dateless(self) -> bool:
        """**No due date reached the CARD** — which is not the same question as
        `omitted`, and #340 Task 3 is the day the two came apart.

        Until 2026-09-04 an empty argument could only ever produce a dateless
        card: `raw=""` fed `parseDateTime`/`parseBareClock`, both returned nil,
        and `parsed=nil` followed by construction. So on every archive this
        script has ever read, `omitted == dateless` identically — which is why
        the buckets could be denominated on the ARGUMENT without anyone
        noticing they were answering the user's question by accident.

        The fallback breaks that identity on purpose: the model sends nothing,
        the user's own sentence carries the date, and the card is correct while
        the argument is still empty. `omitted` keeps its ARGUMENT meaning
        (340-C's founding measurement, and `source=userText` counts exactly the
        rows where it and `dateless` now disagree); `bucket()` moves to this
        one, because what 340-U-C is asking is whether the USER got a usable
        due date.
        """
        return self.parsed.strip() == "nil"

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

        ⚠️ **EXTENDED 2026-09-04 (#340's final fix wave) to the FALLBACK path,
        because on that path this bucket could not go non-zero.** Every
        fallback row has `raw=""`, so `omitted` was true and the guard below
        early-returned False — a fallback-produced instant that had already
        elapsed would have read as `populated-future`, and 340-U-C's
        `already-past = 0` would have been satisfied by construction rather
        than by fact. A bar whose bucket cannot move is not a measurement; it
        is the constant denominator this project has already paid for twice.

        There is no `raw` to judge on that path, so the judgement is made on
        `parsed` — `displayDate`'s own output, which is what actually reached
        the card. It is gated on `source == "userText"` and nothing else: a
        LEGACY row (no `source=` at all) carries no claim about where its date
        came from, so it must keep scoring exactly as it did before this
        landed, and a `model` row keeps being judged on `raw` as it always was.

        The app does guarantee a strictly-future fallback (bar 340-U-A, six
        pinned rows), so this is a scorer double-checking a guarantee rather
        than one expecting violations — which is the point: the guarantee lives
        in the app, and an instrument that cannot contradict what it measures
        is not watching it.
        """
        if self.source == "userText":
            shown = _display(self.parsed)
            called = _naive(self.timestamp)
            return shown is not None and called is not None and shown < called
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


# `DeviceActionParsing.displayDate` is a `DateFormatter` at `.medium` date /
# `.short` time: "Sep 5, 2026 at 4:00 PM".
DISPLAY_FORMAT = "%b %d, %Y at %I:%M %p"


def _display(text: str) -> "datetime | None":
    """Parse the instrument's `parsed=` value — `displayDate`'s own output.

    **The U+202F is the whole reason this is a function.** On a real device
    `DateFormatter` emits a NARROW NO-BREAK SPACE before the meridiem, not an
    ASCII space, so a parser written against the ASCII form reads NOTHING from
    a real archive — and "nothing parsed" reads here as "not past", i.e. the
    right answer to 340-U-C's `already-past = 0` bar for entirely the wrong
    reason. Both spacings are fixtured in `self_test`.

    None means CANNOT JUDGE and callers must treat it as such, never as "not
    past". `%b` and `%p` are read in the C locale, so a device running a
    non-English locale lands here — a known limit, named rather than hidden,
    and the same limit `_naive` has always had for `raw`.
    """
    try:
        return datetime.strptime(text.replace("\u202f", " ").strip(),
                                 DISPLAY_FORMAT)
    except ValueError:
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
                              m.group("parsed").strip(), m.group("bareclock"),
                              m.group("source"), m.group("candidates")))
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

    ⚠️ **CHANGED 2026-09-04 (#340 Task 3), and the change is a no-op on every
    archive collected before that date.** The first line used to read
    `if call.omitted` — the ARGUMENT the model sent. It now reads
    `if call.dateless` — the date that reached the CARD.

    **Why it is a no-op on old data:** before the fallback existed, `raw=""`
    could only produce `parsed=nil`, so the two predicates agreed on every row
    ever scored. The order below preserves the old precedence exactly:
    `unreadable` is false by construction when the argument is empty, and
    `past_at_call` early-returns false for the same rows, so an empty argument
    with a nil parse still lands in `omitted` and nothing else moved.

    **Why it had to change:** the fallback fills the card from the user's own
    sentence while the argument stays empty. Scored on the argument, those
    trials would count as `omitted` — the fix would be invisible in the very
    bucket it exists to move, and 340-U-C (`populated-future >= 34/40` with a
    `source=userText >= 12/40` column) could not be met by a working product.
    The argument rate is not lost: it is `omitted + source=userText`, printed
    on its own line.

    ⚠️ **A blind spot this used to create — CLOSED 2026-09-04, same commit
    (`e7928491`) that added `candidates=`. Until then this was true and was
    named rather than hidden: `past_at_call` judged only the RAW string, so it
    could not judge a fallback-filled row (there was no raw to parse, and
    `parsed` is a display string). A fallback due that had already elapsed
    would therefore have read as `populated-future`, and that was safe only
    because `detectDue` guarantees a strictly-future answer — bar 340-U-A, six
    pinned rows — so the guarantee lived in the app, not here, and a
    regression there would have gone uncaught.

    ⟵ 2026-09-04: no longer the case.** `Call.past_at_call` (around lines
    199-224) gained a `source == "userText"` branch that parses `parsed=`
    (U+202F normalised, via `_display`) and compares it against the call's
    own timestamp — so a fallback row IS now judged for already-past via its
    `parsed=` value. The `model` path is unchanged: `raw` is still the judge
    there, exactly as before. `bucket()` below reflects both routes into
    `wrong-value` without needing to know which one fired. Pinned in
    `self_test`'s `past_fallback` fixture (`past_plain`/`past_nnbsp` vs.
    `future_plain`/`future_nnbsp`, plus `model_past` and `legacy_past` as
    controls on the other two paths).
    """
    if call is None:
        return "no-call"
    if call.unreadable or call.past_at_call:
        return "wrong-value"
    if call.dateless:
        return "omitted"
    return "populated-future"


# #200V's warm-up tag. The battery emits `battery: BEGIN shape=warmup p=… t=0`
# for the trial that pays the model's cold start, BEFORE `beginRun`, so the
# recorder never sees it and the results page is byte-identical to a
# warm-up-free run. The app chose a literal that is not any cell's rawValue for
# exactly this reason — `batteryWarmupTag`'s own comment says the tag says
# `warmup` "so no classifier and no reap line can mistake a discarded warm-up
# trial for a counted one." This scorer was that classifier, and it did.
WARMUP_CELL = "warmup"


def split_warmup(by_cell: "dict[str, list]") -> "tuple[dict[str, list], list]":
    """Separate the discarded warm-up rows from the measured cells.

    A separate function, and the warm-up rows are RETURNED rather than dropped,
    because the count still has to be reported: a reader who sees no mention of
    a warm-up cannot tell "there was none" from "the scorer ate one", and that
    ambiguity is the same `empty output reads as a negative` trap this whole
    script is written against.
    """
    warm = by_cell.get(WARMUP_CELL, [])
    measured = {cell: rows for cell, rows in by_cell.items() if cell != WARMUP_CELL}
    return measured, warm


def report_by_cell(by_cell: "dict[str, list]") -> int:
    """The per-arm view 340-H5 is scored on.

    **`populated-future` is NOT called `correct`, and that is not pedantry.**
    A scorer cannot know what the user meant, so it cannot certify a value as
    the right one; what it can decide mechanically is that the field was filled
    with an instant that has not already elapsed. Naming that "correct" is how
    the first version of this script scored an 8:46 AM answer to a 2:58 PM ask
    as fine.

    **And the warm-up is not an arm.** #340-H5's archive scored as THREE cells,
    the third being `cell warmup — 1 TRIALS` at 100% omission, sorted to the
    bottom of the table where it reads exactly like a very small third arm. The
    battery discards that trial by construction; a table that prints it invites
    a reader to count a discarded trial as a measurement. It is now reported on
    one labelled line, with its count, and in none of the rates.
    """
    measured, warm = split_warmup(by_cell)
    warm_line = None
    if warm:
        with_call = sum(1 for _, call in warm if call is not None)
        warm_line = (f"discarded warm-up: {len(warm)} trial(s), {with_call} of them "
                     "made a call — NOT an arm, and in NONE of the rates below "
                     "(#200V pays the cold start outside the counts)")

    if not measured:
        if warm:
            print(warm_line)
            print("NO DATA — the only `battery: BEGIN shape=` lines were the")
            print("discarded warm-up. A warm-up trial is not a measurement.")
        else:
            print("NO DATA — zero `battery: BEGIN shape=` lines matched.")
        print("This is NOT a clean run. Check, in order:")
        print("  1. Was Developer -> verbose logging ON for the whole run?")
        print("  2. Does the archive window actually cover the battery?")
        print("  3. Did the battery start at all?")
        return 2

    if warm_line:
        print(warm_line)

    order = ["populated-future", "omitted", "wrong-value", "no-call"]
    exit_code = 0
    for cell in sorted(measured):
        rows = measured[cell]
        n = len(rows)
        counts = {name: 0 for name in order}
        for _, call in rows:
            counts[bucket(call)] += 1
        unreadable = sum(1 for _, c in rows if c is not None and c.unreadable)
        past = sum(1 for _, c in rows if c is not None and c.past_at_call)
        resolved = sum(1 for _, c in rows
                       if c is not None and c.bareclock == "resolved")
        # #340 Task 3 / bar 340-U-C: WHERE each usable due date came from.
        # Counted over the `populated-future` rows ONLY — a source on a row the
        # user cannot use is not evidence the fix works, and pooling the two
        # would let a run whose fallback produced nothing but already-past
        # values read as a fallback that is working.
        by_source: "dict[str, int]" = {}
        for _, c in rows:
            if bucket(c) == "populated-future":
                by_source[c.source_label] = by_source.get(c.source_label, 0) + 1

        print(f"\ncell {cell} — {n} TRIALS (denominator is trials, not calls)")
        for name in order:
            print(f"  {name:<18}: {counts[name]}/{n}  ({100 * counts[name] / n:.1f}%)")
        union = counts["omitted"] + counts["wrong-value"]
        print(f"  UNION omitted+wrong-value: {union}/{n}  ({100 * union / n:.1f}%)"
              "   <- 340-H5's non-decomposable bar")
        print(f"    of which unreadable={unreadable}, already-past={past}")
        # #340 bar 340-U-D: a ZERO IS A MEASUREMENT AND MUST BE PRINTED AS ONE.
        #
        # `by_source` counts observed rows, so an arm whose fallback never
        # fired printed no `userText` token at all — and an absent token reads
        # as "the scorer lost the column", not as "the fallback produced
        # nothing". Those are exactly the two readings this arm exists to tell
        # apart: `armed-nofallback`'s whole contribution is a userText count of
        # ZERO, denominated on trials. So both LIVE sources are always printed.
        #
        # `legacy` is deliberately NOT given a zero, and never joins the live
        # pair: an archive that predates the `source=` field carries no opinion
        # about where its dates came from, so `userText=0/N` on such a run would
        # assert something the log cannot support — the same rule that makes the
        # label `legacy` rather than `none` in the first place.
        live_sources = ("model", "userText")
        if "legacy" in by_source:
            names = sorted(by_source)
        else:
            names = sorted(set(by_source) | set(live_sources))
        breakdown = ", ".join(f"{name}={by_source.get(name, 0)}/{n}"
                              for name in names)
        if not by_source:
            breakdown += "  (no populated-future trials)"
        print(f"  populated-future by SOURCE: {breakdown}"
              "   <- 340-U-C's column")
        # 340-C's founding measurement, kept visible now that the buckets are
        # denominated on the CARD: how often the MODEL sent nothing at all.
        # Without this line the argument rate would silently vanish from the
        # report the day the fallback started rescuing it.
        empty_arg = sum(1 for _, c in rows if c is not None and c.omitted)
        print(f"  model sent an EMPTY argument: {empty_arg}/{n}"
              "   <- 340-C's rate; the fallback rescues some of these")
        if "legacy" in by_source:
            print("    ⚠️  `legacy` = the archive predates the source= field "
                  "(2026-09-04). It is NOT `none`, and it licenses no claim "
                  "about where those dates came from.")
        print(f"  app-resolved a bare clock: {resolved}/{n}"
              "   <- #340 route (a) actually firing")
        # #340 fix wave / Owen's decision 2, second clause: "take the EARLIEST
        # future date and LOG THE CANDIDATE COUNT". Reported as the 2+ rate
        # rather than as the raw counts, because 2+ is the only value the ruling
        # is about — it is the trial where the earliest-future rule CHOSE
        # between dates instead of passing a single answer through. 0 and 1 are
        # already better said by `source=` and by the bucket.
        #
        # ABSENT IS NOT ZERO. A cell whose calls predate the field carries no
        # opinion about how many dates its messages named, and `0/N` there would
        # assert that none named two — the same rule that makes an absent
        # `source=` read `legacy` rather than `none`.
        counted = [c for _, c in rows
                   if c is not None and c.candidate_count is not None]
        if counted:
            multi = sum(1 for c in counted if c.candidate_count >= 2)
            print(f"  words carried 2+ date candidates: {multi}/{n}"
                  "   <- decision 2's earliest-future rule actually choosing")
        else:
            print("  words carried 2+ date candidates: field absent"
                  "   <- predates candidates= (2026-09-04); NOT a zero")
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
    # #340-U-C close-out (2026-09-04). The four lines above stopped being a
    # PARTITION the day `past_at_call` learned to judge the fallback path: a
    # fallback row that had already elapsed has `raw == ""` (OMITTED) AND
    # `past_at_call == True` (ALREADY PAST), so it is counted in BOTH lines
    # above and the four percentages can sum past 100% (measured 150% on a
    # two-row fixture). The per-cell view is unaffected — `bucket()` pools
    # such a row into `wrong-value` once, never both — so this line names the
    # overlap in the WHOLE-ARCHIVE view only, the same way `rescued` below
    # names its own OMITTED-subset overlap rather than redefining OMITTED.
    fallback_already_past = [c for c in calls if c.source == "userText" and c.past_at_call]
    print(f"  of which fallback rows already past (counted in both OMITTED and"
          f" ALREADY PAST): {len(fallback_already_past)}/{n}")
    # #340 Task 3. This view is denominated on the ARGUMENT and stays that way
    # — it exists for comparability with every pre-340-H4 measurement, so
    # redefining its OMITTED row would destroy the one thing it is for. But
    # from 2026-09-04 an omitted argument can still produce a correct card, so
    # the count is named here rather than left to be misread as a failure.
    rescued = [c for c in calls if c.source == "userText"]
    if rescued:
        print(f"  …of the omitted, RESCUED from the user's words: {len(rescued)}/{n}"
              f"  ({100 * len(rescued) / n:.1f}%)   ← counted under OMITTED above,"
              " which is an ARGUMENT rate")

    if populated:
        # 🔴 THE HEADING IS THE DENOMINATOR, and for one commit it was not.
        #
        # `populated` is `not omitted and not unreadable and not past_at_call`
        # — an ARGUMENT-denominated set, exactly as the comment above says this
        # view stays. A fallback-rescued row has `raw=""`, so it is `omitted`,
        # so it is NOT in this list: the heading "a usable due date reached the
        # card" named a set this list cannot contain, and its own `source=`
        # column can print `model` or `legacy` but never `userText` — a reader
        # who trusted the heading would have read the absence of `userText` as
        # the fallback never firing.
        #
        # Fixed by making the HEADING truthful rather than by moving the rows
        # in: the rows are what this view is for. Its whole purpose is
        # comparability with every pre-340-H4 measurement, and widening the set
        # would redefine the number those measurements are written in — the
        # same argument that keeps `omitted` itself unchanged. The
        # CARD-denominated view already exists, per cell, and is named here so
        # the operator is sent to it instead of misreading this one.
        print("\nPopulated arguments — the model IS capable of this field:")
        print("   (an ARGUMENT rate. Fallback-rescued rows are NOT listed here"
              " — their argument was empty, so they sit under OMITTED above."
              " For the CARD-denominated view read `populated-future by SOURCE`"
              " in the per-cell section, which needs `battery: BEGIN` lines.)")
        for c in populated:
            print(f"  {c.timestamp}  raw={c.raw!r}  source={c.source_label}  parsed={c.parsed}")

    if past:
        # 🔴 THE HEADING IS THE ATTRIBUTION, and it stopped being true on
        # 2026-09-04. This list used to contain only rows the MODEL populated,
        # so "when the model sent it" was exact. The fix wave taught
        # `past_at_call` to judge the FALLBACK's own value too — a row whose
        # argument was empty and whose date came from the user's sentence — and
        # a heading naming the model over a list that now contains those rows
        # is the same defect the per-call heading above already carried once.
        # The source is printed per row rather than guessed from the heading.
        print("\n🔴 A due that had ALREADY ELAPSED at call time.")
        print("   This is a WRONG value and is NOT counted as populated. A scorer")
        print("   cannot judge intent, so this bucket catches only the decidable")
        print("   case — the class that slipped past this script's first version.")
        print("   `source=` says which path produced it: `model` is judged on the")
        print("   raw argument, `userText` on the date that reached the card.")
        for c in past:
            print(f"  {c.timestamp}  source={c.source_label}  raw={c.raw!r}"
                  f"  parsed={c.parsed}  (already past when called)")

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
    # ---- #340 Task 3: the LEGACY shape. ----
    #
    # Every one of the three fixtures above is a REAL line collected before the
    # `source=` field existed, and they are the reason `source` is optional in
    # the pattern at all: an archive from 2026-08-15 must keep parsing exactly
    # as it did, and its rows must report `legacy` rather than `none` — `none`
    # is a positive claim that the card was dateless, which these lines do not
    # make.
    assert all(c.source is None for c in calls), "pre-#340 lines carry no source"
    assert all(c.source_label == "legacy" for c in calls), \
        "an absent source= must read as legacy, never as none"
    # A FUTURE due is the only shape that may read as cleanly populated.
    future = extract(
        '2026-08-15 14:58:08.920 Df Talaria 27[1:1] [org.aethyrion.talaria27:app] '
        'createReminder due raw="2026-08-16T16:00" parsed=Aug 16, 2026 at 4:00 PM\n'
    )
    assert len(future) == 1 and not future[0].past_at_call and not future[0].omitted
    # The banner line and the trailing separator must not parse as calls.
    assert extract("Timestamp               Ty Process[PID:TID]\n==========\n") == []

    # ---- #340 Task 3: the CURRENT shape, all three source values. ----
    #
    # THE ASSERTION THAT MATTERS MOST HERE IS ON `parsed`, not on `source`.
    # `parsed` runs greedily to end-of-line, so if `source=` were ever emitted
    # AFTER it, every one of these rows would parse with
    # `parsed="Sep 5, 2026 at 4:00 PM source=userText"` — still truthy, still
    # not "nil", and the `unreadable` bucket would silently drop to zero with
    # the source column looking perfectly healthy. So each row below asserts
    # the parsed value EXACTLY. The app side is pinned too
    # (`theInstrumentLineCarriesSourceAheadOfParsed`), which is the half a
    # fixture cannot prove: this file only sees the lines it was handed.
    sourced = extract(
        'Timestamp               Ty Process[PID:TID]\n'
        # ⚠️ THIS ROW CARRIES `candidates=` AND THE OTHER TWO DO NOT — on
        # purpose. The field landed on 2026-09-04's fix wave, after `source=`,
        # so an archive can legitimately carry either shape and BOTH must parse.
        # Mixing them inside one fixture is the cheapest way to prove it: a
        # regex that made the group mandatory would drop two of these three
        # rows, and a regex that omitted the group entirely would drop THIS one
        # (` parsed=` no longer follows ` source=…`), which is S-2's lesson —
        # an old copy of this script over a new archive reports NO DATA rather
        # than a quietly wrong number.
        '2026-09-04 09:00:01.100 Df Talaria 27[1:1] [org.aethyrion.talaria27:app] '
        'createReminder due raw="" bareClock=no source=userText candidates=2 parsed=Sep 5, 2026 at 4:00 PM\n'
        '2026-09-04 09:00:03.100 Df Talaria 27[1:1] [org.aethyrion.talaria27:app] '
        'createReminder due raw="16:30" bareClock=resolved source=model parsed=Sep 4, 2026 at 4:30 PM\n'
        '2026-09-04 09:00:05.100 Df Talaria 27[1:1] [org.aethyrion.talaria27:app] '
        'createReminder due raw="" bareClock=no source=none parsed=nil\n'
        '==========\n'
    )
    assert len(sourced) == 3, f"expected 3 source-bearing calls, got {len(sourced)}"
    assert [c.source for c in sourced] == ["userText", "model", "none"], \
        [c.source for c in sourced]
    assert [c.source_label for c in sourced] == ["userText", "model", "none"]
    assert sourced[0].parsed == "Sep 5, 2026 at 4:00 PM", \
        f"source= was swallowed into parsed: {sourced[0].parsed!r}"
    assert sourced[1].parsed == "Sep 4, 2026 at 4:30 PM", sourced[1].parsed
    assert sourced[2].parsed == "nil", sourced[2].parsed
    # The existing columns are untouched by the new field.
    assert [c.bareclock for c in sourced] == ["no", "resolved", "no"]

    # ---- Decision 2's second clause: the CANDIDATE COUNT, in both shapes. ----
    #
    # Owen's ruling reads "take the EARLIEST future date and LOG THE CANDIDATE
    # COUNT". The count answers a question no other field can: whether the
    # earliest-future rule was CHOOSING between dates or merely passing a single
    # answer through. Absent is `None`, never 0 — 0 is the positive claim that
    # the fallback ran and found nothing, which a pre-fix-wave archive does not
    # make. Same rule as `legacy` for `source=` and `no` for `bareClock=`.
    assert [c.candidates for c in sourced] == ["2", None, None], \
        [c.candidates for c in sourced]
    assert [c.candidate_count for c in sourced] == [2, None, None], \
        [c.candidate_count for c in sourced]
    # And the field must not have been eaten by `parsed`, which is the whole
    # reason it sits ahead of it (pinned app-side by
    # `theInstrumentLineCarriesSourceAheadOfParsed`).
    assert sourced[0].parsed == "Sep 5, 2026 at 4:00 PM", \
        f"candidates= was swallowed into parsed: {sourced[0].parsed!r}"

    # ---- The two predicates that came APART on 2026-09-04. ----
    #
    # Row 0 is the fallback firing: the model's ARGUMENT was empty (`omitted`
    # stays True — 340-C's measurement is not redefined) while the CARD carries
    # a real future instant (`dateless` is False). That divergence is the whole
    # of Task 3, and it is asserted here in both directions so a future edit
    # cannot quietly collapse the two back together.
    assert sourced[0].omitted and not sourced[0].dateless, \
        "the fallback row must be an empty ARGUMENT with a dated CARD"
    assert sourced[2].omitted and sourced[2].dateless, \
        "a source=none row is empty in both senses"
    assert not sourced[1].omitted and not sourced[1].dateless
    assert not sourced[0].unreadable and not sourced[1].past_at_call
    # And the bucket follows the CARD, which is what makes 340-U-C decidable.
    assert bucket(sourced[0]) == "populated-future", bucket(sourced[0])
    assert bucket(sourced[1]) == "populated-future", bucket(sourced[1])
    assert bucket(sourced[2]) == "omitted", bucket(sourced[2])

    # ---- 340-U-C's `already-past = 0` must be SCOREABLE on the fallback. ----
    #
    # `past_at_call` reads the RAW string, and every fallback row has `raw=""`,
    # so `omitted` was true and the function early-returned False: a
    # fallback-produced instant that had ALREADY ELAPSED would have read as
    # `populated-future`. The bar 340-U-C is written against says
    # `already-past = 0`, and a bucket that cannot go non-zero is not a
    # measurement — it is the constant denominator this project has been bitten
    # by before.
    #
    # The app's `detectDue` does guarantee a strictly-future answer (bar
    # 340-U-A, six pinned rows), so this is a scorer that double-checks a
    # guarantee rather than one that expects to find violations. That is
    # exactly the point: the guarantee lives in the app, and an instrument that
    # cannot contradict the thing it measures is not watching it.
    #
    # **The U+202F.** `displayDate` is a `DateFormatter` at `.medium`/`.short`,
    # and on iOS it emits a NARROW NO-BREAK SPACE before the meridiem, not an
    # ASCII space. A parser written against the ASCII form would silently fail
    # to read EVERY row from a real device and report `already-past = 0` — the
    # right answer for the wrong reason, which is the worst shape a bar can
    # have. Both spacings are fixtured, and the ASCII form is kept because that
    # is what the fixtures elsewhere in this file use.
    past_fallback = extract(
        'Timestamp               Ty Process[PID:TID]\n'
        # --- the fallback, future: still populated-future ---
        '2026-09-04 09:00:01.100 Df Talaria 27[1:1] [x] '
        'createReminder due raw="" bareClock=no source=userText parsed=Sep 5, 2026 at 4:00 PM\n'
        # --- the fallback, ALREADY PAST: a wrong value, not a present one ---
        '2026-09-04 09:00:03.100 Df Talaria 27[1:1] [x] '
        'createReminder due raw="" bareClock=no source=userText parsed=Sep 3, 2026 at 4:00 PM\n'
        # --- the same two as the DEVICE writes them, U+202F before the meridiem ---
        '2026-09-04 09:00:05.100 Df Talaria 27[1:1] [x] '
        'createReminder due raw="" bareClock=no source=userText parsed=Sep 5, 2026 at 4:00\u202fPM\n'
        '2026-09-04 09:00:07.100 Df Talaria 27[1:1] [x] '
        'createReminder due raw="" bareClock=no source=userText parsed=Sep 3, 2026 at 4:00\u202fPM\n'
        # --- controls ---
        # the MODEL path is judged on `raw` exactly as it always was…
        '2026-09-04 09:00:09.100 Df Talaria 27[1:1] [x] '
        'createReminder due raw="2026-09-04T08:00" bareClock=no source=model parsed=Sep 4, 2026 at 8:00 AM\n'
        # …a dateless card cannot be judged past at all…
        '2026-09-04 09:00:11.100 Df Talaria 27[1:1] [x] '
        'createReminder due raw="" bareClock=no source=none parsed=nil\n'
        # …and a LEGACY row makes no claim about where its date came from, so
        # the new branch must not touch it: this line is byte-for-byte the shape
        # a 2026-08-15 archive carries, with a display date that IS in the past,
        # and it must still bucket exactly as it did before the fix wave.
        '2026-09-04 09:00:13.100 Df Talaria 27[1:1] [x] '
        'createReminder due raw="" bareClock=no parsed=Sep 3, 2026 at 4:00 PM\n'
        '==========\n'
    )
    assert len(past_fallback) == 7, f"expected 7 calls, got {len(past_fallback)}"
    future_plain, past_plain, future_nnbsp, past_nnbsp, model_past, dateless, legacy_past = past_fallback

    assert not future_plain.past_at_call and bucket(future_plain) == "populated-future"
    assert past_plain.past_at_call, \
        "a fallback-produced due that had already elapsed read as populated"
    assert bucket(past_plain) == "wrong-value", bucket(past_plain)
    # The device's own spacing must score identically to the ASCII one, in BOTH
    # directions — a normaliser that ate the whole string would make every row
    # unparseable and every row would then read `not past`, which looks like a
    # clean bar.
    assert not future_nnbsp.past_at_call, "the U+202F future row read as past"
    assert past_nnbsp.past_at_call, \
        "the U+202F past row was unparseable, so it read as populated"
    assert bucket(future_nnbsp) == "populated-future"
    assert bucket(past_nnbsp) == "wrong-value"

    assert model_past.past_at_call and bucket(model_past) == "wrong-value", \
        "the model path's own already-past judgement must be unchanged"
    assert not dateless.past_at_call and bucket(dateless) == "omitted"
    # THE GATE IS ON `source`, NOT ON THE DATE — and this row is what proves it.
    # It carries a `parsed=` value that IS in the past and no `source=` field at
    # all, so a version that judged `parsed` whenever it could parse would flip
    # it. It must stay exactly where the pre-fix-wave script put it.
    assert legacy_past.source is None and not legacy_past.past_at_call, \
        "a legacy row carries no source= and licenses no judgement of its parsed value"
    assert bucket(legacy_past) == "populated-future", bucket(legacy_past)

    # And the per-CALL view must not ATTRIBUTE the fallback's past value to the
    # model. This is the heading defect the whole-branch review already caught
    # once, in the same report, one section down: a list whose members can only
    # be one thing, under a heading that names another.
    buf = io.StringIO()
    with redirect_stdout(buf):
        past_code = report([past_plain, model_past])
    past_out = buf.getvalue()
    assert past_code == 0, past_code
    assert "ALREADY ELAPSED at call time" in past_out, past_out
    assert "when the model sent it" not in past_out, \
        "the already-past list now contains fallback rows the model never sent"
    assert "source=userText" in past_out and "source=model" in past_out, past_out

    # ---- #340-U-C close-out: the OMITTED/ALREADY-PAST overlap must be NAMED. ----
    #
    # A fallback row that had already elapsed has `raw == ""` (OMITTED) AND
    # `past_at_call == True` (ALREADY PAST), so the whole-archive view's four
    # headline lines stopped partitioning the day `past_at_call` learned to
    # judge the fallback path: such a row is counted in BOTH lines, and the
    # four percentages can sum past 100% (measured 150% on a two-row fixture).
    # The per-cell view is unaffected — `bucket()` pools the row into
    # `wrong-value` only, once — so this is a whole-archive-view fix, named
    # the way `rescued` names its own OMITTED-subset overlap rather than
    # redefining OMITTED itself.
    #
    # `past_plain` (defined above, in `past_fallback`) is exactly that row:
    # `source=userText`, `raw=""`, and a `parsed=` value already in the past.
    # Paired with `model_past` (past, but NOT omitted — a populated argument),
    # this two-row report has exactly one row in the overlap.
    assert "of which fallback rows already past (counted in both OMITTED and" \
           " ALREADY PAST): 1/2" in past_out, past_out
    assert ("due OMITTED" in past_out and "due POPULATED" in past_out
            and "due UNREADABLE" in past_out and "due ALREADY PAST" in past_out), \
        "the four headline lines must still print"

    # ---- The per-CALL view's HEADING must name its own denominator. ----
    #
    # This block exists because the heading was WRONG for one commit: it read
    # "a usable due date reached the card" over a list built from
    # `not omitted and not unreadable and not past_at_call`, which excludes
    # every fallback-rescued row by construction. The three fixtures above are
    # exactly the discriminating input — one model-filled row (listed), one
    # rescued row and one dateless row (both omitted, neither listed) — so a
    # heading that claims the CARD is asserted false against output where the
    # card WAS dated and the row is absent.
    buf = io.StringIO()
    with redirect_stdout(buf):
        per_call_code = report(sourced)
    per_call_out = buf.getvalue()
    assert per_call_code == 0, per_call_code
    assert "Populated arguments — the model IS capable of this field:" in per_call_out, \
        per_call_out
    assert "a usable due date reached the card" not in per_call_out, \
        "the heading claims the CARD over an ARGUMENT-denominated list"
    assert "an ARGUMENT rate" in per_call_out, per_call_out
    # …and it must SEND the reader to the card-denominated view rather than
    # leaving them to infer that one exists.
    assert "populated-future by SOURCE" in per_call_out, per_call_out
    # The listed row is the model-filled one; the rescued row is counted on the
    # RESCUED line and is deliberately not in the list.
    assert "source=model" in per_call_out, per_call_out
    assert "RESCUED from the user's words: 1/3" in per_call_out, per_call_out
    assert "raw='16:30'" in per_call_out, per_call_out
    assert "raw=''" not in per_call_out, \
        "an empty-argument row is listed under a heading that excludes it"

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

    # ---- #340 Task 3: the LEGACY A/B above still scores IDENTICALLY. ----
    #
    # This is the whole backward-compatibility claim of the bucket change, and
    # it is asserted rather than argued: every fixture above predates `source=`,
    # and every one of its buckets is the value the pre-2026-09-04 script
    # produced. The list is written out in full so a future edit that shifts one
    # row has to say so.
    assert [bucket(c) for _, c in by_cell["armed"]] == \
        ["omitted", "wrong-value", "populated-future", "no-call"]
    assert [bucket(c) for _, c in by_cell["armed-bareclock"]] == \
        ["populated-future", "wrong-value", "no-call"]
    buf = io.StringIO()
    with redirect_stdout(buf):
        legacy_code = report_by_cell(by_cell)
    legacy_out = buf.getvalue()
    assert legacy_code == 0, legacy_code
    # A legacy archive's populated rows must be labelled `legacy`, never `none`,
    # and the report must SAY so rather than quietly printing a source column
    # that looks like a measurement.
    assert "populated-future by SOURCE: legacy=1/4" in legacy_out, legacy_out
    assert "the archive predates the source= field" in legacy_out, legacy_out
    # ABSENT IS NOT ZERO, for `candidates=` exactly as for `source=`. Not one
    # line of this A/B carries the field, and printing `0/4` would assert that
    # no message in the run named two dates — a claim the log cannot support.
    assert "words carried 2+ date candidates: field absent" in legacy_out, legacy_out
    assert "words carried 2+ date candidates: 0/" not in legacy_out, legacy_out

    # ---- #340 Task 3: the CURRENT shape, end to end through the report. ----
    #
    # Hand-built for the same reason the A/B above is: the branch that reports
    # `source=userText` must EXECUTE, not merely exist. Two cells, and the
    # treatment arm carries the shape the whole lane is for — an EMPTY argument
    # whose card is nonetheless dated, from the user's own sentence.
    sourced_ab = (
        'Timestamp               Ty Process[PID:TID]\n'
        # --- control: the model filled the field itself ---
        '2026-09-04 09:00:00.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed-nofallback p=remind t=1\n'
        '2026-09-04 09:00:01.100 Df Talaria 27[1:1] [x] createReminder due raw="16:30" bareClock=resolved source=model candidates=0 parsed=Sep 4, 2026 at 4:30 PM\n'
        '2026-09-04 09:00:02.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed-nofallback p=remind t=2\n'
        '2026-09-04 09:00:03.100 Df Talaria 27[1:1] [x] createReminder due raw="" bareClock=no source=none candidates=0 parsed=nil\n'
        # --- treatment: one model-filled, one rescued from the user's words ---
        # The rescued row carries `candidates=2`: the user's sentence named TWO
        # dates and decision 2's earliest-future rule chose between them. That
        # is the edge the ruling is about, and until the fix wave it was
        # invisible in every archive.
        '2026-09-04 09:10:00.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed p=remind t=1\n'
        '2026-09-04 09:10:01.100 Df Talaria 27[1:1] [x] createReminder due raw="16:30" bareClock=resolved source=model candidates=0 parsed=Sep 4, 2026 at 4:30 PM\n'
        '2026-09-04 09:10:02.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=armed p=remind t=2\n'
        '2026-09-04 09:10:03.100 Df Talaria 27[1:1] [x] createReminder due raw="" bareClock=no source=userText candidates=2 parsed=Sep 5, 2026 at 4:00 PM\n'
        '==========\n'
    )
    sourced_cells = attribute(extract(sourced_ab), extract_trials(sourced_ab))
    assert [bucket(c) for _, c in sourced_cells["armed-nofallback"]] == \
        ["populated-future", "omitted"]
    assert [bucket(c) for _, c in sourced_cells["armed"]] == \
        ["populated-future", "populated-future"]

    buf = io.StringIO()
    with redirect_stdout(buf):
        sourced_code = report_by_cell(sourced_cells)
    sourced_out = buf.getvalue()
    assert sourced_code == 0, sourced_code
    # 340-U-C's column, both arms, printed and asserted.
    assert "populated-future by SOURCE: model=1/2, userText=1/2" in sourced_out, sourced_out
    assert "populated-future by SOURCE: model=1/2" in sourced_out, sourced_out
    # ---- 340-U-D: `userText=0` on the nofallback arm is a MEASUREMENT. ----
    #
    # The two substring assertions above cannot see it, and that is the point:
    # `model=1/2` is a prefix of `model=1/2, userText=1/2`, so BOTH of them are
    # already satisfied by the treatment arm's line alone. A scorer that lost
    # the nofallback arm's column entirely would pass them. So the output is
    # split into per-cell sections and the arms are read separately — the
    # nofallback arm must show `userText=0/2`, which is the number 340-U-D's
    # contrast is denominated against.
    #
    # **A ZERO, NOT AN ABSENCE (fix round 1).** `by_source` counts observed
    # rows, so the arm used to print no `userText` token at all — and the
    # assertion here was `"userText" not in nofallback`, which passes equally
    # when the column is measured at zero and when the scorer has lost the
    # column. Those are the two things the operator most needs told apart, so
    # the arm now prints an explicit `userText=0/N` and this asserts that
    # literal, SCOPED to the `by SOURCE:` line: an unscoped scan over the whole
    # section would also be satisfied by the string turning up in a heading, a
    # warning, or any line added later.
    sections: "dict[str, list[str]]" = {}
    current = None
    for line in sourced_out.splitlines():
        if line.startswith("cell "):
            current = line.split()[1]
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    assert set(sections) == {"armed", "armed-nofallback"}, sorted(sections)
    nofallback = "\n".join(sections["armed-nofallback"])
    treatment = "\n".join(sections["armed"])

    def source_line(section: "list[str]") -> str:
        matches = [ln for ln in section if "by SOURCE:" in ln]
        assert len(matches) == 1, f"expected one `by SOURCE:` line, got {matches}"
        return matches[0]

    nofallback_sources = source_line(sections["armed-nofallback"])
    assert "populated-future by SOURCE: model=1/2, userText=0/2" in nofallback_sources, \
        nofallback_sources
    assert "userText=0/" in nofallback_sources, \
        f"the nofallback arm printed userText as an ABSENCE, not a zero: {nofallback_sources}"
    assert "populated-future by SOURCE: model=1/2, userText=1/2" in treatment, treatment
    # The zero is the arm's ONLY userText mention — a stray one elsewhere in the
    # section would leave a reader unsure which number the contrast is against.
    assert nofallback.count("userText") == 1, nofallback

    # ---- Decision 2's second clause, per cell. ----
    #
    # The count is reported as "how many trials had a message carrying 2+
    # candidates", because that is the only question the raw number answers on
    # its own: 1 is the ordinary case and 0 means the fallback did not run or
    # found nothing, both of which `source=` already says better. 2+ is the
    # edge Owen's ruling is ABOUT — the earliest-future rule choosing rather
    # than passing a single answer through — and it has never been visible.
    assert "words carried 2+ date candidates: 1/2" in treatment, treatment
    assert "words carried 2+ date candidates: 0/2" in nofallback, nofallback
    # And a cell with NO populated-future trials at all still prints both live
    # zeros, because that is the arm 340-U-D most hopes to see: a fallback that
    # rescued nothing produces exactly this cell, and "(no populated-future
    # trials)" alone would leave the operator with no `userText=0/N` to read.
    buf = io.StringIO()
    with redirect_stdout(buf):
        dry_code = report_by_cell({"armed": by_cell["armed"][:2]})
    dry = buf.getvalue()
    assert dry_code == 0, dry_code
    assert ("populated-future by SOURCE: model=0/2, userText=0/2"
            "  (no populated-future trials)") in dry, dry
    # 340-C's argument rate stays visible even though the card is now what the
    # buckets count — one omitted argument per arm, one of them rescued.
    assert sourced_out.count("model sent an EMPTY argument: 1/2") == 2, sourced_out
    # And no `legacy` warning on an archive that carries the field.
    assert "predates the source= field" not in sourced_out, sourced_out

    # ---- #200V: the DISCARDED warm-up trial is NOT an arm. ----
    #
    # The battery pays the model's cold start up front, outside the counts, and
    # tags that trial `shape=warmup … t=0` precisely so nothing downstream can
    # mistake it for a measurement (`batteryWarmupTag`, and the app-side
    # comment says so in as many words). This scorer did mistake it: the
    # #340-H5 archive scored as three arms, the third being
    # `cell warmup — 1 TRIALS` at 100% omission — a discarded trial wearing a
    # rate, sorted alphabetically to the bottom of the table where it reads
    # like a result.
    #
    # The fixture puts the warm-up in front of the same A/B used above, so the
    # measured arms' denominators are asserted UNCHANGED by its presence. That
    # is the half that a naive "drop anything called warmup" fix could still
    # get wrong.
    warm_ab = ab.replace(
        'Timestamp               Ty Process[PID:TID]\n',
        'Timestamp               Ty Process[PID:TID]\n'
        '2026-08-21 08:59:00.100 Df Talaria 27[1:1] [x] battery: BEGIN shape=warmup p=remind t=0\n'
        '2026-08-21 08:59:01.100 Df Talaria 27[1:1] [x] createReminder due raw="" bareClock=no parsed=nil\n',
        1)
    warm_cells = attribute(extract(warm_ab), extract_trials(warm_ab))

    # It must be PARSED and PRESENT here: the exclusion has to be a decision
    # taken at report time, never a regex that quietly fails to match. A fix
    # that worked by not seeing the row would pass the output assertions below
    # and would silently drop a real cell the day someone renames a tag.
    assert "warmup" in warm_cells, sorted(warm_cells)
    assert len(warm_cells["warmup"]) == 1
    assert warm_cells["warmup"][0][1] is not None, "the warm-up trial did make a call"
    assert len(warm_cells["armed"]) == 4 and len(warm_cells["armed-bareclock"]) == 3

    buf = io.StringIO()
    with redirect_stdout(buf):
        warm_code = report_by_cell(warm_cells)
    out = buf.getvalue()
    assert warm_code == 0, warm_code
    assert "cell warmup" not in out, "a discarded warm-up must never print as a cell"
    assert "discarded warm-up: 1 trial" in out, out
    assert "cell armed — 4 TRIALS" in out, out
    assert "cell armed-bareclock — 3 TRIALS" in out, out

    # And a run that is NOTHING BUT warm-up is NO DATA, not a clean sweep —
    # the same rule as an empty dict, because a warm-up is not a measurement.
    buf = io.StringIO()
    with redirect_stdout(buf):
        warm_only_code = report_by_cell({"warmup": warm_cells["warmup"]})
    out = buf.getvalue()
    assert warm_only_code == 2, "a warm-up-only archive must exit 2"
    assert "cell warmup" not in out, out
    assert "discarded warm-up: 1 trial" in out, out

    print("--- exercising the by-cell no-data guard; the block below is EXPECTED ---")
    assert report_by_cell({}) == 2, "no trials must exit 2, never report clean buckets"
    print("--- end expected block ---")

    print("SELF-TEST PASSED — 4 call fixtures, all four classes, the no-data")
    print("guard, #340-H4's four buckets attributed across a two-arm A/B, the")
    print("#200V warm-up trial reported as discarded rather than as an arm, and")
    print("#340 Task 3's source= column in BOTH line shapes: legacy archives")
    print("score byte-identically and report `legacy`, current ones report")
    print("model / userText / none with parsed= proven un-swallowed. Plus the")
    print("per-CALL heading pinned as ARGUMENT-denominated (rescued rows absent,")
    print("the reader sent to the card-denominated view), and 340-U-D's per-cell")
    print("split: the two arms read separately, the nofallback arm's userText")
    print("printed as an explicit 0/N zero rather than an absent token.")
    print("And the 2026-09-04 fix wave: decision 2's candidates= column in both")
    print("line shapes (absent reads `field absent`, never 0), and already-past")
    print("made SCOREABLE on the fallback path — parsed= judged against the")
    print("line's own timestamp in both spacings (ASCII and the device's")
    print("U+202F), gated on source=userText so legacy and model rows are")
    print("untouched, and the per-CALL past list no longer attributes a")
    print("fallback-produced value to the model.")
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
