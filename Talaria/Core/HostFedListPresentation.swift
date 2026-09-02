import Foundation

/// #180 — THE CONVENTION for any surface fed from a Hermes host: one shared
/// answer to "what does a surface show when the thing behind it is
/// unavailable, and how does the user find out?" The umbrella exists
/// because four surfaces answered it independently and three answered it
/// wrong the same way. A new host-fed screen follows these four rules —
/// and **rule 5, added 2026-08-09, is wider than host-fed lists: it is the
/// review rule for ANY seam that renders state the app does not own.**
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
/// 5. **UNKNOWN GETS ITS OWN BRANCH — the review rule (added 2026-08-09,
///    lane 180-L).** *Every expression that renders external state must be
///    able to produce THREE outcomes, and UNKNOWN must be the DEFAULT
///    branch, not the `else` branch.*
///
///    **Rules 1–4 are about host-fed LISTS; rule 5 is wider than this
///    file's title** — it governs any seam where the app renders state it
///    does not own: a Hermes host, an OS permission, a framework's async
///    lifecycle, a stream that may never end, a model that may not have
///    seen the image. In every one of those the app has three possible
///    answers — *yes*, *no*, and *I have not been told* — and the render
///    habitually has two branches, with UNKNOWN landing on the affirmative
///    side. That is #180's whole thesis.
///
///    **How to apply it:** point at the boolean, the latch, the `??`, or
///    the `else` sitting between what the app knows and what it draws, and
///    ask **"what does this draw when the answer never arrived?"** If the
///    answer is the same pixels as success, it is an instance.
///
///    **The four forms it takes, each with its verified instance:**
///    - **the monotonic latch** — a success flag that only ever rises,
///      used to gate the failure message:
///      `else if let message = store.lastErrorMessage, !store.hasLoaded`
///      (#180 instance 3 — three screens, identically wrong; rule 2 above
///      and `emptyBranchState` are its fix).
///    - **the collapsing `else`** — `if running { … } else { done }`, where
///      `else` is the whole rest of the universe: a tool in flight when
///      Stop is tapped falls out of `isStreaming` and draws a ✓ (#296).
///    - **the optimistic default** — a stored property whose declared
///      default is the affirmative value, corrected only if some producer
///      bothers to stamp it: `var engine: VoiceEngine = .realtime`
///      (`VoiceState.swift`) named an engine before one had been selected
///      (#139 residual).
///    - **the substitution fallback** — a missing value replaced by a
///      *different* value from the same row rather than marked absent:
///      `title ?? preview` printed the drawer row's one line twice
///      (#177 / #280); `model_snapshot` under the label "Model" (#170a).
///
///    **Corollary — a fallback may NARROW a claim; it may never SUBSTITUTE
///    a different one.** `title ?? "—"` narrows. `title ?? preview`
///    substitutes, and substitution is how a UI comes to assert something
///    no layer beneath it ever said.
///
///    **The rule is SYMMETRIC — it does not say "prefer the pessimistic
///    branch."** Collapsing unknown onto *"Not Set"* for a permission the
///    framework will not report is the same defect with the sign flipped;
///    a fix that just moves defaults from optimistic to pessimistic ships
///    the next instance.
///
///    **In-repo precedent, and the reason rule 5 is written here rather
///    than left in one file's doc comment:**
///    `LocalIntelligenceService.fallbackCard` (`:452-458`) solved exactly
///    this for the on-device card on 2026-07-11 — *"Give the preview a
///    DISTINCT source … a title-only card is honest; two copies of one
///    line is not."* It was never generalized, and the server-fed drawer
///    row reproduced the same render for a month.
///
/// This enum owns rule 2's empty-branch decision, which the three list
/// screens (Skills, Tasks, Insights) previously hand-rolled with an
/// identical — identically wrong — `!hasLoaded` gate on the error state.
/// Rule 5 has no single call site by design: it is a review rule, and the
/// type is deliberately NOT renamed to match its wider scope (three call
/// sites, and a rename buries the diff).
enum HostFedListPresentation {
    enum EmptyBranchState: Equatable {
        case loading
        /// **#180-CONVENTION (2026-09-01): the CLASSIFICATION, not words.**
        /// This case used to carry the store's raw `lastErrorMessage`, which
        /// meant every screen printed whatever string a service error happened
        /// to hold. Carrying the rung instead makes the shared vocabulary the
        /// only route from an observed failure to on-screen words —
        /// structurally, not by convention.
        case error(HostFailureKind)
        case empty
    }

    /// The state to render when the store has no rows to show.
    ///
    /// The first load's spinner outranks a stale failure while a retry runs;
    /// after ANY completed load, a present `failure` is rendered —
    /// `hasLoaded` no longer suppresses it, because a failure after a
    /// successful empty load is "the host did not answer," never "the host has
    /// no rows."
    static func emptyBranchState(
        isLoading: Bool,
        hasLoaded: Bool,
        failure: HostFailureKind?
    ) -> EmptyBranchState {
        if isLoading, !hasLoaded { return .loading }
        if let failure { return .error(failure) }
        return .empty
    }
}
