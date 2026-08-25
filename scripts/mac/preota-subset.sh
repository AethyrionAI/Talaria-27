#!/bin/bash
# #339: the PRE-OTA SUBSET sequencer — the ruled regression pass that runs
# before each staged OTA that will actually be tested. Five members, ~12 min
# unattended, one shared precondition set: unlocked physical device on the
# staged build · Verbose Logging ON · no TCC grants · writes nothing.
#
# Bands, anchors, and the era rules live in OPEN_ITEMS #339 — comparisons are
# BAND-based (a band and an n, never an equality assert; #215/#343 govern).
# `card-clause` is deliberately NOT queued: joining is a decision plus a code
# change (give it defaultCells) — see the entry's "conditional 6th".
#
# Runtime discipline, learned from run-sweep.sh's dead pin: no hardcoded
# osVersion. An osVersion CHANGE vs the previous artifact prints a loud
# RE-BASELINE marker and the run continues (the first run on a new runtime
# re-baselines the bands — that is expected, not an error). An operator who
# KNOWS what regime this run must be in sets TALARIA_EXPECTED_OS; a mismatch
# against the most recent artifact exits 3 before anything launches.
set -uo pipefail   # NOT -e: one failed instrument must not end the subset.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta6.app/Contents/Developer}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${TALARIA_DEVICE:-whoGoesThere}"
OUT_ROOT="${TALARIA_SUBSET_OUT:-$HOME/.talaria-instrument-runs}"
RUNNER="${TALARIA_RUNNER:-$HERE/run-instrument.sh}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
mkdir -p "$OUT_ROOT"
LOG="$OUT_ROOT/preota-$(date -u +%Y%m%dT%H%M%SZ).log"

# The five ruled members, in the ruled order. name|extra-args (beyond
# --trials). due-date's fixed "at 4:30pm" prompt makes its bands comparable
# only within one clock regime — the local time below goes in the record.
MEMBERS=(
  "due-date|20|--cells armed"
  "decline|10|"
  "long-context-probe|10|"     # NO --cells — its cells are the instrument's own
  "pcc-surface|3|"             # the regime witness: says app vs PLATFORM
  "refusal-words|10|"
)

newest_os() {
  local ARTIFACT
  ARTIFACT="$(ls -t "$OUT_ROOT"/*/latest.json 2>/dev/null | head -1)"
  [[ -n "$ARTIFACT" ]] || { echo ""; return; }
  python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('osVersion',''))" "$ARTIFACT" 2>/dev/null || echo ""
}

if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY-RUN: the subset would run, in order:"
  for ENTRY in "${MEMBERS[@]}"; do
    IFS='|' read -r NAME TRIALS EXTRA <<< "$ENTRY"
    echo "  $NAME --trials $TRIALS${EXTRA:+ $EXTRA}"
  done
  echo "DRY-RUN: nothing launched. Device=$DEVICE out=$OUT_ROOT"
  exit 0
fi

PREV_OS="$(newest_os)"
echo "pre-flight: previous artifact osVersion='${PREV_OS:-none}' local-time=$(date '+%Y-%m-%d %H:%M %Z')" | tee -a "$LOG"
if [[ -n "${TALARIA_EXPECTED_OS:-}" && -n "$PREV_OS" ]]; then
  case "$PREV_OS" in
    *"$TALARIA_EXPECTED_OS"*) : ;;
    *) echo "PRECONDITION: TALARIA_EXPECTED_OS='$TALARIA_EXPECTED_OS' but the previous artifact reports '$PREV_OS' — refusing to launch into the wrong regime" | tee -a "$LOG"
       exit 3;;
  esac
fi

OK=0; BAD=0; LAST_OS="$PREV_OS"
for ENTRY in "${MEMBERS[@]}"; do
  IFS='|' read -r NAME TRIALS EXTRA <<< "$ENTRY"
  echo "=== $(date -u +%H:%M:%SZ) launching $NAME (trials=$TRIALS${EXTRA:+ $EXTRA})" | tee -a "$LOG"
  # shellcheck disable=SC2086 — EXTRA is a controlled, space-separated flag list.
  if "$RUNNER" --device "$DEVICE" --instrument "$NAME" \
       --trials "$TRIALS" --timeout 600 --out "$OUT_ROOT" $EXTRA >>"$LOG" 2>&1; then
    echo "    OK $NAME" | tee -a "$LOG"; OK=$((OK+1))
  else
    echo "    FAILED $NAME (continuing)" | tee -a "$LOG"; BAD=$((BAD+1))
  fi
  CURR_OS="$(newest_os)"
  if [[ -n "$LAST_OS" && -n "$CURR_OS" && "$CURR_OS" != "$LAST_OS" ]]; then
    echo "⚠ RE-BASELINE: osVersion changed '$LAST_OS' → '$CURR_OS' — bands re-baseline on this run; do not compare across the transition (#339, #343 era rules)" | tee -a "$LOG"
  fi
  [[ -n "$CURR_OS" ]] && LAST_OS="$CURR_OS"
done
echo "SUBSET COMPLETE ok=$OK failed=$BAD" | tee -a "$LOG"
echo "score due-date from the DEVICE LOG (score-due-omission.py); decline via score-decline-attribution.py" | tee -a "$LOG"
echo "log: $LOG"
