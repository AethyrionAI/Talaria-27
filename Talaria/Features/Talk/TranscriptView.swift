import SwiftUI

struct TranscriptView: View {
    let transcriptItems: [TranscriptItem]
    let voiceState: VoiceState

    private var isLive: Bool {
        switch voiceState {
        case .listening, .thinking, .speaking: true
        default: false
        }
    }

    private var statusColor: Color {
        switch voiceState {
        case .speaking, .listening, .thinking: Design.Brand.accent
        case .interrupted: Design.Brand.forge
        case .disconnected: Design.Colors.danger
        case .idle: Design.Colors.mutedForeground
        }
    }

    var body: some View {
        VStack(spacing: Design.Spacing.sm) {
            if !transcriptItems.isEmpty {
                HUDPanel(cornerRadius: Design.CornerRadius.lg) {
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        HStack(spacing: Design.Spacing.xs) {
                            MonoLabel("LIVE TRANSCRIPT", tracking: Design.Tracking.monoWide)
                            Spacer(minLength: 0)
                            if isLive {
                                StatusPip(color: Design.Brand.accent, diameter: 6, blinks: true)
                            }
                        }

                        ForEach(Array(transcriptItems.suffix(4).enumerated()), id: \.element.id) { index, item in
                            let isLast = index == transcriptItems.suffix(4).count - 1
                            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                                MonoLabel(
                                    item.speaker.displayLabel,
                                    tracking: Design.Tracking.mono,
                                    color: item.speaker == .hermes
                                        ? Design.Colors.accentTint(0.7)
                                        : Design.Colors.mutedForeground
                                )
                                transcriptLine(item, showCaret: isLast && isLive && item.isPartial)
                            }
                        }
                    }
                    .padding(Design.Spacing.md)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: statusColor, diameter: 6, blinks: isLive)
                MonoLabel(
                    voiceState.displayLabel,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: statusColor
                )
            }
            .animation(Design.Motion.quickResponse, value: voiceState)
        }
        .padding(.horizontal, Design.Spacing.md)
    }

    @ViewBuilder
    private func transcriptLine(_ item: TranscriptItem, showCaret: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(item.text)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.coolForeground)
                .opacity(item.isPartial ? 0.72 : 1)
            if showCaret {
                BlinkingCaret()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Blinking caret

/// A thin cyan caret that blinks at the end of live (partial) transcript text.
struct BlinkingCaret: View {
    var height: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Design.Brand.accent)
            .frame(width: 2, height: height)
            .padding(.leading, Design.Spacing.xxs)
            .hudGlow(Design.Brand.accent, radius: 4, strength: 0.8)
            .hudPulse(Design.Motion.caret, from: 1, to: 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Voice waveform

/// A horizontal row of thin vertical cyan bars with animating heights — the
/// "tal-wave" telemetry motif. Decorative; animates only when `isActive` and
/// Reduce Motion is off. Shared by the talk-mode screens.
struct VoiceWaveform: View {
    var isActive: Bool = true
    var barCount: Int = 21
    var height: CGFloat = 38
    var color: Color = Design.Brand.accent

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    bar(index: i, time: t)
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }

    private func bar(index i: Int, time t: TimeInterval) -> some View {
        // Bell-shaped envelope so the centre bars are tallest.
        let centre = Double(barCount - 1) / 2
        let dist = abs(Double(i) - centre) / centre
        let envelope = 1.0 - dist * 0.65

        let animated: Double
        if isActive && !reduceMotion {
            let wave = sin(t * 6 + Double(i) * 0.6)
            let wave2 = sin(t * 3.3 + Double(i) * 1.1)
            animated = (0.45 + 0.55 * abs(wave * 0.6 + wave2 * 0.4))
        } else {
            animated = 0.22
        }

        let h = max(3, height * CGFloat(animated * envelope))
        let glows = isActive && (i % 4 == 0)

        return RoundedRectangle(cornerRadius: 1.5)
            .fill(color.opacity(0.55 + 0.45 * animated))
            .frame(width: 3, height: h)
            .modifier(OptionalWaveGlow(active: glows, color: color))
    }
}

private struct OptionalWaveGlow: ViewModifier {
    let active: Bool
    let color: Color
    func body(content: Content) -> some View {
        if active { content.hudGlow(color, radius: 6, strength: 0.6) }
        else { content }
    }
}
