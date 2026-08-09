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
    /// The choice this approval RESOLVED with — set by our own successful
    /// POST or by an `approval.responded` frame. The only success state.
    /// Deliberately no transcript receipt (dispatch §8: 3B leaves none unless
    /// #224's Q7 decides otherwise; recorded so the drift is deliberate).
    private(set) var resolvedChoice: String?
    /// Card-REPLACING notice for the terminal 4xx arms (bar 304-C) — each
    /// distinct, none a success. Cleared on the next raise or turn end.
    private(set) var resolutionNotice: String?
    /// Card-PRESERVING notice for a POST that never reached the host (#264's
    /// rule: not denied, not approved, one honest "could not reach").
    private(set) var transportNotice: String?
    /// An `approval.responded` frame that landed while OUR OWN POST was in
    /// flight — the frame's account outranks a raced 409, so the POST's
    /// completion consults this before claiming an expiry.
    private var frameResolvedChoice: String?

    /// A stream frame carried a question (the ONLY door a question enters
    /// by), or the driver raised the degraded shape via `raiseDegraded`.
    /// Re-raising the same run is idempotent and never downgrades a question;
    /// a DIFFERENT run's question replaces the card — this client drives one
    /// turn at a time, so the old run's turn is over or abandoned.
    func raise(_ request: RunApprovalRequest) {
        if let current, current.runID == request.runID {
            // Never yank a card out from under its own in-flight answer, and
            // never downgrade a renderable question to the degraded shape.
            if isPosting || resolvedChoice != nil { return }
            if current.question != nil { return }
            if request.question != nil {
                // Degraded → question upgrade: the stream came back with the
                // host's own words. Adopt them.
                self.current = request
            }
            return
        }
        if let current {
            Self.logger.notice("host approval for \(request.runID, privacy: .public) replaces outstanding card for \(current.runID, privacy: .public)")
        }
        current = request
        isPosting = false
        pendingConsequenceChoice = nil
        resolvedChoice = nil
        resolutionNotice = nil
        transportNotice = nil
        frameResolvedChoice = nil
        Self.logger.notice("host approval raised for \(request.runID, privacy: .public) (\(request.question == nil ? "degraded" : "question", privacy: .public))")
    }

    /// Bar 304-D(i): the DEGRADED shape — the stream is gone, the status
    /// object says the run is parked, and the question is unknowable. Offers
    /// Deny alone; the answer channel is stream-independent, so the Deny
    /// still lands. **Never replaces a real question already up for this
    /// run** and never fabricates one (bar 304-F).
    func raiseDegraded(runID: String, profileID: UUID?, endpoint: SessionsHermesClient.ResolvedEndpoint) {
        if let current, current.runID == runID { return }
        raise(RunApprovalRequest(runID: runID, profileID: profileID, endpoint: endpoint, question: nil))
    }

    /// A choice button was tapped. `once`/`deny` POST immediately; O1 routes
    /// `always`/`session` (and any unknown choice) through the second
    /// confirm first.
    func requestChoice(_ choice: String) async {
        guard current != nil, !isPosting, resolvedChoice == nil else { return }
        if RunApprovalRequest.requiresConsequenceConfirm(choice) {
            pendingConsequenceChoice = choice
            return
        }
        await post(choice)
    }

    /// The second confirm's affirmative.
    func confirmPendingChoice() async {
        guard let choice = pendingConsequenceChoice else { return }
        pendingConsequenceChoice = nil
        await post(choice)
    }

    /// The second confirm's back-out — the card returns to its choices.
    func cancelPendingChoice() {
        pendingConsequenceChoice = nil
    }

    /// The one POST door. At most one reaches the host per card (bar 304-B):
    /// `isPosting` latches before the await, a resolved card never posts
    /// again, and only an `.unreachable` outcome — a POST that provably never
    /// arrived — re-opens the door.
    private func post(_ choice: String) async {
        guard let request = current, !isPosting, resolvedChoice == nil else { return }
        isPosting = true
        transportNotice = nil
        let outcome = await sendAnswer(request, choice)
        isPosting = false
        // The card can be legitimately torn down while the POST is in flight
        // (turn ended, someone else resolved it). A success still records;
        // nothing ever resurrects a dead card.
        let stillCurrent = current?.runID == request.runID
        switch outcome {
        case .resolved:
            resolvedChoice = choice
            pendingConsequenceChoice = nil
            if stillCurrent { current = nil }
            Self.logger.notice("host approval \(request.runID, privacy: .public) resolved as '\(choice, privacy: .public)'")
        case .windowClosed:
            if let frameChoice = frameResolvedChoice {
                // The stream said someone already resolved it mid-flight —
                // the truer account than "expired". Not OUR answer landing.
                resolvedChoice = frameChoice
                pendingConsequenceChoice = nil
                if stillCurrent { current = nil }
            } else if stillCurrent {
                settle("The approval window closed — the host already denied this after waiting. Nothing ran.")
            }
        case .notActive:
            if stillCurrent {
                settle("The host has no approval waiting on this run — there is nothing left to answer.")
            }
        case .runGone:
            if stillCurrent {
                settle("The host no longer has this run, so the approval can't be answered.")
            }
        case .rejected(let detail):
            if stillCurrent {
                settle("The host rejected the answer: \(detail)")
            }
        case .unreachable(let detail):
            // #264: the card STAYS LIVE — not denied, not approved — and a
            // retry is legitimate: this POST never reached the host, so
            // at-most-once is not spent.
            if stillCurrent {
                transportNotice = "Couldn't reach the host — the approval is still waiting there. \(detail)"
            }
        case .unsupported:
            if stillCurrent {
                settle("This backend can't answer host approvals.")
            }
        }
    }

    /// The stream says the approval was resolved (our POST's echo, or anyone
    /// else's answer). Idempotent: a duplicate frame, or one for a run with
    /// no card, changes nothing (bar 304-E).
    func markResolved(runID: String, choice: String?) {
        guard let current, current.runID == runID else { return }
        if isPosting {
            // Our own POST is in flight; let its classified outcome settle
            // the card — but remember the frame's account so a raced 409
            // does not read as an expiry (see `post`).
            frameResolvedChoice = choice ?? frameResolvedChoice ?? "resolved"
            return
        }
        self.current = nil
        pendingConsequenceChoice = nil
        if resolvedChoice == nil { resolvedChoice = choice }
    }

    /// Bar 304-E: the turn is over, however it ended — an outstanding card is
    /// torn down, never left tappable against a run whose driver has exited.
    /// (An in-flight POST's completion still classifies via `post`'s
    /// `stillCurrent` guard; it just has no card left to mutate.)
    ///
    /// Unscoped on purpose, and safe BECAUSE the chat consumer is the only
    /// raiser (#304 review-2 ruling — round 1 briefly added a voice raiser
    /// plus a run-scoped overload; with two raisers the chat's unscoped
    /// clears could tear down the other surface's card, so the second raiser
    /// was removed rather than every clear site scoped). If a second raiser
    /// ever returns (#305), scoping every teardown is part of its design,
    /// not an afterthought.
    func clearForTurnEnd() {
        current = nil
        pendingConsequenceChoice = nil
        resolutionNotice = nil
        transportNotice = nil
        frameResolvedChoice = nil
    }

    /// The terminal 4xx arms' shared shape: card gone, DISTINCT notice, and
    /// never a success record (bar 304-C).
    private func settle(_ notice: String) {
        current = nil
        pendingConsequenceChoice = nil
        resolutionNotice = notice
    }
}
