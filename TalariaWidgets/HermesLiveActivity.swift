import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct HermesBrandIcon: View {
    let size: CGFloat
    var fallbackSymbol: String = "brain.head.profile"
    var fallbackTint: Color = .yellow
    var backgroundTint: Color? = nil
    var cornerRadius: CGFloat? = nil

    var body: some View {
        if let uiImage = Self.loadImage() {
            Image(uiImage: uiImage)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.22))
                .ifLet(backgroundTint) { view, tint in
                    view.background(tint, in: RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.22))
                }
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.7, weight: .medium))
                .foregroundStyle(fallbackTint)
                .frame(width: size, height: size)
                .ifLet(backgroundTint) { view, tint in
                    view.background(tint, in: Circle())
                }
        }
    }

    private static func loadImage() -> UIImage? {
        if let image = UIImage(named: "AppIcon60x60", in: Bundle.main, compatibleWith: nil) {
            return image
        }

        let containerAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if let appBundle = Bundle(url: containerAppURL),
           let image = UIImage(named: "AppIcon60x60", in: appBundle, compatibleWith: nil) {
            return image
        }

        return nil
    }
}

extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

struct HermesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HermesActivityAttributes.self) { context in
            // Lock Screen layout
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (long press on Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    HermesBrandIcon(size: 28)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.agentName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(context.state.status)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let tool = context.state.toolName {
                        Text(tool)
                            .font(.caption2)
                            .foregroundStyle(.yellow.opacity(0.7))
                    }
                }
            } compactLeading: {
                // Compact left side of Dynamic Island
                HermesBrandIcon(size: 14)
            } compactTrailing: {
                // Compact right side
                Text(context.state.status.prefix(12))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            } minimal: {
                // Minimal (when multiple Live Activities compete)
                HermesBrandIcon(size: 16)
            }
        }
        .supplementalActivityFamilies([.small])
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<HermesActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            HermesBrandIcon(
                size: 44,
                backgroundTint: Color.yellow.opacity(0.15),
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.agentName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(context.state.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let tool = context.state.toolName {
                    Text(tool)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            // Use the native timer when a start date is available —
            // this ticks in real-time without needing Live Activity updates.
            if let start = context.state.startDate {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else if context.state.elapsedSeconds > 0 {
                Text(formatDuration(context.state.elapsedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// Previews are in Talaria/Features/Talk/LiveActivityPreviews.swift
// (Widget extension targets cannot host previews.)
