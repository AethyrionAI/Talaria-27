import SwiftUI

// MARK: - Test Connection outcome (#151)

/// What a Test Connection attempt concluded. Joins the `ServerProbeResult`
/// wording family (— / ONLINE / NO KEY / OFFLINE) established by #84/#71
/// rather than inventing a third status vocabulary for the same screen.
enum ConnectionTestOutcome: Equatable {
    case passed(latencyMillis: Int)
    case failed(ConnectionTestFailure)
}

/// The failure shapes worth telling apart. #145/#136 established that a
/// refused connection, a firewall black-hole and an answering-but-unkeyed
/// host are three different problems with three different fixes — collapsing
/// them into one "failed" is what made the silent button useless.
enum ConnectionTestFailure: Equatable {
    /// Nothing is listening on that port — the fast-refuse shape.
    case refused
    /// No answer inside the probe budget — the firewall black-hole shape
    /// (DROP, not REFUSE), or a host that is simply powered down.
    case timedOut
    /// The name never resolved.
    case hostNotFound
    /// The host answered and rejected the key (401/403).
    case authRejected
    /// The host answered, but not with success — often a port pointed at a
    /// different service entirely.
    case unexpectedStatus(Int)
    /// Nothing to probe: no base URL, or one that isn't a valid address.
    case notConfigured(String)
    /// Anything else — no network, TLS failure, …
    case other(String)

    /// The mono status word, in the shared vocabulary where one already fits.
    var label: String {
        switch self {
        case .refused: "REFUSED"
        case .timedOut: "NO ANSWER"
        case .hostNotFound: "NO HOST"
        case .authRejected: "NO KEY"
        case .unexpectedStatus(let code): "HTTP \(code)"
        case .notConfigured: "NOT SET"
        case .other: "FAILED"
        }
    }

    /// One sentence naming the likely fix — the whole point of the item.
    var detail: String {
        switch self {
        case .refused:
            "Nothing is listening on that port. Check the port number and that Hermes is running."
        case .timedOut:
            "No reply within 5s. The host may be asleep, or a firewall may be dropping the connection."
        case .hostNotFound:
            "That address didn't resolve. Check the hostname, and that Tailscale is up."
        case .authRejected:
            "The host answered but rejected the key. Paste the API_SERVER_KEY from ~/.hermes/.env above."
        case .unexpectedStatus(let code):
            "The host answered with \(code). That port may belong to a different service."
        case .notConfigured(let reason):
            reason
        case .other(let reason):
            reason
        }
    }
}

/// The Test Connection control's lifecycle.
enum ConnectionTestState: Equatable {
    case idle
    case testing
    case done(ConnectionTestOutcome)
}

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
    /// #151: the Test Connection control's state. Replaces the old bare
    /// `isTesting` flag, which made success, failure and in-flight
    /// indistinguishable at exactly the moment the control exists to answer.
    @State private var testState: ConnectionTestState = .idle
    /// #127: the connect gate's locked state — presents the Connected
    /// paywall instead of enabling a new host. Inert while dormant.
    @State private var paywallPresented = false

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
        // #151: a verdict belongs to the endpoint it was measured against —
        // retyping the URL must not leave a stale ONLINE row underneath it.
        .onChange(of: gatewayBaseURL) { testState = .idle }
        .sheet(isPresented: $paywallPresented) {
            ConnectedPaywallSheet()
        }
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

    /// The active profile's relay-plane pairing state. Mirrors
    /// ServerSettingsScreen's accessor (there is no `pairingStore` in this
    /// view's environment); false when profiles haven't been wired yet.
    private var activeProfileIsPaired: Bool {
        guard let activeID = container.profilesStore?.activeProfileID,
              let sessions = container.profileRelaySessions else { return false }
        return sessions.isPaired(profileID: activeID)
    }

    private var showsUnkeyedNudge: Bool {
        Self.unkeyedNudgeVisible(isPaired: activeProfileIsPaired, apiKey: container.hermesAPIKey)
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
            // #152: the pairing surface owns revoke and disconnect too, so
            // the label can't advertise only pairing.
            GlowButton(title: "Pairing & Devices", systemImage: "link") {
                router.dismissSheet()
                router.navigate(to: .connectHost)
            }
            GhostButton(
                title: testState == .testing ? "Testing…" : "Test Connection",
                systemImage: "antenna.radiowaves.left.and.right"
            ) {
                Task { await testConnection() }
            }
            .disabled(testState == .testing)
            testStatusRow
        }
        .padding(.top, Design.Spacing.xs)
    }

    // MARK: Test Connection (#151)

    /// The probe budget. Deliberately NOT the shared client path: the Sessions
    /// client stamps `timeoutInterval = 300` on every request, so reusing
    /// `refreshDirectHealth()` here would leave Test Connection spinning for
    /// five minutes against a black-holed host — a worse papercut than the
    /// silence it replaces. A fast honest "no answer" beats a slow accurate one.
    static let probeTimeout: TimeInterval = 5

    private func testConnection() async {
        testState = .testing
        let outcome = await Self.probe(baseURL: gatewayBaseURL, apiKey: container.hermesAPIKey)
        testState = .done(outcome)
        // The link panel above is fed by the shared stores; refresh it
        // without gating the verdict on the 300s path.
        Task { await hostStore.refresh() }
    }

    /// Probes the ACTIVE profile's Sessions API (`/v1/models`) — the plane
    /// this screen is about. The relay and shim are independent planes with
    /// their own status surfaces (Settings → Server); a Test Connection that
    /// silently probed a different one would be worse than none.
    static func probe(
        baseURL: String,
        apiKey: String,
        session: URLSession = .shared
    ) async -> ConnectionTestOutcome {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .failed(.notConfigured("No base URL set. Enter the Sessions API endpoint above."))
        }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized + "/v1/models") else {
            return .failed(.notConfigured("That base URL isn't a valid address."))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = probeTimeout
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let started = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Int((Date().timeIntervalSince(started) * 1000).rounded())
            guard let http = response as? HTTPURLResponse else {
                return .failed(.other("The host replied, but not over HTTP."))
            }
            return outcome(statusCode: http.statusCode, latencyMillis: elapsed)
        } catch let error as URLError {
            return .failed(failure(for: error.code))
        } catch {
            return .failed(.other(error.localizedDescription))
        }
    }

    /// Status code → verdict. Defers to `ServerProbeResult.classify` so this
    /// screen and the Server screen can never disagree about what a 401 means.
    /// Static so the rule is unit-testable (M-17).
    static func outcome(statusCode: Int, latencyMillis: Int) -> ConnectionTestOutcome {
        switch ServerProbeResult.classify(statusCode: statusCode) {
        case .online: .passed(latencyMillis: latencyMillis)
        case .unauthorized: .failed(.authRejected)
        case .offline, .unknown: .failed(.unexpectedStatus(statusCode))
        }
    }

    /// Transport error → the three network shapes #145/#136 named. Static so
    /// the mapping is unit-testable without a socket.
    static func failure(for code: URLError.Code) -> ConnectionTestFailure {
        switch code {
        case .cannotConnectToHost: .refused
        case .timedOut: .timedOut
        case .cannotFindHost, .dnsLookupFailed: .hostNotFound
        case .notConnectedToInternet: .other("This device has no network connection.")
        case .appTransportSecurityRequiresSecureConnection:
            .other("App Transport Security blocked the request to that address.")
        default: .other("The connection failed (\(code.rawValue)).")
        }
    }

    @ViewBuilder
    private var testStatusRow: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            testRow(color: Design.Colors.secondaryForeground, showsSpinner: true) {
                MonoLabel("TESTING \(hostDisplay)", size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)
            }
        case .done(.passed(let latencyMillis)):
            testRow(color: Design.Brand.accent, showsSpinner: false) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    MonoLabel("ONLINE · \(latencyMillis) MS", size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.accent)
                    Text("\(hostDisplay) answered the Sessions API.")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
            }
        case .done(.failed(let failure)):
            testRow(color: Design.Brand.forge, showsSpinner: false) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    MonoLabel(failure.label, size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.forge)
                    Text(failure.detail)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
            }
        }
    }

    private func testRow<Content: View>(
        color: Color,
        showsSpinner: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            if showsSpinner {
                ProgressView().controlSize(.mini)
            } else {
                StatusPip(color: color, diameter: 7)
                    .padding(.top, 3)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: color.opacity(0.35),
            fill: color.opacity(0.07),
            innerGlow: false
        )
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

    /// #127: keying a host that has NO stored key is the act that enables
    /// direct chat — a new connect the gate may lock. Replacing or rotating
    /// an existing key is maintenance on an existing configuration and
    /// always passes (fail open). Static so the rule is unit-testable.
    static func keySaveAttempt(existingKey: String) -> ConnectAttempt {
        existingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .newConnect : .existingPairing
    }

    private func saveHermesAPIKey() async {
        let attempt = Self.keySaveAttempt(existingKey: container.hermesAPIKey)
        guard container.connectGateVerdict(for: attempt) == .allow else {
            paywallPresented = true
            return
        }
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
