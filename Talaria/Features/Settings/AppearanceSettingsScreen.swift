import SwiftUI

// MARK: - Appearance settings screen (Settings → APPEARANCE)
//
// HUD appearance prefs. Mirrors design/Settings.dc.html screen 06. These are
// PERSISTED to UserSettings and now drive the whole app live: accent / glow /
// grid / reduce-motion are mirrored into `ThemeRuntime` at the app root, so the
// `Design.*` accent tokens re-skin every surface on change. The on-screen PREVIEW
// mirrors the same prefs; the Theme row reflects the active accent (the deep
// "Deep Field" background is fixed — the single field option).
struct AppearanceSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    @State private var spin = false

    private var accent: AppearanceAccent { settingsStore.settings.appearanceAccent }
    private var glow: Double { settingsStore.settings.hudGlowIntensity }
    private var grid: GridDensity { settingsStore.settings.gridDensity }
    private var reduceMotion: Bool { settingsStore.settings.reduceMotion }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Appearance", subtitle: "Heads-Up Display") { dismiss() }
                    previewPanel
                    accentSection
                    glowSection
                    gridSection
                    togglePanel
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Appearance")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear { spin = true }
    }

    // MARK: Preview

    private var previewPanel: some View {
        let c = accentColors(accent)
        return ZStack {
            RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                .fill(LinearGradient(colors: [Color(hex: 0x0C2730), Color(hex: 0x04070C)],
                                     startPoint: .top, endPoint: .bottom))

            previewGrid(color: c.base)
            previewBrackets(color: c.base)

            VStack {
                HStack {
                    MonoLabel("PREVIEW", size: 8, weight: .medium,
                              tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    MonoLabel("REACTOR · GLOW \(String(format: "%.1f", glow))", size: 8, weight: .medium,
                              tracking: Design.Tracking.mono, color: c.base)
                }
            }
            .padding(Design.Spacing.sm)

            previewReactor(c)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                .strokeBorder(c.base.opacity(0.22), lineWidth: 1)
        }
    }

    private func previewReactor(_ c: AccentColors) -> some View {
        ZStack {
            Circle()
                .strokeBorder(c.base.opacity(0.35), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(c.base, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(6)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 4).repeatForever(autoreverses: false), value: spin)
            Circle()
                .fill(RadialGradient(colors: [c.bright, c.base, c.deep],
                                     center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 13))
                .padding(16)
                .shadow(color: c.base.opacity(0.7), radius: max(2, 16 * glow))
        }
        .frame(width: 58, height: 58)
    }

    private func previewGrid(color: Color) -> some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(color.opacity(0.12)), lineWidth: 1)
        }
        .opacity(gridPreviewOpacity)
    }

    private var gridPreviewOpacity: Double {
        switch grid {
        case .off:   0.0
        case .faint: 0.55
        case .bold:  1.0
        }
    }

    private func previewBrackets(color: Color) -> some View {
        VStack {
            HStack {
                previewCorner(color, .degrees(0))
                Spacer()
                previewCorner(color, .degrees(90))
            }
            Spacer()
            HStack {
                previewCorner(color, .degrees(-90))
                Spacer()
                previewCorner(color, .degrees(180))
            }
        }
        .padding(Design.Spacing.sm)
    }

    private func previewCorner(_ color: Color, _ rotation: Angle) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 14))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(color.opacity(0.55), lineWidth: 1.5)
        .frame(width: 14, height: 14)
        .rotationEffect(rotation)
    }

    // MARK: Accent

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Accent", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            HStack(spacing: Design.Spacing.md) {
                ForEach(AppearanceAccent.allCases, id: \.self) { accentSwatch($0) }
                Spacer()
                MonoLabel(accent.displayLabel.uppercased(), size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: accentColors(accent).base)
            }
            .padding(.horizontal, Design.Spacing.xs)
        }
    }

    private func accentSwatch(_ a: AppearanceAccent) -> some View {
        let c = accentColors(a)
        let selected = (a == accent)
        return Button {
            settingsStore.settings.appearanceAccent = a
        } label: {
            ZStack {
                if selected {
                    Circle()
                        .strokeBorder(c.base, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                        .shadow(color: c.base.opacity(0.45), radius: 6)
                }
                Circle()
                    .fill(c.base)
                    .frame(width: selected ? 24 : 30, height: selected ? 24 : 30)
                    .opacity(selected ? 1 : 0.85)
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a.displayLabel)
    }

    // MARK: Glow

    private var glowSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                MonoLabel("// Glow Intensity", size: 10, tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                Spacer()
                MonoLabel(String(format: "%.1f", glow), size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: accentColors(accent).base)
            }
            Slider(value: glowBinding, in: 0...1.6, step: 0.1)
                .tint(accentColors(accent).base)
                .padding(.horizontal, Design.Spacing.xxs)
        }
    }

    // MARK: Grid density

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Grid Density", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            HStack(spacing: Design.Spacing.xxs) {
                ForEach(GridDensity.allCases, id: \.self) { gridSegment($0) }
            }
            .padding(Design.Spacing.xxs)
            .background(Design.Colors.background.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.cyanHairline, lineWidth: 1)
            }
        }
    }

    private func gridSegment(_ d: GridDensity) -> some View {
        let selected = (d == grid)
        let c = accentColors(accent).base
        return Button {
            settingsStore.settings.gridDensity = d
        } label: {
            Text(d.displayLabel.uppercased())
                .font(Design.Typography.display(11, weight: .semibold, relativeTo: .caption))
                .tracking(Design.Tracking.button)
                .foregroundStyle(selected ? Design.Colors.background : Design.Colors.secondaryForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(selected ? c : Color.clear,
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: Reduce motion + theme (locked)

    private var togglePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reduce Motion")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Toggle("", isOn: reduceMotionBinding)
                    .labelsHidden()
                    .tint(accentColors(accent).base)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)

            Rectangle()
                .fill(Design.Colors.cyanHairline)
                .frame(height: 1)
                .padding(.horizontal, Design.Spacing.md)

            HStack {
                Text("Theme")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                MonoLabel("Deep Field · \(accent.displayLabel)", size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: accentColors(accent).base)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    // MARK: Bindings

    private var glowBinding: Binding<Double> {
        Binding(
            get: { settingsStore.settings.hudGlowIntensity },
            set: { settingsStore.settings.hudGlowIntensity = $0 }
        )
    }

    private var reduceMotionBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.reduceMotion },
            set: { settingsStore.settings.reduceMotion = $0 }
        )
    }

    // MARK: Accent colors

    private struct AccentColors {
        let base: Color
        let bright: Color
        let deep: Color
    }

    private func accentColors(_ a: AppearanceAccent) -> AccentColors {
        switch a {
        case .cyan:   AccentColors(base: Color(hex: 0x54E6F0), bright: Color(hex: 0xCDF8FB), deep: Color(hex: 0x14636E))
        case .amber:  AccentColors(base: Color(hex: 0xFFC14D), bright: Color(hex: 0xFFE2A6), deep: Color(hex: 0x6E4D14))
        case .violet: AccentColors(base: Color(hex: 0xB18CFF), bright: Color(hex: 0xE2D4FF), deep: Color(hex: 0x3A2D6E))
        }
    }
}
