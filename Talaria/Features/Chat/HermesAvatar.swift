import SwiftUI

struct HermesAvatar: View {
    var size: CGFloat = Design.Size.avatarSmall

    var body: some View {
        Text("H")
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .foregroundStyle(Design.Brand.accent)
            .frame(width: size, height: size)
            .background(Design.Colors.surface)
            .clipShape(Circle())
            .accessibilityLabel("Hermes")
    }
}
