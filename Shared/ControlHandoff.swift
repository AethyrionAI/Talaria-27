import Foundation

/// #58 — the Control Center → app launch handoff.
///
/// A control's intent cannot open the app on a `hermes://` URL. `OpenURLIntent`
/// does not support custom URL schemes (Apple DTS: universal links are the
/// supported mechanism), so AppIntents prepares `URL(nil)` and reports the
/// action successful while nothing happens — the #58 defect, diagnosed from the
/// device log on 2026-07-23. The controls therefore set `openAppWhenRun = true`
/// and let the SYSTEM launch the app, leaving the destination here;
/// `AppEntry` picks it up and feeds it to `handleDeeplink`, so controls,
/// Spotlight, Siri and Safari all keep converging on one router.
///
/// Compiled into BOTH the app and the widget extension (`Shared/` is listed in
/// both targets' sources) so the two processes cannot drift onto different app
/// groups or keys — a divergent group string is a silent failure: the write
/// succeeds into a suite nobody reads.
struct ControlHandoffStore {
    /// App Group identifier — the SAME `APP_GROUP_ID` override + fallback as
    /// `SharedWidgetDataStore` (app), `HermesTimelineProvider` (widget) and
    /// `SharedInboxStore` (share extension). Restated rather than called
    /// because the app target's store is not visible from an extension; the
    /// literal must never diverge from those three.
    static let appGroupID: String = {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String, !custom.isEmpty {
            return custom
        }
        return "group.org.aethyrion.talaria"
    }()

    static let destinationKey = "hermes.control.pendingDestination"
    static let writtenAtKey = "hermes.control.pendingDestinationWrittenAt"

    /// How long a written destination stays honourable. The write→read gap is
    /// a single app launch — seconds. Anything older was stranded (the system
    /// launched the app but the scene never activated, or the user swiped it
    /// away) and must not hijack an unrelated launch later. Cheap insurance:
    /// the consume-once clear below already handles the common case, but the
    /// launch it would wrongly route IS the next one, so expiry is what makes
    /// a stranded value self-healing instead of self-inflicting.
    static let defaultStalenessWindow: TimeInterval = 30

    let defaults: UserDefaults
    let stalenessWindow: TimeInterval

    init(defaults: UserDefaults, stalenessWindow: TimeInterval = ControlHandoffStore.defaultStalenessWindow) {
        self.defaults = defaults
        self.stalenessWindow = stalenessWindow
    }

    /// The production store in the shared app-group suite, or nil when the
    /// group is unreachable (missing entitlement — never expected in a signed
    /// build, but real in `CODE_SIGNING_ALLOWED=NO` simulator runs).
    static func appGroup() -> ControlHandoffStore? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        return ControlHandoffStore(defaults: defaults)
    }

    // MARK: - Extension side (write)

    /// Timestamp FIRST, destination second: a torn write then leaves a
    /// timestamp with no destination, which reads as "nothing pending" — the
    /// safe direction. The reverse order would leave an undateable destination.
    func writeDestination(_ destination: URL, now: Date = .now) {
        defaults.set(now.timeIntervalSince1970, forKey: Self.writtenAtKey)
        defaults.set(destination.absoluteString, forKey: Self.destinationKey)
    }

    // MARK: - App side (consume)

    /// Reads the pending destination and CLEARS it in the same pass, whatever
    /// the verdict. Two properties this must keep:
    ///
    /// - **Consume once.** A destination left behind re-routes the NEXT launch:
    ///   tap the Talk control, quit, reopen from the home screen, and the app
    ///   yanks you into voice for no reason.
    /// - **Absence is a no-op, never a default route.** With
    ///   `openAppWhenRun = true` the system launches the app even when
    ///   `perform()` never ran (#179's cold first-tap swallow), and every
    ///   ordinary launch reads this store too — so "nothing pending" is the
    ///   common case, not an error.
    func consumeDestination(now: Date = .now) -> URL? {
        // No destination: return WITHOUT clearing. This is the every-launch
        // path, and clearing here would mean a write into the shared suite on
        // every single foreground to remove nothing. A torn write can leave a
        // lone timestamp behind — deliberate litter, inert by construction: a
        // timestamp alone is never routable, and the next real write
        // overwrites it.
        guard let raw = defaults.string(forKey: Self.destinationKey) else { return nil }
        let writtenAt = defaults.object(forKey: Self.writtenAtKey) as? Double
        clear()
        // No timestamp means a torn or foreign write — refuse it rather than
        // route on a value we can't date.
        guard let writtenAt else { return nil }
        guard now.timeIntervalSince1970 - writtenAt <= stalenessWindow else { return nil }
        return URL(string: raw)
    }

    func clear() {
        defaults.removeObject(forKey: Self.destinationKey)
        defaults.removeObject(forKey: Self.writtenAtKey)
    }
}
