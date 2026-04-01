import SwiftUI

struct ConnectHermesHostScreen: View {
    @Environment(HermesHostStore.self) private var hostStore

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    heroSection
                    statusSection
                    setupCodeSection

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

            Text("Generate a short-lived setup code here, then run `hermes-mobile-connector enroll --code <HC1...>` on the machine where Hermes lives.")
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

            if hostStore.currentHost != nil {
                Button(role: .destructive) {
                    Task { await hostStore.revokeCurrentHost() }
                } label: {
                    Label("Revoke Current Host", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(hostStore.isWorking)
            }
        }
        .padding(Design.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private var setupCodeSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("Host Setup Code")
                .font(Design.Typography.sectionTitle)

            if let enrollmentCode = hostStore.activeEnrollmentCode {
                hostRow(title: "Relay", value: enrollmentCode.relayHost)
                if let expiresAt = enrollmentCode.expiresAt {
                    hostRow(title: "Expires", value: expiresAt.formatted(date: .abbreviated, time: .shortened))
                }

                Text(enrollmentCode.setupCode)
                    .font(Design.Typography.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(Design.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))

                HStack(spacing: Design.Spacing.sm) {
                    Button("Generate New Code") {
                        Task { await hostStore.generateEnrollmentCode() }
                    }
                    .buttonStyle(.glass)

                    ShareLink(item: enrollmentCode.setupCode) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
            } else {
                Text("Generate a code here, then redeem it on the machine running Hermes.")
                    .font(Design.Typography.callout)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await hostStore.generateEnrollmentCode() }
                } label: {
                    if hostStore.isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Generate Setup Code", systemImage: "desktopcomputer.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
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
