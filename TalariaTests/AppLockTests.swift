import Foundation
import Testing
@testable import Talaria

// MARK: - #124 App lock — pure decision-matrix tests
//
// The full scenePhase × grace × toggle × auth matrix runs against the pure
// AppLockStateMachine — no LAContext anywhere (the evaluator is a protocol,
// mocked in the controller tests appended by later tasks).

struct AppLockStateMachineTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func config(_ enabled: Bool, _ grace: AppLockGracePeriod = .immediate) -> AppLockConfiguration {
        AppLockConfiguration(isEnabled: enabled, gracePeriod: grace)
    }

    // MARK: Cold launch

    @Test func coldLaunchLocksWhenEnabled() {
        let machine = AppLockStateMachine(configuration: config(true))
        #expect(machine.isLocked)
        #expect(machine.cover(configuration: config(true)) == .locked)
    }

    @Test func coldLaunchStaysUnlockedWhenDisabled() {
        let machine = AppLockStateMachine(configuration: config(false))
        #expect(!machine.isLocked)
        #expect(machine.cover(configuration: config(false)) == .none)
    }

    // MARK: Grace period matrix

    @Test func immediateGraceLocksOnAnyBackgroundRoundTrip() {
        let c = config(true)
        var machine = unlockedForeground(c)
        machine.scenePhaseChanged(to: .inactive, configuration: c, now: t0)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0.addingTimeInterval(1))
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(2))
        #expect(machine.isLocked)
    }

    @Test func oneMinuteGraceHonoredWithinWindow() {
        let c = config(true, .oneMinute)
        var machine = unlockedForeground(c)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0)
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(30))
        #expect(!machine.isLocked)
    }

    @Test func oneMinuteGraceLocksAtBoundary() {
        let c = config(true, .oneMinute)
        var machine = unlockedForeground(c)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0)
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(60))
        #expect(machine.isLocked)
    }

    @Test func fiveMinuteGraceHonoredWithinWindow() {
        let c = config(true, .fiveMinutes)
        var machine = unlockedForeground(c)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0)
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(299))
        #expect(!machine.isLocked)
    }

    // The grace clock keys on .background, not .inactive: the Face ID sheet
    // itself and notification-shade pulls are .inactive, and locking on them
    // would make authentication re-trigger its own lock.
    @Test func transientInactiveDoesNotLock() {
        let c = config(true)
        var machine = unlockedForeground(c)
        machine.scenePhaseChanged(to: .inactive, configuration: c, now: t0)
        #expect(machine.cover(configuration: c) == .obscured)
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(5))
        #expect(!machine.isLocked)
        #expect(machine.cover(configuration: c) == .none)
    }

    @Test func graceMeasuredFromBackgroundEntryNotInactive() {
        let c = config(true, .oneMinute)
        var machine = unlockedForeground(c)
        machine.scenePhaseChanged(to: .inactive, configuration: c, now: t0)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0.addingTimeInterval(55))
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(70))
        // 70s since inactive but only 15s since background — within grace.
        #expect(!machine.isLocked)
    }

    // MARK: Auth results

    @Test func authSuccessUnlocks() {
        let c = config(true)
        var machine = AppLockStateMachine(configuration: c)
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0)
        machine.authenticationSucceeded()
        #expect(!machine.isLocked)
        #expect(machine.cover(configuration: c) == .none)
    }

    @Test func lockSurvivesRepeatedForegrounding() {
        let c = config(true)
        var machine = AppLockStateMachine(configuration: c)
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0.addingTimeInterval(1))
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(2))
        #expect(machine.isLocked)
    }

    // MARK: Toggle

    @Test func disablingUnlocksAndClearsCover() {
        var machine = AppLockStateMachine(configuration: config(true))
        machine.configurationChanged(config(false))
        #expect(!machine.isLocked)
        #expect(machine.cover(configuration: config(false)) == .none)
    }

    @Test func enablingMidSessionDoesNotLockImmediately() {
        let off = config(false)
        var machine = AppLockStateMachine(configuration: off)
        machine.scenePhaseChanged(to: .active, configuration: off, now: t0)
        machine.configurationChanged(config(true))
        #expect(!machine.isLocked)
        #expect(machine.cover(configuration: config(true)) == .none)
    }

    // MARK: Cover matrix

    @Test func obscuredWhileBackgroundedUnlocked() {
        let c = config(true, .fiveMinutes)
        var machine = unlockedForeground(c)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0)
        #expect(machine.cover(configuration: c) == .obscured)
    }

    @Test func disabledNeverCovers() {
        let c = config(false)
        var machine = AppLockStateMachine(configuration: c)
        machine.scenePhaseChanged(to: .inactive, configuration: c, now: t0)
        #expect(machine.cover(configuration: c) == .none)
        machine.scenePhaseChanged(to: .background, configuration: c, now: t0)
        #expect(machine.cover(configuration: c) == .none)
    }

    @Test func lockedCoverWinsOverObscured() {
        let c = config(true)
        var machine = AppLockStateMachine(configuration: c)
        machine.scenePhaseChanged(to: .inactive, configuration: c, now: t0)
        #expect(machine.cover(configuration: c) == .locked)
    }

    /// Machine that has completed a cold-launch unlock and sits foregrounded.
    private func unlockedForeground(_ c: AppLockConfiguration) -> AppLockStateMachine {
        var machine = AppLockStateMachine(configuration: c)
        machine.scenePhaseChanged(to: .active, configuration: c, now: t0.addingTimeInterval(-100))
        machine.authenticationSucceeded()
        return machine
    }
}

struct AppLockGracePeriodTests {
    @Test func secondsMapping() {
        #expect(AppLockGracePeriod.immediate.seconds == 0)
        #expect(AppLockGracePeriod.oneMinute.seconds == 60)
        #expect(AppLockGracePeriod.fiveMinutes.seconds == 300)
    }
}

// MARK: - Controller tests (mocked evaluator — no LAContext anywhere)

@MainActor
private final class MockAppLockAuthenticator: AppLockAuthenticating {
    var stubbedCapability: AppLockCapability = .faceID
    var nextResult = false
    private(set) var authenticateCallCount = 0
    func capability() -> AppLockCapability { stubbedCapability }
    func authenticate(reason: String) async -> Bool {
        authenticateCallCount += 1
        return nextResult
    }
}

@MainActor
struct AppLockControllerTests {
    private func makeController(
        enabled: Bool = true,
        grace: AppLockGracePeriod = .immediate,
        authenticator: MockAppLockAuthenticator = MockAppLockAuthenticator()
    ) -> (AppLockController, MockAppLockAuthenticator) {
        let controller = AppLockController(
            configuration: { AppLockConfiguration(isEnabled: enabled, gracePeriod: grace) },
            authenticator: authenticator,
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
        return (controller, authenticator)
    }

    @Test func coldLaunchExposesLockedCover() {
        let (controller, _) = makeController()
        #expect(controller.cover == .locked)
    }

    @Test func successfulUnlockClearsCover() async {
        let (controller, auth) = makeController()
        auth.nextResult = true
        controller.scenePhaseChanged(to: .active)
        await controller.requestUnlock()
        #expect(controller.cover == .none)
        #expect(!controller.didFailAuthentication)
    }

    @Test func failedUnlockKeepsLockAndFlagsRetry() async {
        let (controller, auth) = makeController()
        auth.nextResult = false
        controller.scenePhaseChanged(to: .active)
        await controller.requestUnlock()
        #expect(controller.cover == .locked)
        #expect(controller.didFailAuthentication)
    }

    @Test func retryAfterFailureUsesNewEvaluation() async {
        let (controller, auth) = makeController()
        controller.scenePhaseChanged(to: .active)
        auth.nextResult = false
        await controller.requestUnlock()
        auth.nextResult = true
        await controller.requestUnlock()
        #expect(auth.authenticateCallCount >= 2)
        #expect(controller.cover == .none)
    }

    // No passcode set → the feature is neutralized even with a stale enabled
    // flag (an un-evaluable policy would otherwise brick the app).
    @Test func unavailableCapabilityNeutralizesLock() {
        let auth = MockAppLockAuthenticator()
        auth.stubbedCapability = .unavailable
        let (controller, _) = makeController(authenticator: auth)
        #expect(controller.cover == .none)
    }

    @Test func disabledConfigurationNeverAuthenticates() async {
        let (controller, auth) = makeController(enabled: false)
        controller.scenePhaseChanged(to: .active)
        await controller.requestUnlock()
        #expect(auth.authenticateCallCount == 0)
        #expect(controller.cover == .none)
    }

    @Test func coverChangeNotifiesPresenterHook() async {
        let (controller, auth) = makeController()
        var observed: [AppLockCover] = []
        controller.onCoverChanged = { observed.append($0) }
        auth.nextResult = true
        controller.scenePhaseChanged(to: .active)
        await controller.requestUnlock()
        #expect(observed.last == AppLockCover.none)
    }
}

struct AppLockSettingsCodingTests {
    @Test func legacyPayloadDecodesWithLockDefaults() throws {
        // A pre-#124 payload has no appLock keys — decode must default off/immediate.
        let legacy = try JSONEncoder().encode(UserSettings())
        var object = try JSONSerialization.jsonObject(with: legacy) as? [String: Any] ?? [:]
        object.removeValue(forKey: "appLockEnabled")
        object.removeValue(forKey: "appLockGracePeriod")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        #expect(decoded.appLockEnabled == false)
        #expect(decoded.appLockGracePeriod == .immediate)
    }

    @Test func roundTripPreservesLockSettings() throws {
        var settings = UserSettings()
        settings.appLockEnabled = true
        settings.appLockGracePeriod = .fiveMinutes
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.appLockEnabled)
        #expect(decoded.appLockGracePeriod == .fiveMinutes)
        #expect(decoded.appLockConfiguration == AppLockConfiguration(isEnabled: true, gracePeriod: .fiveMinutes))
    }
}
