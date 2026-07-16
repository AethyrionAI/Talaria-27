import SwiftUI

// MARK: - Uplink settings screen (Settings → UPLINK)
//
// The DIRECT chat link to the Hermes Sessions API (:8642): live link status,
// base URL, a Keychain-backed API key, and pair / test-connection actions.
// Mirrors design/Settings.dc.html screen 02.
//
// The RELAY/DIRECT segment was RETIRED by Lane M (M-14, per #108's iPad
// lesson): relay-only cannot reach the Sessions API — the key is a separate
// plane the pairing QR doesn't carry — so Direct is the only workable mode,
// and profiles make it moot (every profile is Direct-with-its-own-key by
// construction). What replaced it is the honest state that mattered: a
// paired-but-UNKEYED profile says so here instead of failing silently.
struct UplinkSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var hermesAPIKeyDraft = ""
    @State private var hermesAPIKeySaving = false
    @State private var hermesAPIKeyJustSaved = false
    @State private var isTesting = false

    /// Prefers the direct Sessions API probe over the relay-based host state, so
    /// the link reads "online" when chat works even if the relay is down.
    private var effectiveConnectionState: HermesHostConnectionState {
        if container.chatStore.directConnectionStatus == .connected { return .online }
        return hostStore.connectionState
    }

    private var isDirect: Bool {
        container.chatStore.directConnectionStatus == .connected
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Uplink", subtitle: activeProfileName) { dismiss() }
                    linkStatusPanel
                    if showsUnkeyedNudge {
                        unkeyedProfileNotice
                    }
                    baseURLSection
                    apiKeySection
                    actionButtons
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Uplink")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await hostStore.refresh() }
        .onAppear { hermesAPIKeyDraft = container.hermesAPIKey }
    }

    // MARK: Link status panel

    private var linkStatusPanel: some View {
        HStack(spacing: Design.Spacing.sm) {
            ReactorOrb(size: Design.Size.orbPanel, style: .standard)

            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(linkTitle)
                    .font(Design.Typography.display(18, weight: .bold, relativeTo: .headline))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .lineLimit(1)

                MonoLabel(
                    linkDetail,
                    size: 10,
                    weight: .medium,
                    tracking: Design.Tracking.mono,
                    color: linkColor
                )
            }

            Spacer(minLength: Design.Spacing.xs)

            StatusPip(color: linkColor, diameter: 9, blinks: effectiveConnectionState == .unreachable)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.xl,
            borderColor: Design.Colors.strongBorder,
            fill: Design.Colors.accentTint(0.08),
            innerGlow: true
        )
    }

    private var linkTitle: String {
        switch effectiveConnectionState {
        case .online: isDirect ? "DIRECT LINK" : "RELAY LINK"
        case .offline: "STANDBY"
        case .unreachable: "OFFLINE"
        case .notConnected: "NOT LINKED"
        }
    }

    private var linkColor: Color {
        switch effectiveConnectionState {
        case .online: Design.Brand.accent
        case .offline, .unreachable: Design.Brand.forge
        case .notConnected: Design.Colors.mutedForeground
        }
    }

    private var linkDetail: String {
        switch effectiveConnectionState {
        case .online: "\(hostDisplay) · \(sessionStore.state.connectionStatus.displayLabel.uppercased())"
        case .offline: "\(hostDisplay) · STANDBY"
        case .unreachable: "UNREACHABLE · CHECK UPLINK"
        case .notConnected: "NOT CONFIGURED"
        }
    }

    private var hostDisplay: String {
        gatewayBaseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    /// Lane M: the ACTIVE profile's gateway is the source of truth; the
    /// legacy settings value remains as the profile-less fallback (bare test
    /// containers) and is mirror-written below so nothing drifts.
    private var gatewayBaseURL: String {
        container.profilesStore?.activeProfile?.gatewayBaseURL
            ?? settingsStore.settings.hermesAPIBaseURL
    }

    // MARK: Unkeyed-profile notice (M-14, per #108)

    /// True when the active profile is paired for the relay plane but has no
    /// Sessions API key — chat would fail silently without this state.
    /// Static so the rule is unit-testable (M-17).
    static func unkeyedNudgeVisible(isPaired: Bool, apiKey: String) -> Bool {
        isPaired && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsUnkeyedNudge: Bool {
        Self.unkeyedNudgeVisible(isPaired: pairingStore.isPaired, apiKey: container.hermesAPIKey)
    }

    private var unkeyedProfileNotice: some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: "key.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Design.Brand.forge)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                MonoLabel("PAIRED — KEY MISSING", size: 10, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Brand.forge)
                Text("\(activeProfileName) is paired for sensors, but chat needs its API key. Paste the API_SERVER_KEY from ~/.hermes/.env below.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Brand.forge.opacity(0.35),
            fill: Design.Brand.forge.opacity(0.07),
            innerGlow: false
        )
    }

    private var activeProfileName: String {
        container.profilesStore?.activeProfile?.name ?? "Hermes Host"
    }

    // MARK: Base URL

    private var baseURLSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("Base URL", size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)

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
    }

    // MARK: API key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                MonoLabel("API Key", size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                          color: Design.Colors.mutedForeground)
                Spacer()
                HStack(spacing: Design.Spacing.xxs) {
                    StatusPip(color: Design.Brand.accent, diameter: 5)
                    MonoLabel("Keychain", size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: Design.Brand.accent)
                }
            }

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
                saveKeyButton
            }
        }
    }

    private var saveKeyButton: some View {
        Button {
            Task { await saveHermesAPIKey() }
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                if hermesAPIKeySaving { ProgressView().controlSize(.mini) }
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

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: Design.Spacing.sm) {
            GlowButton(title: "Pair Device", systemImage: "link") {
                router.dismissSheet()
                router.navigate(to: .connectHost)
            }
            GhostButton(
                title: isTesting ? "Testing…" : "Test Connection",
                systemImage: "antenna.radiowaves.left.and.right"
            ) {
                Task { await testConnection() }
            }
        }
        .padding(.top, Design.Spacing.xs)
    }

    private func testConnection() async {
        isTesting = true
        await hostStore.refresh()
        await container.chatStore.refreshDirectHealth()
        isTesting = false
    }

    // MARK: Bindings / persistence

    private var hermesAPIBaseURLBinding: Binding<String> {
        Binding(
            get: { gatewayBaseURL },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                // Lane M: the active profile owns the endpoint; the legacy
                // settings field is mirror-written for downgrade safety.
                container.profilesStore?.updateActiveProfile { $0.gatewayBaseURL = trimmed }
                settingsStore.settings.hermesAPIBaseURL = trimmed
            }
        )
    }

    private func saveHermesAPIKey() async {
        hermesAPIKeySaving = true
        await container.saveHermesAPIKey(hermesAPIKeyDraft)
        hermesAPIKeySaving = false
        hermesAPIKeyJustSaved = true
        try? await Task.sleep(for: .seconds(1.5))
        hermesAPIKeyJustSaved = false
    }
}

// MARK: - HUD field background

private struct HUDFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Design.Colors.background.opacity(0.6),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.hairline, lineWidth: 1)
            }
    }
}
