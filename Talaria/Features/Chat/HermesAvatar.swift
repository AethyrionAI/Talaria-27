import SwiftUI

struct HermesAvatar: View {
    var size: CGFloat = Design.Size.avatarSmall

    var body: some View {
        ReactorOrb(size: size, style: .standard)
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel("Hermes")
    }
}
