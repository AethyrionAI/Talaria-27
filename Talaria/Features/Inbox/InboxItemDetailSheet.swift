import SwiftUI

struct InboxItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: InboxItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    headerSection
                    metadataSection
                    bodySection
                }
                .padding(Design.Spacing.lg)
            }
            .background(Design.Colors.background)
            .navigationTitle(item.type.displayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Design.Brand.accent)
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: item.type.displayIcon)
                .font(.system(size: Design.Size.iconLarge))
                .foregroundStyle(item.type.displayColor)

            Text(item.title)
                .font(Design.Typography.screenTitle2)
                .foregroundStyle(Design.Colors.foreground)
        }
    }

    private var bodySection: some View {
        Text(item.body)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Colors.secondaryForeground)
    }

    private var metadataSection: some View {
        HStack(spacing: Design.Spacing.md) {
            Label(item.status.rawValue.capitalized, systemImage: "checklist")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)

            Label(item.priority.rawValue.capitalized, systemImage: "flag")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }
}
