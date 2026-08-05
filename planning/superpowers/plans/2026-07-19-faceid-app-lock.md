# Face ID App Lock (#124) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Biometric app lock (`.deviceOwnerAuthentication`, passcode fallback) — Settings toggle, scene-level lock overlay on cold launch / return-to-foreground with a grace period, obscured app-switcher snapshot. Off by default, free tier.

**Architecture:** A pure `AppLockStateMachine` (no clocks, no LAContext, no SwiftUI) decides lock state from scenePhase transitions × grace period × toggle × auth results; an `@Observable AppLockController` wraps it with a `Date` closure and a protocol-mocked authenticator (fresh `LAContext` per attempt in the live impl). The cover renders in a **dedicated topmost `UIWindow`** (level `.alert + 1`) so it sits above sheets/alerts/full-screen covers that a root-ZStack overlay cannot cover — this one mechanism serves both the lock UI and the app-switcher snapshot obscuring (scenePhase-driven opaque overlay, the dispatch's sanctioned simpler approach, hardened for presentation layers).

**Tech Stack:** SwiftUI (app lifecycle), LocalAuthentication, UIKit (overlay window), Swift Testing.

## Global Constraints

- Branch: `claude/t27-124-faceid-lock` off `main`. One PR.
- `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every shell.
- `xcodegen generate` after any file add/remove, in the same commit as the add.
- File-scoped commits; suite green ≥ 755/62 at the end (current baseline 845/72).
- Four-space indent, `@Observable`, no force-unwraps in logic code; real data only.
- `NSFaceIDUsageDescription` goes in `project.yml` `info.properties` — NEVER as an `INFOPLIST_KEY_*` build setting (the #58 lesson: silently ignored with a generated plist).
- No new entitlements.
- Lane V (#118, voice ends on background) is already in main (`AppEntry.swift` scenePhase comment) — no ordering note needed; say so in the PR body.

## Embedded decisions (from dispatch, pin in code comments)

1. **Intent path bypasses the lock** — App Intents (Ask Hermes) have no UI, so they run while locked; any `OpenURLIntent`/deep-link landing INTO the app hits the lock because the cover window sits above everything the scene shows. Pin with a comment on `AppLockController`.
2. **Snapshot obscuring approach** — scenePhase-driven opaque overlay, hosted in a dedicated topmost `UIWindow` rather than the root view hierarchy. Why: SwiftUI-lifecycle friendly (no `UIApplication` snapshot API), and sheets/alerts/fullScreenCovers present in layers ABOVE the window's root view — a root ZStack overlay would leave an open sheet visible above the "lock". Pin with a comment on `AppLockWindowPresenter`.
3. **Never biometry-only** — `.deviceOwnerAuthentication` (passcode fallback); biometry lockout would otherwise brick the app.
4. **Capability degradation** — `biometryNotAvailable`/`notEnrolled` with a passcode set → passcode-policy lock, toggle drops the Face ID language. No passcode at all → App Lock unavailable (honest disabled row) AND the controller treats the feature as off even if the flag is somehow set (no bricking).

---

### Task 1: Pure lock core — `AppLockCore.swift` + matrix tests

**Files:**
- Create: `Talaria/Services/Support/AppLockCore.swift`
- Test: `TalariaTests/AppLockTests.swift`
- Modify: (regen) `Talaria.xcodeproj` via `xcodegen generate`

**Interfaces:**
- Produces: `AppLockGracePeriod` (enum `immediate|oneMinute|fiveMinutes`, `String` raw, `Codable`, `seconds: TimeInterval`, `displayLabel: String`), `AppLockConfiguration { isEnabled: Bool, gracePeriod: AppLockGracePeriod }`, `AppLockScenePhase` (enum `active|inactive|background`), `AppLockCover` (enum `none|obscured|locked`), `AppLockStateMachine` (see code), `AppLockCapability` (enum `faceID|touchID|opticID|passcodeOnly|unavailable` + `toggleLabel`/`lockPolicyAvailable`), `protocol AppLockAuthenticating`.

- [ ] **Step 1: Write the failing tests** (`TalariaTests/AppLockTests.swift`)

```swift
import Foundation
import Testing
@testable import Talaria

struct AppLockStateMachineTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func config(_ enabled: Bool, _ grace: AppLockGracePeriod = .immediate) -> AppLockConfiguration {
        AppLockConfiguration(isEnabled: enabled, gracePeriod: grace)
    }

    // Cold launch
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

    // Grace period matrix
    @Test func immediateGraceLocksOnAnyBackgroundRoundTrip() {
        var machine = unlockedForeground(config(true))
        machine.scenePhaseChanged(to: .inactive, configuration: config(true), now: t0)
        machine.scenePhaseChanged(to: .background, configuration: config(true), now: t0.addingTimeInterval(1))
        machine.scenePhaseChanged(to: .active, configuration: config(true), now: t0.addingTimeInterval(2))
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

    // Grace clock keys on .background, not .inactive (Face ID sheet /
    // notification-shade pulls are .inactive and must never trigger a lock).
    @Test func transientInactiveDoesNotLock() {
        let c = config(true, .immediate)
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

    // Auth results
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

    // Toggle
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

    // Cover matrix
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
```

- [ ] **Step 2: Run to verify failure** (does not compile — types missing). Run via:
```bash
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination '<sim from simctl list>' -only-testing:TalariaTests/AppLockStateMachineTests 2>&1 | tail -20
```
Expected: build FAILURE, "cannot find 'AppLockStateMachine' in scope".

- [ ] **Step 3: Implement** `Talaria/Services/Support/AppLockCore.swift`

```swift
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
    /// but never lock, or auth would re-trigger its own lock.
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
```

- [ ] **Step 4: Regen + run tests**
```bash
xcodegen generate
# then the Step 2 command
```
Expected: all AppLock tests PASS.

- [ ] **Step 5: Commit**
```bash
git add Talaria/Services/Support/AppLockCore.swift TalariaTests/AppLockTests.swift Talaria.xcodeproj
git commit -m "feat(#124): AppLockCore — pure lock-state machine + grace/cover matrix tests"
```

---

### Task 2: `UserSettings` fields

**Files:**
- Modify: `Talaria/Models/UserSettings.swift` (property block ~line 336, init, CodingKeys, decode, encode)
- Test: `TalariaTests/AppLockTests.swift` (append)

**Interfaces:**
- Produces: `UserSettings.appLockEnabled: Bool` (default `false`), `UserSettings.appLockGracePeriod: AppLockGracePeriod` (default `.immediate`), computed `UserSettings.appLockConfiguration: AppLockConfiguration`.

- [ ] **Step 1: Append failing test**

```swift
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
```

- [ ] **Step 2: Run → FAIL** (no such properties).
- [ ] **Step 3: Implement** — mirror the `spotlightIndexingEnabled` pattern exactly: stored props with doc comment (`/// #124: biometric app lock…`), init params `appLockEnabled: Bool = false, appLockGracePeriod: AppLockGracePeriod = .immediate`, CodingKeys cases, `decodeIfPresent … ?? false` / `?? .immediate`, `encode` lines, plus:

```swift
    var appLockConfiguration: AppLockConfiguration {
        AppLockConfiguration(isEnabled: appLockEnabled, gracePeriod: appLockGracePeriod)
    }
```

- [ ] **Step 4: Run → PASS** (`-only-testing:TalariaTests/AppLockSettingsCodingTests`).
- [ ] **Step 5: Commit** `feat(#124): UserSettings appLockEnabled + appLockGracePeriod (default off/immediate)`

---

### Task 3: `AppLockController` + live authenticator

**Files:**
- Create: `Talaria/Core/AppLock/AppLockController.swift`
- Test: `TalariaTests/AppLockTests.swift` (append)
- Modify: (regen)

**Interfaces:**
- Consumes: everything from Task 1, `UserSettings.appLockConfiguration` from Task 2.
- Produces: `@MainActor @Observable final class AppLockController` with `init(configuration: @escaping () -> AppLockConfiguration, authenticator: any AppLockAuthenticating = BiometricAppLockAuthenticator(), now: @escaping () -> Date = Date.init)`, `private(set) var cover: AppLockCover`, `private(set) var capability: AppLockCapability`, `private(set) var isAuthenticating: Bool`, `private(set) var didFailAuthentication: Bool`, `var onCoverChanged: ((AppLockCover) -> Void)?`, `func scenePhaseChanged(to: AppLockScenePhase)`, `func configurationChanged()`, `func requestUnlock() async`, `func refreshCapability()`.

- [ ] **Step 1: Append failing controller tests** (mock authenticator; async auth results)

```swift
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
        #expect(auth.authenticateCallCount == 2)
        #expect(controller.cover == .none)
    }

    // No passcode set → feature is neutralized even with a stale enabled flag.
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
}
```

- [ ] **Step 2: Run → FAIL** (no `AppLockController`).
- [ ] **Step 3: Implement** `Talaria/Core/AppLock/AppLockController.swift`

```swift
import Foundation
import LocalAuthentication

// MARK: - App lock controller (#124)
//
// Decision pinned per the dispatch: App Intents (Ask Hermes from
// Siri/Shortcuts) BYPASS this lock — the intent path has no UI, so a locked
// phone can still ask Hermes headlessly, exactly like a lock-screen Siri
// query. Anything that lands INTO the app UI (OpenURLIntent, hermes:// deep
// links, notification taps) hits the lock first, because the cover window
// sits above everything the scene presents.

@MainActor
@Observable
final class AppLockController {
    private(set) var cover: AppLockCover = .none
    private(set) var capability: AppLockCapability
    private(set) var isAuthenticating = false
    private(set) var didFailAuthentication = false

    /// The window presenter subscribes here (set once at wiring).
    var onCoverChanged: ((AppLockCover) -> Void)?

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
        capability = authenticator.capability()
        let effective = Self.effectiveConfiguration(configuration(), capability: capability)
        machine = AppLockStateMachine(configuration: effective)
        refreshCover()
    }

    func scenePhaseChanged(to phase: AppLockScenePhase) {
        if phase == .active {
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

    /// Biometry enrollment can change while backgrounded — re-resolve on foreground.
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
            // .deviceOwnerAuthentication includes the passcode, so failure
            // here means no passcode is set (or a managed restriction).
            return .unavailable
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcodeOnly
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
```

- [ ] **Step 4: Regen + run → PASS** (`-only-testing:TalariaTests/AppLockControllerTests`).
- [ ] **Step 5: Commit** `feat(#124): AppLockController + fresh-LAContext authenticator, capability degradation`

---

### Task 4: Cover window + overlay view + app wiring

**Files:**
- Create: `Talaria/Core/AppLock/AppLockOverlayView.swift` (view + `AppLockWindowPresenter`)
- Modify: `Talaria/AppEntry.swift` (instantiate, wire scenePhase + settings changes, environment)
- Modify: (regen)

**Interfaces:**
- Consumes: `AppLockController` (Task 3).
- Produces: `AppLockWindowPresenter.attach(controller:)`, overlay UI. `AppLockController` goes into the SwiftUI environment for Task 5.

No pure logic here — UI + lifecycle glue; the state behind it is already tested. Verify by building.

- [ ] **Step 1: Implement** `Talaria/Core/AppLock/AppLockOverlayView.swift`

```swift
import SwiftUI
import UIKit

// MARK: - App lock cover window (#124)
//
// Snapshot-obscuring approach, stated per the dispatch: a scenePhase-driven
// opaque overlay (the sanctioned simpler option) — but hosted in a DEDICATED
// UIWindow at level .alert + 1 rather than the root view hierarchy. Why:
// sheets, alerts, and fullScreenCovers present in UIKit layers ABOVE the
// window's root SwiftUI view, so a root-ZStack overlay would leave an open
// sheet readable on top of the "lock" — and the app-switcher snapshot has
// the same hole. One topmost window covers every presentation layer, serves
// as both the lock UI and the snapshot obscurer, and needs no legacy
// UIApplication snapshot API (SwiftUI lifecycle friendly).

@MainActor
final class AppLockWindowPresenter {
    private var window: UIWindow?
    private weak var controller: AppLockController?

    func attach(controller: AppLockController) {
        self.controller = controller
        controller.onCoverChanged = { [weak self] cover in
            self?.update(cover: cover)
        }
        update(cover: controller.cover)
    }

    private func update(cover: AppLockCover) {
        cover == .none ? hide() : show()
    }

    private func show() {
        guard let controller else { return }
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.role == .windowApplication }) else { return }
            let host = UIHostingController(
                rootView: AppLockOverlayView(controller: controller)
                    .environment(ThemeRuntime.shared)
            )
            host.view.backgroundColor = .clear
            let overlay = UIWindow(windowScene: scene)
            overlay.rootViewController = host
            overlay.windowLevel = .alert + 1
            window = overlay
        }
        // Kill any active keyboard: its window floats above even .alert level.
        window?.windowScene?.keyWindow?.endEditing(true)
        window?.isHidden = false
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}

struct AppLockOverlayView: View {
    @Bindable var controller: AppLockController

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: Design.Spacing.md) {
                ReactorOrb(size: Design.Size.orbOnboarding, style: .onboarding)

                Text("TALARIA")
                    .font(Design.Typography.display(25, weight: .bold, relativeTo: .title))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .padding(.top, Design.Spacing.xs)

                if controller.cover == .locked {
                    MonoLabel("LOCKED", tracking: Design.Tracking.monoWide)

                    if controller.didFailAuthentication {
                        GlowButton("UNLOCK") {
                            Task { await controller.requestUnlock() }
                        }
                        .padding(.top, Design.Spacing.md)
                    }
                }
            }
            .padding(Design.Spacing.xl)
        }
    }
}
```

(Adjust `GlowButton` call to its real initializer during implementation — check `Talaria/Core/HUD/GlowButton.swift`. Same for `ReactorOrb`/`Design.Size` names, mirroring `LaunchSplashView`.)

- [ ] **Step 2: Wire in `Talaria/AppEntry.swift`** (`TalariaApp`):
  - Add state + presenter:
    ```swift
    @State private var appLock = AppLockController(
        configuration: { AppContainer.sharedDefault().settingsStore.settings.appLockConfiguration }
    )
    @State private var appLockPresenter = AppLockWindowPresenter()
    ```
  - In the existing `.onChange(of: scenePhase)` add, before the current branches:
    ```swift
    appLock.scenePhaseChanged(to: AppLockScenePhase(newPhase))
    ```
    with a small `AppLockScenePhase.init(_ phase: ScenePhase)` mapping extension in `AppLockOverlayView.swift` (keeps the core SwiftUI-free), `@unknown default` → `.inactive`.
  - In the existing `.onChange(of: container.settingsStore.settings)` add:
    ```swift
    if oldSettings.appLockConfiguration != newSettings.appLockConfiguration {
        appLock.configurationChanged()
    }
    ```
  - In the existing root `.task` (or a new one) attach the presenter once:
    ```swift
    .task { appLockPresenter.attach(controller: appLock) }
    ```
  - Add `.environment(appLock)` alongside the other environments (Task 5 reads it).

- [ ] **Step 3: Regen, CLI build**
```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit** `feat(#124): scene-level lock cover window + AppEntry wiring`

---

### Task 5: Privacy settings UI + Info.plist key

**Files:**
- Modify: `Talaria/Features/Settings/PrivacySettingsScreen.swift` (new App Lock section after `spotlightSection`)
- Modify: `project.yml` (`NSFaceIDUsageDescription` in the app target's `info.properties`, next to the other `NS*UsageDescription` strings)
- Modify: (regen — project.yml changed)

**Interfaces:**
- Consumes: `AppLockController` from environment (`capability`, `refreshCapability()`), `settingsStore.settings.appLockEnabled` / `.appLockGracePeriod`.

- [ ] **Step 1: Implement the section** — add `@Environment(AppLockController.self) private var appLock`, insert `appLockSection` between `spotlightSection` and `revokeSection` in `body`, following the screen's existing section pattern:

```swift
    // MARK: App Lock (#124)

    private var appLockSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// App Lock", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    HStack(spacing: Design.Spacing.sm) {
                        Text(appLock.capability.toggleLabel)
                            .font(Design.Typography.callout)
                            .foregroundStyle(appLock.capability.lockPolicyAvailable
                                             ? Design.Colors.foreground
                                             : Design.Colors.mutedForeground)
                        Spacer()
                        Toggle("", isOn: appLockEnabledBinding)
                            .labelsHidden()
                            .tint(Design.Brand.accent)
                            .disabled(!appLock.capability.lockPolicyAvailable)
                    }
                    Text(appLockCaption)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }

                if settingsStore.settings.appLockEnabled, appLock.capability.lockPolicyAvailable {
                    HStack(spacing: Design.Spacing.xxs) {
                        ForEach(AppLockGracePeriod.allCases, id: \.self) { period in
                            graceSegment(period)
                        }
                    }
                    .padding(Design.Spacing.xxs)
                    .background(Design.Colors.background.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                    }
                }
            }
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
        .task { appLock.refreshCapability() }
    }

    private var appLockCaption: String {
        appLock.capability.lockPolicyAvailable
            ? "Locks Talaria on launch and on return to the foreground. Your device passcode always works as a fallback."
            : "Set a device passcode to use App Lock."
    }

    private var appLockEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.appLockEnabled },
            set: { settingsStore.settings.appLockEnabled = $0 }
        )
    }

    private func graceSegment(_ period: AppLockGracePeriod) -> some View {
        let active = settingsStore.settings.appLockGracePeriod == period
        return Button {
            settingsStore.settings.appLockGracePeriod = period
        } label: {
            Text(period.displayLabel.uppercased())
                .font(Design.Typography.display(10, weight: .semibold, relativeTo: .caption2))
                .tracking(Design.Tracking.button)
                .foregroundStyle(active ? Design.Colors.background : Design.Colors.secondaryForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(active ? Design.Brand.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 2: project.yml** — after `NSSpeechRecognitionUsageDescription`:
```yaml
        # #124: biometric app lock. Lives HERE, not as an INFOPLIST_KEY_
        # build setting — those are silently ignored with a generated
        # Info.plist (the #58 lesson).
        NSFaceIDUsageDescription: "Talaria uses Face ID to unlock the app."
```

- [ ] **Step 3: Regen + CLI build → BUILD SUCCEEDED**; verify the generated `Talaria/Resources/Info.plist` (if committed) picked up the key: `grep -A1 NSFaceIDUsageDescription Talaria/Resources/Info.plist`.
- [ ] **Step 4: Commit** `feat(#124): Privacy → App Lock section (adaptive label, grace picker) + NSFaceIDUsageDescription`

---

### Task 6: Full-suite gate + OPEN_ITEMS + PR

- [ ] **Step 1: Full suite** on a booted simulator (UITests need one):
```bash
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination '<sim>' 2>&1 | tail -30
```
Expected: green, counts ≥ 755/62 (baseline is currently 845/72 + the new AppLock tests). Run backgrounded (`nohup … &`) — long runs exceed the 4-min cap.
- [ ] **Step 2: `git status` clean** apart from intended changes (regen churn committed with its task).
- [ ] **Step 3: OPEN_ITEMS #124 update note** — built summary + the device checklist from the dispatch acceptance section (toggle→background→reopen prompt; two failures→passcode fallback; obscured switcher snapshot; Siri ask while locked + tap-through lands on lock). Commit `docs(#124): OPEN_ITEMS build note + device checklist`.
- [ ] **Step 4: Push + PR** into `main`, body: what/why, the two pinned decisions (intent bypass, window-hosted overlay + why), Lane V ordering note (already in main), device checklist, suite counts.

## Self-review notes

- Spec coverage: toggle+persistence (T2/T5), scene-root overlay + cold launch + grace (T1/T3/T4), snapshot obscuring (T4, decision stated), APNs/Live-Activity/widget non-interaction (no code touches those paths — they render outside the scene; PR body states it), intent-bypass comment (T3), fresh-LAContext + capability degradation (T3), pure tested decision function with no LAContext (T1), NSFaceIDUsageDescription via project.yml (T5), no new entitlements (none added), regen-per-add + file-scoped commits (each task), suite gate (T6).
- Type consistency: `AppLockConfiguration`/`AppLockScenePhase`/`AppLockCover`/`AppLockCapability` names used identically across T1–T5; controller init signature in T3 matches T4's wiring; `appLockConfiguration` computed prop (T2) used in T4.
- Known adjust-on-contact points (flagged, not placeholders): `GlowButton`/`ReactorOrb` initializer shapes, sim destination name, `Design.Typography` helpers — all mirrored from `LaunchSplashView`/`PrivacySettingsScreen` at implementation time.
