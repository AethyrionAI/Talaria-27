import Foundation

// MARK: - App lock core (#124)
//
// Pure lock-state decision logic — no clocks, no LAContext, no SwiftUI.
// The controller (AppLockController) feeds it scene-phase transitions with
// explicit timestamps; tests drive the full matrix without any system
// dependency.

/// How long the app may sit in the background before returning requires auth.
enum AppLockGracePeriod: String, Codable, CaseIterable, Sendable {
    case immediate
    case oneMinute
    case fiveMinutes

    var seconds: TimeInterval {
        switch self {
        case .immediate: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }

    var displayLabel: String {
        switch self {
        case .immediate: "Immediately"
        case .oneMinute: "After 1 min"
        case .fiveMinutes: "After 5 min"
        }
    }
}

struct AppLockConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var gracePeriod: AppLockGracePeriod

    static let disabled = AppLockConfiguration(isEnabled: false, gracePeriod: .immediate)
}

/// SwiftUI-free mirror of ScenePhase so the core stays UI-framework-pure.
enum AppLockScenePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

/// What the cover window should show.
enum AppLockCover: Equatable, Sendable {
    /// No cover — normal app.
    case none
    /// Opaque privacy cover (app not active but not lock-required): this is
    /// what the app-switcher snapshot captures.
    case obscured
    /// Full lock UI — auth required to proceed.
    case locked
}

struct AppLockStateMachine: Equatable, Sendable {
    private(set) var isLocked: Bool
    private(set) var phase: AppLockScenePhase = .background
    /// When the app last entered `.background`. The grace clock keys on
    /// `.background`, NOT `.inactive` — transient inactivity (the Face ID
    /// sheet itself, notification-shade pulls, incoming calls) must obscure
    /// but never lock, or authentication would re-trigger its own lock.
    private(set) var enteredBackgroundAt: Date?

    /// Cold launch: lock immediately when the feature is on.
    init(configuration: AppLockConfiguration) {
        isLocked = configuration.isEnabled
    }

    mutating func scenePhaseChanged(to newPhase: AppLockScenePhase, configuration: AppLockConfiguration, now: Date) {
        switch newPhase {
        case .background:
            if enteredBackgroundAt == nil {
                enteredBackgroundAt = now
            }
        case .active:
            if configuration.isEnabled, !isLocked,
               let leftAt = enteredBackgroundAt,
               now.timeIntervalSince(leftAt) >= configuration.gracePeriod.seconds {
                isLocked = true
            }
            enteredBackgroundAt = nil
        case .inactive:
            break
        }
        phase = newPhase
        if !configuration.isEnabled {
            isLocked = false
        }
    }

    mutating func authenticationSucceeded() {
        isLocked = false
        enteredBackgroundAt = nil
    }

    /// Toggling the feature off releases any lock; toggling it on never locks
    /// mid-session (the user is demonstrably present).
    mutating func configurationChanged(_ configuration: AppLockConfiguration) {
        if !configuration.isEnabled {
            isLocked = false
            enteredBackgroundAt = nil
        }
    }

    func cover(configuration: AppLockConfiguration) -> AppLockCover {
        guard configuration.isEnabled else { return .none }
        if isLocked { return .locked }
        if phase != .active { return .obscured }
        return .none
    }
}

// MARK: - Auth capability + evaluator seam

/// What the device can actually enforce, resolved from a fresh LAContext.
enum AppLockCapability: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// Biometry unavailable or not enrolled, but a device passcode is set —
    /// `.deviceOwnerAuthentication` still works, so offer a passcode lock
    /// with the biometry language dropped.
    case passcodeOnly
    /// No device passcode: the policy cannot evaluate at all. The toggle is
    /// disabled AND the controller neutralizes a stale enabled flag so the
    /// app can never lock itself with no way back in.
    case unavailable

    var toggleLabel: String {
        switch self {
        case .faceID: "Require Face ID"
        case .touchID: "Require Touch ID"
        case .opticID: "Require Optic ID"
        case .passcodeOnly: "Require Passcode"
        case .unavailable: "App Lock"
        }
    }

    var lockPolicyAvailable: Bool { self != .unavailable }
}

/// LAContext seam — the live implementation builds a FRESH context per call
/// (contexts are single-use after evaluation); tests mock this protocol.
@MainActor
protocol AppLockAuthenticating {
    func capability() -> AppLockCapability
    func authenticate(reason: String) async -> Bool
}
