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

    /// A settled **on-device** reply unless told otherwise.
    ///
    /// The brain is part of the fixture because it is part of the RULE (final
    /// review, Important 3): `currentWeather` is this app's OWN belt tool, and
    /// a Hermes-side tool that happened to share the name would otherwise
    /// render Apple's trademark over data Apple never supplied.
    private static func reply(
        _ activities: [ToolActivity],
        brain: ChatBackendRouter.Brain? = .onDevice,
        isStreaming: Bool = false
    ) -> Message {
        Message(sender: .hermes,
                content: "It's 68 and clear in Gulfport, clearing tonight.",
                status: .delivered,
                toolActivities: activities,
                brain: brain?.rawValue,
                isStreaming: isStreaming)
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

    // MARK: - 435-B (final review, Important 3) — the ORIGIN check

    /// **Important 3.** `currentWeather` is a bare string, and
    /// `ChatStore.swift:1350` writes `label: event.name` verbatim for ANY tool
    /// on ANY brain — the host's runs stream included. So a Hermes-side tool
    /// that happened to be named `currentWeather` would have rendered "Weather
    /// data by Apple Weather" over data Apple never supplied. The rule now
    /// requires the message's own recorded brain to be one this app's WeatherKit
    /// belt actually runs on.
    ///
    /// This is the row the ruling asks for: **a settled host-brain message with
    /// a completed `currentWeather` activity gets nothing.**
    @Test("435-B · a settled Hermes-brain reply gets no row, whatever the tool was called")
    func aSettledHostBrainReplyGetsNoRow() {
        let message = Self.reply([Self.weatherActivity()], brain: .hermes)
        #expect(!WeatherAttribution.required(for: message),
                "a host tool named currentWeather is not this app's WeatherKit belt")
    }

    /// **Important 3, the other direction.** Both brains that run this app's
    /// own belt still owe the attribution — the origin check must not have
    /// narrowed the rule to on-device alone.
    @Test("435-A · both local brains still require the attribution",
          arguments: [ChatBackendRouter.Brain.onDevice, .privateCloud])
    func bothLocalBrainsRequireTheAttribution(brain: ChatBackendRouter.Brain) {
        #expect(WeatherAttribution.required(for: Self.reply([Self.weatherActivity()], brain: brain)))
    }

    /// **Important 3.** A message with NO recorded brain that has SETTLED is
    /// treated as hosted, and that is the vector the finding named:
    /// `SessionsHermesClient.mapStoredMessage` rebuilds a host transcript's
    /// tool calls into `.reconstructed` activities and never sets `brain`, so
    /// an unknown brain on a finished row is a host row far more often than a
    /// pre-#27 local cache.
    @Test("435-B · a settled reply with no recorded brain gets no row")
    func aSettledReplyWithNoRecordedBrainGetsNoRow() {
        #expect(!WeatherAttribution.required(for: Self.reply([Self.weatherActivity()], brain: nil)))
    }

    /// **Fix round 2 — the streaming carve-out is RETIRED, and this row is
    /// what replaced it.**
    ///
    /// The fix round shipped `isLocalBrain(brain) || (brain == nil &&
    /// isStreaming)`: the placeholder was minted with no brain and only
    /// `.finished` ever stamped one, so a strict check would have withheld
    /// the attribution for the whole length of a live local weather reply.
    /// The carve-out bought that window at the price of trusting
    /// `isStreaming` as a proxy for origin — and the re-review found the bill:
    /// `ChatStore.cancelStreaming` settles the placeholder in place
    /// (`isStreaming = false`, `.delivered`) and stamps NO brain, so a
    /// stopped local weather turn kept Apple's data on screen, unattributed,
    /// forever.
    ///
    /// The window is now covered at its source instead — the placeholder
    /// carries its run's brain from the moment `sendStreaming` returns
    /// (`aLiveLocalWeatherReplyIsAttributedWhileItStreams`) — so `isStreaming`
    /// buys the rule nothing and an unknown origin is an unknown origin in
    /// both states.
    @Test("435-B · a streaming reply with no recorded brain gets no row either")
    func aStreamingReplyWithNoRecordedBrainGetsNoRowEither() {
        #expect(!WeatherAttribution.required(
            for: Self.reply([Self.weatherActivity()], brain: nil, isStreaming: true)),
                "an unknown origin is unknown whether or not the turn has settled")
    }

    /// **Fix round 2, the other direction.** A live reply that HAS its brain
    /// is attributed while it streams — the compliance window the retired
    /// carve-out existed to cover, now answered by the origin itself.
    @Test("435-A · a still-streaming reply that knows its brain requires it")
    func aStreamingReplyThatKnowsItsBrainRequiresIt() {
        #expect(WeatherAttribution.required(
            for: Self.reply([Self.weatherActivity()], brain: .onDevice, isStreaming: true)))
    }

    // MARK: - 435-F (final review, Important 1) — the HOST path, MEASURED

    /// **Important 1 is a MEASUREMENT, and the measured answer is: the app
    /// cannot identify a hosted weather read, so it renders nothing and says
    /// so.**
    ///
    /// The default (Hermes) brain DOES serve real WeatherKit data —
    /// `PhoneQueryResponder.swift:57-58` calls
    /// `WeatherTool.performLookup(…, name: "currentWeather")` and
    /// `AppContainer.swift:1084-1087` wires it into `TalariaPlatformLink` in
    /// production — and that read writes no local `ToolActivity` at all
    /// (`PhoneQueryResponder.swift:131-133`: `emit` is nil). The only record
    /// the app ever sees is the HOST's own `tool.started` frame, and that frame
    /// cannot say "weather":
    ///
    ///  1. The plugin exposes ONE tool for all seven reads — the app's own
    ///     responder mirrors its shape, `answer(kind:params:)`, dispatching
    ///     `health` / `location` / `motion` / `weather` / `calendar` /
    ///     `reminders` / `deviceStatus` off an ARGUMENT
    ///     (`PhoneQueryResponder.swift:118-160`). The name is the same for a
    ///     weather read and a health read.
    ///  2. The runs stream — the only turn transport since #382 — carries a
    ///     tool's NAME and `preview` and **no arguments at all**:
    ///     `SessionsHermesClient+RunsTransport.swift:293-295` parses exactly
    ///     `tool` + `preview`, and `:432-436` records why ("the runs
    ///     `tool.started` carries no `args`", cited to `api_server.py`).
    ///
    /// Name without argument cannot discriminate, so a rule keyed on the
    /// hosted tool name would attribute Apple Weather over six kinds of read
    /// that are not weather — the same false-attribution defect Important 3
    /// closed, in the other direction. **Not guessed; filed.** This row pins
    /// the measured behaviour: a hosted phone-query activity gets no row.
    ///
    /// **It fails for the reason the docstring gives (fix round 2, review
    /// note).** This row used to assert one thing — a hosted activity on a
    /// `.hermes` message — which the ORIGIN check answers before the tool
    /// name is ever read, so the mechanism it claims to measure was never
    /// exercised. The first expectation below reaches the array-level
    /// predicate directly, with no origin in the way: the hosted name simply
    /// is not the belt's name, and that stays true whatever brain is
    /// stamped. The `.onDevice` arm makes that hypothetical explicit and the
    /// `.hermes` arm keeps the production shape.
    @Test("435-F · MEASURED: a hosted phone-query activity cannot be identified as weather")
    func aHostedPhoneQueryActivityGetsNoRow() {
        let hosted = [ToolActivity(label: "talaria_phone_query", isActive: false, detail: nil)]
        #expect(!WeatherAttribution.required(for: hosted),
                "the hosted tool name is shared by all seven phone-query kinds — see this test's docstring")
        #expect(!WeatherAttribution.required(for: Self.reply(hosted, brain: .onDevice)),
                "even stamped as local, a hosted phone-query activity says nothing about weather")
        #expect(!WeatherAttribution.required(for: Self.reply(hosted, brain: .hermes)))
    }

    // MARK: - 435-C — the words and the link, pinned

    /// **435-C.** The link is Apple's legal attribution page, character for
    /// character. It is required by Apple's terms rather than chosen by us, so
    /// it is pinned rather than merely referenced.
    ///
    /// **The URL changed in the fix round (final review, Important 2).**
    /// `https://weatherkit.apple.com/legal-attribution.html` is Apple's LEGACY
    /// link and answers only through a 308 redirect; the URL Apple's own
    /// attribution-requirements page names is the developer.apple.com one
    /// below, verified live this session as a 200 carrying the data-source
    /// list. A pinned link that depends on someone else's redirect staying up
    /// is a compliance surface with a dependency nobody wrote down.
    @Test("435-C · the legal link is Apple's attribution page, verbatim")
    func theLegalLinkIsApplesAttributionPage() throws {
        #expect(WeatherAttribution.legalAttributionURLString
                == "https://developer.apple.com/weatherkit/data-source-attribution/")
        let url = try #require(WeatherAttribution.legalAttributionURL,
                               "the pinned string no longer parses as a URL — the row's tap is dead")
        #expect(url.absoluteString == WeatherAttribution.legalAttributionURLString)
    }

    /// **435-C (final review, minor).** House rule: no force-unwraps on
    /// network code. `URL(string: …)!` on a compliance row is the worst place
    /// to keep one — a crash where an attribution belongs.
    @Test("435-C · the pinned URL is built without a force-unwrap")
    func thePinnedURLIsBuiltWithoutAForceUnwrap() throws {
        let source = try Self.read("Talaria/Features/Chat/WeatherAttribution.swift")
        #expect(!source.contains(")!"),
                "a force-unwrapped literal is back in the attribution source")
    }

    /// **435-C (final review, minor).** A 10-point-tall tap target on a link
    /// the user is meant to be able to follow fails Apple's own 44×44 minimum.
    /// The words render at their own size; the HIT REGION is the full-width
    /// container, at least 44 points tall.
    @Test("435-C · the link's hit region is a full-width 44-point target")
    func theLinksHitRegionIsAFullWidth44PointTarget() throws {
        let source = try Self.read("Talaria/Features/Chat/WeatherAttribution.swift")
        let normalized = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(normalized.contains(
            ".frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) .contentShape(Rectangle())"),
                "the tappable area is back to the intrinsic size of the text")
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
        let normalized = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(normalized.contains("if let url = WeatherAttribution.legalAttributionURL { openURL(url) }"),
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
        #expect(section.contains(WeatherAttribution.legalAttributionURLString),
                "the section does not carry the same legal-attribution URL the app opens")
        #expect(!section.contains("weatherkit.apple.com/legal-attribution.html"),
                "the document still carries Apple's legacy redirect link")
    }

    /// **435-D (final review, minor).** The document QUOTES the attribution
    /// line. A quote is a claim about what the app draws, and the two drift
    /// silently — the notice is read by people who will never diff it against
    /// `WeatherAttribution.label`.
    ///
    /// The document wraps the sentence across lines, so the comparison
    /// normalizes whitespace on both sides; nothing else about the quote is
    /// allowed to differ.
    @Test("435-D · the document quotes the app's attribution line verbatim")
    func theDocumentQuotesTheAppsAttributionLineVerbatim() throws {
        let section = try Self.notCoveredHereSection(of: try Self.read("THIRD_PARTY_LICENSES.md"))
        let normalized = section.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(normalized.contains(WeatherAttribution.label),
                "the quoted line has drifted from WeatherAttribution.label")
    }

    /// **435-D (final review, Important 1).** The document used to say Talaria
    /// "owes both halves. It renders them deterministically" — a coverage claim
    /// wider than the mechanism's measured reach. The rule fires on the
    /// on-device and Private Cloud brains; the HOSTED path serves real
    /// WeatherKit data through `talaria_phone_query` and is not covered,
    /// because the runs stream carries a tool's name without its arguments
    /// (see `aHostedPhoneQueryActivityGetsNoRow`). A notice document that
    /// over-claims is the one document where over-claiming matters.
    @Test("435-D · the document scopes its coverage claim to the brains it covers")
    func theDocumentScopesItsCoverageClaim() throws {
        let section = try Self.notCoveredHereSection(of: try Self.read("THIRD_PARTY_LICENSES.md"))
        let normalized = section.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(normalized.contains("on-device and Private Cloud brains"),
                "the document does not name the brains the mechanism actually covers")
        #expect(normalized.contains("talaria_phone_query"),
                "the document does not name the hosted path it cannot cover")
        #expect(normalized.lowercased().contains("follow-up"),
                "the document does not record the hosted path as an open follow-up")
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

    // MARK: - Fix round 2 — the placeholder learns its brain at stream START

    /// A hand-driven client in the shape of the production pair `ChatStore`
    /// actually holds: `ChatBackendRouter` in front of `LocalChatBackend`.
    /// Two properties of that pair are load-bearing here, and both are
    /// modelled deliberately rather than assumed:
    ///
    ///  1. **The brain is resolved before `sendStreaming` RETURNS.**
    ///     `ChatBackendRouter.sendStreaming` picks the brain, takes the
    ///     routing lock and sets `runningBrain` in its own first statements —
    ///     all synchronous, ahead of the `AsyncStream` it hands back. So
    ///     `currentRunBrain` answers from the instant the call comes back,
    ///     which is the whole reason the placeholder can be stamped there.
    ///  2. **The local backend keeps its own transcript copy, with no brain
    ///     on it.** `LocalChatBackend.appendAssistantMessage` stores the very
    ///     `Message` it then yields in `.finished`, and only the ROUTER's
    ///     copy is stamped (`ChatBackendRouter.swift:478`). `ChatStore` merges
    ///     that stored transcript over its own the statement after the settle
    ///     (`ChatStore.swift:1651`) — which is what
    ///     `aFinishedLocalTurnKeepsTheBrainItRanOn` measures.
    @MainActor
    private final class LocalBeltClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        /// The on-device/PCC brain is not server-recoverable, so a Stop takes
        /// `cancelStreaming`'s settle-in-place branch — the one this round is
        /// about. (`ChatBackendRouter.currentRunIsServerRecoverable` is
        /// `runningBrain == .hermes`.)
        var currentRunIsServerRecoverable = false
        /// What the router answers while the routing lock is held. Nil until
        /// the first send, exactly like `runningBrain`.
        var currentRunBrain: String?
        private let brainForRun: String?
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []

        init(brain: ChatBackendRouter.Brain) { self.brainForRun = brain.rawValue }

        @discardableResult
        func hardStopActiveRun() -> Bool { false }

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            // Point 1 above: routing is resolved HERE, before the stream is
            // returned — not when the first frame arrives.
            currentRunBrain = brainForRun
            return AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                self.continuations.append(continuation)
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }

        func reconcileFromServer() async -> Conversation? { nil }
    }

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "weather-attribution-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    @MainActor
    private func pollUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @MainActor private static func streamingReply(in store: ChatStore) -> Message? {
        store.conversation?.messages.last { $0.sender == .hermes && $0.isStreaming }
    }

    @MainActor private static func settledReply(in store: ChatStore) -> Message? {
        store.conversation?.messages.last { $0.sender == .hermes }
    }

    /// Drives a real turn to the state this round is about: a live stream
    /// whose transcript already records a COMPLETED `currentWeather` call —
    /// i.e. Apple's data is on screen and the turn has not settled yet.
    ///
    /// The frames are the ones `LocalChatBackend` emits for a belt call
    /// (`.toolActivity(.started)` → prose → `.toolActivity(.completed)`,
    /// `LocalChatBackend.swift:1292-1296`), applied by
    /// `ChatStore.swift:1332-1380`.
    @MainActor
    private func startWeatherTurn(
        store: ChatStore, client: LocalBeltClient
    ) async throws -> (send: Task<Bool, Never>, stream: AsyncStream<StreamingUpdate>.Continuation) {
        let sendTask = Task { @MainActor in await store.sendMessage("what's the weather in Gulfport") }
        let live = await pollUntil { store.isStreaming && !client.continuations.isEmpty }
        #expect(live, "the turn must be streaming before the test proceeds")
        let stream = try #require(client.continuations.last)
        stream.yield(.toolActivity(ToolCallEvent(
            name: WeatherAttribution.toolName, phase: .started, detail: "Gulfport")))
        stream.yield(.textDelta("It's 68 and clear in Gulfport."))
        stream.yield(.toolActivity(ToolCallEvent(
            name: WeatherAttribution.toolName, phase: .completed)))
        let applied = await pollUntil {
            Self.streamingReply(in: store)?.toolActivities.contains {
                $0.label == WeatherAttribution.toolName && !$0.isActive && $0.failure == nil
            } ?? false
        }
        #expect(applied, "the completed weather call must be on the placeholder before the test proceeds")
        return (sendTask, stream)
    }

    /// **Fix round 2.** The live window, through the real store: the moment
    /// the lookup comes back, Apple's data is on screen and the row must be
    /// there — and it is there because the placeholder KNOWS its origin, not
    /// because `isStreaming` excused it from knowing.
    @Test("435-A · a live local weather reply is attributed while it streams")
    @MainActor
    func aLiveLocalWeatherReplyIsAttributedWhileItStreams() async throws {
        let client = LocalBeltClient(brain: .onDevice)
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let turn = try await startWeatherTurn(store: store, client: client)

        let live = try #require(Self.streamingReply(in: store))
        #expect(live.brain == ChatBackendRouter.Brain.onDevice.rawValue,
                "the placeholder must carry the brain its run was routed to, from stream start")
        #expect(WeatherAttribution.required(for: live),
                "Apple's data is on screen the moment the lookup returns — the row belongs there")

        turn.stream.finish()
        turn.send.cancel()
    }

    /// **Fix round 2 — THE regression this round exists to close.**
    ///
    /// `ChatStore.cancelStreaming` settles the placeholder in place
    /// (`isStreaming = false`, `.delivered`) and marks only the activities
    /// that were STILL ACTIVE; a weather call that already completed keeps
    /// `failure == nil`. Nothing on that path ever stamped a brain — the only
    /// two `.brain =` writes in the app are on `.finished`
    /// (`ChatBackendRouter.swift:447, 478`) — so under the fix round's
    /// origin check the settled row read `brain == nil, isStreaming == false`
    /// and the attribution vanished the instant the user tapped Stop, over
    /// data that stays on screen. Permanently: the row persists that way.
    @Test("435-B · a stopped local turn keeps the attribution its transcript earned")
    @MainActor
    func aStoppedLocalTurnKeepsTheAttribution() async throws {
        let client = LocalBeltClient(brain: .onDevice)
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let turn = try await startWeatherTurn(store: store, client: client)

        store.cancelStreaming(hardStopHost: true)

        let settled = try #require(Self.settledReply(in: store))
        #expect(settled.isStreaming == false, "Stop settles the placeholder in place")
        #expect(settled.status == .delivered)
        #expect(settled.brain == ChatBackendRouter.Brain.onDevice.rawValue,
                "the settled row must still know which brain served it")
        #expect(WeatherAttribution.required(for: settled),
                "the weather Apple served is still on screen after a Stop — so is the attribution it owes")

        turn.stream.finish()
        turn.send.cancel()
    }

    /// **Fix round 2, the guard on the other side.** The stamp must record
    /// the run's REAL brain, not assert a local one. A stopped HOST turn whose
    /// transcript happens to carry a completed `currentWeather` activity still
    /// gets nothing — Important 3's rule, now proven through the settle path
    /// rather than only against a hand-built message.
    @Test("435-B · a stopped HOST turn is attributed to nobody")
    @MainActor
    func aStoppedHostTurnGetsNoRow() async throws {
        let client = LocalBeltClient(brain: .hermes)
        client.currentRunIsServerRecoverable = false   // an explicit Stop settles in place either way
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let turn = try await startWeatherTurn(store: store, client: client)

        store.cancelStreaming(hardStopHost: true)

        let settled = try #require(Self.settledReply(in: store))
        #expect(settled.brain == ChatBackendRouter.Brain.hermes.rawValue)
        #expect(!WeatherAttribution.required(for: settled),
                "a host tool named currentWeather is not this app's WeatherKit belt")

        turn.stream.finish()
        turn.send.cancel()
    }

    /// **Fix round 2 — the normal path, measured end to end rather than
    /// assumed.** A `.finished` local turn is stamped by the router, and then
    /// `ChatStore` merges the backend's OWN transcript over its own the very
    /// next statement (`ChatStore.swift:1651`). The backend's copy of the
    /// reply carries no brain, so this asserts what survives that merge — the
    /// composed-path question a unit test of either half cannot answer.
    @Test("435-A · a finished local turn keeps the brain it ran on, through the merge")
    @MainActor
    func aFinishedLocalTurnKeepsTheBrainItRanOn() async throws {
        let client = LocalBeltClient(brain: .onDevice)
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let turn = try await startWeatherTurn(store: store, client: client)

        // `LocalChatBackend.appendAssistantMessage(reply)` — the same value it
        // yields at `.finished`, stored WITHOUT a brain (only the router's
        // copy is stamped).
        let reply = Message(sender: .hermes,
                            content: "It's 68 and clear in Gulfport.",
                            status: .delivered)
        client.currentConversation = Conversation(
            title: Conversation.defaultTitle, messages: [reply])
        var stamped = reply
        stamped.brain = ChatBackendRouter.Brain.onDevice.rawValue
        turn.stream.yield(.finished(stamped, nil, nil))
        turn.stream.finish()
        _ = await turn.send.value

        let settled = try #require(Self.settledReply(in: store))
        #expect(settled.toolActivities.contains { $0.label == WeatherAttribution.toolName },
                "the merge carries tool activities — without them this row measures nothing")
        #expect(settled.brain == ChatBackendRouter.Brain.onDevice.rawValue,
                "the settled reply lost the brain its run resolved — #27's tag and #435's row both read this field")
        #expect(WeatherAttribution.required(for: settled))
    }
}
