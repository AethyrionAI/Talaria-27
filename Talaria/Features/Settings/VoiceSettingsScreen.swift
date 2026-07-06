import SwiftUI

// MARK: - Voice settings screen (Settings → VOICE, sub-screen 05)
//
// Status & launch panel for the realtime Talk engine, real-data-only (#35):
//   • STATUS reflects the live relay talk/readiness probe (host online /
//     configured / ready + blockedReason) — "—" wherever the probe hasn't
//     answered.
//   • Model + voice are server-managed and READ-ONLY on iOS (the service
//     protocol has no set-voice); shown for information, never as controls.
//   • Latency shows the last session's real TalkLatencyMetrics.
//   • START VOICE SESSION reuses the existing launch path
//     (router.isVoiceOverlayPresented), gated on canStartSession. The overlay
//     is a fullScreenCover on MainTabView — the same view presenting the
//     Settings sheet — so the sheet must finish dismissing before the cover
//     can present.
struct VoiceSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(TalkStore.self) private var talkStore
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Voice", subtitle: "Talk Engine") { dismiss() }
                    heroPanel
                    statusSection
                    modelSection
                    latencySection
                    transcriptSyncSection
                    startSection
                    footer
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Voice")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await talkStore.refreshReadiness() }
    }

    // MARK: Hero

    private var heroPanel: some View {
        HStack(spacing: Design.Spacing.md) {
            ReactorOrb(size: Design.Size.orbPanel, style: .voice)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("TALK ENGINE")
                    .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                MonoLabel("REALTIME · SPEECH-TO-SPEECH", size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                MonoLabel(engineState.text, size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: engineState.color)
            }
            Spacer(minLength: Design.Spacing.xs)
            StatusPip(color: engineState.color, diameter: 9, blinks: engineState.blinks)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.xl,
            borderColor: engineState.color.opacity(0.28),
            fill: Design.Colors.accentTint(0.07),
            innerGlow: true
        )
    }

    private var engineState: (text: String, color: Color, blinks: Bool) {
        switch talkStore.connectionState {
        case .idle:       ("STANDBY", Design.Colors.mutedForeground, false)
        case .checking:   ("CHECKING", Design.Brand.forge, true)
        case .ready:      ("READY", Design.Brand.accent, false)
        case .connecting: ("CONNECTING", Design.Brand.forge, true)
        case .connected:  ("SESSION LIVE", Design.Brand.accent, false)
        case .blocked:    ("BLOCKED", Design.Brand.forge, false)
        case .failed:     ("ERROR", Design.Colors.danger, false)
        }
    }

    // MARK: Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Status")
            VStack(spacing: 0) {
                statusRow("Host", boolStatus(readiness.hostOnline, yes: "ONLINE", no: "OFFLINE",
                                             noColor: Design.Colors.danger))
                rowDivider
                statusRow("Configured", boolStatus(readiness.configured, yes: "CONFIGURED", no: "NOT CONFIGURED",
                                                   noColor: Design.Brand.forge))
                rowDivider
                statusRow("Ready", boolStatus(readiness.ready, yes: "READY", no: "BLOCKED",
                                              noColor: Design.Brand.forge))
            }
            .groupPanel()

            if let reason = talkStore.blockedReason, !reason.isEmpty {
                Text(reason)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    private func boolStatus(_ value: Bool?, yes: String, no: String,
                            noColor: Color) -> (text: String, color: Color) {
        guard let value else { return ("—", Design.Colors.mutedForeground) }
        return value ? (yes, Design.Brand.accent) : (no, noColor)
    }

    // MARK: Model & voice (server-managed, read-only)

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Model & Voice")
            VStack(spacing: 0) {
                statusRow("Model", (readiness.selectedModel?.uppercased() ?? "—", valueColor(readiness.selectedModel)))
                rowDivider
                statusRow("Voice", (readiness.voice?.uppercased() ?? "—", valueColor(readiness.voice)))
                rowDivider
                statusRow("Voice Context", (voiceContextValue, valueColor(voiceContextValue == "—" ? nil : voiceContextValue)))
            }
            .groupPanel()

            Text("Model and voice are managed on the Hermes host. This surface is read-only.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    private var voiceContextValue: String {
        guard let updatedAt = readiness.voiceContextUpdatedAt else { return "—" }
        return updatedAt.formatted(.relative(presentation: .named)).uppercased()
    }

    private func valueColor(_ value: String?) -> Color {
        value == nil ? Design.Colors.mutedForeground : Design.Colors.foreground
    }

    // MARK: Latency (last session)

    private var latencySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Last Session")
            VStack(spacing: 0) {
                statusRow("Bootstrap", latencyValue(talkStore.latencyMetrics.bootstrapLatency))
                rowDivider
                statusRow("Connect", latencyValue(talkStore.latencyMetrics.connectLatency))
                rowDivider
                statusRow("First Reply", latencyValue(talkStore.latencyMetrics.firstAssistantLatency))
            }
            .groupPanel()
        }
    }

    private func latencyValue(_ interval: TimeInterval?) -> (text: String, color: Color) {
        guard let interval else { return ("—", Design.Colors.mutedForeground) }
        if interval < 1 {
            return ("\(Int(interval * 1000)) MS", Design.Colors.foreground)
        }
        return (String(format: "%.2f S", interval), Design.Colors.foreground)
    }

    // MARK: Transcript Sync

    private var transcriptSyncSection: some View {
        @Bindable var settingsStore = settingsStore
        return VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Transcript")
            VStack(spacing: 0) {
                HStack(spacing: Design.Spacing.sm) {
                    Text("Sync to Agent")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer()
                    Toggle("", isOn: $settingsStore.settings.voiceTranscriptSyncEnabled)
                        .labelsHidden()
                        .tint(Design.Brand.accent)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
            .groupPanel()

            Text("When enabled, the voice transcript is sent to the agent after each session so it has context for the next exchange. Disable to keep voice sessions local-only.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    // MARK: Start

    private var startSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            GlowButton(title: "Start Voice Session", systemImage: "waveform") {
                startVoiceSession()
            }
            .disabled(!talkStore.canStartSession)
            .opacity(talkStore.canStartSession ? 1 : 0.45)

            if !talkStore.canStartSession {
                Text("Voice is unavailable until the Talk engine reports ready.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    private func startVoiceSession() {
        guard talkStore.canStartSession else { return }
        // Dismiss the Settings sheet, then present the voice overlay — both
        // are presentations of MainTabView, so they can't overlap.
        container.router.activeSheet = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            container.router.isVoiceOverlayPresented = true
        }
    }

    // MARK: Footer

    private var footer: some View {
        MonoLabel("TALK ENGINE · RELAY-BOOTSTRAPPED · WEBRTC", size: 9, weight: .regular,
                  tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Design.Spacing.xs)
            .padding(.bottom, Design.Spacing.md)
    }

    // MARK: Shared row builders

    private func statusRow(_ label: String, _ status: (text: String, color: Color)) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            MonoLabel(status.text, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: status.color)
                .lineLimit(1)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private func groupLabel(_ text: String) -> some View {
        MonoLabel(text, size: 10, tracking: Design.Tracking.monoXWide,
                  color: Design.Colors.mutedForeground)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Design.Colors.hairline)
            .frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    private var readiness: TalkReadinessInfo { talkStore.readiness }
}

// MARK: - Group panel modifier

private extension View {
    func groupPanel() -> some View {
        self.hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }
}
