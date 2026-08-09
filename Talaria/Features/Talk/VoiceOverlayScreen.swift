import OSLog
import SwiftUI
import UIKit

private let voiceOverlayLog = Logger(subsystem: "org.aethyrion.talaria", category: "VoiceOverlay")

private extension UIApplication.State {
    /// Named for the 254-F log line — an `onDisappear` that fires while the
    /// app is `.background` means something very different from one that
    /// fires while it is `.active`.
    var talariaName: String {
        switch self {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}

/// Full-screen arc-reactor "VOICE LINK" overlay.
/// Auto-starts a voice session on appear and tears it down on dismiss.
struct VoiceOverlayScreen: View {
    @Environment(TalkStore.self) private var talkStore
    @Environment(TabRouter.self) private var router

    @State private var showLiveCameraOverlay = false

    private var isSpeaking: Bool { talkStore.voiceState == .speaking }
    private var isLive: Bool {
        talkStore.connectionState == .connected && {
            switch talkStore.voiceState {
            case .listening, .thinking, .speaking: return true
            default: return false
            }
        }()
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            CornerBrackets(arm: Design.Size.bracket, lineWidth: 1.5, inset: Design.Spacing.md)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.top, Design.Spacing.md)

                Spacer()

                // Transcript area
                transcriptSection

                Spacer()

                // Voice orb
                VoiceOrb(voiceState: talkStore.voiceState, connectionState: talkStore.connectionState)
                    .onTapGesture {
                        if talkStore.voiceState == .speaking {
                            talkStore.interruptAssistant()
                        }
                    }
                    .padding(.bottom, Design.Spacing.sm)

                // Status label — always visible, adapts to state
                orbStatusLabel
                    .padding(.horizontal, Design.Spacing.xl)
                    .animation(Design.Motion.quickResponse, value: talkStore.connectionState)
                    .animation(Design.Motion.quickResponse, value: talkStore.voiceState)

                VoiceWaveform(isActive: isLive)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Design.Spacing.xxl)
                    .padding(.top, Design.Spacing.md)

                // #84: where audio is actually routed right now — a stale
                // Bluetooth route with a dead mic looks identical to a
                // healthy session without this line.
                if talkStore.isSessionActive, let route = talkStore.audioRouteSummary {
                    MonoLabel(
                        "ROUTE · \(route.uppercased())",
                        size: 9,
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.mutedForeground
                    )
                    .lineLimit(1)
                    .padding(.horizontal, Design.Spacing.xl)
                    .padding(.top, Design.Spacing.xs)
                }

                Spacer()

                // Bottom controls
                controlBar
                    .padding(.bottom, Design.Spacing.xxl)
            }
        }
        .task {
            // Skip the readiness check — go straight to session create.
            // If the host is offline or unconfigured, session create fails
            // with a clear error. This saves 2-4s of startup latency
            // (the prewarm RPC rebuilds voice context from disk + subprocess).
            await talkStore.startSessionDirectly()
        }
        .onDisappear {
            // #254 bar 254-F: this line records the ONE assumption the #254
            // mechanism rests on — that `onDisappear` does NOT fire when the
            // app backgrounds a presented `fullScreenCover`. If it fired on
            // background, the unguarded `abandonSession()` below would already
            // cover the connect-window race and no lifecycle fix would be
            // owed. Keep it: it is the cheapest possible re-check of a premise
            // that a future SwiftUI release could silently invert.
            voiceOverlayLog.notice("#254 254-F: VoiceOverlayScreen.onDisappear fired (appState=\(UIApplication.shared.applicationState.talariaName, privacy: .public))")
            // Always clean up the voice session when the overlay disappears.
            // Use a short delay to avoid killing the session when the camera
            // fullScreenCover appears (which triggers onDisappear transiently).
            //
            // #139: NO `isSessionActive` guard. That guard is why dismissal
            // during a slow connect tore nothing down: a start that has not yet
            // published `.connecting` is invisible to the flag, and the session
            // that came back later with a live mic was exactly that one.
            // `abandonSession()` revokes the connect whether or not it has
            // reached a state the store can see.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                // Re-check — if the overlay was re-presented (camera dismiss),
                // the session is still wanted. Only end if truly gone.
                if !showLiveCameraOverlay {
                    await talkStore.abandonSession()
                }
            }
        }
        .statusBarHidden(true)
        .fullScreenCover(isPresented: $showLiveCameraOverlay) {
            LiveCameraOverlay(
                onFrameCaptured: { frameData, _ in
                    // Send frames silently — model responds when user speaks
                    talkStore.sendImage(frameData, triggerResponse: false)
                },
                onDismiss: {
                    showLiveCameraOverlay = false
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Design.Spacing.xs) {
            MonoLabel(sessionHeaderLabel, tracking: Design.Tracking.monoWide)

            Text("HERMES")
                .font(Design.Typography.display(20, weight: .semibold, relativeTo: .title2))
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)

            // #18: local voice is a distinct mode, never silently substituted
            // for the Realtime experience — badge it whenever it's driving.
            if talkStore.voiceEngine == .native {
                MonoLabel(
                    "LOCAL VOICE · ON-DEVICE PIPELINE",
                    size: 9,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Brand.forge
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionHeaderLabel: String {
        Self.sessionHeaderLabel(
            engine: talkStore.voiceEngine,
            connectionState: talkStore.connectionState,
            duration: talkStore.sessionDuration
        )
    }

    /// #119b: bound to the live connection state machine — the label must
    /// never claim CONNECTING once the session is past the connect phase
    /// (the old shape fell back to CONNECTING for EVERY inactive state, so a
    /// mid-conversation `.failed` blip read as a stuck connect). Connected
    /// shows the ticking duration; blocked/failed show the state's own label.
    ///
    /// #180 lane 180-L (bar 180-C): extracted from a private computed property
    /// on the View so the derivation is unit-testable — the house pattern
    /// (`ChatScreen.sessionSummary`, `ChatStore.voiceTranscriptMessages`).
    ///
    /// **`engine == nil` means no engine has been selected, and the label must
    /// name none.** The neutral tag is deliberately "VOICE" and nothing more:
    /// #18's rule is that local voice is never silently substituted for the
    /// Realtime experience, so the unknown state must not read as a THIRD
    /// engine. It is the absence of a claim, not a new claim.
    /// (Copy owed Owen's approval — dispatch §8.5.)
    nonisolated static func sessionHeaderLabel(
        engine: VoiceEngine?,
        connectionState: TalkConnectionState,
        duration: TimeInterval
    ) -> String {
        // Rule 5: unknown gets its own branch, not the `else` branch.
        let tag: String
        switch engine {
        case .native:
            tag = "LOCAL VOICE"
        case .realtime:
            tag = connectionState == .connected ? "VOICE SESSION" : "VOICE LINK"
        case nil:
            tag = "VOICE"
        }
        switch connectionState {
        case .connected:
            return "\(tag) · \(formattedDuration(duration))"
        case .idle, .checking, .ready, .connecting:
            return engine == .native ? "\(tag) · STARTING" : "\(tag) · CONNECTING"
        case .blocked, .failed:
            return "\(tag) · \(connectionState.displayLabel.uppercased())"
        }
    }

    nonisolated static func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                HStack(spacing: Design.Spacing.xs) {
                    MonoLabel("LIVE TRANSCRIPT", tracking: Design.Tracking.monoWide)
                    Spacer(minLength: 0)
                    if isLive {
                        StatusPip(color: Design.Brand.accent, diameter: 6, blinks: true)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        ForEach(talkStore.transcriptItems) { item in
                            transcriptBubble(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.never)
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 280)
            }
            .padding(Design.Spacing.md)
        }
        .padding(.horizontal, Design.Spacing.lg)
    }

    @ViewBuilder
    private func transcriptBubble(_ item: TranscriptItem) -> some View {
        switch item.speaker {
        case .user:
            HStack {
                Spacer()
                if let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                                .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                        }
                } else if !item.text.isEmpty {
                    VStack(alignment: .trailing, spacing: Design.Spacing.xxxs) {
                        MonoLabel("YOU", tracking: Design.Tracking.mono)
                        Text(item.text)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.coolForeground)
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.vertical, Design.Spacing.sm)
                            .background(Design.Colors.accentTint(0.08), in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                            .overlay {
                                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                                    .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                            }
                            .opacity(item.isPartial ? 0.6 : 1)
                    }
                }
            }
        case .hermes:
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                    MonoLabel("HERMES", tracking: Design.Tracking.mono, color: Design.Colors.accentTint(0.7))
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(item.text)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.coolForeground)
                            .opacity(item.isPartial ? 0.72 : 1)
                        if item.isPartial && isLive {
                            BlinkingCaret()
                        }
                    }
                }
                Spacer()
            }
        case .system:
            MonoLabel(item.text, tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Orb Status

    @ViewBuilder
    private var orbStatusLabel: some View {
        switch (talkStore.connectionState, talkStore.voiceState) {
        case (.failed, _), (.blocked, _):
            VStack(spacing: Design.Spacing.sm) {
                Text(talkStore.blockedReason ?? "Unable to connect")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Brand.forge)
                    .multilineTextAlignment(.center)

                // Show "Open Settings" for permission-related blocks (#84:
                // shared predicate keeps the gate in lockstep with the
                // engines' standardized preflight wording).
                if let reason = talkStore.blockedReason,
                   TalkMicPreflight.isPermissionActionable(reason) {
                    openSettingsButton
                }
            }

        case (.checking, _), (.idle, _), (.connecting, _), (.ready, _):
            HStack(spacing: Design.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Design.Brand.accent)
                MonoLabel("ESTABLISHING LINK", weight: .medium, tracking: Design.Tracking.monoWide, color: Design.Brand.accent)
            }

        case (.connected, .listening):
            VStack(spacing: Design.Spacing.sm) {
                statusPipLabel("LISTENING", color: Design.Brand.accent, blinks: true)
                // #84 flatline tripwire: connected but no mic signal evidence
                // — say so instead of listening silently over a dead mic.
                if let hint = talkStore.micHealthHint {
                    Text(hint)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Brand.forge)
                        .multilineTextAlignment(.center)
                    openSettingsButton
                }
            }

        case (.connected, .thinking):
            statusPipLabel(
                (talkStore.statusMessage?.isEmpty == false ? talkStore.statusMessage! : "PROCESSING").uppercased(),
                color: Design.Brand.accent,
                blinks: true
            )

        case (.connected, .speaking):
            statusPipLabel("SPEAKING", color: Design.Brand.accent, blinks: true)

        case (_, .disconnected):
            statusPipLabel("DISCONNECTED", color: Design.Colors.danger, blinks: false)

        default:
            EmptyView()
        }
    }

    private func statusPipLabel(_ text: String, color: Color, blinks: Bool) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: color, diameter: 7, blinks: blinks)
            MonoLabel(text, size: 11, weight: .medium, tracking: Design.Tracking.monoWide, color: color)
        }
    }

    private var openSettingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Text("OPEN SETTINGS")
                .font(Design.Typography.mono(11, weight: .medium))
                .tracking(Design.Tracking.monoWide)
                .foregroundStyle(Design.Brand.accentBright)
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.vertical, Design.Spacing.xs)
                .background(Design.Colors.accentTint(0.1), in: Capsule())
                .overlay { Capsule().strokeBorder(Design.Colors.strongBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: Design.Spacing.lg) {
            if talkStore.isSessionActive {
                // Left secondary — live camera (neutral chip)
                secondaryButton(
                    systemName: "video.fill",
                    accessibility: "Open live camera",
                    tint: Design.Colors.foreground,
                    accent: false
                ) { showLiveCameraOverlay = true }

                // Left secondary — mute (neutral chip)
                secondaryButton(
                    systemName: talkStore.isMuted ? "mic.slash.fill" : "mic.fill",
                    accessibility: talkStore.isMuted ? "Unmute" : "Mute",
                    tint: talkStore.isMuted ? Design.Colors.danger : Design.Colors.foreground,
                    accent: false
                ) { Task { await talkStore.toggleMute() } }

                Spacer()

                // Centre / end — danger, glowing
                endButton {
                    Task {
                        await talkStore.endSession()
                        router.isVoiceOverlayPresented = false
                    }
                }
            } else {
                Spacer()

                // Close button when not active (e.g. failed to start)
                endButton {
                    router.isVoiceOverlayPresented = false
                }
            }
        }
        .padding(.horizontal, Design.Spacing.xl)
    }

    private func secondaryButton(
        systemName: String,
        accessibility: String,
        tint: Color,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(
                    accent ? Design.Colors.accentTint(0.1) : Design.Colors.chipSurface,
                    in: Circle()
                )
                .overlay {
                    Circle().strokeBorder(
                        accent ? Design.Colors.strongBorder : Design.Colors.chipBorder,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private func endButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "phone.down.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Design.Colors.dangerBright)
                .frame(width: 56, height: 56)
                .background(Design.Colors.danger.opacity(0.22), in: Circle())
                .overlay {
                    Circle().strokeBorder(Design.Colors.danger.opacity(0.7), lineWidth: 1.5)
                }
                .hudGlow(Design.Colors.danger, radius: 20, strength: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End voice session")
    }
}
