#!/bin/bash
# #416: proves run-instrument.sh's DEVICE RESOLVER (bars 416-A..D) and
# preota-subset.sh's exit contract (416-E) in ~1s against a fixture listing and
# a stubbed `xcrun` — the preota-subset-test / lane-gate-classify-test
# precedent: exercise the script's own logic with no device and no 12-minute run.
#
# Why this file exists: the resolver extracted the identifier by its LENGTH
# (/^[0-9A-F-]{36}$/). When `devicectl` began reporting whoGoesThere in the
# 25-char ECID form, the match silently emptied and EVERY device instrument run
# died at the precondition check — before a run directory was even created, so
# the only evidence was a one-line "FAILED". A length is a guess; the listing
# prints `<identifier> (UDID)`, so the token before `(UDID)` is an anchor.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/run-instrument.sh"
SUBSET="$HERE/preota-subset.sh"
FAILURES=0
fail() { echo "  FAIL  $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  PASS  $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$SUT" ]] || { echo "  FAIL  run-instrument.sh missing or not executable"; echo "SELF-TEST: FAIL"; exit 1; }

# ---- fixture: a real `devicectl list devices` capture ------------------------
# Verbatim shapes observed 2026-08-27, covering every form the resolver must
# survive: ECID-form physical (the phone), UUID-form physical (the iPad),
# simulated rows whose NAME collides with the physical one, and a paired watch
# whose row carries an identifier but is not a `physical` reality.
LISTING="$TMP/devices.txt"
cat > "$LISTING" <<'EOF'
Name                 Hostname   Identifier                                    State                Model                              Reality
------------------   --------   -------------------------------------------   ------------------   --------------------------------   ---------
CC-lane-1                       79402942-3DD4-4187-9710-044C784840FE (UDID)   shutdown             iPhone Air (iPhone18,4)            simulated
whoGoesThere-sim                D704B375-4077-49A7-98A3-509B73456EBE (UDID)   shutdown             iPhone 17 Pro (iPhone18,1)         simulated
Owen's Apple Watch              00008301-D09C89683C0BC02E (UDID)              available (paired)   Watch6,2
LegacyFormPhone                 91CBCB90-B313-5B09-A405-E0FE284C9D75 (UDID)   connected            iPhone 17 Pro Max (iPhone18,2)     physical
Shelley's iPad (3)              00008122-0006186214E1801C (UDID)              connected (no DDI)   iPad Air 11-inch (M3) (iPad15,3)   physical
whoGoesThere                    00008150-000E794C3C47801C (UDID)              connected            iPhone 17 Pro Max (iPhone18,2)     physical
EOF
# NOTE on the fixture's `LegacyFormPhone` row: tonight's real listing contains NO
# UUID-form PHYSICAL device — every physical row is ECID-form. That row carries
# the 36-char identifier `devicectl` actually reported for whoGoesThere from
# 08-12 through 08-21 (every archived run.log records it), so 416-B guards the
# historical shape rather than a shape merely assumed to exist. This corrects a
# bar-formation error caught by the test's own first run: 416-B originally
# pointed at the iPad and called it UUID-form, which it is not.

# A stub `xcrun` that answers `devicectl list devices` from the fixture and
# refuses everything else — so a test that somehow got past resolution cannot
# silently touch a real device.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/xcrun" <<EOF
#!/bin/bash
if [[ "\$*" == *"list devices"* ]]; then cat "$LISTING"; exit 0; fi
echo "stub xcrun: refusing unexpected invocation: \$*" >&2
exit 90
EOF
chmod +x "$TMP/bin/xcrun"

resolve() {  # resolve <device-arg> -> prints udid, returns the script's rc
  PATH="$TMP/bin:$PATH" TALARIA_RESOLVE_ONLY=1 \
    "$SUT" --device "$1" --instrument decline 2>"$TMP/resolve.stderr"
}

# ---- 416-A: an ECID-form identifier (25 chars) on a physical row RESOLVES ----
GOT="$(resolve whoGoesThere)"; RC=$?
if [[ $RC -eq 0 && "$GOT" == "00008150-000E794C3C47801C" ]]; then
  pass "416-A: ECID-form identifier resolves (00008150-000E794C3C47801C)"
else
  fail "416-A: ECID-form identifier did NOT resolve — rc=$RC got='$GOT' stderr='$(head -1 "$TMP/resolve.stderr")'"
fi

# A second ECID-form physical row, differently shaped (trailing "(no DDI)" in
# State, parentheses in the Name) — the resolver must not be thrown by either.
GOT="$(resolve "Shelley's iPad")"; RC=$?
if [[ $RC -eq 0 && "$GOT" == "00008122-0006186214E1801C" ]]; then
  pass "416-A: a second ECID row resolves despite '(no DDI)' state and a parenthesised name"
else
  fail "416-A: the iPad row did not resolve — rc=$RC got='$GOT'"
fi

# ---- 416-B: a UUID-form identifier (36 chars) still resolves ------------------
GOT="$(resolve "LegacyFormPhone")"; RC=$?
if [[ $RC -eq 0 && "$GOT" == "91CBCB90-B313-5B09-A405-E0FE284C9D75" ]]; then
  pass "416-B: the historical UUID-form identifier still resolves"
else
  fail "416-B: the UUID form regressed — rc=$RC got='$GOT'"
fi

# ---- 416-C: a `simulated` row NEVER resolves, even on a name collision -------
# `whoGoesThere-sim` is simulated; asking for it must find nothing rather than
# hand back a phantom. (#333's guard.)
GOT="$(resolve "whoGoesThere-sim")"; RC=$?
if [[ "$GOT" == "D704B375-4077-49A7-98A3-509B73456EBE" ]]; then
  fail "416-C: a SIMULATED row resolved — phantom hardware (#333's guard is gone)"
elif [[ $RC -eq 3 ]]; then
  pass "416-C: a simulated row never resolves (exit 3)"
else
  # A name-substring match on the physical row is acceptable ONLY if what came
  # back is the physical device; anything else is a phantom.
  [[ "$GOT" == "00008150-000E794C3C47801C" ]] \
    && pass "416-C: simulated row rejected; matched the physical row instead" \
    || fail "416-C: unexpected resolution for a simulated name — rc=$RC got='$GOT'"
fi

# ---- 416-D: no matching physical row ⇒ exit 3 + the PRECONDITION message -----
GOT="$(resolve "NoSuchDevice")"; RC=$?
if [[ $RC -eq 3 ]] && grep -q "PRECONDITION: no connected physical device" "$TMP/resolve.stderr"; then
  pass "416-D: an absent device exits 3 with the PRECONDITION message"
else
  fail "416-D: expected exit 3 + PRECONDITION, got rc=$RC stderr='$(head -1 "$TMP/resolve.stderr")'"
fi

# ---- 416-F: a build that cannot run instruments aborts FAST, not at --timeout
# The Release build launches cleanly and streams nothing (its trigger is behind
# `#if DEBUG`). A working run streams `battery:` lines within seconds. This stub
# xcrun drives the whole poll loop: the listing resolves, every container copy
# reports not-found (so no artifact ever appears), and `process launch` either
# stays silent (F1) or emits a battery line (F2).
LOOPBIN="$TMP/loopbin"; mkdir -p "$LOOPBIN"
cat > "$LOOPBIN/xcrun" <<EOF
#!/bin/bash
if [[ "\$*" == *"list devices"* ]]; then cat "$LISTING"; exit 0; fi
if [[ "\$*" == *"copy from"* ]]; then
  echo "Failed to retrieve the file node" >&2; exit 1
fi
if [[ "\$*" == *"process launch"* ]]; then
  [[ -n "\${STUB_EMIT_BATTERY:-}" ]] && echo "battery: START trials=1 cells=1 (#200)"
  sleep 30
  exit 0
fi
exit 90
EOF
chmod +x "$LOOPBIN/xcrun"

run_loop() {  # run_loop <timeout> ; honours STUB_EMIT_BATTERY
  PATH="$LOOPBIN:$PATH" TALARIA_FIRST_OUTPUT_GRACE=1 TALARIA_POLL_INTERVAL=1 \
    "$SUT" --device whoGoesThere --instrument decline --timeout "$1" \
    --out "$TMP/loopruns" > "$TMP/loop.out" 2>&1
}

# 416-F1: silent launch ⇒ exit 4, fast, naming the Release/#if DEBUG hypothesis.
run_loop 600; RC=$?
LOOPLOG="$(ls -t "$TMP/loopruns"/*/run.log 2>/dev/null | head -1)"
if [[ $RC -eq 4 ]]; then
  pass "416-F1: a silent launch aborts with exit 4 instead of burning the timeout"
else
  fail "416-F1: expected exit 4 on a silent launch, got $RC"
fi
if grep -q "RELEASE build" "${LOOPLOG:-/dev/null}" && grep -q "#if DEBUG" "${LOOPLOG:-/dev/null}"; then
  pass "416-F1: the abort names the Release / '#if DEBUG' hypothesis"
else
  fail "416-F1: the abort message does not name the cause — $(tail -2 "${LOOPLOG:-/dev/null}" 2>/dev/null)"
fi
grep -q "ota-stage.sh <branch> Debug" "${LOOPLOG:-/dev/null}" \
  && pass "416-F1: the abort prints the remedy command" \
  || fail "416-F1: the abort does not print the remedy"

# 416-F2: a launch that DOES emit `battery:` must NOT trip the guard. It has no
# artifact either, so it ends as an ordinary timeout — the point is that the
# reason differs.
STUB_EMIT_BATTERY=1 run_loop 3; RC=$?
LOOPLOG="$(ls -t "$TMP/loopruns"/*/run.log 2>/dev/null | head -1)"
if [[ $RC -eq 4 ]]; then
  fail "416-F2: FALSE POSITIVE — a run that streamed 'battery:' was aborted as buildless"
else
  pass "416-F2: a run streaming 'battery:' is not aborted by the guard (rc=$RC)"
fi
grep -q "no instrument output" "${LOOPLOG:-/dev/null}" \
  && fail "416-F2: the guard's message appeared on a run that produced output" \
  || pass "416-F2: the guard stayed silent on a producing run"

# ---- 416-E: preota-subset.sh exits NONZERO when any member failed ------------
# Uses the subset's own documented seams (TALARIA_RUNNER / TALARIA_SUBSET_OUT),
# the same ones preota-subset-test.sh drives.
if [[ -x "$SUBSET" ]]; then
  STUB="$TMP/stub-runner.sh"
  cat > "$STUB" <<'EOF'
#!/bin/bash
NAME=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instrument) NAME="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) shift;;
  esac
done
mkdir -p "$OUT/$NAME"
printf '{"osVersion": "iOS 27.0 (24A5423a)", "instrument": "%s"}\n' "$NAME" > "$OUT/$NAME/latest.json"
[[ -n "${STUB_FAIL_ALL:-}" ]] && exit 1
exit 0
EOF
  chmod +x "$STUB"

  OUT_E="$TMP/out-e"; mkdir -p "$OUT_E"
  STUB_FAIL_ALL=1 TALARIA_RUNNER="$STUB" TALARIA_SUBSET_OUT="$OUT_E" \
    "$SUBSET" > "$TMP/e-allfail.log" 2>&1
  RC=$?
  grep -q "ok=0 failed=5" "$TMP/e-allfail.log" \
    || fail "416-E: fixture did not produce the all-fail case — $(grep 'SUBSET COMPLETE' "$TMP/e-allfail.log" || echo 'no summary')"
  [[ $RC -ne 0 ]] \
    && pass "416-E: a total wipeout (ok=0 failed=5) exits nonzero (rc=$RC)" \
    || fail "416-E: ok=0 failed=5 returned EXIT 0 — a wipeout reported as success"

  OUT_F="$TMP/out-f"; mkdir -p "$OUT_F"
  TALARIA_RUNNER="$STUB" TALARIA_SUBSET_OUT="$OUT_F" \
    "$SUBSET" > "$TMP/e-allok.log" 2>&1
  RC=$?
  [[ $RC -eq 0 ]] \
    && pass "416-E: an all-green subset still exits 0" \
    || fail "416-E: all-green subset exited $RC (must stay 0)"
else
  fail "416-E: preota-subset.sh missing or not executable"
fi

echo
if [[ $FAILURES -eq 0 ]]; then echo "SELF-TEST: PASS"; exit 0; fi
echo "SELF-TEST: FAIL ($FAILURES)"; exit 1
