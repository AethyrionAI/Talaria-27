import SwiftUI

// MARK: - Private Cloud settings screen (Settings → PRIVATE CLOUD, #395-D)
//
// The tier's control and its state, one surface. The hard opt-out (#395)
// moved here from the Models screen on Owen's 2026-08-23 ruling — a dedicated
// tile is discoverable without knowing the tier is model-related. The Models
// screen keeps a read-only quota row beside the brain picker (#30); the
// binding WRITE lives only on this screen (one source of truth, pinned
// structurally in PrivateCloudOptOutTests).
//
// The tile that opens this screen exists only where the tier does
// (SettingsSubsystem.cases(privateCloudAvailable:)), so this screen assumes
// the tier is at least present on the device.
struct PrivateCloudSettingsScreen: View {
    // #252: deck pages supply the background and top bar; the screen keeps
    // owning its content in both presentations.
    var embedded: Bool = false
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if !embedded {
                HUDScreenBackground()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if !embedded {
                        SettingsScreenHeader(title: "Private Cloud", subtitle: "Apple Compute") { dismiss() }
                    }
                    if embedded {
                        SubsystemHero(
                            motif: .squares,
                            title: SettingsSubsystem.privateCloud.title,
                            status: SettingsCardValues.privateCloud(
                                enabled: settingsStore.settings.privateCloudEnabled,
                                quota: container.localChatBackend?.privateCloudStatus()?.quota),
                            statusColor: settingsStore.settings.privateCloudEnabled
                                ? Design.Brand.accentText : Design.Colors.mutedForeground,
                            chip: SettingsSubsystem.privateCloud.chip,
                            accented: settingsStore.settings.privateCloudEnabled
                        )
                    }
                    controlSection
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Private Cloud")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    /// **#395: the hard opt-out for the Private Cloud tier.** Moved from the
    /// Models screen by #395-D; the write to `privateCloudEnabled` must not
    /// exist anywhere else.
    private var privateCloudEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.privateCloudEnabled },
            set: { settingsStore.settings.privateCloudEnabled = $0 }
        )
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.sm) {
                Text("Private Cloud β")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Toggle("", isOn: privateCloudEnabledBinding)
                    .labelsHidden()
                    .tint(Design.Brand.accentText)
                    .accessibilityLabel("Use Private Cloud Compute")
            }
            Text(settingsStore.settings.privateCloudEnabled
                 ? "Larger model, on Apple's servers. Turn off to keep every local turn on this device."
                 : "Off — nothing is sent to Apple's servers. Local turns run on-device only.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
            if settingsStore.settings.privateCloudEnabled,
               let status = container.localChatBackend?.privateCloudStatus() {
                PrivateCloudQuotaRow(status: status) {
                    container.localChatBackend?.showPrivateCloudLimitIncreaseOptions()
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.hairline,
            fill: Design.Colors.background.opacity(0.4)
        )
    }
}

/// **#391's honest quota row, shared** by the Models screen (read-only state
/// beside the brain picker, #30) and the dedicated Private Cloud screen
/// (#395-D) — one component, so the two surfaces can never disagree about
/// what the quota says.
struct PrivateCloudQuotaRow: View {
    let status: LocalChatBackend.PrivateCloudStatus
    var showOptions: (() -> Void)?

    var body: some View {
        // #391: the label is built by a pure formatter on the status type, so
        // the today-vs-later branch and the nil reset date are assertable
        // without a view.
        let label = LocalChatBackend.PrivateCloudStatus.quotaRowLabel(
            quota: status.quota, resetDate: status.resetDate, now: Date())
        let color: Color = switch status.quota {
        case .belowLimit(approaching: false): Design.Colors.mutedForeground
        case .belowLimit(approaching: true): Design.Brand.forgeText
        case .limitReached: Design.Colors.dangerText
        // #391: unknown is not good news and not bad news — it is unknown,
        // and it must not borrow the reassuring muted tone OR the alarming
        // one.
        case .unknown: Design.Colors.dimForeground
        }
        HStack(spacing: Design.Spacing.sm) {
            MonoLabel(label, size: 8, tracking: Design.Tracking.mono, color: color)
            Spacer()
            if status.hasLimitIncreaseSuggestion, let showOptions {
                Button("Show options", action: showOptions)
                    .font(Design.Typography.mono(10, weight: .medium))
                    .foregroundStyle(Design.Brand.accentText)
            }
        }
        .padding(.top, Design.Spacing.xs)
    }
}
