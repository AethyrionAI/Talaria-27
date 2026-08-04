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

    /// The theme actually in effect — honors automatic (seasonal) mode (#24).
    private var theme: AppearanceTheme { settingsStore.settings.effectiveAppearanceTheme() }
    private var accent: AppearanceAccent { settingsStore.settings.appearanceAccent }
    private var glow: Double { settingsStore.settings.hudGlowIntensity }
    private var grid: GridDensity { settingsStore.settings.gridDensity }
    private var reduceMotion: Bool { settingsStore.settings.reduceMotion }

    /// Render identity for a theme as this screen previews it: the adaptive
    /// Comic Book resolves with the runtime's mirrored scheme, so its card
    /// and swatches show the variant matching the PRESENTED surface —
    /// identical to live resolution whenever Comic Book is active. Known
    /// limit (Lane L Phase 2, noted in the PR): while a FIXED theme is
    /// active the mirror reads that theme's forced scheme, so on a device
    /// whose system appearance differs, the Comic Book card previews the
    /// other half than selecting it will produce. SwiftUI offers no
    /// un-forced system-scheme read inside the overridden window; a
    /// screen-traits reader is the candidate follow-up if the Mac pass
    /// wants the stricter behavior.
    private func resolvedThemeID(_ theme: AppearanceTheme) -> ThemeID {
        theme.themeID(for: ThemeRuntime.shared.systemColorScheme)
    }

    /// #239: the Themes navRow value — seasonal mode surfaces the season so
    /// automatic rotation stays legible from the top level.
    nonisolated static func themesRowValue(settings: UserSettings, on date: Date = Date()) -> String {
        let theme = settings.effectiveAppearanceTheme(on: date)
        guard settings.appearanceThemeMode == .automatic else {
            return theme.displayLabel.uppercased()
        }
        return "\(ThemeCatalog.season(on: date).displayLabel.uppercased()) · \(theme.displayLabel.uppercased())"
    }

    /// Palette for the *selected* (theme, accent) — matches the live runtime
    /// once the app root mirrors the settings change.
    private var palette: ThemePalette { ThemePalette(theme: resolvedThemeID(theme), accent: accent.slot) }

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
                    themesNavRow
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

    // MARK: Themes navRow (#239)

    /// The theme cards + accents live one level down (ThemesSettingsScreen);
    /// this row surfaces the resolved state so automatic mode stays legible
    /// from the top level.
    private var themesNavRow: some View {
        NavigationLink {
            ThemesSettingsScreen()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: 32, height: 32)
                    .background(Design.Colors.accentTint(0.05),
                                in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                            .strokeBorder(Design.Colors.accentTint(0.18), lineWidth: 1)
                    }
                Text("Themes")
                    .font(Design.Typography.body(15, weight: .medium))
                    .foregroundStyle(Design.Colors.foreground)
                Spacer(minLength: Design.Spacing.xs)
                MonoLabel(Self.themesRowValue(settings: settingsStore.settings),
                          size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Design.Colors.accentTint(0.7))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.lg,
                      borderColor: Design.Colors.accentTint(0.12),
                      fill: Design.Colors.background.opacity(0.5),
                      innerGlow: false)
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    private func previewReactor(_ p: ThemePalette) -> some View {
        // Bespoke orb anatomies (Event Horizon's singularity and the gallery
        // ports) preview the real composition. Safe to read the live orb
        // here: the preview panel's (theme, accent) always mirrors the
        // runtime — selection applies immediately — so `ReactorOrb`'s
        // runtime-resolved palette matches `p`. The four flagship styles
        // keep the generic glyph below, unchanged.
        let flagshipStyles: [ThemeOrbStyle] = [.arcReactor, .forgeSun, .crtCrosshair, .paperReel]
        if !flagshipStyles.contains(p.orbStyle) {
            ReactorOrb(size: 58, style: .standard, glowIntensity: glow)
        } else {
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
        .hoverEffect(.highlight)
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

            // #238: relocated from the retired Notifications settings screen —
            // haptics is experience feedback, so it lives with the other
            // feel toggles.
            HStack {
                Text("Haptic Feedback")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Toggle("", isOn: hapticsBinding)
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
                MonoLabel("\(theme.displayLabel) · \(effectiveAccent.displayLabel(for: resolvedThemeID(theme)))",
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

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hapticFeedbackEnabled },
            set: { settingsStore.settings.hapticFeedbackEnabled = $0 }
        )
    }
}
