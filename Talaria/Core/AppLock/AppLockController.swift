import Foundation
import LocalAuthentication
import os

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

    // MARK: - #272 diagnostics
    //
    // The re-prompt loop Owen reported on 2026-07-25 has never been seen
    // twice and has never been diagnosed. These lines are ALWAYS ON — not
    // behind Verbose Logging — because the event is rare, cheap, and only
    // useful if it is already recording when it happens. `.notice` (not
    // `.info`) because Console.app hides `.info` by default, and every
    // interpolation is `privacy: .public` or it redacts. Bar 272-B.
    @ObservationIgnored
    private let log = Logger(subsystem: TalariaLog.subsystem, category: "AppLock")

    /// Attempts made in the CURRENT lock episode. Reset when the episode ends
    /// (a successful unlock, or the lock being disabled) — so a log grep
    /// reads "attempt=3" directly instead of needing timestamp math over a
    /// Console pull.
    @ObservationIgnored private var episodeAttempt = 0

    /// Previous scene phase, tracked only so the log can show old → new.
    @ObservationIgnored private var lastPhase: AppLockScenePhase = .background

    /// Single emission point. Builds a plain `String` and hands it over as
    /// one public interpolation — the `TalariaLog.event` pattern, which keeps
    /// the format string trivial and the redaction behaviour unambiguous.
    private func note(_ line: String) {
        log.notice("\(line, privacy: .public)")
    }

    private static func label(_ phase: AppLockScenePhase) -> String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        }
    }

    private static func label(_ cover: AppLockCover) -> String {
        switch cover {
        case .none: "none"
        case .obscured: "obscured"
        case .locked: "locked"
        }
    }

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
        // Pre-state, BEFORE this function's own mutations — the whole point
        // of #272's instrumentation is to see what the guards saw.
        let previousPhase = lastPhase
        lastPhase = phase
        note(
            "scenePhase \(Self.label(previousPhase)) -> \(Self.label(phase))"
                + " | pre: cover=\(Self.label(cover)) locked=\(machine.isLocked)"
                + " authenticating=\(isAuthenticating) didFail=\(didFailAuthentication)"
                + " attempt=\(episodeAttempt)"
        )
        if phase == .active {
            // Biometry enrollment can change while backgrounded.
            refreshCapability()
            // Logged only when it CLEARS a real failure — a false->false
            // reset is noise. When this fires it is the single line that
            // explains a re-prompt: the retry flag did not survive.
            if didFailAuthentication {
                note("didFailAuthentication true->false on .active (retry flag cleared by foreground, attempt=\(episodeAttempt))")
            }
            didFailAuthentication = false
        }
        machine.scenePhaseChanged(to: phase, configuration: effectiveConfiguration(), now: now())
        refreshCover()
        autoAuthenticateIfNeeded()
    }

    func configurationChanged() {
        let configuration = effectiveConfiguration()
        machine.configurationChanged(configuration)
        if !configuration.isEnabled, episodeAttempt != 0 {
            note("configurationChanged: lock disabled, episode attempt counter reset (was \(episodeAttempt))")
            episodeAttempt = 0
        }
        refreshCover()
    }

    func refreshCapability() {
        capability = authenticator.capability()
    }

    func requestUnlock() async {
        // Split from one `guard` into three so the log can name WHICH clause
        // declined. Same clauses, same order, same short-circuiting.
        guard machine.isLocked else {
            note("requestUnlock DECLINED guard=notLocked")
            return
        }
        guard effectiveConfiguration().isEnabled else {
            note("requestUnlock DECLINED guard=lockDisabled")
            return
        }
        guard !isAuthenticating else {
            note("requestUnlock DECLINED guard=alreadyAuthenticating")
            return
        }
        episodeAttempt += 1
        let attempt = episodeAttempt
        note("requestUnlock ENTER attempt=\(attempt) (this lock episode)")
        isAuthenticating = true
        defer { isAuthenticating = false }
        // Fresh LAContext per attempt inside the authenticator (single-use contexts).
        let unlocked = await authenticator.authenticate(reason: "Unlock Talaria")
        if unlocked {
            machine.authenticationSucceeded()
            didFailAuthentication = false
            note("requestUnlock EXIT attempt=\(attempt) result=SUCCESS (episode ends, counter reset)")
            episodeAttempt = 0
        } else {
            didFailAuthentication = true
            note("requestUnlock EXIT attempt=\(attempt) result=FAILED_OR_CANCELLED didFail=true")
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
    ///
    /// ⚠️ #272: that second clause is a PROMISE THIS CODE DOES NOT KEEP —
    /// `scenePhaseChanged(to:)` clears `didFailAuthentication` on every
    /// `.active` before this runs, so a foreground event re-arms the prompt
    /// with no user tap. Reproduced deterministically in
    /// `TalariaTests/AppLockControllerRaceTests.swift`; the fix is a separate
    /// lane (see OPEN_ITEMS #272, bars 272-A/D). Do not delete this note
    /// until the reproduction's assertions have been inverted.
    ///
    /// Split from one `guard` into four so the log can name WHICH clause
    /// blocked. Same clauses, same order, same short-circuiting.
    private func autoAuthenticateIfNeeded() {
        guard cover == .locked else {
            note("autoAuth BLOCKED guard=cover(\(Self.label(cover)))")
            return
        }
        guard machine.phase == .active else {
            note("autoAuth BLOCKED guard=phase(\(Self.label(machine.phase)))")
            return
        }
        guard !isAuthenticating else {
            note("autoAuth BLOCKED guard=isAuthenticating")
            return
        }
        guard !didFailAuthentication else {
            note("autoAuth BLOCKED guard=didFailAuthentication (retry button is showing)")
            return
        }
        note("autoAuth FIRED (no tap) after attempt=\(episodeAttempt) this episode")
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
