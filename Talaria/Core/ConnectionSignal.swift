import Foundation

/// **#264 half 2 — ONE connection signal.** The chat banner, the sidebar
/// footer, and all three settings surfaces answer "can we reach the host?"
/// from this one type. Nothing else in the app may derive that state.
///
/// **Why one signal is the whole point.** #264's live incident was a gateway
/// that came up with a healthy PID and no `:8642` listener: chat refused while
/// other surfaces still read healthy, because every surface consulted its own
/// inputs. Both facts come through the same door, so it is one banner and one
/// truth — the #180-adopted convention's literal first bullet.
///
/// **What this replaces (inventory re-derived at HEAD, 2026-08-26).** #350
/// already collapsed the four `effectiveConnectionState` BODIES into two shared
/// functions; what survived was two mappings living in two places and THREE
/// hand-assembled argument lists that disagreed about `hostConfigured`. The
/// argument lists are gone: a caller can no longer choose the predicate,
/// because it is no longer a parameter any view supplies.
/// The derivation itself is pure and un-isolated so it can be pinned without a
/// container; only ``settingsState(container:hostStore:)``, which reads live
/// stores, is `@MainActor`.
enum ConnectionSignal {

    // MARK: - The two surfaces

    /// **The mappings differ ON PURPOSE, and collapsing them would be a
    /// behaviour change.** #264's 2026-08-09 ruling warned about exactly this:
    /// the chat property "is the fourth, with a different body; collapsing the
    /// wrong one silently changes chat-banner behaviour."
    ///
    /// They are arms of one function rather than two functions in two enums, so
    /// the difference is visible at the point of decision instead of being
    /// discoverable only by reading both call sites.
    enum Surface: Equatable, Sendable {
        /// Chat and the split-view sidebar footer. Chat talks **directly** to
        /// the Sessions API on `:8642`, so relay-sourced host state must never
        /// paint it: a measured failure is `.offline` (the chat vocabulary) and
        /// there is no fallback to fall back to.
        case chat
        /// The settings surfaces (About, Channels, Uplink). A measured failure
        /// is `.unreachable` (the settings vocabulary), and with no verdict yet
        /// a configured host is `.checking` while a hostless one keeps the
        /// host-store story unchanged.
        case settings
    }

    // MARK: - The measured inputs

    /// Everything the derivation is allowed to look at, assembled once.
    ///
    /// `hostFallback` and `hostConfigured` are ignored on `.chat` by
    /// construction — the chat plane is direct-only — which is why
    /// ``chatState(direct:)`` does not ask for them.
    struct Inputs: Equatable, Sendable {
        var direct: ConnectionStatus
        var hostFallback: HermesHostConnectionState
        var hostConfigured: Bool

        init(
            direct: ConnectionStatus,
            hostFallback: HermesHostConnectionState = .notConnected,
            hostConfigured: Bool = false
        ) {
            self.direct = direct
            self.hostFallback = hostFallback
            self.hostConfigured = hostConfigured
        }
    }

    // MARK: - The derivation (the only one)

    /// #350's rule survives verbatim in both arms: a MEASURED direct verdict
    /// outranks relay-plane memory, `.connected` is the only way to green, and
    /// "not yet probed" renders as unknown rather than as confident green
    /// (#25 — the old optimistic mapping painted LINKED · ONLINE against a dead
    /// port across a cold launch).
    static func state(_ inputs: Inputs, for surface: Surface) -> HermesHostConnectionState {
        switch inputs.direct {
        case .connected:
            return .online
        case .error:
            // The one deliberate divergence. Chat says OFFLINE; settings say
            // UNREACHABLE. Same fact, two vocabularies, both already shipped.
            return surface == .chat ? .offline : .unreachable
        case .connecting, .disconnected:
            guard surface == .settings else { return .checking }
            return inputs.hostConfigured ? .checking : inputs.hostFallback
        }
    }

    /// The chat plane's signal. Direct-only by design, which is why it takes no
    /// fallback: `hostStore.connectionState` is relay-sourced and the relay is
    /// retired, so consulting it here would paint a false "Hermes host offline"
    /// banner and a stale model chip.
    static func chatState(direct: ConnectionStatus) -> HermesHostConnectionState {
        state(Inputs(direct: direct), for: .chat)
    }

    // MARK: - The one `hostConfigured` predicate

    /// **THE predicate — and it is not a parameter any view may spell.**
    ///
    /// Before this collapse, About and Channels asked
    /// `activeProfile?.hasGateway == true` while Uplink asked
    /// `!gatewayBaseURL.isEmpty`, where that screen's `gatewayBaseURL` falls
    /// back to the legacy `settingsStore.settings.hermesAPIBaseURL`. On a
    /// container with no active profile but a stale legacy URL, that made
    /// Uplink read CHECKING while About and Channels read the hostless story —
    /// three surfaces, three truths, from one signal.
    ///
    /// **The profile spelling is the correct one, because it is what the app
    /// actually dials.** Every gateway call site resolves
    /// `profilesStore.activeProfile?.gatewayBaseURL` with no legacy fallback
    /// (`AppContainer.swift`); the settings value is a migration SEED, not an
    /// endpoint. A surface that promises CHECKING against a URL chat cannot
    /// dial is asserting, not measuring.
    static func hostConfigured(activeProfile: BackendProfile?) -> Bool {
        activeProfile?.hasGateway == true
    }

    // MARK: - The settings surfaces' one call

    /// The whole settings derivation: reads the inputs, applies the predicate,
    /// returns the state. About, Channels and Uplink each call exactly this and
    /// pass nothing — which is what makes disagreement unrepresentable rather
    /// than merely discouraged.
    @MainActor
    static func settingsState(
        container: AppContainer,
        hostStore: HermesHostStore
    ) -> HermesHostConnectionState {
        state(
            Inputs(
                direct: container.chatStore.directConnectionStatus,
                hostFallback: hostStore.connectionState,
                hostConfigured: hostConfigured(activeProfile: container.profilesStore?.activeProfile)
            ),
            for: .settings
        )
    }
}
