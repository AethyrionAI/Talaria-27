import SwiftUI

// MARK: - Developer settings screen (Settings → DEVELOPER, sub-screen 12)
//
// Internal debug surface. Mirrors design/Settings-Additional.dc.html page 12,
// real-data-only:
//   • ENVIRONMENT lists only the environments this build actually permits
//     (availableEnvironments — Production-only in Release), with the real
//     endpoint string per environment.
//   • Verbose Logging is wired to real os_log via TalariaLog — flipping it
//     persists the flag and emits an observable notice line.
//   • The mockup's "Mock Responses" toggle is dropped (no real mock layer).
//   • COMMIT has no build-injected source, so it renders "—".
//
// The SYSTEM index only links here in DEBUG builds (the row is compiled out of
// Release), matching the "hidden in App Store builds" intent.
struct DeveloperSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Developer", subtitle: "Debug Builds Only") { dismiss() }
                    warningBanner
                    environmentSection
                    flagsSection
                    buildSection
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Developer")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: Warning

    private var warningBanner: some View {
        HStack(spacing: Design.Spacing.sm) {
            StatusPip(color: Design.Brand.forge, diameter: 7, blinks: true)
            Text("Internal tools — hidden in App Store builds.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Brand.forge)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Brand.forge.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                .strokeBorder(Design.Brand.forge.opacity(0.28), lineWidth: 1)
        }
    }

    // MARK: Environment

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Environment", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                let envs = settingsStore.availableEnvironments
                ForEach(Array(envs.enumerated()), id: \.element) { index, env in
                    environmentRow(env)
                    if index < envs.count - 1 {
                        Rectangle()
                            .fill(Design.Colors.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Design.Spacing.md)
                    }
                }
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func environmentRow(_ env: AppEnvironment) -> some View {
        let selected = settingsStore.settings.environment == env
        return Button {
            withAnimation(Design.Motion.quickResponse) {
                settingsStore.settings.environment = env
            }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                StatusPip(color: selected ? Design.Brand.accent : Design.Colors.mutedForeground, diameter: 7)
                Text(env.displayLabel)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer(minLength: Design.Spacing.xs)
                MonoLabel(endpointLabel(env), size: 9, weight: .medium,
                          tracking: Design.Tracking.mono,
                          color: selected ? Design.Brand.accent : Design.Colors.mutedForeground)
                    .lineLimit(1)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Real endpoint string for an environment. Production/Staging route through
    /// the configured relay (no hardcoded host), so they show the relay origin or
    /// "—" when none is configured.
    private func endpointLabel(_ env: AppEnvironment) -> String {
        if !env.baseURLString.isEmpty {
            return env.baseURLString.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
        }
        let origin = settingsStore.settings.relayConfiguration.relayOriginLabel
        return origin == "Not Configured" ? "—" : origin
    }

    // MARK: Flags

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Flags", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            HStack {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text("Verbose Logging")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    MonoLabel("os_log · \(TalariaLog.subsystem)", size: 8, weight: .regular,
                              tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                }
                Spacer()
                Toggle("", isOn: verboseLoggingBinding)
                    .labelsHidden()
                    .tint(Design.Brand.accent)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    // MARK: Build

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Build", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: Design.Spacing.sm) {
                buildRow("VERSION", appShortVersion, Design.Colors.coolForeground)
                buildRow("BUILD", appBuildNumber, Design.Colors.coolForeground)
                buildRow("COMMIT", "—", Design.Colors.mutedForeground)
            }
            .padding(Design.Spacing.md)
            .background(Design.Colors.background,
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.accentTint(0.14), lineWidth: 1)
            }
        }
    }

    private func buildRow(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack {
            MonoLabel(label, size: 10, weight: .regular,
                      tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            Spacer()
            MonoLabel(value, size: 11, weight: .medium,
                      tracking: Design.Tracking.mono, color: valueColor)
        }
    }

    // MARK: Derived

    private var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "—"
    }

    // MARK: Bindings

    private var verboseLoggingBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.verboseLogging },
            set: { newValue in
                settingsStore.settings.verboseLogging = newValue
                TalariaLog.setVerbose(newValue)
            }
        )
    }
}
