import SwiftUI

struct TalkModeScreen: View {
    @Environment(TalkStore.self) private var talkStore
    @Environment(AppSessionStore.self) private var sessionStore

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: Design.Spacing.xl) {
                Spacer()

                VoiceOrb(voiceState: talkStore.voiceState)

                TranscriptView(
                    transcript: talkStore.transcript,
                    voiceState: talkStore.voiceState
                )

                sessionTimer

                Spacer()

                controlBar
            }
            .padding(.bottom, Design.Spacing.xxl)
        }
        .navigationTitle("Talk Mode")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mockIndicator
            }
        }
    }

    // MARK: - Session Timer

    private var sessionTimer: some View {
        Group {
            if talkStore.isSessionActive {
                Text(formattedDuration)
                    .font(Design.Typography.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(Design.Motion.standard, value: talkStore.isSessionActive)
    }

    private var formattedDuration: String {
        let minutes = Int(talkStore.sessionDuration) / 60
        let seconds = Int(talkStore.sessionDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Controls

    private var controlBar: some View {
        GlassEffectContainer(spacing: Design.Spacing.lg) {
            HStack(spacing: Design.Spacing.lg) {
                if talkStore.isSessionActive {
                    // Mute button
                    Button {
                        Task { await talkStore.toggleMute() }
                    } label: {
                        Image(systemName: talkStore.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: Design.Size.iconLarge))
                            .foregroundStyle(talkStore.isMuted ? .red : .primary)
                            .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                    }
                    .clipShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel(talkStore.isMuted ? "Unmute" : "Mute")

                    // End session button
                    Button {
                        endSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: Design.Size.iconLarge, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Design.Size.iconHero, height: Design.Size.iconHero)
                            .background(.red, in: Circle())
                    }
                    .accessibilityLabel("End session")
                } else {
                    // Start session button
                    Button {
                        startSession()
                    } label: {
                        Label("Start Talking", systemImage: "mic.fill")
                            .font(Design.Typography.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Design.Spacing.lg)
                            .padding(.vertical, Design.Spacing.sm)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Start voice session")
                }
            }
        }
        .animation(Design.Motion.expressive, value: talkStore.isSessionActive)
    }

    // MARK: - Mock Indicator

    private var mockIndicator: some View {
        Text(sessionStore.state.isMockMode ? "MOCK" : "LIVE")
            .font(Design.Typography.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Design.Spacing.xs)
            .padding(.vertical, Design.Spacing.xxxs)
            .glassEffect(.regular, in: Capsule())
    }

    // MARK: - Actions

    private func startSession() {
        Task { await talkStore.startSession() }
    }

    private func endSession() {
        Task { await talkStore.endSession() }
    }
}
