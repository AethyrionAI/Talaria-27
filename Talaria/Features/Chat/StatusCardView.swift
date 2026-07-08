import SwiftUI

struct StatusCardView: View {
    let connectionLabel: String
    let messageCount: Int
    let conversationID: UUID?
    let tokenUsage: TokenUsage?
    let dismissAction: () -> Void
    /// #46: last-turn receipt + session running totals. All optional and all
    /// real-data-only — rows render only for values that actually exist.
    var lastTurnDuration: TimeInterval? = nil
    var lastTurnCost: Double? = nil
    var sessionTotals: ChatStore.SessionUsageTotals? = nil
    var sessionCost: (cost: Double, costedTurns: Int)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.sm) {
                // Cyan checkmark box
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                    .background(Design.Colors.accentTint(0.14), in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 1))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 1)
                            .strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                    Text("Session Status")
                        .font(Design.Typography.body(13, weight: .medium))
                        .foregroundStyle(Design.Colors.foregroundBright)
                    MonoLabel(
                        connectionLabel,
                        size: 10,
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.mutedForeground
                    )
                }

                Spacer(minLength: 0)

                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss session status")
            }

            Rectangle()
                .fill(Design.Colors.accentTint(0.12))
                .frame(height: 1)

            statusRow("Connection", value: connectionLabel)
            statusRow("Messages", value: "\(messageCount)")
            if let id = conversationID {
                statusRow("Session", value: String(id.uuidString.prefix(8)))
            }

            if let usage = tokenUsage {
                Rectangle()
                    .fill(Design.Colors.accentTint(0.12))
                    .frame(height: 1)
                sectionHeader("LAST TURN")
                statusRow("Input", value: "\(TurnReceiptFormat.fullTokenLabel(usage.promptTokens)) tokens")
                statusRow("Output", value: TurnReceiptFormat.fullTokenLabel(usage.completionTokens))
                statusRow("Total", value: TurnReceiptFormat.fullTokenLabel(usage.totalTokens))
                if let lastTurnDuration {
                    statusRow("Duration", value: TurnReceiptFormat.durationLabel(lastTurnDuration))
                }
                if let lastTurnCost {
                    statusRow("Est. cost", value: "~\(TurnReceiptFormat.costLabel(lastTurnCost))")
                }
            }

            // #46: session running totals across every metered turn. Input
            // sums on purpose (each turn re-reads context — the sum is what
            // gets billed).
            if let totals = sessionTotals {
                Rectangle()
                    .fill(Design.Colors.accentTint(0.12))
                    .frame(height: 1)
                sectionHeader("SESSION")
                statusRow("Metered turns", value: "\(totals.meteredTurns)")
                statusRow("Input", value: "\(TurnReceiptFormat.fullTokenLabel(totals.promptTokens)) tokens")
                statusRow("Output", value: TurnReceiptFormat.fullTokenLabel(totals.completionTokens))
                if totals.totalDuration > 0 {
                    statusRow("Model time", value: TurnReceiptFormat.durationLabel(totals.totalDuration))
                }
                if let sessionCost {
                    statusRow(
                        sessionCost.costedTurns == totals.meteredTurns
                            ? "Est. cost"
                            : "Est. cost (\(sessionCost.costedTurns)/\(totals.meteredTurns) turns priced)",
                        value: "~\(TurnReceiptFormat.costLabel(sessionCost.cost))"
                    )
                }
                MonoLabel(
                    "COSTS ARE ESTIMATES — USAGE CARRIES NO CACHE-READ SPLIT",
                    size: 8,
                    tracking: Design.Tracking.mono,
                    color: Design.Colors.dimForeground
                )
            }
        }
        .padding(Design.Spacing.md)
        .background(
            LinearGradient(
                colors: [Design.Colors.accentTint(0.1), Design.Colors.accentTint(0.03)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 4)
                .strokeBorder(Design.Colors.accentTint(0.25), lineWidth: 1)
        }
        .padding(.horizontal, Design.Spacing.md)
    }

    private func sectionHeader(_ title: String) -> some View {
        MonoLabel(
            title,
            size: 9,
            tracking: Design.Tracking.monoWide,
            color: Design.Colors.dimForeground
        )
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            MonoLabel(
                label,
                size: 10,
                tracking: Design.Tracking.mono,
                color: Design.Colors.mutedForeground
            )
            Spacer()
            Text(value)
                .font(Design.Typography.mono(11, weight: .medium))
                .foregroundStyle(Design.Colors.coolForeground)
        }
    }
}
