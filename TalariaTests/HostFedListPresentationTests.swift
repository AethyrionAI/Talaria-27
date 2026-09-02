import Testing
@testable import Talaria

/// #180 — the empty-list branch decision shared by the three host-fed list
/// screens (Skills, Tasks, Insights). The screens previously hand-rolled an
/// identical `!hasLoaded` gate on the error state, which hid any failure
/// that arrived AFTER a successful empty load: the screen claimed "the host
/// has no X" when the truth was "the host did not answer."
///
/// **2026-09-01 (#180-CONVENTION):** the branch now carries the CLASSIFIED
/// failure rather than a raw message string, so the words a screen shows can
/// only come from `HostFailurePresentation`. The seven decisions below are
/// unchanged — this file was retyped against the new payload, not
/// re-specified, and `keyRefused` stands in for the string the rows used to
/// pass.
struct HostFedListPresentationTests {

    @Test func firstLoadInFlightShowsLoading() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: false, failure: nil
        )
        #expect(state == .loading)
    }

    @Test func retryInFlightBeforeFirstSuccessStillShowsLoading() {
        // A failed first load leaves a failure; the retry's spinner wins
        // while it runs — pins the pre-#180 behavior.
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: false, failure: .noAnswer
        )
        #expect(state == .loading)
    }

    @Test func failureBeforeFirstLoadShowsTheError() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: false, failure: .noAnswer
        )
        #expect(state == .error(.noAnswer))
    }

    /// THE #180 case — the one the hand-rolled gate got wrong: a failure
    /// after a successful empty load must be visible, not silently rendered
    /// as "the host has no X."
    @Test func failureAfterASuccessfulEmptyLoadShowsTheErrorNotEmpty() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: true, failure: .noAnswer
        )
        #expect(state == .error(.noAnswer))
    }

    @Test func loadedCleanAndEmptyShowsEmpty() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: true, failure: nil
        )
        #expect(state == .empty)
    }

    @Test func refreshInFlightOverACleanEmptyLoadStaysEmpty() {
        // No spinner flash on refresh — rows-or-empty stays put while a
        // refresh runs; only the FIRST load shows the spinner.
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: true, failure: nil
        )
        #expect(state == .empty)
    }

    @Test func refreshInFlightAfterAFailureKeepsShowingTheError() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: true, failure: .noAnswer
        )
        #expect(state == .error(.noAnswer))
    }

    /// #180-CONVENTION: the branch preserves WHICH failure, so the screen can
    /// name the rung. Collapsing every rung onto one rendering is the defect
    /// this umbrella's fourth rule exists to stop.
    @Test func theBranchPreservesTheRungItWasGiven() {
        for kind in HostFailureKind.allCases {
            #expect(HostFedListPresentation.emptyBranchState(
                isLoading: false, hasLoaded: true, failure: kind) == .error(kind))
        }
    }
}
