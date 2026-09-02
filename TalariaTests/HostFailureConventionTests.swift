import Foundation
import Testing
@testable import Talaria

/// **#180-CONVENTION (2026-09-01) — the three host-fed screens join the
/// Connect Host honest-degradation convention.**
///
/// Owen's 2026-08-25 ruling adopted the Connect Host state vocabulary as the
/// umbrella's "one design default"; its home is
/// `Talaria/Features/Settings/ConnectHostCopy.swift`. Four members were left
/// outstanding at that close-out. This suite holds the bars for three of them
/// (the health-permission card is HELD, awaiting Owen's `PermissionStatus`
/// ruling, and nothing here touches it).
///
/// - **180-C-A** — Skills / Tasks / Insights render a host failure through the
///   convention's closed vocabulary, never a raw `store.lastErrorMessage`
///   string. The structural pin below is the one that was RED first.
/// - **180-C-B** — a terminal run the host itself flagged carries a degraded
///   marker instead of arriving with the confidence of a clean answer.
/// - **180-C-C** — #139's residual copy: the unknown-engine voice header no
///   longer claims CONNECTING in states where nothing is connecting.
struct HostFailureConventionTests {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
    }

    private static func read(_ relativePath: String) throws -> String {
        try #require(
            try? String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8),
            "cannot read \(relativePath) — this check did not run"
        )
    }

    /// The three screens the 2026-08-25 close-out named as still outstanding.
    private static let hostFedScreens = [
        "Talaria/Features/Skills/SkillsScreen.swift",
        "Talaria/Features/Tasks/TasksScreen.swift",
        "Talaria/Features/Insights/InsightsScreen.swift",
    ]

    // MARK: - 180-C-A, the structural pin (RED FIRST)

    /// **180-C-A structural half.** No host-fed list screen may reach for the
    /// store's raw failure string. The mapper is the only route from an
    /// observed failure to on-screen words, so a screen that names
    /// `lastErrorMessage` has bypassed the vocabulary — which is exactly how
    /// the umbrella's third instance got written three times, identically
    /// wrong, in the first place.
    ///
    /// A `#180` tombstone comment is allowed so the deleted shape can still be
    /// named at its own site; a code line is not.
    ///
    /// Fails LOUDLY when a file cannot be read: a check that did not run must
    /// say so rather than pass.
    @Test func noHostFedScreenRendersTheRawErrorString() throws {
        var offenders: [String] = []
        for path in Self.hostFedScreens {
            let text = try Self.read(path)
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard line.contains("lastErrorMessage") else { continue }
                guard !(trimmed.hasPrefix("//") && line.contains("#180")) else { continue }
                offenders.append("\(path):\(index + 1): \(trimmed)")
            }
        }
        let report = offenders.joined(separator: "\n")
        #expect(offenders.isEmpty,
                "a host-fed screen renders the raw failure string instead of the convention's vocabulary:\n\(report)")
    }

    /// The same pin from the other side: each screen must actually route
    /// through the shared mapper. Without this, deleting the error surface
    /// altogether would satisfy the check above — the gate's founding sin in
    /// miniature.
    @Test func everyHostFedScreenRoutesThroughTheSharedMapper() throws {
        for path in Self.hostFedScreens {
            let text = try Self.read(path)
            #expect(text.contains("HostFailurePresentation"),
                    "\(path) no longer routes its failure copy through the shared mapper")
        }
    }

    // MARK: - 180-C-A, the classification

    /// Every typed service failure lands on a rung of the Connect Host ladder.
    /// The three services declare the same five cases; one mapper reads all
    /// three so the screens cannot drift apart the way the `!hasLoaded` gate
    /// did.
    @Test func typedServiceFailuresLandOnTheLadder() {
        #expect(HostFailurePresentation.kind(for: SkillsServiceError.notConfigured("x")) == .notConfigured)
        #expect(HostFailurePresentation.kind(for: SkillsServiceError.unreachable("x")) == .noAnswer)
        #expect(HostFailurePresentation.kind(for: SkillsServiceError.timeout) == .noAnswer)
        #expect(HostFailurePresentation.kind(for: SkillsServiceError.unauthorized("x")) == .keyRefused)
        #expect(HostFailurePresentation.kind(for: SkillsServiceError.invalidResponse("x")) == .notHermes)

        #expect(HostFailurePresentation.kind(for: InsightsServiceError.notConfigured("x")) == .notConfigured)
        #expect(HostFailurePresentation.kind(for: InsightsServiceError.unreachable("x")) == .noAnswer)
        #expect(HostFailurePresentation.kind(for: InsightsServiceError.timeout) == .noAnswer)
        #expect(HostFailurePresentation.kind(for: InsightsServiceError.unauthorized("x")) == .keyRefused)
        #expect(HostFailurePresentation.kind(for: InsightsServiceError.invalidResponse("x")) == .notHermes)

        #expect(HostFailurePresentation.kind(for: CronJobServiceError.notConfigured("x")) == .notConfigured)
        #expect(HostFailurePresentation.kind(for: CronJobServiceError.unreachable("x")) == .noAnswer)
        #expect(HostFailurePresentation.kind(for: CronJobServiceError.timeout) == .noAnswer)
        #expect(HostFailurePresentation.kind(for: CronJobServiceError.unauthorized("x")) == .keyRefused)
        #expect(HostFailurePresentation.kind(for: CronJobServiceError.invalidResponse("x")) == .notHermes)
    }

    /// **Rule 1's other half, and rule 5's default branch.** A failure this
    /// build cannot place is NAMED as unplaced — never rounded onto the
    /// nearest rung, which would put a cause on the screen that nothing
    /// measured. `notFound` and `serverRejected` are real cron cases with no
    /// ladder rung; an arbitrary foreign error is the general case.
    @Test func anUnplaceableFailureIsNamedRatherThanRounded() {
        #expect(HostFailurePresentation.kind(for: CronJobServiceError.notFound) == .notPlaced)
        #expect(HostFailurePresentation.kind(for: CronJobServiceError.serverRejected("x")) == .notPlaced)
        #expect(HostFailurePresentation.kind(for: CocoaError(.fileNoSuchFile)) == .notPlaced)
    }

    /// A transport failure that reaches a store unwrapped is still a measured
    /// "nothing answered" — the same rung the typed `unreachable` takes.
    @Test func rawTransportFailuresAreStillNoAnswer() {
        for code in [URLError.Code.timedOut, .cannotConnectToHost, .networkConnectionLost,
                     .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed] {
            #expect(HostFailurePresentation.kind(for: URLError(code)) == .noAnswer,
                    "\(code) is a measured no-answer")
        }
    }

    // MARK: - 180-C-A, the vocabulary is NOT forked

    /// Every name the mapper prints is a `ConnectHostCopy` constant, read from
    /// that file rather than re-spelled here. This is the bar that stops a
    /// second vocabulary growing beside the first — the exact failure the copy
    /// file's own header warns about.
    @Test func everyFailureNameComesFromTheConnectHostVocabulary() {
        #expect(HostFailurePresentation.title(.notConfigured) == ConnectHostCopy.runningLocallyTitle)
        #expect(HostFailurePresentation.blurb(.notConfigured) == ConnectHostCopy.runningLocallyBlurb)
        #expect(HostFailurePresentation.title(.noAnswer) == ConnectHostCopy.noAnswerTitle)
        #expect(HostFailurePresentation.blurb(.noAnswer) == ConnectHostCopy.stillSavedBlurb)
        #expect(HostFailurePresentation.title(.keyRefused) == ConnectHostCopy.keyRefusedTitle)
        #expect(HostFailurePresentation.blurb(.keyRefused) == ConnectHostCopy.keyRefusedHeadline)
        #expect(HostFailurePresentation.title(.notHermes) == ConnectHostCopy.notHermesTitle)
        #expect(HostFailurePresentation.blurb(.notHermes) == ConnectHostCopy.notHermesBlurb)

        // `.notPlaced` is the one rung Connect Host has no word for — it is
        // the honest floor UNDER the ladder rather than a rung of it — so its
        // name lives in the mapper. Pinned here so a later edit cannot quietly
        // start a second vocabulary somewhere else.
        #expect(HostFailurePresentation.title(.notPlaced) == HostFailurePresentation.notPlacedTitle)
        #expect(HostFailurePresentation.blurb(.notPlaced) == HostFailurePresentation.notPlacedBlurb)
    }

    /// Closed vocabulary, stated as a closure rather than implied: every kind
    /// has a non-empty name and blurb, and no two kinds share a name. A rung
    /// that printed nothing would be a silent failure surface — the thing this
    /// umbrella exists to remove.
    @Test func theVocabularyIsClosedAndDistinct() {
        var names: Set<String> = []
        for kind in HostFailureKind.allCases {
            let title = HostFailurePresentation.title(kind)
            #expect(!title.isEmpty, "\(kind) prints no name")
            #expect(!HostFailurePresentation.blurb(kind).isEmpty, "\(kind) prints no blurb")
            #expect(names.insert(title).inserted, "\(kind) reuses the name \(title)")
        }
        #expect(names.count == HostFailureKind.allCases.count)
    }

    /// The strip over surviving rows keeps its measured stamp — rows on screen
    /// are a LAST FETCH, and the failure name says which rung broke rather
    /// than a bare "refresh failed" (rules 1 and 4 in one line).
    @Test func theStripNamesTheRungAndKeepsItsStamp() {
        #expect(HostFailurePresentation.stripLabel(.noAnswer)
                    == "\(ConnectHostCopy.noAnswerTitle) — SHOWING LAST FETCH")
        #expect(HostFailurePresentation.stripLabel(.keyRefused)
                    == "\(ConnectHostCopy.keyRefusedTitle) — SHOWING LAST FETCH")
    }

    /// The empty branch carries the KIND, not a string — so a screen cannot
    /// receive words it did not get from the mapper. The three
    /// `emptyBranchState` decisions themselves are unchanged and stay pinned
    /// by `HostFedListPresentationTests`.
    @Test func theEmptyBranchCarriesTheClassificationNotWords() {
        #expect(HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: true, failure: .keyRefused) == .error(.keyRefused))
        #expect(HostFedListPresentation.emptyBranchState(
            isLoading: false, hasLoaded: true, failure: nil) == .empty)
    }

    // MARK: - 180-C-B — the host-flagged turn

    /// **The site: `SessionsHermesClient+RunsTransport`'s terminal assembly.**
    ///
    /// A `run.completed` frame carrying the host's own `error` flag used to
    /// reach `runsFinalMessage` and be thrown away: the reply rendered
    /// `.delivered`, with exactly the confidence of a clean answer. That is
    /// #241's inherited instance in its structural form — two branches
    /// (completed ⇒ answer, failed ⇒ error) with the third state, *completed
    /// and flagged*, landing on the affirmative side.
    ///
    /// The wire's `error` is a UNION (#296-C1: the host sends a JSON boolean),
    /// so the marker is read through `hostErrorDetail`, which already knows
    /// that.
    @Test func aCompletedRunTheHostFlaggedIsReadAsFlagged() {
        let flagged = """
        {"event":"run.completed","output":"I could not reach any model.","error":true}
        """
        #expect(SessionsHermesClient.decodeTerminalHostError(flagged)
                    == SessionsHermesClient.unspecifiedHostError)

        let worded = """
        {"event":"run.completed","output":"…","error":"no provider answered"}
        """
        #expect(SessionsHermesClient.decodeTerminalHostError(worded) == "no provider answered")
    }

    /// The other direction, and it is the one that matters: a clean completion
    /// must NOT grow a marker. `error: false`, an absent key, and an empty
    /// string all mean nothing went wrong — repainting them would be #296
    /// inverted.
    @Test func acleanCompletionGrowsNoMarker() {
        for payload in [
            #"{"event":"run.completed","output":"hello"}"#,
            #"{"event":"run.completed","output":"hello","error":false}"#,
            #"{"event":"run.completed","output":"hello","error":""}"#,
            "not json at all",
        ] {
            #expect(SessionsHermesClient.decodeTerminalHostError(payload) == nil,
                    "a clean completion was marked degraded: \(payload)")
        }
    }

    /// The marker rides the message, so the bubble can show it and the cache
    /// can keep it. Absent on every ordinary reply — old caches decode fine.
    @Test func theDegradedMarkerRidesTheMessageAndSurvivesTheCache() throws {
        var message = Message(sender: .hermes, content: "I could not reach any model.",
                              status: .delivered)
        #expect(message.hostReportedFailure == nil)

        message.hostReportedFailure = "no provider answered"
        let round = try JSONDecoder().decode(
            Message.self, from: try JSONEncoder().encode(message))
        #expect(round.hostReportedFailure == "no provider answered")

        let legacy = """
        {"id":"\(UUID().uuidString)","sender":"hermes","content":"hi",
         "timestamp":0,"status":"delivered"}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(Message.self, from: legacy)
        #expect(old.hostReportedFailure == nil, "a pre-#180 cached reply must not read as flagged")
    }

    /// The marker's words are the convention's, and the DETAIL is the host's
    /// own — never a cause this app invented. Rule 6, and `runFailureText`'s
    /// standing house rule one surface over.
    @Test func theDegradedMarkerNamesTheObservationAndNotACause() {
        #expect(!HostFailurePresentation.hostFlaggedMarker.isEmpty)
        // An observation ("the host flagged it"), never a diagnosis.
        let marker = HostFailurePresentation.hostFlaggedMarker.uppercased()
        for forbidden in ["OFFLINE", "UNREACHABLE", "MODEL", "NETWORK"] {
            #expect(!marker.contains(forbidden),
                    "the marker names a cause the app did not establish: \(forbidden)")
        }
    }

    // MARK: - 180-C-C — #139's residual copy

    /// **#139's residual, corrected.** With no engine selected the header used
    /// to read `VOICE · CONNECTING` for `.idle`, `.checking` and `.ready` as
    /// well as `.connecting` — a claim about an action in flight, printed in
    /// three states where nothing is in flight. That copy shipped owed Owen's
    /// approval and never got it; the 2026-08-25 ruling supplies the standard
    /// instead, and rule 1 answers it: measured, or named as unmeasured.
    ///
    /// The fix reuses `TalkConnectionState.displayLabel` — the state's own
    /// measured name — so no new word enters the vocabulary.
    @Test func theUnknownEngineHeaderClaimsOnlyTheMeasuredState() {
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: nil, connectionState: .idle, duration: 0) == "VOICE · IDLE")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: nil, connectionState: .checking, duration: 0) == "VOICE · CHECKING")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: nil, connectionState: .ready, duration: 0) == "VOICE · READY")
        // The one pre-connect state where CONNECTING is measured keeps it.
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: nil, connectionState: .connecting, duration: 0) == "VOICE · CONNECTING")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: nil, connectionState: .failed, duration: 0) == "VOICE · FAILED")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: nil, connectionState: .connected, duration: 65) == "VOICE · 01:05")
    }

    /// And the pin that stops the correction over-reaching: a SELECTED engine
    /// is still named, and its own pre-connect wording is untouched (#18 —
    /// local voice is never silently substituted for the Realtime experience).
    @Test func aSelectedEnginesWordingIsUnchangedByTheCorrection() {
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .native, connectionState: .idle, duration: 0) == "LOCAL VOICE · STARTING")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .realtime, connectionState: .idle, duration: 0) == "VOICE LINK · CONNECTING")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .realtime, connectionState: .ready, duration: 0) == "VOICE LINK · CONNECTING")
    }
}
