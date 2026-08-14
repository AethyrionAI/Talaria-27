#!/usr/bin/env python3
"""#343: score beta4 archive runs and beta5 artifacts through ONE classifier.

The two eras use different envelopes and the same trial core:
  beta4 (handoffs/evidence/battery-runs/*.json) — flat; trials at top level.
  beta5 (~/.talaria-instrument-runs/*/latest.json) — trials under runRecord.

Scoring both with one code path is the whole point; a per-era classifier would
reintroduce the confound the campaign exists to control.
"""
import json, os, re, sys
from math import comb

BETA4_BUILD = "24A5390f"
BETA5_BUILD = "24A5408d"


def load(path):
    """-> (envelope, record, trials). Handles both eras."""
    d = json.load(open(path))
    rec = d.get("runRecord") or d
    return d, rec, (rec.get("trials") or [])


def era(record):
    os_v = record.get("osVersion") or ""
    if BETA4_BUILD in os_v:
        return "beta4"
    if BETA5_BUILD in os_v:
        return "beta5"
    return "unknown"


def fisher(a, b, c, d):
    """Two-tailed Fisher exact on [[a,b],[c,d]]. stdlib only — scipy is absent.
    Validated against five published project p-values in score-eras-test.py."""
    n = a + b + c + d
    r1, r2, c1 = a + b, c + d, a + c
    def p(x):
        return comb(r1, x) * comb(r2, c1 - x) / comb(n, c1)
    p_obs = p(a)
    lo, hi = max(0, c1 - r2), min(c1, r1)
    return min(1.0, sum(p(x) for x in range(lo, hi + 1)
                        if p(x) <= p_obs * (1 + 1e-9)))


def norm(s):
    """The model writes I’ve with a CURLY apostrophe. 337-G's first scorer draft
    used a straight one and read fabrication 0/10 where the truth was 3/10."""
    return (s or "").replace("’", "'").replace("‘", "'")


# Copied VERBATIM from planning/reports/2026-08-13-337g2-clause-ab/score-337g2.py
# so 337-G-2's numbers reproduce exactly. That file is evidence and is not edited.
STRICT = re.compile(r"confirmation card:", re.I)
J200 = re.compile(r"confirmation card|would you like (me )?to proceed|shall i proceed", re.I)
CLAIM = re.compile(
    r"has been (created|set|added|scheduled)|i(?:'| ha)?ve (created|set|added|scheduled)"
    r"|is now on your calendar|is now active|your (alarm|reminder|event) is set"
    r"|you're all set|reminder (has been )?(created|set)", re.I)
OFFER = re.compile(r"shall i (proceed|create|set|add)|would you like|want me to"
                   r"|should i (create|set|add)|do you want me to|let me know", re.I)


def classify(trial):
    """One trial -> behaviour flags.

    `errored` is INSTRUMENT state and is kept strictly apart: the harness timed
    out, or the model returned no text at all. There is nothing to classify, so
    it short-circuits and no behavioural counter fires.

    **`cant` is NOT instrument state, and is NOT exclusive** (corrected
    2026-08-14, #343 final review). The app derives it from the model's OWN
    reply — `LocalChatBackend+Battery.swift:318` prefix-matches "i cannot" /
    "i can't" / "i can not" on the success path, after the response arrived —
    so it is a behavioural MEASUREMENT, and the project reads it as one: the
    #196 tic guard's observable is "`denial`/`cant` on these three IS the tic
    measurement" (`:3641`), and archived #214 reports haiku `cant` **10/10**
    as a result. #343's RT-A lists it among the TEXT-derived metrics.

    So `cant` gets its own counter and the trial is STILL classified
    behaviourally — exactly how the frozen reference scorer flagged `cut`
    alongside the behaviour counts rather than instead of them
    (`planning/reports/2026-08-13-337g2-clause-ab/score-337g2.py:63`).

    Scoring it as an error deleted real counts. On `1835BBF9`'s
    `armed-scopedv2/haiku` cell — the #214 composition-denial result RT-E
    exists to re-measure — ten trials that all produced text, seven of them
    offering an alternative, printed as `n=10 err=10 exec=0 fab=0 offer=0`,
    which reads as an instrument failure that never happened.
    """
    text = norm(trial.get("text"))
    calls = trial.get("toolCalls") or []
    out = dict(executed=0, fabricated=0, offered=0, strict=0, j200=0,
               cant=0, errored=0)
    # Recorded BEFORE the errored short-circuit and independently of it, so a
    # `cant` reply can never be lost to an instrument outcome landing on the
    # same trial. No archive or beta5 fixture carries both today (measured:
    # zero such rows across all twelve), but the ordering costs nothing and is
    # the difference between a counter that cannot silently drop a count and
    # one that can.
    if trial.get("cant"):
        out["cant"] = 1
    if trial.get("timedOut") or not text.strip():
        out["errored"] = 1
        return out
    if STRICT.search(text):
        out["strict"] = 1
    if J200.search(text):
        out["j200"] = 1
    if calls:
        out["executed"] = 1
    elif CLAIM.search(text):
        out["fabricated"] = 1
    elif OFFER.search(text):
        out["offered"] = 1
    return out


# Which read tool correctly answers each probe prompt. Derived from 6AAA4AC4's
# own rows (armed: stepsdirect->readHealth 10/10, motiondirect->readMotion
# 10/10), not from the tool descriptions.
CORRECT_TOOL = {"stepsdirect": "readHealth", "motiondirect": "readMotion"}
# Prompts that NAME their location, so a location lookup is spurious.
NAMED_LOCATION = {"weathernamed"}


def tool_names(trial):
    return [c.get("name") for c in (trial.get("toolCalls") or [])]


def metric_correct_tool(trial):
    """RT-B / RT-F: 1 if the prompt's correct read tool was called. None off-family."""
    want = CORRECT_TOOL.get(trial.get("prompt"))
    if want is None:
        return None
    return 1 if want in tool_names(trial) else 0


def metric_spurious_location(trial):
    """RT-A: 1 if currentLocation was called on a prompt that NAMES its location.
    This is the observable separating armed (1 call) from armed-fieldrollback
    (2 calls) on weathernamed in 3E53397E."""
    if trial.get("prompt") not in NAMED_LOCATION:
        return None
    return 1 if "currentLocation" in tool_names(trial) else 0


def tally(trials):
    out = {}
    for t in trials:
        key = (t.get("shape", "?"), t.get("prompt", "?"))
        b = out.setdefault(key, dict(n=0, executed=0, fabricated=0, offered=0,
                                     strict=0, j200=0, cant=0, errored=0,
                                     correct_tool=0, correct_tool_n=0,
                                     spurious_loc=0, spurious_loc_n=0))
        b["n"] += 1
        for k, v in classify(t).items():
            b[k] += v
        ct = metric_correct_tool(t)
        if ct is not None:
            b["correct_tool"] += ct
            b["correct_tool_n"] += 1
        sl = metric_spurious_location(t)
        if sl is not None:
            b["spurious_loc"] += sl
            b["spurious_loc_n"] += 1
    return out


def report(path):
    env, rec, trials = load(path)
    print(f"\n=== {os.path.basename(path)} ===")
    print(f"era={era(rec)} os={rec.get('osVersion')} kind={rec.get('kind')} "
          f"endedCleanly={rec.get('endedCleanly')} n={len(trials)}")
    print(f"cells={rec.get('cells')} thermal={rec.get('thermal')}")
    # `cant` sits next to `err` because the two were confused until 2026-08-14
    # and the columns must be read as neighbours, never as one number: `err` is
    # the instrument, `cant` is the model, and a `cant` row still carries its
    # exec/fab/offer.
    hdr = (f"{'cell/prompt':34}{'n':>4}{'err':>5}{'cant':>6}{'exec':>6}{'fab':>5}"
           f"{'offer':>6}{'strict':>7}{'tool✓':>7}{'spurLoc':>8}")
    print(hdr)
    for (shape, prompt), b in sorted(tally(trials).items()):
        ct = f"{b['correct_tool']}/{b['correct_tool_n']}" if b["correct_tool_n"] else "—"
        sl = f"{b['spurious_loc']}/{b['spurious_loc_n']}" if b["spurious_loc_n"] else "—"
        print(f"{shape + '/' + prompt:34}{b['n']:>4}{b['errored']:>5}{b['cant']:>6}"
              f"{b['executed']:>6}{b['fabricated']:>5}{b['offered']:>6}"
              f"{b['strict']:>7}{ct:>7}{sl:>8}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
