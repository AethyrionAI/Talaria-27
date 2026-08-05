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

    // MARK: Batteries (#200 harness — relocated by #252)
    #if DEBUG

    private var batteriesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Batteries (#200 harness)")
            localBrainPanel
        }
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

    // #196 second battery: one launcher, two powers — n=10 resolves the
    // reminder-grab question (8/10 -> ~0 is unmissable); n=20 is required
    // for a significant composition verdict (4/10 vs 8/10 at n=10 is
    // p~0.17 — the exact underpowering behind the afternoon's overturned
    // n=4 conviction).
    @ViewBuilder
    private func batteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            // Headless battery sessions can never answer a confirmation
            // card (non-cancellable continuation), so action-tool grabs
            // auto-decline for the run — which also measures post-denial
            // recovery behavior. The auto-modes are mutually exclusive:
            // clearing accept here (and both at run end) keeps the #200
            // launcher and this one from ever overlapping flags.
            container.toolConfirmationCenter.autoAcceptForBattery = false
            container.toolConfirmationCenter.autoDeclineForBattery = true
            // A ~20-minute n=20 must survive auto-lock — work-desk runs
            // (#196 results-page lane) have no cable keeping the screen
            // awake, and a locked screen suspends the run mid-battery.
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runShapeBattery(trials: trials)
                container.toolConfirmationCenter.autoDeclineForBattery = false
                container.toolConfirmationCenter.autoAcceptForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200 action battery: the action-SUCCESS path. Auto-ACCEPT armed —
    // every staged confirmation approves, so appropriate creates EXECUTE:
    // real EventKit/AlarmKit writes, every artifact marker-tagged by the
    // gate, all reaped before the DONE line. Run with Reminders/Calendar
    // permissions GRANTED (the observed #200 failure post-dates the grant).
    // Shares the batteryRunning guard with the other instruments.
    @ViewBuilder
    private func actionBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            // Mutually exclusive with the decline mode — decline would
            // measure the #196 contract, not action success.
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            // Same auto-lock guard as the shape battery.
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runActionBattery(trials: trials)
                // Both flags cleared at run end, whatever this run armed.
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200B destall battery: the reminder list-stall treatment as measured
    // cells (control / guidefix / toolfix / bothfix) × four prompts — the
    // haiku grab canary included, since the de-stall texts push toward
    // immediate creation. Auto-ACCEPT, real writes, reaped. Promotion only
    // on the classified verdict.
    @ViewBuilder
    private func destallBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDestallBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200C instrfix battery: control vs the INSTRUCTIONS-level de-stall
    // clause (#200B falsified the tool-text seam — the stall fires before
    // tool engagement). Auto-ACCEPT, grab canary watching whether "create
    // it right away" pushes haiku grabs above the 8/10 control baseline.
    @ViewBuilder
    private func instrfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runInstrfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200E toolmode battery: promoted-production control vs the structural
    // `.required` treatment (DynamicProfile with the mandatory demote-after-
    // first-call exit — a static .required loops). Auto-ACCEPT; the canary
    // measures which tool a FORCED call grabs on the haiku misroute.
    @ViewBuilder
    private func toolmodeBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runToolmodeBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200F community battery: promoted-production control vs the three
    // survey-derived treatments (per-intent scoped belt, create-only belt,
    // find-first carve-out instructions). Auto-ACCEPT; per-trial reap.
    @ViewBuilder
    private func communityBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCommunityBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200G findfix re-verify: promoted control vs explicit-true findfix
    // (identity — both halves measure production and pool).
    @ViewBuilder
    private func findfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runFindfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200H spiral battery: promoted control vs the lookup-spiral
    // carve-out (instructions) and the third-strike demote (structural).
    @ViewBuilder
    private func spiralBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSpiralBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #209 read-tool battery: production vs the pinned read-tool rollback on
    // prompts where OMITTING the field is correct. READ tools only — nothing
    // is written, so no auto-accept is needed and the reap is a no-op.
    @ViewBuilder
    private func readToolBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runReadToolBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #214 THE structural lane: production vs per-intent belt + composition
    // licensing. Creates real artifacts — auto-ACCEPT, reaped before DONE.
    @ViewBuilder
    private func scopedV2BatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runScopedV2Battery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #215 THE missing denominator: unrouted control vs production's routed
    // configuration. Creates real artifacts — auto-ACCEPT, reaped before DONE.
    @ViewBuilder
    private func routedBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runRoutedActionBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #216 the narrow belt re-tried where it cannot lose: both arms routed,
    // only the armed belt differs. Creates real artifacts — auto-ACCEPT, reaped.
    @ViewBuilder
    private func routedScopedBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runRoutedScopedBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #217 intent-router probe: READ-ONLY, no tools registered, nothing
    // created or reaped. Just classifications.
    @ViewBuilder
    private func intentRouterProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runIntentRouterProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #211 follow-on: promoted vs promoted-plus-boundary. READ tools only.
    @ViewBuilder
    private func motionRedirectBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runMotionRedirectBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #211 motion-scope: control vs the scoped readMotion description.
    @ViewBuilder
    private func motionScopeBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runMotionScopeBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200I spiralfix re-measure: promoted control vs the event-scoped
    // reword of the lookup-spiral carve-out. Strikefix is parked (its
    // tally instrument is unproven), so this is 2 cells, not 3.
    @ViewBuilder
    private func spiralfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSpiralfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200J: promoted control vs the card-narration clause — the
    // treatment for #200I's largest failure bucket (zero-tool trials that
    // type the confirmation card out in prose and call nothing).
    @ViewBuilder
    private func cardfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCardfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200K: the promoted control + the (now identity) cardfix cell —
    // pooled as the production re-verify — plus the datefix treatment.
    @ViewBuilder
    private func datefixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDatefixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200L: promoted production vs the pinned card-clause rollback vs
    // the #200I spiral carve-out — the calendar lane.
    @ViewBuilder
    private func calendarBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalendarBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200M: production vs the v3 dead-end carve-out vs v2, same run.
    @ViewBuilder
    private func deadendBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200N: the v3 confirmation A/B — production vs the dead-end
    // carve-out only, second independent run before any promotion.
    @ViewBuilder
    private func deadendVerifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendVerifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200O: the promoted control + the (now identity) deadendfix cell
    // pooled as the production re-verify, plus the grabfix treatment.
    @ViewBuilder
    private func grabfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runGrabfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200P: production vs the card-correction clause — the conserved
    // zero-tool stall, treated as a class rather than field by field.
    @ViewBuilder
    private func stallfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runStallfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200Q: production vs the reminder tool whose optional fields are
    // optional in the SCHEMA — the stall's structural seam.
    @ViewBuilder
    private func schemafixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSchemafixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #201B: the same two arms REVERSED — production first, in the cool slot,
    // so the run doubles as the thermal control.
    @ViewBuilder
    private func deadendReversedBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendReversedBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #201: #200U's contact fix re-measured at n=20, production last — the
    // primary is a dead-end COUNT, which n=10 could not carry.
    @ViewBuilder
    private func deadendReconsiderBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendReconsiderBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200X: the promoted calendar tool against its OWN pinned rollback,
    // warm, production last — the confidence run the promotion is owed.
    @ViewBuilder
    private func calRollbackVerifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalRollbackVerifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200W: #200T's calendar arms re-run WARM with production last. The
    // primaries are the location-spiral and invented-location counts, not the
    // rate — warm production calendar is already ~9/10.
    @ViewBuilder
    private func calfixWarmBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalfixWarmBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200V: #200U's three arms REVERSED (production last) after a discarded
    // warm-up pass — the confirmation run that tests the cell-order confound.
    @ViewBuilder
    private func deadendConfirmBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendConfirmBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200U: control vs the contact not-found RESULT carrying continuation,
    // plus the ceiling probe with the tool absent.
    @ViewBuilder
    private func deadend2BatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadend2Battery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200T: production control vs the calendar tool with its two
    // undefaultable fields optional in the schema.
    @ViewBuilder
    private func calfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200S: pooled production re-verify (control + the now-identity
    // schemafix cell) vs the pinned pre-promotion rollback.
    @ViewBuilder
    private func schemaReverifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSchemaReverifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
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

    // #196 battery 4: router-accuracy probe — no tools execute (pure
    // classification), so no confirmation auto-decline is needed; the
    // shared batteryRunning guard keeps the two instruments from
    // overlapping on the model.
    @ViewBuilder
    private func routerProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            // Same auto-lock guard as the battery button — 200 router
            // generations take minutes, not seconds.
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runRouterProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202A: same shape as the #196 router probe — pure classification, so
    // no confirmation auto-decline and nothing to sweep afterwards. The
    // idle-timer lock matters here too: ~585 generations is ~10 minutes.
    @ViewBuilder
    private func routerContextProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runRouterContextProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202B two-turn battery: an offer, then a bare affirmative. Auto-ACCEPT
    // so an appropriate create EXECUTES and is countable as an artifact —
    // real writes, marker-tagged, reaped per trial.
    @ViewBuilder
    private func twoTurnBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runTwoTurnBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202C: the honesty lane. Every trial runs with an EMPTY belt, so no
    // confirmation can fire and nothing can be written — no grants needed
    // and nothing to reap, same as the probes.
    @ViewBuilder
    private func honestyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runHonestyBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #207: same shape as the other probes — classification only.
    @ViewBuilder
    private func imageRoutingProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runImageRoutingProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #199: the DECLINE lane. auto-DECLINE is mutually exclusive with
    // auto-accept — declining is the whole measurement, so no artifact can
    // be created and there is nothing to reap.
    @ViewBuilder
    private func declineBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoAcceptForBattery = false
            container.toolConfirmationCenter.autoDeclineForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeclineBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #204: full action battery — auto-ACCEPT, real writes, reaped per
    // trial. Run with Reminders/Calendar GRANTED.
    @ViewBuilder
    private func clauseReverifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runClauseReverifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202D: same empty-belt shape as #202C — nothing to grant, nothing to reap.
    @ViewBuilder
    private func honestyV2BatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runHonestyBattery(
                    trials: trials, cells: LocalChatBackend.honestyV2BatteryCells)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    @ViewBuilder
    private func longContextProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runLongContextProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
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
                    batteryButton(trials: 10, label: "Battery n=10 (~120 trials)")
                    batteryButton(trials: 20, label: "Battery n=20 (~240)")
                }
                HStack(spacing: Design.Spacing.sm) {
                    routerProbeButton(trials: 20, label: "Router probe n=20 (200)")
                }
                // #200 action battery: 1 armed cell × 3 create prompts × n,
                // auto-ACCEPT — real writes, [T27-battery]-tagged, reaped
                // before DONE. Run with Reminders/Calendar GRANTED. n=5 is
                // the crash-repro power (both 2026-07-28 n=20 attempts died
                // mid-run); n=20 is the measurement power.
                HStack(spacing: Design.Spacing.sm) {
                    actionBatteryButton(trials: 5, label: "Action battery n=5 (15)")
                    actionBatteryButton(trials: 20, label: "Action battery n=20 (60)")
                }
                // #209: production vs the pinned read-tool rollback, on prompts
                // where omitting the field is CORRECT. 2 cells × 4 prompts × n.
                // #212: raw WeatherKit call, everything else stripped out.
                HStack(spacing: Design.Spacing.sm) {
                    weatherKitProbeButton
                }
                weatherKitProbeResultRow
                HStack(spacing: Design.Spacing.sm) {
                    readToolBatteryButton(trials: 10, label: "Read-tool battery n=10 (80)")
                }
                // #211: control vs the scoped readMotion description, on the
                // step question the app currently answers wrong 20/20.
                HStack(spacing: Design.Spacing.sm) {
                    motionScopeBatteryButton(trials: 10, label: "Motion-scope battery n=10 (40)")
                }
                // #214 THE structural lane — belt narrowing + composition
                // licensing, the combination never yet run.
                HStack(spacing: Design.Spacing.sm) {
                    scopedV2BatteryButton(trials: 10, label: "ScopedV2 battery n=10 (80)")
                }
                // #215 THE missing denominator — the same four prompts, but
                // the routed cell classifies each turn first, the way every
                // shipped turn does. 2 cells × 4 prompts × n, plus one router
                // generation per routed trial.
                HStack(spacing: Design.Spacing.sm) {
                    routedBatteryButton(trials: 10, label: "Routed battery n=10 (80+40)")
                }
                // #216 the narrow belt re-tried under routing — the composition
                // objection that closed #214 is unreachable once the router
                // sends those turns toolless. 2 cells x 4 prompts x n + routes.
                HStack(spacing: Design.Spacing.sm) {
                    routedScopedBatteryButton(trials: 10, label: "Routed-scoped n=10 (80+40)")
                }
                // #217 CAN the model classify intent safely enough to drive a
                // belt? 10 baseline rows (regression gate) + 16 intent rows.
                // No tools, no artifacts — classifications only.
                HStack(spacing: Design.Spacing.sm) {
                    intentRouterProbeButton(trials: 5, label: "Intent 2x2 n=5 (520)")
                }
                // #211 follow-on: promoted vs promoted-plus-boundary, against
                // the extra-tool chaining the promotion cost.
                HStack(spacing: Design.Spacing.sm) {
                    motionRedirectBatteryButton(trials: 10, label: "Motion-redirect battery n=10 (40)")
                }
                // #200B: 4 treatment cells × 4 prompts (haiku grab canary).
                HStack(spacing: Design.Spacing.sm) {
                    destallBatteryButton(trials: 10, label: "Destall battery n=10 (160)")
                }
                // #200C: control vs instructions-level de-stall clause.
                HStack(spacing: Design.Spacing.sm) {
                    instrfixBatteryButton(trials: 10, label: "Instrfix battery n=10 (80)")
                }
                // #200E: control vs structural .required (demote exit).
                HStack(spacing: Design.Spacing.sm) {
                    toolmodeBatteryButton(trials: 10, label: "Toolmode battery n=10 (80)")
                }
                // #200F: control vs scoped / create-only / find-first cells.
                HStack(spacing: Design.Spacing.sm) {
                    communityBatteryButton(trials: 10, label: "Community battery n=10 (160)")
                }
                // #200G: promoted-production re-verify (both halves pool).
                HStack(spacing: Design.Spacing.sm) {
                    findfixBatteryButton(trials: 10, label: "Findfix battery n=10 (80)")
                }
                // #200H: control vs spiral carve-out / third-strike demote.
                HStack(spacing: Design.Spacing.sm) {
                    spiralBatteryButton(trials: 10, label: "Spiral battery n=10 (120)")
                }
                // #200I: the same control vs the event-scoped reword only.
                HStack(spacing: Design.Spacing.sm) {
                    spiralfixBatteryButton(trials: 10, label: "Spiralfix battery n=10 (80)")
                }
                // #200J: control vs the card-narration clause.
                HStack(spacing: Design.Spacing.sm) {
                    cardfixBatteryButton(trials: 10, label: "Cardfix battery n=10 (80)")
                }
                // #200K: pooled production re-verify + the datefix cell.
                HStack(spacing: Design.Spacing.sm) {
                    datefixBatteryButton(trials: 10, label: "Datefix battery n=10 (120)")
                }
                // #200L: production vs card-clause rollback vs spiralfix.
                HStack(spacing: Design.Spacing.sm) {
                    calendarBatteryButton(trials: 10, label: "Calendar battery n=10 (120)")
                }
                // #200M: production vs carve-out v3 vs carve-out v2.
                HStack(spacing: Design.Spacing.sm) {
                    deadendBatteryButton(trials: 10, label: "Deadend battery n=10 (120)")
                }
                // #200N: the v3 confirmation A/B.
                HStack(spacing: Design.Spacing.sm) {
                    deadendVerifyBatteryButton(trials: 10, label: "Deadend verify n=10 (80)")
                }
                // #200O: pooled production re-verify + the grabfix cell.
                HStack(spacing: Design.Spacing.sm) {
                    grabfixBatteryButton(trials: 10, label: "Grabfix battery n=10 (120)")
                }
                // #200P: production vs the card-correction clause.
                HStack(spacing: Design.Spacing.sm) {
                    stallfixBatteryButton(trials: 10, label: "Stallfix battery n=10 (80)")
                }
                // #200Q: production vs the schema swap.
                HStack(spacing: Design.Spacing.sm) {
                    schemafixBatteryButton(trials: 10, label: "Schemafix battery n=10 (80)")
                }
                // #200S: promotion re-verify vs its own rollback.
                HStack(spacing: Design.Spacing.sm) {
                    schemaReverifyBatteryButton(trials: 10, label: "Schema re-verify n=10 (120)")
                }
                // #200T: production vs the calendar schema swap.
                HStack(spacing: Design.Spacing.sm) {
                    calfixBatteryButton(trials: 10, label: "Calendar schema n=10 (80)")
                }
                // #200U: contact dead-end fix + its ceiling probe.
                HStack(spacing: Design.Spacing.sm) {
                    deadend2BatteryButton(trials: 10, label: "Contact dead-end n=10 (120)")
                }
                // #200V: the same three arms reversed, warm-up first.
                HStack(spacing: Design.Spacing.sm) {
                    deadendConfirmBatteryButton(trials: 10, label: "Dead-end confirm n=10 (120+4)")
                }
                // #200W: calendar arms warm, production last.
                HStack(spacing: Design.Spacing.sm) {
                    calfixWarmBatteryButton(trials: 10, label: "Calendar warm n=10 (80+4)")
                }
                // #200X: promoted calendar tool vs its pinned rollback.
                HStack(spacing: Design.Spacing.sm) {
                    calRollbackVerifyBatteryButton(trials: 10, label: "Calendar rollback n=10 (80+4)")
                }
                // #201: contact dead-end fix re-measured at n=20.
                HStack(spacing: Design.Spacing.sm) {
                    deadendReconsiderBatteryButton(trials: 20, label: "Dead-end reconsider n=20 (160+4)")
                }
                // #201B: the SAME two arms at n=40 — powered from the 16.7%
                // base rate so a 0-vs-k comparison can actually conclude.
                HStack(spacing: Design.Spacing.sm) {
                    deadendReconsiderBatteryButton(trials: 40, label: "Dead-end POWER n=40 (320+4)")
                }
                // #201B confirmation: reversed, production in the cool slot.
                HStack(spacing: Design.Spacing.sm) {
                    deadendReversedBatteryButton(trials: 40, label: "Dead-end REVERSED n=40 (320+4)")
                }
                // #202A: the context-blind router probe. 3 generating
                // variants × 23 rows × n, plus the free deterministic
                // lenrule column. Pure classification — no tool runs and
                // nothing is written, so this one needs no grants and has
                // nothing to reap.
                HStack(spacing: Design.Spacing.sm) {
                    routerContextProbeButton(trials: 15, label: "Router context n=15 (~585)")
                }
                // #202B: the two-turn offer→accept shape. Auto-ACCEPT, real
                // writes, reaped per trial — run with Reminders GRANTED.
                HStack(spacing: Design.Spacing.sm) {
                    twoTurnBatteryButton(trials: 12, label: "Two-turn n=12 (24+5+1)")
                }
                // #202C: the toolless honesty clause + the #196 tic guard.
                // NO belt in any trial, so nothing can be created and there
                // is nothing to grant or reap.
                HStack(spacing: Design.Spacing.sm) {
                    honestyBatteryButton(trials: 10, label: "Honesty n=10 (20+24+1)")
                }
                // #202C companion: ctx-a on realistic LONG contexts, timed.
                HStack(spacing: Design.Spacing.sm) {
                    longContextProbeButton(trials: 5, label: "Long-context probe n=5 (50)")
                }
                // #207: can the router be told an image is attached, and is
                // that enough? Pure classification — no grants, no reap.
                HStack(spacing: Design.Spacing.sm) {
                    imageRoutingProbeButton(trials: 10, label: "Image routing n=10 (420)")
                }
                // #199: auto-DECLINE. Measures what production SAYS after the
                // user says no. Nothing is created, so nothing is reaped.
                HStack(spacing: Design.Spacing.sm) {
                    declineBatteryButton(trials: 10, label: "Decline n=10 (40)")
                }
                // #204: the two promoted instruction clauses vs their own
                // rollbacks, warm and within-run. Auto-ACCEPT, real writes.
                HStack(spacing: Design.Spacing.sm) {
                    clauseReverifyBatteryButton(trials: 10, label: "Clause re-verify n=10 (120+4)")
                }
                // #202D: clause v1 vs the reworded v2 — production absent,
                // its number is settled across two runs.
                HStack(spacing: Design.Spacing.sm) {
                    honestyV2BatteryButton(trials: 10, label: "Honesty v2 n=10 (20+24+1)")
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
