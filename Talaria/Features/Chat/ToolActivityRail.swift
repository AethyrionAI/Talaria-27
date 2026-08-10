import SwiftUI

/// A compact, live-rotating view showing what tools Hermes is using in real time.
///
/// **Streaming**: shows a "TOOL ACTIVITY" HUD panel with a per-step timeline.
/// **Finished**: shows a collapsed chip naming the call(s) that expands to the
/// full timeline — tool name, key inputs, and how the call ENDED — on tap (#11).
///
/// **#296 corrects this comment.** It used to say the finished timeline showed
/// "completion status", and it never did: the rail was two-valued
/// (running / not-running) and *everything* not-running drew the same ✓ — a
/// tool the user killed mid-flight included. `StepState` below is the third
/// state that comment was describing before it existed.
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
                    activityRow(activity, state: Self.state(of: activity))
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
                    // #296: the ✓ is no longer unconditional. A chip whose
                    // steps include one the user stopped (or one the host
                    // reported an error for) must not open with the glyph that
                    // means "this finished".
                    Image(systemName: summaryState == .interrupted ? "xmark" : "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(summaryState == .interrupted ? Design.Brand.forge : Design.Brand.accent)

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
        // #296: VoiceOver read the same string for a completed run and a
        // stopped one. The glyph is the only thing that carried the
        // difference, so a non-visual reader got the ✓ version of the lie.
        .accessibilityLabel(
            summaryState == .interrupted
                ? "Tools, stopped before finishing: \(activities.map(\.label).joined(separator: ", "))"
                : "Tools: \(activities.map(\.label).joined(separator: ", "))"
        )
    }

    /// #296: the collapsed chip's state.
    private var summaryState: StepState { Self.summaryState(of: activities) }

    // MARK: - Expanded Timeline

    private var expandedTimeline: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm - 2) {
            ForEach(activities) { activity in
                // Deliberately never `.running` here — this timeline only ever
                // renders under the FINISHED chip, and a "running" spinner on a
                // turn that is over would be its own small lie. That rule is
                // pre-#296 (`running: false` was passed unconditionally); #296
                // only adds the interrupted case it could not express.
                activityRow(activity, state: Self.state(of: activity) == .interrupted ? .interrupted : .completed)
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

    private func activityRow(_ activity: ToolActivity, state: StepState) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs + 2) {
            switch state {
            case .running:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Brand.forge)
                    .hudPulse(Design.Motion.blink, from: 1, to: 0.35)
            case .interrupted:
                // #296: the warning slot, NOT `Design.Colors.danger`. The
                // usual cause is the user's own Stop — that is a thing they
                // asked for, not a fault to flag in red.
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Brand.forge)
                    .frame(width: 11, height: 11)
            case .completed:
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

                // #296: WHY it did not finish — the user's Stop, or a
                // host-reported failure (296-C1). Rendered BESIDE `detail`,
                // never over it: `detail` is what the call touched, and that
                // stays the more useful of the two.
                //
                // Corrected 2026-08-10: this said "the host's own error text",
                // which the wire does not provide — the runs host sends a bare
                // `error: true`, so what renders here is usually the generic
                // "The host reported an error." A short, honest line rather
                // than an invented reason.
                if let failure = activity.failure, !failure.isEmpty {
                    Text(failure)
                        .font(Design.Typography.monoSmall)
                        .foregroundStyle(Design.Brand.forge)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Design.Spacing.xs)

            if state == .running {
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

// MARK: - #296: the rail's glyph decision, as a pure function

extension ToolActivityRail {
    /// #296: three states, not two. `interrupted` is what the rail was
    /// missing — a call the user stopped, or one the host reported an error
    /// for, is neither running nor done, and collapsing it into "done" is how
    /// a killed `sleep 30; echo STOPTEST` came to render as `✓ TERMINAL`.
    ///
    /// Lives out here, `nonisolated` and total, so the decision is testable
    /// without a view host — the two-valued version it replaces was an inline
    /// boolean inside `body` and could only ever be checked by eye.
    enum StepState: Equatable, Sendable {
        case running
        case completed
        case interrupted
    }

    /// One step's state.
    ///
    /// `failure` is tested FIRST and wins outright. A marked activity is
    /// interrupted whatever `isActive` says: `ChatStore.cancelStreaming`
    /// writes the marker and clears `isActive` as two separate passes, so
    /// there is a real window where both are set, and the interrupted answer
    /// is the correct one throughout it.
    nonisolated static func state(of activity: ToolActivity) -> StepState {
        if activity.failure != nil { return .interrupted }
        return activity.isActive ? .running : .completed
    }

    /// The collapsed chip's glyph: interrupted if ANY step is.
    ///
    /// Deliberately two-valued — it never returns `.running`. The collapsed
    /// chip only renders on a turn that is over, and a finished turn holding
    /// an activity nobody ever resolved (a `tool.started` with no completion
    /// and no prose after it) would otherwise start claiming it is still
    /// running, forever. That is a different bug from #296's and this is not
    /// the lane that invents a rendering for it; `.completed` here preserves
    /// exactly what shipped, and 296-B is the bar that says it must.
    nonisolated static func summaryState(of activities: [ToolActivity]) -> StepState {
        activities.contains { state(of: $0) == .interrupted } ? .interrupted : .completed
    }
}
