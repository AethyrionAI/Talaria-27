import SwiftUI

struct InboxItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: InboxItem

    var body: some View {
        NavigationStack {
            ZStack {
                HUDScreenBackground(gridIntensity: 0.35)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                        headerSection
                        metadataSection
                        bodySection
                    }
                    .padding(Design.Spacing.lg)
                }
            }
            .navigationTitle(item.type.displayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(Design.Typography.body(15, weight: .medium))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel(
                "\(item.type.displayLabel) · \(priorityLabel)",
                size: 10,
                weight: .medium,
                tracking: Design.Tracking.monoWide,
                color: priorityColor
            )

            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                Image(systemName: item.type.displayIcon)
                    .font(.system(size: Design.Size.iconLarge))
                    .foregroundStyle(priorityColor)
                    .hudGlow(priorityColor, radius: 10, strength: 0.4)

                Text(item.title)
                    .font(Design.Typography.screenTitle2)
                    .foregroundStyle(Design.Colors.foregroundBright)
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel(
                "DETAIL",
                size: 10,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )

            Text(item.body)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Spacing.md)
                .hudPanel(
                    cornerRadius: Design.CornerRadius.lg,
                    borderColor: Design.Colors.cyanHairline,
                    fill: Design.Colors.surface
                )
        }
    }

    private var metadataSection: some View {
        HStack(spacing: Design.Spacing.sm) {
            metadataChip(
                label: item.status.rawValue.uppercased(),
                systemImage: "checklist",
                color: Design.Brand.accent
            )

            metadataChip(
                label: priorityLabel,
                systemImage: "flag.fill",
                color: priorityColor
            )

            Spacer(minLength: 0)
        }
    }

    private func metadataChip(label: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)

            MonoLabel(
                label,
                size: 9,
                weight: .medium,
                tracking: Design.Tracking.mono,
                color: color
            )
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .background(color.opacity(0.10), in: Capsule())
        .overlay {
            Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1)
        }
    }

    // MARK: - Derived values

    private var priorityColor: Color {
        switch item.priority {
        case .high, .urgent: Design.Colors.danger
        case .normal: Design.Brand.forge
        case .low: Design.Brand.accent
        }
    }

    private var priorityLabel: String {
        switch item.priority {
        case .high: "HIGH"
        case .urgent: "URGENT"
        case .normal: "MED"
        case .low: "LOW"
        }
    }
}
