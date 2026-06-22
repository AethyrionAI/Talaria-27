import SwiftUI

// MARK: - HUD primitives
// Reusable arc-reactor HUD building blocks. Every screen composes these instead
// of hand-rolling shapes. See design/Talaria.dc.html.

// MARK: Screen background (radial field + faint cyan grid)

/// The base HUD field: deep radial gradient with an optional faint cyan grid.
/// Drop behind a screen's content with `.ignoresSafeArea()`.
struct HUDScreenBackground: View {
    var gridIntensity: Double = 0.5

    var body: some View {
        ZStack {
            Design.Colors.background
            Design.Colors.screenGradient
            GridOverlay()
                .opacity(gridIntensity)
        }
    }
}

// MARK: Grid overlay

/// Faint cyan grid (default 26pt cells) drawn with a Canvas.
struct GridOverlay: View {
    var cell: CGFloat = Design.Size.gridCell
    var lineColor: Color = Design.Colors.accentTint(0.05)

    var body: some View {
        Canvas { context, size in
            let stroke = GraphicsContext.Shading.color(lineColor)
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: stroke, lineWidth: 1)
                x += cell
            }
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: stroke, lineWidth: 1)
                y += cell
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Corner brackets

/// L-shaped cyan brackets framing a view (targeting-frame motif). Apply with
/// `.overlay { CornerBrackets() }` or use it standalone inside a ZStack.
struct CornerBrackets: View {
    var arm: CGFloat = Design.Size.bracket
    var lineWidth: CGFloat = 1.5
    var color: Color = Design.Colors.accentTint(0.55)
    var inset: CGFloat = 0

    var body: some View {
        GeometryReader { _ in
            ZStack {
                bracket(top: true, leading: true)
                bracket(top: true, leading: false)
                bracket(top: false, leading: true)
                bracket(top: false, leading: false)
            }
            .padding(inset)
        }
        .allowsHitTesting(false)
    }

    private func bracket(top: Bool, leading: Bool) -> some View {
        Path { path in
            // Vertical arm
            path.move(to: CGPoint(x: leading ? 0 : arm, y: top ? arm : 0))
            path.addLine(to: CGPoint(x: leading ? 0 : arm, y: top ? 0 : arm))
            // Horizontal arm
            path.addLine(to: CGPoint(x: leading ? arm : 0, y: top ? 0 : arm))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
        .frame(width: arm, height: arm)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: Alignment(horizontal: leading ? .leading : .trailing,
                                    vertical: top ? .top : .bottom))
    }
}

// MARK: Scan line

/// A glow sweeping vertically across its container. Use sparingly (chat surface).
struct ScanLine: View {
    var duration: Double = Design.Motion.scanDuration
    var height: CGFloat = 120
    var intensity: Double = 0.45

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [Design.Colors.accentTint(0.16), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .opacity(intensity)
            .offset(y: reduceMotion ? 0 : (sweep ? proxy.size.height : -height))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: HUD panel

/// Dark translucent panel with a cyan hairline border and a subtle inner glow.
struct HUDPanel<Content: View>: View {
    var cornerRadius: CGFloat = Design.CornerRadius.lg
    var borderColor: Color = Design.Colors.cyanHairline
    var fill: Color = Design.Colors.surface
    var innerGlow: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .overlay {
                if innerGlow {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Design.Brand.accent.opacity(0.06), lineWidth: 6)
                        .blur(radius: 6)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
    }
}

/// Convenience modifier form of `HUDPanel` for views that already have padding.
extension View {
    func hudPanel(
        cornerRadius: CGFloat = Design.CornerRadius.lg,
        borderColor: Color = Design.Colors.cyanHairline,
        fill: Color = Design.Colors.surface,
        innerGlow: Bool = false
    ) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .overlay {
                if innerGlow {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Design.Brand.accent.opacity(0.06), lineWidth: 6)
                        .blur(radius: 6)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
    }
}

// MARK: Mono label

/// JetBrains-Mono uppercase tracked telemetry label (the `// ·` style).
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 10
    var weight: Design.Typography.MonoWeight = .regular
    var tracking: CGFloat = Design.Tracking.monoWide
    var color: Color = Design.Colors.mutedForeground

    init(
        _ text: String,
        size: CGFloat = 10,
        weight: Design.Typography.MonoWeight = .regular,
        tracking: CGFloat = Design.Tracking.monoWide,
        color: Color = Design.Colors.mutedForeground
    ) {
        self.text = text.uppercased()
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Design.Typography.mono(size, weight: weight))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: Status pip

/// A small glowing status dot. Cyan = online/secure; amber/red = warning.
struct StatusPip: View {
    var color: Color = Design.Brand.accent
    var diameter: CGFloat = 7
    var blinks: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .hudGlow(color, radius: 5, strength: 1.0)
            .modifier(OptionalBlink(active: blinks))
    }
}

private struct OptionalBlink: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.hudPulse(Design.Motion.blink, from: 1, to: 0.3) }
        else { content }
    }
}

// MARK: Glow button

/// Primary CTA: cyan gradient fill + cyan border + outer glow (e.g. PAIR DEVICE).
struct GlowButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = 56
    var glowIntensity: Double = Design.Glow.k
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title.uppercased())
                    .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                    .tracking(Design.Tracking.button)
            }
            .foregroundStyle(Design.Colors.foregroundBright)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                LinearGradient(
                    colors: [Design.Colors.accentTint(0.22), Design.Colors.accentTint(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.accentTint(0.6), lineWidth: 1)
            }
            .hudGlow(Design.Brand.accent, radius: 24, strength: 0.35, intensity: glowIntensity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary (ghost) button

/// Low-emphasis HUD button — translucent fill, cyan hairline.
struct GhostButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(Design.Typography.body(14, weight: .medium))
            }
            .foregroundStyle(Design.Brand.accentBright)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Design.Colors.accentTint(0.1), in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
