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
            // Art-direction lensing spokes (Event Horizon's .spin-ring) —
            // above the washes, below the star texture, matching the
            // design's layer order. Nil for every theme without a spec.
            if let spokes = ThemeRuntime.shared.artDirection.radialSpokes {
                RadialSpokeField(spec: spokes)
            }
            ThemeTextureView()
            GridOverlay()
                .opacity(gridIntensity ?? ThemeRuntime.shared.gridDensity.gridIntensity)
            // Sweeping tracking band (Haunted VHS) — below the scanline rows,
            // matching the handoff's z-order. Nil for every theme without one.
            if let sweep = ThemeRuntime.shared.artDirection.sweepBar {
                SweepBarField(spec: sweep)
            }
            // Dark CRT scanline rows — the handoffs stack these ABOVE the
            // whole screen (`::after` with multiply), so they get their own
            // slot over the grid. Nil for every theme without a spec.
            if let scanlines = ThemeRuntime.shared.artDirection.scanlineOverlay {
                LineFieldTexture(spec: scanlines)
            }
            // Art-direction corner ribbon (chat-screen::after) — Graffiti
            // Galaxy's rotated 'TAG' throwie, pinned to the top-trailing
            // corner; `.clipped()` below trims the bleed exactly like the
            // CSS overflow. Nil for every theme without a ribbon.
            if let ribbon = ThemeRuntime.shared.artDirection.cornerRibbon {
                CornerRibbonView(spec: ribbon)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
            }
        }
        .clipped()
    }
}

/// The rotated corner banner (`ThemeArtDirection.cornerRibbon`): text on a
/// solid band, turned 45° so it reads along the corner diagonal, offset so
/// its ends bleed past the screen edge (the design's `right: -26px`). The
/// hosting `HUDScreenBackground` clips the bleed. A spec with a `blinkPeriod`
/// hard-blinks between full and `blinkMinOpacity` (Haunted VHS's `recBlink
/// 1.1s steps(2)`); static ribbons (Graffiti Galaxy) never pay for the
/// timeline. Held at full opacity under Reduce Motion (system or app toggle)
/// — the CSS animation's 0% keyframe.
struct CornerRibbonView: View {
    let spec: ThemeCornerRibbonSpec

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    var body: some View {
        if let period = spec.blinkPeriod, period > 0, !reduceMotion {
            // A steps(2) blink only changes state twice per cycle — 10 fps
            // resolves the 1.1s cadence with no visible aliasing.
            TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                banner.opacity(phase < 0.5 ? 1 : spec.blinkMinOpacity)
            }
        } else {
            banner
        }
    }

    private var banner: some View {
        Text(spec.text)
            .font(Design.Typography.display(10, weight: .bold, relativeTo: .caption2))
            .kerning(0.8)
            .foregroundStyle(spec.textColor)
            .padding(.vertical, 4)
            .padding(.horizontal, 28)
            .background(spec.background)
            .rotationEffect(.degrees(45))
            .offset(x: 26, y: 22)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
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
        let strip = ThemeRuntime.shared.artDirection.panelTopStrip
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
            .overlay {
                // Art-direction top strip (card::before): a thin 90° gradient
                // hugging the panel's top edge. Filling the panel's rounded
                // shape and masking to the top `height` keeps the strip
                // following the rounded corners instead of poking past them.
                // Inert (no overlay) for every theme without a strip.
                if let strip {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(colors: strip.colors,
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .opacity(strip.opacity)
                        .mask(
                            VStack(spacing: 0) {
                                Rectangle().frame(height: strip.height)
                                Spacer(minLength: 0)
                            }
                        )
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: halo.map { $0.glowColor.opacity(glowOpacity) } ?? .clear,
                radius: halo?.glowRadius ?? 0
            )
    }

    /// Art-direction neon title glow (`ThemeArtDirection.titleGlow`): the
    /// handoffs' layered h1 text-shadow chain — tight + mid + wide primary
    /// shadows, one outer secondary halo — riding the glow pref × the theme's
    /// `glowScale` like every other `hudGlow`. Inert (clear, zero-radius
    /// shadows) for every theme without a treatment, so default titles render
    /// exactly as before.
    @MainActor
    func hudTitleGlow() -> some View {
        let art = ThemeRuntime.shared.artDirection
        let glow = art.titleGlow
        let k = min(1.0, Design.Glow.k * ThemeRuntime.shared.palette.glowScale)
        return self
            // Offset/chromatic shadow layers (comic + graffiti + glitch
            // titles) — inert modifier when the theme has no spec.
            .modifier(TitleShadowModifier(spec: art.titleShadow, glowK: k))
            .shadow(color: glow.map { $0.primary.opacity(0.90 * k) } ?? .clear,
                    radius: glow == nil ? 0 : 5)
            .shadow(color: glow.map { $0.primary.opacity(0.55 * k) } ?? .clear,
                    radius: glow == nil ? 0 : 15)
            .shadow(color: glow.map { $0.primary.opacity(0.45 * k) } ?? .clear,
                    radius: glow == nil ? 0 : 30)
            .shadow(color: glow.map { $0.secondary.opacity(0.25 * k) } ?? .clear,
                    radius: glow == nil ? 0 : 45)
    }
}

/// Renders `ThemeArtDirection.titleShadow`: up to four stacked offset shadows
/// (the inventory maxes at three). Layers with `blur == 0` are ink — comic
/// print offsets that must not fade with the glow pref; blurred layers are
/// light and ride it like every other glow. A spec with `glitchPeriod` runs
/// the Glitch Garden jitter: quiet for ~92% of the cycle, then two brief
/// scrambles of the offset layers — static under Reduce Motion (system or
/// app toggle), matching the CSS animation's 0% keyframe.
private struct TitleShadowModifier: ViewModifier {
    let spec: ThemeTitleShadowSpec?
    let glowK: Double

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let spec {
            if let period = spec.glitchPeriod, period > 0, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    shadowed(content, layers: Self.jittered(spec.layers, phase: phase))
                }
            } else {
                shadowed(content, layers: spec.layers)
            }
        } else {
            content
        }
    }

    private func shadowed(_ content: Content, layers: [ThemeTitleShadowSpec.Layer]) -> some View {
        func layer(_ index: Int) -> ThemeTitleShadowSpec.Layer? {
            index < layers.count ? layers[index] : nil
        }
        func color(_ layer: ThemeTitleShadowSpec.Layer?) -> Color {
            guard let layer else { return .clear }
            return layer.hue.opacity(layer.alpha * (layer.blur > 0 ? glowK : 1))
        }
        return content
            .shadow(color: color(layer(0)), radius: layer(0)?.blur ?? 0,
                    x: layer(0)?.offsetX ?? 0, y: layer(0)?.offsetY ?? 0)
            .shadow(color: color(layer(1)), radius: layer(1)?.blur ?? 0,
                    x: layer(1)?.offsetX ?? 0, y: layer(1)?.offsetY ?? 0)
            .shadow(color: color(layer(2)), radius: layer(2)?.blur ?? 0,
                    x: layer(2)?.offsetX ?? 0, y: layer(2)?.offsetY ?? 0)
            .shadow(color: color(layer(3)), radius: layer(3)?.blur ?? 0,
                    x: layer(3)?.offsetX ?? 0, y: layer(3)?.offsetY ?? 0)
    }

    /// The design's 92/94/96% keyframes scramble only the OFFSET (ink)
    /// layers; glow layers hold steady. Two states: mirror every offset,
    /// then swap-skew (first offset stretched, second compressed, both
    /// mirrored) — a perception-level port of the CSS offset shuffle.
    private static func jittered(
        _ layers: [ThemeTitleShadowSpec.Layer],
        phase: Double
    ) -> [ThemeTitleShadowSpec.Layer] {
        guard phase >= 0.92, phase < 0.98 else { return layers }
        let swapSkew = phase >= 0.95
        var offsetIndex = 0
        return layers.map { layer in
            guard layer.blur == 0 else { return layer }
            let scale: CGFloat = swapSkew ? (offsetIndex == 0 ? 1.5 : 0.5) : 1
            offsetIndex += 1
            return ThemeTitleShadowSpec.Layer(
                hue: layer.hue, alpha: layer.alpha,
                offsetX: -layer.offsetX * scale, offsetY: -layer.offsetY * scale,
                blur: 0
            )
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

// MARK: Single-line HUD label behavior (#42)

extension View {
    /// Pins a HUD label to one line: tighten first, then scale down, then
    /// truncate with `…` as the last resort. Header telemetry must never
    /// character-wrap (`HE`/`RM`/`ES`) under horizontal pressure. Opt-in —
    /// some MonoLabels (voice transcript lines) wrap by design.
    func hudSingleLine(minScale: CGFloat = 0.6) -> some View {
        self
            .lineLimit(1)
            .allowsTightening(true)
            .minimumScaleFactor(minScale)
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
