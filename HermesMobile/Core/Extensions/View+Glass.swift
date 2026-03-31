import SwiftUI

extension View {
    /// Apply glass effect with automatic fallback for pre-iOS 26.
    /// Uses the provided shape for glass rendering, falling back to material for older iOS.
    @ViewBuilder
    func adaptiveGlass(
        prominent: Bool = false,
        in shape: AnyShape = AnyShape(.rect(cornerRadius: 16))
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(prominent ? .prominent : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Apply interactive glass effect (for tappable elements only).
    /// Uses the provided shape for glass rendering, falling back to material for older iOS.
    @ViewBuilder
    func adaptiveInteractiveGlass(
        prominent: Bool = false,
        in shape: AnyShape = AnyShape(.rect(cornerRadius: 12))
    ) -> some View {
        if #available(iOS 26, *) {
            let style: GlassEffectStyle = prominent
                ? .prominent.interactive()
                : .regular.interactive()
            self.glassEffect(style, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
