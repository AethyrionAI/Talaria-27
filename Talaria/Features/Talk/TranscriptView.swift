import SwiftUI

struct TranscriptView: View {
    let transcriptItems: [TranscriptItem]
    let voiceState: VoiceState

    var body: some View {
        VStack(spacing: Design.Spacing.xs) {
            if !transcriptItems.isEmpty {
                VStack(spacing: Design.Spacing.sm) {
                    ForEach(Array(transcriptItems.suffix(4))) { item in
                        VStack(spacing: Design.Spacing.xxxs) {
                            Text(item.speaker.displayLabel.uppercased())
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.5))
                            Text(item.text)
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.foreground)
                                .multilineTextAlignment(.center)
                                .opacity(item.isPartial ? 0.72 : 1)
                        }
                        .padding(.horizontal, Design.Spacing.lg)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Text(voiceState.displayLabel)
                .font(Design.Typography.caption)
                .foregroundStyle(voiceState.displayColor)
                .animation(Design.Motion.quickResponse, value: voiceState)
        }
        .padding(.horizontal, Design.Spacing.md)
    }
}
