#!/bin/bash
# #333: launch an instrument on a device via launch env, poll the artifact
# with a HARD timeout (a TCC hang parks a run silently — the harness detects
# it, not a human), fetch, and verify the POSITIVE completion flag.
# Usage: run-instrument.sh --device <name|udid> --instrument <name> [--trials N]
#        [--cells a,b] [--timeout SECONDS] [--out DIR]
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta5.app/Contents/Developer}"
BUNDLE_ID="org.aethyrion.talaria27"
DEVICE="" INSTRUMENT="" TRIALS=10 CELLS="" TIMEOUT=1800 OUT_ROOT="$HOME/.talaria-instrument-runs"
while [[ $# -gt 0 ]]; do case "$1" in
  --device) DEVICE="$2"; shift 2;; --instrument) INSTRUMENT="$2"; shift 2;;
  --trials) TRIALS="$2"; shift 2;; --cells) CELLS="$2"; shift 2;;
  --timeout) TIMEOUT="$2"; shift 2;; --out) OUT_ROOT="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 3;;
esac; done
[[ -n "$DEVICE" && -n "$INSTRUMENT" ]] || { echo "need --device and --instrument" >&2; exit 3; }

# Resolve to a PHYSICAL device udid (the Reality column — a sim match here
# once produced a phantom-hardware recommendation). Anchor on $NF (the last
# whitespace-delimited field), which is always the Reality column regardless
# of how many words the Model column has — an exact match, not a substring
# search over the whole row, so a device/model NAME that merely contains the
# word "physical" can never masquerade as a physical Reality value.
UDID=$(xcrun devicectl list devices 2>/dev/null | awk -v d="$DEVICE" \
  '$0 ~ d && $NF == "physical" {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) print $i}' | head -1)
[[ -n "$UDID" ]] || { echo "PRECONDITION: no connected physical device matching '$DEVICE'" >&2; exit 3; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ); OUT_DIR="$OUT_ROOT/$STAMP-$INSTRUMENT"; mkdir -p "$OUT_DIR"
SHA=$(git -C "$(dirname "$0")/../.." rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "device=$UDID instrument=$INSTRUMENT trials=$TRIALS cells=$CELLS timeout=${TIMEOUT}s sha=$SHA" | tee "$OUT_DIR/run.log"

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

fetch_latest() {
  rm -f "$OUT_DIR/latest.json"
  xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/InstrumentRuns/latest.json" \
    --destination "$OUT_DIR/latest.json" >/dev/null 2>&1 || return 1
}
status_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('status',''))" "$1" 2>/dev/null || echo ""; }
started_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('startedAt',''))" "$1" 2>/dev/null || echo ""; }

ELAPSED=0; STATUS=""; FIRST_STARTED=""
while (( ELAPSED < TIMEOUT )); do
  sleep 20; ELAPSED=$((ELAPSED+20))
  fetch_latest || continue
  S=$(status_of "$OUT_DIR/latest.json"); STARTED=$(started_of "$OUT_DIR/latest.json")
  # Guard against reading a PREVIOUS run's terminal artifact: only trust a
  # terminal status once we've seen THIS run's file (startedAt changes).
  if [[ -z "$FIRST_STARTED" && -n "$STARTED" ]]; then
    if [[ "$S" == "running" ]]; then FIRST_STARTED="$STARTED";
    elif (( ELAPSED >= 60 )); then FIRST_STARTED="$STARTED"; fi   # fast refusal never shows running
  fi
  [[ -n "$FIRST_STARTED" ]] || continue
  if [[ "$S" != "running" && -n "$S" ]]; then STATUS="$S"; break; fi
  echo "t+${ELAPSED}s status=$S" | tee -a "$OUT_DIR/run.log"
done
kill "$LAUNCH_PID" 2>/dev/null || true

if [[ -z "$STATUS" ]]; then
  echo "TIMEOUT after ${TIMEOUT}s — run NOT complete. Fetching store snapshots for post-mortem." | tee -a "$OUT_DIR/run.log"
  xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support/BatteryRuns" \
    --destination "$OUT_DIR/BatteryRuns" >/dev/null 2>&1 || true
  exit 2
fi
echo "RESULT: $STATUS — artifact at $OUT_DIR/latest.json" | tee -a "$OUT_DIR/run.log"
case "$STATUS" in completed|refused) exit 0;; *) exit 1;; esac
