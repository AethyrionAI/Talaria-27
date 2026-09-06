import Foundation
import Testing
@testable import Talaria

/// #435 — deterministic Apple Weather attribution on replies that drew on the
/// weather tool.
///
/// The controller's reading of Apple's requirement
/// (`developer.apple.com/weatherkit/#attribution-requirements`): wherever Apple
/// Weather DATA is displayed, show the Apple Weather mark or name AND link to
/// Apple's legal attribution page — and a value-added transformation of the
/// data (a model's prose IS one) still owes it.
///
/// The whole point of this lane is that the attribution is **derived, never
/// model-authored**: it is a pure function of the persisted transcript, so a
/// reply that drew on `currentWeather` carries it whether or not the model
/// happened to mention Apple.
///
/// Every check that reads a file fails LOUDLY when it cannot read it — a check
/// that did not run must say so rather than pass.
struct WeatherAttributionTests {

    // MARK: - Helpers

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

    /// The one section of `THIRD_PARTY_LICENSES.md` this lane is allowed to
    /// touch (#434 edits the others concurrently).
    private static func notCoveredHereSection(of document: String) throws -> String {
        let heading = "## Not covered here"
        let start = try #require(document.range(of: heading),
                                 "\(heading) is gone from THIRD_PARTY_LICENSES.md — this check did not run")
        let rest = String(document[start.upperBound...])
        if let next = rest.range(of: "\n## ") {
            return String(rest[..<next.lowerBound])
        }
        return rest
    }


    // MARK: - Fixtures

    private static func weatherActivity(
        isActive: Bool = false,
        failure: String? = nil,
        provenance: ToolActivity.Provenance? = nil
    ) -> ToolActivity {
        ToolActivity(label: WeatherAttribution.toolName,
                     isActive: isActive,
                     detail: "Gulfport",
                     failure: failure,
                     provenance: provenance)
    }

    private static func reply(_ activities: [ToolActivity]) -> Message {
        Message(sender: .hermes,
                content: "It's 68 and clear in Gulfport, clearing tonight.",
                status: .delivered,
                toolActivities: activities)
    }

    // MARK: - 435-A — the derived trigger

    /// **435-A.** The whole rule in one row: a reply whose transcript records a
    /// COMPLETED `currentWeather` call owes the attribution.
    @Test("435-A · a completed weather call requires the attribution")
    func aCompletedWeatherCallRequiresTheAttribution() {
        #expect(WeatherAttribution.required(for: Self.reply([Self.weatherActivity()])))
    }

    /// **435-A.** The trigger reads the message, not just a bare array — the
    /// convenience the view actually calls must agree with the predicate under
    /// it, and a reply with several tools among which weather completed still
    /// owes it.
    @Test("435-A · the message-level trigger agrees, weather among other tools")
    func theMessageLevelTriggerFindsWeatherAmongOtherTools() {
        let message = Self.reply([
            ToolActivity(label: "readCalendar", isActive: false),
            Self.weatherActivity(),
            ToolActivity(label: "searchPlaces", isActive: false)
        ])
        #expect(WeatherAttribution.required(for: message))
    }

    /// **435-A.** The attribution is derived from a PERSISTED field, so it
    /// survives relaunch with no new coding key — that claim is the reason this
    /// lane needed no change to `Message.CodingKeys`, and an unasserted claim
    /// of that shape is how a chip ships and never renders (#422's
    /// `memoryProvenance`).
    @Test("435-A · the trigger survives a coding round trip")
    func attributionSurvivesACodingRoundTrip() throws {
        let original = Self.reply([Self.weatherActivity()])
        let restored = try JSONDecoder().decode(
            Message.self, from: try JSONEncoder().encode(original))
        #expect(WeatherAttribution.required(for: restored),
                "toolActivities is persisted, so the derived attribution must survive a relaunch")
    }

    /// **435-A.** The constant this whole lane keys on is the weather tool's
    /// OWN name. A rename would otherwise stop the attribution silently, which
    /// is the failure mode a pin has to catch — the mechanism would keep
    /// working, keep passing, and simply never fire.
    @MainActor
    @Test("435-A · the pinned tool name is WeatherTool's own name")
    func thePinnedToolNameIsTheWeatherToolsOwnName() {
        let provider = DeviceLocationProvider(seam: .init(
            authorizationStatus: { .denied },
            cachedLocation: { nil },
            requestWhenInUseAuthorization: {},
            requestLocation: {}
        ))
        let tool = WeatherTool(relay: ToolEventRelay(), location: provider)
        #expect(WeatherAttribution.toolName == tool.name,
                "the attribution keys on a tool name the belt no longer emits")
    }

    /// **435-A.** The row is rendered, and rendered UNCONDITIONALLY on the
    /// strength of the predicate — no disclosure, no expansion state, no
    /// second gate. An attribution the reader has to open is not displayed.
    @Test("435-A · MessageBubble renders the row, gated only by the predicate")
    func theBubbleRendersTheAttributionRowGatedOnlyByThePredicate() throws {
        let bubble = try Self.read("Talaria/Features/Chat/MessageBubble.swift")
        let normalized = bubble.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(normalized.contains("if WeatherAttribution.required(for: message) { WeatherAttributionRow() }"),
                "the attribution row is missing, or carries a second gate the predicate does not know about")
    }

    // MARK: - 435-B — no false attribution

    /// **435-B.** A reply that never called the weather tool displays no Apple
    /// data. It owes nothing, and a row there would be a claim about a source
    /// the turn never touched.
    @Test("435-B · a reply with no tool activity requires nothing")
    func aReplyWithNoToolActivityRequiresNothing() {
        #expect(!WeatherAttribution.required(for: Self.reply([])))
    }

    /// **435-B.** Another tool completing is not this tool completing.
    @Test("435-B · a different completed tool requires nothing")
    func aDifferentCompletedToolRequiresNothing() {
        let message = Self.reply([
            ToolActivity(label: "readHealth", isActive: false),
            ToolActivity(label: "readCalendar", isActive: false)
        ])
        #expect(!WeatherAttribution.required(for: message))
    }

    /// **435-B.** A weather call still in flight has displayed nothing yet.
    @Test("435-B · a weather call still running requires nothing yet")
    func aWeatherCallStillRunningRequiresNothingYet() {
        #expect(!WeatherAttribution.required(for: Self.reply([Self.weatherActivity(isActive: true)])))
    }

    /// **435-B.** A FAILED lookup showed no Apple data, so it owes no
    /// attribution. All three markers that reach `failure` are covered: the
    /// host's unspecified error, the user's Stop (#296), and a system-revoked
    /// turn.
    @Test("435-B · a failed, stopped or interrupted weather call requires nothing",
          arguments: ["the weather service rejected this app's credentials",
                      ToolActivity.stoppedByUser,
                      ToolActivity.interruptedBySystem])
    func aFailedWeatherCallRequiresNothing(failure: String) {
        #expect(!WeatherAttribution.required(for: Self.reply([Self.weatherActivity(failure: failure)])))
    }

    /// **435-B.** `failure` wins over `isActive`, exactly as
    /// `ToolActivityRail.state(of:)` decides it — `ChatStore.cancelStreaming`
    /// writes the marker and clears `isActive` in two separate passes, so a
    /// stopped call can be seen mid-way with both set.
    @Test("435-B · a stopped call that is still marked active requires nothing")
    func aStoppedCallStillMarkedActiveRequiresNothing() {
        let message = Self.reply([Self.weatherActivity(isActive: true, failure: ToolActivity.stoppedByUser)])
        #expect(!WeatherAttribution.required(for: message))
    }

    /// **435-B, the other direction.** A failed call followed by a successful
    /// retry DID display Apple data. The rule is "any completed weather call",
    /// not "no failed ones" — a turn whose second attempt worked owes the
    /// attribution.
    @Test("435-B · a failed call plus a completed one still requires it")
    func aFailedCallPlusACompletedOneStillRequiresIt() {
        let message = Self.reply([
            Self.weatherActivity(failure: ToolActivity.stoppedByUser),
            Self.weatherActivity()
        ])
        #expect(WeatherAttribution.required(for: message))
    }

    // MARK: - 435-C — the words and the link, pinned

    /// **435-C.** The link is Apple's legal attribution page, character for
    /// character. It is required by Apple's terms rather than chosen by us, so
    /// it is pinned rather than merely referenced.
    @Test("435-C · the legal link is Apple's attribution page, verbatim")
    func theLegalLinkIsApplesAttributionPage() {
        #expect(WeatherAttribution.legalAttributionURL.absoluteString
                == "https://weatherkit.apple.com/legal-attribution.html")
    }

    /// **435-C.** The label carries the Apple Weather trademark AND the
    /// value-added notice Apple's terms require ("a notice that the data
    /// provided by Apple has been modified") — the second half is what a
    /// model's prose about the weather makes necessary.
    @Test("435-C · the label names Apple Weather and says the data was modified")
    func theLabelNamesAppleWeatherAndTheModification() {
        #expect(WeatherAttribution.label.contains("Apple Weather"))
        #expect(WeatherAttribution.label.lowercased().contains("modified"))
        #expect(WeatherAttribution.accessibilityLabel.contains(WeatherAttribution.label),
                "the spoken label must carry the same words as the row (#371-E)")
    }

    /// **435-C.** Tapping hands Apple's page to the system with `openURL` — no
    /// in-app browser, no embedded frame.
    @Test("435-C · the row opens the link with openURL, never a web view")
    func theRowOpensTheLinkWithOpenURL() throws {
        let source = try Self.read("Talaria/Features/Chat/WeatherAttribution.swift")
        #expect(source.contains("openURL(WeatherAttribution.legalAttributionURL)"),
                "the row no longer opens the legal link with openURL")
        for banned in ["WKWebView", "SFSafariViewController", "SafariView", "WebView"] {
            #expect(!source.contains(banned),
                    "\(banned) appears in the attribution row — 435-C pins openURL, not an in-app browser")
        }
    }

    // MARK: - 435-D — the notice document

    /// **435-D.** `THIRD_PARTY_LICENSES.md` grouped WeatherKit with the Apple
    /// frameworks that carry "no attribution obligation" — conflating USING the
    /// framework (which owes nothing) with DISPLAYING its data (which does).
    /// The blanket bullet must no longer name WeatherKit.
    ///
    /// Asserted against the bullet rather than the section, so the correction
    /// that follows it — which of course says "WeatherKit" — cannot make this
    /// check pass by accident.
    @Test("435-D · WeatherKit is no longer filed under \"no attribution obligation\"")
    func weatherKitIsNotFiledUnderNoAttributionObligation() throws {
        let section = try Self.notCoveredHereSection(of: try Self.read("THIRD_PARTY_LICENSES.md"))
        let bullets = section.components(separatedBy: "\n- ")
        let blanket = try #require(
            bullets.first(where: { $0.contains("no attribution obligation") }),
            "the \"no attribution obligation\" bullet is gone — this check did not run"
        )
        #expect(!blanket.contains("WeatherKit"),
                "WeatherKit is still listed among the frameworks with no attribution obligation")
    }

    /// **435-D.** The correction is not merely a deletion: the document has to
    /// SAY what WeatherKit owes, and carry the URL a reader can follow.
    @Test("435-D · the section states WeatherKit's display obligation and links Apple's page")
    func theNoticeDocumentStatesTheWeatherKitObligation() throws {
        let section = try Self.notCoveredHereSection(of: try Self.read("THIRD_PARTY_LICENSES.md"))
        #expect(section.contains("WeatherKit"),
                "the section no longer mentions WeatherKit at all — deleting the claim is not correcting it")
        #expect(section.contains("Apple Weather"),
                "the section does not name the Apple Weather attribution")
        #expect(section.contains("https://weatherkit.apple.com/legal-attribution.html"),
                "the section does not carry Apple's legal-attribution URL")
    }

    // MARK: - 435-E — voice, MEASURED

    /// **435-E is a MEASUREMENT, not a mechanism.** It records what the voice
    /// path does TODAY so 435-A's coverage claim is not guessed at.
    ///
    /// **Measured answer: NO — a voice transcript row carries no
    /// `toolActivities`, so 435-A does not cover voice.** Two independent
    /// sites, either of which alone is sufficient:
    ///
    ///  1. `NativeVoicePipelineService.swift`'s stream loop consumes
    ///     `.toolActivity` only to move `voiceState`/`statusMessage` — the
    ///     event is dropped, never recorded onto anything that outlives the
    ///     turn.
    ///  2. `ChatStore.voiceTranscriptMessages(from:)` composes every transcript
    ///     row as `Message(sender:content:status:)`, so `toolActivities`
    ///     defaults to `[]` no matter what ran during the session.
    ///
    /// This test pins site 2, which is the one a unit can reach. **If it ever
    /// goes red because voice rows now carry activities, that is the follow-up
    /// landing — delete this test and re-measure 435-A's coverage.** It is a
    /// record of a measured gap, not a defence of it.
    @Test("435-E · MEASURED: voice transcript rows carry no toolActivities")
    func voiceTranscriptRowsCarryNoToolActivities() {
        let session = CompletedVoiceSession(
            voiceSessionId: UUID(),
            duration: 42,
            turnCount: 2,
            transcript: [
                TranscriptItem(speaker: .user, text: "what's the weather"),
                TranscriptItem(speaker: .hermes, text: "It's 68 and clear.")
            ],
            engine: .native
        )
        let rows = ChatStore.voiceTranscriptMessages(from: session)
        #expect(rows.count == 3, "banner + two spoken turns")
        for row in rows {
            #expect(row.toolActivities.isEmpty,
                    "a voice transcript row carries no tool activities — 435-E's measured gap")
        }
    }
}
