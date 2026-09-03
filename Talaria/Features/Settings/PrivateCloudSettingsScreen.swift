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

    /// **#422-N fix round 1: the policy sentence must not render while the
    /// tier is OFF.** It rendered unconditionally right after the OFF-state
    /// blurb ("Off — nothing is sent to Apple's servers…"), so the screen
    /// said nothing is sent and, on the very next line, that the request
    /// leaves the device — a contradiction, not a disclosure. The sentence
    /// describes what a PCC turn does; it has nothing to say while the tier
    /// is off. Static (not inlined into the `if`) so the rule is
    /// unit-testable without a view (M-17's reasoning, same file family as
    /// `UplinkSettingsScreen.unkeyedNudgeVisible`).
    static func showsPolicySentence(isOn: Bool) -> Bool { isOn }

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
            // #422-N: the policy disclosure, byte-identical to docs/privacy.html —
            // shown ONLY while the tier is ON (Self.showsPolicySentence), reading
            // the SAME toggle state the blurb above reads. Rendering it while OFF
            // would contradict the OFF-state blurb on the line right above it.
            if Self.showsPolicySentence(isOn: settingsStore.settings.privateCloudEnabled) {
                Text(ConnectHostCopy.privateCloudPolicySentence)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
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

/// **#391's honest quota row.** (Its one-time second consumer — the Models
/// screen readout — was consolidated away by #395/#362; this screen is the
/// only surface, doc corrected by #404.)
///
/// #404 reshaped the single wrapped sentence into the design system's
/// kicker/value telemetry fields. The sentence itself survives,
/// byte-identical, as this row's ACCESSIBILITY label — assembled from the
/// same field formatters the fields render, so what VoiceOver hears and
/// what the screen shows can never disagree.
struct PrivateCloudQuotaRow: View {
    let status: LocalChatBackend.PrivateCloudStatus
    var showOptions: (() -> Void)?

    var body: some View {
        // #391: every value comes from a pure formatter on the status type —
        // the today-vs-later branch and the nil reset date stay assertable
        // without a view, and `RESETS —` remains a rendered value (the
        // absence IS the information), just dimmed now instead of dangling.
        let state = LocalChatBackend.PrivateCloudStatus.quotaStateText(status.quota)
        let resets = LocalChatBackend.PrivateCloudStatus.resetFieldText(status.resetDate, now: Date())
        // #391: unknown is not good news and not bad news — it is unknown,
        // and it must not borrow the reassuring muted tone OR the alarming
        // one.
        let tone: Color = switch status.quota {
        case .belowLimit(approaching: false): Design.Colors.mutedForeground
        case .belowLimit(approaching: true): Design.Brand.forgeText
        case .limitReached: Design.Colors.dangerText
        case .unknown: Design.Colors.dimForeground
        }
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: Design.Spacing.md) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    MonoLabel("QUOTA", size: 8, tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.dimForeground)
                    HStack(spacing: Design.Spacing.xs) {
                        StatusPip(color: tone, diameter: 5)
                        MonoLabel(state, size: 10, weight: .medium,
                                  tracking: Design.Tracking.mono, color: tone)
                    }
                }
                Spacer(minLength: Design.Spacing.sm)
                VStack(alignment: .trailing, spacing: Design.Spacing.xxs) {
                    MonoLabel("RESETS", size: 8, tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.dimForeground)
                    MonoLabel(resets, size: 10, weight: .medium,
                              tracking: Design.Tracking.mono,
                              color: status.resetDate == nil
                                  ? Design.Colors.dimForeground
                                  : Design.Colors.foreground)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LocalChatBackend.PrivateCloudStatus.quotaRowLabel(
                quota: status.quota, resetDate: status.resetDate, now: Date()))
            if status.hasLimitIncreaseSuggestion, let showOptions {
                Button(action: showOptions) {
                    MonoLabel("SHOW OPTIONS", size: 9, weight: .medium,
                              tracking: Design.Tracking.monoWide,
                              color: Design.Brand.accentText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show options")
            }
        }
        .padding(.top, Design.Spacing.xs)
    }
}
