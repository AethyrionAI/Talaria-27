import SwiftUI

// MARK: - Subsystem hero (#252 Task 7)
//
// The deck-page identity block every embedded sub-screen shows at the top of
// its scroll content: a per-subsystem motif drawing (~120pt, plain SwiftUI
// shapes — see Talaria/Core/HUD/ReactorOrb.swift / GridOverlay.swift for the
// project's shape-drawing idiom), a big title, a live status line fed by the
// HOST screen's own authoritative computed property (never re-derived here),
// and a muted chip capsule naming the subsystem's card label
// (`SettingsSubsystem.chip`). Standalone presentation is untouched — screens
// that already render an equivalent top panel (Voice `heroPanel`, Uplink's
// link status panel) wrap that panel in `if !embedded` so only the deck shows
// this hero.
struct SubsystemHero: View {
    enum Motif {
        case rings, profileBars, barChart, waveform, hatchShield, stackedRows, sparkline, squares
    }

    let motif: Motif
    let title: String
    let status: String
    let statusColor: Color
    let chip: String
    let accented: Bool

    private var tint: Color { accented ? Design.Brand.accent : Design.Colors.mutedForeground }

    var body: some View {
        VStack(spacing: Design.Spacing.sm) {
            motifView
                .frame(width: Design.Size.thumbnailMedium, height: Design.Size.thumbnailMedium)
                .accessibilityHidden(true)

            Text(title)
                .font(Design.Typography.heroTitle)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            MonoLabel(status, size: 11, weight: .medium,
                      tracking: Design.Tracking.mono, color: statusColor)

            MonoLabel(chip, size: 9, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
                .padding(.horizontal, Design.Spacing.sm)
                .padding(.vertical, Design.Spacing.xxs)
                .overlay {
                    Capsule().strokeBorder(Design.Colors.accentTint(0.18), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing.sm)
        .padding(.bottom, Design.Spacing.xs)
    }

    @ViewBuilder
    private var motifView: some View {
        switch motif {
        case .rings: RingsMotif(tint: tint)
        case .profileBars: ProfileBarsMotif(tint: tint)
        case .barChart: BarChartMotif(tint: tint)
        case .waveform: WaveformMotif(tint: tint)
        case .hatchShield: HatchShieldMotif(tint: tint)
        case .stackedRows: StackedRowsMotif(tint: tint)
        case .sparkline: SparklineMotif(tint: tint)
        case .squares: SquaresMotif(tint: tint)
        }
    }
}

// MARK: - Motifs (each a plain-shape drawing, ≤40 lines)

/// Uplink — concentric rings around a solid core (the link/broadcast motif).
private struct RingsMotif: View {
    let tint: Color
    var body: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { i in
                Circle()
                    .strokeBorder(tint.opacity(0.9 - Double(i) * 0.25), lineWidth: 2)
                    .frame(width: 120 - CGFloat(i) * 28, height: 120 - CGFloat(i) * 28)
            }
            Circle()
                .fill(tint.opacity(0.85))
                .frame(width: 18, height: 18)
        }
    }
}

/// Server — stacked outlined bars (the backend-profile stack).
private struct ProfileBarsMotif: View {
    let tint: Color
    private let heights: [CGFloat] = [46, 78, 60]
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(tint.opacity(i == 1 ? 1 : 0.5), lineWidth: 2)
                    .frame(width: 28, height: heights[i])
            }
        }
        .frame(height: 90, alignment: .bottom)
    }
}

/// Models — a filled bar chart (the model catalog motif).
private struct BarChartMotif: View {
    let tint: Color
    private let heights: [CGFloat] = [28, 52, 40, 78, 50]
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.35 + Double(i) * 0.12))
                    .frame(width: 14, height: heights[i])
            }
        }
        .frame(height: 90, alignment: .bottom)
    }
}

/// Voice — thin waveform bars (the talk-engine motif).
private struct WaveformMotif: View {
    let tint: Color
    private let heights: [CGFloat] = [18, 38, 62, 88, 62, 38, 18, 46, 26]
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(tint.opacity(0.9))
                    .frame(width: 4, height: heights[i])
            }
        }
        .frame(height: 90)
    }
}

/// Privacy — a hatched hexagon (permissions/shield motif): a repeating
/// diagonal gradient clipped to a hexagon, with a solid rim.
private struct HatchShieldMotif: View {
    let tint: Color

    private var hatchGradient: LinearGradient {
        let stops = (0 ..< 20).map { i -> Gradient.Stop in
            .init(color: tint.opacity(i.isMultiple(of: 2) ? 0.45 : 0.08), location: Double(i) / 20)
        }
        return LinearGradient(gradient: Gradient(stops: stops),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(hatchGradient)
                .clipShape(HexagonShape())
            HexagonShape().stroke(tint, lineWidth: 2.5)
        }
        .frame(width: 108, height: 108)
    }
}

private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = (0 ..< 6).map { i -> CGPoint in
            let angle = Angle.degrees(Double(i) * 60 - 90).radians
            return CGPoint(x: rect.midX + rect.width / 2 * CGFloat(cos(angle)),
                            y: rect.midY + rect.height / 2 * CGFloat(sin(angle)))
        }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// Sessions — stacked outlined rows (the session-shelf motif).
private struct StackedRowsMotif: View {
    let tint: Color
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0 ..< 4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(tint.opacity(i == 0 ? 1 : 0.5), lineWidth: 1.5)
                    .frame(width: 112 - CGFloat(i) * 14, height: 16)
            }
        }
    }
}

/// Diagnostics — a sparkline path (the health-trend motif).
private struct SparklineMotif: View {
    let tint: Color
    private let points: [CGFloat] = [0.5, 0.3, 0.6, 0.2, 0.55, 0.15, 0.4, 0.1]
    var body: some View {
        Path { path in
            let step = CGFloat(120) / CGFloat(points.count - 1)
            for (i, p) in points.enumerated() {
                let point = CGPoint(x: CGFloat(i) * step, y: 70 * p)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        .frame(width: 120, height: 70)
    }
}

/// Developer — a 3×3 grid of squares (the internal-tools motif).
private struct SquaresMotif: View {
    let tint: Color
    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 3)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0 ..< 9, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint.opacity(i.isMultiple(of: 2) ? 0.75 : 0.3))
                    .frame(width: 28, height: 28)
            }
        }
    }
}
