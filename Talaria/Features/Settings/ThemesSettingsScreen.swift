import SwiftUI

// #239: the theme cards, seasonal auto-rotation, and accent swatches moved
// here from AppearanceSettingsScreen — the card wall was burying Glow/Grid/
// App Icon/feel toggles on the top level. Pure relocation: same settings
// keys, same ThemeRuntime resolution. The screen carries its own
// HUDScreenBackground and resolves palettes per render, so picking a card
// re-skins THIS screen immediately, exactly as the single screen did
// (Owen's explicit #239 requirement, proven by the 239-B walk).
struct ThemesSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    /// The theme actually in effect — honors automatic (seasonal) mode (#24).
    private var theme: AppearanceTheme { settingsStore.settings.effectiveAppearanceTheme() }
    private var isAutomatic: Bool { settingsStore.settings.appearanceThemeMode == .automatic }
    private var accent: AppearanceAccent { settingsStore.settings.appearanceAccent }

    /// Same resolution rule as the parent screen: the adaptive theme renders
    /// with the runtime's mirrored scheme (see AppearanceSettingsScreen's
    /// `resolvedThemeID` doc for the fixed-theme mirror caveat).
    private func resolvedThemeID(_ theme: AppearanceTheme) -> ThemeID {
        theme.themeID(for: ThemeRuntime.shared.systemColorScheme)
    }

    /// Palette for the *selected* (theme, accent) — matches the live runtime
    /// because selection applies immediately.
    private var palette: ThemePalette { ThemePalette(theme: resolvedThemeID(theme), accent: accent.slot) }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Themes", subtitle: "Appearance") { dismiss() }
                    themeSection
                    // Locked themes (Terminal) offer no accent choice — their
                    // identity is the hero hue (#12).
                    if theme.themeID.lockedAccentSlot == nil {
                        accentSection
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Themes")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Theme", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            automaticPanel
            // Titled sections mirroring the gallery taxonomy (Lane E Task 0).
            // Availability still runs through the catalog per group: holiday
            // themes appear only in their window, an emptied group vanishes.
            ForEach(ThemeCatalog.sections) { section in
                themeGroup(section.title, section.definitions)
            }
        }
    }

    @ViewBuilder
    private func themeGroup(_ title: String, _ definitions: [ThemeDefinition]) -> some View {
        let available = ThemeCatalog.availableDefinitions(on: Date(), in: definitions)
        if !available.isEmpty {
            MonoLabel(title, size: 9, weight: .medium,
                      tracking: Design.Tracking.monoWide,
                      color: Design.Colors.dimForeground)
                .padding(.top, Design.Spacing.xxs)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Design.Spacing.sm),
                                GridItem(.flexible())],
                      spacing: Design.Spacing.sm) {
                ForEach(available) { themeCard($0) }
            }
        }
    }

    // MARK: Automatic (seasonal) mode

    /// Seasonal auto-rotation toggle (#24). When on, the app resolves the theme
    /// from the calendar; picking a card below switches back to manual.
    private var automaticPanel: some View {
        HStack {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("Seasonal (Auto)")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                MonoLabel(automaticCaption, size: 9, weight: .regular,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            }
            Spacer()
            Toggle("", isOn: automaticBinding)
                .labelsHidden()
                .tint(palette.base)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: isAutomatic ? Design.Colors.accentTint(0.3) : Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private var automaticCaption: String {
        if isAutomatic {
            return "\(ThemeCatalog.season(on: Date()).displayLabel.uppercased()) · \(theme.displayLabel.uppercased())"
        }
        return "Rotate theme by season"
    }

    private var automaticBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.appearanceThemeMode == .automatic },
            set: { settingsStore.settings.appearanceThemeMode = $0 ? .automatic : .manual }
        )
    }

    private func themeCard(_ definition: ThemeDefinition) -> some View {
        // Each card renders its own environment, resolved with the user's
        // current accent slot so it previews what they'd actually get.
        let t = definition.appearanceTheme
        let p = ThemePalette(theme: resolvedThemeID(t), accent: accent.slot)
        // In automatic mode the active season's theme reads as selected.
        let selected = (t == theme)
        return Button {
            // Picking a specific theme is a manual override (leaves auto mode).
            var updated = settingsStore.settings
            updated.appearanceThemeMode = .manual
            updated.appearanceTheme = t
            settingsStore.settings = updated
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
                    if definition.locked {
                        lockBadge(p)
                    }
                }
                .padding(.top, Design.Spacing.sm)

                MonoLabel(definition.displayName, size: 9, weight: .medium,
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
        // Lane J (J-5): pointer affordance on iPad — inert without a pointer.
        .hoverEffect(.highlight)
        .accessibilityLabel(definition.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Reserved premium/paid gate (#24). Inert today — no shipped theme is
    /// locked — but the affordance exists so a future tier is a flag flip.
    private func lockBadge(_ p: ThemePalette) -> some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(p.foreground)
            .padding(4)
            .background(Circle().fill(p.deep.opacity(0.85)))
            .offset(x: 15, y: -15)
    }

    // MARK: Accent

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Accent", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            HStack(spacing: Design.Spacing.md) {
                ForEach(AppearanceAccent.allCases, id: \.self) { accentSwatch($0) }
                Spacer()
                // Slot names come from the RESOLVED variant so the adaptive
                // theme labels its slots per the presented appearance
                // (Kapow Yellow by night, Ben-Day Cyan by day).
                MonoLabel(accent.displayLabel(for: resolvedThemeID(theme)).uppercased(),
                          size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: palette.base)
            }
            .padding(.horizontal, Design.Spacing.xs)
        }
    }

    private func accentSwatch(_ a: AppearanceAccent) -> some View {
        // The slot swatch shows the color the CURRENT theme resolves it to.
        let c = ThemePalette(theme: resolvedThemeID(theme), accent: a.slot)
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
        .hoverEffect(.highlight)
        // Scheme-resolved so VoiceOver names the swatch by the variant it
        // visibly renders (the adaptive theme's halves differ).
        .accessibilityLabel(a.displayLabel(for: resolvedThemeID(theme)))
    }
}
