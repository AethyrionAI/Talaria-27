#!/bin/bash
# lane-gate-classify.sh — the gate's failure-advice classifier (OPEN_ITEMS 300).
#
# Sourced by lane-gate.sh. Kept in its own file for one reason: the classifier
# must be testable WITHOUT running a twenty-minute suite, and the gate itself
# cannot be sourced for its side effects. `lane-gate-classify-test.sh` sources
# this file and drives it over recorded fixtures.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# The advice this replaces asked one question of the WHOLE log:
#
#     grep -qE '\.swift:[0-9]+: error:'   ->  "real"  else  "harness flake"
#
# That regex only knows the XCTest diagnostic shape
# (`File.swift:12: error: -[Suite test] : XCTAssertTrue failed`). Swift Testing
# does not print it. Swift Testing prints:
#
#     Test foo() recorded an issue at File.swift:157:9: Expectation failed: x
#
# — line AND column, and no `error:` token at all. So every Swift Testing
# failure in the project fell through to the else branch and was announced as
# an XCUITest harness flake with "NO assertion text", which is the exact
# opposite of the truth. Observed 2026-08-09: a real `Expectation failed:
# landed` in a Swift Testing unit test was labelled a flake and the reader was
# sent to a CLOSED tracker item about a different test. Following that advice
# literally re-rolls a genuine failure as noise.
#
# THE INVARIANT, and the reason for the fallback below: the safe direction of
# error is to call a flake real, never to call a real failure a flake. A real
# failure dressed as noise gets re-rolled until it hides; a flake dressed as
# real costs one wasted investigation. So anything this file cannot positively
# attribute is reported as REAL.
#
# THE OTHER RULE: no tracker item numbers in text a reader is told to act on.
# A shell script cannot keep an item number live — the number this advice used
# to print had been closed for five days. Advice names the FAMILY and tells the
# reader how to find its current home; provenance citations in comments (which
# describe history, and history does not go stale) are a different thing.
# ---------------------------------------------------------------------------

# A locus is a file:line a test framework attributed an issue to. Two shapes,
# and only these two — a bare `error:` match is worthless here because the
# simulator's own CoreData chatter prints hundreds of `[error] CoreData: error:`
# lines into the same log (884 of them in the 2026-08-09 fixture). That is the
# gate header's "grep -c error: counts sim runtime noise" trap, one level in.
GATE_LOCUS_RE='(recorded an issue at [^[:space:]]+\.swift:[0-9]+|[^[:space:]]+\.swift:[0-9]+(:[0-9]+)?: error:)'

# Reduce a "Failing tests:" entry to the bare function identifier.
#   "\tHTMLArtifactSandboxTests.controlArmWithoutRulesLeaksToTheListener()"
#     -> "controlArmWithoutRulesLeaksToTheListener"
#   "\tTalariaUITests.testPairedRelaunchSkipsPairingEntry()"
#     -> "testPairedRelaunchSkipsPairingEntry"
gate_bare_test_name() {
    local raw="$1"
    raw="${raw//$'\t'/ }"
    raw="${raw#"${raw%%[![:space:]]*}"}"   # ltrim
    raw="${raw%"${raw##*[![:space:]]}"}"   # rtrim
    raw="${raw%%(*}"                       # drop the argument list
    printf '%s' "${raw##*.}"               # drop the suite prefix
}

# The raw entries under "Failing tests:", one per line, blanks dropped.
#
# Every reader of that block went through the same two-stage sed and its own
# blank guard, and each new reader was one more chance to write a slightly
# different one. One definition, four callers.
# One sed, not three piped ones: this is called several times per classify and
# the classifier is called several times per gate run, so the process count is
# not free (measured in the self-test, which the gate runs in preflight).
gate_failing_test_lines() {   # gate_failing_test_lines <logfile>
    local log="$1"
    [[ -s "$log" ]] || return 0
    sed -n '/^Failing tests:/,/^$/{ /^Failing tests:/d; /^[[:space:]]*$/d; p; }' "$log"
}

# Echo the locus lines this log attributes to one test. Empty output == none.
#
# Matching is STRUCTURAL, not a substring search for the name: `grep -F name`
# would let `testFoo` collect `testFooBar`'s failures. Both forms below pin the
# identifier between fixed delimiters.
#
# One grep over the log rather than two, for the process-count reason given on
# gate_failing_test_lines. The two shapes are alternated, not merged: each
# alternative still pins the identifier between its own fixed delimiters.
gate_loci_for_test() {   # gate_loci_for_test <logfile> <bare-name>
    local log="$1" name="$2"
    [[ -s "$log" && -n "$name" ]] || return 0
    # Swift Testing:  ✘ Test <name>(…) recorded an issue at File.swift:L:C: …
    # XCTest:  /path/File.swift:L: error: -[Suite <name>] : XCTAssert… failed
    grep -hoE "Test ${name}\([^)]*\) recorded an issue at [^[:space:]]+\.swift:[0-9]+(:[0-9]+)?:.*|[^[:space:]]+\.swift:[0-9]+(:[0-9]+)?: error: -\[[^]]* ${name}\].*" \
        "$log" 2>/dev/null | sort -u
}

# Does the log carry ANY attributable locus at all?
gate_log_has_any_locus() {   # gate_log_has_any_locus <logfile>
    local log="$1"
    [[ -s "$log" ]] || return 1
    grep -qE "$GATE_LOCUS_RE" "$log"
}

# ---------------------------------------------------------------------------
# THE KNOWN-FLAKE LIST.
#
# A NAMED, SMALL, AUDITED set of tests whose reds this gate is permitted to
# treat as noise — and the only thing in this file that can excuse a failure.
# It exists because the locus rule above, which is right about everything else,
# is exactly wrong here.
#
# `testConnectedRelaunchSkipsTheConnectEntry` and its two sibling connect and
# disconnect journeys fail on a SWALLOWED TAP: the runner reports the event
# synthesized (and, on the measured red, a hit point of {-1, -1}), the app
# never receives it, and the assertion that trips is about the state AFTER the
# tap that did not happen. So the failure carries a locus, the classifier read
# it as `assertion`, and the advice printed "Do NOT re-roll it" — over the one
# family whose standing protocol is precisely ONE re-roll. Roughly one run in
# ten, at 35-40 minutes a red, the gate told the reader to do the opposite of
# the rule.
#
# THE LIST IS THE HAZARD, and it is kept in this shape to bound it:
#
#   * it excuses a run ONLY when every failing test is on it. One unlisted
#     failure and the ordinary logic applies untouched. The list can never
#     hide a red it did not fully account for.
#   * it buys exactly one re-run over identical bytes. A second red is a real
#     red. Nothing here can excuse a failure twice.
#   * every entry carries the tracker file its search string resolves in, and
#     the self-test greps THAT file for THAT string on every run. An entry
#     naming a test no tracker knows about is a red excused by nothing, so it
#     fails the gate in preflight rather than quietly widening.
#   * a test that stops being a flake must come OFF the list. Nothing
#     automatic will notice; that is the standing cost of having one.
#
# Format: <kind>|<search string>|<tracker file the string resolves in>
#   test   a bare test identifier, matched against the failing set
#   hint   a tracker header phrase the advice prints as a grep, carried here
#          so it is resolved by the same check rather than a separate one
KNOWN_FLAKE_TESTS=(
    "test|testConnectedRelaunchSkipsTheConnectEntry|OPEN_ITEMS-ARCHIVE.md"
    "test|testConnectingAHostViaSettingsEntryPointLandsBackInChat|OPEN_ITEMS-ARCHIVE.md"
    "test|testDisconnectingAHostReturnsToStandaloneChat|OPEN_ITEMS-ARCHIVE.md"
    "hint|runner dies mid-bundle|OPEN_ITEMS-ARCHIVE.md"
)

# Every entry, verbatim, for the self-test's resolution loop.
#
# The emptiness guard is not decoration: under `set -u` on bash 3.2 — which is
# what /bin/bash is on this Mac — expanding an empty array is an "unbound
# variable" error, so an emptied list would abort the caller instead of
# reporting zero entries. The mutation that empties this list must produce
# FAILING CHECKS, not a dead script.
gate_known_flake_entries() {
    (( ${#KNOWN_FLAKE_TESTS[@]} > 0 )) || return 0
    printf '%s\n' "${KNOWN_FLAKE_TESTS[@]}"
}

# Just the test identifiers, one per line.
gate_known_flake_names() {
    local entry rest
    (( ${#KNOWN_FLAKE_TESTS[@]} > 0 )) || return 0
    for entry in "${KNOWN_FLAKE_TESTS[@]}"; do
        [[ "${entry%%|*}" == "test" ]] || continue
        rest="${entry#*|}"
        printf '%s\n' "${rest%%|*}"
    done
}

# Is this bare test name listed? Exact match, never a substring: `testFoo` must
# not inherit `testFooBar`'s excuse any more than it inherits its locus.
#
# Walks the array directly rather than reading `gate_known_flake_names` — this
# is called once per failing test and the classifier is called several times
# per gate run, and a process substitution per call was measurably the whole
# cost of the new verdict in the self-test.
gate_is_known_flake_test() {   # gate_is_known_flake_test <bare-name>
    local want="$1" entry rest
    [[ -n "$want" ]] || return 1
    (( ${#KNOWN_FLAKE_TESTS[@]} > 0 )) || return 1
    for entry in "${KNOWN_FLAKE_TESTS[@]}"; do
        [[ "${entry%%|*}" == "test" ]] || continue
        rest="${entry#*|}"
        [[ "${rest%%|*}" == "$want" ]] && return 0
    done
    return 1
}

# The comma-joined bare names of everything in the failing set. For the line
# the gate prints when it re-rolls — the reader must be told WHICH tests were
# excused, or the re-roll is an unattributed act.
gate_failing_test_names() {   # gate_failing_test_names <logfile>
    local log="$1" line name out=""
    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        name="$(gate_bare_test_name "$line")"
        [[ -n "$name" ]] || continue
        if [[ -z "$out" ]]; then out="$name"; else out="$out, $name"; fi
    done < <(gate_failing_test_lines "$log")
    printf '%s' "$out"
}

# The classifier. Echoes exactly one token for the whole run:
#
#   known-flake    the failing set is non-empty and EVERY member of it is on
#                  the list above -> one re-roll over identical bytes, and a
#                  locus does not override this (see the list's comment)
#   assertion      at least one failing test has a locus -> a REAL failure
#   unattributed   no failing test has a locus, but the log holds loci anyway
#                  (display-named tests, a name shape not parsed here) -> also
#                  treated as REAL; see the invariant above
#   runner-flake   no locus anywhere in the log for anything -> the signature
#                  of the UI-test runner dying or restarting mid-bundle
#   unknown        no failing-test list to reason about
#
# `known-flake` is tested FIRST and on the whole set, which is what makes the
# safe direction hold in both directions at once: it can only fire when there
# is nothing else in the run to be wrong about, and everything it does not
# fire on falls through to the pre-existing logic byte for byte.
gate_classify_failures() {   # gate_classify_failures <logfile>
    local log="$1" line name saw_any=0 all_known=1
    [[ -s "$log" ]] || { printf 'unknown'; return; }

    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        saw_any=1
        name="$(gate_bare_test_name "$line")"
        gate_is_known_flake_test "$name" || all_known=0
    done < <(gate_failing_test_lines "$log")

    if (( ! saw_any )); then printf 'unknown'; return; fi
    if (( all_known )); then printf 'known-flake'; return; fi

    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        name="$(gate_bare_test_name "$line")"
        if [[ -n "$(gate_loci_for_test "$log" "$name")" ]]; then
            printf 'assertion'
            return
        fi
    done < <(gate_failing_test_lines "$log")

    if gate_log_has_any_locus "$log"; then printf 'unattributed'; return; fi
    printf 'runner-flake'
}

# ---------------------------------------------------------------------------
# THE XCUITEST COUNT.
#
# Lives here, beside the classifier, for the same reason the classifier does:
# it must be testable in a second instead of behind a twenty-minute suite.
# `lane-gate.sh` calls it; `lane-gate-classify-test.sh` drives it over recorded
# fixtures.
#
# WHAT THIS REPLACES, and why the replacement is not a tidy-up. The count used
# to be the MAX number on any line reading `Executed N tests, with 0 failures`.
# On a GREEN run that is right. On a RED run the phrase is not printed for the
# sub-suite that failed, so the number fell through to whichever sub-suite
# happened to be clean — on 2026-09-01 the two-test launch suite — and the gate
# announced "XCUITest tests run — 2" over a bundle of fifteen that had run to
# completion, 14 passed and 1 failed.
#
# That is worse than a wrong number. "2 of a 15-test bundle" is the exact
# signature of the runner being lost mid-bundle, so the line read as a harness
# flake and misdirected the overnight diagnosis twice before someone counted
# the Test Case lines by hand. A counter that is only correct when everything
# passed is a counter that lies precisely when it is being read hardest.
#
# So count the ledger XCTest actually prints, one line per start and one per
# outcome:
#
#   Test Case '-[TalariaUITests.TalariaUITests testChatSendFlow]' started.
#   Test Case '-[TalariaUITests.TalariaUITests testChatSendFlow]' passed (11.164 seconds).
#
# LINES, never unique names: the launch suite runs `testLaunch` twice under two
# configurations and both are real executions.
# ---------------------------------------------------------------------------

# The raw tally. Echoes three integers: started, passed, failed.
gate_xcuitest_ledger() {   # gate_xcuitest_ledger <logfile>
    local log="$1" started passed failed
    if [[ ! -s "$log" ]]; then printf '0 0 0'; return; fi
    started="$(grep -cE "^Test Case '-\[.*\]' started" "$log")"
    passed="$( grep -cE "^Test Case '-\[.*\]' passed"  "$log")"
    failed="$( grep -cE "^Test Case '-\[.*\]' failed"  "$log")"
    printf '%s %s %s' "${started:-0}" "${passed:-0}" "${failed:-0}"
}

# Echo the count/summary to print after the label. Empty output means "nothing
# countable in this log", which the caller must treat as a FAIL.
#
# A clean bundle prints the bare number and nothing else — byte-identical to
# what this gate has printed since it was written, so no historical PASS count
# changes meaning. Anything else prints all three figures, which is what lets a
# reader tell 14-passed-1-failed apart from 10-reported-of-15-started.
gate_xcuitest_summary() {   # gate_xcuitest_summary <logfile>
    local started passed failed
    read -r started passed failed <<<"$(gate_xcuitest_ledger "$1")"
    if (( started == 0 )); then return 0; fi
    if (( failed == 0 && passed == started )); then
        printf '%s' "$passed"
        return 0
    fi
    printf '%s passed / %s failed / %s ran' "$passed" "$failed" "$started"
}

# ---------------------------------------------------------------------------
# THE SINGLE AUTOMATED RE-ROLL.
#
# The DECISION and the EVALUATION live here, beside the classifier, for the
# same reason everything else in this file does: a gate that re-runs itself is
# the last thing that should only be testable by running it. `lane-gate.sh`
# owns exactly two things — asking, and invoking xcodebuild. Every rule about
# WHEN and about what counts as a clean second run is exercised over recorded
# fixtures in about a second.
#
# The protocol is not new and this does not change it: on a named flake,
# re-run ONCE over identical bytes, keep BOTH logs, and a second red is a real
# red. What changed is who performs the re-run.
# ---------------------------------------------------------------------------

# The Swift Testing pass count, or empty when the run did not report one.
#
# Deliberately NOT the gate's `require_count` helper, which takes the MAX over
# every number on the matched line and can therefore return the SUITE count.
# That is harmless for a `> 0` report and would be wrong here, where the answer
# gates an automated re-run: extract the capture group.
gate_swift_testing_passed_count() {   # gate_swift_testing_passed_count <logfile>
    local log="$1"
    [[ -s "$log" ]] || return 0
    grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites passed' "$log" \
        | sed -E 's/^Test run with ([0-9]+) tests.*/\1/' | sort -rn | head -1
}

# May the gate re-roll this suite log? Echoes `yes` or `no` — three conditions,
# all required:
#
#   a. there is a failing-test list at all;
#   b. the verdict is `known-flake` — so every failing test is named on the
#      list above, and one unlisted failure disqualifies the whole run;
#   c. the Swift Testing run PASSED, with a count greater than zero.
#
# (c) is the load-bearing one and it is cheap to get wrong. The units run
# before the UI target in the scheme, so on a UI-only red that line is always
# present; a Swift Testing red therefore CANNOT reach a re-roll, which is the
# rule that keeps this from ever re-running a genuine unit failure. And the
# count must be non-zero for the same reason every other count in this gate
# must be: `Test run with 0 tests in 0 suites passed` is a marker a no-op
# satisfies.
gate_should_reroll() {   # gate_should_reroll <suite.log>
    local log="$1" units
    [[ -s "$log" ]] || { printf 'no'; return; }
    grep -q '^Failing tests:' "$log" || { printf 'no'; return; }
    [[ "$(gate_classify_failures "$log")" == "known-flake" ]] || { printf 'no'; return; }
    units="$(gate_swift_testing_passed_count "$log")"
    [[ -n "$units" ]] || { printf 'no'; return; }
    (( units > 0 )) || { printf 'no'; return; }
    printf 'yes'
}

# Judge the re-roll's own log. Prints `PASS` or `FAIL` on the first line, and
# on a FAIL one indented reason per line after it.
#
#   gate_evaluate_reroll_log <suite-reroll.log> <expected_total> [xcodebuild-status]
#
# The same positive-marker discipline as every other check here, minus one
# thing and plus one thing:
#
#   MINUS: the re-roll runs `-only-testing:TalariaUITests`, so it has no Swift
#   Testing summary line at all. Requiring one would fail every good re-roll.
#
#   PLUS: the bundle that came back must be the SAME SIZE as the one that
#   failed. This is the check with no counterpart in the first run, and it is
#   the one that matters most: a `-only-testing` argument that resolved to a
#   subset — a renamed target, a scheme edit — would re-run two tests, pass,
#   and clear a red over thirteen tests nobody ran. A count that is merely
#   greater than zero cannot see that.
#
# The exit status is optional so the two-argument form stays driveable from
# fixtures, and is checked when given because a nonzero exit is disqualifying
# on its own (the gate's oldest correction).
gate_evaluate_reroll_log() {
    local log="$1" expected="${2:-}" status="${3:-0}"
    local reasons="" started passed failed
    if [[ ! -s "$log" ]]; then
        printf 'FAIL\n'
        printf '  the re-roll log is empty or missing (%s)\n' "$log"
        return
    fi
    if (( status != 0 )); then
        reasons="${reasons}  xcodebuild exited ${status}"$'\n'
    fi
    if grep -qE '\*\* TEST FAILED \*\*|\*\* TEST BUILD FAILED \*\*' "$log"; then
        reasons="${reasons}  the log carries an explicit failure marker"$'\n'
    fi
    if ! grep -qE '\*\* TEST SUCCEEDED \*\*' "$log"; then
        reasons="${reasons}  no ** TEST SUCCEEDED ** marker — absence of a failure marker is not success"$'\n'
    fi
    if grep -q '^Failing tests:' "$log"; then
        reasons="${reasons}  a failing-test list is present: $(gate_failing_test_names "$log")"$'\n'
    fi
    # An unreadable expected total must never be treated as "nothing to
    # compare against". A zero expectation would make any bundle the right
    # size, which is the count-of-zero trap wearing a different hat.
    if ! [[ "$expected" =~ ^[0-9]+$ ]] || (( expected == 0 )); then
        reasons="${reasons}  the first run's XCUITest total was not readable ('${expected}'), so the re-roll's size cannot be checked"$'\n'
    fi
    read -r started passed failed <<<"$(gate_xcuitest_ledger "$log")"
    if (( started == 0 )); then
        reasons="${reasons}  no per-test ledger at all — zero is not a count"$'\n'
    elif (( failed != 0 || passed != started )); then
        reasons="${reasons}  the ledger did not come back clean: ${passed} passed / ${failed} failed / ${started} ran"$'\n'
    elif [[ "$expected" =~ ^[0-9]+$ ]] && (( expected > 0 && passed != expected )); then
        reasons="${reasons}  the re-roll ran ${passed} test(s) where the first run ran ${expected} — a smaller bundle cannot clear a red over the tests it never ran"$'\n'
    fi
    if [[ -z "$reasons" ]]; then printf 'PASS\n'; return; fi
    printf 'FAIL\n'
    printf '%s' "$reasons"
}

# Print the per-test breakdown plus the verdict-specific advice.
gate_print_failure_advice() {   # gate_print_failure_advice <logfile>
    local log="$1" line name loci verdict identity_named=0

    verdict="$(gate_classify_failures "$log")"

    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        name="$(gate_bare_test_name "$line")"
        case "$line" in *MessageIdentityUITests*) identity_named=1 ;; esac
        printf '        %s\n' "$(printf '%s' "$line" | tr -d '\t')"
        loci="$(gate_loci_for_test "$log" "$name")"
        if [[ -n "$loci" ]]; then
            printf '%s\n' "$loci" | sed 's/^/          ASSERTION  /'
        else
            printf '          (no assertion locus attributed to this test)\n'
        fi
    done < <(gate_failing_test_lines "$log")

    case "$verdict" in
        assertion)
            echo "        ^ ASSERTION TEXT PRESENT — treat this as a REAL failure."
            echo "          Do NOT re-roll it. Swift Testing prints its issues as"
            echo "          \"recorded an issue at File.swift:LINE:COL\" with no"
            echo "          \"error:\" token, so a real unit failure looks nothing"
            echo "          like a compiler diagnostic — that is what this reads."
            # The message-identity family has a rule of its own, and it is the
            # opposite of a re-roll: NAME THE CAUSE FIRST. Its entry carries a
            # transcript-dump recipe that says which reply actually landed, and
            # reading that before touching anything is what keeps a duplicate-ID
            # regression from being re-run until it hides.
            if (( identity_named )); then
                echo "          One of these is in the message-identity family, whose"
                echo "          own rule is to NAME THE CAUSE FIRST: dump the"
                echo "          transcript and read which reply actually landed"
                echo "          before changing anything. The recipe lives with its"
                echo "          entry — find it with:"
                echo "              grep -n 'the on-device reply for' OPEN_ITEMS-ARCHIVE.md"
            fi
            ;;
        known-flake)
            echo "        ^ EVERY failing test above is on this gate's KNOWN-FLAKE"
            echo "          list: the swallowed-first-tap family, whose journeys die"
            echo "          on a tap the runner reports as synthesized and the app"
            echo "          never receives. Any assertion quoted above is about the"
            echo "          state AFTER that tap, so its presence is expected here"
            echo "          and is not evidence that the product broke."
            echo "          PROTOCOL: re-run the UI target ONCE over IDENTICAL BYTES,"
            echo "          keep BOTH logs, and a second red is a REAL red — not a"
            echo "          third roll. This gate performs that one re-run itself"
            echo "          when the unit suite passed; if it did not, the units are"
            echo "          what to read, and this list has no say over them."
            echo "          Find the family's live entry with:"
            echo "              grep -n 'runner dies mid-bundle' OPEN_ITEMS-ARCHIVE.md"
            echo "          (a SEARCH STRING, not an item number — this script cannot"
            echo "          keep a number live, and the ones it used to print had"
            echo "          been closed for days by the time anyone followed one.)"
            echo "          The list is DATA, not a judgement: a test that stops"
            echo "          being a flake has to come off it by hand, or this gate"
            echo "          will go on excusing a real red."
            ;;
        unattributed)
            echo "        ^ ASSERTION TEXT IS PRESENT IN THE LOG but could not be"
            echo "          attributed to a named failing test (a display-named"
            echo "          test, or a name shape this classifier does not parse)."
            echo "          Treat as a REAL failure and read the log — the safe"
            echo "          direction is never to call a real failure a flake."
            ;;
        runner-flake)
            echo "        ^ NO assertion locus anywhere in the log — the signature"
            echo "          of the XCUITest RUNNER being lost or restarted, which"
            echo "          marks every test in the bundle failed without recording"
            echo "          an issue against any of them."
            echo "          Re-run ONCE and RECORD BOTH runs against the"
            echo "          XCUITest-runner-flake family on the tracker — find its"
            echo "          live entry with:"
            echo "              grep -n 'runner dies mid-bundle' OPEN_ITEMS-ARCHIVE.md"
            echo "          (deliberately NOT a hardcoded item number: this script"
            echo "          cannot keep one live, and the number it used to print"
            echo "          had been closed for five days.)"
            echo "          Do not re-run until green and report only the green one."
            ;;
        *)
            echo "        ^ could not read a failing-test list — read the log directly."
            ;;
    esac
}
