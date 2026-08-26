#!/bin/bash
# lane-gate.sh — the pre-PR gate.
#
# Born of OPEN_ITEMS-ARCHIVE.md item 218 (closed 2026-08-04). That is a
# PROVENANCE citation into the archive, where entries are kept verbatim and
# never renumbered, so it stays resolvable. It is deliberately the only item
# number left in this file, and it is in a comment: no number appears in text
# this script PRINTS. A shell script cannot keep a tracker number live, and
# every number this gate used to print at the reader had been closed for days
# by the time someone followed one (see item 300).
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

# Both resolved to absolute paths BEFORE the cd — `dirname "$0"` afterwards is
# relative to wherever we landed, so invoking this as ./lane-gate.sh from inside
# scripts/mac would look for the library in the repo root and not find it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# The failure-advice classifier. Sourced, not inlined, so that it can be tested
# in a second instead of behind a full suite run — `lane-gate-classify-test.sh`
# drives it over recorded fixtures. A missing library is fatal rather than
# silent: losing a check quietly is the failure mode this whole script exists
# to prevent.
GATE_CLASSIFY_LIB="$SCRIPT_DIR/lane-gate-classify.sh"
if [[ ! -r "$GATE_CLASSIFY_LIB" ]]; then
    echo "lane-gate: cannot read $GATE_CLASSIFY_LIB" >&2
    echo "GATE: FAIL (cannot run)" >&2
    exit 1
fi
# shellcheck source=./lane-gate-classify.sh
. "$GATE_CLASSIFY_LIB"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta6.app/Contents/Developer}"
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
    #
    # MAX is taken over EVERY number on the matched line, not just the test
    # count — so for "N tests in M suites" it can return the suite count when
    # suites > tests. That is harmless because the value is only ever used for
    # a >0 check and is reported, never compared to an expected total; if a
    # future caller compares it to a number, extract the capture group first.
    # (Noted by the external audit, 2026-08-02.)
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

# TCC, granted HERE and for the UDID resolved above.
#
# BatteryReapEventKitProbeTests calls requestFullAccessToEvents(). With a
# DENIED record it fails visibly, which is what its docstring promises. On a
# simulator with NO RECORD AT ALL the call blocks forever: the suite stalls
# mid-run with no failure, no marker and no verdict, and the only tell is a log
# that has stopped growing. That is this gate's founding sin — "absence of a
# failure marker is not success" — arriving as a hang instead of a pass.
#
# It was documented as an operator step ("grant before every run") and that was
# not enough, twice. On 2026-08-19 a run was started with TALARIA_SIM_NAME set
# to one pool member while the grants had been issued against another's UDID:
# the instruction was followed in form, the wrong device got the grants, and
# 47 minutes went into a suite that had been parked since minute two. An
# operator pairing a NAME with a UDID by hand is a step that can be done wrong
# silently — so the script, which already resolved the UDID, now does it.
#
# Boot first: `simctl privacy` errors on a Shutdown device ("Unable to lookup
# in current state"). And this FAILS THE GATE rather than warning, because a
# gate that cannot arrange the conditions for its own suite must say so at
# second three, not hang at minute two.
#
# The bundle id is READ FROM project.yml, not hardcoded here, and that is not
# tidiness. Probed 2026-08-19: `simctl privacy grant` accepts an unknown bundle
# id and exits 0 — it writes the record and never checks that anything owns it.
# So a renamed or mistyped id would grant "successfully" against nothing and
# the suite would hang exactly as before, with a PASS line above it saying the
# opposite. A grant whose failure mode is a green marker is worse than no grant.
TCC_BUNDLE_ID="$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\([A-Za-z0-9._-]*\) *$/\1/p' \
    "$REPO_ROOT/project.yml" | head -1)"
if [[ -z "$TCC_BUNDLE_ID" ]]; then
    bad "could not read PRODUCT_BUNDLE_IDENTIFIER from project.yml — TCC would be granted to nothing"
    echo; echo "GATE: FAIL (cannot run)"; exit 1
fi
if ! xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1; then
    bad "could not boot simulator $SIM_UDID — TCC cannot be granted and the suite would hang"
    echo; echo "GATE: FAIL (cannot run)"; exit 1
fi

# WHICH RUNTIME DID THIS GATE ACTUALLY MEASURE? Reported, never checked — the
# gate has no business failing a lane over the OS it was handed. But it must
# SAY it, because a verdict with no runtime on it is read as "green on the
# user's phone" and that has not been true for most of this project's life.
#
# The naive answers are both wrong, and that is the whole reason this is here:
#
#   * `simctl list devices` reports the runtime IDENTIFIER
#     (com.apple.CoreSimulator.SimRuntime.iOS-27-0). Three DIFFERENT builds on
#     this Mac share that one identifier, so the listing cannot tell them
#     apart. A gate that printed it would look precise and say nothing.
#   * the device's own device.plist records `runtimePolicy: System`, meaning it
#     does not pin a build at all — it FOLLOWS the system runtime match. So the
#     simulator under this gate can change OS between two runs with no commit,
#     no flag, and nothing in this repo to show for it. That has already
#     happened once, silently, on the day a newer runtime landed.
#
# So ask the booted OS itself. `sw_vers` does not exist inside an iOS runtime
# (probed: NSPOSIXErrorDomain code=2), but the simulator exports its own build
# into the device environment, and that value comes from the runtime that is
# actually running rather than from a policy that describes what should be.
# Boot first — this necessarily sits after the bootstatus above.
SIM_RUNTIME_BUILD="$(xcrun simctl getenv "$SIM_UDID" SIMULATOR_RUNTIME_BUILD_VERSION 2>/dev/null | tr -d '[:space:]')"
SIM_RUNTIME_VERSION="$(xcrun simctl getenv "$SIM_UDID" SIMULATOR_RUNTIME_VERSION 2>/dev/null | tr -d '[:space:]')"
: "${SIM_RUNTIME_BUILD:=UNKNOWN}"
: "${SIM_RUNTIME_VERSION:=?}"
if [[ "$SIM_RUNTIME_BUILD" == "UNKNOWN" ]]; then
    # Not a FAIL: an unreadable build does not make the suite less valid. But
    # it is not silence either — the point of the line is that the reader can
    # never assume a runtime, and "UNKNOWN" says that better than omission.
    echo "  NOTE  runtime: UNKNOWN on \"$SIM_NAME\" — could not read the booted"
    echo "        runtime's build. Do not read this run's verdict as applying"
    echo "        to any particular OS."
else
    ok "runtime: iOS $SIM_RUNTIME_VERSION ($SIM_RUNTIME_BUILD) on \"$SIM_NAME\""
fi
echo "        THIS GATE IS GREEN ON THAT RUNTIME, not on the phone's. The two are"
echo "        different builds unless someone has checked today, and this"
echo "        simulator follows the system runtime match, so it can advance"
echo "        between runs on its own. A battery rate or a behavioural claim"
echo "        carries the build it was measured on or it is ambiguous."

TCC_FAILED=""
for service in calendar reminders; do
    xcrun simctl privacy "$SIM_UDID" grant "$service" "$TCC_BUNDLE_ID" >/dev/null 2>&1 \
        || TCC_FAILED="$TCC_FAILED $service"
done
if [[ -z "$TCC_FAILED" ]]; then
    ok "TCC granted on $SIM_NAME (calendar, reminders) — the EventKit probe cannot hang"
else
    bad "TCC grant FAILED for:$TCC_FAILED — the EventKit probe would hang, not fail"
    echo; echo "GATE: FAIL (cannot run)"; exit 1
fi

# The failure-advice classifier's own self-test. About a second, and it is the
# only thing standing between a reworded tracker header and advice that points
# nowhere — the advice cites items by SEARCH STRING now, and a search string
# that matches nothing is the same defect as the dead item numbers it replaced,
# just quieter. Running it here means a rotted pointer surfaces in preflight
# rather than five days later in someone's failed run.
if [[ -x "$SCRIPT_DIR/lane-gate-classify-test.sh" ]]; then
    if CLASSIFY_OUT="$("$SCRIPT_DIR/lane-gate-classify-test.sh" 2>&1)"; then
        ok "failure-advice classifier — $(printf '%s' "$CLASSIFY_OUT" | tail -1)"
    else
        bad "failure-advice classifier SELF-TEST FAILED — the gate's advice cannot be trusted"
        printf '%s\n' "$CLASSIFY_OUT" | grep -E '^  FAIL|^CLASSIFIER' | sed 's/^/        /'
    fi
else
    bad "failure-advice classifier self-test missing or not executable"
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

    # SKIPS. A skipped test is not a passing test, and until 2026-08-02 this
    # gate could not see one. Measured then: `CondenserFidelityTests` printed
    # "✔ Suite … passed" while BOTH of its model-path tests were skipped for
    # want of Apple Intelligence hardware, and the gate reported only
    # "Swift Testing tests run — 1497" with no hint that two of its subjects
    # were never exercised. That is the Release-build lesson one level up:
    # a positive marker that a no-op satisfies is not a positive marker, and
    # "passed" over an empty suite is exactly that no-op.
    #
    # Deliberately a REPORT, not a FAIL: these particular skips are honest
    # (the hardware genuinely is absent on a sim run) and a live tracker item
    # owns making them run on device. What was wrong was that they were
    # INVISIBLE. A number the reader can see is the fix; if it ever moves,
    # that is a finding.
    SKIPPED=$(grep -cE '➜ Test .* skipped' "$SUITE_LOG" 2>/dev/null || true)
    SKIPPED=${SKIPPED:-0}
    if (( SKIPPED > 0 )); then
        echo "  NOTE  $SKIPPED test(s) SKIPPED — not run, not passed:"
        # BOTH name forms. A `@Test("Display name")` skip prints the quoted
        # string; a plain `@Test func foo()` skip prints the bare identifier.
        # Matching only the quoted form made the LIST disagree with the COUNT
        # above — measured 2026-08-10: "4 test(s) SKIPPED" over a list of two,
        # with the two invisible ones being the interesting ones (a lane's
        # deliberate skips, not the known hardware pair). A count the listing
        # cannot account for is the same defect as advice that names the wrong
        # cause: it reads as complete and is not.
        grep -oE '➜ Test ("[^"]+"|[A-Za-z_][A-Za-z0-9_]*\([^)]*\)) skipped: "[^"]+"' "$SUITE_LOG" \
            | sed 's/➜ Test /        /' | sort -u
        echo "        A skip is not a pass. The known-permanent pair is"
        echo "        CondenserFidelityTests (needs Apple Intelligence hardware,"
        echo "        so it can never run on a simulator). EVERY OTHER skip is a"
        echo "        lane's deliberate choice and should name a tracker item in"
        echo "        its own skip reason — if one does not, that is a finding."
        echo "            grep -n CondenserFidelityTests OPEN_ITEMS-ARCHIVE.md"
    else
        ok "no skipped tests"
    fi

    # Name names when something failed — the whole point is not making the
    # reader go log-diving. The classifier lives in lane-gate-classify.sh so it
    # can be exercised without a twenty-minute suite run; see OPEN_ITEMS 300 for
    # why its predecessor had to be replaced (it recognised only the XCTest
    # diagnostic shape, so it announced every Swift Testing failure in the
    # project as a harness flake and pointed the reader at a closed item).
    if grep -q "^Failing tests:" "$SUITE_LOG"; then
        echo "   failing tests:"
        gate_print_failure_advice "$SUITE_LOG"
    fi

    # A test count that did not move after editing tests is the stale-binary
    # signature: build-for-testing can silently re-run the OLD .xctest.
    echo "   NOTE: if this lane added or renamed tests, confirm the count MOVED."
    echo "         If it did not: rm -rf <DerivedData>/Build/Intermediates.noindex and re-run."
    echo
fi

# ----------------------------------------------------------------- release
if (( RUN_RELEASE )); then
    echo "-- Release build (the check a Debug-only stack cannot make)"
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
#
# The runtime rides the VERDICT line, not only the preflight one. A verdict is
# the line that gets copied into a tracker entry, a PR body and a handoff; the
# preflight scrolls away. "GATE: PASS" quoted with no runtime is exactly the
# ambiguity this is meant to end, so the two travel together or the fix does
# not work.
if (( FAIL == 0 )); then
    echo "GATE: PASS on $SIM_RUNTIME_BUILD — logs in $LOGDIR"
    exit 0
fi
echo "GATE: FAIL ($FAIL check(s)) on $SIM_RUNTIME_BUILD — logs in $LOGDIR"
exit 1
