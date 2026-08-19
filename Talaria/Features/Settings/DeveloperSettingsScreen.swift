import SwiftUI
import Foundation
import UIKit

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
// The SYSTEM index links here in EVERY build since #231/#228: Release needs a
// reachable Verbose Logging toggle for the production tool-call instrument, and
// the screen is Release-clean (DEBUG-only sections individually compiled out).
// Re-hiding for App Store builds is a Phase 7 decision, flagged in #231.
struct DeveloperSettingsScreen: View {
    // #252: deck pages supply the background and top bar; the screen keeps
    // owning its content, tasks, and sheets in both presentations.
    var embedded: Bool = false
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
            if !embedded {
                HUDScreenBackground()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if !embedded {
                        SettingsScreenHeader(title: "Developer", subtitle: "Internal Tools") { dismiss() }
                    }
                    if embedded {
                        SubsystemHero(
                            motif: .squares,
                            title: SettingsSubsystem.developer.title,
                            status: SettingsCardValues.developer(
                                environmentLabel: settingsStore.settings.environment.displayLabel),
                            statusColor: Design.Colors.mutedForeground,
                            chip: SettingsSubsystem.developer.chip,
                            accented: false
                        )
                    }
                    warningBanner
                    environmentSection
                    flagsSection
                    #if DEBUG
                    generativeUISection
                    monetizationSection
                    sensorMigrationSection
                    #endif
                    buildSection
                    #if DEBUG
                    batteriesSection   // #252: relocated verbatim from DiagnosticsSettingsScreen (#200 harness)
                    #endif
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
            Text("Internal tools — visible in all builds until launch (#231).")
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

                Rectangle()
                    .fill(Design.Colors.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, Design.Spacing.md)

                flagRow(
                    "Runs Transport (Phase 3)",
                    detail: "Default since the #368 cutover · off = legacy sessions plane",
                    isOn: runsTransportBinding
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

    /// #283: no side effect — the client reads this through
    /// `SessionsHermesClient.useRunsTransportProvider`, armed once at launch.
    /// #368 (3E): ON is now the default; this row is the one-week escape
    /// hatch Owen's 2026-08-19 ruling kept, and #382 removes it.
    private var runsTransportBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.useRunsTransport },
            set: { settingsStore.settings.useRunsTransport = $0 }
        )
    }

    // MARK: Batteries (#200 harness — relocated by #252)
    #if DEBUG

    private var batteriesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Batteries (#200 harness)")
            localBrainPanel
            throwawayLiveActivityPanel
        }
    }

    // MARK: Throwaway Live Activity (#250 R2, DEBUG builds only)
    //
    // Device row §R2 — "the Dynamic Island wears the selected icon" — was a
    // standing watch because the island is untriggerable on demand. This starts
    // a THROWAWAY instance of the REAL activity through the production
    // `LiveActivityService`, so what the island renders is what a real run
    // renders. Tap, look at the island's leading icon slot, compare against
    // Settings → Appearance → App Icon.
    //
    // The harness is `ThrowawayLiveActivityHarness.shared`, not a `@State` on
    // this view, precisely so the auto-end outlives the screen.

    private var throwawayLiveActivityPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Live Activity — #250 R2", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            MonoLabel("Starts a labelled THROWAWAY activity through the real LiveActivityService. Compare the island's leading icon against Settings → Appearance → App Icon. Ends itself after \(throwawayAutoEndSeconds)s, or tap again.",
                      size: 9, tracking: Design.Tracking.mono,
                      color: Design.Colors.secondaryForeground)
            GhostButton(
                title: throwawayHarness.isRunning
                    ? "End throwaway"
                    : "Start throwaway Live Activity (#250 R2)",
                systemImage: throwawayHarness.isRunning ? "stop.circle" : "bolt.fill",
                height: 40
            ) {
                throwawayHarness.toggle()
            }
            if !throwawayHarness.service.isAvailable {
                MonoLabel("Live Activities are disabled for Talaria — enable them in Settings → Talaria → Live Activities, or nothing will appear.",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Brand.forge)
            } else if throwawayHarness.isRunning {
                MonoLabel("Running — long-press the island to expand it. Auto-ends in ≤\(throwawayAutoEndSeconds)s.",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Brand.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private var throwawayHarness: ThrowawayLiveActivityHarness {
        ThrowawayLiveActivityHarness.shared
    }

    private var throwawayAutoEndSeconds: Int {
        Int(throwawayHarness.autoEndAfter.components.seconds)
    }

    private func groupLabel(_ text: String) -> some View {
        MonoLabel(text, size: 10, tracking: Design.Tracking.monoXWide,
                  color: Design.Colors.mutedForeground)
    }

    // MARK: Local brain — forced-trip harness (#134, DEBUG builds only)
    //
    // Device-verification trigger for the merged #102 breaker + #110 speech
    // retraction: drives a synthetic degenerate stream through the REAL
    // on-device chat path (the live model's guardrails defeat organic loop
    // repros). The reply in the chat collapses to one copy of the loop unit,
    // Console shows the #102 escalation notice, and — with read-aloud on —
    // speech cuts instead of droning the loop.

    private enum ForcedTripState: Equatable {
        case idle
        case running
        case done
    }

    @State private var forcedTripState: ForcedTripState = .idle
    // #196: mirrors the persisted debug.sessionShape override; seeded from
    // defaults so the picker reflects the pending (next-launch) cell,
    // normalized through SessionShape so a RETIRED cell name ("armed-noprose"
    // from 176C, "armed-direct"/"armed-noneg" from the first battery) can't
    // leave the control unselected — it lands on production, by design.
    // Post-promotion (2026-07-28) production = armed-routed.
    @State private var sessionShapeOverride: String =
        LocalChatBackend.SessionShape(
            rawValue: UserDefaults.standard.string(forKey: "debug.sessionShape") ?? "armed-routed"
        )?.rawValue ?? "armed-routed"
    // #196: guards the one-tap rate battery against double-fires.
    @State private var batteryRunning = false

    // #333: ONE factory for every instrument button. The action is the same
    // conductor call the launch-env trigger makes — bar 333-B's "one code
    // path" is this line, not a resemblance between two of them. The
    // conductor owns ALL flag discipline (accept / decline / attended-alarms)
    // and the idle-timer lock, so a button sets none of them: that is why the
    // deleted factories' twelve hand-copied flag lines apiece are gone rather
    // than moved. `batteryRunning` stays a UI-only double-fire guard; the real
    // mutex is backend-owned (`beginBatteryRun`).
    @ViewBuilder
    private func instrumentButton(_ name: String, trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning,
                  let backend = container.localChatBackend,
                  let spec = InstrumentRegistry.spec(named: name) else { return }
            batteryRunning = true
            Task {
                let conductor = InstrumentConductor(
                    confirmationCenter: container.toolConfirmationCenter, backend: backend)
                await conductor.run(spec: spec, trials: trials, cells: nil, unattended: false)
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200 orphan cleanup: the four crashed action batteries stranded
    // their battery alarms (up to ~50 armed for 6:30 AM, ringing through
    // Silent). AlarmKit enumeration carries no label, so this cancels ALL
    // Talaria alarms — real /alarm ones included. User-invoked only.
    @State private var alarmSweepResult: String?

    // #212: the raw WeatherKit probe. Nothing between the app and the service —
    // no model, no tool belt, no location provider, no geocode, hardcoded
    // coordinate. If this fails identically to `currentWeather`, Talaria's code
    // is exonerated and the fault is identity/account/service.
    @State private var weatherProbeResult: String?
    @State private var weatherProbeRunning = false

    // #333 sweep — DELIBERATELY NOT registry-routed, and the reason is not
    // "it looked different". It calls no `LocalChatBackend` method at all
    // (`WeatherKitProbe.run()` is a static on another type), opens no battery
    // run, and writes no `BatteryRunRecord` — so a conductor run would report
    // `.failed` for it every time, since `completed` MEANS a new record was
    // embedded. It also owns result state the generic label cannot show.
    // There is no backend call here to route, so there is nothing to register.
    @ViewBuilder
    private var weatherKitProbeButton: some View {
        Button {
            guard !weatherProbeRunning else { return }
            weatherProbeRunning = true
            weatherProbeResult = nil
            Task {
                let result = await WeatherKitProbe.run()
                // Emit to the battery sinks too, so the raw text survives in the
                // container log even if the screen is dismissed — #212's whole
                // lesson is that a result you can only read on screen is a
                // result you can lose.
                LocalChatBackend.batteryEmit("probe: weatherkit \(result.detail)")
                weatherProbeResult = result.detail
                weatherProbeRunning = false
            }
        } label: {
            MonoLabel(weatherProbeRunning ? "Probing WeatherKit…" : "WeatherKit raw probe (#212)",
                      size: 10, tracking: Design.Tracking.mono,
                      color: weatherProbeRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(weatherProbeRunning)
    }

    @ViewBuilder
    private var weatherKitProbeResultRow: some View {
        if let weatherProbeResult {
            MonoLabel(weatherProbeResult, size: 9, tracking: Design.Tracking.mono,
                      color: weatherProbeResult.hasPrefix("OK")
                          ? Design.Colors.foregroundBright : Design.Colors.danger)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // #333 sweep — NOT an instrument and NOT registry-routed: this is a
    // maintenance action (cancel every Talaria alarm, real ones included), not
    // a measurement. It runs no trials, takes no `trials` count, and produces
    // no run record. It keeps `.disabled(batteryRunning)` so it cannot fire
    // into a live battery's reap.
    @ViewBuilder
    private var alarmSweepButton: some View {
        Button {
            let result = AlarmService.sweepAllTalariaAlarms()
            alarmSweepResult = "cancelled=\(result.cancelled) failed=\(result.failed)"
        } label: {
            MonoLabel(alarmSweepResult.map { "Swept — \($0)" } ?? "Sweep ALL Talaria alarms (incl. real)",
                      size: 10, tracking: Design.Tracking.mono,
                      color: alarmSweepResult == nil ? Design.Colors.danger : Design.Colors.mutedForeground)
        }
        .disabled(batteryRunning)
    }

    private var localBrainPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Local brain — #102", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            // #196 desk A/B: pick the session shape for the NEXT launch.
            // Mirrors the TALARIA_SESSION_SHAPE launch env (which wins when
            // set); read once per process, so a change here needs a
            // force-quit + relaunch to take effect — which is the A/B
            // protocol between cells anyway.
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                MonoLabel("Session shape A/B (#196) — active: \(LocalChatBackend.activeSessionShape.rawValue). Changes apply after force-quit + relaunch; start a NEW chat per cell.",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                Picker("Session shape", selection: $sessionShapeOverride) {
                    // Post-promotion (2026-07-28): armed-routed IS
                    // production; armed is the legacy control.
                    Text("armed-routed (production)").tag("armed-routed")
                    Text("armed (legacy control)").tag("armed")
                    Text("toolless-lic (payload A)").tag("toolless-lic")
                    Text("toolless-lic2 (payload B)").tag("toolless-lic2")
                    // Battery-3 decomposition cells + battery-2 treatments:
                    // reachable for spot checks, out of the battery list.
                    Text("armed-noinstr").tag("armed-noinstr")
                    Text("toolless-noinstr").tag("toolless-noinstr")
                    Text("armed-readonly").tag("armed-readonly")
                    Text("armed-nocall").tag("armed-nocall")
                    Text("armed-noschema").tag("armed-noschema")
                    Text("armed-remfix (held)").tag("armed-remfix")
                    Text("armed-complic (held)").tag("armed-complic")
                    Text("armed-fix (held)").tag("armed-fix")
                    Text("toolless (held)").tag("toolless")
                }
                // Menu, not segmented: eleven cells don't fit a phone-width
                // segmented control (#196).
                .pickerStyle(.menu)
                .onChange(of: sessionShapeOverride) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "debug.sessionShape")
                }

                // #196 fourth battery (cure lane): 4 cells × 3 prompts × n
                // trials, in-process, results to Console (category
                // LocalChatBackend, lines prefixed "battery:"); armed-routed
                // trials log their per-trial "route=" line, and the router
                // probe measures classification accuracy alone (lines
                // prefixed "router:"). No force-quit cycling needed.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("shape", trials: 10, label: "Battery n=10 (~120 trials)")
                    instrumentButton("shape", trials: 20, label: "Battery n=20 (~240)")
                }
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("router-probe", trials: 20, label: "Router probe n=20 (200)")
                }
                // #200 action battery: 1 armed cell × 3 create prompts × n,
                // auto-ACCEPT — real writes, [T27-battery]-tagged, reaped
                // before DONE. Run with Reminders/Calendar GRANTED. n=5 is
                // the crash-repro power (both 2026-07-28 n=20 attempts died
                // mid-run); n=20 is the measurement power.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("action", trials: 5, label: "Action battery n=5 (15)")
                    instrumentButton("action", trials: 20, label: "Action battery n=20 (60)")
                }
                // #209: production vs the pinned read-tool rollback, on prompts
                // where omitting the field is CORRECT. 2 cells × 4 prompts × n.
                // #212: raw WeatherKit call, everything else stripped out.
                HStack(spacing: Design.Spacing.sm) {
                    weatherKitProbeButton
                }
                weatherKitProbeResultRow
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("read-tool", trials: 10, label: "Read-tool battery n=10 (80)")
                }
                // #211: control vs the scoped readMotion description, on the
                // step question the app currently answers wrong 20/20.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("motion-scope", trials: 10, label: "Motion-scope battery n=10 (40)")
                }
                // #214 THE structural lane — belt narrowing + composition
                // licensing, the combination never yet run.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("scoped-v2", trials: 10, label: "ScopedV2 battery n=10 (80)")
                }
                // #215 THE missing denominator — the same four prompts, but
                // the routed cell classifies each turn first, the way every
                // shipped turn does. 2 cells × 4 prompts × n, plus one router
                // generation per routed trial.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("routed", trials: 10, label: "Routed battery n=10 (80+40)")
                }
                // #216 the narrow belt re-tried under routing — the composition
                // objection that closed #214 is unreachable once the router
                // sends those turns toolless. 2 cells x 4 prompts x n + routes.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("routed-scoped", trials: 10, label: "Routed-scoped n=10 (80+40)")
                }
                // #217 CAN the model classify intent safely enough to drive a
                // belt? 10 baseline rows (regression gate) + 16 intent rows.
                // No tools, no artifacts — classifications only.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("intent-router-probe", trials: 5, label: "Intent 2x2 n=5 (520)")
                }
                // #284 the Bool-vector route: 10 baseline (gate) + 21 grid
                // (armed/groups/danger) + 2 meta rows (measured, no bar).
                // No tools, no artifacts — classifications only.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("vector-router-probe", trials: 5, label: "Vector router probe (#284)")
                }
                // #211 follow-on: promoted vs promoted-plus-boundary, against
                // the extra-tool chaining the promotion cost.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("motion-redirect", trials: 10, label: "Motion-redirect battery n=10 (40)")
                }
                // #200B: 4 treatment cells × 4 prompts (haiku grab canary).
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("destall", trials: 10, label: "Destall battery n=10 (160)")
                }
                // #200C: control vs instructions-level de-stall clause.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("instrfix", trials: 10, label: "Instrfix battery n=10 (80)")
                }
                // #200E: control vs structural .required (demote exit).
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("toolmode", trials: 10, label: "Toolmode battery n=10 (80)")
                }
                // #200F: control vs scoped / create-only / find-first cells.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("community", trials: 10, label: "Community battery n=10 (160)")
                }
                // #200G: promoted-production re-verify (both halves pool).
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("findfix", trials: 10, label: "Findfix battery n=10 (80)")
                }
                // #200H: control vs spiral carve-out / third-strike demote.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("spiral", trials: 10, label: "Spiral battery n=10 (120)")
                }
                // #200I: the same control vs the event-scoped reword only.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("spiralfix", trials: 10, label: "Spiralfix battery n=10 (80)")
                }
                // #200J: control vs the card-narration clause.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("cardfix", trials: 10, label: "Cardfix battery n=10 (80)")
                }
                // #200K: pooled production re-verify + the datefix cell.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("datefix", trials: 10, label: "Datefix battery n=10 (120)")
                }
                // #340: production vs #200K's unpromoted day-default clause,
                // remind prompt only, auto-DECLINE — nothing is written.
                // Read the verdict from the device log, not the artifact:
                // `scripts/mac/score-due-omission.py`, four buckets.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("due-date", trials: 20, label: "Due-date A/B n=20 (40)")
                }
                // #200L: production vs card-clause rollback vs spiralfix.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("calendar", trials: 10, label: "Calendar battery n=10 (120)")
                }
                // #200M: production vs carve-out v3 vs carve-out v2.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("deadend", trials: 10, label: "Deadend battery n=10 (120)")
                }
                // #200N: the v3 confirmation A/B.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("deadend-verify", trials: 10, label: "Deadend verify n=10 (80)")
                }
                // #200O: pooled production re-verify + the grabfix cell.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("grabfix", trials: 10, label: "Grabfix battery n=10 (120)")
                }
                // #200P: production vs the card-correction clause.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("stallfix", trials: 10, label: "Stallfix battery n=10 (80)")
                }
                // #200Q: production vs the schema swap.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("schemafix", trials: 10, label: "Schemafix battery n=10 (80)")
                }
                // #200S: promotion re-verify vs its own rollback.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("schema-reverify", trials: 10, label: "Schema re-verify n=10 (120)")
                }
                // #200T: production vs the calendar schema swap.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("calfix", trials: 10, label: "Calendar schema n=10 (80)")
                }
                // #200U: contact dead-end fix + its ceiling probe.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("deadend2", trials: 10, label: "Contact dead-end n=10 (120)")
                }
                // #200V: the same three arms reversed, warm-up first.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("deadend-confirm", trials: 10, label: "Dead-end confirm n=10 (120+4)")
                }
                // #200W: calendar arms warm, production last.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("calfix-warm", trials: 10, label: "Calendar warm n=10 (80+4)")
                }
                // #200X: promoted calendar tool vs its pinned rollback.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("cal-rollback-verify", trials: 10, label: "Calendar rollback n=10 (80+4)")
                }
                // #201: contact dead-end fix re-measured at n=20.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("deadend-reconsider", trials: 20, label: "Dead-end reconsider n=20 (160+4)")
                }
                // #201B: the SAME two arms at n=40 — powered from the 16.7%
                // base rate so a 0-vs-k comparison can actually conclude.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("deadend-reconsider", trials: 40, label: "Dead-end POWER n=40 (320+4)")
                }
                // #201B confirmation: reversed, production in the cool slot.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("deadend-reversed", trials: 40, label: "Dead-end REVERSED n=40 (320+4)")
                }
                // #202A: the context-blind router probe. 3 generating
                // variants × 23 rows × n, plus the free deterministic
                // lenrule column. Pure classification — no tool runs and
                // nothing is written, so this one needs no grants and has
                // nothing to reap.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("router-context-probe", trials: 15, label: "Router context n=15 (~585)")
                }
                // #202B: the two-turn offer→accept shape. Auto-ACCEPT, real
                // writes, reaped per trial — run with Reminders GRANTED.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("two-turn", trials: 12, label: "Two-turn n=12 (24+5+1)")
                }
                // #202C: the toolless honesty clause + the #196 tic guard.
                // NO belt in any trial, so nothing can be created and there
                // is nothing to grant or reap.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("honesty", trials: 10, label: "Honesty n=10 (20+24+1)")
                }
                // #202C companion: ctx-a on realistic LONG contexts, timed.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("long-context-probe", trials: 5, label: "Long-context probe n=5 (50)")
                }
                // #207: can the router be told an image is attached, and is
                // that enough? Pure classification — no grants, no reap.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("image-routing-probe", trials: 10, label: "Image routing n=10 (420)")
                }
                // #199: auto-DECLINE. Measures what production SAYS after the
                // user says no. Nothing is created, so nothing is reaped.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("decline", trials: 10, label: "Decline n=10 (40)")
                }
                // #204: the two promoted instruction clauses vs their own
                // rollbacks, warm and within-run. Auto-ACCEPT, real writes.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("clause-reverify", trials: 10, label: "Clause re-verify n=10 (120+4)")
                }
                // #202D: clause v1 vs the reworded v2 — production absent,
                // its number is settled across two runs.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("honesty-v2", trials: 10, label: "Honesty v2 n=10 (20+24+1)")
                }
                // #297: does a registry-generated capability index make "What
                // can you do?" honest without costing the toolless branch's
                // own honesty? 2 arms x 3 prompts x n. Belt is empty in both
                // arms — nothing created, nothing to reap.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("toolless-index", trials: 20, label: "Toolless index A/B n=20 (120)")
                }
                // #257: capability-question detection — the second production
                // Bool (arm) vs the pinned 1-field control, same run. GATE
                // 2x10x10 + RECALL 10x5 + DANGER 20x5 = 350 classifications;
                // no tools, nothing created.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("capability-detection-probe", trials: 10, label: "Capability detection (#257) (350)")
                }
                // #335 A: #257's owed pre-flight — what the two-field
                // capability router's payload COSTS on the device's own
                // tokenizer, outside any turn, against the caps read from the
                // production constants. No generation, nothing created. `n`
                // is a REPEAT count: the counts should be deterministic and
                // the repeats are what prove it.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("tokencount-preflight", trials: 3,
                                     label: "Token-count pre-flight (#257) (n=3)")
                }
                // #335 B: #324-W3's three device-only FM questions — the
                // 4096-vs-8192 tokenCount boundary, the new beta5
                // `variant.displayName`, and throw-vs-truncate under a binding
                // response cap. Read-only; one beltless generation in the
                // third band. ⚠️ beta5 runtimes ONLY (new-in-beta5 symbol).
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("fm-asymmetries", trials: 3,
                                     label: "FM asymmetries (#324-W3) (n=3)")
                }
                // #335 C: #210's residual — does ONE forced condensation get an
                // over-8,192 transcript back under the window? Production's own
                // condenser, a synthetic overflow transcript, nothing written
                // and nothing generated.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("condensation-fit", trials: 3,
                                     label: "Condensation fit (#210) (n=3)")
                }
                // #101 bar 101-A1: does production's router ARM a turn whose
                // answer lives in a past conversation? 10 pinned rows x 2 =
                // n=20 classifications; no tools, nothing created.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("cross-chat-recall-probe", trials: 2, label: "Cross-chat recall routing A-1 (n=20)")
                }
                // #337 bar 337-D: what the refusals that trigger #232's cut
                // actually SAY, verbatim, plus the post-cut toolless retry's
                // text (#225 B2's gap). Auto-DECLINE — nothing is written, so
                // no grants and nothing to reap. Two cells x 3 prompts x n.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("refusal-words", trials: 10,
                                     label: "Refusal words (#337-D) n=10 (60)")
                }
                // #337 bar 337-F: does the "Confirmation card:" prose shape
                // track the tool-description clause? 3 arms x 3 prompts x n.
                // Auto-DECLINE — nothing written, nothing to grant or reap.
                HStack(spacing: Design.Spacing.sm) {
                    instrumentButton("card-clause", trials: 10,
                                     label: "Card clause A/B (#337-F) n=10 (90)")
                }
                HStack(spacing: Design.Spacing.sm) {
                    alarmSweepButton
                }

                // #196 results-page lane: every run above also persists to
                // the structured store — view, drill into raw replies, and
                // export from anywhere, no Console required.
                NavigationLink {
                    BatteryResultsScreen()
                } label: {
                    MonoLabel("Battery results →", size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.accent)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                MonoLabel("Streams a synthetic loop through the real on-device chat path. Turn on read-aloud first to verify #110.",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                GhostButton(
                    title: forcedTripState == .running ? "Tripping…" : "Force repetition trip",
                    systemImage: "repeat",
                    height: 40
                ) {
                    runForcedTrip(holdLiveSDKStream: false)
                }
                .disabled(forcedTripState == .running)
                GhostButton(
                    title: "Force trip (live SDK)",
                    systemImage: "bolt",
                    height: 40
                ) {
                    runForcedTrip(holdLiveSDKStream: true)
                }
                .disabled(forcedTripState == .running)
                if forcedTripState == .done {
                    MonoLabel("Tripped — check the chat reply, the #102 Console notice, and that the next send still works.",
                              size: 9, tracking: Design.Tracking.mono,
                              color: Design.Brand.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func runForcedTrip(holdLiveSDKStream: Bool) {
        guard forcedTripState != .running else { return }
        forcedTripState = .running
        Task {
            await container.chatStore.debugRunForcedTrip(holdLiveSDKStream: holdLiveSDKStream)
            forcedTripState = .done
        }
    }
    #endif
}
