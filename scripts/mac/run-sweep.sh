#!/bin/bash
# #343 Track U sequencer. Priority-ordered: archive-matched and Class 1 rows
# first, so a clock overrun truncates the LEAST valuable rows.
set -uo pipefail   # NOT -e: one failed instrument must not end the sweep.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta5.app/Contents/Developer}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${TALARIA_DEVICE:-whoGoesThere}"
OUT_ROOT="${TALARIA_SWEEP_OUT:-$HOME/.talaria-instrument-runs}"
LOG="$OUT_ROOT/sweep-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p "$OUT_ROOT"

# PRE-FLIGHT. A sweep that starts on the wrong runtime measures nothing, and
# finding that out at 2:15 costs the night.
PREFLIGHT_ARTIFACT="$(ls -t "$OUT_ROOT"/*/latest.json 2>/dev/null | head -1)"
if [[ -n "$PREFLIGHT_ARTIFACT" ]]; then
  OSV=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('osVersion',''))" \
        "$PREFLIGHT_ARTIFACT")
  echo "pre-flight: most recent artifact reports osVersion=$OSV" | tee -a "$LOG"
  case "$OSV" in
    *24A5408d*) : ;;
    *) echo "PRECONDITION: expected beta5 24A5408d, got '$OSV'" | tee -a "$LOG"; exit 3;;
  esac
fi

# name:trials — ORDER IS THE PRIORITY. Canary first, then archive-matched
# (Class 1), then everything else. Truncation takes from the bottom.
QUEUE=(
  "motion-redirect:10"          # canary #1 — archive 6AAA4AC4/328502AD
  "read-tool:10"                # RT-A  — archive 3E53397E/6C3EBD86 (Class 1a)
  "motion-scope:10"             # RT-B  — Class 1b canary
  "card-clause:10"
  "refusal-words:10"
  "decline:10"
  "shape:10"
  "router-probe:10"
  "intent-router-probe:10"
  "vector-router-probe:10"
  "toolless-index:10"
  "capability-detection-probe:10"
  "tokencount-preflight:3"
  "condensation-fit:10"
  "fm-asymmetries:10"
  "cross-chat-recall-probe:10"
  "router-context-probe:10"
  "image-routing-probe:10"
  "long-context-probe:10"
  "honesty:10"
  "honesty-v2:10"
)
DEADLINE_EPOCH="${TALARIA_SWEEP_DEADLINE:-0}"
# #343 fix round 1: an unguarded $DEADLINE_EPOCH inside (( )) is a bash
# arithmetic context — a non-integer value (a typo, or `$(date)` without
# +%s) is parsed as a variable NAME, and under `set -u` that is a FATAL
# unbound-variable error on the first loop iteration: zero instruments run,
# no log file is created, and the shell's own error exit code is masked by
# `| tee -a "$LOG"` never running — nothing prints "SWEEP COMPLETE" and
# nothing prints a failure either. Validate BEFORE it ever reaches
# arithmetic, and fail the same way the wrong-runtime gate does: a loud
# PRECONDITION, exit 3, before any instrument launches.
if [[ ! "$DEADLINE_EPOCH" =~ ^[0-9]+$ ]]; then
  echo "PRECONDITION: TALARIA_SWEEP_DEADLINE must be epoch seconds (0 = no deadline), got '$DEADLINE_EPOCH'" | tee -a "$LOG"
  exit 3
fi
OK=0; BAD=0; SKIPPED=()
for ENTRY in "${QUEUE[@]}"; do
  NAME="${ENTRY%%:*}"; TRIALS="${ENTRY##*:}"
  if [[ "$DEADLINE_EPOCH" != "0" ]] && (( $(date +%s) >= DEADLINE_EPOCH )); then
    SKIPPED+=("$NAME"); continue
  fi
  echo "=== $(date -u +%H:%M:%SZ) launching $NAME (trials=$TRIALS)" | tee -a "$LOG"
  # --timeout is passed EXPLICITLY. run-instrument.sh defaults to 1800s, and
  # the deadline above is only checked BETWEEN instruments — so a hang inside
  # one is uninterruptible by this loop, and a single parked run at the default
  # would eat 30 of Track U's 45 minutes before control ever returned here.
  # 600s bounds that to one instrument's worth of damage; the runner's own
  # TIMEOUT path still fetches store snapshots for the post-mortem, so a capped
  # run is a recorded failure rather than a silent hole.
  if "$HERE/run-instrument.sh" --device "$DEVICE" --instrument "$NAME" \
       --trials "$TRIALS" --timeout 600 --out "$OUT_ROOT" >>"$LOG" 2>&1; then
    echo "    OK $NAME" | tee -a "$LOG"; OK=$((OK+1))
  else
    echo "    FAILED $NAME (continuing)" | tee -a "$LOG"; BAD=$((BAD+1))
  fi
done
echo "SWEEP COMPLETE ok=$OK failed=$BAD skipped=${SKIPPED[*]:-none}" | tee -a "$LOG"
echo "log: $LOG"
