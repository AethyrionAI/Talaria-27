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
        if let motion = art.atmosphereMotion {
            // An atmosphere motion spec supersedes the static texture — it IS
            // the theme's atmosphere (Event Horizon's `.page-bg` drift). Every
            // theme without a spec takes the switch below, byte-identical to
            // the pre-motion rendering.
            AtmosphereMotionField(spec: motion)
        } else if let lines = art.lineTexture {
            // A line-field spec is the theme's page texture the same way
            // (Holo Sushi's dual-tone grid, Cyber Cactus's crosshatch,
            // Graffiti Galaxy's spray streaks). Next in the supersede chain.
            LineFieldTexture(spec: lines)
        } else {
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
}

// MARK: Glow pools (art-direction nebula layer)

/// Radial glow pools painted between the screen gradient and the texture —
/// `ThemeArtDirection.glowPools`. Empty for every theme without an art-
/// direction entry, so the default screen stack is unchanged. Pools with a
/// `pulsePeriod` breathe their opacity through a TimelineView (Karaoke
/// Supernova's `roomPulse`); static pools never pay for the timeline.
struct GlowPoolField: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    var body: some View {
        let pools = ThemeRuntime.shared.artDirection.glowPools
        if !pools.isEmpty {
            if pools.contains(where: { $0.pulsePeriod != nil }) && !reduceMotion {
                // 10 fps is plenty for a 5s opacity breathe.
                TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
                    poolStack(pools, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Static pools — and the Reduce Motion frame, which pins
                // pulsing pools at `pulseMinOpacity` (the CSS 0% keyframe).
                poolStack(pools, time: nil)
            }
        }
    }

    private func poolStack(_ pools: [ThemeGlowPool], time: TimeInterval?) -> some View {
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
                    .opacity(pulseOpacity(pool, time: time))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Ease-in-out breathe between `pulseMinOpacity` and 1, min at phase 0 —
    /// the handoff's `0%,100% { opacity: .6 } 50% { opacity: 1 }`.
    private func pulseOpacity(_ pool: ThemeGlowPool, time: TimeInterval?) -> Double {
        guard let period = pool.pulsePeriod, period > 0 else { return 1 }
        guard let time else { return pool.pulseMinOpacity }
        let phase = time.truncatingRemainder(dividingBy: period) / period
        let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)   // 0 → 1 → 0, smooth
        return pool.pulseMinOpacity + (1 - pool.pulseMinOpacity) * wave
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

// MARK: Atmosphere motion (data-driven parallax drift)

/// Renders an `AtmosphereMotionSpec`: each layer is a repeating speck tile
/// translated by `driftPerLoop · (t / period)` and wrapped at tile bounds —
/// the Swift port of the handoffs' multi-layer `background-position` pans
/// (Event Horizon's `starfieldDrift`). One Canvas, one batched path fill per
/// layer, no per-speck views. Frozen at t = 0 under Reduce Motion (system or
/// app toggle), which matches the CSS animation's 0% keyframe.
struct AtmosphereMotionField: View {
    let spec: AtmosphereMotionSpec

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    Self.draw(context: context, size: size, time: 0, spec: spec)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    Canvas { context, size in
                        Self.draw(
                            context: context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            spec: spec
                        )
                    }
                }
            }
        }
        .opacity(spec.fieldOpacity)
        .allowsHitTesting(false)
    }

    private static func draw(context: GraphicsContext, size: CGSize, time: Double, spec: AtmosphereMotionSpec) {
        guard size.width > 0, size.height > 0, spec.period > 0 else { return }
        var phase = time.truncatingRemainder(dividingBy: spec.period) / spec.period
        if let steps = spec.stepCount, steps > 0 {
            // Quantize the pan into discrete jumps (Haunted VHS's
            // `steps(4)` static scramble) — the field holds still between
            // jumps instead of gliding.
            phase = (Double(steps) * phase).rounded(.down) / Double(steps)
        }

        for layer in spec.layers {
            let tileW = layer.tileSize
            let tileH = layer.tileHeight ?? layer.tileSize
            guard tileW > 0, tileH > 0 else { continue }

            // This frame's pan, wrapped to one tile so the loop is seamless
            // (drift components are whole tile multiples by construction).
            let offsetX = ((layer.driftX * phase).truncatingRemainder(dividingBy: tileW) + tileW)
                .truncatingRemainder(dividingBy: tileW)
            let offsetY = ((layer.driftY * phase).truncatingRemainder(dividingBy: tileH) + tileH)
                .truncatingRemainder(dividingBy: tileH)

            // One speck per tile, batched into a single fill. Start one tile
            // before the origin so wrapped specks cover the leading edges.
            var specks = Path()
            let radius = layer.speckRadius
            let cols = Int((size.width / tileW).rounded(.up))
            let rows = Int((size.height / tileH).rounded(.up))
            for col in -1...cols {
                for row in -1...rows {
                    let x = (CGFloat(col) + layer.anchorX) * tileW + offsetX
                    let y = (CGFloat(row) + layer.anchorY) * tileH + offsetY
                    if let barHeight = layer.barHeight {
                        // Vertical laser bar (Karaoke Supernova's
                        // `radial-gradient(2px 80px …)`) — a capsule centered
                        // on the anchor, speck-width wide.
                        specks.addPath(Path(roundedRect: CGRect(
                            x: x - radius, y: y - barHeight / 2,
                            width: radius * 2, height: barHeight
                        ), cornerRadius: radius))
                    } else {
                        specks.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                                     width: radius * 2, height: radius * 2))
                    }
                }
            }
            // The design's speck is a radial-gradient point fading to
            // transparent — soft, not a hard disc. A blur on the batched
            // path (one filter per LAYER, not per speck) reproduces the
            // falloff while keeping a single fill call, so the perf
            // guardrail holds. Radius scales with speck size; `blurScale`
            // hardens deliberate print dots (halftone) without giving up
            // the soft default.
            var layerContext = context
            let blur = radius * 0.8 * layer.blurScale
            if blur > 0.01 {
                layerContext.addFilter(.blur(radius: blur))
            }
            layerContext.fill(specks, with: .color(layer.hue.opacity(layer.speckAlpha)))
        }
    }
}

// MARK: Line field (art-direction lattices, scanlines, spray streaks)

/// Renders a `ThemeLineFieldSpec`: per layer either a continuous parallel-line
/// lattice at an arbitrary angle (Holo Sushi's dual grid, Cyber Cactus's
/// crosshatch, the dark CRT scanline overlays) or one soft streak per tile
/// (Graffiti Galaxy's spray grain). Static specs (`driftPeriod == nil` —
/// every pre-batch-4 adopter) stay a single Canvas with one batched stroke
/// per layer and no TimelineView cost; a spec with a `driftPeriod` pans its
/// layers by `driftX/driftY` per loop (Midnight Aquarium's `causticDrift`),
/// frozen at t = 0 under Reduce Motion.
struct LineFieldTexture: View {
    let spec: ThemeLineFieldSpec

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    var body: some View {
        Group {
            if let period = spec.driftPeriod, period > 0, !reduceMotion {
                // The caustic pan is slow (a tile-scale glide over 16s) —
                // 10 fps is visually continuous at lattice alphas.
                TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
                    Canvas { context, size in
                        Self.draw(
                            context: context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            spec: spec
                        )
                    }
                }
            } else {
                Canvas { context, size in
                    Self.draw(context: context, size: size, time: 0, spec: spec)
                }
            }
        }
        .opacity(spec.fieldOpacity)
        .allowsHitTesting(false)
    }

    private static func draw(context: GraphicsContext, size: CGSize, time: Double, spec: ThemeLineFieldSpec) {
        guard size.width > 0, size.height > 0 else { return }
        let phase: Double
        if let period = spec.driftPeriod, period > 0 {
            phase = time.truncatingRemainder(dividingBy: period) / period
        } else {
            phase = 0
        }

        for layer in spec.layers {
            guard layer.spacing > 0 else { continue }
            let offsetX = layer.driftX * phase
            let offsetY = layer.driftY * phase

            if let segment = layer.segmentLength {
                // Streak mode: one dash per axis-aligned tile, angled along
                // the layer direction from the tile origin (the CSS
                // `linear-gradient(135deg, hue 0, transparent 12px)` corner
                // marks). A light blur reproduces the paint fade without
                // per-streak gradients.
                let tile = layer.spacing
                let angle = Angle(degrees: layer.angleDegrees).radians
                let dx = cos(angle) * segment
                let dy = sin(angle) * segment
                // This frame's pan, wrapped to one tile (drift is inert at
                // phase 0, so static specs draw exactly as before).
                let tileOffsetX = ((offsetX).truncatingRemainder(dividingBy: tile) + tile)
                    .truncatingRemainder(dividingBy: tile)
                let tileOffsetY = ((offsetY).truncatingRemainder(dividingBy: tile) + tile)
                    .truncatingRemainder(dividingBy: tile)
                var streaks = Path()
                let cols = Int((size.width / tile).rounded(.up))
                let rows = Int((size.height / tile).rounded(.up))
                for col in -1...cols {
                    for row in -1...rows {
                        let x = CGFloat(col) * tile + tileOffsetX
                        let y = CGFloat(row) * tile + tileOffsetY
                        streaks.move(to: CGPoint(x: x, y: y))
                        streaks.addLine(to: CGPoint(x: x + dx, y: y + dy))
                    }
                }
                var layerContext = context
                layerContext.addFilter(.blur(radius: layer.lineWidth * 0.6))
                layerContext.stroke(
                    streaks,
                    with: .color(layer.hue.opacity(layer.alpha)),
                    style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round)
                )
            } else {
                // Continuous lattice: parallel lines along `angleDegrees`,
                // `spacing` apart. Drawn in a rotated copy of the context so
                // one horizontal-line loop covers every angle; the span is
                // padded to the diagonal — plus the layer's full drift, so a
                // panning lattice never exposes corners mid-loop — so
                // rotation never exposes corners.
                let halfSpan = hypot(size.width, size.height) / 2 + layer.spacing
                    + hypot(layer.driftX, layer.driftY)
                var lines = Path()
                var y = -halfSpan
                while y <= halfSpan {
                    lines.move(to: CGPoint(x: -halfSpan, y: y))
                    lines.addLine(to: CGPoint(x: halfSpan, y: y))
                    y += layer.spacing
                }
                var layerContext = context
                layerContext.translateBy(x: size.width / 2 + offsetX,
                                         y: size.height / 2 + offsetY)
                layerContext.rotate(by: .degrees(layer.angleDegrees))
                layerContext.stroke(
                    lines,
                    with: .color(layer.hue.opacity(layer.alpha)),
                    lineWidth: layer.lineWidth
                )
            }
        }
    }
}

// MARK: Sweep bar (Haunted VHS tracking bar)

/// Renders a `ThemeSweepBarSpec`: one full-width horizontal band with the
/// handoff's symmetric profile (transparent → shoulder → center → shoulder →
/// transparent) whose top edge travels `travelStart → travelEnd` (screen-height
/// fractions) once per `period`, linear infinite. A single gradient view on a
/// 20 fps timeline — no Canvas needed for one rect. Under Reduce Motion the
/// band parks at `travelStart` (the CSS 0% keyframe, off-screen above), which
/// is exactly the handoff's `prefers-reduced-motion: animation none` result.
struct SweepBarField: View {
    let spec: ThemeSweepBarSpec

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    var body: some View {
        Group {
            if reduceMotion {
                band(travel: spec.travelStart)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    let phase = spec.period > 0
                        ? timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: spec.period) / spec.period
                        : 0
                    band(travel: spec.travelStart + (spec.travelEnd - spec.travelStart) * phase)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func band(travel: Double) -> some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: spec.shoulderColor.opacity(spec.shoulderAlpha), location: 0.35),
                    .init(color: spec.centerColor.opacity(spec.centerAlpha), location: 0.50),
                    .init(color: spec.shoulderColor.opacity(spec.shoulderAlpha), location: 0.65),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: spec.height)
            .offset(y: proxy.size.height * travel)
        }
    }
}

// MARK: Radial spokes (art-direction lensing starburst)

/// The design's `.spin-ring`: thin conic spokes fanning from screen center,
/// rotating one full turn per `spec.period` — Event Horizon's gravitational
/// lensing. One batched wedge path per frame (90 wedges at the 2°/2°
/// cadence), no per-spoke views. Static at t = 0 under Reduce Motion.
struct RadialSpokeField: View {
    let spec: RadialSpokeSpec

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    Self.draw(context: context, size: size, time: 0, spec: spec)
                }
            } else {
                // Slowest motion in the theme (12°/s at period 30) — 10 fps
                // is visually continuous and half the atmosphere's budget.
                TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
                    Canvas { context, size in
                        Self.draw(
                            context: context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            spec: spec
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(context: GraphicsContext, size: CGSize, time: Double, spec: RadialSpokeSpec) {
        guard size.width > 0, size.height > 0, spec.period > 0, spec.segmentDegrees > 0 else { return }
        let phase = time.truncatingRemainder(dividingBy: spec.period) / spec.period
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Past every corner, so wedges cover the full surface at any angle.
        let reach = hypot(size.width, size.height) / 2 + 2

        let segment = Angle(degrees: spec.segmentDegrees).radians
        let baseRotation = phase * 2 * .pi
        var spokes = Path()
        var angle = 0.0
        while angle < 2 * .pi {
            let start = angle + baseRotation
            spokes.move(to: center)
            spokes.addArc(
                center: center,
                radius: reach,
                startAngle: .radians(start),
                endAngle: .radians(start + segment),
                clockwise: false
            )
            spokes.closeSubpath()
            angle += segment * 2   // lit spoke + equal gap
        }
        context.fill(spokes, with: .color(spec.hue.opacity(spec.spokeAlpha)))
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
