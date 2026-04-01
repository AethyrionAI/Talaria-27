import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onPenTap: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            penButton
            textField
            sendButton
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, Design.Spacing.md)
        .padding(.bottom, Design.Spacing.xs)
    }

    private var penButton: some View {
        Button(action: onPenTap) {
            Image(systemName: "pencil")
                .font(.system(size: Design.Size.iconMedium, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(
                    width: Design.Size.minTapTarget,
                    height: Design.Size.minTapTarget
                )
        }
        .accessibilityLabel("Attachments")
    }

    private var textField: some View {
        TextField("Message Hermes.", text: $text)
            .font(Design.Typography.body)
            .focused($isFocused)
            .onSubmit {
                if canSend { onSend() }
            }
    }

    private var sendButton: some View {
        Button {
            if canSend { onSend() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: Design.Size.iconLarge))
                .foregroundStyle(sendButtonColor)
        }
        .disabled(!canSend)
        .accessibilityLabel("Send message")
        .animation(Design.Motion.quickResponse, value: canSend)
    }

    private var sendButtonColor: Color {
        canSend ? Design.Brand.accent : .gray.opacity(0.3)
    }
}
