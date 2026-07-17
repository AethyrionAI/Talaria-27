import SwiftUI

// MARK: - Connected-tier paywall (#127)
//
// One screen, theme-tokened, honest: the Connected feature list, the App
// Store's localized price (never hardcoded — "—" until loaded), purchase +
// restore + "Not now". Always dismissible; no dark patterns. Works both as
// sheet content (Server/Uplink gate points) and as a pushed destination
// (the .connectHost route seam) — `dismiss` pops or closes accordingly.
struct ConnectedPaywallView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var actionErrorMessage: String?
    @State private var pendingNotice = false

    private var entitlements: (any EntitlementServiceProtocol)? {
        container.entitlementService
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    heroSection
                    featuresCard
                    priceCard
                    if let message = actionErrorMessage ?? entitlements?.lastErrorMessage {
                        errorNotice(message)
                    }
                    if pendingNotice {
                        infoNotice("Purchase pending approval — the tier unlocks automatically once the App Store confirms it.")
                    }
                    actionButtons
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.lg)
            }
        }
        .navigationTitle("Connected")
        .task {
            await entitlements?.loadProductIfNeeded()
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        VStack(spacing: Design.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Design.Colors.accentTint(0.12))
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1)
                    .frame(width: 80, height: 80)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Design.Brand.accent)
                    .hudGlow(Design.Brand.accent, radius: 12, strength: 0.4)
            }
            .padding(.top, Design.Spacing.sm)

            MonoLabel("CONNECTED TIER", weight: .medium, tracking: Design.Tracking.monoXWide,
                      color: Design.Brand.accent)

            Text("Pair Talaria with your own Hermes host. Everything on-device stays free — Connected unlocks the bring-your-own-host feature set.")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Features

    private var featuresCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.xl) {
            VStack(alignment: .leading, spacing: 0) {
                featureRow(icon: "desktopcomputer", title: "Hermes host pairing",
                           detail: "Connect the agent running on your own machine")
                divider
                featureRow(icon: "square.stack.3d.up", title: "Backend profiles",
                           detail: "Named hosts with per-profile keys — switch anytime")
                divider
                featureRow(icon: "sensor", title: "Sensor uplink",
                           detail: "Health, location, and motion context to your agent")
                divider
                featureRow(icon: "tray.full", title: "Agent inbox",
                           detail: "Items your agent posts to the phone, with verdicts")
                divider
                featureRow(icon: "waveform", title: "Realtime voice",
                           detail: "Live talk sessions through your host")
            }
            .padding(Design.Spacing.md)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.hairline)
            .frame(height: 1)
            .padding(.leading, 20 + Design.Spacing.sm)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Design.Brand.accent)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Text(detail)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    // MARK: Price

    private var priceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                MonoLabel("PRICE", size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                          color: Design.Colors.mutedForeground)
                Text(priceKindCaption)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            Spacer()
            MonoLabel(
                PaywallPresentation.priceLabel(displayPrice: entitlements?.connectedProductDisplayPrice),
                size: 18, weight: .medium, tracking: Design.Tracking.mono,
                color: Design.Colors.foregroundBright
            )
        }
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private var priceKindCaption: String {
        switch MonetizationConfiguration.productKind {
        case .nonConsumable: "One-time purchase"
        case .annualSubscription: "Per year · auto-renews"
        }
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: Design.Spacing.sm) {
            GlowButton(title: purchaseTitle, systemImage: "lock.open") {
                Task { await purchase() }
            }
            .disabled(!PaywallPresentation.purchaseEnabled(
                productLoaded: entitlements?.connectedProductDisplayPrice != nil,
                actionInFlight: entitlements?.isActionInFlight == true
            ))

            GhostButton(title: "Restore Purchases", systemImage: "arrow.clockwise") {
                Task { await restore() }
            }
            .disabled(!PaywallPresentation.restoreEnabled(
                actionInFlight: entitlements?.isActionInFlight == true
            ))

            Button {
                dismiss()
            } label: {
                Text("Not now")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(minHeight: Design.Size.minTapTarget)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Design.Spacing.xs)
    }

    private var purchaseTitle: String {
        entitlements?.isActionInFlight == true ? "Working…" : "Unlock Connected"
    }

    private func purchase() async {
        guard let entitlements else { return }
        let outcome = await entitlements.purchaseConnectedTier()
        handle(outcome)
    }

    private func restore() async {
        guard let entitlements else { return }
        let outcome = await entitlements.restorePurchases()
        if outcome == .notUnlocked {
            actionErrorMessage = "No Connected purchase found for this Apple Account."
            return
        }
        handle(outcome)
    }

    private func handle(_ outcome: EntitlementActionOutcome) {
        pendingNotice = false
        switch outcome {
        case .unlocked:
            actionErrorMessage = nil
            if PaywallPresentation.shouldAutoDismiss(after: outcome) {
                dismiss()
            }
        case .cancelled, .notUnlocked:
            actionErrorMessage = nil
        case .pending:
            pendingNotice = true
            actionErrorMessage = nil
        case .failed(let message):
            actionErrorMessage = message
        }
    }

    // MARK: Notices

    private func errorNotice(_ message: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Design.Size.iconSmall, weight: .semibold))
                .foregroundStyle(Design.Brand.forge)
            Text(message)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.foreground)
                .lineLimit(3)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.lg,
                  borderColor: Design.Brand.forge.opacity(0.4))
    }

    private func infoNotice(_ message: String) -> some View {
        Text(message)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Colors.secondaryForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sheet wrapper for the gate points that present the paywall modally
/// (Server add-profile / pair, Uplink first-key save).
struct ConnectedPaywallSheet: View {
    var body: some View {
        NavigationStack {
            ConnectedPaywallView()
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
