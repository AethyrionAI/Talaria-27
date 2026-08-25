#!/bin/bash
# #339: proves the pre-OTA subset sequencer's bars (SEQ-A..C) in ~1s against
# fixtures and a stub runner — the lane-gate-classify-test precedent: exercise
# the script's own logic without a device or a 12-minute run.
#
# SEQ-D (run-sweep.sh's minimal diff) is proven by inspection in the lane's
# result block — it is a two-line change to an existing script, not new logic.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/preota-subset.sh"
FAILURES=0
fail() { echo "  FAIL  $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  PASS  $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$SUT" ]] || { echo "  FAIL  preota-subset.sh missing or not executable — nothing to test"; echo "SELF-TEST: FAIL"; exit 1; }

# ---- fixtures ---------------------------------------------------------------
# A previous-run artifact reporting the beta5 device build, the regime every
# recorded anchor was measured on.
OUT_A="$TMP/out-a"
mkdir -p "$OUT_A/older-instrument"
cat > "$OUT_A/older-instrument/latest.json" <<'EOF'
{"osVersion": "iOS 27.0 (24A5408d)", "instrument": "older-instrument"}
EOF

# A stub runner: records its argv, seals a fresh artifact carrying STUB_OS,
# and fails only for STUB_FAIL_NAME — so sequencing honesty is observable.
STUB="$TMP/stub-runner.sh"
cat > "$STUB" <<'EOF'
#!/bin/bash
echo "$@" >> "$STUB_CALLS"
NAME=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instrument) NAME="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) shift;;
  esac
done
mkdir -p "$OUT/$NAME"
printf '{"osVersion": "%s", "instrument": "%s"}\n' "$STUB_OS" "$NAME" > "$OUT/$NAME/latest.json"
[[ "$NAME" == "${STUB_FAIL_NAME:-}" ]] && exit 1
exit 0
EOF
chmod +x "$STUB"

# ---- SEQ-A: dry-run prints the five ruled invocations, in order, launches nothing
CALLS="$TMP/calls-a.log"; : > "$CALLS"
DRY=$(STUB_CALLS="$CALLS" STUB_OS="unused" TALARIA_RUNNER="$STUB" \
      TALARIA_SUBSET_OUT="$OUT_A" "$SUT" --dry-run 2>&1)
if [[ $? -ne 0 ]]; then fail "SEQ-A: dry-run exited nonzero"; fi
POSITIONS=()
for SPEC in \
  "due-date --trials 20 --cells armed" \
  "decline --trials 10" \
  "long-context-probe --trials 10" \
  "pcc-surface --trials 3" \
  "refusal-words --trials 10"
do
  LINE_NO=$(printf '%s\n' "$DRY" | grep -n -F -- "$SPEC" | head -1 | cut -d: -f1)
  if [[ -z "$LINE_NO" ]]; then
    fail "SEQ-A: dry-run missing invocation: $SPEC"
  else
    POSITIONS+=("$LINE_NO")
  fi
done
if [[ ${#POSITIONS[@]} -eq 5 ]]; then
  SORTED=$(printf '%s\n' "${POSITIONS[@]}" | sort -n)
  [[ "$(printf '%s\n' "${POSITIONS[@]}")" == "$SORTED" ]] \
    && pass "SEQ-A: five invocations present in the ruled order" \
    || fail "SEQ-A: invocations out of ruled order (${POSITIONS[*]})"
fi
printf '%s\n' "$DRY" | grep -n -F -- "long-context-probe" | head -1 | grep -q -- "--cells" \
  && fail "SEQ-A: long-context-probe carries --cells (its cells must stay the instrument's own)" \
  || pass "SEQ-A: long-context-probe carries no --cells"
[[ -s "$CALLS" ]] && fail "SEQ-A: dry-run launched the runner" || pass "SEQ-A: dry-run launched nothing"

# ---- SEQ-B (gate half): EXPECTED_OS mismatch exits 3 before any launch
CALLS="$TMP/calls-b1.log"; : > "$CALLS"
set +e
STUB_CALLS="$CALLS" STUB_OS="iOS 27.0 (24A5422a)" TALARIA_RUNNER="$STUB" \
  TALARIA_SUBSET_OUT="$OUT_A" TALARIA_EXPECTED_OS="24A5422a" "$SUT" > "$TMP/b1.log" 2>&1
RC=$?
set -e
[[ $RC -eq 3 ]] && pass "SEQ-B: EXPECTED_OS mismatch vs previous artifact exits 3" \
                || fail "SEQ-B: expected exit 3 on EXPECTED_OS mismatch, got $RC"
[[ -s "$CALLS" ]] && fail "SEQ-B: a mismatched gate still launched the runner" \
                  || pass "SEQ-B: nothing launched under the failed gate"

# ---- SEQ-B (drift half): an osVersion change prints RE-BASELINE and continues
OUT_B="$TMP/out-b"; mkdir -p "$OUT_B/older-instrument"
cp "$OUT_A/older-instrument/latest.json" "$OUT_B/older-instrument/latest.json"
CALLS="$TMP/calls-b2.log"; : > "$CALLS"
STUB_CALLS="$CALLS" STUB_OS="iOS 27.0 (24A5422a)" TALARIA_RUNNER="$STUB" \
  TALARIA_SUBSET_OUT="$OUT_B" "$SUT" > "$TMP/b2.log" 2>&1
grep -q "RE-BASELINE" "$TMP/b2.log" \
  && pass "SEQ-B: osVersion change prints the RE-BASELINE marker" \
  || fail "SEQ-B: no RE-BASELINE marker on an osVersion change"
[[ "$(wc -l < "$CALLS" | tr -d ' ')" == "5" ]] \
  && pass "SEQ-B: the run continued through all five members after the marker" \
  || fail "SEQ-B: expected 5 launches after re-baseline, got $(wc -l < "$CALLS" | tr -d ' ')"

# ---- SEQ-C: a failing member is recorded and the rest still run
OUT_C="$TMP/out-c"; mkdir -p "$OUT_C"
CALLS="$TMP/calls-c.log"; : > "$CALLS"
STUB_CALLS="$CALLS" STUB_OS="iOS 27.0 (24A5422a)" STUB_FAIL_NAME="decline" \
  TALARIA_RUNNER="$STUB" TALARIA_SUBSET_OUT="$OUT_C" "$SUT" > "$TMP/c.log" 2>&1
[[ "$(wc -l < "$CALLS" | tr -d ' ')" == "5" ]] \
  && pass "SEQ-C: all five members attempted despite the failure" \
  || fail "SEQ-C: expected 5 launches, got $(wc -l < "$CALLS" | tr -d ' ')"
grep -q "FAILED decline" "$TMP/c.log" \
  && pass "SEQ-C: the failing member is named FAILED" \
  || fail "SEQ-C: the failing member was not reported"
grep -q "ok=4 failed=1" "$TMP/c.log" \
  && pass "SEQ-C: the summary counts reconcile (ok=4 failed=1)" \
  || fail "SEQ-C: summary counts wrong — $(grep 'SUBSET COMPLETE' "$TMP/c.log" || echo 'no summary line')"

echo
if [[ $FAILURES -eq 0 ]]; then echo "SELF-TEST: PASS"; exit 0; fi
echo "SELF-TEST: FAIL ($FAILURES)"; exit 1
