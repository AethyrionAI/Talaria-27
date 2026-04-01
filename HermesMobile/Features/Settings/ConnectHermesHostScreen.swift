import SwiftUI

struct ConnectHermesHostScreen: View {
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    heroSection
                    statusSection
                    setupSection
                    dangerZoneSection

                    if let errorMessage = hostStore.lastErrorMessage {
                        errorCard(message: errorMessage)
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Connect Your Hermes Host")
                .font(Design.Typography.heroTitle)
                .foregroundStyle(.primary)

            Text("Host setup now starts from the machine running Hermes. Run `hermes-mobile setup`, then `hermes-mobile pair-phone`, and keep the connector available with either the background service or `hermes-mobile run`.")
                .font(Design.Typography.body)
                .foregroundStyle(.secondary)
        }
        .padding(Design.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Current Host")
                .font(Design.Typography.sectionTitle)

            if let host = hostStore.currentHost {
                hostRow(title: "Name", value: host.resolvedDisplayName)
                hostRow(title: "Status", value: host.isOnline ? "Online" : "Offline")
                if let lastSeenAt = host.lastSeenAt {
                    hostRow(title: "Last Seen", value: lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                }
            } else {
                Text("No Hermes host is connected yet.")
                    .font(Design.Typography.callout)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(Design.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("Setup From Your Hermes Machine")
                .font(Design.Typography.sectionTitle)

            Text("1. On the Hermes host, run `hermes-mobile setup` once.")
                .font(Design.Typography.callout)
                .foregroundStyle(.primary)

            Text("2. Generate a phone code with `hermes-mobile pair-phone`, then scan or enter that code in the app.")
                .font(Design.Typography.callout)
                .foregroundStyle(.primary)

            Text("3. For persistent uptime, run `hermes-mobile service install` and `hermes-mobile service start`.")
                .font(Design.Typography.callout)
                .foregroundStyle(.primary)

            Text("4. Use `hermes-mobile run` when you want foreground debugging instead.")
                .font(Design.Typography.callout)
                .foregroundStyle(.primary)
        }
        .padding(Design.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            if hostStore.currentHost != nil {
                Button(role: .destructive) {
                    Task { await hostStore.revokeCurrentHost() }
                } label: {
                    HStack {
                        Label("Revoke Current Host", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                            .font(Design.Typography.callout)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .frame(minHeight: Design.Size.minTapTarget)
                }
                .disabled(hostStore.isWorking)
            }

            Button {
                Task { await pairingStore.disconnect() }
            } label: {
                HStack {
                    Label("Disconnect Hermes", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(Design.Typography.callout)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .frame(minHeight: Design.Size.minTapTarget)
            }
        }
        .padding(Design.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private func hostRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Design.Typography.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Design.Typography.callout.monospaced())
                .multilineTextAlignment(.trailing)
        }
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(Design.Typography.callout)
                .foregroundStyle(.primary)
        }
        .padding(Design.Spacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
    }
}
