#!/bin/bash
# lane-gate.sh — the pre-PR gate (OPEN_ITEMS #218).
#
# Runs the two checks a lane must pass before its PR is opened:
#
#   1. the Debug test suite   (units + XCUITest)
#   2. a RELEASE build
#
# Step 2 exists because on 2026-08-01 `main` was found to have been unable to
# build in Release for two days — three promoted instruction clauses were
# declared inside `#if DEBUG` while production read them every turn. Nothing
# caught it: the suite builds Debug, corded device installs build Debug, and an
# external auditor's independent rebuild was `build-for-testing`, also Debug.
# 1461 green tests said nothing about it, and `ota-stage.sh` (Release) would
# have failed at the next archive. A deep verification stack is worthless if it
# is uniform.
#
# THE RULE THIS SCRIPT ENCODES: a check passes only on a POSITIVE marker.
# Absence of "BUILD FAILED" is not success — a build that dies early, a
# toolchain that is missing, or a log that never got written all produce a log
# with no failure marker in it. Every check below greps for the success string
# and treats "no output" as FAIL. That is the same lesson as `grep -c "error:"`
# counting sim runtime noise and `ls-remote | grep || echo absent` reporting a
# branch gone that was never gone: an empty result and a negative result are
# the same bytes, so never infer one from the other.
#
# Usage:
#   scripts/mac/lane-gate.sh              suite + Release build (the gate)
#   scripts/mac/lane-gate.sh --release    Release build only (fast re-check)
#   scripts/mac/lane-gate.sh --suite      suite only
#
# Env overrides:
#   TALARIA_SIM_NAME     simulator to test on (default "iPhone 17 Pro Max")
#   TALARIA_GATE_LOGDIR  where logs land (default a mktemp dir; path is printed)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta4.app/Contents/Developer}"
export DEVELOPER_DIR
SIM_NAME="${TALARIA_SIM_NAME:-iPhone 17 Pro Max}"
LOGDIR="${TALARIA_GATE_LOGDIR:-$(mktemp -d -t talaria-gate)}"
mkdir -p "$LOGDIR"

RUN_SUITE=1
RUN_RELEASE=1
case "${1:-}" in
    --release) RUN_SUITE=0 ;;
    --suite)   RUN_RELEASE=0 ;;
    "")        ;;
    *) echo "usage: $0 [--release|--suite]" >&2; exit 2 ;;
esac

FAIL=0
ok()  { echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

# Grep a log for a REQUIRED success marker. Empty or missing log => FAIL.
# This is the whole point of the script; do not "simplify" it into a
# `! grep FAILED` check.
require() {   # require <logfile> <pattern> <label>
    local log="$1" pat="$2" label="$3"
    if [[ ! -s "$log" ]]; then
        bad "$label — log is empty or missing ($log)"
        return 1
    fi
    if grep -qE "$pat" "$log"; then
        ok "$label"
        return 0
    fi
    bad "$label — success marker not found in $log"
    return 1
}

echo "== Talaria lane gate =="
echo "   repo:      $REPO_ROOT  ($(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD))"
echo "   toolchain: $DEVELOPER_DIR"
echo "   logs:      $LOGDIR"
echo

# ---------------------------------------------------------------- preflight
echo "-- preflight"
if [[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    ok "xcodebuild present ($("$DEVELOPER_DIR/usr/bin/xcodebuild" -version | head -1))"
else
    bad "xcodebuild not found under DEVELOPER_DIR — set DEVELOPER_DIR to the beta toolchain"
    echo; echo "GATE: FAIL (cannot run)"; exit 1
fi

SIM_UDID="$(xcrun simctl list devices available 2>/dev/null \
    | grep -F "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [[ -n "$SIM_UDID" ]]; then
    ok "simulator \"$SIM_NAME\" = $SIM_UDID"
else
    bad "no available simulator named \"$SIM_NAME\" (set TALARIA_SIM_NAME)"
    echo; echo "GATE: FAIL (cannot run)"; exit 1
fi

# xcodegen drift: explicit source listings mean a added/removed Swift file that
# never got regenerated builds fine locally and breaks for the next person.
if command -v xcodegen >/dev/null 2>&1; then
    if git diff --quiet -- Talaria.xcodeproj/project.pbxproj; then
        ok "project.pbxproj has no uncommitted drift"
    else
        echo "  WARN  project.pbxproj is modified — if you added/removed Swift files, commit the regen"
    fi
fi
echo

# ------------------------------------------------------------------- suite
if (( RUN_SUITE )); then
    echo "-- Debug suite (units + XCUITest) on $SIM_NAME"
    SUITE_LOG="$LOGDIR/suite.log"
    "$DEVELOPER_DIR/usr/bin/xcodebuild" test \
        -project Talaria.xcodeproj -scheme Talaria \
        -destination "platform=iOS Simulator,id=$SIM_UDID" \
        > "$SUITE_LOG" 2>&1
    # NOTE: exit status is recorded but NOT trusted on its own — see require().
    echo "   xcodebuild exit=$?"

    require "$SUITE_LOG" 'Test run with [0-9]+ tests in [0-9]+ suites passed' \
            "Swift Testing suite passed" \
        && echo "        $(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites passed' "$SUITE_LOG" | tail -1)"

    # XCUITest reports separately; reading only one line badly undercounts.
    if grep -qE 'Executed [0-9]+ tests?, with 0 failures' "$SUITE_LOG"; then
        ok "XCUITest passed — $(grep -oE 'Executed [0-9]+ tests?, with 0 failures' "$SUITE_LOG" | tail -1)"
    else
        bad "XCUITest — no 'Executed N tests, with 0 failures' line in $SUITE_LOG"
    fi

    # A test count that did not move after editing tests is the stale-binary
    # signature: build-for-testing can silently re-run the OLD .xctest.
    echo "   NOTE: if this lane added or renamed tests, confirm the count MOVED."
    echo "         If it did not: rm -rf <DerivedData>/Build/Intermediates.noindex and re-run."
    echo
fi

# ----------------------------------------------------------------- release
if (( RUN_RELEASE )); then
    echo "-- Release build (the #218 check)"
    REL_LOG="$LOGDIR/release.log"
    "$DEVELOPER_DIR/usr/bin/xcodebuild" \
        -project Talaria.xcodeproj -scheme Talaria \
        -configuration Release -destination 'generic/platform=iOS Simulator' \
        build CODE_SIGNING_ALLOWED=NO \
        > "$REL_LOG" 2>&1
    echo "   xcodebuild exit=$?"

    require "$REL_LOG" '\*\* BUILD SUCCEEDED \*\*|BUILD SUCCEEDED' "Release build succeeded"

    # Report compile errors explicitly rather than leaving them to be inferred.
    ERRS="$(grep -cE '\.swift:[0-9]+:[0-9]+: error:' "$REL_LOG")"
    if [[ "$ERRS" == "0" ]]; then
        ok "no Swift compile errors in Release"
    else
        bad "$ERRS Swift compile error line(s) in Release:"
        grep -E '\.swift:[0-9]+:[0-9]+: error:' "$REL_LOG" | sort -u | sed 's/^/        /'
    fi
    echo
fi

# ----------------------------------------------------------------- verdict
if (( FAIL == 0 )); then
    echo "GATE: PASS — logs in $LOGDIR"
    exit 0
fi
echo "GATE: FAIL ($FAIL check(s)) — logs in $LOGDIR"
exit 1
