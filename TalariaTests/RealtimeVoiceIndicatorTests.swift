import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Talaria

/// #320 — **the realtime voice indicator.**
///
/// Owen's ruling (2026-08-09) was one decision with two surfaces: the public
/// copy becomes "no Talaria-operated cloud; realtime voice uses your host's
/// provider," and the app stops relying on copy alone — a voice session running
/// on the realtime engine shows a visible signal, so the user can tell in the
/// moment that audio is leaving the phone.
///
/// The bars (pre-registered 2026-08-11, before any code) are named on each
/// test. The one carrying real risk is **320-B**: the indicator's source must
/// be the ENGINE actually in use, never the brain setting — #303's cold
/// Control Center launch pins `.native` while the brain says `hermes`, and an
/// indicator wired to the brain would announce cloud audio for a session that
/// never left the phone.
@MainActor
struct RealtimeVoiceIndicatorTests {

    // MARK: - Harness

    /// A voice service the tests drive by hand.
    ///
    /// `stampsEngine` is the load-bearing knob and it models a **production
    /// asymmetry**, not a test convenience: `NativeVoicePipelineService:71` is
    /// the only engine that stamps `TalkSessionSnapshot.engine` itself;
    /// `LiveVoiceSessionService` never has. A realtime stub that stamps its own
    /// engine would quietly hide the whole class of defect this file pins.
    @MainActor
    final class StubVoiceService: VoiceSessionServiceProtocol {
        let engine: VoiceEngine
        var stampsEngine: Bool

        var voiceState: VoiceState = .idle
        var connectionState: TalkConnectionState = .idle
        var transcriptItems: [TranscriptItem] = []
        var sessionDuration: TimeInterval = 0
        var isMuted = false
        var blockedReason: String?
        var statusMessage: String?
        var canStartSession = true
        var latencyMetrics = TalkLatencyMetrics()
        var readiness = TalkReadinessInfo()

        private(set) var startCalls = 0
        private(set) var endCalls = 0
        /// Connection state this stub lands in when `startSession()` runs.
        var stateAfterStart: TalkConnectionState = .connected
        /// Connection state this stub lands in when `refreshReadiness()` runs.
        var stateAfterRefresh: TalkConnectionState = .ready

        init(engine: VoiceEngine, stampsEngine: Bool = true) {
            self.engine = engine
            self.stampsEngine = stampsEngine
        }

        var snapshot: TalkSessionSnapshot {
            var built = TalkSessionSnapshot(
                voiceState: voiceState,
                connectionState: connectionState,
                transcriptItems: transcriptItems,
                sessionDuration: sessionDuration,
                isMuted: isMuted,
                blockedReason: blockedReason,
                statusMessage: statusMessage,
                canStartSession: canStartSession,
                latencyMetrics: latencyMetrics,
                voiceSessionID: nil,
                readiness: readiness
            )
            if stampsEngine { built.engine = engine }
            return built
        }

        private let hub = TalkSessionEventHub()
        func events() -> AsyncStream<TalkSessionEvent> { hub.stream(initial: snapshot) }
        /// Push a snapshot the way a live engine does, so the router's
        /// `forward(from:engine:)` stamp is exercised.
        func publish() { hub.publish(snapshot: snapshot) }

        func refreshReadiness() async {
            connectionState = stateAfterRefresh
        }

        func startSession() async {
            startCalls += 1
            connectionState = stateAfterStart
            voiceState = stateAfterStart == .connected ? .listening : .thinking
            publish()
        }

        func endSession() async {
            endCalls += 1
            connectionState = .idle
            voiceState = .idle
            publish()
        }

        func toggleMute() async { isMuted.toggle() }
        func manuallyInterruptAssistantOutput() {}
        @discardableResult
        func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool { false }
    }

    /// A brain the test can move between the router's `init` and its
    /// `startSession()` — which is the entire mechanism of #303.
    @MainActor
    final class BrainBox {
        var value: ChatBackendRouter.Brain
        init(_ value: ChatBackendRouter.Brain) { self.value = value }
    }

    /// Builds the production wiring: an unstamping realtime engine, a stamping
    /// native one, behind the real `VoiceEngineRouter`, feeding a real
    /// `TalkStore`. Nothing here is a test double for the code under test —
    /// only the two leaf engines are stubs.
    private func makeStack(
        brain: BrainBox,
        relayPaired: Bool = true,
        realtimeStateAfterStart: TalkConnectionState = .connected
    ) -> (realtime: StubVoiceService, native: StubVoiceService, router: VoiceEngineRouter, store: TalkStore) {
        let realtime = StubVoiceService(engine: .realtime, stampsEngine: false)
        realtime.stateAfterStart = realtimeStateAfterStart
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(
            realtime: realtime,
            native: native,
            isVoiceHostPaired: { relayPaired },
            activeBrain: { brain.value }
        )
        return (realtime, native, router, TalkStore(voiceService: router))
    }

    // MARK: - 320-A — both arms, one test

    /// **320-A.** A session on the realtime engine shows the indicator; a
    /// session on the native engine does not. Both arms are asserted here
    /// deliberately — the bar says a positive-arm-only test does not score,
    /// because an indicator that is simply always on would pass one.
    ///
    /// Both arms run the same stack and differ in exactly one input: whether
    /// the brain permits realtime at the moment the router is built.
    @Test func realtimeSessionShowsTheIndicatorAndANativeSessionDoesNot() async {
        // ARM 1 — realtime.
        let realtimeBrain = BrainBox(.hermes)
        let realtimeStack = makeStack(brain: realtimeBrain)
        #expect(realtimeStack.router.activeEngine == .realtime)
        await realtimeStack.store.startSession()

        #expect(realtimeStack.realtime.startCalls == 1)
        #expect(realtimeStack.native.startCalls == 0)
        #expect(realtimeStack.store.voiceEngine == .realtime)
        #expect(RealtimeVoiceNotice.isArmed(
            engine: realtimeStack.store.voiceEngine,
            connectionState: realtimeStack.store.connectionState
        ), "a realtime session must show the indicator — this is the whole point of #320")

        // ARM 2 — native. Same stack, same start, brain forbids realtime.
        let nativeBrain = BrainBox(.onDevice)
        let nativeStack = makeStack(brain: nativeBrain)
        #expect(nativeStack.router.activeEngine == .native)
        await nativeStack.store.startSession()

        #expect(nativeStack.native.startCalls == 1)
        #expect(nativeStack.realtime.startCalls == 0)
        #expect(nativeStack.store.voiceEngine == .native)
        #expect(RealtimeVoiceNotice.isArmed(
            engine: nativeStack.store.voiceEngine,
            connectionState: nativeStack.store.connectionState
        ) == false, "a local session must NOT claim audio is leaving the phone")
    }

    // MARK: - 320-B — the indicator reads the ENGINE, not the intent

    /// **320-B, the bar that carries the risk — #303's cold-launch shape,
    /// reproduced.**
    ///
    /// `VoiceEngineRouter.init` picks the engine from
    /// `realtimeIsPermitted(activeBrain()) && isVoiceHostPaired()`. On a cold
    /// Control Center launch it reads the brain ~35 ms BEFORE the sticky
    /// default restores `hermes`, and `startSession()` has a downgrade branch
    /// but no upgrade — so the session runs NATIVE while the brain says
    /// `hermes` (build 2330, 14:00:22.780 → 14:00:23.113).
    ///
    /// An indicator sourced from the brain would announce cloud audio for a
    /// session whose microphone audio never left the device. That is worse
    /// than no indicator: a false privacy signal teaches the user to discount
    /// the true ones.
    @Test func indicatorReadsTheEngineNotTheBrainOnTheColdLaunchShape() async {
        // t=0 — the brain has not been restored yet.
        let brain = BrainBox(.onDevice)
        let stack = makeStack(brain: brain)
        #expect(stack.router.activeEngine == .native, "#303: init pinned native")

        // t=35ms — the sticky default restores `hermes`. The BRAIN now permits
        // realtime, and nothing re-routes (#303: no upgrade path).
        brain.value = .hermes
        #expect(VoiceEngineRouter.realtimeIsPermitted(for: brain.value),
                "the brain-sourced indicator would arm from here — that is the trap")

        await stack.store.startSession()

        // The session really is native…
        #expect(stack.native.startCalls == 1)
        #expect(stack.realtime.startCalls == 0)
        #expect(stack.store.voiceEngine == .native)
        // …so the indicator must stay dark, brain notwithstanding.
        #expect(RealtimeVoiceNotice.isArmed(
            engine: stack.store.voiceEngine,
            connectionState: stack.store.connectionState
        ) == false,
                "the brain permits realtime but the ENGINE is native — announcing cloud audio here is a false privacy signal")
    }

    /// **320-B, second half — the source is not a copy constant either.** The
    /// derivation is total over its inputs and depends on nothing else: for
    /// every engine × connection-state pair the answer is a pure function of
    /// the pair, and it is affirmative in exactly the realtime-and-driving
    /// cells.
    @Test func theDerivationIsAPureFunctionOfEngineAndConnectionState() {
        let driving: Set<TalkConnectionState> = [.connecting, .connected]
        let allStates: [TalkConnectionState] = [.idle, .checking, .ready, .connecting, .connected, .blocked, .failed]

        for state in allStates {
            #expect(RealtimeVoiceNotice.isArmed(engine: .realtime, connectionState: state)
                    == driving.contains(state),
                    "realtime × \(state.rawValue)")
            #expect(RealtimeVoiceNotice.isArmed(engine: .native, connectionState: state) == false,
                    "native × \(state.rawValue) must never arm")
            #expect(RealtimeVoiceNotice.isArmed(engine: nil, connectionState: state) == false,
                    "unknown × \(state.rawValue) must never arm — nil is 'no engine published', not 'probably realtime'")
        }
    }

    /// **320-B, third — the pull path must not lose the stamp.**
    ///
    /// Found while wiring this lane. `LiveVoiceSessionService` never stamps its
    /// own snapshots, so on the realtime path the engine reached the store only
    /// through the event stream — while `TalkStore` also pulls
    /// `voiceService.snapshot` directly at every decision point and writes the
    /// result over it. `toggleMute()` mid-session therefore wrote
    /// `voiceEngine = nil` on a live realtime session and the indicator blinked
    /// out until the engine next happened to publish.
    ///
    /// A privacy signal whose truthfulness depends on how chatty the engine is
    /// does not meet 320-B. `VoiceEngineRouter.snapshot` now stamps provenance
    /// when the active service is actually driving.
    @Test func theIndicatorSurvivesAMidSessionPullOfTheSnapshot() async {
        let brain = BrainBox(.hermes)
        let stack = makeStack(brain: brain)
        await stack.store.startSession()
        #expect(stack.store.voiceEngine == .realtime)

        // `toggleMute` ends with `applySnapshot(voiceService.snapshot)` — the
        // pull path, with no event behind it.
        await stack.store.toggleMute()

        #expect(stack.store.voiceEngine == .realtime,
                "a pulled snapshot must not erase the engine of a live session")
        #expect(RealtimeVoiceNotice.isArmed(
            engine: stack.store.voiceEngine,
            connectionState: stack.store.connectionState
        ), "the indicator must hold for the whole session, not most of it")
    }

    /// The other half of that fix: it must not resurrect #180-C. Before
    /// anything has run, the router's snapshot still names NO engine — the
    /// init guess may not reach the header.
    @Test func aPreSessionSnapshotStillNamesNoEngine() {
        let brain = BrainBox(.hermes)
        let stack = makeStack(brain: brain)

        #expect(stack.router.activeEngine == .realtime, "the init guess is realtime…")
        #expect(stack.router.snapshot.engine == nil, "…and it must not appear on an idle snapshot (#180-C)")
        #expect(stack.store.voiceEngine == nil)
        #expect(RealtimeVoiceNotice.isArmed(
            engine: stack.store.voiceEngine,
            connectionState: stack.store.connectionState
        ) == false)

        for state in [TalkConnectionState.checking, .ready, .blocked, .failed] {
            stack.realtime.connectionState = state
            #expect(stack.router.snapshot.engine == nil,
                    "\(state.rawValue) is not a driving state — provenance may not be claimed")
        }
    }

    // MARK: - 320-C — fixed at session start

    /// **320-C.** #303 leaves no mid-session upgrade path, so the indicator
    /// must not imply live tracking. The structural guarantee is that it can
    /// only ever be armed AT start: within a session the engine can move
    /// `realtime → native` (the #221 gate, the #247 B1 fallback) but never the
    /// reverse — `refreshReadiness()` returns early under an active session and
    /// `startSession()` has only a downgrade branch.
    ///
    /// This exercises the one transition that exists. A realtime start that
    /// fails falls back to local voice, and the indicator CLEARS — it does not
    /// keep claiming cloud audio for a session that became local, which is what
    /// a value latched at session start would have done.
    @Test func theIndicatorClearsWhenARealtimeStartFallsBackToLocalVoice() async {
        let brain = BrainBox(.hermes)
        let stack = makeStack(brain: brain, realtimeStateAfterStart: .failed)
        #expect(stack.router.activeEngine == .realtime)

        await stack.store.startSession()

        #expect(stack.realtime.startCalls == 1, "realtime was attempted…")
        #expect(stack.native.startCalls == 1, "…and #247 B1 fell back to local voice")
        #expect(stack.store.voiceEngine == .native)
        #expect(RealtimeVoiceNotice.isArmed(
            engine: stack.store.voiceEngine,
            connectionState: stack.store.connectionState
        ) == false,
                "the session is local now — a latched start value would still be claiming cloud audio")
    }

    /// **320-C, the no-upgrade guarantee stated as a test.** A live session's
    /// readiness refresh must not be able to route to realtime, which is what
    /// would let the indicator arm mid-session.
    @Test func aLiveNativeSessionCannotBeUpgradedToRealtimeByARefresh() async {
        let brain = BrainBox(.onDevice)
        let stack = makeStack(brain: brain)
        await stack.store.startSession()
        #expect(stack.store.voiceEngine == .native)

        // The brain flips mid-session and readiness is refreshed. The stub is
        // told to stay connected so the assertion is about ROUTING and not
        // about a stub that hung up on itself.
        brain.value = .hermes
        stack.native.stateAfterRefresh = .connected
        await stack.store.refreshReadiness()

        #expect(stack.router.activeEngine == .native,
                "no silent engine swap under an active session")
        #expect(RealtimeVoiceNotice.isArmed(
            engine: stack.store.voiceEngine,
            connectionState: stack.store.connectionState
        ) == false,
                "the indicator must never ARM after a session has started")
    }

    /// **320-C, the copy half — "and says so."** The surface states that the
    /// choice is fixed for the session, so nothing on screen reads as live
    /// monitoring of a thing that could change.
    @Test func theCopySaysTheChoiceIsFixedForTheSession() {
        let combined = (RealtimeVoiceNotice.headline + " " + RealtimeVoiceNotice.detail).uppercased()
        #expect(combined.contains("FIXED FOR THIS SESSION"))
        #expect(RealtimeVoiceNotice.accessibilityLabel
            .localizedCaseInsensitiveContains("fixed for this session"))
        #expect(RealtimeVoiceNotice.accessibilityLabel
            .localizedCaseInsensitiveContains("when the session started"))
    }

    // MARK: - 320-D — theme + VoiceOver

    /// **320-D, VoiceOver.** The label must state the CONSEQUENCE, not the
    /// engine name alone. "Realtime" tells a user who has never read the
    /// tracker nothing about where their microphone audio goes; #18's
    /// no-silent-substitution rule is the family this belongs to, and its whole
    /// content is that the user gets to know which way the audio went.
    @Test func theVoiceOverLabelStatesTheConsequenceNotJustTheEngineName() {
        let label = RealtimeVoiceNotice.accessibilityLabel

        #expect(label.localizedCaseInsensitiveContains("audio"))
        #expect(label.localizedCaseInsensitiveContains("leaves this phone"))
        #expect(label.localizedCaseInsensitiveContains("provider configured on your host"))
        // The engine name alone would not score this bar.
        let strippedOfEngineName = label.replacingOccurrences(
            of: "realtime", with: "", options: .caseInsensitive)
        #expect(strippedOfEngineName.localizedCaseInsensitiveContains("goes to"),
                "the consequence must survive deleting the engine's name from the label")
        #expect(!RealtimeVoiceNotice.accessibilityIdentifier.isEmpty)
    }

    /// **320-D, the visible copy.** The headline leads with the consequence
    /// too — a HUD badge reading only `REALTIME` would be the engine name
    /// alone, in the sighted arm.
    @Test func theVisibleHeadlineLeadsWithTheConsequence() {
        #expect(RealtimeVoiceNotice.headline.contains("AUDIO LEAVES THIS PHONE"))
        #expect(RealtimeVoiceNotice.detail.contains("YOUR HOST'S PROVIDER"))
        // #18: the two badges must stay distinguishable — this one must not
        // borrow the local badge's wording.
        #expect(!RealtimeVoiceNotice.headline.contains("LOCAL VOICE"))
        #expect(!RealtimeVoiceNotice.headline.contains("ON-DEVICE"))
    }

    /// **320-D, theme — asserted as a real WCAG contrast ratio**, because
    /// "renders" and "can be read" are different claims and only the second one
    /// is worth anything for a privacy signal. The sweep covers every
    /// `ThemeID × AccentSlot` in the catalogue, which is what puts the light
    /// Paper Tape in scope alongside the twenty dark themes.
    ///
    /// **4.5:1 is WCAG 2.1 AA for normal text** (SC 1.4.3); the badge is 9pt
    /// and 8pt mono, which is small text by any reading, so this is the floor
    /// and not a claim of comfort. `foregroundBright` clears it everywhere with
    /// a wide margin — the measured minimum is 10.99:1 on `casinoLucky7s`.
    ///
    /// **This bar is why the badge is not `forge`.** Measured on the same
    /// sweep, `forge` against the theme's own background is 2.18:1 at worst
    /// (`springSprout`, `pulpNoir` cyan/violet), 2.52 on `retroSciFi`, 2.54 on
    /// `winterFrost` — under even the 3.0:1 non-text threshold in four themes,
    /// and under AA text contrast in roughly half the catalogue. The first
    /// draft of this indicator used it, matching the `LOCAL VOICE` badge, and
    /// this test is what caught it.
    @Test func theIndicatorTextIsLegibleInEveryThemeIncludingPaperTape() {
        #expect(ThemeID.allCases.contains(.paperTape), "the light theme must be in the sweep")
        #expect(ThemeID.allCases.count >= 20, "the sweep must cover the whole catalogue")

        var worst = Double.infinity
        for theme in ThemeID.allCases {
            for accent in AccentSlot.allCases {
                let palette = ThemePalette(theme: theme, accent: accent)
                let ratio = Self.contrastRatio(palette.foregroundBright, palette.background)
                worst = min(worst, ratio)
                #expect(ratio >= 4.5,
                        "\(theme.rawValue) × \(accent.rawValue): indicator text on background is \(String(format: "%.2f", ratio)):1")
                // The pip is decorative — the text carries every fact — but it
                // still has to be a different colour from what it sits on.
                #expect(palette.forge != palette.background)
            }
        }
        #expect(worst >= 4.5, "worst case across the catalogue was \(String(format: "%.2f", worst)):1")
    }

    /// The measurement that DECIDED the colour, pinned so a later "make it
    /// forge like the other badge" edit has to argue with a number. If the
    /// design system ever raises `forge` above AA everywhere, this test fails
    /// and the indicator can go back to the warning hue — which is the outcome
    /// this pin is hoping for, not one it is blocking.
    ///
    /// **⚠️ UPDATED 2026-08-21 by #325, which changed the numbers under this
    /// test without changing its verdict.** `forge` was nudged in four light
    /// themes to clear the 3.0:1 NON-TEXT floor, so the measured minimum is no
    /// longer 2.18:1 — it is ~3.03:1. Still under AA, so `offenders` is still
    /// non-empty and this pin still holds.
    ///
    /// **But the outcome it hoped for has arrived by another route.** #325 did
    /// not raise `forge` above AA; it added `Design.Brand.forgeText`, which
    /// clears 4.5:1 in every theme. **So this badge COULD now use the warning
    /// hue legibly** — via `forgeText` rather than via `forge`. That is a
    /// design decision for #320's surface and Owen's to make, so it is named
    /// here and deliberately not taken: changing the badge inside a palette
    /// lane would be #325 quietly editing #320's ruled outcome.
    @Test func theWarningTokenIsNotLegibleEnoughForThisBadgeInEveryTheme() {
        let offenders = ThemeID.allCases.filter { theme in
            Self.contrastRatio(
                ThemePalette(theme: theme, accent: .cyan).forge,
                ThemePalette(theme: theme, accent: .cyan).background
            ) < 4.5
        }
        #expect(!offenders.isEmpty,
                "forge falls under AA text contrast in several themes — min 2.18:1 as measured 2026-08-11, ~3.03:1 after #325 nudged four light themes to the 3.0 non-text floor. Still under AA, which is why this badge uses foregroundBright rather than forge. #325's forgeText is the legible alternative and is a #320 decision, not a #325 one.")
        #expect(offenders.contains(.springSprout) || offenders.contains(.retroSciFi) || offenders.contains(.winterFrost),
                "the measured worst cases were springSprout / retroSciFi / winterFrost / pulpNoir")
    }

    /// **320-D, no literal colour.** The tint is the theme's own `forge` token
    /// as `ThemeRuntime` resolves it right now, so a theme switch re-skins the
    /// badge with everything else. Asserted by identity with `Design.Brand`
    /// rather than by mutating the shared runtime: Swift Testing runs suites in
    /// parallel, and a test that reassigns the app-wide theme would be a flake
    /// generator for every other theme-reading test in the bundle.
    @Test func theIndicatorTintIsTheLiveThemeTokenAndNotALiteral() {
        #expect(RealtimeVoiceNotice.tint == Design.Brand.forge)
        #expect(RealtimeVoiceNotice.tint == ThemeRuntime.shared.palette.forge)
        #expect(RealtimeVoiceNotice.textColor == Design.Colors.foregroundBright)
        #expect(RealtimeVoiceNotice.textColor == ThemeRuntime.shared.palette.foregroundBright)

        // The view is a pure function of its two inputs — armed and dark forms
        // both build, and both agree with the derivation.
        let armed = RealtimeVoiceIndicator(engine: .realtime, connectionState: .connected)
        let dark = RealtimeVoiceIndicator(engine: .native, connectionState: .connected)
        #expect(RealtimeVoiceNotice.isArmed(engine: armed.engine, connectionState: armed.connectionState))
        #expect(!RealtimeVoiceNotice.isArmed(engine: dark.engine, connectionState: dark.connectionState))
    }

    // MARK: - Contrast helper

    /// WCAG 2.1 relative luminance. Both inputs are opaque sRGB literals from
    /// the palette catalog, so the `UIColor` round-trip is exact.
    private static func relativeLuminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private static func contrastRatio(_ a: Color, _ b: Color) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
