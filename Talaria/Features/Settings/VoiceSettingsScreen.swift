import AVFoundation
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
    @Environment(SpeechOutputService.self) private var speechOutput

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
                    readAloudSection
                    transcriptsSection
                    latencySection
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
                // #18: the engine line is live — local voice is a distinct
                // mode, never presented as the Realtime experience.
                MonoLabel(engineDescriptor, size: 9, weight: .medium,
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

    private var engineDescriptor: String {
        switch talkStore.voiceEngine {
        case .realtime: "REALTIME · SPEECH-TO-SPEECH"
        case .native: "LOCAL · ON-DEVICE PIPELINE"
        }
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
                statusRow("Engine", (talkStore.voiceEngine.monoLabel,
                                     talkStore.voiceEngine == .native ? Design.Brand.forge : Design.Brand.accent))
                rowDivider
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

    // MARK: Read-aloud (#2) — local TTS, the one voice surface iOS controls

    private var readAloudSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Read-Aloud")
            VStack(spacing: 0) {
                toggleRow(
                    "Auto-Read Replies",
                    detail: "SPEAKS AS THE REPLY STREAMS",
                    isOn: Binding(
                        get: { settingsStore.settings.readAloudAutoPlay },
                        set: { settingsStore.settings.readAloudAutoPlay = $0 }
                    )
                )
                rowDivider
                voicePickerRow
                rowDivider
                rateRow
            }
            .groupPanel()

            personalVoiceFooter

            GhostButton(title: "Preview Voice", systemImage: "play.circle") {
                speechOutput.previewVoice()
            }
            .disabled(talkStore.isSessionActive)
            .opacity(talkStore.isSessionActive ? 0.45 : 1)

            Text("Read-aloud uses this device's speech voices — download higher-quality voices in Settings → Accessibility → Spoken Content. Paused automatically while a Talk session is live.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    private var voicePickerRow: some View {
        HStack(spacing: Design.Spacing.sm) {
            Text("Voice")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            Menu {
                Button {
                    settingsStore.settings.readAloudVoiceIdentifier = nil
                } label: {
                    if settingsStore.settings.readAloudVoiceIdentifier == nil {
                        Label("System Default", systemImage: "checkmark")
                    } else {
                        Text("System Default")
                    }
                }
                ForEach(SpeechOutputService.availableVoices(), id: \.identifier) { voice in
                    Button {
                        settingsStore.settings.readAloudVoiceIdentifier = voice.identifier
                    } label: {
                        if settingsStore.settings.readAloudVoiceIdentifier == voice.identifier {
                            Label(voiceMenuLabel(voice), systemImage: "checkmark")
                        } else {
                            Text(voiceMenuLabel(voice))
                        }
                    }
                }
            } label: {
                HStack(spacing: Design.Spacing.xxs) {
                    MonoLabel(selectedVoiceLabel, size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.accent)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private var rateRow: some View {
        HStack(spacing: Design.Spacing.sm) {
            Text("Speed")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            MonoLabel("SLOW", size: 8, weight: .regular,
                      tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            Slider(
                value: Binding(
                    get: { settingsStore.settings.readAloudRate },
                    set: { settingsStore.settings.readAloudRate = $0 }
                ),
                in: 0.3 ... 0.7
            )
            .tint(Design.Brand.accent)
            MonoLabel("FAST", size: 8, weight: .regular,
                      tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    @ViewBuilder
    private var personalVoiceFooter: some View {
        switch speechOutput.personalVoiceAuthorization {
        case .notDetermined:
            GhostButton(title: "Enable Personal Voice", systemImage: "person.wave.2") {
                Task { await speechOutput.requestPersonalVoiceAuthorization() }
            }
        case .authorized:
            Text("Personal Voice enabled — your voices appear in the picker.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        case .denied:
            Text("Personal Voice request denied — allow it in Settings → Accessibility → Personal Voice.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        case .unsupported:
            // Simulators and older hardware — no control to show (real data only).
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }

    private var selectedVoiceLabel: String {
        guard let identifier = settingsStore.settings.readAloudVoiceIdentifier else {
            return "SYSTEM DEFAULT"
        }
        return AVSpeechSynthesisVoice(identifier: identifier)?.name.uppercased() ?? "UNAVAILABLE"
    }

    private func voiceMenuLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        var label = voice.name
        if voice.voiceTraits.contains(.isPersonalVoice) {
            label += " · Personal"
        } else if voice.quality == .premium {
            label += " · Premium"
        } else if voice.quality == .enhanced {
            label += " · Enhanced"
        }
        return label
    }

    // MARK: Transcripts (#1)

    private var transcriptsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Transcripts")
            toggleRow(
                "Send Transcripts to Hermes",
                detail: "SESSIONS API · TEXT TURN",
                isOn: Binding(
                    get: { settingsStore.settings.postVoiceTranscriptsToHermes },
                    set: { settingsStore.settings.postVoiceTranscriptsToHermes = $0 }
                )
            )
            .groupPanel()

            Text("Transcripts always appear in chat and persist on this device. When enabled, they are also posted to the agent so it has voice context for the next exchange. Off keeps voice sessions local-only.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
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
        MonoLabel(
            talkStore.voiceEngine == .native
                ? "TALK ENGINE · ON-DEVICE · SPEECHANALYZER + TTS"
                : "TALK ENGINE · RELAY-BOOTSTRAPPED · WEBRTC",
            size: 9, weight: .regular,
            tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Design.Spacing.xs)
            .padding(.bottom, Design.Spacing.md)
    }

    // MARK: Shared row builders

    private func toggleRow(_ label: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(label)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                if let detail {
                    MonoLabel(detail, size: 8, weight: .regular,
                              tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

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
