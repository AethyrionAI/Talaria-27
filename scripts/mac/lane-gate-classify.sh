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

# Echo the locus lines this log attributes to one test. Empty output == none.
#
# Matching is STRUCTURAL, not a substring search for the name: `grep -F name`
# would let `testFoo` collect `testFooBar`'s failures. Both forms below pin the
# identifier between fixed delimiters.
gate_loci_for_test() {   # gate_loci_for_test <logfile> <bare-name>
    local log="$1" name="$2"
    [[ -s "$log" && -n "$name" ]] || return 0
    {
        # Swift Testing:  ✘ Test <name>(…) recorded an issue at File.swift:L:C: …
        grep -hoE "Test ${name}\([^)]*\) recorded an issue at [^[:space:]]+\.swift:[0-9]+(:[0-9]+)?:.*" "$log"
        # XCTest:  /path/File.swift:L: error: -[Suite <name>] : XCTAssert… failed
        grep -hoE "[^[:space:]]+\.swift:[0-9]+(:[0-9]+)?: error: -\[[^]]* ${name}\].*" "$log"
    } 2>/dev/null | sort -u
}

# Does the log carry ANY attributable locus at all?
gate_log_has_any_locus() {   # gate_log_has_any_locus <logfile>
    local log="$1"
    [[ -s "$log" ]] || return 1
    grep -qE "$GATE_LOCUS_RE" "$log"
}

# The classifier. Echoes exactly one token for the whole run:
#
#   assertion      at least one failing test has a locus -> a REAL failure
#   unattributed   no failing test has a locus, but the log holds loci anyway
#                  (display-named tests, a name shape not parsed here) -> also
#                  treated as REAL; see the invariant above
#   runner-flake   no locus anywhere in the log for anything -> the signature
#                  of the UI-test runner dying or restarting mid-bundle
#   unknown        no failing-test list to reason about
gate_classify_failures() {   # gate_classify_failures <logfile>
    local log="$1" line name saw_any=0
    [[ -s "$log" ]] || { printf 'unknown'; return; }

    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        saw_any=1
        name="$(gate_bare_test_name "$line")"
        if [[ -n "$(gate_loci_for_test "$log" "$name")" ]]; then
            printf 'assertion'
            return
        fi
    done < <(sed -n '/^Failing tests:/,/^$/p' "$log" | sed '1d')

    if (( ! saw_any )); then printf 'unknown'; return; fi
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
# THIS IS THE PRE-FIX BEHAVIOUR, EXTRACTED VERBATIM so the self-test can watch
# it fail. It is the gate's own long-standing grep: take the MAX number on any
# line reading `Executed N tests, with 0 failures`. A run with a FAILING test
# does not print that phrase for the suite that failed, so the number falls
# through to whichever sub-suite happened to be clean.
# ---------------------------------------------------------------------------

# Echo the count/summary to print after the label. Empty output means "nothing
# countable in this log", which the caller must treat as a FAIL.
gate_xcuitest_summary() {   # gate_xcuitest_summary <logfile>
    local log="$1" n
    [[ -s "$log" ]] || return 0
    n="$(grep -oE 'Executed [0-9]+ tests?, with 0 failures' "$log" \
         | grep -oE '[0-9]+' | sort -rn | head -1)"
    [[ -n "$n" ]] || return 0
    printf '%s' "$n"
}

# Print the per-test breakdown plus the verdict-specific advice.
gate_print_failure_advice() {   # gate_print_failure_advice <logfile>
    local log="$1" line name loci verdict

    verdict="$(gate_classify_failures "$log")"

    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        name="$(gate_bare_test_name "$line")"
        printf '        %s\n' "$(printf '%s' "$line" | tr -d '\t')"
        loci="$(gate_loci_for_test "$log" "$name")"
        if [[ -n "$loci" ]]; then
            printf '%s\n' "$loci" | sed 's/^/          ASSERTION  /'
        else
            printf '          (no assertion locus attributed to this test)\n'
        fi
    done < <(sed -n '/^Failing tests:/,/^$/p' "$log" | sed '1d')

    case "$verdict" in
        assertion)
            echo "        ^ ASSERTION TEXT PRESENT — treat this as a REAL failure."
            echo "          Do NOT re-roll it. Swift Testing prints its issues as"
            echo "          \"recorded an issue at File.swift:LINE:COL\" with no"
            echo "          \"error:\" token, so a real unit failure looks nothing"
            echo "          like a compiler diagnostic — that is what this reads."
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
            echo "              grep -n 'runner dies mid-bundle' OPEN_ITEMS.md"
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
