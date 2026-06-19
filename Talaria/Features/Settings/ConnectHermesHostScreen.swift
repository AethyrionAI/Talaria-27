import SwiftUI

struct ConnectHermesHostScreen: View {
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Design.Colors.background
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
        .navigationTitle("Connect Host")
        .task {
            await hostStore.refresh()
        }
    }

    // MARK: - Host Status

    private var hostStatusCard: some View {
        VStack(spacing: Design.Spacing.lg) {
            // Large status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: statusIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            .padding(.top, Design.Spacing.sm)

            // Status text
            VStack(spacing: Design.Spacing.xxs) {
                Text(statusTitle)
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foreground)

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
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    // MARK: - Setup Instructions

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Label("Setup", systemImage: "terminal")
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.foreground)

            setupStep(number: "1", command: "hermes-mobile setup", detail: "One-time registration")
            setupStep(number: "2", command: "hermes-mobile pair-phone", detail: "Scan the code in-app")
            setupStep(number: "3", command: "hermes-mobile service install", detail: "Background uptime")
        }
        .padding(Design.Spacing.lg)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 0) {
            if hostStore.currentHost != nil {
                Button(role: .destructive) {
                    Task { await hostStore.revokeCurrentHost() }
                } label: {
                    actionRow(
                        icon: "desktopcomputer.trianglebadge.exclamationmark",
                        label: "Revoke Host",
                        color: .red
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
                    color: .red
                )
            }
        }
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    // MARK: - Components

    private func detailRow(icon: String, label: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.secondaryForeground)
                .frame(width: 20)
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
        }
        .frame(minHeight: Design.Size.minTapTarget)
    }

    private func setupStep(number: String, command: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Design.Brand.accent)
                .frame(width: 22, height: 22)
                .background(Design.Brand.accent.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Design.Colors.foreground)
                Text(detail)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    private func actionRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color.opacity(0.5))
        }
        .frame(minHeight: Design.Size.minTapTarget)
        .padding(.horizontal, Design.Spacing.lg)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.foreground)
                .lineLimit(2)
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        switch hostStore.connectionState {
        case .online:
            return .green
        case .offline, .unreachable:
            return .orange
        case .notConnected:
            return Design.Colors.secondaryForeground
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
