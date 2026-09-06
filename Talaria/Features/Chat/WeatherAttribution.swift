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
// persists — `Message.toolActivities` — and the row renders on the strength of
// that record, whatever the model said.
//
// Nothing here needs a new persisted field: `toolActivities` is already part of
// `Message.CodingKeys`, so the attribution survives relaunch for free (pinned
// by `attributionSurvivesACodingRoundTrip`).

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
    static let legalAttributionURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

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

    /// Whether this message must carry the attribution.
    static func required(for message: Message) -> Bool {
        required(for: message.toolActivities)
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
    /// A `.reconstructed` activity (#371 — rebuilt from a server transcript,
    /// never witnessed completing) DOES count. #371's rule is that the chip
    /// must not claim it watched the call finish; this row makes no such claim.
    /// Attributing data that may not have been shown is a stray line;
    /// withholding attribution from data that was is the compliance failure, so
    /// the tie goes to attributing.
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
            openURL(WeatherAttribution.legalAttributionURL)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(WeatherAttribution.accessibilityLabel)
        .accessibilityIdentifier("weather.attribution")
    }
}
