import SwiftUI

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(PermissionsStore.self) private var permissionsStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var hermesAPIKeyDraft: String = ""
    @State private var hermesAPIKeySaving = false
    @State private var hermesAPIKeyJustSaved = false

    var body: some View {
        ZStack {
            HUDScreenBackground(gridIntensity: 0.35)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    systemHeader
                    hostLinkPanel
                    connectionSection
                    hermesAPISection
                    modelsSection
                    relaySection
                    if settingsStore.availableEnvironments.count > 1 {
                        environmentSection
                    }
                    preferencesSection
                    locationSection
                    privacySection
                    aboutSection
                    footer
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Settings")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await hostStore.refresh()
            await permissionsStore.reloadCapabilities()
        }
    }

    // MARK: - Header

    private var systemHeader: some View {
        HStack {
            Text("SYSTEM")
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)

            Spacer()

            GlassCircleButton(icon: "xmark", accessibilityLabel: "Close settings") {
                dismiss()
            }
        }
        .padding(.top, Design.Spacing.xs)
    }

    // MARK: - Host link panel

    private var hostLinkPanel: some View {
        HStack(spacing: Design.Spacing.sm) {
            ReactorOrb(size: Design.Size.orbPanel, style: .standard)

            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(hostStatusRowValue)
                    .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .lineLimit(1)

                MonoLabel(
                    hostLinkStatusLine,
                    size: 10,
                    weight: .medium,
                    tracking: Design.Tracking.mono,
                    color: hostLinkStatusColor
                )
            }

            Spacer(minLength: Design.Spacing.xs)

            StatusPip(
                color: hostLinkStatusColor,
                diameter: 9,
                blinks: hostStore.connectionState == .unreachable
            )
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.xl,
            borderColor: Design.Colors.cyanBorder,
            fill: Design.Colors.accentTint(0.08),
            innerGlow: true
        )
    }

    private var hostLinkStatusColor: Color {
        switch hostStore.connectionState {
        case .online: Design.Brand.accent
        case .offline, .unreachable: Design.Brand.forge
        case .notConnected: Design.Colors.mutedForeground
        }
    }

    private var hostLinkStatusLine: String {
        switch hostStore.connectionState {
        case .online: "LINKED · \(sessionStore.state.connectionStatus.displayLabel.uppercased())"
        case .offline: "OFFLINE · STANDBY"
        case .unreachable: "UNREACHABLE · CHECK UPLINK"
        case .notConnected: "NOT LINKED"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        MonoLabel(
            "TALARIA v\(appVersionString) · DEVICE-BOUND",
            size: 9,
            weight: .regular,
            tracking: Design.Tracking.monoWide,
            color: Design.Colors.dimForeground
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Design.Spacing.sm)
        .padding(.bottom, Design.Spacing.lg)
    }

    private var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    // MARK: - Connection

    private var connectionSection: some View {
        SettingsSectionView(title: "Connection") {
            VStack(spacing: 0) {
                settingsRow(
                    icon: sessionStore.state.connectionStatus.displayIcon,
                    iconColor: sessionStore.state.connectionStatus.displayColor,
                    title: "Status",
                    value: sessionStore.state.connectionStatus.displayLabel
                )

                sectionDivider

                if pairingStore.pairedRelayConfiguration != nil {
                    settingsNavRow(
                        icon: hostStatusRowIcon,
                        iconColor: hostStatusRowColor,
                        title: "Hermes Host",
                        value: hostStatusRowValue,
                        accessibilityIdentifier: "settings.hermesHost"
                    ) {
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            router.navigate(to: .connectHost)
                        }
                    }

                    sectionDivider
                }

                settingsToggle(
                    icon: "bolt.fill",
                    iconColor: Design.Brand.accent,
                    title: "Auto-Connect",
                    isOn: autoConnectBinding
                )
            }
        }
    }

    // MARK: - Hermes API (Sessions)

    private var hermesAPISection: some View {
        SettingsSectionView(title: "Hermes API") {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    MonoLabel(
                        "Base URL",
                        size: 9,
                        weight: .medium,
                        tracking: Design.Tracking.monoWide,
                        color: Design.Colors.mutedForeground
                    )

                    TextField("http://ojamd:8642", text: hermesAPIBaseURLBinding)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .font(Design.Typography.callout.monospaced())
                        .foregroundStyle(Design.Colors.foreground)
                        .padding(Design.Spacing.md)
                        .modifier(HUDFieldBackground())

                    Text("Hermes Sessions API endpoint, e.g. http://ojamd:8642.")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }

                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    MonoLabel(
                        "API Key",
                        size: 9,
                        weight: .medium,
                        tracking: Design.Tracking.monoWide,
                        color: Design.Colors.mutedForeground
                    )

                    SecureField("Bearer key from ~/.hermes/.env", text: $hermesAPIKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Design.Typography.callout.monospaced())
                        .foregroundStyle(Design.Colors.foreground)
                        .padding(Design.Spacing.md)
                        .modifier(HUDFieldBackground())

                    HStack {
                        Text(container.hermesAPIKey.isEmpty ? "No key stored." : "Key stored in Keychain.")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                        Spacer()
                        Button {
                            Task { await saveHermesAPIKey() }
                        } label: {
                            HStack(spacing: Design.Spacing.xs) {
                                if hermesAPIKeySaving {
                                    ProgressView().controlSize(.mini)
                                }
                                Text((hermesAPIKeyJustSaved ? "Saved" : "Save").uppercased())
                                    .font(Design.Typography.mono(11, weight: .medium))
                                    .tracking(Design.Tracking.mono)
                            }
                            .foregroundStyle(Design.Brand.accentBright)
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.vertical, Design.Spacing.xs)
                            .background(Design.Colors.accentTint(0.10), in: Capsule())
                            .overlay { Capsule().strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .disabled(hermesAPIKeyDraft == container.hermesAPIKey)
                    }
                }
            }
        }
        .onAppear {
            hermesAPIKeyDraft = container.hermesAPIKey
        }
    }

    private func saveHermesAPIKey() async {
        hermesAPIKeySaving = true
        await container.saveHermesAPIKey(hermesAPIKeyDraft)
        hermesAPIKeySaving = false
        hermesAPIKeyJustSaved = true
        try? await Task.sleep(for: .seconds(1.5))
        hermesAPIKeyJustSaved = false
    }

    // MARK: - Models

    private var modelsSection: some View {
        SettingsSectionView(title: "Models") {
            NavigationLink {
                ModelsSettingsScreen()
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "cpu")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Design.Brand.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Model Picker")
                            .font(Design.Typography.body(15, weight: .medium))
                            .foregroundStyle(Design.Colors.foreground)
                        Text(container.chatStore.activeModelName ?? "Pick the active + default model")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: Design.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Environment

    private var relaySection: some View {
        SettingsSectionView(title: "Relay") {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                if pairingStore.isPaired {
                    settingsRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        iconColor: Design.Brand.accent,
                        title: "Active Relay",
                        value: pairingStore.pairedRelayConfiguration?.hostDisplayName ?? relayConfiguration.relayOriginLabel
                    )
                    sectionDivider
                    settingsRow(
                        icon: "link",
                        iconColor: Design.Colors.mutedForeground,
                        title: "Base URL",
                        value: pairingStore.pairedRelayConfiguration?.baseURLString ?? relayConfiguration.activeBaseURLString ?? "Not configured"
                    )
                    Text("Disconnect Hermes before changing the relay configuration.")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .padding(.top, Design.Spacing.xs)
                } else {
                    if relayConfiguration.canUseHosted {
                        Picker("Relay Mode", selection: relayModeBinding) {
                            Text(RelayMode.custom.displayLabel).tag(RelayMode.custom)
                            Text(RelayMode.hosted.displayLabel).tag(RelayMode.hosted)
                        }
                        .pickerStyle(.segmented)

                        sectionDivider
                    }

                    if relayConfiguration.relayMode == .custom {
                        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                            TextField("https://your-relay.example.com/v1", text: customRelayURLBinding)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .font(Design.Typography.callout.monospaced())
                                .foregroundStyle(Design.Colors.foreground)
                                .padding(Design.Spacing.md)
                                .modifier(HUDFieldBackground())

                            Text("Enter the relay API base URL your connector will use.")
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.secondaryForeground)
                        }
                    } else if let hostedRelayBaseURL = relayConfiguration.hostedRelayBaseURL {
                        settingsRow(
                            icon: "cloud",
                            iconColor: Design.Brand.accent,
                            title: "Hosted Relay",
                            value: hostedRelayBaseURL
                        )
                    }

                    if let relayValidationMessage {
                        Text(relayValidationMessage)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Brand.forge)
                    }
                }
            }
        }
    }

    private var hostStatusRowIcon: String {
        switch hostStore.connectionState {
        case .online:
            return "desktopcomputer"
        case .offline:
            return "desktopcomputer.trianglebadge.exclamationmark"
        case .unreachable:
            return "wifi.exclamationmark"
        case .notConnected:
            return "desktopcomputer"
        }
    }

    private var hostStatusRowColor: Color {
        switch hostStore.connectionState {
        case .online:
            return .green
        case .offline, .unreachable:
            return .orange
        case .notConnected:
            return Design.Colors.secondaryForeground
        }
    }

    private var hostStatusRowValue: String {
        switch hostStore.connectionState {
        case .online, .offline:
            return hostStore.currentHost?.resolvedDisplayName ?? "Hermes Host"
        case .unreachable:
            return "Status unavailable"
        case .notConnected:
            return "Not Connected"
        }
    }

    private var environmentSection: some View {
        SettingsSectionView(title: "Internal Environment") {
            VStack(spacing: 0) {
                ForEach(Array(settingsStore.availableEnvironments.enumerated()), id: \.element) { index, env in
                    Button {
                        withAnimation(Design.Motion.quickResponse) {
                            settingsStore.settings.environment = env
                        }
                    } label: {
                        HStack {
                            Text(env.displayLabel)
                                .font(Design.Typography.callout)
                                .foregroundStyle(Design.Colors.foreground)

                            Spacer()

                            if settingsStore.settings.environment == env {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Design.Brand.accent)
                            }
                        }
                        .frame(minHeight: Design.Size.minTapTarget)
                    }

                    if index < settingsStore.availableEnvironments.count - 1 {
                        sectionDivider
                    }
                }
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        SettingsSectionView(title: "Preferences") {
            VStack(spacing: 0) {
                settingsToggle(
                    icon: "bell.fill",
                    iconColor: Design.Brand.accent,
                    title: "Notifications",
                    isOn: notificationsBinding
                )

                sectionDivider

                settingsToggle(
                    icon: "hand.tap.fill",
                    iconColor: Design.Brand.accent,
                    title: "Haptic Feedback",
                    isOn: hapticBinding
                )
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        SettingsSectionView(title: "Location") {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                settingsRow(
                    icon: "location.fill",
                    iconColor: Design.Brand.accent,
                    title: "Authorization",
                    value: permissionsStore.locationAuthorizationLevel.displayLabel
                )

                sectionDivider

                settingsRow(
                    icon: "scope",
                    iconColor: Design.Brand.accent,
                    title: "Accuracy",
                    value: permissionsStore.locationAccuracyLevel.displayLabel
                )

                sectionDivider

                settingsToggle(
                    icon: "location.circle.fill",
                    iconColor: Design.Brand.accent,
                    title: "Background Location",
                    isOn: backgroundLocationBinding
                )

                Text(backgroundLocationDescription)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        SettingsSectionView(title: "Privacy") {
            settingsNavRow(
                icon: "lock.shield.fill",
                iconColor: Design.Brand.accent,
                title: "Permissions"
            ) {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    router.navigate(to: .permissions)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSectionView(title: "About") {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "info.circle",
                    iconColor: Design.Colors.mutedForeground,
                    title: "Version",
                    value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "1"))"
                )

                sectionDivider

                settingsNavRow(
                    icon: "doc.text",
                    iconColor: Design.Colors.mutedForeground,
                    title: "Terms of Service"
                ) {
                    openConfiguredURL(settingsStore.buildConfiguration.termsOfServiceURL)
                }

                sectionDivider

                settingsNavRow(
                    icon: "hand.raised",
                    iconColor: Design.Colors.mutedForeground,
                    title: "Privacy Policy"
                ) {
                    openConfiguredURL(settingsStore.buildConfiguration.privacyPolicyURL)
                }

                if settingsStore.buildConfiguration.supportURL != nil {
                    sectionDivider

                    settingsNavRow(
                        icon: "questionmark.circle",
                        iconColor: Design.Colors.mutedForeground,
                        title: "Support"
                    ) {
                        openConfiguredURL(settingsStore.buildConfiguration.supportURL)
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private var autoConnectBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.autoConnectOnLaunch },
            set: { settingsStore.settings.autoConnectOnLaunch = $0 }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.notificationsEnabled },
            set: { newValue in
                settingsStore.settings.notificationsEnabled = newValue
                // Immediately register or deactivate push token on the relay
                Task {
                    let container = AppContainer.sharedDefault()
                    if let token = UserDefaults.standard.string(forKey: "hermes.apns.deviceToken") {
                        await container.registerPushTokenIfNeeded(token)
                    }
                }
            }
        )
    }

    private var hapticBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hapticFeedbackEnabled },
            set: { settingsStore.settings.hapticFeedbackEnabled = $0 }
        )
    }

    private var backgroundLocationBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.locationSyncPreference == .backgroundAllowed },
            set: { isEnabled in
                let preference: LocationSyncPreference = isEnabled ? .backgroundAllowed : .foregroundOnly
                settingsStore.settings.locationSyncPreference = preference
                permissionsStore.updateLocationSyncPreference(preference)

                guard isEnabled else { return }

                Task {
                    switch permissionsStore.locationAuthorizationLevel {
                    case .denied, .restricted:
                        permissionsStore.openLocationSystemSettings()
                    case .always, .whenInUse:
                        // Both levels support CLBackgroundActivitySession.
                        // While In Use shows blue indicator; Always does not.
                        await permissionsStore.requestBackgroundLocationAccess()
                    case .notDetermined:
                        await permissionsStore.requestBackgroundLocationAccess()
                    }
                }
            }
        )
    }

    private var relayConfiguration: RelayConfiguration {
        settingsStore.settings.relayConfiguration
    }

    private var relayValidationMessage: String? {
        relayConfiguration.validationMessage
    }

    private var backgroundLocationDescription: String {
        if settingsStore.settings.locationSyncPreference == .backgroundAllowed {
            switch permissionsStore.locationAuthorizationLevel {
            case .always:
                return "Hermes receives location updates in the background without the blue indicator."
            case .whenInUse:
                return "Hermes receives background location updates. A blue indicator appears at the top of the screen when active."
            case .notDetermined:
                return "Enabling this will request location access so Hermes can sync while backgrounded."
            case .denied, .restricted:
                return "Location is blocked at the system level. Open Settings to allow Hermes to request background updates."
            }
        }

        return "Foreground-only keeps location updates limited to active app use."
    }

    private var relayModeBinding: Binding<RelayMode> {
        Binding(
            get: { settingsStore.settings.relayConfiguration.relayMode },
            set: { newValue in
                var relayConfiguration = settingsStore.settings.relayConfiguration
                relayConfiguration.relayMode = newValue
                settingsStore.settings.relayConfiguration = relayConfiguration
            }
        )
    }

    private var customRelayURLBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.relayConfiguration.customRelayBaseURL },
            set: { newValue in
                var relayConfiguration = settingsStore.settings.relayConfiguration
                relayConfiguration.customRelayBaseURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsStore.settings.relayConfiguration = relayConfiguration
            }
        )
    }

    private var hermesAPIBaseURLBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.hermesAPIBaseURL },
            set: { newValue in
                settingsStore.settings.hermesAPIBaseURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    // MARK: - Row Components

    private var sectionDivider: some View {
        Rectangle()
            .fill(Design.Colors.cyanHairline)
            .frame(height: 1)
    }

    private func settingsRow(icon: String, iconColor: Color, title: String, value: String?) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .center)

            Text(title)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)

            Spacer()

            if let value {
                Text(value.uppercased())
                    .font(Design.Typography.mono(11, weight: .medium))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Brand.accent)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: Design.Size.minTapTarget)
    }

    @ViewBuilder
    private func settingsNavRow(
        icon: String,
        iconColor: Color,
        title: String,
        value: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let row = Button(action: action) {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, alignment: .center)

                Text(title)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)

                Spacer()

                if let value {
                    Text(value.uppercased())
                        .font(Design.Typography.mono(11, weight: .medium))
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Brand.accent)
                        .multilineTextAlignment(.trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Colors.accentTint(0.7))
            }
            .frame(minHeight: Design.Size.minTapTarget)
        }

        if let accessibilityIdentifier {
            row.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            row
        }
    }

    private func settingsToggle(
        icon: String,
        iconColor: Color,
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, alignment: .center)

                Text(title)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
            }
        }
        .tint(Design.Brand.accent)
        .frame(minHeight: Design.Size.minTapTarget)
    }

    private func openConfiguredURL(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }
}

// MARK: - HUD field background

/// Dark input-field background with a cyan hairline border, matching the HUD
/// text-entry treatment in the design reference.
private struct HUDFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Design.Colors.background.opacity(0.6),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.cyanHairline, lineWidth: 1)
            }
    }
}
