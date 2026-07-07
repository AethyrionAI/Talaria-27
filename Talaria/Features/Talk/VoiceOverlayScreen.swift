import SwiftUI
import UIKit

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
            // Always clean up the voice session when the overlay disappears.
            // Use a short delay to avoid killing the session when the camera
            // fullScreenCover appears (which triggers onDisappear transiently).
            if talkStore.isSessionActive {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    // Re-check — if the overlay was re-presented (camera dismiss),
                    // the session is still wanted. Only end if truly gone.
                    if !showLiveCameraOverlay {
                        await talkStore.endSession()
                    }
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
        let sessionTag = talkStore.voiceEngine == .native ? "LOCAL VOICE" : "VOICE SESSION"
        if talkStore.isSessionActive {
            return "\(sessionTag) · \(formattedDuration)"
        }
        return talkStore.voiceEngine == .native ? "LOCAL VOICE · STARTING" : "VOICE LINK · CONNECTING"
    }

    private var formattedDuration: String {
        let minutes = Int(talkStore.sessionDuration) / 60
        let seconds = Int(talkStore.sessionDuration) % 60
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

                // Show "Open Settings" for permission-related blocks
                if let reason = talkStore.blockedReason,
                   reason.localizedCaseInsensitiveContains("microphone") || reason.localizedCaseInsensitiveContains("permission") {
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
            }

        case (.checking, _), (.idle, _), (.connecting, _), (.ready, _):
            HStack(spacing: Design.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Design.Brand.accent)
                MonoLabel("ESTABLISHING LINK", weight: .medium, tracking: Design.Tracking.monoWide, color: Design.Brand.accent)
            }

        case (.connected, .listening):
            statusPipLabel("LISTENING", color: Design.Brand.accent, blinks: true)

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
