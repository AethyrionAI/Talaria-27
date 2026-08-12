#!/bin/bash
# #333: launch an instrument on a device via launch env, poll the artifact
# with a HARD timeout (a TCC hang parks a run silently — the harness detects
# it, not a human), fetch, and verify the POSITIVE completion flag.
# Usage: run-instrument.sh --device <name|udid> --instrument <name> [--trials N]
#        [--cells a,b] [--timeout SECONDS] [--out DIR]
set -euo pipefail
# NOTE (tee-under-pipefail): every `cmd | tee -a "$OUT_DIR/run.log"` below is a
# plain two-stage pipe, and `set -o pipefail` (via `set -euo pipefail`) means
# the pipeline's exit status is non-zero if EITHER stage fails — so if `tee`
# itself fails (full disk, unwritable path) the pipeline fails and `set -e`
# aborts the script. That's intentional: a run whose own log can't be written
# should not continue unobserved.
# NOTE (bounded devicectl): macOS ships no GNU `timeout`, so every FOREGROUND
# `xcrun devicectl ...` invocation in this script is wrapped
# `perl -e 'alarm shift; exec @ARGV' 60 xcrun devicectl ...` — perl is always
# present, and its alarm() delivers SIGALRM (default disposition: terminate)
# to the exec'd devicectl process at the 60s mark if it hangs. The one
# exception is the app LAUNCH itself, which is deliberately backgrounded
# (`&`, tracked via $LAUNCH_PID) and is meant to keep running for the life of
# the app — it isn't a foreground call this script can block on, so it isn't
# a hang hazard in the same sense.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta5.app/Contents/Developer}"
BUNDLE_ID="org.aethyrion.talaria27"
DEVICE="" INSTRUMENT="" TRIALS=10 CELLS="" TIMEOUT=1800 OUT_ROOT="$HOME/.talaria-instrument-runs"
while [[ $# -gt 0 ]]; do case "$1" in
  --device) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 3; }; DEVICE="$2"; shift 2;;
  --instrument) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 3; }; INSTRUMENT="$2"; shift 2;;
  --trials) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 3; }; TRIALS="$2"; shift 2;;
  --cells) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 3; }; CELLS="$2"; shift 2;;
  --timeout) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 3; }; TIMEOUT="$2"; shift 2;;
  --out) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 3; }; OUT_ROOT="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 3;;
esac; done
[[ -n "$DEVICE" && -n "$INSTRUMENT" ]] || { echo "need --device and --instrument" >&2; exit 3; }

# Resolve to a PHYSICAL device udid (the Reality column — a sim match here
# once produced a phantom-hardware recommendation). Anchor on $NF (the last
# whitespace-delimited field), which is always the Reality column regardless
# of how many words the Model column has — an exact match, not a substring
# search over the whole row, so a device/model NAME that merely contains the
# word "physical" can never masquerade as a physical Reality value.
# NOTE: $0 ~ d treats the caller-supplied --device value as an awk regex, not
# a literal string — fine for a human-driven harness invocation, just don't
# feed it untrusted input.
UDID=$(perl -e 'alarm shift; exec @ARGV' 60 xcrun devicectl list devices 2>/dev/null | awk -v d="$DEVICE" \
  '$0 ~ d && $NF == "physical" {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) print $i}' | head -1)
[[ -n "$UDID" ]] || { echo "PRECONDITION: no connected physical device matching '$DEVICE'" >&2; exit 3; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ); OUT_DIR="$OUT_ROOT/$STAMP-$INSTRUMENT"
mkdir -p "$OUT_DIR" || { echo "PRECONDITION: cannot create $OUT_DIR" >&2; exit 3; }
SHA=$(git -C "$(dirname "$0")/../.." rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "device=$UDID instrument=$INSTRUMENT trials=$TRIALS cells=$CELLS timeout=${TIMEOUT}s sha=$SHA" | tee "$OUT_DIR/run.log"

fetch_latest() {
  rm -f "$OUT_DIR/latest.json"
  perl -e 'alarm shift; exec @ARGV' 60 \
    xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/InstrumentRuns/latest.json" \
    --destination "$OUT_DIR/latest.json" >/dev/null 2>&1 || return 1
}
status_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('status',''))" "$1" 2>/dev/null || echo ""; }
started_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('startedAt',''))" "$1" 2>/dev/null || echo ""; }

# Baseline copy, stderr captured (unlike fetch_latest, which discards it) so
# we can tell "nothing there yet" apart from "the device can't serve a copy
# right now" — see the three-state baseline logic below.
baseline_copy() {
  rm -f "$OUT_DIR/latest.json"
  perl -e 'alarm shift; exec @ARGV' 60 \
    xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/InstrumentRuns/latest.json" \
    --destination "$OUT_DIR/latest.json" >/dev/null 2>"$OUT_DIR/baseline-fetch.stderr"
}

# Baseline snapshot BEFORE the app launches: whatever terminal artifact is
# already sitting in the container (or none) becomes the floor a NEW
# artifact's startedAt must differ from. Without this, a previous run's
# completed/refused/failed file can be read as THIS run's verdict if the app
# is slow to write its own (CRITICAL, reproduced by the controller: prior
# completed artifact + slow-to-write new run → the old elapsed-time
# heuristic exited on the stale file at t+60s).
#
# Three possible outcomes, distinguished by stderr shape:
#   1. copy succeeds              -> BASELINE_STARTED = its startedAt.
#   2. copy fails, "not found"    -> legitimately no prior artifact (fresh
#                                     device / fresh install) -> "".
#   3. copy fails, any other way  -> retry twice (10s apart); still failing
#                                     -> PRECONDITION exit 3, BEFORE any
#                                     launch. A device that can't serve a
#                                     pre-launch copy will fail the poll
#                                     loop's copies too, and launching
#                                     anyway is exactly how a stale artifact
#                                     gets silently adopted as this run's
#                                     result.
BASELINE_STARTED=""
BASELINE_ESTABLISHED=0
for ATTEMPT in 1 2 3; do
  if baseline_copy; then
    BASELINE_STARTED=$(started_of "$OUT_DIR/latest.json")
    BASELINE_ESTABLISHED=1
    break
  fi
  # "Failed to retrieve the file node" / CoreDeviceError 7000 is devicectl's REAL
  # missing-file signature, observed live on the first #333 device run (2026-08-12);
  # the other patterns are kept as belt-and-braces for future toolchain wording.
  if grep -qiE "Failed to retrieve the file node|CoreDeviceError error 7000|couldn.t be found|No such file|does not exist" "$OUT_DIR/baseline-fetch.stderr" 2>/dev/null; then
    BASELINE_ESTABLISHED=1
    break
  fi
  if (( ATTEMPT < 3 )); then
    echo "baseline fetch attempt $ATTEMPT failed (not a not-found error); retrying in 10s" | tee -a "$OUT_DIR/run.log"
    sleep 10
  fi
done
if [[ "$BASELINE_ESTABLISHED" -ne 1 ]]; then
  echo "PRECONDITION: cannot establish artifact baseline (device copy failing)" >&2
  exit 3
fi

# Launch. DEVICECTL_CHILD_* is the proven env bridge (HANDOFF-2026-07-28).
# --console streams app stdout; background it — it blocks for the app's life.
DEVICECTL_CHILD_TALARIA_RUN_INSTRUMENT="$INSTRUMENT" \
DEVICECTL_CHILD_TALARIA_TRIALS="$TRIALS" \
DEVICECTL_CHILD_TALARIA_CELLS="$CELLS" \
DEVICECTL_CHILD_TALARIA_BUILD_SHA="$SHA" \
xcrun devicectl device process launch --terminate-existing --console \
  --device "$UDID" "$BUNDLE_ID" >> "$OUT_DIR/console.log" 2>&1 &
LAUNCH_PID=$!
echo "launched (console pid $LAUNCH_PID); polling every 20s" | tee -a "$OUT_DIR/run.log"

STATUS=""; FIRST_STARTED=""
SECONDS=0
while (( SECONDS < TIMEOUT )); do
  sleep 20
  fetch_latest || continue
  S=$(status_of "$OUT_DIR/latest.json"); STARTED=$(started_of "$OUT_DIR/latest.json")
  # Arm FIRST_STARTED only once we observe a startedAt that DIFFERS from the
  # pre-launch baseline (a newly-appeared file where none existed also
  # qualifies, since BASELINE_STARTED is "" in that case). No elapsed-time
  # heuristic — only the artifact's own identity proves it belongs to THIS
  # run. A run that never writes a new artifact times out (exit 2) instead
  # of ever reporting a verdict pulled from a stale file.
  if [[ -z "$FIRST_STARTED" && -n "$STARTED" && "$STARTED" != "$BASELINE_STARTED" ]]; then
    FIRST_STARTED="$STARTED"
  fi
  [[ -n "$FIRST_STARTED" ]] || continue
  if [[ "$S" != "running" && -n "$S" ]]; then STATUS="$S"; break; fi
  echo "t+${SECONDS}s status=$S" | tee -a "$OUT_DIR/run.log"
done
kill "$LAUNCH_PID" 2>/dev/null || true

if [[ -z "$STATUS" ]]; then
  echo "TIMEOUT after ${TIMEOUT}s — run NOT complete. Fetching store snapshots for post-mortem." | tee -a "$OUT_DIR/run.log"
  perl -e 'alarm shift; exec @ARGV' 60 \
    xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support/BatteryRuns" \
    --destination "$OUT_DIR/BatteryRuns" >/dev/null 2>&1 || true
  # Terminate the hung instance and leave the app idle at its normal launch
  # state — no DEVICECTL_CHILD_* env vars armed this time, so nothing runs;
  # this just clears a timed-out run off the device instead of leaving it
  # resident and stuck.
  perl -e 'alarm shift; exec @ARGV' 60 \
    xcrun devicectl device process launch --terminate-existing --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  exit 2
fi
echo "RESULT: $STATUS — artifact at $OUT_DIR/latest.json" | tee -a "$OUT_DIR/run.log"
case "$STATUS" in completed|refused) exit 0;; *) exit 1;; esac
