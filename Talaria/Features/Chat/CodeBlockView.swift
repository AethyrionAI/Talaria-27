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
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Design.Colors.foreground)
                    .textSelection(.enabled)
                    .padding(.horizontal, Design.Spacing.sm)
                    .padding(.vertical, Design.Spacing.xs)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Code block\(language.map { ", \($0)" } ?? "")")
        .accessibilityAction(named: "Copy code") { copyToClipboard() }
    }

    private var header: some View {
        HStack(spacing: Design.Spacing.xs) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(Design.Typography.caption2.monospaced())
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button(action: copyToClipboard) {
                HStack(spacing: Design.Spacing.xxxs) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                    Text(didCopy ? "Copied" : "Copy")
                        .font(Design.Typography.caption2)
                }
                .foregroundStyle(didCopy ? .green : Design.Colors.secondaryForeground)
                .animation(Design.Motion.quickResponse, value: didCopy)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.top, Design.Spacing.xs)
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
