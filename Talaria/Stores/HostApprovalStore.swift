import Foundation
import os

/// #304 (Phase 3 slice 3B): the store behind `HostApprovalCard` — at most ONE
/// live host approval, answered over `POST /v1/runs/{run_id}/approval`.
///
/// **A sibling of `ToolConfirmationCenter` (#29), deliberately NOT a reuse of
/// it** (dispatch §5): that gate suspends a Swift continuation for a tool on
/// THIS phone, defaults closed, and auto-declines a second concurrent request
/// — semantics that would silently DROP a host approval arriving while a
/// device card is up. A host approval is a network round trip against a run
/// id with a server-side deadline; none of the continuation model transfers,
/// and the two cards can be on screen at the same moment.
///
/// Lifecycle rules, each pinned by a bar:
/// - A QUESTION is only ever raised from a stream frame (`raise(_:)` with a
///   non-nil `question`); the status object never carries one, so
///   `raiseDegraded` can only produce the question-less Deny-only shape
///   (bars 304-D(i) / 304-F).
/// - The POST reaching the host is what makes a state true (#279's shape):
///   nothing is torn down or recorded as answered until the classified
///   response is back. At most ONE POST reaches the host per card regardless
///   of tap count (bar 304-B); the sole re-entry is a POST that provably
///   never reached the host (`.unreachable`, #264's card-stays-live rule).
/// - Terminal turn exit tears an outstanding card down — never left tappable
///   against a run whose driver has exited (bar 304-E). A duplicate
///   `approval.responded` is idempotent (same bar).
@MainActor
@Observable
final class HostApprovalStore {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "HostApprovalStore")

    /// The answer transport, injected so the store never holds a client:
    /// AppContainer routes this through `ChatBackendRouter.answerApproval`,
    /// which forwards by routing lock to the runs client. The default is the
    /// honest dead end — a store nobody wired can never fake a success.
    var sendAnswer: @MainActor (RunApprovalRequest, String) async -> RunApprovalAnswerOutcome = { _, _ in .unsupported }

    /// The card the transcript renders. Nil when no approval is live.
    private(set) var current: RunApprovalRequest?
    /// A POST is in flight — buttons disable; a second tap is a no-op.
    private(set) var isPosting = false
    /// O1's second confirm: an `always`/`session` (or unknown) choice was
    /// tapped and awaits its consequence confirmation. Nil otherwise.
    private(set) var pendingConsequenceChoice: String?
    /// The choice a SUCCESSFUL resolution recorded — the only success state.
    /// Deliberately no transcript receipt (dispatch §8: 3B leaves none unless
    /// #224's Q7 decides otherwise; recorded so the drift is deliberate).
    private(set) var resolvedChoice: String?
    /// Card-REPLACING notice for the terminal 4xx arms (bar 304-C) — each
    /// distinct, none a success. Cleared on the next raise or turn end.
    private(set) var resolutionNotice: String?
    /// Card-PRESERVING notice for a POST that never reached the host (#264's
    /// rule: not denied, not approved, one honest "could not reach").
    private(set) var transportNotice: String?

    // #304 RED shell — every method below is a no-op until the lane's GREEN
    // commit lands the behavior the RunsApprovalFlowTests pin.

    /// A stream frame carried a question (the ONLY door a question enters
    /// by). Re-raising the same run's question is idempotent; a different
    /// run's question replaces the card.
    func raise(_ request: RunApprovalRequest) {}

    /// Bar 304-D(i): the DEGRADED shape — stream gone, run parked, question
    /// unknowable. Deny-only; never replaces a real question already up for
    /// this run, and never fabricates one (bar 304-F).
    func raiseDegraded(runID: String, profileID: UUID?, endpoint: SessionsHermesClient.ResolvedEndpoint) {}

    /// A choice button was tapped. `once`/`deny` POST immediately; O1 routes
    /// `always`/`session` (and any unknown choice) through the second
    /// confirm first.
    func requestChoice(_ choice: String) async {}

    /// The second confirm's affirmative.
    func confirmPendingChoice() async {}

    /// The second confirm's back-out — the card returns to its choices.
    func cancelPendingChoice() {}

    /// The stream says the approval was resolved. Idempotent: a duplicate
    /// frame, or one for a run with no card, changes nothing (bar 304-E).
    func markResolved(runID: String, choice: String?) {}

    /// Bar 304-E: the turn is over, however it ended — an outstanding card is
    /// torn down, never left tappable against a run whose driver has exited.
    func clearForTurnEnd() {}
}
