import SwiftUI

/// Record → transcribe → review → attach flow for voice-memo attachments (#9).
///
/// The memo is transcribed fully on-device (`VoiceMemoTranscriber`) and staged
/// as a TEXT attachment through the #8 inlining branch — the audio never
/// transmits, so the review step shows the actual transcript (what will ship)
/// with local playback of the actual recording ("real data only"). Everything
/// here — record, transcribe, stage, play back — works with no network.
struct VoiceMemoRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TalkStore.self) private var talkStore
    @Environment(SpeechOutputService.self) private var speechOutput

    /// Delivered with the staged attachment when the user taps Attach.
    let onComplete: (PendingAttachment) -> Void

    @State private var recorder = VoiceMemoRecorder()
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?
    /// Set when the recording was handed off as an attachment — the audio file
    /// now belongs to the staged PendingAttachment and must survive dismissal.
    @State private var didAttach = false

    private let player = VoiceMemoPlayer.shared

    private enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        /// Transcription done — reviewing before attach.
        case review(transcript: String, audioPath: String, duration: TimeInterval, recordedAt: Date)
        /// Transcription failed — the memo has no wire shape (audio can't be
        /// sent, #43), so the only honest options are retry or discard.
        case transcriptionFailed(audioPath: String, duration: TimeInterval, recordedAt: Date, reason: String)
    }

    var body: some View {
        VStack(spacing: Design.Spacing.md) {
            Capsule()
                .fill(Design.Colors.accentTint(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, Design.Spacing.sm)

            MonoLabel(
                "Voice Memo",
                size: 12,
                weight: .medium,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.coolForeground
            )

            if talkStore.isSessionActive {
                // The Talk session owns the .playAndRecord audio session
                // (WebRTC) — recording would fight it. Honest refusal.
                talkSessionNotice
            } else {
                content
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Design.Typography.mono(11, relativeTo: .caption))
                    .foregroundStyle(Design.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.Spacing.md)
            }

            Spacer(minLength: Design.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Design.Colors.background)
        .onDisappear {
            // Swiping the sheet away mid-flow must not leak a live recorder,
            // a playing preview, or an orphaned un-attached recording; only an
            // attached memo's audio survives (it belongs to the attachment).
            player.stop()
            if !didAttach {
                recorder.discard()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .recording:
            recordingControls
        case .transcribing:
            VStack(spacing: Design.Spacing.sm) {
                ProgressView()
                    .tint(Design.Brand.accent)
                MonoLabel(
                    "Transcribing on-device…",
                    size: 10,
                    tracking: Design.Tracking.mono,
                    color: Design.Colors.mutedForeground
                )
            }
            .padding(.vertical, Design.Spacing.lg)
        case .review(let transcript, let audioPath, let duration, let recordedAt):
            reviewView(transcript: transcript, audioPath: audioPath, duration: duration, recordedAt: recordedAt)
        case .transcriptionFailed(let audioPath, let duration, let recordedAt, let reason):
            failureView(audioPath: audioPath, duration: duration, recordedAt: recordedAt, reason: reason)
        }
    }

    // MARK: - Recording

    private var recordingControls: some View {
        VStack(spacing: Design.Spacing.md) {
            // Elapsed readout + live level bar — both from the real recorder.
            MonoLabel(
                PendingAttachment.voiceMemoDuration(recorder.elapsed),
                size: 22,
                weight: .medium,
                tracking: Design.Tracking.mono,
                color: recorder.isRecording ? Design.Colors.foregroundBright : Design.Colors.mutedForeground
            )

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Design.Colors.accentTint(0.15))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Design.Brand.accent)
                            .frame(width: proxy.size.width * recorder.level)
                            .animation(.linear(duration: 0.1), value: recorder.level)
                    }
            }
            .frame(height: 4)
            .padding(.horizontal, Design.Spacing.xl)
            .opacity(recorder.isRecording ? 1 : 0.35)

            Button {
                if recorder.isRecording {
                    finishRecording()
                } else {
                    beginRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Design.Colors.surface)
                        .frame(width: 72, height: 72)
                        .overlay {
                            Circle().strokeBorder(
                                recorder.isRecording ? Design.Colors.danger : Design.Colors.strongBorder,
                                lineWidth: 1.5
                            )
                        }
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(recorder.isRecording ? Design.Colors.danger : Design.Brand.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")

            MonoLabel(
                recorder.isRecording ? "RECORDING — TAP TO STOP" : "TAP TO RECORD",
                size: 9,
                tracking: Design.Tracking.mono,
                color: recorder.isRecording ? Design.Colors.danger : Design.Colors.mutedForeground
            )
        }
        .padding(.vertical, Design.Spacing.sm)
    }

    private func beginRecording() {
        errorMessage = nil
        // Read-aloud would bleed (ducked) into the mic — cut it, same as a
        // Talk session start does (#2 wiring in AppContainer).
        speechOutput.stop()
        Task {
            do {
                try await recorder.startRecording()
                phase = .recording
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finishRecording() {
        guard let recording = recorder.stopRecording() else { return }
        // Provenance header carries when the memo STARTED, not when it stopped.
        let recordedAt = Date().addingTimeInterval(-recording.duration)
        phase = .transcribing
        Task {
            do {
                let transcript = try await VoiceMemoTranscriber.transcribe(url: recording.url)
                phase = .review(
                    transcript: transcript,
                    audioPath: recording.url.path,
                    duration: recording.duration,
                    recordedAt: recordedAt
                )
            } catch {
                phase = .transcriptionFailed(
                    audioPath: recording.url.path,
                    duration: recording.duration,
                    recordedAt: recordedAt,
                    reason: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Review

    private func reviewView(transcript: String, audioPath: String, duration: TimeInterval, recordedAt: Date) -> some View {
        VStack(spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.sm) {
                Button {
                    player.togglePlayback(path: audioPath)
                } label: {
                    Image(systemName: player.isPlaying(path: audioPath) ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Design.Brand.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying(path: audioPath) ? "Stop playback" : "Play recording")

                MonoLabel(
                    PendingAttachment.voiceMemoDuration(duration).uppercased(),
                    size: 11,
                    tracking: Design.Tracking.mono,
                    color: Design.Colors.coolForeground
                )
                Spacer()
                // What ships is the transcript, not the audio — say so.
                MonoLabel(
                    "SENDS AS TEXT",
                    size: 9,
                    tracking: Design.Tracking.mono,
                    color: Design.Colors.mutedForeground
                )
            }
            .padding(.horizontal, Design.Spacing.md)

            ScrollView {
                Text(transcript)
                    .font(Design.Typography.mono(12, relativeTo: .caption))
                    .foregroundStyle(Design.Colors.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.sm)
            }
            .frame(maxHeight: 140)
            .hudPanel(
                cornerRadius: Design.CornerRadius.md,
                borderColor: Design.Colors.hairline,
                fill: Design.Colors.surface
            )
            .padding(.horizontal, Design.Spacing.md)

            HStack(spacing: Design.Spacing.sm) {
                GhostButton(title: "Discard", systemImage: "trash", height: 44) {
                    player.stop()
                    recorder.discard()
                    phase = .idle
                }
                GlowButton(title: "Attach", systemImage: "paperclip", height: 44) {
                    player.stop()
                    didAttach = true
                    onComplete(
                        PendingAttachment.voiceMemo(
                            transcript: transcript,
                            audioFileURL: URL(fileURLWithPath: audioPath),
                            duration: duration,
                            recordedAt: recordedAt
                        )
                    )
                    dismiss()
                }
            }
            .padding(.horizontal, Design.Spacing.md)
        }
    }

    // MARK: - Failure

    private func failureView(audioPath: String, duration: TimeInterval, recordedAt: Date, reason: String) -> some View {
        VStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Design.Size.iconLarge))
                .foregroundStyle(Design.Brand.forge)
            // Audio has no wire shape on the Sessions API (#43), so an
            // untranscribed memo cannot be sent — the real reason, then retry
            // (playback proves the audio survived) or discard.
            Text(reason)
                .font(Design.Typography.mono(11, relativeTo: .caption))
                .foregroundStyle(Design.Colors.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.md)
            MonoLabel(
                "AUDIO CAN'T BE SENT WITHOUT A TRANSCRIPT",
                size: 9,
                tracking: Design.Tracking.mono,
                color: Design.Colors.mutedForeground
            )

            HStack(spacing: Design.Spacing.sm) {
                Button {
                    player.togglePlayback(path: audioPath)
                } label: {
                    Image(systemName: player.isPlaying(path: audioPath) ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Design.Brand.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying(path: audioPath) ? "Stop playback" : "Play recording")

                GhostButton(title: "Discard", systemImage: "trash", height: 44) {
                    player.stop()
                    recorder.discard()
                    phase = .idle
                }
                GlowButton(title: "Retry", systemImage: "arrow.clockwise", height: 44) {
                    player.stop()
                    retryTranscription(audioPath: audioPath, duration: duration, recordedAt: recordedAt)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
        }
    }

    private func retryTranscription(audioPath: String, duration: TimeInterval, recordedAt: Date) {
        phase = .transcribing
        Task {
            do {
                let transcript = try await VoiceMemoTranscriber.transcribe(url: URL(fileURLWithPath: audioPath))
                phase = .review(transcript: transcript, audioPath: audioPath, duration: duration, recordedAt: recordedAt)
            } catch {
                phase = .transcriptionFailed(audioPath: audioPath, duration: duration, recordedAt: recordedAt, reason: error.localizedDescription)
            }
        }
    }

    private var talkSessionNotice: some View {
        VStack(spacing: Design.Spacing.sm) {
            Image(systemName: "waveform.slash")
                .font(.system(size: Design.Size.iconLarge))
                .foregroundStyle(Design.Brand.forge)
            MonoLabel(
                "VOICE SESSION ACTIVE — END IT TO RECORD A MEMO",
                size: 9,
                tracking: Design.Tracking.mono,
                color: Design.Brand.forge
            )
        }
        .padding(.vertical, Design.Spacing.lg)
    }
}
