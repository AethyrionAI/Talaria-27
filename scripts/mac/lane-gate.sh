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
# ...AND THE FIRST VERSION OF THIS SCRIPT BROKE ITS OWN RULE. On its first real
# run against main it printed GATE: PASS while four UI tests had failed and
# xcodebuild had exited 65. Three separate mistakes, all worth keeping in view:
#
#   1. The XCUITest marker was `Executed N tests, with 0 failures` — and **zero
#      is a number**. An empty sub-suite prints "Executed 0 tests, with 0
#      failures", which matched. A "positive marker" that a no-op satisfies is
#      not a positive marker. Counts are now required to be > 0.
#   2. It grepped for a marker that appears MANY times in a test log and passed
#      on any one of them, instead of the single authoritative verdict line
#      (`** TEST SUCCEEDED **` / `** TEST FAILED **`).
#   3. It recorded xcodebuild's exit status and deliberately did not act on it.
#      "Do not trust exit status ALONE" is right; "ignore it" is not. A nonzero
#      exit is now disqualifying on its own.
#
# So: success requires the authoritative marker AND a zero exit AND a nonzero
# count, and any explicit failure marker fails the check outright.
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

# FAIL if an explicit failure marker is present, whatever else the log says.
# Success markers and failure markers both appear in a test log; the failure
# one wins.
refute() {   # refute <logfile> <pattern> <label>
    local log="$1" pat="$2" label="$3"
    if grep -qE "$pat" "$log"; then
        bad "$label"
        return 1
    fi
    return 0
}

# A count that must be greater than zero. `Executed 0 tests, with 0 failures`
# is why this exists — see the header.
require_count() {   # require_count <logfile> <extract-regex> <label>
    local log="$1" pat="$2" label="$3" n
    # MAX, not first: a log legitimately contains an empty sub-suite line
    # ("Executed 0 tests") alongside the real one, and taking the first would
    # false-FAIL a good run. Safe because the pattern itself requires
    # "with 0 failures" — a run with failures matches nothing here and falls
    # through to the no-count-line FAIL below.
    n="$(grep -oE "$pat" "$log" | grep -oE '[0-9]+' | sort -rn | head -1)"
    if [[ -z "$n" ]]; then
        bad "$label — no count line found in $log"
        return 1
    fi
    if (( n > 0 )); then
        ok "$label — $n"
        return 0
    fi
    bad "$label — count is ZERO, which is not a pass"
    return 1
}

# Non-zero xcodebuild exit is disqualifying. Not sufficient on its own to
# declare success, but sufficient to declare failure.
require_exit0() {   # require_exit0 <status> <label>
    if (( $1 == 0 )); then return 0; fi
    bad "$2 — xcodebuild exited $1"
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
    SUITE_STATUS=$?
    echo "   xcodebuild exit=$SUITE_STATUS"

    # The authoritative verdict, and the one that overrides everything else in
    # the log. Both directions are checked explicitly.
    require_exit0 "$SUITE_STATUS" "Test run"
    refute  "$SUITE_LOG" '\*\* TEST FAILED \*\*|\*\* TEST BUILD FAILED \*\*' \
            "Test run reported ** TEST FAILED **"
    require "$SUITE_LOG" '\*\* TEST SUCCEEDED \*\*' "Test run reported TEST SUCCEEDED"

    # Swift Testing and XCUITest report separately; reading either alone
    # undercounts. Both counts must be greater than zero.
    require_count "$SUITE_LOG" 'Test run with [0-9]+ tests in [0-9]+ suites passed' \
                  "Swift Testing tests run"
    require_count "$SUITE_LOG" 'Executed [0-9]+ tests?, with 0 failures' \
                  "XCUITest tests run"

    # Name names when something failed — the whole point is not making the
    # reader go log-diving.
    if grep -q "^Failing tests:" "$SUITE_LOG"; then
        echo "   failing tests:"
        sed -n '/^Failing tests:/,/^$/p' "$SUITE_LOG" | sed '1d;/^$/d' | sed 's/^/        /'
        # Distinguish a product failure from a harness hiccup. A real failure
        # names an assertion and a file:line; the XCUITest runner dying or
        # restarting marks every UI test failed with NO assertion text at all
        # (observed 2026-08-01: testLaunch passed, restarted, then the suite
        # reported zero tests and four failures).
        if grep -qE '\.swift:[0-9]+: error:' "$SUITE_LOG"; then
            echo "        ^ assertion text present — treat as a REAL failure."
        else
            echo "        ^ NO assertion text — likely an XCUITest harness flake"
            echo "          (runner lost/restarted). Re-run ONCE and RECORD both"
            echo "          runs in OPEN_ITEMS #164. Do not re-run until green"
            echo "          and report only the green one."
        fi
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
    REL_STATUS=$?
    echo "   xcodebuild exit=$REL_STATUS"

    require_exit0 "$REL_STATUS" "Release build"
    refute  "$REL_LOG" '\*\* BUILD FAILED \*\*' "Release build reported ** BUILD FAILED **"
    require "$REL_LOG" '\*\* BUILD SUCCEEDED \*\*' "Release build succeeded"

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
