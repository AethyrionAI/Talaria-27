import SwiftUI

struct GlassCircleButton: View {
    let icon: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                .foregroundStyle(Design.Brand.accentBright)
                .frame(
                    width: Design.Size.glassCircleButton,
                    height: Design.Size.glassCircleButton
                )
                .background(
                    Design.Colors.accentTint(0.08),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(Design.Colors.cyanBorder, lineWidth: 1)
                }
                .hudGlow(Design.Brand.accent, radius: 12, strength: 0.25)
        }
        .buttonStyle(.plain)
        .frame(minWidth: Design.Size.minTapTarget, minHeight: Design.Size.minTapTarget)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel ?? icon)
    }
}
