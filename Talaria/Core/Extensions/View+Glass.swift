import SwiftUI

extension View {
    /// Apply glass effect for elevated surfaces.
    @ViewBuilder
    func adaptiveGlass(in shape: some Shape = .rect(cornerRadius: 16)) -> some View {
        self.glassEffect(.regular, in: shape)
    }

    /// Apply interactive glass effect (for tappable elements only).
    @ViewBuilder
    func adaptiveInteractiveGlass(in shape: some Shape = .rect(cornerRadius: 12)) -> some View {
        self.glassEffect(.regular.interactive(), in: shape)
    }
}
