#!/usr/bin/env python3
"""Score 337-G-2: narration in the clause-ON arm vs the clause-OFF arm.

TWO classifiers are reported, never collapsed, because the two eras used
different ones and a single number would silently pick a side:

  STRICT  — the literal "Confirmation card:" specimen (#337-A / 337-G's count).
  200J    — the archived grep: "confirmation card" | "would you like to
            proceed" | "shall I proceed" (OPEN_ITEMS-ARCHIVE.md:7517). This is
            WIDER: it also catches the plain offer, which 337-G counted
            separately as "offered instead of acting".

Plus the behaviour readings 337-G established, so the arms are comparable on
what actually happened, not only on what was said:
  executed  — >=1 tool call recorded
  fabricated— zero tool calls AND a completed-action claim ("has been created",
              "I've set", "is now on your calendar", ...)
  offered   — zero tool calls AND an offer to proceed
"""
import json, re, sys, glob, os

STRICT = re.compile(r"confirmation card:", re.I)
J200 = re.compile(r"confirmation card|would you like (me )?to proceed|shall i proceed", re.I)
CLAIM = re.compile(
    r"has been (created|set|added|scheduled)|i(?:'| ha)?ve (created|set|added|scheduled)"
    r"|is now on your calendar|is now active|your (alarm|reminder|event) is set"
    r"|you're all set|reminder (has been )?(created|set)",
    re.I)
OFFER = re.compile(r"shall i (proceed|create|set|add)|would you like|want me to"
                   r"|should i (create|set|add)|do you want me to|let me know", re.I)


def norm(s):
    """Curly apostrophes are the whole fabrication class ("I’ve set") — a
    straight-quote-only regex scored 0/10 where the truth was 3/10."""
    return (s or "").replace("’", "'").replace("‘", "'")


def score(path):
    d = json.load(open(path))
    rr = d["runRecord"]
    rows = rr["trials"]
    out = {}
    for t in rows:
        key = (t.get("shape", "?"), t.get("prompt", "?"))
        b = out.setdefault(key, dict(n=0, strict=0, j200=0, executed=0,
                                     fabricated=0, offered=0, cut=0, specimens=[]))
        text = norm(t.get("text"))
        calls = t.get("toolCalls") or []
        b["n"] += 1
        if STRICT.search(text):
            b["strict"] += 1
            b["specimens"].append((t.get("trial"), text[:200]))
        if J200.search(text):
            b["j200"] += 1
        if calls:
            b["executed"] += 1
        else:
            if CLAIM.search(text):
                b["fabricated"] += 1
            elif OFFER.search(text):
                b["offered"] += 1
        if t.get("cant") or t.get("timedOut") or not text:
            b["cut"] += 1
    return d, rr, out


def report(path):
    d, rr, out = score(path)
    print(f"\n=== {os.path.basename(os.path.dirname(path))} ===")
    print(f"instrument={d['instrument']} status={d['status']} "
          f"endedCleanly={rr.get('endedCleanly')} id={rr.get('id')} "
          f"trials={len(rr['trials'])} perCell={rr.get('trialsPerCell')} "
          f"unattended={d.get('unattended')} os={d.get('osVersion')}")
    print(f"cells={rr.get('cells')} thermal={rr.get('thermal')}")
    print(f"reap: {rr.get('reapSummary')}")
    print(f"{'cell/prompt':32} {'n':>3} {'STRICT':>6} {'200J':>5} {'exec':>5} "
          f"{'fab':>4} {'offer':>5} {'empty':>5}")
    tot = dict(n=0, strict=0, j200=0, executed=0, fabricated=0, offered=0, cut=0)
    for (shape, prompt), b in sorted(out.items()):
        print(f"{shape+'/'+prompt:32} {b['n']:3} {b['strict']:6} {b['j200']:5} "
              f"{b['executed']:5} {b['fabricated']:4} {b['offered']:5} {b['cut']:5}")
        for k in tot:
            tot[k] += b[k]
    print(f"{'TOTAL':32} {tot['n']:3} {tot['strict']:6} {tot['j200']:5} "
          f"{tot['executed']:5} {tot['fabricated']:4} {tot['offered']:5} {tot['cut']:5}")
    for (shape, prompt), b in sorted(out.items()):
        for trial, text in b["specimens"]:
            print(f"  SPECIMEN {shape}/{prompt} t{trial}: {text}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
