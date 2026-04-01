import SwiftUI

struct SettingsScreen: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    profileSection
                    connectionSection
                    if settingsStore.availableEnvironments.count > 1 {
                        environmentSection
                    }
                    notificationsSection
                    privacySection
                    aboutSection
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle("Settings")
        .task {
            await hostStore.refresh()
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        SettingsSectionView(title: "Profile") {
            HStack(spacing: Design.Spacing.md) {
                Text(settingsStore.settings.avatarInitials)
                    .font(.system(size: Design.Size.iconMedium, weight: .semibold, design: .rounded))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: Design.Size.avatarMedium, height: Design.Size.avatarMedium)
                    .clipShape(Circle())
                    .glassEffect(.regular, in: Circle())

                VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                    Text(settingsStore.settings.userName)
                        .font(Design.Typography.headline)
                    Text("Personal assistant profile")
                        .font(Design.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        @Bindable var settingsStore = settingsStore

        return SettingsSectionView(title: "Connection") {
            VStack(spacing: Design.Spacing.sm) {
                settingsRow(
                    icon: sessionStore.state.connectionStatus.displayIcon,
                    iconColor: sessionStore.state.connectionStatus.displayColor,
                    title: "Hermes Server",
                    subtitle: sessionStore.state.connectionStatus.displayLabel
                )

                settingsRow(
                    icon: sessionStore.state.syncStatus.displayIcon,
                    iconColor: sessionStore.state.syncStatus.displayColor,
                    title: "Sync Status",
                    subtitle: sessionStore.state.syncStatus.displayLabel
                )

                settingsRow(
                    icon: sessionStore.state.deviceRegistered ? "iphone.gen3" : "iphone.slash",
                    iconColor: sessionStore.state.deviceRegistered ? .green : .secondary,
                    title: "Device Registration",
                    subtitle: sessionStore.state.deviceRegistered ? "Registered" : "Pending"
                )

                settingsRow(
                    icon: sessionStore.state.pushTokenRegistered ? "bell.badge.fill" : "bell.slash",
                    iconColor: sessionStore.state.pushTokenRegistered ? .green : .secondary,
                    title: "Push Registration",
                    subtitle: sessionStore.state.pushTokenRegistered ? "Registered" : "Not Registered"
                )

                settingsRow(
                    icon: "clock.arrow.circlepath",
                    iconColor: .secondary,
                    title: "Last Sync",
                    subtitle: sessionStore.state.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                )

                if let pairedRelay = pairingStore.pairedRelayConfiguration {
                    settingsRow(
                        icon: "server.rack",
                        iconColor: .secondary,
                        title: "Relay Host",
                        subtitle: pairedRelay.hostDisplayName
                    )

                    settingsRow(
                        icon: "person.crop.circle",
                        iconColor: .secondary,
                        title: "Connected Account",
                        subtitle: sessionStore.state.displayName ?? "Unknown"
                    )

                    settingsRow(
                        icon: hostStore.isHostOnline ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark",
                        iconColor: hostStore.isHostOnline ? .green : .orange,
                        title: "Hermes Host",
                        subtitle: hostStore.currentHost?.resolvedDisplayName ?? "Not Connected"
                    )

                    if let host = hostStore.currentHost {
                        settingsRow(
                            icon: "clock.arrow.circlepath",
                            iconColor: .secondary,
                            title: "Host Last Seen",
                            subtitle: host.lastSeenAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"
                        )
                    }

                    if settingsStore.availableEnvironments.count > 1 {
                        Button {
                            router.navigate(to: .connectHost, in: .settings)
                        } label: {
                            HStack {
                                Label(hostStore.currentHost == nil ? "Connect Hermes Host" : "Manage Hermes Host", systemImage: "desktopcomputer.and.arrow.down")
                                    .font(Design.Typography.callout)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(Design.Typography.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: Design.Size.minTapTarget)
                        }
                    }

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

                Toggle(isOn: $settingsStore.settings.autoConnectOnLaunch) {
                    Label("Auto-Connect on Launch", systemImage: "bolt.fill")
                        .font(Design.Typography.callout)
                }
                .tint(Design.Brand.accent)
            }
        }
    }

    // MARK: - Environment

    private var environmentSection: some View {
        SettingsSectionView(title: "Environment") {
            VStack(spacing: Design.Spacing.sm) {
                ForEach(settingsStore.availableEnvironments, id: \.self) { env in
                    Button {
                        withAnimation(Design.Motion.quickResponse) {
                            settingsStore.settings.environment = env
                        }
                    } label: {
                        HStack {
                            Text(env.displayLabel)
                                .font(Design.Typography.callout)
                                .foregroundStyle(.primary)

                            Spacer()

                            if settingsStore.settings.environment == env {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Design.Brand.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(minHeight: Design.Size.minTapTarget)
                    }
                }

                settingsRow(
                    icon: "server.rack",
                    iconColor: .secondary,
                    title: "Backend Endpoint",
                    subtitle: sessionStore.state.backendEndpoint
                )
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        @Bindable var settingsStore = settingsStore

        return SettingsSectionView(title: "Notifications") {
            VStack(spacing: Design.Spacing.sm) {
                Toggle(isOn: $settingsStore.settings.notificationsEnabled) {
                    Label("Push Notifications", systemImage: "bell.fill")
                        .font(Design.Typography.callout)
                }
                .tint(Design.Brand.accent)

                Toggle(isOn: $settingsStore.settings.hapticFeedbackEnabled) {
                    Label("Haptic Feedback", systemImage: "hand.tap.fill")
                        .font(Design.Typography.callout)
                }
                .tint(Design.Brand.accent)
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        @Bindable var settingsStore = settingsStore

        return SettingsSectionView(title: "Privacy") {
            VStack(spacing: Design.Spacing.sm) {
                Toggle(isOn: $settingsStore.settings.analyticsEnabled) {
                    Label("Usage Analytics", systemImage: "chart.bar.fill")
                        .font(Design.Typography.callout)
                }
                .tint(Design.Brand.accent)

                Button {
                    router.navigate(to: .permissions)
                } label: {
                    HStack {
                        Label("Permissions", systemImage: "lock.shield.fill")
                            .font(Design.Typography.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Design.Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: Design.Size.minTapTarget)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSectionView(title: "About") {
            VStack(spacing: Design.Spacing.sm) {
                settingsRow(icon: "info.circle", iconColor: .secondary, title: "Version", subtitle: "1.0.0 (1)")
                settingsRow(icon: "doc.text", iconColor: .secondary, title: "Terms of Service", subtitle: nil)
                settingsRow(icon: "hand.raised", iconColor: .secondary, title: "Privacy Policy", subtitle: nil)
            }
        }
    }

    // MARK: - Helpers

    private func settingsRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: Design.Size.iconMedium)

            Text(title)
                .font(Design.Typography.callout)

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(Design.Typography.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: Design.Size.minTapTarget)
    }
}
