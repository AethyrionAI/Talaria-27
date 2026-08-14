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
