import SwiftUI

struct SlashCommandMenu: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    if index > 0 {
                        Divider()
                            .background(Design.Colors.divider)
                            .padding(.horizontal, Design.Spacing.md)
                    }

                    Button { onSelect(command) } label: {
                        HStack(spacing: Design.Spacing.sm) {
                            Text(command.displayTitle)
                                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Design.Brand.accent)
                                .frame(width: 100, alignment: .leading)

                            Text(command.description)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.secondaryForeground)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, Design.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                .stroke(Design.Colors.divider, lineWidth: 1)
        )
        .padding(.horizontal, Design.Spacing.md)
    }
}
