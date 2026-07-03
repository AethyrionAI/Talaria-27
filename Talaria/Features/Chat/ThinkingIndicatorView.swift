import SwiftUI

struct ThinkingIndicatorView: View {
    let startTime: Date
    var toolActivity: String? = nil

    @State private var showElapsedTime = false
    @State private var isPulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            ReactorOrb(size: Design.Size.avatarSmall, style: .standard)
                .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                .opacity(isPulsing ? 0.6 : 1.0)

            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                if let activity = toolActivity {
                    toolActivityLabel(activity)
                } else {
                    reasoningLine
                }
                elapsedTimeLabel
            }

            Spacer(minLength: Design.Spacing.xxl)
        }
        .padding(.horizontal, Design.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture { showElapsedTime.toggle() }
        .onAppear {
            withAnimation(Design.Motion.breathe) {
                isPulsing = true
            }
        }
    }

    private func toolActivityLabel(_ label: String) -> some View {
        MonoLabel(
            label,
            size: 10,
            tracking: Design.Tracking.mono,
            color: Design.Colors.secondaryForeground
        )
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xxs + 1)
        .hudPanel(
            cornerRadius: Design.CornerRadius.full,
            borderColor: Design.Colors.hairline,
            fill: Design.Colors.surface
        )
        .transition(.opacity)
        .animation(Design.Motion.quickResponse, value: label)
    }

    private var reasoningLine: some View {
        HStack(spacing: Design.Spacing.xs) {
            reasoningDots
            MonoLabel(
                "Hermes Is Reasoning",
                size: 11,
                tracking: Design.Tracking.mono,
                color: Design.Colors.mutedForeground
            )
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    private var reasoningDots: some View {
        HStack(spacing: Design.Spacing.xxs - 1) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(Design.Brand.accent)
                    .frame(width: 5, height: 5)
                    .opacity(isPulsing ? 0.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isPulsing
                    )
            }
        }
    }

    @ViewBuilder
    private var elapsedTimeLabel: some View {
        if showElapsedTime {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(startTime)
                Text(formatElapsed(elapsed))
                    .font(Design.Typography.monoSmall)
                    .foregroundStyle(Design.Colors.dimForeground)
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
