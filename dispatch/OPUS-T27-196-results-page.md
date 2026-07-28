# OPUS-T27-196-RESULTS-PAGE — in-app battery results: view + export, no Mac required

**Executor:** local Claude Code. **Requested by Owen 2026-07-28.** Build ON TOP of the
open PR stack (#160/#161) or after their merge — your call from branch state; the
results page ships as its OWN file-scoped PR either way.

## Why

Owen can install OTA-staged builds from work over the tailnet, but Console/Xcode
capture only works at home on the LAN. Battery runs (n=10/n=20 buttons AND the #161
router cells) are currently write-only from work. The instrument needs an in-app
results surface: capture, view, and — the part that matters most — EXPORT, so raw
results can be pasted to the verdict desk from anywhere.

## Requirements

**1. Capture — structured store, not just os.Logger.** Keep the Console lines exactly
as they are (home workflow unchanged); ADDITIONALLY write per-trial records to a
persisted run store: run header (timestamp, build/commit, n, cell list) + per trial:
shape, prompt tag, trial index, FULL reply text (the 180-char prefix was a Console
constraint — full text is the classification upgrade), cant/denial flags, tool
invocations with details (feed the store from the same `batteryTrialTag` path the
relay logging uses), ERROR/TIMEOUT markers, and per-trial latency. Router cells (#161)
additionally record the router's classification decision and chosen route per trial.
Persist as one JSON file per run in Application Support — NOT UserDefaults (#104's
churn lesson; runs are 100KB+). Bound the store (keep the most recent ~10 runs).

**2. View — Diagnostics → "Battery results".** Run list (date, build, n, cells,
trial/error counts) → run detail: per-cell × prompt tally table computed from flags,
LABELED as heuristic (raw text is ground truth — the page must never present flag
tallies as verdicts) → drill into any cell×prompt for the full raw replies with tool
lines inline. Router runs also show the decision distribution (intent → route counts).

**3. Export — the actual point.** A "Copy raw run" button placing the COMPLETE run on
the clipboard in the established `battery:` line format (with full texts), so a paste
into chat is immediately classifiable by the verdict desk; plus a share sheet for the
JSON. This replaces Console entirely for the work flow.

**4. Constraints.** DEBUG-only surface, Release compiles out (pin it). Zero production
behavior changes. Real-data only — no sample/demo rows ever, an empty store shows an
empty state. Past runs are not recoverable (they were Console-only; already tabulated
in OPEN_ITEMS) — do not fake them. Tests: record encode/decode round-trip, store
bounding, battery writes N records for N trials via an injectable store, tally math.
House rules apply: file-scoped commits, merge commits only, OPEN_ITEMS separate,
suite green with stated count, evidence scope + build ID in the PR.

**5. After merge:** OTA-stage Debug (`scripts/mac/ota-stage.sh main Debug`) and report
the staged commit so Owen can install from work.
