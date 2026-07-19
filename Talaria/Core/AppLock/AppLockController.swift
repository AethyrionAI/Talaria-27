import Foundation
import LocalAuthentication

// MARK: - App lock controller (#124)
//
// Decision pinned per the dispatch: App Intents (Ask Hermes from
// Siri/Shortcuts) BYPASS this lock — the intent path has no UI, so a locked
// phone can still ask Hermes headlessly, exactly like a lock-screen Siri
// query. Anything that lands INTO the app UI (OpenURLIntent, hermes:// deep
// links, notification taps) hits the lock first, because the cover window
// sits above everything the scene presents. Live Activities and widgets are
// likewise unaffected — they render outside the app process entirely.

@MainActor
@Observable
final class AppLockController {
    private(set) var cover: AppLockCover = .none
    private(set) var capability: AppLockCapability
    private(set) var isAuthenticating = false
    private(set) var didFailAuthentication = false

    /// The window presenter subscribes here (set once at wiring).
    @ObservationIgnored var onCoverChanged: ((AppLockCover) -> Void)?

    private var machine: AppLockStateMachine
    private let configuration: () -> AppLockConfiguration
    private let authenticator: any AppLockAuthenticating
    private let now: () -> Date

    init(
        configuration: @escaping () -> AppLockConfiguration,
        authenticator: any AppLockAuthenticating = BiometricAppLockAuthenticator(),
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.authenticator = authenticator
        self.now = now
        let resolvedCapability = authenticator.capability()
        capability = resolvedCapability
        machine = AppLockStateMachine(
            configuration: Self.effectiveConfiguration(configuration(), capability: resolvedCapability)
        )
        refreshCover()
    }

    func scenePhaseChanged(to phase: AppLockScenePhase) {
        if phase == .active {
            // Biometry enrollment can change while backgrounded.
            refreshCapability()
            didFailAuthentication = false
        }
        machine.scenePhaseChanged(to: phase, configuration: effectiveConfiguration(), now: now())
        refreshCover()
        autoAuthenticateIfNeeded()
    }

    func configurationChanged() {
        machine.configurationChanged(effectiveConfiguration())
        refreshCover()
    }

    func refreshCapability() {
        capability = authenticator.capability()
    }

    func requestUnlock() async {
        guard machine.isLocked, effectiveConfiguration().isEnabled, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        // Fresh LAContext per attempt inside the authenticator (single-use contexts).
        let unlocked = await authenticator.authenticate(reason: "Unlock Talaria")
        if unlocked {
            machine.authenticationSucceeded()
            didFailAuthentication = false
        } else {
            didFailAuthentication = true
        }
        refreshCover()
    }

    // No device passcode → `.deviceOwnerAuthentication` cannot evaluate;
    // honoring a stale enabled flag would brick the app. Treat as disabled.
    private func effectiveConfiguration() -> AppLockConfiguration {
        Self.effectiveConfiguration(configuration(), capability: capability)
    }

    private static func effectiveConfiguration(
        _ configuration: AppLockConfiguration, capability: AppLockCapability
    ) -> AppLockConfiguration {
        capability.lockPolicyAvailable ? configuration : .disabled
    }

    private func refreshCover() {
        let newCover = machine.cover(configuration: effectiveConfiguration())
        guard newCover != cover else { return }
        cover = newCover
        onCoverChanged?(newCover)
    }

    /// First foregrounding of a lock episode prompts without a tap; a failed
    /// or cancelled attempt drops to the retry button (no prompt loop).
    private func autoAuthenticateIfNeeded() {
        guard cover == .locked, machine.phase == .active,
              !isAuthenticating, !didFailAuthentication else { return }
        Task { await requestUnlock() }
    }
}

/// Live evaluator: a FRESH `LAContext` per call — contexts are single-use
/// after `evaluatePolicy`, and a reused one returns stale results.
@MainActor
struct BiometricAppLockAuthenticator: AppLockAuthenticating {
    func capability() -> AppLockCapability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // `.deviceOwnerAuthentication` includes the passcode, so failure
            // here means no passcode is set (or a managed restriction) —
            // there is nothing the lock could fall back to.
            return .unavailable
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default:
            // Biometry not available/enrolled but the passcode policy holds:
            // offer the lock with the biometry language dropped.
            return .passcodeOnly
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            // Never biometry-only: passcode fallback is the way back in
            // after a biometry lockout.
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
