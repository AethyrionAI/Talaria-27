import SwiftUI

struct SlashCommandMenu: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    if index > 0 {
                        Rectangle()
                            .fill(Design.Colors.accentTint(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, Design.Spacing.md)
                    }

                    Button { onSelect(command) } label: {
                        HStack(spacing: Design.Spacing.sm) {
                            Text(command.displayTitle)
                                .font(Design.Typography.mono(13, weight: .medium))
                                .foregroundStyle(Design.Brand.accent)
                                .frame(width: 110, alignment: .leading)
                                .lineLimit(1)

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
                    .buttonStyle(SlashCommandButtonStyle())
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 260)
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.cyanBorder,
            fill: Design.Colors.surface,
            innerGlow: true
        )
        .padding(.horizontal, Design.Spacing.md)
    }
}

/// Highlights a slash-command row with a cyan wash while pressed.
private struct SlashCommandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Design.Colors.accentTint(0.12)
                    : Color.clear
            )
    }
}
