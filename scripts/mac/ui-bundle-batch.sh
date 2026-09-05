#!/bin/bash
# ui-bundle-batch.sh — run the XCUITest bundle N times over IDENTICAL BYTES and
# write down what happened each time.
#
# THIS IS AN INSTRUMENT, NOT A GATE. It never decides anything: reds do not
# make it exit nonzero, because a batch whose purpose is measuring a flake rate
# would be useless if it stopped at the first red. Only a failure to RUN the
# batch — no simulator, no TCC, a build that did not build — is an error here.
#
# WHY IT EXISTS. One XCUITest journey (and its two siblings) fails roughly one
# run in ten on a tap the runner reports as synthesized and the app never
# receives. "Roughly" is the problem: every number anyone has for it comes from
# gate runs that were not measuring it, taken across different bytes, different
# machine loads and at least three OS builds. A rate you cannot cite the
# denominator for is an anecdote. This produces the denominator.
#
# THE ONE THING THAT MAKES THE NUMBER MEAN ANYTHING: `build-for-testing` runs
# ONCE, and every trial after it is `test-without-building` against that same
# product. So the usual stale-binary hazard — `test-without-building` happily
# re-running an OLD .xctest and reporting a green suite at the old count — is
# not a hazard WITHIN a batch; it is the design. Identical bytes is the
# controlled variable. It IS still a hazard BETWEEN batches: a batch measures
# the product built at its own start, so never compare two batches without
# checking they were built from the same commit.
#
# Usage:
#   scripts/mac/ui-bundle-batch.sh <N>
#   scripts/mac/ui-bundle-batch.sh --self-test   # classify two recorded
#                                                 # fixtures; no build, no sim
#
# Env:
#   TALARIA_SIM_NAME      simulator to run on (default "CC-lane-2")
#   TALARIA_BATCH_LOGDIR  where logs land (default a mktemp dir; path printed)
#   UITEST_TAP_STRATEGY   optional; forwarded to the test process as
#                         TEST_RUNNER_UITEST_TAP_STRATEGY (xcodebuild passes
#                         TEST_RUNNER_-prefixed variables through to the test
#                         runner). Accepted: "element" (the default behaviour)
#                         or "coordinate". An unrecognised value is REFUSED
#                         rather than forwarded: the test side falls back to
#                         its default when it does not recognise a value, so a
#                         typo would produce an artifact labelled with an arm
#                         it did not run — a mislabelled measurement is worse
#                         than a refused one. Whichever arm is selected, it is
#                         WITNESSED in trial 1's own diagnostics before the
#                         batch continues (see "the arm WITNESS" below); an
#                         unwitnessed arm ABORTS the batch.
#
# Output, all under the log directory:
#   run-NN.log          the full xcodebuild log for trial NN
#   run-NN.hittap.txt   every HITTAP / XFLAKE diagnostic line from that trial
#   ledger.tsv          one row per trial (plus a commented header block)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# The gate's classifier library, reused rather than reimplemented. The
# per-test ledger and the failing-test names are the same questions the gate
# asks, and a second implementation of either is a second thing to be wrong.
GATE_CLASSIFY_LIB="$SCRIPT_DIR/lane-gate-classify.sh"
if [[ ! -r "$GATE_CLASSIFY_LIB" ]]; then
    echo "ui-bundle-batch: cannot read $GATE_CLASSIFY_LIB" >&2
    exit 1
fi
# shellcheck source=./lane-gate-classify.sh
. "$GATE_CLASSIFY_LIB"

# ---------------------------------------------------------------------------
# THE PASS/FAIL CRITERION for one trial. Factored into a function so the
# self-test below can exercise it directly against a recorded fixture — no
# xcodebuild, no simulator — instead of only ever running live inside the
# trial loop where a wrong verdict would just look like a red run.
#
# Same three checks the trial loop has always applied: a zero exit, a
# positive success marker with no failure marker present, and a complete
# non-zero XCUITest ledger (a count is not "ran clean" until it is compared
# against itself: started>0, failed==0, passed==started).
#
# 2026-09-05 (#219m): the marker check now accepts EITHER
# `** TEST SUCCEEDED **` (what `xcodebuild test` prints) OR
# `** TEST EXECUTE SUCCEEDED **` (what `test-without-building` prints — and
# `test-without-building`, not `test`, is what the trial loop below actually
# runs). Before this fix the regex matched only the former, so this script
# labelled FAIL every single trial regardless of the underlying suite result
# — 30/30 on 2026-09-04's DET-C/E pair, all green (18/18, exit 0) and all
# marked FAIL. See OPEN_ITEMS #219.
ui_batch_classify_result() {   # ui_batch_classify_result <logfile> <exit-status>
    local log="$1" exit_status="$2" started passed failed
    read -r started passed failed <<<"$(gate_xcuitest_ledger "$log")"
    if (( exit_status == 0 )) \
        && grep -qE '\*\* TEST (SUCCEEDED|EXECUTE SUCCEEDED) \*\*' "$log" \
        && ! grep -qE '\*\* TEST FAILED \*\*|\*\* TEST BUILD FAILED \*\*' "$log" \
        && (( started > 0 && failed == 0 && passed == started )); then
        printf 'PASS'
    else
        printf 'FAIL'
    fi
}

if [[ "${1:-}" == "--self-test" ]]; then
    SELFTEST_DIR="$(mktemp -d -t talaria-uibatch-selftest)"
    trap 'rm -rf "$SELFTEST_DIR"' EXIT
    ST_PASS=0; ST_FAIL=0

    st_check() {   # st_check <label> <expected> <actual>
        if [[ "$2" == "$3" ]]; then
            ST_PASS=$((ST_PASS+1)); printf '  PASS  %s\n' "$1"
        else
            ST_FAIL=$((ST_FAIL+1)); printf '  FAIL  %s — expected "%s", got "%s"\n' "$1" "$2" "$3"
        fi
    }

    # Fixture: a recorded, byte-exact tail (lines 1657-1705) of a REAL
    # test-without-building log — the DET-C run that motivated this fix,
    # planning/reports/2026-09-04-219-det-ce/det-c/ledger.tsv's run-01, kept
    # at /Users/owenjones/talaria-batches/det-ce-20260904/det-c/run-01.log on
    # this Mac. Two XCUITest cases (started+passed, 0 failed), the suite
    # summaries including `Executed 18 tests` and `Test Suite 'All tests'
    # passed`, and the `** TEST EXECUTE SUCCEEDED **` marker. Checked for
    # anything sensitive before recording here: none — a local DerivedData
    # path and timestamps, no secrets, no tokens.
    cat > "$SELFTEST_DIR/execute-succeeded.log" <<'FIXTURE_EOF'
Test Suite 'TalariaUITestsLaunchTests' started at 2026-09-04 18:16:41.311.
Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' started.
    t =     0.00s Setting appearance mode to Light
    t =     0.04s     Wait for org.aethyrion.talaria27 to idle
    t =     0.17s Start Test at 2026-09-04 18:16:41.484
    t =     0.18s Set Up
    t =     0.18s Open org.aethyrion.talaria27
    t =     0.18s     Launch org.aethyrion.talaria27
    t =     0.18s         Terminate org.aethyrion.talaria27:82783
2026-09-04 18:16:42.542 xcodebuild[81763:16635469] [MT] IDELaunchParametersSnapshot: debugger version lookup failed for path '<nil>': noURL
2026-09-04 18:16:42.542 xcodebuild[81763:16635469] [MT] IDELaunchParametersSnapshot: no debugger version
    t =     1.44s         Setting up automation session
    t =     3.87s         Wait for org.aethyrion.talaria27 to idle
    t =     5.98s Find the Target Application 'org.aethyrion.talaria27'
    t =     6.16s Added attachment named 'Launch Screen'
    t =     6.16s Tear Down
Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' passed (6.375 seconds).
Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' started.
    t =     0.00s Setting appearance mode to Dark
    t =     0.06s     Wait for org.aethyrion.talaria27 to idle
    t =     0.17s Start Test at 2026-09-04 18:16:47.854
    t =     0.19s Set Up
    t =     0.19s Open org.aethyrion.talaria27
    t =     0.19s     Launch org.aethyrion.talaria27
    t =     0.19s         Terminate org.aethyrion.talaria27:82799
2026-09-04 18:16:48.914 xcodebuild[81763:16635469] [MT] IDELaunchParametersSnapshot: debugger version lookup failed for path '<nil>': noURL
2026-09-04 18:16:48.914 xcodebuild[81763:16635469] [MT] IDELaunchParametersSnapshot: no debugger version
    t =     1.43s         Setting up automation session
    t =     3.90s         Wait for org.aethyrion.talaria27 to idle
    t =     5.91s Find the Target Application 'org.aethyrion.talaria27'
    t =     6.09s Added attachment named 'Launch Screen'
    t =     6.09s Tear Down
Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' passed (6.331 seconds).
Test Suite 'TalariaUITestsLaunchTests' passed at 2026-09-04 18:16:54.018.
	 Executed 2 tests, with 0 failures (0 unexpected) in 12.706 (12.707) seconds
Test Suite 'TalariaUITests.xctest' passed at 2026-09-04 18:16:54.019.
	 Executed 18 tests, with 0 failures (0 unexpected) in 342.222 (342.245) seconds
Test Suite 'All tests' passed at 2026-09-04 18:16:54.019.
	 Executed 18 tests, with 0 failures (0 unexpected) in 342.222 (342.247) seconds
2026-09-04 18:16:54.397 xcodebuild[81763:16635469] [MT] IDETestOperationsObserverDebug: 356.420 elapsed -- Testing started completed.
2026-09-04 18:16:54.397 xcodebuild[81763:16635469] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-09-04 18:16:54.397 xcodebuild[81763:16635469] [MT] IDETestOperationsObserverDebug: 356.420 sec, +356.420 sec -- end

Test session results, code coverage, and logs:
	/Users/owenjones/Library/Developer/Xcode/DerivedData/Talaria-gzpowyfsuofejnbsytskngrskzkm/Logs/Test/Test-Talaria-2026.09.04_18-10-57--0500.xcresult

** TEST EXECUTE SUCCEEDED **

Testing started
FIXTURE_EOF

    # Negative control: the identical fixture with the marker line removed.
    # If the criterion cannot fail this, it cannot fail anything — a check
    # that can only say yes is not a check.
    grep -v '^\*\* TEST EXECUTE SUCCEEDED \*\*$' "$SELFTEST_DIR/execute-succeeded.log" \
        > "$SELFTEST_DIR/no-marker.log"

    st_check "test-without-building's own marker classifies PASS" \
             "PASS" "$(ui_batch_classify_result "$SELFTEST_DIR/execute-succeeded.log" 0)"
    st_check "the same log with the marker line removed classifies FAIL" \
             "FAIL" "$(ui_batch_classify_result "$SELFTEST_DIR/no-marker.log" 0)"
    st_check "a nonzero exit still FAILs even with the marker present" \
             "FAIL" "$(ui_batch_classify_result "$SELFTEST_DIR/execute-succeeded.log" 1)"

    echo
    if (( ST_FAIL == 0 )); then
        echo "UI-BUNDLE-BATCH SELF-TEST: PASS ($ST_PASS checks)"
        exit 0
    fi
    echo "UI-BUNDLE-BATCH SELF-TEST: FAIL ($ST_FAIL of $((ST_PASS+ST_FAIL)) checks)"
    exit 1
fi

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta6.app/Contents/Developer}"
export DEVELOPER_DIR
SIM_NAME="${TALARIA_SIM_NAME:-CC-lane-2}"
TAP_STRATEGY="${UITEST_TAP_STRATEGY:-}"

N="${1:-}"
if ! [[ "$N" =~ ^[0-9]+$ ]] || (( N < 1 )); then
    echo "usage: $0 <N>   (N = number of trials, a positive integer)" >&2
    echo "       $0 --self-test" >&2
    exit 2
fi

if [[ -n "$TAP_STRATEGY" && "$TAP_STRATEGY" != "element" && "$TAP_STRATEGY" != "coordinate" ]]; then
    echo "ui-bundle-batch: UITEST_TAP_STRATEGY=\"$TAP_STRATEGY\" is not one of: element, coordinate" >&2
    echo "  Refusing rather than forwarding it. The test side falls back to its default" >&2
    echo "  on a value it does not know, so this batch would be labelled with an arm it" >&2
    echo "  never ran." >&2
    exit 2
fi

# WHICH `via=` TOKEN THE HELPER WILL PRINT for the arm above. The test side
# resolves "coordinate" to `.coordinateAfterTimeout` and everything else —
# including unset — to `.elementTap`, then prints the resolved case name. The
# baseline is witnessed exactly as the coordinate arm is, so a mislabel cannot
# happen in either direction: an inherited TEST_RUNNER_UITEST_TAP_STRATEGY from
# the calling shell would otherwise silently turn an "unset" batch into a
# coordinate one.
if [[ "$TAP_STRATEGY" == "coordinate" ]]; then
    EXPECT_VIA="coordinateAfterTimeout"
else
    EXPECT_VIA="elementTap"
fi

# ------------------------------------------------- the START CHATTING site
#
# READ THIS BEFORE CHANGING ANY PATTERN BELOW. Every one is copied from
# TalariaUITests/Support/HittableTap.swift and TalariaUITests/AppTemplateUITests.swift.
# A grep keyed on a string the helper cannot emit is a check that always fails,
# and the next operator either chases a phantom or learns to skip the step. The
# four shapes that matter, verbatim from a real run:
#
#   HITTAP tapped connectHostWizard.startChatting via=elementTap polledFor=0.82s polls=0 budget=10.0s
#   HITTAP centre connectHostWizard.startChatting point=(210.0, 537.0) strategy=elementTap timeout=10.0s
#   HITTAP fallback connectHostWizard.startChatting via=elementTap under=19
#   HITTAP post outcome=tappedAfterTimeout(via: elementTap) wizardUp=true composerIn5s=false wizardUpAfter=true
#
# AND THE TRAP THAT MAKES THE OBVIOUS GREP USELESS. Two DEBUG fixture tests tap
# the SAME button, and they PIN their arms in the source — one `.elementTap`,
# one `.coordinateAfterTimeout` — so every run emits one `fallback … via=elementTap`
# line and one `fallback … via=coordinateAfterTimeout` line whatever this batch
# set. A witness that greps `via=<arm>` alone therefore matches in both
# directions and can never say no; a "timed out" column that counts `fallback`
# lines can never read 0. Both would be instruments that cannot fail.
#
# What separates production from the fixtures is the BUDGET. The fixtures pass
# `timeout: 3` deliberately (they are about the path, not the budget);
# `completeConnect` — the one site this A/B varies, and the one the flake lives
# at — passes `timeout: 10`. So every pattern below carries that number, and
# `HITTAP post` is used for the timeout tally because only `completeConnect`
# emits it at all.
#
# If the site's budget is ever changed, this batch ABORTS on its witness rather
# than mislabelling a run — the safe direction — and SITE_BUDGET is what to
# update with it.
SITE_BUDGET="10.0"
SITE_BUDGET_RE="${SITE_BUDGET//./\\.}"
SITE_LABEL='connectHostWizard\.startChatting'

# The arm ARRIVED at the site this batch varies: a production-site line, on
# either outcome, carrying it. BOTH outcomes are accepted because trial 1 may
# itself be the flake, and aborting a batch on the very outcome it exists to
# count would be absurd.
count_arm_witness() {   # count_arm_witness <hittap-file> <via-token>
    local n
    n="$(grep -cE "HITTAP tapped $SITE_LABEL via=$2 .*budget=${SITE_BUDGET_RE}s|HITTAP centre $SITE_LABEL .*strategy=$2 timeout=${SITE_BUDGET_RE}s" "$1" 2>/dev/null)"
    printf '%s' "${n:-0}"
}

# The three START CHATTING columns, so the ledger answers "was this run's tap
# clean, late, or lost?" without anyone grepping. `polls` counts 0.25s waits,
# so `polls=0` is "hittable on the first look" and `polls>0` is "became
# hittable during the poll" — a self-heal, which now passes where it used to
# fail, and which a reader of these runs has to be able to tell from a clean tap.
count_sc_first_look() {   # <hittap-file>
    local n; n="$(grep -cE "HITTAP tapped $SITE_LABEL .*polls=0 budget=${SITE_BUDGET_RE}s" "$1" 2>/dev/null)"
    printf '%s' "${n:-0}"
}
count_sc_self_healed() {   # <hittap-file>
    local n; n="$(grep -cE "HITTAP tapped $SITE_LABEL .*polls=[1-9][0-9]* budget=${SITE_BUDGET_RE}s" "$1" 2>/dev/null)"
    printf '%s' "${n:-0}"
}
count_sc_timed_out() {   # <hittap-file>
    # `HITTAP post` is emitted at ONE place in the suite — `completeConnect`,
    # immediately after this tap — so it needs no budget filter, and unlike the
    # `fallback` line it also covers the degenerate timeout path that never
    # reaches a `centre` line.
    local n; n="$(grep -c 'HITTAP post outcome=tappedAfterTimeout' "$1" 2>/dev/null)"
    printf '%s' "${n:-0}"
}

LOGDIR="${TALARIA_BATCH_LOGDIR:-$(mktemp -d -t talaria-uibatch)}"
mkdir -p "$LOGDIR" || exit 1
LEDGER="$LOGDIR/ledger.tsv"

echo "== Talaria UI bundle batch =="
echo "   repo:      $REPO_ROOT  ($(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD))"
echo "   toolchain: $DEVELOPER_DIR"
echo "   trials:    $N (sequential, one simulator, identical bytes)"
echo "   logs:      $LOGDIR"
echo

# ------------------------------------------------------------------ preflight
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    echo "PREFLIGHT FAIL: xcodebuild not found under DEVELOPER_DIR" >&2
    exit 1
fi

SIM_UDID="$(xcrun simctl list devices available 2>/dev/null \
    | grep -F "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [[ -z "$SIM_UDID" ]]; then
    echo "PREFLIGHT FAIL: no available simulator named \"$SIM_NAME\" (set TALARIA_SIM_NAME)" >&2
    echo "  The pool is CC-lane-1 / CC-lane-2 / CC-lane-3. Recreate a missing member;" >&2
    echo "  do not invent a new per-item name." >&2
    exit 1
fi
echo "   simulator: \"$SIM_NAME\" = $SIM_UDID"

# THE THREE-BOOTED CEILING. Owen's standing ruling, and it is not a style
# preference: this Mac has been crashed outright by booting past it. Three is
# measured stable and leaves headroom for an accidental overage, so an
# instrument that boots a fourth is an instrument that can take the box down
# mid-measurement and lose the batch it was writing.
#
# Counted BEFORE any boot, and a target that is already booted is free — it is
# one of the three, not a fourth.
BOOTED_COUNT="$(xcrun simctl list devices 2>/dev/null | grep -c "Booted")"
BOOTED_COUNT=${BOOTED_COUNT:-0}
TARGET_BOOTED=0
if xcrun simctl list devices 2>/dev/null | grep -F "$SIM_UDID" | grep -q "Booted"; then
    TARGET_BOOTED=1
fi
if (( TARGET_BOOTED )); then
    echo "   booted:    $BOOTED_COUNT (target already among them)"
elif (( BOOTED_COUNT >= 3 )); then
    echo "PREFLIGHT FAIL: $BOOTED_COUNT simulators are already booted and \"$SIM_NAME\" is not one" >&2
    echo "  of them. Three booted is the ceiling on this Mac — booting past it has crashed" >&2
    echo "  the box. Shut one down first:" >&2
    echo "      xcrun simctl list devices | grep Booted" >&2
    echo "      xcrun simctl shutdown <udid>" >&2
    exit 1
else
    echo "   booted:    $BOOTED_COUNT — booting \"$SIM_NAME\" makes $((BOOTED_COUNT + 1))"
fi

# TCC, for the UDID resolved above and never for a name paired by hand.
#
# A simulator with a DENIED record fails the EventKit probe visibly. One with
# NO RECORD AT ALL blocks forever: the bundle stalls with no failure, no marker
# and no verdict, and the only tell is a log that stopped growing. In a batch
# that is worse than in a gate, because the operator is not watching — trial 4
# of 10 parks overnight and the morning's artifact is silence.
#
# Boot first (`simctl privacy` errors on a Shutdown device), and read the
# bundle id from project.yml rather than hardcoding it: `simctl privacy grant`
# accepts an unknown bundle id and exits 0, so a mistyped id would grant
# successfully against nothing and hang exactly as before.
TCC_BUNDLE_ID="$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\([A-Za-z0-9._-]*\) *$/\1/p' \
    "$REPO_ROOT/project.yml" | head -1)"
if [[ -z "$TCC_BUNDLE_ID" ]]; then
    echo "PREFLIGHT FAIL: could not read PRODUCT_BUNDLE_IDENTIFIER from project.yml" >&2
    exit 1
fi
if ! xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1; then
    echo "PREFLIGHT FAIL: could not boot $SIM_UDID — TCC cannot be granted and the bundle would hang" >&2
    exit 1
fi
TCC_FAILED=""
for service in calendar reminders; do
    xcrun simctl privacy "$SIM_UDID" grant "$service" "$TCC_BUNDLE_ID" >/dev/null 2>&1 \
        || TCC_FAILED="$TCC_FAILED $service"
done
if [[ -n "$TCC_FAILED" ]]; then
    echo "PREFLIGHT FAIL: TCC grant failed for:$TCC_FAILED — the probe would hang, not fail" >&2
    exit 1
fi
echo "   TCC:       granted (calendar, reminders) for $TCC_BUNDLE_ID"

# WHICH RUNTIME THIS BATCH MEASURED. A rate without the build it was taken on
# is ambiguous, and this simulator follows the system runtime match, so it can
# advance between batches with nothing in the repo to show for it. Asked of the
# booted OS rather than read from the device listing, which only knows the
# runtime IDENTIFIER that three different builds share.
SIM_RUNTIME_BUILD="$(xcrun simctl getenv "$SIM_UDID" SIMULATOR_RUNTIME_BUILD_VERSION 2>/dev/null | tr -d '[:space:]')"
SIM_RUNTIME_VERSION="$(xcrun simctl getenv "$SIM_UDID" SIMULATOR_RUNTIME_VERSION 2>/dev/null | tr -d '[:space:]')"
: "${SIM_RUNTIME_BUILD:=UNKNOWN}"
: "${SIM_RUNTIME_VERSION:=?}"
echo "   runtime:   iOS $SIM_RUNTIME_VERSION ($SIM_RUNTIME_BUILD)"
if [[ -n "$TAP_STRATEGY" ]]; then
    export TEST_RUNNER_UITEST_TAP_STRATEGY="$TAP_STRATEGY"
    echo "   tap arm:   $TAP_STRATEGY (forwarded as TEST_RUNNER_UITEST_TAP_STRATEGY)"
else
    echo "   tap arm:   unset — the test side's own default"
fi
echo

# --------------------------------------------------------------------- build
# ONCE. Everything after this is the same product, which is the whole point.
echo "-- build-for-testing (once; every trial below re-uses this product)"
BUILD_LOG="$LOGDIR/build.log"
"$DEVELOPER_DIR/usr/bin/xcodebuild" build-for-testing \
    -project Talaria.xcodeproj -scheme Talaria \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
if (( BUILD_STATUS != 0 )) || ! grep -qE '\*\* TEST BUILD SUCCEEDED \*\*' "$BUILD_LOG"; then
    # Positive marker required, exactly as the gate requires one: a build that
    # died early leaves a log with no failure marker in it, and "no BUILD
    # FAILED" is not "BUILD SUCCEEDED".
    echo "PREFLIGHT FAIL: build-for-testing did not report ** TEST BUILD SUCCEEDED ** (exit $BUILD_STATUS)" >&2
    echo "  log: $BUILD_LOG" >&2
    grep -E '\.swift:[0-9]+:[0-9]+: error:' "$BUILD_LOG" | sort -u | sed 's/^/    /' >&2
    exit 1
fi
echo "   PASS  ** TEST BUILD SUCCEEDED ** — $BUILD_LOG"
echo

# -------------------------------------------------------------------- trials
{
    printf '# ui-bundle-batch %s trial(s)\n' "$N"
    printf '# commit\t%s\n' "$(git rev-parse HEAD)"
    printf '# simulator\t%s\t%s\n' "$SIM_NAME" "$SIM_UDID"
    printf '# runtime\tiOS %s\t%s\n' "$SIM_RUNTIME_VERSION" "$SIM_RUNTIME_BUILD"
    printf '# tap_strategy\t%s\n' "${TAP_STRATEGY:-unset}"
    printf '# started\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    # What the two count columns actually count, said here because a 0 in
    # either is ambiguous otherwise. They tally log lines whose XCUITest
    # activity name begins with the prefix "HITTAP " (the current tap helper)
    # or "XFLAKE " (the older one). A build whose helper emits neither prefix
    # reports 0 for both, and that is "none emitted under this prefix" — not a
    # broken instrument and not a clean run.
    printf '# columns\thittap_lines / xflake_lines = activity lines prefixed "HITTAP " / "XFLAKE "\n'
    # The START CHATTING columns. They exist so the reading of a batch is a
    # column, not a grep — and so the three outcomes stay separable, because a
    # tap that self-heals inside the budget now PASSES and would otherwise be
    # indistinguishable in the ledger from one that never had to wait.
    printf '# columns\tsc_* = the START CHATTING tap in completeConnect (budget %ss) — the ONLY site this batch varies:\n' "$SITE_BUDGET"
    printf '# columns\t  sc_first_look  = tapped on the first look (polls=0)\n'
    printf '# columns\t  sc_self_healed = became hittable DURING the poll (polls>0) — late, not lost\n'
    printf '# columns\t  sc_timed_out   = never hittable; the fallback tap went out (outcome=tappedAfterTimeout)\n'
    printf '# columns\t  the three sum to the number of connect journeys in the bundle (3 today)\n'
    printf '# columns\t  the two DEBUG overlay fixtures tap the same button on a SHORTER budget with their\n'
    printf '# columns\t  arms pinned in the source; they are excluded from all three and are not this site\n'
    printf 'run\tresult\tfailing_tests\thittap_lines\txflake_lines\tsc_first_look\tsc_self_healed\tsc_timed_out\txcuitest_ledger\n'
} > "$LEDGER"

# The per-test red tally. bash 3.2 has no associative arrays, so failing names
# are appended to a file and counted at the end with sort | uniq -c. HITTAP and
# XFLAKE are counted SEPARATELY and never summed: they are two different
# prefixes emitted by two different vintages of the same helper, and a single
# number would hide which one this build actually produces.
#
# It lives under tmp/ rather than as a dotfile beside the artifacts. This log
# directory is published — it goes into the tracker entry as the batch's
# evidence — and a hidden scratch file in it is one an ls does not show and a
# reader cannot account for. Kept rather than deleted: it is the raw input the
# summary's tally was computed from, so a reader who doubts the tally can
# recount it.
SCRATCH_DIR="$LOGDIR/tmp"
mkdir -p "$SCRATCH_DIR" || exit 1
REDS_FILE="$SCRATCH_DIR/failing-names"
: > "$REDS_FILE"
RUN_FAILS=0
SC_TOTAL_FIRST=0
SC_TOTAL_HEALED=0
SC_TOTAL_TIMEOUT=0

for (( i = 1; i <= N; i++ )); do
    RUN_ID="$(printf '%02d' "$i")"
    RUN_LOG="$LOGDIR/run-$RUN_ID.log"
    HITTAP_FILE="$LOGDIR/run-$RUN_ID.hittap.txt"
    printf '   trial %s/%s ... ' "$RUN_ID" "$N"

    "$DEVELOPER_DIR/usr/bin/xcodebuild" test-without-building \
        -project Talaria.xcodeproj -scheme Talaria \
        -only-testing:TalariaUITests \
        -destination "platform=iOS Simulator,id=$SIM_UDID" \
        > "$RUN_LOG" 2>&1
    RUN_STATUS=$?

    # The tap diagnostics, kept beside the log so a reader does not have to
    # grep a 200 MB xcodebuild transcript to see what the helper observed.
    grep -E 'HITTAP |XFLAKE ' "$RUN_LOG" > "$HITTAP_FILE" 2>/dev/null || true
    HITTAP_N="$(grep -c 'HITTAP ' "$RUN_LOG" 2>/dev/null)"; HITTAP_N=${HITTAP_N:-0}
    XFLAKE_N="$(grep -c 'XFLAKE ' "$RUN_LOG" 2>/dev/null)"; XFLAKE_N=${XFLAKE_N:-0}

    # The three START CHATTING outcomes, read from the extracted file so they
    # are computed over exactly the lines the artifact preserves.
    SC_FIRST="$(count_sc_first_look  "$HITTAP_FILE")"
    SC_HEALED="$(count_sc_self_healed "$HITTAP_FILE")"
    SC_TIMEOUT="$(count_sc_timed_out  "$HITTAP_FILE")"
    SC_TOTAL_FIRST=$((SC_TOTAL_FIRST + SC_FIRST))
    SC_TOTAL_HEALED=$((SC_TOTAL_HEALED + SC_HEALED))
    SC_TOTAL_TIMEOUT=$((SC_TOTAL_TIMEOUT + SC_TIMEOUT))

    # PASS needs all three, the same way the gate does: the authoritative
    # marker, a zero exit, and a per-test count greater than zero. Zero is not
    # a count, and absence of a failure marker is not success. The marker and
    # ledger checks live in ui_batch_classify_result (defined above), not
    # inline here, so the self-test can exercise the exact same logic.
    read -r RUN_STARTED RUN_PASSED RUN_FAILED <<<"$(gate_xcuitest_ledger "$RUN_LOG")"
    RESULT="$(ui_batch_classify_result "$RUN_LOG" "$RUN_STATUS")"

    FAILING="$(gate_failing_test_names "$RUN_LOG")"
    [[ -n "$FAILING" ]] || FAILING="-"
    if [[ "$RESULT" == "FAIL" ]]; then
        RUN_FAILS=$((RUN_FAILS + 1))
        if [[ "$FAILING" != "-" ]]; then
            printf '%s\n' "$FAILING" | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
                | grep -v '^$' >> "$REDS_FILE"
        else
            # A red with no failing-test list is the runner dying, and it must
            # be counted as SOMETHING or the per-test tally will not add up to
            # the run tally — which is how a swallowed trial reads as clean.
            printf '(no failing-test list — runner lost)\n' >> "$REDS_FILE"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s ran / %s passed / %s failed\n' \
        "$RUN_ID" "$RESULT" "$FAILING" "$HITTAP_N" "$XFLAKE_N" \
        "$SC_FIRST" "$SC_HEALED" "$SC_TIMEOUT" \
        "$RUN_STARTED" "$RUN_PASSED" "$RUN_FAILED" >> "$LEDGER"

    printf '%s  (exit %s, %s ran / %s passed / %s failed, HITTAP %s, XFLAKE %s, START CHATTING %s first / %s healed / %s timed out)  %s\n' \
        "$RESULT" "$RUN_STATUS" "$RUN_STARTED" "$RUN_PASSED" "$RUN_FAILED" \
        "$HITTAP_N" "$XFLAKE_N" "$SC_FIRST" "$SC_HEALED" "$SC_TIMEOUT" "$RUN_LOG"

    # ------------------------------------------------------ the arm WITNESS
    #
    # After trial 1, and it ABORTS rather than warns.
    #
    # The tap arm is the batch's independent variable, and until now its only
    # basis was an environment variable nobody had watched arrive: this script
    # exports TEST_RUNNER_UITEST_TAP_STRATEGY, xcodebuild has to forward it
    # into the runner, the runner has to hand it to the test process, and the
    # helper has to read the key it expects. Any one of those failing yields a
    # batch that measured the DEFAULT arm and says on its face that it measured
    # the other one. A mislabelled measurement is the one outcome worse than no
    # measurement, and it is undetectable afterwards — which is why this is a
    # refusal and not a note in the summary.
    #
    # Trial 1's artifacts are already written above, so the abort loses nothing
    # a reader needs to diagnose it.
    if (( i == 1 )); then
        WITNESS_N="$(count_arm_witness "$HITTAP_FILE" "$EXPECT_VIA")"
        if (( WITNESS_N == 0 )); then
            echo
            echo "BATCH ABORTED after trial $RUN_ID — the tap arm was never WITNESSED." >&2
            echo "  Wanted at least one production START CHATTING line carrying via=$EXPECT_VIA" >&2
            echo "  (or strategy=$EXPECT_VIA on the timeout path) with the site's own ${SITE_BUDGET}s" >&2
            echo "  budget, in:" >&2
            echo "      $HITTAP_FILE" >&2
            echo "  Either UITEST_TAP_STRATEGY did not reach the test process, or the site's" >&2
            echo "  budget changed and SITE_BUDGET in this script is stale." >&2
            echo "  Refusing to continue: every remaining trial would be labelled with an arm" >&2
            echo "  nobody has seen arrive." >&2
            echo "  What that trial actually recorded for this button:" >&2
            grep -E "HITTAP (tapped|centre|fallback|post) ($SITE_LABEL|outcome=)" "$HITTAP_FILE" \
                2>/dev/null | sed 's/^/      /' >&2 \
                || echo "      (nothing at all — the button was never tapped through the helper)" >&2
            echo "  Logs so far: $LOGDIR" >&2
            exit 1
        fi
        echo "   WITNESS: the arm reached the production site $WITNESS_N time(s) in this trial (via=$EXPECT_VIA, budget ${SITE_BUDGET}s)"
    fi
done

printf '# finished\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LEDGER"

# ------------------------------------------------------------------- summary
echo
echo "-- batch summary"
echo "   runs FAILED: $RUN_FAILS of $N"
if [[ -s "$REDS_FILE" ]]; then
    echo "   reds per test, over $N run(s):"
    sort "$REDS_FILE" | uniq -c | sort -rn | while read -r count name; do
        printf '     %s/%s  %s\n' "$count" "$N" "$name"
    done
else
    echo "   no failing test was named in any run"
fi
echo "   START CHATTING over $N run(s): $SC_TOTAL_FIRST tapped on the first look /"
echo "                        $SC_TOTAL_HEALED became hittable during the poll /"
echo "                        $SC_TOTAL_TIMEOUT timed out and took the fallback tap"
echo "                        (the site this batch varies, budget ${SITE_BUDGET}s. The two DEBUG"
echo "                        overlay fixtures tap the same button on a shorter budget with"
echo "                        their arms pinned in the source and are NOT counted here.)"
echo "   runtime measured on: iOS $SIM_RUNTIME_VERSION ($SIM_RUNTIME_BUILD)"
echo "   tap arm:             ${TAP_STRATEGY:-unset} — WITNESSED as via=$EXPECT_VIA at the"
echo "                        production site in trial 01, not merely forwarded"
echo "   HITTAP/XFLAKE:       activity lines prefixed \"HITTAP \" / \"XFLAKE \" — a 0"
echo "                        means none were emitted under that prefix by this build"
echo "   ledger:              $LEDGER"
echo "   logs:                $LOGDIR"
echo "   scratch:             $SCRATCH_DIR (raw input to the per-test tally above)"
echo
echo "   A rate from this batch carries the commit, the runtime and the tap arm"
echo "   above, or it is ambiguous. Do not compare it with a batch built from"
echo "   different bytes."

# Exit 0 on a completed batch REGARDLESS of reds. This measures; it does not
# judge. The failures above are the finding, not an error in the instrument.
exit 0
