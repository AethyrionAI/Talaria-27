import SwiftUI

// MARK: - Model selector (UI shell)
//
// Header control showing the active model (e.g. "CLAUDE OPUS 4.6") that opens a
// picker over a stubbed model list. Presentation only — the available models and
// the selection sink are exposed on `ModelSelectorModel` behind
// `// TODO: wire to hermes config/models`. No backend integration here.

// MARK: View model (wiring seam)

@MainActor
@Observable
final class ModelSelectorModel {

    struct ModelOption: Identifiable, Hashable {
        let id: String
        var displayName: String
        var detail: String?
    }

    // TODO: wire to hermes config/models — replace this placeholder list with the
    // host's actual available models (from HermesHostStore / a models endpoint).
    var availableModels: [ModelOption] = [
        ModelOption(id: "opus-4.6", displayName: "Claude Opus 4.6", detail: "Most capable"),
        ModelOption(id: "sonnet-4.6", displayName: "Claude Sonnet 4.6", detail: "Balanced"),
        ModelOption(id: "haiku-4.5", displayName: "Claude Haiku 4.5", detail: "Fastest"),
    ]

    var selectedModelID: String

    /// Optional override for the chip label (e.g. the live model name reported by
    /// the host). Falls back to the selected option's display name.
    var activeModelNameOverride: String?

    /// Wiring seam — connected to real model-switch behavior later.
    var onSelectModel: ((ModelOption) -> Void)? = nil

    /// Wiring seam — starts a fresh session. A model picked here is dispatched as
    /// a `/model` switch that applies to the CURRENT session (effective on the next
    /// message). NEW sessions instead start from the persistent default (set in
    /// Settings → Models / the models shim), so this is offered as a convenience.
    var onStartNewSession: (() -> Void)? = nil

    init(selectedModelID: String? = nil, activeModelNameOverride: String? = nil) {
        self.activeModelNameOverride = activeModelNameOverride
        self.selectedModelID = selectedModelID
            ?? activeModelNameOverride
            ?? "opus-4.6"
    }

    var activeDisplayName: String {
        if let override = activeModelNameOverride, !override.isEmpty { return override }
        return availableModels.first { $0.id == selectedModelID }?.displayName ?? "Select model"
    }

    func select(_ option: ModelOption) {
        selectedModelID = option.id
        activeModelNameOverride = nil
        onSelectModel?(option)
    }
}

// MARK: Header chip + picker

struct ModelSelector: View {
    var model: ModelSelectorModel
    /// Whether the host is online (drives the pip color).
    var isOnline: Bool = true

    @State private var isPickerPresented = false

    var body: some View {
        Button { isPickerPresented = true } label: {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: isOnline ? Design.Brand.accent : Design.Brand.forge, diameter: 7)
                Text(model.activeDisplayName.uppercased())
                    .font(Design.Typography.display(13, weight: .semibold, relativeTo: .subheadline))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Design.Brand.accent)
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.cyanBorder,
                      fill: Design.Colors.accentTint(0.08), innerGlow: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model: \(model.activeDisplayName). Change model")
        .popover(isPresented: $isPickerPresented) {
            picker
                .presentationCompactAdaptation(.popover)
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("SELECT MODEL", size: 10, tracking: Design.Tracking.monoWide)
                .padding(.bottom, Design.Spacing.xxs)
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            ForEach(model.availableModels) { option in
                Button {
                    model.select(option)
                } label: {
                    HStack(spacing: Design.Spacing.sm) {
                        StatusPip(
                            color: option.id == model.selectedModelID ? Design.Brand.accent : Design.Colors.dimForeground,
                            diameter: 7
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.displayName)
                                .font(Design.Typography.body(14, weight: .medium))
                                .foregroundStyle(Design.Colors.foreground)
                            if let detail = option.detail {
                                MonoLabel(detail, size: 9, color: Design.Colors.mutedForeground)
                            }
                        }
                        Spacer(minLength: Design.Spacing.lg)
                        if option.id == model.selectedModelID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Design.Brand.accent)
                        }
                    }
                    .padding(.vertical, Design.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
                }
            }
            .frame(maxHeight: 300)

            if model.onStartNewSession != nil {
                Rectangle()
                    .fill(Design.Colors.cyanHairline)
                    .frame(height: 1)
                    .padding(.vertical, Design.Spacing.xxs)
                MonoLabel("SWITCH APPLIES THIS SESSION", size: 8, tracking: Design.Tracking.mono,
                          color: Design.Colors.mutedForeground)
                Button {
                    model.onStartNewSession?()
                    isPickerPresented = false
                } label: {
                    HStack(spacing: Design.Spacing.xs) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Start New Session")
                            .font(Design.Typography.body(13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Design.Brand.accent)
                    .padding(.vertical, Design.Spacing.xs)
                    .padding(.horizontal, Design.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(Design.Colors.accentTint(0.08), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, Design.Spacing.xxs)
            }
        }
        .padding(Design.Spacing.md)
        .frame(width: 240)
        .background(Design.Colors.background)
    }
}
