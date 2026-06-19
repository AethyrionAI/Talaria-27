import SwiftUI
import UIKit

/// Full-screen voice overlay, inspired by ChatGPT's voice mode.
/// Auto-starts a voice session on appear and tears it down on dismiss.
struct VoiceOverlayScreen: View {
    @Environment(TalkStore.self) private var talkStore
    @Environment(TabRouter.self) private var router

    @State private var showLiveCameraOverlay = false

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("Hermes")
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.foreground)
                    Text("Voice")
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                    Spacer()
                }
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

    // MARK: - Transcript

    private var transcriptSection: some View {
        ScrollView {
            LazyVStack(spacing: Design.Spacing.sm) {
                ForEach(talkStore.transcriptItems) { item in
                    transcriptBubble(item)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
        }
        .scrollDismissesKeyboard(.never)
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: 320)
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
                } else if !item.text.isEmpty {
                    Text(item.text)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.foreground)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.sm)
                        .background(Design.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
                        .opacity(item.isPartial ? 0.6 : 1)
                }
            }
        case .hermes:
            HStack {
                Text(item.text)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.foreground)
                    .opacity(item.isPartial ? 0.6 : 1)
                Spacer()
            }
        case .system:
            Text(item.text)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .frame(maxWidth: .infinity)
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
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .multilineTextAlignment(.center)

                // Show "Open Settings" for permission-related blocks
                if let reason = talkStore.blockedReason,
                   reason.localizedCaseInsensitiveContains("microphone") || reason.localizedCaseInsensitiveContains("permission") {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(Design.Typography.callout.weight(.medium))
                            .padding(.horizontal, Design.Spacing.lg)
                            .padding(.vertical, Design.Spacing.xs)
                            .background(Design.Colors.surface)
                            .clipShape(Capsule())
                    }
                }
            }

        case (.checking, _), (.idle, _), (.connecting, _), (.ready, _):
            HStack(spacing: Design.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Design.Colors.secondaryForeground)
                Text("Connecting\u{2026}")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

        case (.connected, .listening):
            Text("Listening")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)

        case (.connected, .thinking):
            Text(talkStore.statusMessage ?? "")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)

        case (.connected, .speaking):
            EmptyView()

        case (_, .disconnected):
            Text("Disconnected")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)

        default:
            EmptyView()
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: Design.Spacing.xl) {
            if talkStore.isSessionActive {
                // Live camera button
                Button { showLiveCameraOverlay = true } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Design.Colors.foreground)
                        .frame(width: 52, height: 52)
                        .background(Design.Colors.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Open live camera")

                // Mute button
                Button {
                    Task { await talkStore.toggleMute() }
                } label: {
                    Image(systemName: talkStore.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(talkStore.isMuted ? .red : Design.Colors.foreground)
                        .frame(width: 52, height: 52)
                        .background(Design.Colors.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel(talkStore.isMuted ? "Unmute" : "Mute")

                Spacer()

                // Close button
                Button {
                    Task {
                        await talkStore.endSession()
                        router.isVoiceOverlayPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Design.Colors.foreground)
                        .frame(width: 52, height: 52)
                        .background(Design.Colors.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("End voice session")
            } else {
                Spacer()

                // Close button when not active (e.g. failed to start)
                Button {
                    router.isVoiceOverlayPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Design.Colors.foreground)
                        .frame(width: 52, height: 52)
                        .background(Design.Colors.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, Design.Spacing.xl)
    }
}
