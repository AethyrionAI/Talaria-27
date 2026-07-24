import SwiftUI

// MARK: - Pairing & Devices (#152)
//
// Reached from Settings → Hermes Host → "Pairing & Devices". The label used
// to read "Pair Device", which advertised only the add action while this
// screen's actual contents are Revoke Host and Disconnect — an unpair hidden
// behind a pairing verb. The QR pairing flow itself is unchanged; adding a
// device is now an explicit action HERE rather than the implied purpose of
// the whole surface.
struct ConnectHermesHostScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    hostStatusCard
                    if hostStore.currentHost == nil {
                        setupCard
                    }
                    actionsCard

                    if let errorMessage = hostStore.lastErrorMessage {
                        errorBanner(message: errorMessage)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.lg)
            }
        }
        .navigationTitle("Pairing & Devices")
        .task {
            await hostStore.refresh()
        }
    }

    // MARK: - Host Status

    private var hostStatusCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.xl) {
            VStack(spacing: Design.Spacing.lg) {
                // Large status icon with cyan targeting brackets.
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Circle()
                        .strokeBorder(statusColor.opacity(0.4), lineWidth: 1)
                        .frame(width: 80, height: 80)
                    Image(systemName: statusIcon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(statusColor)
                        .hudGlow(statusColor, radius: 12, strength: 0.4)
                }
                .padding(.top, Design.Spacing.sm)

                // Status text
                VStack(spacing: Design.Spacing.xs) {
                    HStack(spacing: Design.Spacing.xs) {
                        StatusPip(color: statusColor, diameter: 7, blinks: statusBlinks)
                        MonoLabel(statusTitle, weight: .medium, tracking: Design.Tracking.monoXWide,
                                  color: statusColor)
                    }

                    Text(statusSubtitle)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .multilineTextAlignment(.center)
                }

                // Host details (when connected)
                if let host = hostStore.currentHost {
                    VStack(spacing: 0) {
                        Divider().overlay(Design.Colors.divider)
                        detailRow(icon: "desktopcomputer", label: host.resolvedDisplayName)
                        Divider().overlay(Design.Colors.divider)
                        detailRow(
                            icon: "clock",
                            label: host.lastSeenAt?.formatted(date: .abbreviated, time: .shortened) ?? "Just now"
                        )
                    }
                    .padding(.top, Design.Spacing.xs)
                }
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Setup Instructions

    private var setupCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.xl) {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "terminal")
                        .font(.system(size: Design.Size.iconSmall, weight: .semibold))
                        .foregroundStyle(Design.Brand.accent)
                    MonoLabel("SETUP", weight: .medium, tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.secondaryForeground)
                }

                setupStep(number: "1", command: "hermes-mobile setup", detail: "One-time registration")
                setupStep(number: "2", command: "hermes-mobile pair-phone", detail: "Scan the code in-app")
                setupStep(number: "3", command: "hermes-mobile service install", detail: "Background uptime")
            }
            .padding(Design.Spacing.lg)
        }
    }

    // MARK: - Actions

    private var actionsCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.xl) {
            VStack(spacing: 0) {
                // #152: the ADD action, stated plainly. Naming a pair target
                // re-resolves the shared `.connectHost` seam to the QR flow —
                // the same path the Server screen's per-profile Pair uses, so
                // the pairing flow itself is untouched.
                Button {
                    pairingStore.pairingTargetProfileID =
                        container.profilesStore?.activeProfileID
                } label: {
                    actionRow(
                        icon: "qrcode.viewfinder",
                        label: "Pair New Device (QR)",
                        detail: "Scan a code from your Hermes machine.",
                        color: Design.Brand.accent
                    )
                }
                .disabled(container.profilesStore?.activeProfileID == nil)

                Divider().overlay(Design.Colors.divider)

                if hostStore.currentHost != nil {
                    Button(role: .destructive) {
                        Task { await hostStore.revokeCurrentHost() }
                    } label: {
                        actionRow(
                            icon: "desktopcomputer.trianglebadge.exclamationmark",
                            label: "Revoke Host",
                            detail: "Unregisters this Hermes machine. The phone stays paired.",
                            color: Design.Colors.danger
                        )
                    }
                    .disabled(hostStore.isWorking)

                    Divider().overlay(Design.Colors.divider)
                }

                Button {
                    Task {
                        await pairingStore.disconnect()
                        dismiss()
                    }
                } label: {
                    actionRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        label: "Disconnect",
                        detail: "Signs this device out and clears its pairing.",
                        color: Design.Colors.danger
                    )
                }
            }
        }
    }

    // MARK: - Components

    private func detailRow(icon: String, label: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.mutedForeground)
                .frame(width: 20)
            Text(label)
                .font(Design.Typography.mono(13, weight: .regular))
                .foregroundStyle(Design.Colors.coolForeground)
            Spacer()
        }
        .frame(minHeight: Design.Size.minTapTarget)
    }

    private func setupStep(number: String, command: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Text(number)
                .font(Design.Typography.mono(12, weight: .bold))
                .foregroundStyle(Design.Brand.accent)
                .frame(width: 22, height: 22)
                .background(Design.Colors.accentTint(0.12))
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(Design.Colors.strongBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(command)
                    .font(Design.Typography.mono(13, weight: .regular))
                    .foregroundStyle(Design.Colors.coolForeground)
                Text(detail)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    /// #152: `detail` names what the action actually does — "Revoke Host" and
    /// "Disconnect" sit next to each other and are not the same operation.
    private func actionRow(
        icon: String,
        label: String,
        detail: String? = nil,
        color: Color
    ) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Design.Typography.callout)
                    .foregroundStyle(color)
                if let detail {
                    Text(detail)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color.opacity(0.5))
        }
        .frame(minHeight: Design.Size.minTapTarget)
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.xs)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Design.Size.iconSmall, weight: .semibold))
                .foregroundStyle(Design.Brand.forge)
            Text(message)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.foreground)
                .lineLimit(2)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.lg,
                  borderColor: Design.Brand.forge.opacity(0.4))
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        switch hostStore.connectionState {
        case .online:
            return Design.Brand.accent
        case .offline, .unreachable:
            return Design.Brand.forge
        case .notConnected:
            return Design.Colors.secondaryForeground
        }
    }

    private var statusBlinks: Bool {
        switch hostStore.connectionState {
        case .online: return true
        default: return false
        }
    }

    private var statusIcon: String {
        switch hostStore.connectionState {
        case .online:
            return "checkmark.circle.fill"
        case .offline:
            return "exclamationmark.circle.fill"
        case .unreachable:
            return "wifi.exclamationmark"
        case .notConnected:
            return "desktopcomputer"
        }
    }

    private var statusTitle: String {
        switch hostStore.connectionState {
        case .online:
            return "Connected"
        case .offline:
            return "Offline"
        case .unreachable:
            return "Status Unavailable"
        case .notConnected:
            return "No Host"
        }
    }

    private var statusSubtitle: String {
        switch hostStore.connectionState {
        case .online:
            return "Your Hermes agent is ready"
        case .offline:
            return "Waiting for the connector to come online"
        case .unreachable:
            return hostStore.lastErrorMessage ?? "We couldn't refresh host status from the relay."
        case .notConnected:
            return "Set up from your Hermes machine"
        }
    }
}
