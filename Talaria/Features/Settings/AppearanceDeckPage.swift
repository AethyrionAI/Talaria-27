import SwiftUI
import UIKit

// MARK: - #252 Appearance deck page
//
// The deck entry for the #244 channel browser — a spectrum hero + read-only
// tuning values + the handoff button. The browser itself is UNCHANGED; this
// page never duplicates its controls.
struct AppearanceDeckPage: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.lg) {
                spectrumHero
                infoPanel
                NavigationLink { AppearanceSettingsScreen() } label: {
                    MonoLabel("OPEN CHANNEL BROWSER", size: 12, weight: .bold,
                              tracking: Design.Tracking.monoWide,
                              color: Design.Colors.foregroundBright)
                        .padding(.vertical, Design.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .hudPanel(cornerRadius: Design.CornerRadius.lg,
                                  borderColor: Design.Colors.strongBorder,
                                  fill: Design.Colors.accentTint(0.12), innerGlow: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.appearance.openBrowser")
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
    }

    private var spectrumHero: some View {
        VStack(spacing: Design.Spacing.sm) {
            RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                .fill(LinearGradient(
                    colors: [Design.Colors.background,
                             Design.Brand.accentDeep,
                             Design.Brand.accent,
                             Design.Brand.accentBright],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 140)
                .overlay(alignment: .bottomLeading) {
                    MonoLabel(channelLabel, size: 12, weight: .bold,
                              tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.background)
                        .padding(Design.Spacing.md)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                        .strokeBorder(Design.Colors.strongBorder, lineWidth: 1)
                }
                .accessibilityHidden(true)
            Text(themeName.uppercased())
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)
            MonoLabel(accentLine, size: 11, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Brand.accent)
        }
    }

    private var infoPanel: some View {
        VStack(spacing: 0) {
            infoRow("GLOW", String(format: "%.1f×", settingsStore.settings.hudGlowIntensity))
            divider
            infoRow("GRID", settingsStore.settings.gridDensity.displayLabel.uppercased())
            divider
            infoRow("APP ICON", currentIconName)
        }
        .hudPanel(cornerRadius: Design.CornerRadius.lg,
                  borderColor: Design.Colors.accentTint(0.14),
                  fill: Design.Colors.background.opacity(0.5), innerGlow: false)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            MonoLabel(label, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)
            Spacer()
            MonoLabel(value, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.foreground)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private var divider: some View {
        Rectangle().fill(Design.Colors.hairline).frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    private var themeName: String { ThemeRuntime.shared.theme.displayLabel }

    private var accentLine: String {
        ThemeRuntime.shared.accent.displayLabel(for: ThemeRuntime.shared.theme).uppercased()
    }

    // Same channel list the #244 browser counts with (AppearanceSettingsScreen
    // builds `ThemeChannels.build(on:)` and indexes into it — SettingsChannelsScreen's
    // `currentChannelIndex` does the identical lookup for the grid card).
    private var channelLabel: String {
        let channels = ThemeChannels.build(on: Date())
        let index: Int?
        if settingsStore.settings.appearanceThemeMode == .automatic {
            index = channels.firstIndex { $0.id == "auto" }
        } else {
            let stored = settingsStore.settings.appearanceTheme
            index = channels.firstIndex { $0.kind == .theme && $0.definition.appearanceTheme == stored }
        }
        guard let index else { return "CHANNEL —" }
        return String(format: "CHANNEL %02d", index)
    }

    // `AppIconCatalog.option(forAlternateIconName:)` returns a non-optional
    // `AppIconOption` (falls back to `.primary` internally) — mirrors the
    // Tuning sheet's App Icon row (AppearanceSettingsScreen.currentIconName),
    // which reads the same way with no optional chaining.
    private var currentIconName: String {
        AppIconCatalog.option(forAlternateIconName: UIApplication.shared.alternateIconName)
            .displayName.uppercased()
    }
}
