import SwiftUI

/// #320 — **the visible signal that this voice session is running on the
/// REALTIME engine**, so microphone audio is leaving the phone for the provider
/// configured on the user's own host.
///
/// Owen's ruling (2026-08-09, decision pass) was one decision with two
/// surfaces: the public copy becomes "no Talaria-operated cloud; realtime voice
/// uses your host's provider," **and the app stops relying on copy alone.** A
/// privacy claim a user can only verify by reading a web page is not a signal
/// they can act on in the moment. This is the in-the-moment half.
///
/// It is the complement of #18's rule rather than a restatement of it. #18 says
/// local voice is never *silently substituted* for the Realtime experience, and
/// the overlay's `LOCAL VOICE · ON-DEVICE PIPELINE` badge discharges that. This
/// discharges the other direction: realtime is never silently substituted for
/// local, either — and that direction is the one where audio leaves the device.
///
/// ## Bar 320-B — this reads the ENGINE, never the intent
///
/// `engine` here is `TalkSessionSnapshot.engine`, which #180 lane 180-L
/// established as a **fact**: `VoiceEngineRouter.forward(from:engine:)` stamps
/// each snapshot with the engine of the service that actually produced it,
/// and a snapshot from before anything has run carries no engine at all,
/// precisely so the router's provisional pick cannot masquerade as a
/// selection. (This lane extended that stamp to the router's pull-path
/// `snapshot` under a driving-only guard — see the comment there for the
/// defect that forced it. The pre-session states are untouched.)
///
/// Three sources were available and two of them are wrong:
/// - **The brain setting** (`ChatBackendRouter.Brain`) — wrong, and #303 is the
///   proof. A cold Control Center launch pins `.native` because `init` read the
///   brain ~35 ms before the sticky default restored `hermes`, and
///   `startSession()` has no upgrade branch. An indicator wired to the brain
///   would announce cloud audio for a session that never left the phone. **A
///   false privacy signal is worse than none**, because a user who learns the
///   badge over-fires learns to ignore it.
/// - **`VoiceEngineRouter.activeEngine`** — also wrong, for a smaller reason
///   that is easy to miss: the #198A instrument at
///   `VoiceEngineRouter.startSession()` logs `activeEngine` *before* the #221
///   last-line-of-defence gate can downgrade it, so that first log line is the
///   pre-gate pick and a `native` session can be preceded by a line naming
///   `realtime`. The correcting line follows immediately, so the *record* is
///   honest — but the first value is not authoritative and must not be a UI
///   source.
/// - **A copy constant** — wrong by construction; it would make the indicator a
///   restatement of the marketing claim it exists to back up.
///
/// ## Bar 320-C — fixed at session start, and it says so
///
/// #303 leaves **no mid-session upgrade path**, so within one session the
/// engine can only move `realtime → native` (the #221 gate, or the #247 B1
/// fallback) and never the reverse: `refreshReadiness()` returns early under an
/// active session, and `startSession()` contains only a downgrade branch. The
/// consequence for this surface is precise and is what makes a live derivation
/// safe: **the indicator can never ARM after a session has started.** It is
/// armed at start or not at all; if it clears, that is a genuine fall back to
/// local voice, which #18's badge then reports.
///
/// That is why this is a live derivation rather than a value latched at start.
/// A latch taken at start would survive the realtime→native fallback and keep
/// claiming cloud audio for a session that had become local — the exact lie
/// this lane exists to prevent, arriving by the other door.
///
/// The copy carries the same fact (`FIXED FOR THIS SESSION`) and the pip
/// deliberately does **not** blink: a pulsing indicator reads as live
/// monitoring of something that could change, and nothing here is being
/// monitored. **If a future lane adds an upgrade path, this doc comment and
/// bar 320-C are what tell it to revisit the surface.**
enum RealtimeVoiceNotice {

    // MARK: - The derivation

    /// Whether the realtime notice should be showing.
    ///
    /// Both inputs are facts published by the engine that produced the
    /// snapshot — see the type doc for why neither the brain nor the router's
    /// provisional pick is admissible here.
    ///
    /// `connectionState` is required as well as the engine because
    /// `voiceEngine` outlives a session (the store keeps the last engine for
    /// the settings row), and a badge that claimed audio was leaving the phone
    /// while nothing was running would be its own false signal. `.connecting`
    /// counts: the realtime bootstrap and the microphone open both happen
    /// inside that state, so waiting for `.connected` would warn late.
    nonisolated static func isArmed(
        engine: VoiceEngine?,
        connectionState: TalkConnectionState
    ) -> Bool {
        // Rule 5 (`HostFedListPresentation`): the unknown case gets its own
        // branch and falls to the negative. `nil` means no engine has been
        // published — that is not a realtime session.
        guard engine == .realtime else { return false }
        switch connectionState {
        case .connecting, .connected:
            return true
        case .idle, .checking, .ready, .blocked, .failed:
            return false
        }
    }

    // MARK: - Copy

    /// The consequence, stated first. Not the engine's name — a user who has
    /// never read the tracker does not know what "realtime" costs them.
    static let headline = "REALTIME VOICE · AUDIO LEAVES THIS PHONE"

    /// Where it goes, and the #303 fixedness (bar 320-C).
    static let detail = "TO YOUR HOST'S PROVIDER · FIXED FOR THIS SESSION"

    /// Bar 320-D: VoiceOver states the **consequence**, not the engine name
    /// alone. A blind user hearing "Realtime" learns nothing about where their
    /// microphone audio is going, which is the entire point of the surface.
    static let accessibilityLabel = """
        Realtime voice. Your audio leaves this phone and goes to the voice \
        provider configured on your host. This was set when the session \
        started and is fixed for this session.
        """

    /// Stable hook for UI assertions.
    static let accessibilityIdentifier = "voice.realtimeIndicator"

    /// Bar 320-D, the alert hue: the theme's warning token, resolved live by
    /// `ThemeRuntime`. It is carried by the PIP only — see `textColor` for why.
    @MainActor static var tint: Color { Design.Brand.forge }

    /// Bar 320-D, the legibility half — and this is the one place the lane
    /// departed from the obvious design, on measurement.
    ///
    /// The first draft rendered this badge in `forge`, matching the
    /// `LOCAL VOICE · ON-DEVICE PIPELINE` badge one line above it. Sweeping
    /// every `ThemeID × AccentSlot` for WCAG contrast against the theme's own
    /// background killed that: **`forge` bottoms out at 2.18:1**
    /// (`springSprout`, `pulpNoir` cyan/violet; `retroSciFi` 2.52,
    /// `winterFrost` 2.54) and clears WCAG AA's 4.5:1 for normal text in only
    /// about half the catalogue. `foregroundBright` never drops below
    /// **10.99:1** (`casinoLucky7s`) and is typically 16–20:1.
    ///
    /// For an ordinary warning that is a design-system question. For **this**
    /// badge it is disqualifying: a privacy signal the user cannot read in the
    /// theme they happen to be using has failed at its only job, and it fails
    /// silently. So the text takes the guaranteed-legible token and the `forge`
    /// pip carries the alert colour — a 5pt dot conveys "something is flagged"
    /// without being the thing that must be read.
    ///
    /// (The measurement also says the shipping `forge` badges are below AA text
    /// contrast in several themes. That is a real finding about the design
    /// system, filed separately — it is not this lane's to fix, and it is not a
    /// reason to copy the problem into a new surface.)
    @MainActor static var textColor: Color { Design.Colors.foregroundBright }
}

/// The badge itself. Renders nothing unless `RealtimeVoiceNotice.isArmed`.
struct RealtimeVoiceIndicator: View {
    let engine: VoiceEngine?
    let connectionState: TalkConnectionState

    var body: some View {
        if RealtimeVoiceNotice.isArmed(engine: engine, connectionState: connectionState) {
            VStack(spacing: Design.Spacing.xxxs) {
                HStack(spacing: Design.Spacing.xxs) {
                    // Deliberately non-blinking — see bar 320-C in the
                    // `RealtimeVoiceNotice` doc.
                    StatusPip(color: RealtimeVoiceNotice.tint, diameter: 5, blinks: false)
                    MonoLabel(
                        RealtimeVoiceNotice.headline,
                        size: 9,
                        weight: .medium,
                        tracking: Design.Tracking.monoWide,
                        color: RealtimeVoiceNotice.textColor
                    )
                }
                // Hierarchy comes from size, weight and tracking rather than a
                // dimmer colour. This line carries the DESTINATION, which is
                // the fact a user most needs off this badge, and
                // `foregroundBright` is the only token measured across the
                // whole catalogue — dimming it would trade a proven floor for
                // an unmeasured one on the more load-bearing of the two lines.
                MonoLabel(
                    RealtimeVoiceNotice.detail,
                    size: 8,
                    tracking: Design.Tracking.mono,
                    color: RealtimeVoiceNotice.textColor
                )
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RealtimeVoiceNotice.accessibilityLabel)
            .accessibilityIdentifier(RealtimeVoiceNotice.accessibilityIdentifier)
        }
    }
}
