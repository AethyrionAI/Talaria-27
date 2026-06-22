import SwiftUI

/// Renders a fenced code block with monospaced font, distinct background,
/// optional language label, and a copy-to-clipboard button.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with language label and copy button
            if language != nil || !code.isEmpty {
                header
            }

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Design.Typography.mono(13, relativeTo: .footnote))
                    .foregroundStyle(Design.Colors.coolForeground)
                    .textSelection(.enabled)
                    .padding(.horizontal, Design.Spacing.sm)
                    .padding(.vertical, Design.Spacing.xs)
            }
        }
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Code block\(language.map { ", \($0)" } ?? "")")
        .accessibilityAction(named: "Copy code") { copyToClipboard() }
    }

    private var header: some View {
        HStack(spacing: Design.Spacing.xs) {
            MonoLabel(
                (language?.isEmpty == false ? language! : "code"),
                size: 10,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )

            Spacer()

            Button(action: copyToClipboard) {
                HStack(spacing: Design.Spacing.xxs) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                    Text(didCopy ? "COPIED" : "COPY")
                        .font(Design.Typography.mono(10, weight: .medium, relativeTo: .caption2))
                        .tracking(Design.Tracking.mono)
                }
                .foregroundStyle(didCopy ? Design.Brand.accent : Design.Colors.mutedForeground)
                .animation(Design.Motion.quickResponse, value: didCopy)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.top, Design.Spacing.xs)
        .padding(.bottom, Design.Spacing.xxs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.accentTint(0.12))
                .frame(height: 1)
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = code
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
