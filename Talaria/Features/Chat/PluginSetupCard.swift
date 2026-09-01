import SwiftUI

/// #269-B: the conversational installer's surfaces, in the transcript.
///
/// #251 chose where this lives and #269 carries the sentence: *"Consent
/// ('enable talaria?') surfaces in chat where the user lives; the app probes
/// to verify."* So this follows the vocabulary the transcript already has —
/// `ToolConfirmationCard` (#29) and `HostApprovalCard` (#304): a panel at the
/// tail of the thread, a titled ask, two plain buttons, and a notice row that
/// takes the card's place when it settles.
///
/// What it deliberately does NOT do is decide anything. The consent card
/// cannot send (the store's `confirm()` is the only door, 269-B-F) and the
/// result row cannot claim (its text comes from the probe's verdict alone,
/// 269-B-G).
struct PluginSetupConsentCard: View {
    let store: PluginSetupStore

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(Design.Brand.accentText)
                MonoLabel("Setup", size: 9, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Brand.accentText)
                Spacer()
            }

            Text(PluginSetupStore.Consent.title)
                .font(Design.Typography.body(15, weight: .medium))
                .foregroundStyle(Design.Colors.foregroundBright)

            Text(PluginSetupStore.Consent.body)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Design.Spacing.sm) {
                Button {
                    store.decline()
                } label: {
                    Text(PluginSetupStore.Consent.declineLabel.uppercased())
                        .font(Design.Typography.mono(11, weight: .medium))
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs)
                        .overlay { Capsule().strokeBorder(Design.Colors.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not now — nothing is sent")

                Button {
                    Task { await store.confirm() }
                } label: {
                    Text(PluginSetupStore.Consent.confirmLabel.uppercased())
                        .font(Design.Typography.mono(11, weight: .medium))
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Brand.accentBrightText)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs)
                        .background(Design.Colors.accentTint(0.10), in: Capsule())
                        .overlay { Capsule().strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send the setup instructions to your agent")

                Spacer()
            }
        }
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.35),
            fill: Design.Colors.surface
        )
        .padding(.horizontal, Design.Spacing.md)
        .accessibilityIdentifier("chat.pluginSetup.consent")
    }
}

/// The in-flight row: the turn is out, or the probe is running. It states
/// which, and claims nothing about the outcome of either.
struct PluginSetupProgressRow: View {
    let isVerifying: Bool

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            ProgressView()
                .controlSize(.small)
            MonoLabel(isVerifying ? "VERIFYING WITH TALARIA'S OWN PROBE" : "SENDING SETUP INSTRUCTIONS",
                      size: 9, weight: .medium, tracking: Design.Tracking.mono,
                      color: Design.Colors.mutedForeground)
            Spacer(minLength: 0)
        }
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.hairline,
            fill: Design.Colors.surface
        )
        .padding(.horizontal, Design.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.pluginSetup.progress")
    }
}

/// The settled row — a sibling of `HostApprovalNoticeRow`, and the surface
/// bar 269-B-H holds. Every word comes from `TalariaPluginSetupCompletion`,
/// which comes from the probe; nothing here reads the agent's reply.
struct PluginSetupResultRow: View {
    let completion: TalariaPluginSetupCompletion
    let onDismiss: () -> Void

    private var tint: Color {
        switch completion {
        case .live: Design.Brand.accentText
        case .notLive: Design.Brand.forgeText
        case .hostUnreachable, .notMeasured, .promptNotSent: Design.Colors.mutedForeground
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: tint, diameter: 6)
                MonoLabel(completion.headline, size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: tint)
                Spacer(minLength: Design.Spacing.xs)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: Design.Size.iconSmall))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss setup result")
            }
            Text(completion.detail)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.hairline,
            fill: Design.Colors.surface
        )
        .padding(.horizontal, Design.Spacing.md)
        .accessibilityIdentifier("chat.pluginSetup.result")
    }
}
