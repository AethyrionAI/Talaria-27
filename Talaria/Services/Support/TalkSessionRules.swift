import AVFoundation
import Foundation
import os

// MARK: - Voice-residuals lane decision cores (#118 / #119)
//
// Residuals from the #82 confirm run, pure so they're testable without a
// device:
//   • `TalkBackgroundRule` — #118 (privacy): leaving the app must not leave
//     the capture chain (and the system mic indicator) live. There is no
//     background-audio voice mode in this app; backgrounding ends the
//     session. CarPlay is the one exemption — CarPlay voice runs with the
//     phone UI backgrounded by design (#19), and the CarPlay scene contract
//     explicitly keeps the session alive across connect/disconnect.
//   • `RealtimeErrorRule` — #119a: which realtime `error` events are normal
//     races to swallow, and which are real failures that must surface. A
//     cancel racing an already-completed response is a no-op, not a session
//     failure — the old handler bubbled the backend string into the session
//     UI AND flagged the connection `.failed`, which is also what wedged the
//     header on CONNECTING (#119b) mid-conversation.
//   • `AudioSessionOffMain` — the lane rider: synchronous AVAudioSession
//     activate/deactivate on the main thread logs an iOS 27
//     UI-unresponsiveness warning per call (`AVAudioSession_iOS.mm:978`).
//     Mechanics only — callers await, so the #106 ownership and ordering
//     (activation completes before engine start) are unchanged. **Since
//     #198B-M it also carries the instrument**: one always-on `.notice` per
//     transition, which is the positive control #198B-A's absence bar needs
//     (see `setActiveLogDetail`).

enum TalkBackgroundRule {
    /// True when a `didEnterBackground` event should revoke the voice session.
    /// Both engines answer to this rule: the realtime engine survives
    /// backgrounding (UIBackgroundModes `audio` keeps WebRTC streaming), and
    /// the native pipeline's capture chain outlives the scene — the mic
    /// indicator stays lit either way.
    ///
    /// **#254 — why there are three inputs and not one.**
    ///
    /// `isSessionActive` is derived in `TalkStore.applySnapshot` from the
    /// *engine's* published `connectionState`, so it is false for the prologue
    /// of every start (brain gate, pairing check, #82 mic preflight) and false
    /// AGAIN during the realtime→native fallback, where a start that landed
    /// `.failed` opens a local microphone from a not-active state. Gating on it
    /// alone made a start-in-flight invisible: backgrounding revoked nothing,
    /// and the connect came up live, speaking, on a forced loudspeaker with no
    /// UI and no owner.
    ///
    /// **`isStartingSession` is an ADDITION, not a replacement.** Revoking on
    /// every backgrounding would reach
    /// `AudioSessionOffMain.setActive(false, .notifyOthersOnDeactivation)`
    /// with nothing live — the #84 shape, where a stray deactivation on the
    /// shared session killed the live mic. The idle case must stay false.
    ///
    /// **CarPlay exempts BOTH arms** (#19): a start in flight in a car is
    /// still a session CarPlay is driving, and the new input must not smuggle
    /// a teardown past the exemption the live arm has always honoured.
    ///
    /// This rule is the ONLY backstop on the background path, and that is
    /// measured rather than assumed — bar 254-F (2026-08-09) established that
    /// `VoiceOverlayScreen.onDisappear` does **not** fire when the app
    /// backgrounds a presented `fullScreenCover`, so #139's unguarded
    /// `abandonSession()` never runs here.
    static func shouldEndSession(
        isSessionActive: Bool,
        isStartingSession: Bool,
        routeHasCarAudio: Bool
    ) -> Bool {
        (isSessionActive || isStartingSession) && !routeHasCarAudio
    }
}

enum RealtimeErrorRule {
    enum Disposition: Equatable {
        /// #119a: a barge-in/manual cancel raced a response that had already
        /// completed server-side. The connection is healthy and the
        /// conversation continues — log `.notice`, never touch session state.
        case swallowNoOpCancel
        /// Our own `response.create` after MCP tool completion raced an
        /// already-active response (pre-existing suppression, now classified).
        case swallowResponseCreateRace
        /// A real failure — surface it honestly.
        case surface
    }

    /// Classifies a realtime `error` event by its `code` and `message`.
    /// Matching is deliberately narrow — anything unrecognized fails open to
    /// `.surface` (an unnecessary banner beats a silently eaten failure).
    static func disposition(code: String?, message: String) -> Disposition {
        let lowered = message.lowercased()
        if code == "response_cancel_not_active"
            || (lowered.contains("cancel") && lowered.contains("no active response")) {
            return .swallowNoOpCancel
        }
        if lowered.contains("active response in progress") {
            return .swallowResponseCreateRace
        }
        return .surface
    }
}

/// #198: the iOS 27 interruption model, reduced to two pure decisions.
///
/// `AVAudioSession.interruptionNotification` carried a `.began`/`.ended` type
/// plus a `.shouldResume` option. Its successors are two SEPARATE
/// notifications, and the swap is **not** a rename:
///
/// - `didBecomeInactiveNotification` fires for deactivations the old `.began`
///   **never reported, including our own.**
/// - `resumptionRecommendationNotification` carries the resume decision that
///   used to ride `.ended` as an option flag.
///
/// The context objects delivered in those notifications
/// (`DeactivationContext`, `ResumptionContext`) declare `init` as
/// `NS_UNAVAILABLE`, so **no test can synthesize either notification.** That is
/// precisely why the decisions live here as pure functions over the plain
/// enums — those *are* constructible — and the notification handlers are kept
/// down to extract-and-delegate.
enum AudioInterruptionRule {

    /// Whether a `didBecomeInactive` deactivation is an interruption to react
    /// to, or merely us switching the session off.
    ///
    /// **This filter is the whole migration.** The app deactivates its own
    /// session at **ten** call sites across seven files — voice-session
    /// teardown, read-aloud finishing, voice-memo record and playback stop —
    /// and every one now emits `didBecomeInactive` with `source == .app`. The
    /// old `.began` fired for none of them, so without this a normal "stop
    /// talking" tap would report "Audio interrupted." to the user.
    ///
    /// Deliberately keyed on `source` alone and NOT on
    /// `DeactivationContext.interruptionContext`, which the header populates
    /// "only when the session was interrupted by another application" — that
    /// would silently drop the non-app interruptions the old code did handle
    /// (route disconnected, built-in mic muted, device locked). Between the two
    /// error directions, over-reporting is the safe one: an unwarranted
    /// `.interrupted` is recovered by the route-change handler, while a missed
    /// interruption leaves a dead capture chain that looks live.
    static func isInterruption(source: AVAudioSession.DeactivationSource) -> Bool {
        source == .system
    }

    /// Whether a resumption recommendation should resume capture. Replaces
    /// `InterruptionOptions.contains(.shouldResume)`; the system now states the
    /// recommendation outright instead of implying it by an absent flag.
    static func shouldResume(_ recommendation: AVAudioSession.ResumptionRecommendation) -> Bool {
        recommendation == .shouldResume
    }
}

/// Moves AVAudioSession calls off the main thread. `Task.detached` is
/// deliberate — a nonisolated async function can inherit the caller's actor
/// under `NonisolatedNonsendingByDefault`, which would put the call right
/// back on main; a detached task never does.
enum AudioSessionOffMain {
    private static let logger = Logger(
        subsystem: TalariaLog.subsystem,
        category: "AudioSessionOffMain"
    )

    /// **#198B-M — the memo path's always-on positive control.** Pure, pinned
    /// by `VoiceInstrumentLogLineTests`.
    ///
    /// #198B-A's device bar is an ABSENCE bar (zero `AVAudioSession_iOS.mm`
    /// fault lines across a memo record→play→discard session), and an absence
    /// bar with no positive control reads PASS on an empty log. The only
    /// app-emitted marker that path had was a `.debug` line, verbose-gated,
    /// on the RECORD leg alone — invisible to `log collect` and blind to play
    /// and discard. This line is emitted from the one off-main choke point all
    /// three transitions funnel through, at `.notice`, un-gated.
    ///
    /// `reason` is what makes it attributable: a full session emits four
    /// distinct legs, so a run that exercised only some of them says so
    /// instead of generalising.
    nonisolated static func setActiveLogDetail(active: Bool, reason: String) -> String {
        "AudioSessionOffMain: setActive(\(active)) off-main (#198B) reason=\(reason)"
    }

    /// Off-main `setActive`. Callers await, so call-site ordering relative to
    /// engine start/stop is exactly what it was when the call was inline.
    static func setActive(
        _ active: Bool,
        options: AVAudioSession.SetActiveOptions = [],
        reason: String
    ) async throws {
        try await run(activating: active, reason: reason) { session in
            try session.setActive(active, options: options)
        }
    }

    /// Off-main compound configuration (category + activation + overrides in
    /// one hop, preserving their relative order inside the closure).
    ///
    /// `activating` is how a COMPOUND caller declares which transition its
    /// closure performs — the closure is opaque here, so the direction cannot
    /// be read out of it. `nil` means the hop changes no activation state (a
    /// route read), and emits nothing.
    ///
    /// **The line is emitted on ENTRY, not on success.** A control that
    /// vanished when the transition threw would score the single most
    /// interesting run INVALID rather than surfacing it — and the claim the
    /// line makes ("this ran off-main") is true of the attempt.
    static func run<T: Sendable>(
        activating: Bool? = nil,
        reason: String = "unspecified",
        _ body: @escaping @Sendable (AVAudioSession) throws -> T
    ) async throws -> T {
        if let activating {
            logger.notice("\(setActiveLogDetail(active: activating, reason: reason), privacy: .public)")
        }
        return try await Task.detached(priority: .userInitiated) {
            try body(AVAudioSession.sharedInstance())
        }.value
    }
}

/// #198: the one place that knows how iOS 27 spells the tap installer.
///
/// **Why migrate at all**, when the deprecated `installTap` still works: it
/// reports failure by RAISING an Objective-C exception, which Swift cannot
/// catch. This codebase carries **two** hand-rolled mitigations that exist
/// only because of that:
///
/// - **#82** (`LiveSpeechService`) — a preflight refusing a degenerate capture
///   format, commented "uncatchable NSException otherwise".
/// - **#128** (`NativeVoicePipelineService`) — `removeTap` kept immediately
///   adjacent to the install because two interleaved capture starts
///   double-installed and crashed a device on 2026-07-17
///   (`CreateRecordingTap: nullptr == Tap()`), an invariant currently held by
///   nothing but a comment.
///
/// The successor returns an error instead of raising, so the same conditions
/// become recoverable. **Both preflights stay** — they prevent the failure,
/// this only makes the residue survivable.
///
/// **Why a wrapper.** `installTapOnBus:bufferSize:format:error:block:` is
/// `NS_REFINED_FOR_SWIFT` and AVFAudio ships no overlay for it in beta 4, so
/// the only callable spelling is the `__`-prefixed import — whose `error:`
/// parameter survives as a meaningless `()` where the `NSError**` was. That
/// spelling WILL change when the overlay lands. Confining it here means that
/// day edits one function instead of every call site, and the break is a
/// compile error rather than anything that reaches a user.
enum AudioNodeTap {
    /// Installs a capture tap, throwing instead of raising on failure.
    static func install(
        on node: AVAudioNode,
        bus: AVAudioNodeBus = 0,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock
    ) throws {
        // `error: ()` is the importer's placeholder for the consumed
        // `NSError**` — it carries no value. Verified against the beta-4
        // signature, which imports as
        // `(AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat?, (),
        //   @escaping AVAudioNodeTapBlock) throws -> ()`.
        try node.__installTap(
            onBus: bus,
            bufferSize: bufferSize,
            format: format,
            error: (),
            block: block
        )
    }
}
