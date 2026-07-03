import SwiftUI

// MARK: - Model selector (UI shell)
//
// Header chip showing the active model name. Tapping opens the real Settings →
// MODELS picker (shim-backed) via the `onChipTap` callback — no local dropdown.
// The chip label tracks the live model through `activeModelNameOverride`, seeded
// at launch from the shim or command catalog and updated on `/model` switches.

// MARK: View model

@MainActor
@Observable
final class ModelSelectorModel {

    /// The chip label — set from chatStore.activeModelName or the shim's current
    /// model. Falls back to "HERMES" when no source has provided a name yet.
    var activeModelNameOverride: String?

    /// Callback fired on chip tap. ChatScreen wires this to present the Settings →
    /// Models sheet (the shim-backed picker).
    var onChipTap: (() -> Void)?

    var activeDisplayName: String {
        if let override = activeModelNameOverride, !override.isEmpty { return override }
        return "HERMES"
    }
}

// MARK: Header chip

struct ModelSelector: View {
    var model: ModelSelectorModel
    /// Whether the host is online (drives the pip color).
    var isOnline: Bool = true

    var body: some View {
        Button { model.onChipTap?() } label: {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: isOnline ? Design.Brand.accent : Design.Brand.forge, diameter: 7)
                Text(model.activeDisplayName.uppercased())
                    .font(Design.Typography.display(13, weight: .semibold, relativeTo: .subheadline))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .lineLimit(1)
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.strongBorder,
                      fill: Design.Colors.accentTint(0.08), innerGlow: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model: \(model.activeDisplayName). Open model picker")
    }
}
