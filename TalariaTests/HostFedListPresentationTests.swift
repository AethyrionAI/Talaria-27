import Testing
@testable import Talaria

/// #180 — the empty-list branch decision shared by the three host-fed list
/// screens (Skills, Tasks, Insights). The screens previously hand-rolled an
/// identical `!hasLoaded` gate on the error state, which hid any failure
/// that arrived AFTER a successful empty load: the screen claimed "the host
/// has no X" when the truth was "the host did not answer."
struct HostFedListPresentationTests {

    @Test func firstLoadInFlightShowsLoading() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: false, errorMessage: nil
        )
        #expect(state == .loading)
    }

    @Test func retryInFlightBeforeFirstSuccessStillShowsLoading() {
        // A failed first load leaves a message; the retry's spinner wins
        // while it runs — pins the pre-#180 behavior.
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: false, errorMessage: "Host offline."
        )
        #expect(state == .loading)
    }

    @Test func failureBeforeFirstLoadShowsTheError() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: false, errorMessage: "Host offline."
        )
        #expect(state == .error("Host offline."))
    }

    /// THE #180 case — the one the hand-rolled gate got wrong: a failure
    /// after a successful empty load must be visible, not silently rendered
    /// as "the host has no X."
    @Test func failureAfterASuccessfulEmptyLoadShowsTheErrorNotEmpty() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: true, errorMessage: "Host offline."
        )
        #expect(state == .error("Host offline."))
    }

    @Test func loadedCleanAndEmptyShowsEmpty() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: true, errorMessage: nil
        )
        #expect(state == .empty)
    }

    @Test func refreshInFlightOverACleanEmptyLoadStaysEmpty() {
        // No spinner flash on refresh — rows-or-empty stays put while a
        // refresh runs; only the FIRST load shows the spinner.
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: true, errorMessage: nil
        )
        #expect(state == .empty)
    }

    @Test func refreshInFlightAfterAFailureKeepsShowingTheError() {
        let state = HostFedListPresentation.emptyBranchState(
            isLoading: true, hasLoaded: true, errorMessage: "Host offline."
        )
        #expect(state == .error("Host offline."))
    }
}
