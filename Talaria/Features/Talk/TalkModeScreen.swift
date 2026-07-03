import SwiftUI

struct TalkModeScreen: View {
    @Environment(TalkStore.self) private var talkStore
    @Environment(AppSessionStore.self) private var sessionStore

    private var isSpeaking: Bool { talkStore.voiceState == .speaking }
    private var isLive: Bool {
        switch talkStore.voiceState {
        case .listening, .thinking, .speaking: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            CornerBrackets(arm: Design.Size.bracket, lineWidth: 1.5, inset: Design.Spacing.md)
                .ignoresSafeArea()

            VStack(spacing: Design.Spacing.lg) {
                header

                Spacer()

                VoiceOrb(voiceState: talkStore.voiceState, connectionState: talkStore.connectionState)
                    .onTapGesture {
                        if talkStore.voiceState == .speaking {
                            talkStore.interruptAssistant()
                        }
                    }
                    .accessibilityAction(named: "Stop speaking") {
                        talkStore.interruptAssistant()
                    }

                statusLine

                VoiceWaveform(isActive: isLive)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Design.Spacing.xl)

                TranscriptView(
                    transcriptItems: talkStore.transcriptItems,
                    voiceState: talkStore.voiceState
                )

                if let statusMessage = talkStore.statusMessage {
                    MonoLabel(statusMessage, tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Design.Spacing.lg)
                }

                if let blockedReason = talkStore.blockedReason, !talkStore.isSessionActive {
                    Text(blockedReason)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Brand.forge)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Design.Spacing.lg)
                }

                Spacer()

                controlBar
            }
            .padding(.top, Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xxl)
        }
        .navigationTitle("Talk Mode")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await talkStore.refreshReadiness()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mockIndicator
            }
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
        }
        .frame(maxWidth: .infinity)
        .animation(Design.Motion.standard, value: talkStore.isSessionActive)
    }

    /// Mono header line — shows the live session duration when active.
    private var sessionHeaderLabel: String {
        if talkStore.isSessionActive {
            return "VOICE SESSION · \(formattedDuration)"
        }
        return "VOICE SESSION · STANDBY"
    }

    private var formattedDuration: String {
        let minutes = Int(talkStore.sessionDuration) / 60
        let seconds = Int(talkStore.sessionDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Status line

    private var statusLine: some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: statusColor, diameter: 7, blinks: isLive)
            MonoLabel(
                statusText,
                size: 11,
                weight: .medium,
                tracking: Design.Tracking.monoWide,
                color: statusColor
            )
        }
        .animation(Design.Motion.quickResponse, value: talkStore.voiceState)
    }

    private var statusText: String {
        switch talkStore.voiceState {
        case .speaking: "SPEAKING"
        case .listening: "LISTENING"
        case .thinking: "PROCESSING"
        case .interrupted: "INTERRUPTED"
        case .disconnected: "OFFLINE"
        case .idle: "STANDBY"
        }
    }

    private var statusColor: Color {
        switch talkStore.voiceState {
        case .speaking, .listening, .thinking: Design.Brand.accent
        case .interrupted: Design.Brand.forge
        case .disconnected: Design.Colors.danger
        case .idle: Design.Colors.mutedForeground
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: Design.Spacing.xl) {
            if talkStore.isSessionActive {
                // Left secondary — mute (neutral chip)
                secondaryButton(
                    systemName: talkStore.isMuted ? "mic.slash.fill" : "mic.fill",
                    accessibility: talkStore.isMuted ? "Unmute" : "Mute",
                    tint: talkStore.isMuted ? Design.Colors.danger : Design.Colors.foreground,
                    accent: false
                ) {
                    Task { await talkStore.toggleMute() }
                }

                // Centre — end / hang-up (danger, glowing)
                endButton

                // Right secondary — interrupt / pause (cyan)
                secondaryButton(
                    systemName: isSpeaking ? "pause.fill" : "waveform",
                    accessibility: isSpeaking ? "Stop speaking" : "Listening",
                    tint: Design.Brand.accent,
                    accent: true
                ) {
                    if isSpeaking { talkStore.interruptAssistant() }
                }
                .disabled(!isSpeaking)
                .opacity(isSpeaking ? 1 : 0.45)
            } else {
                // Start session button
                Button {
                    startSession()
                } label: {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("START TALKING")
                            .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                            .tracking(Design.Tracking.button)
                    }
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Design.Colors.accentTint(0.22), Design.Colors.accentTint(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                            .strokeBorder(Design.Colors.accentTint(0.6), lineWidth: 1)
                    }
                    .hudGlow(Design.Brand.accent, radius: 24, strength: 0.35)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Design.Spacing.xl)
                .accessibilityLabel("Start voice session")
                .disabled(!talkStore.canStartSession)
                .opacity(talkStore.canStartSession ? 1 : 0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Design.Motion.expressive, value: talkStore.isSessionActive)
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
                .font(.system(size: Design.Size.iconMedium, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Design.Size.minTapTarget + 12, height: Design.Size.minTapTarget + 12)
                .background(
                    accent ? Design.Colors.accentTint(0.1) : Design.Colors.chipSurface,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            accent ? Design.Colors.strongBorder : Design.Colors.chipBorder,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var endButton: some View {
        Button {
            endSession()
        } label: {
            Image(systemName: "phone.down.fill")
                .font(.system(size: Design.Size.iconLarge, weight: .semibold))
                .foregroundStyle(Design.Colors.dangerBright)
                .frame(width: Design.Size.iconHero + 8, height: Design.Size.iconHero + 8)
                .background(Design.Colors.danger.opacity(0.22), in: Circle())
                .overlay {
                    Circle().strokeBorder(Design.Colors.danger.opacity(0.7), lineWidth: 1.5)
                }
                .hudGlow(Design.Colors.danger, radius: 22, strength: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End session")
    }

    // MARK: - Mock Indicator

    private var mockIndicator: some View {
        let live = !sessionStore.state.isMockMode
        return HStack(spacing: Design.Spacing.xxs) {
            StatusPip(color: live ? Design.Brand.accent : Design.Brand.forge, diameter: 5, blinks: false)
            MonoLabel(
                live ? "LIVE" : "MOCK",
                tracking: Design.Tracking.mono,
                color: live ? Design.Brand.accent : Design.Brand.forge
            )
        }
        .padding(.horizontal, Design.Spacing.xs)
        .padding(.vertical, Design.Spacing.xxs)
        .overlay {
            Capsule().strokeBorder(Design.Colors.hairline, lineWidth: 1)
        }
    }

    // MARK: - Actions

    private func startSession() {
        Task { await talkStore.startSession() }
    }

    private func endSession() {
        Task { await talkStore.endSession() }
    }
}
