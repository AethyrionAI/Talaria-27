import SwiftUI

/// The shared confirm gate's transcript card (#29): what a side-effecting
/// device tool staged, rendered inline at the tail of the chat while the
/// tool's async call is suspended on the gate. Fields are editable in place
/// — Approve executes with the CURRENT values; Cancel resolves the tool with
/// a "user declined" result. Nothing happens until one of them is tapped.
struct ToolConfirmationCard: View {
    let center: ToolConfirmationCenter
    let confirmation: ToolConfirmationCenter.PendingConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "hand.raised")
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(Design.Brand.forge)
                MonoLabel("Confirm", size: 9, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Brand.forge)
                Spacer()
            }

            Text(confirmation.title)
                .font(Design.Typography.body(15, weight: .semibold))
                .foregroundStyle(Design.Colors.foregroundBright)

            VStack(spacing: Design.Spacing.xs) {
                ForEach(confirmation.fields) { field in
                    HStack(spacing: Design.Spacing.sm) {
                        MonoLabel(field.label.uppercased(), size: 9,
                                  tracking: Design.Tracking.mono,
                                  color: Design.Colors.mutedForeground)
                            .frame(width: 64, alignment: .leading)
                        TextField(field.label, text: Binding(
                            get: { center.pending?.fields.first(where: { $0.id == field.id })?.value ?? field.value },
                            set: { center.updateField(id: field.id, value: $0) }
                        ))
                        .font(Design.Typography.callout.monospaced())
                        .foregroundStyle(Design.Colors.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, Design.Spacing.sm)
                        .padding(.vertical, Design.Spacing.xs)
                        .background(Design.Colors.accentTint(0.06), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                                .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                        }
                    }
                }
            }

            if let detail = confirmation.detail {
                Text(detail)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            HStack(spacing: Design.Spacing.sm) {
                Button {
                    center.decline()
                } label: {
                    Text("CANCEL")
                        .font(Design.Typography.mono(11, weight: .medium))
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs)
                        .overlay { Capsule().strokeBorder(Design.Colors.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel — nothing will be created")

                Button {
                    center.approve()
                } label: {
                    Text("APPROVE")
                        .font(Design.Typography.mono(11, weight: .medium))
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Brand.accentBright)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs)
                        .background(Design.Colors.accentTint(0.10), in: Capsule())
                        .overlay { Capsule().strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Approve with the values shown")

                Spacer()
            }
        }
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Brand.forge.opacity(0.35),
            fill: Design.Colors.surface
        )
        .padding(.horizontal, Design.Spacing.md)
    }
}
