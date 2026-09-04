#!/bin/bash
# lane-gate-classify-test.sh — the classifier's own self-test (OPEN_ITEMS 300).
#
# The gate is the one script every lane's verdict depends on, so a wrong "fix"
# to its advice silently degrades every future reading. This runs in a second
# or two and needs no simulator, no toolchain and no build.
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
#
# The known-flake fixtures (12 onward) are transcribed from the 2026-09-03 gate
# red kept at planning/reports/2026-09-04-219-evidence-swallowed-tap.txt. They
# cover the third verdict and the gate's single automated re-roll — a decision
# and a log evaluation that both live in the library precisely so they can be
# exercised here in a second rather than behind a 35-minute suite.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
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
# Rendering the advice is the expensive thing in this file (a classify plus a
# locus grep per failing test), and most fixtures are asked several questions
# in a row. One-entry cache, filled in the CALLER's shell — a command
# substitution would put the cache in a subshell and never see it again.
ADVICE_KEY=""; ADVICE_OUT=""
advice_render() {   # advice_render <logfile>
    if [[ "$ADVICE_KEY" != "$1" ]]; then
        ADVICE_KEY="$1"
        ADVICE_OUT="$(gate_print_failure_advice "$1")"
    fi
}

advice_says() {   # advice_says <label> <logfile> <needle>
    advice_render "$2"
    if [[ "$ADVICE_OUT" == *"$3"* ]]; then
        PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL  %s — advice did not contain "%s"\n' "$1" "$3"
    fi
}

# The inverse, and it is not symmetry for its own sake. The known-flake verdict
# exists because the advice for this family used to read "Do NOT re-roll it" —
# the exact opposite of its ruled protocol. An assertion that the wrong words
# are ABSENT is the only one that can catch that sentence coming back.
advice_never_says() {   # advice_never_says <label> <logfile> <needle>
    local out
    advice_render "$2"
    out="$ADVICE_OUT"
    if [[ "$out" != *"$3"* ]]; then
        PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL  %s — advice contained "%s" and must not\n' "$1" "$3"
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

# --------------------------------------- fixtures 12-17: the KNOWN FLAKE
#
# The swallowed-first-tap family. `testConnectedRelaunchSkipsTheConnectEntry`
# and its two sibling connect/disconnect journeys fail on a tap the runner
# reports as delivered — `Synthesize event`, then `Computed hit point {-1, -1}`
# — and the app never receives. The assertion that follows is about the state
# AFTER that tap, so the failure DOES carry a locus.
#
# That is the whole reason this verdict had to exist. A locus-only classifier
# reads this as `assertion` and prints "Do NOT re-roll it" over the one family
# whose ruled protocol is exactly one re-roll — so the advice was telling the
# reader to do the opposite of the protocol, on the failure it sees most often.
#
# Transcribed from the 2026-09-03 gate red; the locus, the failure text and the
# activity lines are that run's
# (planning/reports/2026-09-04-219-evidence-swallowed-tap.txt).
#
# Every fixture below that must NOT re-roll for a VERDICT reason carries the
# Swift Testing pass line, so that its "no" isolates on the verdict and cannot
# be satisfied accidentally by a missing marker.
SWIFT_TESTING_PASSED='✔ Test run with 3128 tests in 200 suites passed after 412.331 seconds.'
FLAKE_LOCUS='/Users/owenjones/Talaria/TalariaUITests/AppTemplateUITests.swift:540: error: -[TalariaUITests.TalariaUITests testConnectedRelaunchSkipsTheConnectEntry] : failed - a successful connect should land straight in chat'

# Fixture 12 — THE case: one listed test, a real locus, units green above it.
# The units run before the UI target in the scheme, so a UI-only red always
# carries the Swift Testing pass line.
{
    emit_ledger 5 -1
    printf '    t =    21.97s XFLAKE pre hittable=false frame=(24.0, 509.0, 372.0, 56.0) window=(0.0, 0.0, 420.0, 912.0) scroll=(0.0, 127.0, 420.0, 785.0)\n'
    printf '    t =    22.05s         Computed hit point {-1, -1} after scrolling to visible\n'
    printf '%s\n' "$FLAKE_LOCUS"
    printf '%s\n' "$SWIFT_TESTING_PASSED"
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testConnectedRelaunchSkipsTheConnectEntry()\n\n'
} > "$FIXDIR/known-flake-red.log"

# Fixture 13 — the same red with NO Swift Testing pass line. Still the same
# verdict (the verdict is about WHICH tests failed), but it must not re-roll:
# a Swift Testing red never re-rolls, and "the line is missing" is
# indistinguishable from "the units did not pass" without reading further.
{
    emit_ledger 5 -1
    printf '%s\n' "$FLAKE_LOCUS"
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testConnectedRelaunchSkipsTheConnectEntry()\n\n'
} > "$FIXDIR/known-flake-red-no-units.log"

# Fixture 14 — MIXED: a listed test and an unlisted one, both UI, units green.
# One unlisted failure disqualifies the whole run. This is the safe-direction
# invariant in its new clothes: the list may only ever EXCUSE a run in which
# nothing else failed. (Its ledger reports one failure rather than two —
# `emit_ledger` takes a single index. Nothing here reads this fixture's count;
# the subject is the verdict.)
{
    emit_ledger 5 -1
    printf '%s\n' "$FLAKE_LOCUS"
    printf '/Users/owenjones/Talaria/TalariaUITests/MessageIdentityUITests.swift:212: error: -[TalariaUITests.MessageIdentityUITests testTranscriptNeverRendersDuplicateMessageIDs] : XCTAssertEqual failed\n'
    printf '%s\n' "$SWIFT_TESTING_PASSED"
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testConnectedRelaunchSkipsTheConnectEntry()\n\tMessageIdentityUITests.testTranscriptNeverRendersDuplicateMessageIDs()\n\n'
} > "$FIXDIR/known-flake-mixed.log"

# Fixture 15 — an UNLISTED UI red with units green. Ordinary `assertion`, no
# re-roll, and the identity family's own advice line rides along.
{
    emit_ledger 1 -1
    printf '/Users/owenjones/Talaria/TalariaUITests/MessageIdentityUITests.swift:212: error: -[TalariaUITests.MessageIdentityUITests testTranscriptNeverRendersDuplicateMessageIDs] : XCTAssertEqual failed\n'
    printf '%s\n' "$SWIFT_TESTING_PASSED"
    printf '** TEST FAILED **\n\nFailing tests:\n\tMessageIdentityUITests.testTranscriptNeverRendersDuplicateMessageIDs()\n\n'
} > "$FIXDIR/unlisted-red.log"

# Fixture 16 — a runner death with units green and an UNLISTED test named. The
# runner-flake verdict survives untouched, and it does not re-roll: its
# protocol is the same one re-run, but by a human who has read the log.
{
    emit_ledger -1 10
    printf '%s\n' "$SWIFT_TESTING_PASSED"
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testSettingsDeckNavigation()\n\n'
} > "$FIXDIR/runner-death-with-units.log"

# Fixture 17 — a runner death that happens to name a LISTED test: fifteen tests
# START and only five ever report an outcome. THE LIST DOES NOT WIN HERE, and
# this fixture exists to hold that line.
#
# A name on the list excuses ONE KNOWN FAILURE MODE — a tap the app never
# received — not every red that happens to mention that test. When the runner
# dies, which test is named is an accident of what it was holding at the time,
# so reading the name as the swallowed-tap family throws away the only
# diagnosis the log actually supports ("no assertion locus anywhere — the
# runner died").
#
# It also INVERTS the re-roll's size check. A truncated first run makes the
# expected total short, so a clean fifteen-test re-roll trips `passed !=
# expected` and the gate reports "the re-roll ran 15 test(s) where the first
# run ran 5" — a false FAIL after 35 minutes, explained by the opposite of
# what happened.
#
# The discriminator is the LEDGER, not the locus: started == passed + failed
# means every test that started reported an outcome, which is the direct
# measure of "the runner did not die".
{
    emit_ledger -1 5
    printf '%s\n' "$SWIFT_TESTING_PASSED"
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testConnectedRelaunchSkipsTheConnectEntry()\n\n'
} > "$FIXDIR/runner-death-listed.log"

# Fixture 23 — the same shape at its extreme: a listed test named with NO
# ledger at all. Nothing started, so nothing could report an outcome, and
# `passed + failed == started` holds VACUOUSLY (0 == 0) — a completeness rule
# written as that comparison alone would call this the most complete ledger it
# ever saw. Zero is not a count here either.
{
    printf '%s\n' "$SWIFT_TESTING_PASSED"
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testConnectedRelaunchSkipsTheConnectEntry()\n\n'
} > "$FIXDIR/runner-death-listed-no-ledger.log"

# ------------------------------------- fixtures 18-22: the RE-ROLL's own log
#
# The re-roll runs `-only-testing:TalariaUITests`, so it has NO Swift Testing
# line and must not be asked for one. Everything else is the gate's ordinary
# discipline, plus one check the first run cannot make: the bundle that came
# back has to be the SAME SIZE as the one that failed. A `-only-testing`
# argument that resolves to a subset would otherwise re-roll two tests, pass,
# and clear a red over thirteen tests nobody ran.

# Fixture 18 — a clean re-roll: all fifteen, all passed.
{
    emit_ledger -1 -1
    printf '\t Executed 15 tests, with 0 failures (0 unexpected) in 290.183 (290.208) seconds\n'
    printf '** TEST SUCCEEDED **\n'
} > "$FIXDIR/reroll-green.log"

# Fixture 19 — the second red. This is a REAL red, and the gate must say so.
{
    emit_ledger 5 -1
    printf '%s\n' "$FLAKE_LOCUS"
    printf '** TEST FAILED **\n\nFailing tests:\n\tTalariaUITests.testConnectedRelaunchSkipsTheConnectEntry()\n\n'
} > "$FIXDIR/reroll-red.log"

# Fixture 20 — every marker green, but only two tests ran. The count check is
# the only thing standing between this log and a cleared red.
{
    printf "Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' started.\n"
    printf "Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' passed (5.001 seconds).\n"
    printf "Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' started.\n"
    printf "Test Case '-[TalariaUITests.TalariaUITestsLaunchTests testLaunch]' passed (5.002 seconds).\n"
    printf '** TEST SUCCEEDED **\n'
} > "$FIXDIR/reroll-short.log"

# Fixture 21 — TEST SUCCEEDED over no ledger at all. Zero is not a count and
# absence is not a pass; this is the gate's founding sin in miniature.
printf '** TEST SUCCEEDED **\n' > "$FIXDIR/reroll-no-ledger.log"

# Fixture 22 — the build died before the bundle ran.
printf '** TEST BUILD FAILED **\n' > "$FIXDIR/reroll-build-failed.log"

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

echo "-- DET-B: the known-flake verdict — a locus does NOT make this family real"
check "listed test alone -> known-flake" \
      "known-flake" "$(gate_classify_failures "$FIXDIR/known-flake-red.log")"
check "listed test, no units line -> still known-flake" \
      "known-flake" "$(gate_classify_failures "$FIXDIR/known-flake-red-no-units.log")"
check "listed + unlisted -> assertion (one real failure disqualifies the run)" \
      "assertion" "$(gate_classify_failures "$FIXDIR/known-flake-mixed.log")"
check "unlisted UI red -> assertion" \
      "assertion" "$(gate_classify_failures "$FIXDIR/unlisted-red.log")"
check "runner death naming an unlisted test -> runner-flake" \
      "runner-flake" "$(gate_classify_failures "$FIXDIR/runner-death-with-units.log")"
check "runner death naming a LISTED test -> runner-flake (the list does NOT win)" \
      "runner-flake" "$(gate_classify_failures "$FIXDIR/runner-death-listed.log")"
check "runner death naming a LISTED test with NO ledger -> runner-flake" \
      "runner-flake" "$(gate_classify_failures "$FIXDIR/runner-death-listed-no-ledger.log")"
# The two halves of the discriminator, pinned in both directions so the reason
# a fixture qualifies is visible in the output and not just in a comment.
read -r KF_STARTED KF_PASSED KF_FAILED <<<"$(gate_xcuitest_ledger "$FIXDIR/known-flake-red.log")"
check "the known-flake fixture's ledger is COMPLETE — that is what qualifies it" \
      "15 == 15" "$KF_STARTED == $((KF_PASSED + KF_FAILED))"
read -r RD_STARTED RD_PASSED RD_FAILED <<<"$(gate_xcuitest_ledger "$FIXDIR/runner-death-listed.log")"
check "the runner-death fixture's ledger is INCOMPLETE — that is what disqualifies it" \
      "15 != 5" "$RD_STARTED != $((RD_PASSED + RD_FAILED))"
advice_says "known-flake advice prescribes exactly ONE re-run" \
            "$FIXDIR/known-flake-red.log" "ONCE"
advice_says "known-flake advice says a second red is a REAL red" \
            "$FIXDIR/known-flake-red.log" "a second red is a REAL red"
advice_says "known-flake advice says keep BOTH logs" \
            "$FIXDIR/known-flake-red.log" "BOTH logs"
advice_says "known-flake advice says identical bytes" \
            "$FIXDIR/known-flake-red.log" "IDENTICAL BYTES"
advice_says "known-flake advice points at the family's live entry" \
            "$FIXDIR/known-flake-red.log" "grep -n 'runner dies mid-bundle' OPEN_ITEMS-ARCHIVE.md"
advice_says "known-flake advice still quotes the locus back" \
            "$FIXDIR/known-flake-red.log" "AppTemplateUITests.swift:540"
advice_never_says "known-flake advice never tells the reader NOT to re-roll" \
            "$FIXDIR/known-flake-red.log" "Do NOT re-roll"
advice_says "a mixed run keeps the REAL-failure advice" \
            "$FIXDIR/known-flake-mixed.log" "REAL failure"
advice_says "a mixed run still says do NOT re-roll" \
            "$FIXDIR/known-flake-mixed.log" "Do NOT re-roll"
# The runner-death diagnosis must SURVIVE a listed name. Losing it is the whole
# cost of letting the list win: the one sentence the log supports is the one
# the reader stops being told.
advice_says "a runner death that names a listed test still gets the runner diagnosis" \
            "$FIXDIR/runner-death-listed.log" "NO assertion locus anywhere"
advice_never_says "a runner death is never dressed up as a known flake" \
            "$FIXDIR/runner-death-listed.log" "KNOWN-FLAKE"
echo

echo "-- DET-F: the identity family names its cause first, and never re-rolls"
advice_says "identity failure names its transcript-dump search string" \
            "$FIXDIR/unlisted-red.log" "the on-device reply for"
advice_says "identity failure gets a resolvable pointer" \
            "$FIXDIR/unlisted-red.log" "grep -n 'the on-device reply for' OPEN_ITEMS-ARCHIVE.md"
advice_says "the identity line rides a mixed run too" \
            "$FIXDIR/known-flake-mixed.log" "the on-device reply for"
advice_never_says "a run with no identity test gets no identity line" \
            "$FIXDIR/swift-testing-assertion.log" "the on-device reply for"
advice_never_says "the identity family is never on the known-flake list" \
            "$FIXDIR/unlisted-red.log" "KNOWN-FLAKE"
echo

echo "-- DET-D: the single automated re-roll fires on exactly one shape"
check "listed-only red + units green -> yes" \
      "yes" "$(gate_should_reroll "$FIXDIR/known-flake-red.log")"
check "listed-only red with NO Swift Testing pass line -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/known-flake-red-no-units.log")"
check "mixed listed+unlisted -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/known-flake-mixed.log")"
check "unlisted red -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/unlisted-red.log")"
check "runner death -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/runner-death-with-units.log")"
# The decision keys on the VERDICT, so this follows from the classifier rather
# than from a second rule kept in step by hand. It is pinned anyway: a
# truncated first run also makes the size check's expectation short, so a
# re-roll here would be a long run that fails for the opposite of its reason.
check "runner death naming a LISTED test -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/runner-death-listed.log")"
check "runner death naming a LISTED test, no ledger -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/runner-death-listed-no-ledger.log")"
check "a Swift Testing failure -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/swift-testing-assertion.log")"
check "a GREEN run -> no (there is nothing to re-roll)" \
      "no" "$(gate_should_reroll "$FIXDIR/xcui-green.log")"
check "a missing log -> no" \
      "no" "$(gate_should_reroll "$FIXDIR/does-not-exist.log")"
echo

echo "-- DET-D: the re-roll's own log is judged on positive markers AND its size"
check "clean re-roll of the whole bundle -> PASS" \
      "PASS" "$(gate_evaluate_reroll_log "$FIXDIR/reroll-green.log" 15 0 | head -1)"
check "the two-argument form (no exit status) still works" \
      "PASS" "$(gate_evaluate_reroll_log "$FIXDIR/reroll-green.log" 15 | head -1)"
check "a second red -> FAIL" \
      "FAIL" "$(gate_evaluate_reroll_log "$FIXDIR/reroll-red.log" 15 65 | head -1)"
check "green markers over a SHORT bundle -> FAIL" \
      "FAIL" "$(gate_evaluate_reroll_log "$FIXDIR/reroll-short.log" 15 0 | head -1)"
REROLL_SHORT_WHY="$(gate_evaluate_reroll_log "$FIXDIR/reroll-short.log" 15 0 | tail -n +2)"
check "the short re-roll says what it got and what it owed" \
      "yes" "$( [[ "$REROLL_SHORT_WHY" == *2* && "$REROLL_SHORT_WHY" == *15* ]] && echo yes || echo no )"
check "TEST SUCCEEDED over no ledger at all -> FAIL" \
      "FAIL" "$(gate_evaluate_reroll_log "$FIXDIR/reroll-no-ledger.log" 15 0 | head -1)"
check "a build failure -> FAIL" \
      "FAIL" "$(gate_evaluate_reroll_log "$FIXDIR/reroll-build-failed.log" 15 65 | head -1)"
check "a missing log -> FAIL" \
      "FAIL" "$(gate_evaluate_reroll_log "$FIXDIR/does-not-exist.log" 15 0 | head -1)"
check "every marker green but a NONZERO xcodebuild exit -> FAIL" \
      "FAIL" "$(gate_evaluate_reroll_log "$FIXDIR/reroll-green.log" 15 65 | head -1)"
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
# `ui-bundle-batch.sh` is in the list because the same rule binds it: it is an
# instrument a reader is told to act on. It is guarded rather than required —
# this check owns "no dead numbers in emitted text", not "these files exist",
# and a future lane retiring the batch instrument must not red the gate's
# preflight to do it.
for f in "$HERE/lane-gate.sh" "$HERE/lane-gate-classify.sh" "$HERE/ui-bundle-batch.sh"; do
    [[ -r "$f" ]] || continue
    # Every echo/printf argument string in the script, stripped of comments.
    n="$(grep -hoE '^[[:space:]]*(echo|printf)[[:space:]].*' "$f" | grep -coE '#[0-9]+' || true)"
    EMITTED_NUMS=$((EMITTED_NUMS + ${n:-0}))
done
check "emitted tracker numbers" "0" "$EMITTED_NUMS"
echo

echo "-- and the pointers that REPLACED them actually resolve"
# Dropping the item numbers only helps if what took their place finds the item.
# A grep hint that matches nothing is the same defect wearing a different hat,
# so every `grep … OPEN_ITEMS*.md` the scripts print is executed here.
#
# **BOTH tracker files, since 2026-09-02 (138-M's lane).** The check used to
# resolve every hint against `OPEN_ITEMS.md` alone, and to EXTRACT only hints
# naming that file — so the documented fix for a swept item (repoint the hint
# at `OPEN_ITEMS-ARCHIVE.md`, #313's shape) moved the hint out of the checker's
# sight instead of satisfying it. `CondenserFidelityTests` had been unverified
# on exactly that account since 2026-08-18. Resolving each hint against the
# file it NAMES is the only form of this check that a repoint cannot silence.
# (REPO_ROOT is resolved at the top of this file — the known-flake list's own
# resolution check below needs it too.)
ADVICE_LINES="$(grep -hoE '^[[:space:]]*(echo|printf)[[:space:]].*' \
    "$HERE/lane-gate.sh" "$HERE/lane-gate-classify.sh")"
HINTS=0
for tracker_name in OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md; do
    tracker="$REPO_ROOT/$tracker_name"
    tracker_re="${tracker_name//./\\.}"
    while IFS= read -r pat; do
        [[ -n "$pat" ]] || continue
        HINTS=$((HINTS+1))
        if [[ -s "$tracker" ]] && grep -q -- "$pat" "$tracker"; then
            PASS=$((PASS+1)); printf '  PASS  hint resolves: grep %s %s -> %s hit(s)\n' \
                "$pat" "$tracker_name" "$(grep -c -- "$pat" "$tracker")"
        else
            FAIL=$((FAIL+1)); printf '  FAIL  hint finds NOTHING in %s: %s\n' "$tracker_name" "$pat"
        fi
    done < <(
        printf '%s\n' "$ADVICE_LINES" \
        | grep -oE "grep -n '[^']+' ${tracker_re}|grep -n [A-Za-z0-9_]+ ${tracker_re}" \
        | sed -E "s/^grep -n '?//; s/'? ${tracker_re}\$//"
    )
done
check "advice emits at least one tracker pointer" "yes" "$( ((HINTS>0)) && echo yes || echo no )"
echo

echo "-- and every KNOWN-FLAKE entry resolves in the tracker file it names"
# The list is the only thing that can excuse a red, so an entry naming a test
# no tracker knows about is a red excused by nothing. Same discipline as the
# advice hints above, and for the same reason: each entry carries the file it
# resolves in, and it is checked against THAT file — a swept entry repointed at
# the archive must keep resolving, not fall out of sight.
KNOWN_ENTRIES=0
while IFS='|' read -r kf_kind kf_pat kf_tracker_name; do
    [[ -n "${kf_pat:-}" ]] || continue
    KNOWN_ENTRIES=$((KNOWN_ENTRIES+1))
    kf_tracker="$REPO_ROOT/$kf_tracker_name"
    if [[ -s "$kf_tracker" ]] && grep -q -- "$kf_pat" "$kf_tracker"; then
        PASS=$((PASS+1)); printf '  PASS  known-flake %s resolves: %s -> %s hit(s) in %s\n' \
            "$kf_kind" "$kf_pat" "$(grep -c -- "$kf_pat" "$kf_tracker")" "$kf_tracker_name"
    else
        FAIL=$((FAIL+1)); printf '  FAIL  known-flake %s finds NOTHING in %s: %s\n' \
            "$kf_kind" "$kf_tracker_name" "$kf_pat"
    fi
done < <(gate_known_flake_entries)
check "the known-flake list is non-empty" \
      "yes" "$( ((KNOWN_ENTRIES>0)) && echo yes || echo no )"
check "the known-flake list carries at least one TEST name" \
      "yes" "$( [[ -n "$(gate_known_flake_names)" ]] && echo yes || echo no )"
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
