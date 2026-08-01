#if DEBUG
import CoreLocation
import Foundation
import WeatherKit

/// #212 — the smallest possible WeatherKit call, with nothing else in the way.
///
/// **What it is for.** `currentWeather` has failed 40/40 in three consecutive
/// battery runs with `WDSJWTAuthenticatorServiceListener.Errors error 2`, and
/// every configuration layer we can inspect is correct: the capability is
/// enabled on `org.aethyrion.talaria27`, the entitlement is present in the
/// signed binary AND the embedded provisioning profile, both developer
/// agreements are accepted, the plan is provisioned with a 500k quota showing 0
/// used — and updating the expired payment card changed nothing.
///
/// Two hypotheses have already been refuted on this item (the profile, then
/// billing). Rather than offer a third, this removes everything between the app
/// and the service so the remaining question is answerable:
///
/// - **no model, no router, no tool belt** — the failure cannot be a bad
///   argument or a mis-scoped tool;
/// - **no `DeviceLocationProvider`, no permission prompt, no GPS** — the
///   coordinate is hardcoded, so a location failure cannot masquerade as a
///   weather failure;
/// - **no geocoding** — #198 moved that to MapKit, and this bypasses it.
///
/// **What each outcome means.** If this fails identically, Talaria's code is
/// exonerated: the problem lives in the app's identity, the account, or the
/// service, and no further work inside this codebase will move it. If it
/// SUCCEEDS, the fault is somewhere in our tool path and the diff between this
/// call and `WeatherTool.performLookup` is the whole search space.
///
/// **What it deliberately cannot tell us:** app-specific vs account-wide. Both
/// this probe and the tool run under the same bundle id and team, so a shared
/// failure is consistent with either. Separating those needs a SECOND App ID
/// with WeatherKit enabled — a portal action, and the next step only if this
/// probe fails.
enum WeatherKitProbe {

    /// A fixed, unambiguous coordinate — New Orleans. Deliberately not the
    /// user's location: no permission, no fix, no reverse geocode, and a place
    /// Apple Weather certainly covers, so "no data for this point" cannot be
    /// confused with an auth failure.
    static let probeLocation = CLLocation(latitude: 29.9511, longitude: -90.0715)

    struct Result: Sendable {
        let succeeded: Bool
        /// The RAW error text on failure — never sanitised. #212's lesson: the
        /// honest user-facing message erased exactly this from a run that
        /// existed to capture it, so the probe reports the underlying string
        /// and nothing else.
        let detail: String
    }

    static func run() async -> Result {
        do {
            let weather = try await WeatherService.shared.weather(for: probeLocation)
            let c = weather.currentWeather
            return Result(
                succeeded: true,
                detail: "OK — \(c.condition.description), \(c.temperature.formatted())"
            )
        } catch {
            // Both forms: `localizedDescription` is what the tool surfaced,
            // `String(describing:)` is what carried the enum case in #209's
            // taxonomy work. Recording both means the next reader does not have
            // to guess which one the SDK populated.
            return Result(
                succeeded: false,
                detail: "FAILED localizedDescription=\(error.localizedDescription) "
                    + "|| describing=\(String(describing: error))"
            )
        }
    }
}
#endif
