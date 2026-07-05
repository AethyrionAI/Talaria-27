import SwiftUI
import UIKit

// MARK: - Appearance settings screen (Settings → APPEARANCE)
//
// HUD appearance prefs. Mirrors design/Settings.dc.html screen 06, extended
// with the theme system (design/THEME_SYSTEM_PLAN.md). Theme / accent / glow /
// grid / reduce-motion are PERSISTED to UserSettings and drive the whole app
// live via `ThemeRuntime` at the app root.
//
// Preview helpers here resolve `ThemePalette(theme:accent:)` DIRECTLY (not the
// live runtime) so each theme card can render its own environment while a
// different theme is active. The accent swatches show the slot colors as the
// *current* theme resolves them (hero-slot model — see ThemePaletteCore.swift).
struct AppearanceSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    @State private var spin = false

    private var theme: AppearanceTheme { settingsStore.settings.appearanceTheme }
    private var accent: AppearanceAccent { settingsStore.settings.appearanceAccent }
    private var glow: Double { settingsStore.settings.hudGlowIntensity }
    private var grid: GridDensity { settingsStore.settings.gridDensity }
    private var reduceMotion: Bool { settingsStore.settings.reduceMotion }

    /// Palette for the *selected* (theme, accent) — matches the live runtime
    /// once the app root mirrors the settings change.
    private var palette: ThemePalette { ThemePalette(theme: theme.themeID, accent: accent.slot) }

    /// The accent palette resolution actually uses. Locked themes (Terminal)
    /// pin to their hero slot (#12), so labels must not echo a stale stored
    /// accent while the screen renders the hero hue.
    private var effectiveAccent: AppearanceAccent {
        guard let locked = theme.themeID.lockedAccentSlot else { return accent }
        return AppearanceAccent(rawValue: locked.rawValue) ?? accent
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Appearance", subtitle: "Heads-Up Display") { dismiss() }
                    previewPanel
                    themeSection
                    // Locked themes (Terminal) offer no accent choice — their
                    // identity is the hero hue (#12).
                    if theme.themeID.lockedAccentSlot == nil {
                        accentSection
                    }
                    glowSection
                    gridSection
                    appIconRow
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
        let p = palette
        return ZStack {
            RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                .fill(LinearGradient(colors: p.screenGradientStops.map(\.color),
                                     startPoint: .top, endPoint: .bottom))

            previewGrid(p)
            previewBrackets(color: p.base)

            VStack {
                HStack {
                    MonoLabel("PREVIEW", size: 8, weight: .medium,
                              tracking: Design.Tracking.monoWide, color: p.mutedForeground)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    MonoLabel("REACTOR · GLOW \(String(format: "%.1f", glow))", size: 8, weight: .medium,
                              tracking: Design.Tracking.mono, color: p.base)
                }
            }
            .padding(Design.Spacing.sm)

            previewReactor(p)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                .strokeBorder(p.base.opacity(0.22), lineWidth: 1)
        }
    }

    private func previewReactor(_ p: ThemePalette) -> some View {
        ZStack {
            Circle()
                .strokeBorder(p.base.opacity(0.35), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(p.base, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(6)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 4).repeatForever(autoreverses: false), value: spin)
            Circle()
                .fill(RadialGradient(colors: [p.bright, p.base, p.deep],
                                     center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 13))
                .padding(16)
                .shadow(color: p.base.opacity(0.7 * p.glowScale), radius: max(2, 16 * glow))
        }
        .frame(width: 58, height: 58)
    }

    private func previewGrid(_ p: ThemePalette) -> some View {
        GridOverlay(cell: 22, lineColor: p.base.opacity(0.12), style: p.gridStyle)
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

    // MARK: Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Theme", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Design.Spacing.sm),
                                GridItem(.flexible())],
                      spacing: Design.Spacing.sm) {
                ForEach(AppearanceTheme.allCases, id: \.self) { themeCard($0) }
            }
        }
    }

    private func themeCard(_ t: AppearanceTheme) -> some View {
        // Each card renders its own environment, resolved with the user's
        // current accent slot so it previews what they'd actually get.
        let p = ThemePalette(theme: t.themeID, accent: accent.slot)
        let selected = (t == theme)
        return Button {
            settingsStore.settings.appearanceTheme = t
        } label: {
            VStack(spacing: Design.Spacing.xs) {
                ZStack {
                    Circle()
                        .strokeBorder(p.base.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                    Circle()
                        .fill(RadialGradient(colors: [p.bright, p.base, p.deep],
                                             center: UnitPoint(x: 0.5, y: 0.4),
                                             startRadius: 0, endRadius: 9))
                        .frame(width: 16, height: 16)
                        .shadow(color: p.base.opacity(0.6 * p.glowScale), radius: 6)
                }
                .padding(.top, Design.Spacing.sm)

                MonoLabel(t.displayLabel, size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: p.foreground)
                    .padding(.bottom, Design.Spacing.sm)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: p.screenGradientStops.map(\.color),
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(selected ? p.base.opacity(0.7) : p.hairline,
                                  lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: selected ? p.base.opacity(0.35 * p.glowScale) : .clear, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.displayLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Accent

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Accent", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            HStack(spacing: Design.Spacing.md) {
                ForEach(AppearanceAccent.allCases, id: \.self) { accentSwatch($0) }
                Spacer()
                MonoLabel(accent.displayLabel(for: theme).uppercased(), size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: palette.base)
            }
            .padding(.horizontal, Design.Spacing.xs)
        }
    }

    private func accentSwatch(_ a: AppearanceAccent) -> some View {
        // The slot swatch shows the color the CURRENT theme resolves it to.
        let c = ThemePalette(theme: theme.themeID, accent: a.slot)
        let selected = (a == accent)
        return Button {
            settingsStore.settings.appearanceAccent = a
        } label: {
            ZStack {
                if selected {
                    Circle()
                        .strokeBorder(c.base, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                        .shadow(color: c.base.opacity(0.45 * c.glowScale), radius: 6)
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
        .accessibilityLabel(a.displayLabel(for: theme))
    }

    // MARK: Glow

    private var glowSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                MonoLabel("// Glow Intensity", size: 10, tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                Spacer()
                MonoLabel(String(format: "%.1f", glow), size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: palette.base)
            }
            Slider(value: glowBinding, in: 0...1.6, step: 0.1)
                .tint(palette.base)
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
                    .strokeBorder(Design.Colors.hairline, lineWidth: 1)
            }
        }
    }

    private func gridSegment(_ d: GridDensity) -> some View {
        let selected = (d == grid)
        let c = palette.base
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

    // MARK: Reduce motion + theme summary

    private var togglePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reduce Motion")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Toggle("", isOn: reduceMotionBinding)
                    .labelsHidden()
                    .tint(palette.base)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)

            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
                .padding(.horizontal, Design.Spacing.md)

            HStack {
                Text("Theme")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                MonoLabel("\(theme.displayLabel) · \(effectiveAccent.displayLabel(for: theme))",
                          size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: palette.base)
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

    // MARK: App icon

    /// Navigates to the data-driven icon picker (issue #25). Shows the current
    /// icon's name so the row reads as real state, not a static label.
    private var appIconRow: some View {
        NavigationLink {
            AppIconSettingsScreen()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "app.badge")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: 32, height: 32)
                    .background(Design.Colors.accentTint(0.05),
                                in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                            .strokeBorder(Design.Colors.accentTint(0.18), lineWidth: 1)
                    }
                Text("App Icon")
                    .font(Design.Typography.body(15, weight: .medium))
                    .foregroundStyle(Design.Colors.foreground)
                Spacer(minLength: Design.Spacing.xs)
                MonoLabel(currentIconName.uppercased(), size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Design.Colors.accentTint(0.7))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private var currentIconName: String {
        AppIconCatalog.option(forAlternateIconName: UIApplication.shared.alternateIconName).displayName
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
}
