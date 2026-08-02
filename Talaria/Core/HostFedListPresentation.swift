import Foundation

/// #180 — THE CONVENTION for any surface fed from a Hermes host: one shared
/// answer to "what does a surface show when the thing behind it is
/// unavailable, and how does the user find out?" The umbrella exists
/// because four surfaces answered it independently and three answered it
/// wrong the same way. A new host-fed screen follows these four rules:
///
/// 1. **Rows on screen survive a failed refresh.** The store keeps its
///    content and only surfaces the message (every store's hard rule).
/// 2. **A failure is always visible** — `refreshFailedStrip` above live
///    rows, or the error state in the empty branch below. Never gate it
///    behind "first load only": that gate hid every later failure (#180's
///    third instance).
/// 3. **Data is stamped.** `lastRefreshedAt` renders "as of HH:mm" so a
///    load-time snapshot is never presented as live.
/// 4. **Stores are profile-scoped.** A host switch returns them to
///    never-loaded (`reset()`, wired from
///    `AppContainer.handleActiveProfileChanged`), so no surface can offer
///    Host A's rows against Host B.
///
/// This enum owns rule 2's empty-branch decision, which the three list
/// screens (Skills, Tasks, Insights) previously hand-rolled with an
/// identical — identically wrong — `!hasLoaded` gate on the error state.
enum HostFedListPresentation {
    enum EmptyBranchState: Equatable {
        case loading
        case error(String)
        case empty
    }

    /// The state to render when the store has no rows to show.
    ///
    /// The first load's spinner outranks a stale failure message while a
    /// retry runs; after ANY completed load, a present `errorMessage` is
    /// rendered — `hasLoaded` no longer suppresses it, because a failure
    /// after a successful empty load is "the host did not answer," never
    /// "the host has no rows."
    static func emptyBranchState(
        isLoading: Bool,
        hasLoaded: Bool,
        errorMessage: String?
    ) -> EmptyBranchState {
        if isLoading, !hasLoaded { return .loading }
        if let errorMessage { return .error(errorMessage) }
        return .empty
    }
}
