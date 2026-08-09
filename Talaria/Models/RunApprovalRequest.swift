import Foundation

/// #304 (Phase 3 slice 3B): one HOST-side approval request, parked on a
/// `/v1/runs` run, as the phone can answer it over
/// `POST /v1/runs/{run_id}/approval`.
///
/// **A different actor from `ToolConfirmationCenter` (#29), sharing nothing
/// but a card-shaped surface.** That gate suspends a Swift continuation for a
/// tool running ON THIS PHONE; this value describes a question the HOST asked
/// about ITS OWN action, with a server-side deadline (`approvals.timeout`,
/// default 300s) and a network round trip to answer. The two can be on screen
/// at the same moment and must not look alike.
///
/// **The endpoint rides the VALUE, never the client's live slot** (dispatch
/// §9 trap 1, the #285 shape): `activeRunContext` is a SINGLE slot cleared on
/// the turn's terminal exit, so an approval answered even a beat later would
/// address nothing — and a mid-turn profile switch must not redirect the
/// answer to the wrong host. Everything needed to POST the answer is frozen
/// here at the moment the question arrived.
struct RunApprovalRequest: Identifiable, Equatable, Sendable {
    /// The host's own question — absent in the DEGRADED shape (bar 304-D(i)):
    /// the stream that carried it is gone and only the run's parked state is
    /// knowable, so the card offers Deny alone and says it cannot show what
    /// it would deny. **A question is only ever built from a stream frame —
    /// never from the status object, which does not carry one (bar 304-F).**
    struct Question: Equatable, Sendable {
        /// The gated action AS THE HOST SENT IT (already credential-redacted
        /// host-side). **Not always a shell command**: the MCP-elicitation
        /// producer reuses this field for its consent MESSAGE, and the
        /// execute-code guard sends Python source. Render verbatim — never
        /// reformat, re-highlight, or truncate (and never a surface to
        /// reconstruct written files from, 3A-D).
        let command: String
        /// The host's one-line account of what matched, when it sent one.
        let description: String?
        /// The matched pattern's key (`"mcp_elicitation"` marks the consent
        /// shape). Informational; never used to gate rendering of choices.
        let patternKey: String?
        /// **The host's own choice set, exactly as received.** Computed per
        /// request host-side (`_approval_event_choices`): four-choice,
        /// three-choice, and `smart_denied` two-choice arms all exist, and
        /// upstream can grow more — so this is `[String]`, not a closed enum,
        /// and an unknown choice must RENDER rather than vanish. A hardcoded
        /// four-button card is a bar failure (304-A).
        let choices: [String]

        /// The MCP consent shape: `command` is a MESSAGE, not a command, and
        /// the card must not present it as something the host would "run".
        var isElicitation: Bool { patternKey == "mcp_elicitation" }
    }

    /// The run this approval parks — the answer POST's address half.
    let runID: String
    /// The turn's birth profile (M-5), for naming the actor on the card.
    /// Nil in profile-less constructions; the endpoint below still resolves.
    let profileID: UUID?
    /// The run's FROZEN endpoint (#285): the answer rides this, never a
    /// re-resolution of the live providers.
    let endpoint: SessionsHermesClient.ResolvedEndpoint
    /// Nil = the degraded, question-less shape (see `Question`).
    let question: Question?

    var id: String { runID }

    /// The actor line's host half — the gateway this question came from.
    /// Real data only: derived from the frozen endpoint, never a guess.
    var hostDisplayName: String {
        guard let url = URL(string: endpoint.baseURL), let host = url.host else {
            return endpoint.baseURL
        }
        return host
    }

    // MARK: - Choice display mapping (Owen's O1 ruling, 2026-08-09)

    /// Button label for a wire choice. **`session` must not imply
    /// conversation scope** — it is scoped to `approval_session_key`, which
    /// IS the run id, so it reads "THIS RUN". Unknown choices render as
    /// themselves (uppercased), never dropped.
    static func buttonLabel(for choice: String) -> String {
        switch choice {
        case "once": "ONCE"
        case "session": "THIS RUN"
        case "always": "ALWAYS"
        case "deny": "DENY"
        default: choice.uppercased()
        }
    }

    /// O1: `once` and `deny` are one tap; `always` and `session` sit behind a
    /// SECOND CONFIRM naming the consequence. An unknown choice's effect is
    /// the host's to define, so it fails safe: second confirm too.
    static func requiresConsequenceConfirm(_ choice: String) -> Bool {
        switch choice {
        case "once", "deny": false
        default: true
        }
    }

    /// The second confirm's consequence statement (O1's exact framing).
    /// For an unknown choice this is honest absence, not an invented effect.
    static func consequenceStatement(for choice: String, host: String) -> String {
        switch choice {
        case "always":
            "Permanently allowlists this pattern on \(host). It will not ask again — across sessions, until changed on the host."
        case "session":
            "Applies to this one run only — not this conversation."
        default:
            "The host defines what '\(choice)' does. Talaria cannot describe its effect."
        }
    }

    /// VoiceOver labels state the CONSEQUENCE, not the choice name (the
    /// 224-1D precedent).
    static func accessibilityLabel(for choice: String, host: String) -> String {
        switch choice {
        case "once":
            "Approve once — \(host) runs this action one time"
        case "session":
            "Approve for this run — allows this pattern until this one run ends, not the whole conversation"
        case "always":
            "Approve always — permanently allowlists this pattern on \(host)"
        case "deny":
            "Deny — \(host) will not run this action"
        default:
            "\(choice) — a choice offered by \(host); its effect is defined by the host"
        }
    }
}

/// #304: the classified result of `POST /v1/runs/{run_id}/approval` — bar
/// 304-C's whole point is that every arm renders DISTINCTLY and none renders
/// as success. The store maps these to user-facing copy; the client maps HTTP
/// to these and nothing else.
enum RunApprovalAnswerOutcome: Equatable, Sendable {
    /// 2xx `{object:"hermes.run.approval_response", …}` — the host resolved
    /// the approval with the sent choice. The ONLY success arm.
    case resolved
    /// 409 `approval_not_pending`: the window closed (timeout already denied
    /// it host-side) — "too late", never an error the user caused.
    case windowClosed
    /// 409 `approval_not_active`: the host has no approval session for this
    /// run at all. Distinct from `windowClosed` — nothing was ever pending
    /// on this run, vs. something was and expired.
    case notActive
    /// 404 `run_not_found`: the host no longer has the run (TTL, restart,
    /// or a different host).
    case runGone
    /// Any other HTTP answer (400 invalid choice, 5xx, an unknown 409 code):
    /// the host's own words, surfaced. Never success.
    case rejected(String)
    /// The POST never reached the host (transport failure). Per #264's rule
    /// the card must stay LIVE — not denied, not approved, one honest
    /// "could not reach the host".
    case unreachable(String)
    /// The protocol default: this backend has no runs plane to answer on
    /// (mock / relay / the on-device brain). A programming-error guard, not
    /// a user state — but if it ever surfaces, it surfaces honestly.
    case unsupported
}
