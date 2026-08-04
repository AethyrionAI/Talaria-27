import SwiftUI
import UIKit

// MARK: - Appearance settings screen (Settings → APPEARANCE)
//
// #244: a full-bleed theme CHANNEL browser (from Claude Design's mockup,
// routed by Owen 2026-08-04). One theme per channel; the LIVE app chrome is
// the canvas — a channel applies as you land on it, so the screen you're
// looking at IS the preview (#239's live-re-skin guarantee, by construction).
// Channel 00 is Seasonal AUTO; the rest are the catalog's picker identities
// in section order (ThemeChannels.build). Everything non-theme rehomes into
// the TUNING sheet: glow, grid, reduce motion, haptics, app icon. Accent
// slots render as three dots under the spectrum, hidden when the channel's
// theme pins its slot (Terminal, #12). Supersedes the #239 sub-screen and
// subsumes the #243 gallery idea.
struct AppearanceSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var channels: [ThemeChannels.Channel] = []
    @State private var selectedChannelID: String = ""
    @State private var showTuning = false
    @State private var sweepVisible = false

    // MARK: Applied state (the runtime mirrors these on write)

    private var theme: AppearanceTheme { settingsStore.settings.effectiveAppearanceTheme() }
    private var accent: AppearanceAccent { settingsStore.settings.appearanceAccent }
    private var glow: Double { settingsStore.settings.hudGlowIntensity }
    private var grid: GridDensity { settingsStore.settings.gridDensity }
    private var reduceMotion: Bool { systemReduceMotion || settingsStore.settings.reduceMotion }

    /// Render identity, honoring the adaptive theme's mirrored scheme — the
    /// same resolution (and the same known Comic Book preview limit) the
    /// previous screen documented.
    private func resolvedThemeID(_ theme: AppearanceTheme) -> ThemeID {
        theme.themeID(for: ThemeRuntime.shared.systemColorScheme)
    }

    /// Palette for one CHANNEL's content — resolved directly so a neighboring
    /// page mid-swipe renders its own colors before it applies on land.
    private func channelPalette(_ channel: ThemeChannels.Channel) -> ThemePalette {
        ThemePalette(theme: resolvedThemeID(channel.definition.appearanceTheme), accent: accent.slot)
    }

    private var currentChannel: ThemeChannels.Channel? {
        channels.first { $0.id == selectedChannelID }
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.top, Design.Spacing.xs)

                TabView(selection: $selectedChannelID) {
                    ForEach(channels) { channel in
                        channelContent(channel)
                            .tag(channel.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomControls
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.bottom, Design.Spacing.md)
            }

            if sweepVisible {
                sweepBand
            }
        }
        .navigationTitle("Appearance")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { configureChannels() }
        .onChange(of: selectedChannelID) { old, new in
            guard !old.isEmpty else { return }   // initial positioning is not a pick
            applyChannel(id: new)
            runSweep()
        }
        .sheet(isPresented: $showTuning) { tuningSheet }
    }

    // MARK: Channel list + apply

    private func configureChannels() {
        guard channels.isEmpty else { return }
        channels = ThemeChannels.build(on: Date())
        // Open on the channel matching current state: AUTO when automatic,
        // else the stored theme's channel (fallback: first).
        if settingsStore.settings.appearanceThemeMode == .automatic {
            selectedChannelID = "auto"
        } else {
            let stored = settingsStore.settings.appearanceTheme
            selectedChannelID = channels.first { $0.kind == .theme && $0.definition.appearanceTheme == stored }?.id
                ?? channels.first?.id ?? ""
        }
    }

    /// Apply-on-land (#244: "applies as you go"): the visible channel IS the
    /// applied theme. AUTO writes the mode; a theme channel writes the same
    /// atomic mode+theme pair the retired grid card wrote.
    private func applyChannel(id: String) {
        guard let channel = channels.first(where: { $0.id == id }) else { return }
        var updated = settingsStore.settings
        switch channel.kind {
        case .automatic:
            guard updated.appearanceThemeMode != .automatic else { return }
            updated.appearanceThemeMode = .automatic
        case .theme:
            let target = channel.definition.appearanceTheme
            guard updated.appearanceThemeMode != .manual || updated.appearanceTheme != target else { return }
            updated.appearanceThemeMode = .manual
            updated.appearanceTheme = target
        }
        settingsStore.settings = updated
    }

    private func step(_ delta: Int) {
        guard let index = channels.firstIndex(where: { $0.id == selectedChannelID }) else { return }
        let next = (index + delta + channels.count) % channels.count
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            selectedChannelID = channels[next].id
        }
    }

    private func surprise() {
        guard channels.count > 1,
              let index = channels.firstIndex(where: { $0.id == selectedChannelID }) else { return }
        var next = index
        while next == index { next = Int.random(in: 0 ..< channels.count) }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            selectedChannelID = channels[next].id
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            GlassCircleButton(icon: "chevron.left", accessibilityLabel: "Back") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 3) {
                MonoLabel("APPEARANCE", size: 9, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
                MonoLabel(counterText, size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.accent)
                    .accessibilityIdentifier("appearance.channelCounter")
            }
            Spacer()
            GlassCircleButton(icon: "arrow.clockwise", accessibilityLabel: "Surprise me") { surprise() }
        }
    }

    private var counterText: String {
        guard let index = channels.firstIndex(where: { $0.id == selectedChannelID }) else {
            return "CHANNEL \u{2014}"
        }
        return String(format: "CHANNEL %02d / %02d", index + 1, channels.count)
    }

    // MARK: Channel content

    private func channelContent(_ channel: ThemeChannels.Channel) -> some View {
        let palette = channelPalette(channel)
        let applied = isApplied(channel)
        return VStack(spacing: Design.Spacing.lg) {
            Spacer(minLength: Design.Spacing.md)

            channelOrb(channel, palette: palette, applied: applied)

            VStack(spacing: Design.Spacing.sm) {
                Text(channel.definition.displayName.uppercased())
                    .font(Design.Typography.display(40, weight: .bold, relativeTo: .largeTitle))
                    .tracking(1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(palette.isLight ? palette.foreground : palette.foregroundBright)

                MonoLabel(slotLine(channel), size: 11, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: palette.base)

                HStack(spacing: Design.Spacing.xs) {
                    if channel.definition.locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(palette.mutedForeground)
                    }
                    MonoLabel(channel.sectionTitle.uppercased(), size: 9, weight: .medium,
                              tracking: Design.Tracking.mono, color: palette.mutedForeground)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.xs)
                .overlay { Capsule().strokeBorder(palette.base.opacity(0.22), lineWidth: 1) }
            }

            Spacer(minLength: Design.Spacing.sm)

            spectrumStrip(palette)

            if !channel.locksAccent {
                accentDots(channel)
            }

            tuningHandle
        }
        .padding(.horizontal, Design.Spacing.lg)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(channel.kind == .automatic ? "Seasonal Auto" : channel.definition.displayName)
        .accessibilityAddTraits(applied ? .isSelected : [])
    }

    private func isApplied(_ channel: ThemeChannels.Channel) -> Bool {
        switch channel.kind {
        case .automatic: return settingsStore.settings.appearanceThemeMode == .automatic
        case .theme:
            return settingsStore.settings.appearanceThemeMode == .manual
                && settingsStore.settings.appearanceTheme == channel.definition.appearanceTheme
        }
    }

    /// The applied channel renders the REAL runtime orb (bespoke anatomies
    /// free); a neighboring page mid-swipe gets a generic ring in its own
    /// palette — it becomes the real orb the instant it applies on land.
    @ViewBuilder
    private func channelOrb(_ channel: ThemeChannels.Channel, palette: ThemePalette, applied: Bool) -> some View {
        if applied {
            ReactorOrb(size: 96, style: .standard, glowIntensity: glow)
        } else {
            ZStack {
                Circle().strokeBorder(palette.base.opacity(0.35), lineWidth: 1.5)
                Circle()
                    .fill(RadialGradient(colors: [palette.bright, palette.base, palette.deep],
                                         center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 24))
                    .padding(24)
                    .shadow(color: palette.base.opacity(0.7 * palette.glowScale), radius: max(2, 22 * glow))
            }
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
        }
    }

    private func slotLine(_ channel: ThemeChannels.Channel) -> String {
        let resolved = resolvedThemeID(channel.definition.appearanceTheme)
        if channel.kind == .automatic {
            return "\(ThemeCatalog.season(on: Date()).displayLabel.uppercased()) \u{00b7} \(accent.displayLabel(for: resolved).uppercased())"
        }
        return accent.displayLabel(for: resolved).uppercased()
    }

    // MARK: Spectrum strip (bright / base / deep / foreground / background)

    private func spectrumStrip(_ palette: ThemePalette) -> some View {
        let swatches: [Color] = [palette.bright, palette.base, palette.deep, palette.foreground, palette.background]
        return VStack(spacing: Design.Spacing.xxs) {
            HStack(spacing: 3) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { index, color in
                    UnevenRoundedRectangle(
                        topLeadingRadius: index == 0 ? 9 : 3,
                        bottomLeadingRadius: index == 0 ? 9 : 3,
                        bottomTrailingRadius: index == swatches.count - 1 ? 9 : 3,
                        topTrailingRadius: index == swatches.count - 1 ? 9 : 3
                    )
                    .fill(color)
                    .frame(height: 42)
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: index == 0 ? 9 : 3,
                            bottomLeadingRadius: index == 0 ? 9 : 3,
                            bottomTrailingRadius: index == swatches.count - 1 ? 9 : 3,
                            topTrailingRadius: index == swatches.count - 1 ? 9 : 3
                        )
                        .strokeBorder(palette.base.opacity(index == swatches.count - 1 ? 0.2 : 0), lineWidth: 1)
                    }
                }
            }
            HStack(spacing: 3) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                    MonoLabel(ThemeChannels.hexLabel(for: color), size: 7, weight: .regular,
                              tracking: 0.6, color: palette.mutedForeground)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Accent dots (mockup decision 1 — under the spectrum)

    private func accentDots(_ channel: ThemeChannels.Channel) -> some View {
        let resolved = resolvedThemeID(channel.definition.appearanceTheme)
        return HStack(spacing: Design.Spacing.md) {
            ForEach(AppearanceAccent.allCases, id: \.self) { a in
                let c = ThemePalette(theme: resolved, accent: a.slot)
                let selected = (a == accent)
                Button {
                    settingsStore.settings.appearanceAccent = a
                } label: {
                    ZStack {
                        if selected {
                            Circle()
                                .strokeBorder(c.base, lineWidth: 1.5)
                                .frame(width: 26, height: 26)
                                .shadow(color: c.base.opacity(0.45 * c.glowScale), radius: 5)
                        }
                        Circle()
                            .fill(c.base)
                            .frame(width: selected ? 16 : 20, height: selected ? 16 : 20)
                            .opacity(selected ? 1 : 0.85)
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(a.displayLabel(for: resolved))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Tuning handle + bottom controls

    private var tuningHandle: some View {
        Button {
            showTuning = true
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                MonoLabel("TUNING", size: 9, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Design.Brand.accent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle().fill(Design.Colors.hairline).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tuning")
    }

    private var bottomControls: some View {
        HStack(spacing: Design.Spacing.sm) {
            channelStepButton(icon: "chevron.left", label: "Previous theme") { step(-1) }
            GlowButton(title: "Surprise Me", height: 50) { surprise() }
            channelStepButton(icon: "chevron.right", label: "Next theme") { step(1) }
        }
    }

    private func channelStepButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Design.Brand.accentBright)
                .frame(width: 56, height: 50)
                .background(Design.Colors.accentTint(0.10),
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                        .strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Reboot sweep (gated on reduce motion)

    private var sweepBand: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, Design.Brand.accent.opacity(0.16), Design.Brand.accentBright.opacity(0.3), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: proxy.size.height * 0.46)
            .offset(y: sweepVisible ? proxy.size.height : -proxy.size.height * 0.46)
            .animation(.easeOut(duration: 0.62), value: sweepVisible)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func runSweep() {
        guard !reduceMotion else { return }
        sweepVisible = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            sweepVisible = false
        }
    }

    // MARK: Tuning sheet (the rehomed settings)

    private var tuningSheet: some View {
        NavigationStack {
            ZStack {
                Design.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Design.Spacing.lg) {
                        glowSection
                        gridSection
                        togglesPanel
                        appIconRow
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.top, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.md)
                }
            }
            .navigationTitle("Tuning")
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .presentationDetents([.height(420)])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(420)))
        .presentationDragIndicator(.visible)
    }

    private var glowSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                MonoLabel("// Glow", size: 10, tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                Spacer()
                MonoLabel(String(format: "%.1f", glow), size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.accent)
            }
            Slider(value: glowBinding, in: 0...1.6, step: 0.1)
                .tint(Design.Brand.accent)
                .padding(.horizontal, Design.Spacing.xxs)
        }
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Grid", size: 10, tracking: Design.Tracking.monoXWide,
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
        return Button {
            settingsStore.settings.gridDensity = d
        } label: {
            Text(d.displayLabel.uppercased())
                .font(Design.Typography.display(11, weight: .semibold, relativeTo: .caption))
                .tracking(Design.Tracking.button)
                .foregroundStyle(selected ? Design.Colors.background : Design.Colors.secondaryForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(selected ? Design.Brand.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private var togglesPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reduce Motion")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Toggle("", isOn: reduceMotionBinding)
                    .labelsHidden()
                    .tint(Design.Brand.accent)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)

            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
                .padding(.horizontal, Design.Spacing.md)

            // #238: relocated from the retired Notifications screen; #244
            // keeps it on the TUNING surface — feel, alongside motion.
            HStack {
                Text("Haptic Feedback")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Toggle("", isOn: hapticsBinding)
                    .labelsHidden()
                    .tint(Design.Brand.accent)
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
