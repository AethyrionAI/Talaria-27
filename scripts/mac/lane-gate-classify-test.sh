#!/bin/bash
# lane-gate-classify-test.sh — the classifier's own self-test (OPEN_ITEMS 300).
#
# The gate is the one script every lane's verdict depends on, so a wrong "fix"
# to its advice silently degrades every future reading. This runs in about a
# second and needs no simulator, no toolchain and no build.
#
#   scripts/mac/lane-gate-classify-test.sh
#
# FIXTURES. The two load-bearing cases are transcriptions of REAL gate logs
# from 2026-08-09, reproduced here byte-exactly for the lines that matter so
# the bars stay runnable after /tmp is swept. Where the original logs still
# exist they are ALSO exercised, as a check that the transcriptions did not
# quietly drift from the thing they stand in for.
#
#   /tmp/gate-254-run2/suite.log   Swift Testing failure WITH assertion text.
#                                  The one the old classifier called a flake.
#   /tmp/gate-279-run2/suite.log   XCUITest runner death, no assertion text
#                                  anywhere. The true positive.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lane-gate-classify.sh
. "$HERE/lane-gate-classify.sh"

FIXDIR="$(mktemp -d -t talaria-classify)"
trap 'rm -rf "$FIXDIR"' EXIT
PASS=0; FAIL=0

check() {   # check <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL  %s — expected "%s", got "%s"\n' "$1" "$2" "$3"
    fi
}

# Assert the advice text contains a string.
#
# The output is captured into a variable and grepped SEPARATELY rather than
# piped. Under `set -o pipefail` a `producer | grep -q` pipeline reports
# failure whenever grep matches early and exits, because the producer then dies
# of SIGPIPE and pipefail takes its status — so a MATCH is reported as a miss,
# nondeterministically, depending on how much output fit in the pipe buffer.
# That bit this very file on its first run.
advice_says() {   # advice_says <label> <logfile> <needle>
    local out
    out="$(gate_print_failure_advice "$2")"
    if [[ "$out" == *"$3"* ]]; then
        PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL  %s — advice did not contain "%s"\n' "$1" "$3"
    fi
}

# --------------------------------------------------------------- fixture 1
# Swift Testing, real assertion. Verbatim from /tmp/gate-254-run2/suite.log.
# Note what makes this the whole point: the issue line carries file:LINE:COLUMN
# and NO "error:" token, so the pre-2026-08-10 regex ('\.swift:[0-9]+: error:')
# matched nothing and the run was announced as a harness flake.
cat > "$FIXDIR/swift-testing-assertion.log" <<'EOF'
◇ Test controlArmWithoutRulesLeaksToTheListener() started.
✘ Test controlArmWithoutRulesLeaksToTheListener() recorded an issue at HTMLArtifactSandboxTests.swift:157:9: Expectation failed: landed
↳ control arm produced no network hit — the harness is not live
✘ Test controlArmWithoutRulesLeaksToTheListener() failed after 5.754 seconds with 1 issue.
** TEST FAILED **

Failing tests:
	HTMLArtifactSandboxTests.controlArmWithoutRulesLeaksToTheListener()

EOF

# --------------------------------------------------------------- fixture 2
# XCUITest runner death. The test STARTS and is then listed as failed with no
# issue recorded against it anywhere — the genuine flake signature.
cat > "$FIXDIR/runner-death.log" <<'EOF'
Test Case '-[TalariaUITests.TalariaUITests testPairedRelaunchSkipsPairingEntry]' started.
** TEST FAILED **

Failing tests:
	TalariaUITests.testPairedRelaunchSkipsPairingEntry()

EOF

# --------------------------------------------------------------- fixture 3
# Classic XCTest diagnostic — the ONLY shape the old regex understood. Kept so
# the fix cannot regress the case that used to work.
cat > "$FIXDIR/xctest-assertion.log" <<'EOF'
Test Case '-[TalariaUITests.MessageIdentityUITests testComposerReachable]' started.
/Users/owenjones/Talaria/TalariaUITests/MessageIdentityUITests.swift:100: error: -[TalariaUITests.MessageIdentityUITests testComposerReachable] : XCTAssertTrue failed
** TEST FAILED **

Failing tests:
	MessageIdentityUITests.testComposerReachable()

EOF

# --------------------------------------------------------------- fixture 4
# A runner death whose log is ALSO full of the simulator's CoreData chatter.
# The real 2026-08-09 log carried 884 lines matching a bare `: error:`, none of
# them a test failure. A classifier that reaches for `grep -c error:` reads
# this as a real failure; that is the gate header's own sim-noise trap.
{
    echo "Test Case '-[TalariaUITests.TalariaUITests testPairedRelaunchSkipsPairingEntry]' started."
    for _ in $(seq 1 40); do
        echo "2026-08-09 07:15:22.910285-0500 Talaria 27[36378:41918588] [error] CoreData: error:   File Permissions: 	0644"
    done
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testPairedRelaunchSkipsPairingEntry()\n\n'
} > "$FIXDIR/runner-death-with-noise.log"

# --------------------------------------------------------------- fixture 5
# A DISPLAY-NAMED Swift Testing test: the issue line carries the human string
# from @Test("…"), so no function identifier links it to the failing-test
# entry. Nothing can attribute it — and the answer must still be "real", never
# "flake". This is the safe-direction invariant, tested.
cat > "$FIXDIR/display-named.log" <<'EOF'
✘ Test "Condensed priming stays in budget on a long journal" recorded an issue at CondenserFidelityTests.swift:88:5: Expectation failed: budget
** TEST FAILED **

Failing tests:
	CondenserFidelityTests.condensedPrimingStaysInBudget()

EOF

# --------------------------------------------------------------- fixture 6
# Mixed run: one real Swift Testing failure alongside a UI test with nothing
# recorded. A run containing ANY real failure is a real failure.
cat > "$FIXDIR/mixed.log" <<'EOF'
✘ Test somethingRealBroke() recorded an issue at AppStoresTests.swift:1781:9: Expectation failed: stopped.failure != nil
Test Case '-[TalariaUITests.TalariaUITests testPairedRelaunchSkipsPairingEntry]' started.
** TEST FAILED **

Failing tests:
	AppStoresTests.somethingRealBroke()
	TalariaUITests.testPairedRelaunchSkipsPairingEntry()

EOF

# --------------------------------------------------------------- fixture 7
# Substring collision: testFoo must not inherit testFooBar's assertion.
cat > "$FIXDIR/substring.log" <<'EOF'
✘ Test testFooBar() recorded an issue at SomeTests.swift:12:3: Expectation failed: nope
Test Case '-[UITests.UITests testFoo]' started.
** TEST FAILED **

Failing tests:
	SomeTests.testFoo()

EOF

# ------------------------------------------------- fixtures 8-11: the ledger
# The XCUITest bundle exactly as it ran on 2026-09-01, in log order. Two things
# about this list are load-bearing:
#
#   * `testLaunch` appears TWICE. The launch suite runs it under two
#     configurations and both are real executions, so the ledger counts LINES
#     and must never deduplicate names.
#   * the per-suite `Executed` lines are reproduced too, because they are the
#     whole defect: on a red run only the two-test launch sub-suite still says
#     "with 0 failures", so a MAX over that phrase reports 2 for a bundle of
#     fifteen — which reads to a human exactly like the runner dying after two
#     tests, and misdirected a diagnosis twice on the night this was found.
XCUI_TESTS=(
    "MessageIdentityUITests testQueuedChipCancelRemovesHeldMessageWithNothingPosted"
    "MessageIdentityUITests testTranscriptNeverRendersDuplicateMessageIDs"
    "TalariaUITests testAppearanceChannelBrowserAppliesThemeOnLand"
    "TalariaUITests testCapabilitiesSurfaceReachableByChipAndSlashCommand"
    "TalariaUITests testChatSendFlow"
    "TalariaUITests testConnectedRelaunchSkipsTheConnectEntry"
    "TalariaUITests testConnectingAHostViaSettingsEntryPointLandsBackInChat"
    "TalariaUITests testDisconnectingAHostReturnsToStandaloneChat"
    "TalariaUITests testFreshInstallNeverPresentsNotificationPermissionDialog"
    "TalariaUITests testPrivacyAgentActionsControlRendersAndSwitchesMode"
    "TalariaUITests testSettingsDeckNavigation"
    "TalariaUITests testSettingsGridPresentsNineSubsystems"
    "TalariaUITests testStandaloneFirstLaunchLandsInChat"
    "TalariaUITestsLaunchTests testLaunch"
    "TalariaUITestsLaunchTests testLaunch"
)

# emit_ledger <failing-index-or--1> <stop-after-index-or--1>
#   failing-index   the one test that reports `failed` (-1 = none)
#   stop-after      after this many outcome lines, stop reporting outcomes at
#                   all while still printing the `started` lines — the runner
#                   dying mid-bundle (-1 = report every one)
emit_ledger() {
    local fail_at="$1" stop_after="$2" i=0 outcomes=0 suite name
    for entry in "${XCUI_TESTS[@]}"; do
        suite="${entry%% *}"; name="${entry##* }"
        printf "Test Case '-[TalariaUITests.%s %s]' started.\n" "$suite" "$name"
        if (( stop_after >= 0 && outcomes >= stop_after )); then
            i=$((i+1)); continue
        fi
        if (( i == fail_at )); then
            printf "Test Case '-[TalariaUITests.%s %s]' failed (42.664 seconds).\n" "$suite" "$name"
        else
            printf "Test Case '-[TalariaUITests.%s %s]' passed (11.164 seconds).\n" "$suite" "$name"
        fi
        outcomes=$((outcomes+1)); i=$((i+1))
    done
}

# Fixture 8 — the RED run. Transcribed from the two 2026-09-01 gate logs
# (talaria-gate.OvEY5t4EZE and .8vQbvPdIOy); both carry these exact counts.
{
    emit_ledger 5 -1
    printf '\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds\n'
    printf '\t Executed 2 tests, with 0 failures (0 unexpected) in 70.179 (70.184) seconds\n'
    printf '\t Executed 11 tests, with 1 failure (0 unexpected) in 210.685 (210.695) seconds\n'
    printf '\t Executed 2 tests, with 0 failures (0 unexpected) in 12.400 (12.402) seconds\n'
    printf '\t Executed 15 tests, with 1 failure (0 unexpected) in 293.265 (293.286) seconds\n'
    printf '\t Executed 15 tests, with 1 failure (0 unexpected) in 293.265 (293.287) seconds\n'
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testConnectedRelaunchSkipsTheConnectEntry()\n\n'
} > "$FIXDIR/xcui-red.log"

# Fixture 9 — the GREEN run (talaria-gate.qGBfEfdv9p). The count here must stay
# byte-identical to what the gate has always printed, or every historical PASS
# count silently changes meaning.
{
    emit_ledger -1 -1
    printf '\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.002) seconds\n'
    printf '\t Executed 2 tests, with 0 failures (0 unexpected) in 70.374 (70.385) seconds\n'
    printf '\t Executed 11 tests, with 0 failures (0 unexpected) in 207.332 (207.342) seconds\n'
    printf '\t Executed 2 tests, with 0 failures (0 unexpected) in 12.477 (12.479) seconds\n'
    printf '\t Executed 15 tests, with 0 failures (0 unexpected) in 290.183 (290.208) seconds\n'
    printf '\t Executed 15 tests, with 0 failures (0 unexpected) in 290.183 (290.212) seconds\n'
    printf '** TEST SUCCEEDED **\n'
} > "$FIXDIR/xcui-green.log"

# Fixture 10 — the runner dies after ten outcomes. Every test STARTED; five
# never reported anything. This is the shape the red-run defect was mistaken
# for, so the two must be distinguishable in the output.
{
    emit_ledger -1 10
    printf '\t Executed 2 tests, with 0 failures (0 unexpected) in 12.400 (12.402) seconds\n'
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testSettingsDeckNavigation()\n\n'
} > "$FIXDIR/xcui-runner-death.log"

# Fixture 11 — a log with no XCUITest ledger at all (a build that died before
# the bundle ran). Absence must read as absence, never as a count.
printf '** TEST BUILD FAILED **\n' > "$FIXDIR/xcui-no-ledger.log"

echo "== classifier self-test =="
echo

echo "-- 300-A: a Swift Testing failure WITH assertion text is a REAL failure"
check "swift-testing assertion -> assertion" \
      "assertion" "$(gate_classify_failures "$FIXDIR/swift-testing-assertion.log")"
advice_says "advice says REAL failure" \
            "$FIXDIR/swift-testing-assertion.log" "REAL failure"
advice_says "advice quotes the locus back to the reader" \
            "$FIXDIR/swift-testing-assertion.log" "HTMLArtifactSandboxTests.swift:157:9"
advice_says "advice quotes the expectation text" \
            "$FIXDIR/swift-testing-assertion.log" "Expectation failed: landed"
echo

echo "-- 300-B: a genuine no-assertion-text runner death is still the flake family"
check "runner death -> runner-flake" \
      "runner-flake" "$(gate_classify_failures "$FIXDIR/runner-death.log")"
check "runner death + CoreData noise -> runner-flake" \
      "runner-flake" "$(gate_classify_failures "$FIXDIR/runner-death-with-noise.log")"
advice_says "advice still prescribes the re-run-once protocol" \
            "$FIXDIR/runner-death.log" "Re-run ONCE"
echo

echo "-- no regression on the shape the old regex DID handle"
check "xctest assertion -> assertion" \
      "assertion" "$(gate_classify_failures "$FIXDIR/xctest-assertion.log")"
echo

echo "-- the safe direction: never dress a real failure as noise"
check "display-named issue -> unattributed (still REAL)" \
      "unattributed" "$(gate_classify_failures "$FIXDIR/display-named.log")"
advice_says "unattributed advice still says REAL failure" \
            "$FIXDIR/display-named.log" "REAL failure"
check "mixed run -> assertion" \
      "assertion" "$(gate_classify_failures "$FIXDIR/mixed.log")"
check "substring collision does not borrow a locus" \
      "unattributed" "$(gate_classify_failures "$FIXDIR/substring.log")"
echo

echo "-- the XCUITest count must be honest on a RED run, not only on a green one"
check "red run -> passed/failed/total" \
      "14 passed / 1 failed / 15 ran" "$(gate_xcuitest_summary "$FIXDIR/xcui-red.log")"
check "green run -> the same bare number the gate has always printed" \
      "15" "$(gate_xcuitest_summary "$FIXDIR/xcui-green.log")"
check "runner death is DISTINGUISHABLE from a red run" \
      "10 passed / 0 failed / 15 ran" "$(gate_xcuitest_summary "$FIXDIR/xcui-runner-death.log")"
check "no ledger -> empty, which the caller must fail on" \
      "" "$(gate_xcuitest_summary "$FIXDIR/xcui-no-ledger.log")"
check "missing log -> empty, never a count" \
      "" "$(gate_xcuitest_summary "$FIXDIR/does-not-exist.log")"
echo

echo "-- the REAL 2026-09-01 gate logs, if they are still on this machine"
for pair in \
    "14 passed / 1 failed / 15 ran:OvEY5t4EZE" \
    "14 passed / 1 failed / 15 ran:8vQbvPdIOy" \
    "15:qGBfEfdv9p"
do
    want="${pair%:*}"; stem="${pair##*:}"
    reallog="$(ls -d "${TMPDIR:-/tmp}"/talaria-gate."$stem" 2>/dev/null)/suite.log"
    if [[ -s "$reallog" ]]; then
        check "real log talaria-gate.$stem -> $want" \
              "$want" "$(gate_xcuitest_summary "$reallog")"
    else
        echo "  SKIP  talaria-gate.$stem is gone — the fixtures above stand in for it"
    fi
done
echo

echo "-- 300-C: no tracker item numbers in text the gate EMITS"
EMITTED_NUMS=0
for f in "$HERE/lane-gate.sh" "$HERE/lane-gate-classify.sh"; do
    # Every echo/printf argument string in the script, stripped of comments.
    n="$(grep -hoE '^[[:space:]]*(echo|printf)[[:space:]].*' "$f" | grep -coE '#[0-9]+' || true)"
    EMITTED_NUMS=$((EMITTED_NUMS + ${n:-0}))
done
check "emitted tracker numbers" "0" "$EMITTED_NUMS"
echo

echo "-- and the pointers that REPLACED them actually resolve"
# Dropping the item numbers only helps if what took their place finds the item.
# A grep hint that matches nothing is the same defect wearing a different hat,
# so every `grep … OPEN_ITEMS.md` the scripts print is executed here.
TRACKER="$(cd "$HERE/../.." && pwd)/OPEN_ITEMS.md"
HINTS=0
while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    HINTS=$((HINTS+1))
    if [[ -s "$TRACKER" ]] && grep -q -- "$pat" "$TRACKER"; then
        PASS=$((PASS+1)); printf '  PASS  hint resolves: grep %s -> %s hit(s)\n' \
            "$pat" "$(grep -c -- "$pat" "$TRACKER")"
    else
        FAIL=$((FAIL+1)); printf '  FAIL  hint finds NOTHING in OPEN_ITEMS.md: %s\n' "$pat"
    fi
done < <(
    grep -hoE '^[[:space:]]*(echo|printf)[[:space:]].*' \
        "$HERE/lane-gate.sh" "$HERE/lane-gate-classify.sh" \
    | grep -oE "grep -n '[^']+' OPEN_ITEMS\.md|grep -n [A-Za-z0-9_]+ OPEN_ITEMS\.md" \
    | sed -E "s/^grep -n '?//; s/'? OPEN_ITEMS\.md$//"
)
check "advice emits at least one tracker pointer" "yes" "$( ((HINTS>0)) && echo yes || echo no )"
echo

echo "-- the ORIGINAL logs, if they are still on this machine"
for pair in "assertion:/tmp/gate-254-run2/suite.log" "runner-flake:/tmp/gate-279-run2/suite.log"; do
    want="${pair%%:*}"; log="${pair#*:}"
    if [[ -s "$log" ]]; then
        check "real log $(basename "$(dirname "$log")") -> $want" \
              "$want" "$(gate_classify_failures "$log")"
    else
        echo "  SKIP  $log is gone — the embedded transcription stands in for it"
    fi
done
echo

if (( FAIL == 0 )); then
    echo "CLASSIFIER: PASS ($PASS checks)"
    exit 0
fi
echo "CLASSIFIER: FAIL ($FAIL of $((PASS+FAIL)) checks)"
exit 1
