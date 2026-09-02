import Foundation

/// **#180-CONVENTION — the shared core between the Connect Host vocabulary and
/// every other surface that has to say a host failed.**
///
/// Owen ruled on 2026-08-25 that the Connect Host design's state vocabulary IS
/// the umbrella's long-sought "one design default", and #309 Lane B wrote the
/// six rules onto `ConnectHostCopy`'s header, next to the strings they govern.
/// What that close-out left outstanding was the *reach*: the vocabulary lived
/// on two Connect Host surfaces and nowhere else, so the three host-fed list
/// screens went on printing whatever string a service error happened to carry.
///
/// This file is the migration seam. It answers ONE question —
/// *given a failure the app observed, which rung of the Connect Host ladder is
/// it?* — and hands back that rung's name from `ConnectHostCopy` itself rather
/// than re-spelling it. The no-fork rule is not a comment here: it is a test
/// (`HostFailureConventionTests.everyFailureNameComesFromTheConnectHostVocabulary`)
/// that reads both files and fails if the two spellings ever diverge.
///
/// **Observation only.** Every string below names something the app watched
/// happen — nothing answered, the key came back refused, the body was the wrong
/// shape — and never why. `.notPlaced` exists because rule 1 has two halves and
/// the second one is the load-bearing one: a failure this build cannot place is
/// NAMED as unplaced rather than rounded onto the nearest rung. Rounding is how
/// a screen comes to assert a cause that nothing measured.
enum HostFailureKind: String, CaseIterable, Equatable, Sendable {
    /// No host is saved. **Rule 3: empty is not an error** — the hostless
    /// install is the default user, and describing them as broken is the defect.
    case notConfigured
    /// Nothing answered: transport failure or the request budget expiring.
    case noAnswer
    /// Something answered and refused the key (401/403).
    case keyRefused
    /// Something answered, and it was not a Hermes gateway's shape.
    case notHermes
    /// A failure this build measured but cannot place on the ladder. The
    /// DEFAULT branch, per `HostFedListPresentation`'s rule 5 — unknown is
    /// never the `else` of a two-way test.
    case notPlaced
}

enum HostFailurePresentation {

    // MARK: - Classification

    /// The rung an observed failure lands on.
    ///
    /// The three host-fed services (`SkillsService`, `InsightsService`,
    /// `CronJobService`) declare the same five typed cases, which is why one
    /// mapper can read all three — and why the screens can no longer drift
    /// apart the way the `!hasLoaded` gate did, three files, identically wrong.
    ///
    /// **Unknown is the default branch and not the `else` branch.** Anything
    /// this function cannot place returns `.notPlaced`, which prints a name
    /// saying exactly that.
    static func kind(for error: Error) -> HostFailureKind {
        if let skills = error as? SkillsServiceError {
            switch skills {
            case .notConfigured: return .notConfigured
            case .unreachable, .timeout: return .noAnswer
            case .unauthorized: return .keyRefused
            case .invalidResponse: return .notHermes
            }
        }
        if let insights = error as? InsightsServiceError {
            switch insights {
            case .notConfigured: return .notConfigured
            case .unreachable, .timeout: return .noAnswer
            case .unauthorized: return .keyRefused
            case .invalidResponse: return .notHermes
            }
        }
        if let cron = error as? CronJobServiceError {
            switch cron {
            case .notConfigured: return .notConfigured
            case .unreachable, .timeout: return .noAnswer
            case .unauthorized: return .keyRefused
            case .invalidResponse: return .notHermes
            // A job that is gone, and a create/edit the server argued with,
            // are real cron answers with no rung on THIS ladder. Naming them
            // "no answer" would be a measurement the app never took.
            case .notFound, .serverRejected: return .notPlaced
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .secureConnectionFailed,
                 .internationalRoamingOff, .callIsActive, .dataNotAllowed:
                return .noAnswer
            case .userAuthenticationRequired:
                return .keyRefused
            default:
                return .notPlaced
            }
        }
        return .notPlaced
    }

    // MARK: - The vocabulary

    /// The rung's NAME — read from `ConnectHostCopy` wherever Connect Host
    /// already has a word for this state, so there is exactly one spelling of
    /// each in the tree.
    static func title(_ kind: HostFailureKind) -> String {
        switch kind {
        case .notConfigured: ConnectHostCopy.runningLocallyTitle
        case .noAnswer: ConnectHostCopy.noAnswerTitle
        case .keyRefused: ConnectHostCopy.keyRefusedTitle
        case .notHermes: ConnectHostCopy.notHermesTitle
        case .notPlaced: notPlacedTitle
        }
    }

    /// The sentence under the name. Each one is a Connect Host line already
    /// shown for the same state on the Settings card, chosen for the variants
    /// that need no measurement the list screens do not hold (no latency, no
    /// host name — see `keyRefusedBlurb(host:milliseconds:)`, deliberately not
    /// used here).
    static func blurb(_ kind: HostFailureKind) -> String {
        switch kind {
        case .notConfigured: ConnectHostCopy.runningLocallyBlurb
        case .noAnswer: ConnectHostCopy.stillSavedBlurb
        case .keyRefused: ConnectHostCopy.keyRefusedHeadline
        case .notHermes: ConnectHostCopy.notHermesBlurb
        case .notPlaced: notPlacedBlurb
        }
    }

    /// The strip over rows that survived the failure. It keeps rule 1's stamp
    /// — what is on screen is a LAST FETCH, not live — and rule 4's naming, so
    /// the reader learns which rung broke instead of a bare "refresh failed".
    static func stripLabel(_ kind: HostFailureKind) -> String {
        "\(title(kind)) — SHOWING LAST FETCH"
    }

    /// The glyph beside the name. `.notConfigured` is deliberately NOT a
    /// warning glyph: rule 3 again — the hostless state is an answer, not a
    /// fault, and a red triangle on it is the app calling the default user
    /// broken.
    static func systemImage(_ kind: HostFailureKind) -> String {
        switch kind {
        case .notConfigured: "iphone.gen3"
        case .noAnswer: "wifi.exclamationmark"
        case .keyRefused: "key.slash"
        case .notHermes: "questionmark.square.dashed"
        case .notPlaced: "exclamationmark.triangle"
        }
    }

    /// Whether this state is a FAILURE at all — false for `.notConfigured`,
    /// which is why the empty branch offers it no Retry: there is nothing to
    /// retry against, and a button that cannot work is a claim too.
    static func isFailure(_ kind: HostFailureKind) -> Bool {
        kind != .notConfigured
    }

    // MARK: - Names the convention needs beyond the Connect Host surfaces

    /// **Rule 1's second half.** The app measured a failure and cannot say
    /// which step broke. Rule 4 forbids collapsing real discriminations into
    /// "failed"; it does not ask the app to invent one it never made, and this
    /// is the honest floor under the ladder rather than a rung of it.
    static let notPlacedTitle = "UNNAMED FAILURE"
    static let notPlacedBlurb =
        "The refresh failed, and this app can't say which step broke. Pull down to try again."

    /// **#180-C-B — the degraded marker on a host reply the host itself
    /// flagged.** An observation and nothing more: it says the host raised a
    /// flag on this turn, never what went wrong. The host's own words ride
    /// beneath it when it gave any (`SessionsHermesClient.runFailureText`'s
    /// standing rule one surface over); when it gave none, the app reports the
    /// one bit it actually received.
    static let hostFlaggedMarker = "⚠ THE HOST FLAGGED THIS REPLY"
}
