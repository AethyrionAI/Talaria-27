import SwiftUI

/// A compact, live-rotating view showing what tools Hermes is using in real time.
///
/// **Streaming**: shows a "TOOL ACTIVITY" HUD panel with a per-step timeline.
/// **Finished**: shows a collapsed chip naming the call(s) that expands to the
/// full timeline — tool name, key inputs, completion status — on tap (#11).
struct ToolActivityRail: View {
    let activities: [ToolActivity]
    let isStreaming: Bool

    @State private var isExpanded = false

    private var latestActivity: ToolActivity? {
        activities.last(where: { $0.isActive }) ?? activities.last
    }

    var body: some View {
        if !activities.isEmpty {
            if isStreaming {
                liveIndicator
            } else {
                finishedSummary
            }
        }
    }

    // MARK: - Live Streaming Panel

    private var liveIndicator: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                MonoLabel("Tool Activity", size: 10, tracking: Design.Tracking.monoWide)
                Spacer()
                MonoLabel(
                    "\(activities.count) Step\(activities.count == 1 ? "" : "s")",
                    size: 10,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Brand.accent
                )
            }
            .padding(.horizontal, Design.Spacing.sm + 1)
            .padding(.vertical, Design.Spacing.xs + 1)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Design.Colors.accentTint(0.12))
                    .frame(height: 1)
            }

            // Step rows
            VStack(alignment: .leading, spacing: Design.Spacing.sm - 1) {
                ForEach(activities) { activity in
                    activityRow(activity, running: activity.isActive)
                }
            }
            .padding(.horizontal, Design.Spacing.sm + 1)
            .padding(.vertical, Design.Spacing.sm - 1)
        }
        .hudPanel(
            cornerRadius: Design.CornerRadius.sm + 4,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
    }

    // MARK: - Finished Summary (expandable)

    /// Collapsed label: the tool's name when there's a single call, a count
    /// otherwise — never just "a tool ran" (#11).
    private var collapsedLabel: String {
        if activities.count == 1, let only = activities.first {
            return only.label
        }
        return "\(activities.count) Tool Calls"
    }

    private var finishedSummary: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Button {
                withAnimation(Design.Motion.quickResponse) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Design.Brand.accent)

                    MonoLabel(
                        collapsedLabel,
                        size: 10,
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.secondaryForeground
                    )

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
                .padding(.horizontal, Design.Spacing.sm)
                .padding(.vertical, Design.Spacing.xxs + 2)
                .hudPanel(
                    cornerRadius: Design.CornerRadius.full,
                    borderColor: Design.Colors.hairline,
                    fill: Design.Colors.surface
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedTimeline
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Design.Motion.quickResponse, value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tools: \(activities.map(\.label).joined(separator: ", "))")
    }

    // MARK: - Expanded Timeline

    private var expandedTimeline: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm - 2) {
            ForEach(activities) { activity in
                activityRow(activity, running: false)
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs + 1)
        .hudPanel(
            cornerRadius: Design.CornerRadius.sm + 4,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
    }

    // MARK: - Shared step row

    private func activityRow(_ activity: ToolActivity, running: Bool) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs + 2) {
            if running {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Brand.forge)
                    .hudPulse(Design.Motion.blink, from: 1, to: 0.35)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: 11, height: 11)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.label)
                    .font(Design.Typography.mono(12))
                    .foregroundStyle(Design.Colors.coolForeground)
                    .lineLimit(1)

                // Key inputs from the tool.started payload (#11); truncated —
                // long values are already elided at parse time.
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(Design.Typography.monoSmall)
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Design.Spacing.xs)

            if running {
                Text("running")
                    .font(Design.Typography.monoSmall)
                    .foregroundStyle(Design.Brand.accent)
            } else {
                Text(activity.startedAt, style: .time)
                    .font(Design.Typography.monoSmall)
                    .foregroundStyle(Design.Colors.dimForeground)
            }
        }
    }
}
