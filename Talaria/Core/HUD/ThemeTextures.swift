import SwiftUI

// MARK: - Theme background textures
// Per-theme atmosphere drawn behind the grid in `HUDScreenBackground`. All
// pure Canvas — no pixel assets. Layouts are seeded/deterministic so a static
// frame is stable; the only motion (ember drift) runs through TimelineView and
// is disabled under Reduce Motion (system or app toggle), which degrades to
// the same static frame.

/// Draws the active theme's texture (`ThemePalette.texture`). Deep Field has
/// none — its background stays byte-identical to the pre-theming app.
/// Texture colors resolve through `ThemeArtDirection` where a theme curates
/// them; the fallbacks are the pre-art-direction values.
struct ThemeTextureView: View {
    var body: some View {
        let art = ThemeRuntime.shared.artDirection
        switch ThemeRuntime.shared.palette.texture {
        case .none:
            EmptyView()
        case .embers:
            EmberTexture(color: art.emberTint ?? Design.Brand.forge)
        case .scanlines:
            ScanlineTexture(color: Design.Colors.accentTint(0.04))
        case .paperGrain:
            PaperGrainTexture(ink: Design.Colors.foreground)
        case .starfield:
            // A starfield theme curates its own speck hues; the accent
            // fallback only exists so a missing entry fails soft, not blank.
            StarfieldTexture(field: art.starfield ?? ThemeStarfield(colors: [Design.Brand.accent]))
        }
    }
}

// MARK: Glow pools (art-direction nebula layer)

/// Radial glow pools painted between the screen gradient and the texture —
/// `ThemeArtDirection.glowPools`. Empty for every theme without an art-
/// direction entry, so the default screen stack is unchanged.
struct GlowPoolField: View {
    var body: some View {
        let pools = ThemeRuntime.shared.artDirection.glowPools
        if !pools.isEmpty {
            GeometryReader { proxy in
                let radiusBase = max(proxy.size.width, proxy.size.height)
                ZStack {
                    ForEach(pools.indices, id: \.self) { index in
                        let pool = pools[index]
                        RadialGradient(
                            colors: [pool.color, .clear],
                            center: pool.center,
                            startRadius: 0,
                            endRadius: max(1, radiusBase * pool.radiusFraction)
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: Seeded pseudo-random

/// Deterministic unit-interval hash (classic sine-fract). Stable per (index,
/// salt) so texture layouts don't reshuffle between frames or launches.
private func seededUnit(_ index: Int, _ salt: Int) -> Double {
    let x = sin(Double(index &* 127 &+ salt &* 311) + 0.5) * 43758.5453
    return x - x.rounded(.down)
}

// MARK: Embers (Solar Forge)

/// Sparse warm specks drifting slowly upward. Static under Reduce Motion.
struct EmberTexture: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    private static let emberCount = 22

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    Self.draw(context: context, size: size, time: 0, color: color)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                    Canvas { context, size in
                        Self.draw(
                            context: context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            color: color
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(context: GraphicsContext, size: CGSize, time: Double, color: Color) {
        guard size.height > 0 else { return }
        let travel = size.height + 40
        for i in 0..<emberCount {
            let sx = seededUnit(i, 1)
            let sy = seededUnit(i, 2)
            let ss = seededUnit(i, 3)
            let sp = seededUnit(i, 4)

            let speed = 8.0 + ss * 14.0  // pt/s upward
            let phase = (sy * travel + time * speed).truncatingRemainder(dividingBy: travel)
            let y = size.height + 20 - phase
            let wobble = sin(time * (0.4 + sp * 0.5) + sx * 2 * .pi) * 6
            let x = sx * size.width + wobble
            let radius = 1.0 + ss * 1.8
            let opacity = 0.05 + sp * 0.11

            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        }
    }
}

// MARK: Scanlines (Terminal)

/// Static phosphor scanline rows. Deliberately no flicker — flicker is a
/// photosensitivity hazard and adds nothing at this subtlety.
struct ScanlineTexture: View {
    let color: Color
    var pitch: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += pitch
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: Starfield (Event Horizon)

/// Multi-hue star specks drifting in slow diagonals — the handoff's four
/// `.page-bg` layers panning over 24s. Seeded/deterministic like the other
/// textures; static under Reduce Motion.
struct StarfieldTexture: View {
    let field: ThemeStarfield

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    /// Per-layer drift vectors (pt/s) — four diagonals mirroring the
    /// handoff's `starfieldDrift` background-position pans.
    private static let drifts: [(dx: Double, dy: Double)] = [
        (3.75, 3.75), (-5.0, 5.0), (6.25, -6.25), (-4.6, 4.6),
    ]

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    Self.draw(context: context, size: size, time: 0, field: field)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                    Canvas { context, size in
                        Self.draw(
                            context: context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            field: field
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(context: GraphicsContext, size: CGSize, time: Double, field: ThemeStarfield) {
        guard size.width > 0, size.height > 0, !field.colors.isEmpty else { return }
        // Specks wrap across a margin-padded span so drift never pops at edges.
        let margin: Double = 20
        let spanW = size.width + margin * 2
        let spanH = size.height + margin * 2

        for i in 0..<field.count {
            let drift = drifts[i % drifts.count]
            let color = field.colors[i % field.colors.count]

            let baseX = seededUnit(i, 31) * spanW
            let baseY = seededUnit(i, 32) * spanH
            let rawX = (baseX + time * drift.dx * field.driftScale).truncatingRemainder(dividingBy: spanW)
            let rawY = (baseY + time * drift.dy * field.driftScale).truncatingRemainder(dividingBy: spanH)
            let x = (rawX + spanW).truncatingRemainder(dividingBy: spanW) - margin
            let y = (rawY + spanH).truncatingRemainder(dividingBy: spanH) - margin

            let radius = 0.7 + seededUnit(i, 33) * 1.1
            let opacity = 0.10 + seededUnit(i, 34) * 0.18

            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        }
    }
}

// MARK: Paper grain (Paper Tape)

/// Static ink speckle + a few short fibers, like recycled teletype stock.
struct PaperGrainTexture: View {
    let ink: Color

    var body: some View {
        Canvas { context, size in
            // Speckles — density scales with area, capped for battery sanity.
            let speckleCount = min(650, Int(size.width * size.height / 900))
            var speckles = Path()
            for i in 0..<speckleCount {
                let x = seededUnit(i, 11) * size.width
                let y = seededUnit(i, 12) * size.height
                let radius = 0.4 + seededUnit(i, 13) * 0.7
                speckles.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
            context.fill(speckles, with: .color(ink.opacity(0.035)))

            // Fibers — short near-horizontal strands.
            var fibers = Path()
            for i in 0..<14 {
                let x = seededUnit(i, 21) * size.width
                let y = seededUnit(i, 22) * size.height
                let length = 5.0 + seededUnit(i, 23) * 5.0
                let angle = (seededUnit(i, 24) - 0.5) * 0.6
                fibers.move(to: CGPoint(x: x, y: y))
                fibers.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
            }
            context.stroke(fibers, with: .color(ink.opacity(0.05)), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}
