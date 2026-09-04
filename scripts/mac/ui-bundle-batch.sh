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
#                         than a refused one.
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

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta6.app/Contents/Developer}"
export DEVELOPER_DIR
SIM_NAME="${TALARIA_SIM_NAME:-CC-lane-2}"
TAP_STRATEGY="${UITEST_TAP_STRATEGY:-}"

N="${1:-}"
if ! [[ "$N" =~ ^[0-9]+$ ]] || (( N < 1 )); then
    echo "usage: $0 <N>   (N = number of trials, a positive integer)" >&2
    exit 2
fi

if [[ -n "$TAP_STRATEGY" && "$TAP_STRATEGY" != "element" && "$TAP_STRATEGY" != "coordinate" ]]; then
    echo "ui-bundle-batch: UITEST_TAP_STRATEGY=\"$TAP_STRATEGY\" is not one of: element, coordinate" >&2
    echo "  Refusing rather than forwarding it. The test side falls back to its default" >&2
    echo "  on a value it does not know, so this batch would be labelled with an arm it" >&2
    echo "  never ran." >&2
    exit 2
fi

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
    printf 'run\tresult\tfailing_tests\thittap_lines\txflake_lines\txcuitest_ledger\n'
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

    # PASS needs all three, the same way the gate does: the authoritative
    # marker, a zero exit, and a per-test count greater than zero. Zero is not
    # a count, and absence of a failure marker is not success.
    read -r RUN_STARTED RUN_PASSED RUN_FAILED <<<"$(gate_xcuitest_ledger "$RUN_LOG")"
    RESULT="FAIL"
    if (( RUN_STATUS == 0 )) \
        && grep -qE '\*\* TEST SUCCEEDED \*\*' "$RUN_LOG" \
        && ! grep -qE '\*\* TEST FAILED \*\*|\*\* TEST BUILD FAILED \*\*' "$RUN_LOG" \
        && (( RUN_STARTED > 0 && RUN_FAILED == 0 && RUN_PASSED == RUN_STARTED )); then
        RESULT="PASS"
    fi

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

    printf '%s\t%s\t%s\t%s\t%s\t%s ran / %s passed / %s failed\n' \
        "$RUN_ID" "$RESULT" "$FAILING" "$HITTAP_N" "$XFLAKE_N" \
        "$RUN_STARTED" "$RUN_PASSED" "$RUN_FAILED" >> "$LEDGER"

    printf '%s  (exit %s, %s ran / %s passed / %s failed, HITTAP %s, XFLAKE %s)  %s\n' \
        "$RESULT" "$RUN_STATUS" "$RUN_STARTED" "$RUN_PASSED" "$RUN_FAILED" \
        "$HITTAP_N" "$XFLAKE_N" "$RUN_LOG"
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
echo "   runtime measured on: iOS $SIM_RUNTIME_VERSION ($SIM_RUNTIME_BUILD)"
echo "   tap arm:             ${TAP_STRATEGY:-unset}"
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
