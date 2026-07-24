import Foundation

/// #175: how often the chat screen re-probes host + Sessions API health.
///
/// A wire capture on 2026-07-23 logged six `GET /v1/models` inside a minute of
/// an idle app. That was not an accident of view lifecycle — it was exactly
/// this loop: `ChatScreen.monitorConnectionStatus()` slept a flat ten seconds
/// and probed, forever, whether or not anything was moving. Six ticks, six
/// requests, arithmetic confirmed.
///
/// Ten seconds is right when the connection is actually changing — it drives
/// the header pip and triggers the offline compose outbox's drain. It is
/// wasteful when the answer has been the same for half a minute. So the
/// cadence relaxes while the status holds and snaps back the moment it moves.
///
/// Pure so the cadence is assertable without a running screen.
enum ChatHealthPollPolicy {
    /// Cadence while the connection status is still moving.
    static let responsiveInterval: TimeInterval = 10

    /// Cadence once it has settled — 2 probes/minute instead of 6.
    static let steadyInterval: TimeInterval = 30

    /// Consecutive identical probes before relaxing. Three keeps a flapping
    /// link on the fast cadence.
    static let steadyAfterUnchangedProbes = 3

    static func interval(consecutiveUnchangedProbes: Int) -> TimeInterval {
        consecutiveUnchangedProbes >= steadyAfterUnchangedProbes ? steadyInterval : responsiveInterval
    }

    /// The probe only means something while the user can see its result, and
    /// a `.task` is NOT cancelled by backgrounding — the view never
    /// disappears — so the loop would otherwise keep firing until iOS
    /// suspends the process.
    static func shouldProbe(scenePhase: ScenePhaseSnapshot) -> Bool {
        scenePhase == .active
    }

    /// Mirror of SwiftUI's `ScenePhase` so this file stays UI-framework-free
    /// and testable.
    enum ScenePhaseSnapshot: Equatable, Sendable {
        case active
        case inactive
        case background
    }
}
