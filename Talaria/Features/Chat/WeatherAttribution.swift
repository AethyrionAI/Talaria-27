import SwiftUI

// MARK: - #435: deterministic Apple Weather attribution
//
// Apple's WeatherKit terms (`developer.apple.com/weatherkit/#attribution-
// requirements`, read 2026-09-06) put two obligations on an app that shows
// Apple's weather data:
//
//   * display the Apple Weather trademark plus the legal link to Apple's data
//     sources, and
//   * for a VALUE-ADDED product built out of that data, attribute the source
//     to Apple Weather "along with a notice that the data provided by Apple has
//     been modified."
//
// A model's prose about the weather is a value-added product, so this app owes
// both halves — which is why the label below names Apple Weather AND says the
// data was modified, and why it carries the legal link.
//
// **The attribution is DERIVED, never model-authored.** The entry this lane
// closes was filed because the weather tool's output reaches the model as
// ordinary text and nothing deterministic attributed it: a reply that happened
// to mention Apple satisfied nobody, and a reply that did not was a compliance
// gap. So the rule is a pure function of the transcript the app already
// persists — `Message.toolActivities` for WHAT ran and `Message.brain` for
// WHOSE weather service ran it — and the row renders on the strength of that
// record, whatever the model said.
//
// Nothing here needs a new persisted field: both `toolActivities` and `brain`
// are already part of `Message.CodingKeys`, so the attribution survives
// relaunch for free (pinned by `attributionSurvivesACodingRoundTrip`).

/// The rule, the words and the link — one type so no surface can drift from
/// another, and so the predicate can be asserted as a value instead of being
/// inferred from a view body.
enum WeatherAttribution {

    /// The tool whose completed call owes the attribution.
    ///
    /// It is `WeatherTool.name` verbatim, and that is the whole chain: the belt
    /// stamps this string onto the event (`ToolEventRelay.started` emits
    /// `ToolCallEvent(name:)`), and `ChatStore` writes `event.name` straight
    /// into `ToolActivity.label`. A runtime pin
    /// (`thePinnedToolNameIsTheWeatherToolsOwnName`) fails if the tool is ever
    /// renamed out from under this constant — the failure mode being a silent
    /// stop, which is exactly the kind a source-witness has to catch.
    static let toolName = "currentWeather"

    /// Apple's legal attribution page. Pinned verbatim by bar 435-C: this is
    /// the link Apple's terms require beside the trademark, not a page we chose.
    ///
    /// **Two fix-round corrections live in this one constant.**
    ///
    ///  * **The address.** `weatherkit.apple.com/legal-attribution.html` is
    ///    Apple's LEGACY link and answers only through a 308 redirect to the
    ///    URL below — which is the one Apple's own attribution-requirements
    ///    page names, verified live (200, carrying the data-source list). A
    ///    compliance surface should not depend on someone else's redirect
    ///    staying up.
    ///  * **The construction.** The pinned STRING is the truth and the `URL`
    ///    is derived from it, optionally: the house rule forbids force-unwrapping
    ///    `URL(string:)` on network code, and an attribution row is the last
    ///    place to keep a crash. Nothing is lost by the optional, because the
    ///    row draws its WORDS unconditionally and only the TAP is conditional —
    ///    a nil here could never silence the attribution itself, and
    ///    `theLegalLinkIsApplesAttributionPage` requires it to resolve anyway.
    static let legalAttributionURLString = "https://developer.apple.com/weatherkit/data-source-attribution/"
    static let legalAttributionURL: URL? = URL(string: legalAttributionURLString)

    /// The one line the transcript shows.
    ///
    /// **The words, and why they are these words.** "Apple Weather" is the
    /// trademark Apple's terms name; "modified by Talaria" is the value-added
    /// notice the same section requires, in the app's own outward identity.
    ///
    /// **Why the name and not the  Weather mark.** Apple's terms accept the
    /// trademark rendered with the Apple logo glyph (U+F8FF), but this row is
    /// set in JetBrains Mono — a bundled custom face with no glyph at that
    /// private-use code point — so the mark would render as a fallback box in
    /// the one place it must read cleanly. The words carry the same trademark.
    static let label = "Weather data by Apple Weather, modified by Talaria"

    /// #371-E's rule: the spoken label carries the SAME WORDS as the row, plus
    /// what tapping does. A paraphrase is how a label drifts from the claim on
    /// screen.
    static let accessibilityLabel =
        "\(label). Opens Apple's legal attribution page."

    /// Whether a reply's recorded brain is one whose weather data came from
    /// **this app's own WeatherKit belt**.
    ///
    /// **Why the rule needs an origin at all (fix round, final review).**
    /// `toolName` is a bare string and nothing upstream of it is namespaced:
    /// `ChatStore` writes `label: event.name` verbatim for any tool on any
    /// brain — the host's runs stream included — and
    /// `SessionsHermesClient.mapStoredMessage` mints the same labels again when
    /// it rebuilds a host transcript into `.reconstructed` activities. Without
    /// this check a Hermes-side tool that happened to be called
    /// `currentWeather` would render Apple's trademark over data Apple never
    /// supplied, which is a false attribution rather than a cautious one.
    ///
    /// The switch is exhaustive on purpose: a fourth brain has to ANSWER this
    /// question rather than inherit an answer.
    static func isLocalBrain(_ rawBrain: String?) -> Bool {
        guard let rawBrain, let brain = ChatBackendRouter.Brain(rawValue: rawBrain) else { return false }
        switch brain {
        case .onDevice, .privateCloud: return true
        case .hermes: return false
        }
    }

    /// Whether this message must carry the attribution.
    ///
    /// Two conditions: the transcript must record a completed weather call,
    /// **and** the reply must have come from a brain this app's own WeatherKit
    /// belt serves.
    ///
    /// **The nil-brain carve-out, and why it is exactly this narrow.**
    /// `ChatStore` mints the streaming placeholder with no brain at all, and
    /// `ChatBackendRouter` stamps one only at `.finished`. A strict check would
    /// therefore withhold the attribution for the ENTIRE length of a live local
    /// weather reply — the exact window this row was deliberately placed
    /// outside `!isStreaming` to cover, because the moment the lookup returns,
    /// Apple's data is on screen. So an unrecorded brain counts only while the
    /// turn is STILL STREAMING; once a reply has settled, an unknown brain is
    /// treated as hosted, which is what a rebuilt host transcript row actually
    /// is. The residual is a row that appears and then vanishes if a host tool
    /// is ever named `currentWeather` — visibly self-correcting, where the
    /// alternative was an unattributed live reply.
    ///
    /// **The HOSTED path is not covered, and that is measured rather than
    /// assumed.** The default Hermes brain does serve real WeatherKit data
    /// (`PhoneQueryResponder.weather` calls `WeatherTool.performLookup`), but
    /// that read emits no local activity (`emit` is nil), and the only record
    /// the app sees is the host's own `tool.started` frame — which carries a
    /// tool NAME and `preview` and no arguments
    /// (`SessionsHermesClient+RunsTransport.swift:293-295`, `:432-436`). The
    /// plugin serves all seven phone-query kinds under one tool name, with
    /// `kind` as an argument, so a hosted weather read is indistinguishable
    /// from a hosted health or calendar read on this wire. Attributing on the
    /// name alone would repeat the very defect the brain check above closes, so
    /// the app renders nothing there and the gap is filed as a follow-up.
    static func required(for message: Message) -> Bool {
        let originIsOurBelt = isLocalBrain(message.brain)
            || (message.brain == nil && message.isStreaming)
        return originIsOurBelt && required(for: message.toolActivities)
    }

    /// The rule itself: **a weather call that COMPLETED.**
    ///
    /// `ToolActivityRail.state(of:)` is reused rather than re-derived. "Did
    /// this call finish, fail, or is it still running" already has exactly one
    /// home in this app, and a second copy of that three-way decision would
    /// drift the first time either moved — the seam-between-green-units shape.
    ///
    /// The two exclusions are bar 435-B and both are deliberate:
    ///
    ///  * **`.running`** — the call has not come back, so no Apple data has
    ///    been displayed yet. The row appears the moment it does.
    ///  * **`.interrupted`** (`failure != nil` — a host-reported failure, the
    ///    user's Stop, or a revoked turn) — a lookup that failed showed no
    ///    Apple data, so it owes no attribution.
    ///
    /// **⟵ CORRECTED in the fix round.** This paragraph used to say a
    /// `.reconstructed` activity (#371 — rebuilt from a server transcript,
    /// never witnessed completing) DOES count. As a statement about THIS
    /// function it is still true, and as a statement about the app it is now
    /// false: `.reconstructed` activities are minted at exactly one site
    /// (`SessionsHermesClient.mapStoredMessage`), which rebuilds HOST
    /// transcripts and sets no `brain` — so the origin check in
    /// `required(for message:)` excludes every one of them before this
    /// predicate is ever consulted. The #371 reasoning that justified counting
    /// them is unchanged and simply no longer reachable from the row.
    ///
    /// The tie still goes to attributing WITHIN a local reply: attributing data
    /// that may not have been shown is a stray line, while withholding
    /// attribution from data that was is the compliance failure. What the fix
    /// round changed is that the tie is only broken once the reply's ORIGIN is
    /// this app's own belt.
    ///
    /// **One known over-attribution, recorded rather than hidden.** The belt
    /// calls `relay.completed` even when the lookup returned an honest
    /// non-answer — "Location permission is not granted…", "Couldn't find a
    /// place called …" — because that sentence IS the tool's result. Those
    /// turns display no Apple data and still get the row. Separating them would
    /// need the tool's outcome carried onto `ToolActivity`, i.e. a new coding
    /// key on a persisted type, which is a different lane; the current
    /// behaviour errs toward attributing and is the safe direction.
    static func required(for activities: [ToolActivity]) -> Bool {
        activities.contains { activity in
            activity.label == toolName && ToolActivityRail.state(of: activity) == .completed
        }
    }
}

// MARK: - The row

/// The attribution line itself: one muted row under the reply's content,
/// always visible on a loaded reply — never behind a disclosure, because an
/// attribution the reader has to open is not displayed.
///
/// Tapping opens Apple's page with `openURL`, not an in-app web view (bar
/// 435-C). That is not a styling preference: the legal link is Apple's page,
/// and handing it to the system browser is the honest, unframed presentation
/// of someone else's document — and it keeps this row out of #429's remote-
/// content consent surface entirely.
struct WeatherAttributionRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = WeatherAttribution.legalAttributionURL { openURL(url) }
        } label: {
            HStack(spacing: Design.Spacing.xxs) {
                // A plain `Text`, deliberately NOT `MonoLabel`: MonoLabel
                // force-uppercases, and "WEATHER DATA BY APPLE WEATHER" turns
                // a trademark into telemetry. Same font token, same muted
                // color — only the casing is preserved.
                Text(WeatherAttribution.label)
                    .font(Design.Typography.monoSmall)
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.mutedForeground)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Design.Colors.dimForeground)
            }
            // The words are set small on purpose — this is a footnote, not a
            // headline — but the TAP TARGET is not: Apple's own minimum is
            // 44×44, and a ~10-point-tall link on a compliance row is one the
            // reader cannot reliably follow. The frame goes INSIDE the button's
            // label so the hit region is the button's, and `contentShape` makes
            // the whole (mostly empty) rectangle tappable rather than just the
            // glyphs.
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WeatherAttribution.accessibilityLabel)
        .accessibilityIdentifier("weather.attribution")
    }
}
