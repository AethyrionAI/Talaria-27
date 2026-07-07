import SwiftUI

// MARK: - HUD primitives
// Reusable arc-reactor HUD building blocks. Every screen composes these instead
// of hand-rolling shapes. See design/Talaria.dc.html.

// MARK: Screen background (radial field + texture + faint grid)

/// The base HUD field: the theme's radial gradient, its background texture
/// (embers / scanlines / paper grain — none for Deep Field), and an optional
/// faint grid. Drop behind a screen's content with `.ignoresSafeArea()`.
struct HUDScreenBackground: View {
    /// Optional fixed override. When nil (the default), the grid intensity
    /// follows the user's APPEARANCE → Grid Density pref via `ThemeRuntime`.
    var gridIntensity: Double? = nil

    var body: some View {
        ZStack {
            Design.Colors.background
            Design.Colors.screenGradient
            GlowPoolField()
            ThemeTextureView()
            GridOverlay()
                .opacity(gridIntensity ?? ThemeRuntime.shared.gridDensity.gridIntensity)
        }
    }
}

// MARK: Grid overlay

/// Faint background grid drawn with a Canvas. Style, color, and cell size
/// follow the active theme (lines / phosphor dots / ledger rules) unless
/// overridden.
struct GridOverlay: View {
    var cell: CGFloat? = nil
    var lineColor: Color? = nil
    var style: ThemeGridStyle? = nil

    var body: some View {
        let palette = ThemeRuntime.shared.palette
        let cell = self.cell ?? palette.gridCell
        let color = self.lineColor ?? palette.gridLineColor
        let style = self.style ?? palette.gridStyle

        Canvas { context, size in
            switch style {
            case .lines:
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += cell
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += cell
                }
                context.stroke(path, with: .color(color), lineWidth: 1)

            case .dots:
                // Phosphor dot pitch — a dot at each cell intersection.
                var dots = Path()
                let radius: CGFloat = 0.8
                var x: CGFloat = 0
                while x <= size.width {
                    var y: CGFloat = 0
                    while y <= size.height {
                        dots.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                                   width: radius * 2, height: radius * 2))
                        y += cell
                    }
                    x += cell
                }
                context.fill(dots, with: .color(color))

            case .rules:
                // Ledger rules — horizontal lines only.
                var path = Path()
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += cell
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
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

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
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
    var borderColor: Color = Design.Colors.hairline
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
            .panelHalo(cornerRadius: cornerRadius)
    }
}

/// Convenience modifier form of `HUDPanel` for views that already have padding.
extension View {
    @MainActor
    func hudPanel(
        cornerRadius: CGFloat = Design.CornerRadius.lg,
        borderColor: Color = Design.Colors.hairline,
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
            .panelHalo(cornerRadius: cornerRadius)
    }

    /// Art-direction panel halo (`ThemeArtDirection.panelHalo`): a rim ring
    /// just outside the border plus an outer glow. Inert (clear shadow, no
    /// overlay) for every theme without a halo, so default panels render
    /// exactly as before.
    @MainActor
    func panelHalo(cornerRadius: CGFloat) -> some View {
        let halo = ThemeRuntime.shared.artDirection.panelHalo
        let glowOpacity = 0.16 * Design.Glow.k * ThemeRuntime.shared.palette.glowScale
        return self
            .overlay {
                if let halo {
                    RoundedRectangle(cornerRadius: cornerRadius + 3)
                        .strokeBorder(halo.ringColor, lineWidth: 1)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: halo.map { $0.glowColor.opacity(glowOpacity) } ?? .clear,
                radius: halo?.glowRadius ?? 0
            )
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
