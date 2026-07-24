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
    #if DEBUG
    @Environment(AppContainer.self) private var container
    // #127: local mirrors of MonetizationDebugSettings (UserDefaults-backed,
    // DEBUG-only) — seeded in onAppear, written through on change.
    @State private var monetizationGateEnabled = false
    // #137: one-shot feedback for the migration-stamp reset.
    @State private var migrationStampCleared = false
    @State private var entitlementOverride: MonetizationEntitlementOverride = .system
    #endif

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
                    #if DEBUG
                    generativeUISection
                    monetizationSection
                    sensorMigrationSection
                    #endif
                    buildSection
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Developer")
        .toolbarVisibility(.hidden, for: .navigationBar)
        #if DEBUG
        .onAppear {
            monetizationGateEnabled = MonetizationDebugSettings.gateEnabled
            entitlementOverride = MonetizationDebugSettings.entitlementOverride
        }
        #endif
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

            VStack(spacing: 0) {
                flagRow(
                    "Verbose Logging",
                    detail: "os_log · \(TalariaLog.subsystem)",
                    isOn: verboseLoggingBinding
                )

                Rectangle()
                    .fill(Design.Colors.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, Design.Spacing.md)

                flagRow(
                    "Composer Writing Tools",
                    detail: "FULL PANEL · .writingToolsBehavior(.complete)",
                    isOn: writingToolsBinding
                )
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )

            if settingsStore.settings.composerWritingToolsEnabled {
                Text("The full Writing Tools panel froze the device on iOS 27 beta 2. Leave this on only while re-testing on a newer beta (#4).")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Brand.forge)
            }
        }
    }

    private func flagRow(_ label: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(label)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                MonoLabel(detail, size: 8, weight: .regular,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    // MARK: Generative UI (IR v0 harness — DEBUG builds only, like this screen's
    // own SYSTEM-index link; GenUIDebugScreen is compiled out of Release)

    #if DEBUG
    /// #137: clears the grandfathering done-stamp so the next launch re-runs
    /// the migration. The stamp is MONOTONIC in shipping builds by design —
    /// clearing it on unpair would let a re-pair re-migrate an un-stamped,
    /// paired device and switch streaming and motion ON without consent. This
    /// exists so the fresh-install device pass does not require erasing the
    /// device, and it ships in no release build.
    private var sensorMigrationSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Sensor opt-in migration", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            Button {
                container.debugPersistence?.clearSensorStreamingMigrationStamp()
                withAnimation(Design.Motion.quickResponse) { migrationStampCleared = true }
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    StatusPip(color: migrationStampCleared ? Design.Brand.accent
                                                           : Design.Colors.mutedForeground,
                              diameter: 7)
                    Text("Clear migration stamp")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer(minLength: Design.Spacing.xs)
                    MonoLabel(migrationStampCleared ? "CLEARED · RELAUNCH" : "#137 · DEBUG ONLY",
                              size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: migrationStampCleared ? Design.Brand.accent
                                                           : Design.Colors.mutedForeground)
                        .lineLimit(1)
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

            Text("Clears BOTH halves of the stamp — UserDefaults and the Keychain mirror. "
                 + "Clearing only one reads as still-migrated. Relaunch to re-run grandfathering.")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.mutedForeground)
        }
    }

    private var generativeUISection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Generative UI", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            NavigationLink {
                GenUIDebugScreen()
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Text("IR v0 Harness")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer(minLength: Design.Spacing.xs)
                    MonoLabel("3 SAMPLE TREES", size: 9, weight: .medium,
                              tracking: Design.Tracking.mono,
                              color: Design.Colors.mutedForeground)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.mutedForeground)
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
    }
    // MARK: Monetization (#127 — device testing without sandbox purchases)
    //
    // The shipped gate is dormant (`MonetizationConfiguration.isEnabled` =
    // false). The toggle activates it for THIS DEBUG build; the override
    // then forces the entitlement answer — LOCKED shows the paywall at
    // every gated connect entry point, UNLOCKED opens them, SYSTEM keeps
    // the real StoreKit state so sandbox purchase/restore round-trips are
    // still testable with the gate live.

    private var monetizationSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Monetization", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                flagRow(
                    "Connect Gate",
                    detail: "FORCES monetizationEnabled · THIS BUILD ONLY",
                    isOn: monetizationGateBinding
                )

                Rectangle()
                    .fill(Design.Colors.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, Design.Spacing.md)

                overrideRow

                Rectangle()
                    .fill(Design.Colors.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, Design.Spacing.md)

                entitlementStatusRow
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private var overrideRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("Entitlement Override")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                MonoLabel("SYSTEM = REAL STOREKIT (SANDBOX OK)", size: 8, weight: .regular,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            }
            Spacer()
            Picker("", selection: overrideBinding) {
                ForEach(MonetizationEntitlementOverride.allCases, id: \.self) { value in
                    Text(value.rawValue.uppercased())
                        .font(Design.Typography.mono(10, weight: .medium))
                        .tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    /// Real data only: the live service's actual state + cache, so the
    /// override's effect can be compared against what StoreKit says.
    private var entitlementStatusRow: some View {
        HStack {
            MonoLabel("STOREKIT", size: 10, weight: .regular,
                      tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            Spacer()
            MonoLabel(entitlementStatusLabel, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.coolForeground)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private var entitlementStatusLabel: String {
        guard let entitlements = container.entitlementService else { return "—" }
        let state = switch entitlements.entitlementState {
        case .unknown: "UNKNOWN"
        case .entitled: "ENTITLED"
        case .notEntitled: "NOT ENTITLED"
        }
        let cache = switch entitlements.cachedEntitlement {
        case .some(true): "CACHE PAID"
        case .some(false): "CACHE FREE"
        case .none: "CACHE —"
        }
        return "\(state) · \(cache)"
    }

    private var monetizationGateBinding: Binding<Bool> {
        Binding(
            get: { monetizationGateEnabled },
            set: { newValue in
                monetizationGateEnabled = newValue
                MonetizationDebugSettings.gateEnabled = newValue
            }
        )
    }

    private var overrideBinding: Binding<MonetizationEntitlementOverride> {
        Binding(
            get: { entitlementOverride },
            set: { newValue in
                entitlementOverride = newValue
                MonetizationDebugSettings.entitlementOverride = newValue
            }
        )
    }
    #endif

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

    private var writingToolsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.composerWritingToolsEnabled },
            set: { settingsStore.settings.composerWritingToolsEnabled = $0 }
        )
    }
}
