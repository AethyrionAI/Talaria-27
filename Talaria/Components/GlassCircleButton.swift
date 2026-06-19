import SwiftUI

struct GlassCircleButton: View {
    let icon: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                .foregroundStyle(Design.Colors.foreground)
                .frame(
                    width: Design.Size.glassCircleButton,
                    height: Design.Size.glassCircleButton
                )
        }
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel ?? icon)
    }
}
