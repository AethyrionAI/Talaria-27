import SwiftUI

// MARK: - Server settings screen (Settings → SERVER, Lane M / OPEN_ITEMS #114)
//
// The backend-profile switcher: one card per named backend (OJAMD, Mac Mini),
// showing active state, live reachability (gateway answer —
// real probes only, "—" until probed), and per-profile paired state. Tap a
// card to activate (confirm sheet; non-destructive by construction — M-6),
// add/edit/delete profiles, pair each through the existing QR flow (M-12).
// Replaces the retired Relay sub-page (M-13); the auto-connect toggle moved
// here with it.

/// One probe's outcome. Honest states only: `unknown` renders as "—".
enum ServerProbeResult: Equatable {
    case unknown
    case online
    /// The host answered but refused the credential (401/403) — reachable,
    /// but this profile's key is wrong or missing.
    case unauthorized
    case offline

    /// Classification from an HTTP status code — pure for tests (M-17).
    static func classify(statusCode: Int) -> ServerProbeResult {
        switch statusCode {
        case 200 ..< 300: .online
        case 401, 403: .unauthorized
        default: .offline
        }
    }


    var label: String {
        switch self {
        case .unknown: "—"
        case .online: "ONLINE"
        case .unauthorized: "NO KEY"
        case .offline: "OFFLINE"
        }
    }
}

struct ServerProfileReachability: Equatable {
    var gateway: ServerProbeResult = .unknown
}

struct ServerSettingsScreen: View {
    // #252: deck pages supply the background and top bar; the screen keeps
    // owning its content, tasks, and sheets in both presentations.
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var reachability: [UUID: ServerProfileReachability] = [:]
    /// #251-2A: the active profile's talaria plugin-link pairing, resolved by
    /// an async Keychain read on appear.
    @State private var talariaLink: TalariaLinkDisplayState = .unknown
    @State private var pendingActivation: BackendProfile?
    @State private var editorTarget: ProfileEditorTarget?
    /// #153: delete is destructive AND purges the profile's Keychain
    /// credentials — it confirms, exactly like the (less destructive) Forget
    /// Pairing already did.
    @State private var pendingDelete: BackendProfile?
    @State private var deleteErrorMessage: String?
    /// #127: the connect gate's locked state — presents the Connected
    /// paywall instead of the add/pair action. Inert while dormant.
    @State private var paywallPresented = false

    private enum ProfileEditorTarget: Identifiable {
        case add
        case edit(BackendProfile)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let profile): profile.id.uuidString
            }
        }
    }

    // #224: the HOST's approval mode — three-valued, response-driven.
    // UNKNOWN is the default branch (#180 rule 5): the picker renders "—"
    // and disabled until the read answers; it never guesses.
    @State private var hostApprovalMode: HostApprovalModeState = .unknown
    @State private var hostApprovalMessage: String?
    @State private var hostApprovalSetInFlight = false

    // #224: the approval-mode picker's pinned copy — statics so the copy
    // pins can reach them (#396's convention).
    static let approvalCaption = "The host's persistent approval mode for dangerous commands — the same switch as its /approvals command."
    static let approvalPredatesFootnote = "This Hermes host predates approval modes — the picker unlocks after the host updates."

    var body: some View {
        ZStack {
            if !embedded {
                HUDScreenBackground()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if !embedded {
                        SettingsScreenHeader(title: "Server", subtitle: "Backend Profiles") { dismiss() }
                    }
                    if embedded {
                        SubsystemHero(
                            motif: .profileBars,
                            title: SettingsSubsystem.server.title,
                            status: SettingsCardValues.server(
                                activeProfileName: container.profilesStore?.activeProfile?.name,
                                hasHost: container.hasGatewayCredentials),
                            statusColor: container.profilesStore?.activeProfile != nil
                                ? Design.Brand.accentText : Design.Colors.mutedForeground,
                            chip: SettingsSubsystem.server.chip,
                            accented: container.profilesStore?.activeProfile != nil
                        )
                    }
                    profileCards
                    talariaLinkPanel
                    hostApprovalPanel
                    addProfileButton
                    autoConnectPanel
                    if let deleteErrorMessage {
                        errorNotice(deleteErrorMessage)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Server")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await probeAllProfiles() }
        // #251-2A: KEYED on the active profile, not a plain `.task`. The
        // switch happens on THIS screen (the confirm alert is
        // `setActiveProfile`'s only caller), so a plain `.task` never re-fires
        // and the row would go on asserting the PREVIOUS profile's pairing —
        // confidently wrong, which is worse than "—". A local Keychain read,
        // so it settles ahead of the probes above rather than behind them.
        .task(id: container.profilesStore?.activeProfileID) {
            await refreshTalariaLinkState()
            // #224: same invalidation the link row argued for — a switched
            // profile's mode must not survive as the new host's claim.
            await refreshHostApprovalMode()
        }
        // #193: was a `.confirmationDialog`, whose cancel role does not
        // render on iOS 26/27. Non-destructive, but a one-button sheet with
        // no visible decline reads as a forced choice for something that
        // re-homes the whole app — an alert keeps the explicit Cancel.
        .alert(
            "Switch backend?",
            isPresented: Binding(
                get: { pendingActivation != nil },
                set: { if !$0 { pendingActivation = nil } }
            ),
            presenting: pendingActivation
        ) { profile in
            Button("Switch to \(profile.name)") {
                pendingActivation = nil
                container.profilesStore?.setActiveProfile(profile.id)
            }
            Button("Cancel", role: .cancel) { pendingActivation = nil }
        } message: { profile in
            Text("New chats, inbox, and models will use \(profile.name). Existing conversations keep talking to the host they started on, and sensors stay on their pinned destination. Nothing is un-paired.")
        }
        // #309 Lane B: the "Forget this pairing?" alert is DELETED with
        // `PairingStore.forgetPairing`. Its subject was a relay-era pairing
        // record — and its message ("you'll need to pair again to resume its
        // sensor path") named a pipeline #352 deleted. Disconnect, on Connect
        // Host, is the forget-this-host action; Delete below still removes the
        // profile and purges its Keychain slots.
        // #193: destructive confirmation → `.alert` (visible Cancel).
        .alert(
            "Delete this profile?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { profile in
            Button("Delete \(profile.name)", role: .destructive) {
                let target = profile
                pendingDelete = nil
                deleteProfile(target)
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { profile in
            Text("Removes \(profile.name) and its stored credentials — its API key and this phone's link to it — from this device. Conversations that started on it stay in your history but can't reach it again until you re-add it. Other profiles are untouched.")
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .add:
                ProfileEditorSheet(existing: nil)
            case .edit(let profile):
                ProfileEditorSheet(existing: profile)
            }
        }
        .sheet(isPresented: $paywallPresented) {
            ConnectedPaywallSheet()
        }
    }

    // MARK: Cards

    private var profiles: [BackendProfile] {
        container.profilesStore?.profiles ?? []
    }

    private var profileCards: some View {
        VStack(spacing: Design.Spacing.sm) {
            ForEach(profiles) { profile in
                profileCard(profile)
            }
        }
    }

    private func profileCard(_ profile: BackendProfile) -> some View {
        let isActive = container.profilesStore?.activeProfileID == profile.id
        // #309 Lane C: the badge asks whether this profile can reach a Hermes
        // host — gateway URL + key — instead of whether it holds a relay-era
        // pairing record. The old predicate answered YES forever for any
        // profile that ever paired (the record outlives the relay it names)
        // and NO for every gateway-only one.
        let isKeyed = container.hasGatewayCredentials(forProfileID: profile.id)
        let probes = reachability[profile.id] ?? ServerProfileReachability()

        return ZStack(alignment: .topTrailing) {
            profileCardBody(
                profile,
                isActive: isActive,
                isKeyed: isKeyed,
                probes: probes
            )

            // #153: the SAME actions the long-press offers, given a visible
            // affordance. They were discoverable only by long-pressing a card
            // that gave no sign it was long-pressable — which is why "add a
            // delete feature" was filed against a screen that already had one.
            Menu {
                profileActions(profile, isActive: isActive, isKeyed: isKeyed)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(profile.name) actions")
        }
    }

    private func profileCardBody(
        _ profile: BackendProfile,
        isActive: Bool,
        isKeyed: Bool,
        probes: ServerProfileReachability
    ) -> some View {
        Button {
            guard !isActive else { return }
            pendingActivation = profile
        } label: {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                HStack(spacing: Design.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Design.Spacing.xs) {
                            Text(profile.name)
                                .font(Design.Typography.body(16, weight: .medium))
                                .foregroundStyle(isActive ? Design.Colors.foregroundBright : Design.Colors.foreground)
                                .lineLimit(1)
                            if isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Design.Brand.accentText)
                                    .accessibilityLabel("Active profile")
                            }
                        }
                        MonoLabel(hostLabel(for: profile), size: 10, tracking: Design.Tracking.mono,
                                  color: Design.Colors.secondaryForeground)
                            .lineLimit(1)
                        if let note = profile.note, !note.isEmpty {
                            Text(note)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.mutedForeground)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: Design.Spacing.xs)
                    VStack(alignment: .trailing, spacing: Design.Spacing.xxs) {
                        if isActive {
                            tag("ACTIVE", color: Design.Brand.accentText)
                        }
                    }
                }
                // #153: reserve the gutter the actions menu floats in, so
                // neither the name nor the tags sit underneath it.
                .padding(.trailing, Design.Spacing.lg)

                HStack(spacing: Design.Spacing.md) {
                    statusRow("GATEWAY", result: probes.gateway)
                    Spacer(minLength: 0)
                    // #309 Lane C: "KEYED"/"NO KEY", not "PAIRED"/"NOT
                    // PAIRED". The badge reports gateway credentials now, and
                    // the app already speaks this word — `ServerProbeResult`
                    // classifies a 401/403 gateway answer as `.unkeyed`, and
                    // the Uplink screen's nudge is the unkeyed-profile notice.
                    MonoLabel(isKeyed ? "KEYED" : "NO KEY", size: 9, weight: .medium,
                              tracking: Design.Tracking.mono,
                              color: isKeyed ? Design.Brand.accentText : Design.Colors.mutedForeground)
                }
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: isActive ? Design.Colors.accentTint(0.4) : Design.Colors.accentTint(0.12),
                fill: isActive ? Design.Colors.accentTint(0.08) : Design.Colors.background.opacity(0.5),
                innerGlow: isActive
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile.name)\(isActive ? ", active" : ""), \(isKeyed ? "keyed" : "no key")")
        .contextMenu {
            profileActions(profile, isActive: isActive, isKeyed: isKeyed)
        }
    }

    /// The per-profile action set, shared verbatim by the long-press context
    /// menu and the visible actions menu (#153) so the two can never drift.
    @ViewBuilder
    private func profileActions(
        _ profile: BackendProfile,
        isActive: Bool,
        isKeyed: Bool
    ) -> some View {
        Button {
            editorTarget = .edit(profile)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        // #309 Lane B: "Pair"/"Re-Pair" became "Connect"/"Reconnect" with the
        // vocabulary. There is no pairing ceremony left to name — the action
        // acquires two values and probes them.
        Button {
            startConnect(profile)
        } label: {
            Label(isKeyed ? "Reconnect" : "Connect", systemImage: "link")
        }
        // #309 Lane B: the FORGET PAIRING row is DELETED with `PairingStore`.
        // It cleared a relay-era pairing record — a row that, on the gateway
        // plane, has nothing to clear. The forget-this-host action is Connect
        // Host's Disconnect, which clears the credentials that actually exist;
        // DELETE below is still the louder one that removes the profile.
        if !isActive {
            // #153: confirms before deleting — this purges Keychain
            // credentials, so it is strictly more destructive than Forget
            // Pairing, which already confirmed.
            Button(role: .destructive) {
                pendingDelete = profile
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        MonoLabel(text, size: 8, weight: .medium, tracking: Design.Tracking.mono, color: color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
                    .strokeBorder(color.opacity(0.35), lineWidth: 1)
            }
    }

    private func statusRow(_ label: String, result: ServerProbeResult) -> some View {
        HStack(spacing: Design.Spacing.xxs) {
            StatusPip(color: probeColor(result), diameter: 6)
            MonoLabel("\(label) \(result.label)", size: 9, tracking: Design.Tracking.mono,
                      color: probeColor(result))
        }
    }

    private func probeColor(_ result: ServerProbeResult) -> Color {
        switch result {
        case .unknown: Design.Colors.mutedForeground
        case .online: Design.Brand.accentText
        case .unauthorized: Design.Brand.forgeText
        case .offline: Design.Colors.dangerText
        }
    }

    private func hostLabel(for profile: BackendProfile) -> String {
        let trimmed = profile.gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "NO GATEWAY SET" }
        return URL(string: trimmed)?.host ?? trimmed
    }

    // MARK: Actions

    private var addProfileButton: some View {
        GhostButton(title: "Add Profile", systemImage: "plus") {
            // #127: adding a backend profile is a new-connect entry point.
            guard container.connectGateVerdict(for: .newConnect) == .allow else {
                paywallPresented = true
                return
            }
            editorTarget = .add
        }
    }

    private func startConnect(_ profile: BackendProfile) {
        // #127: connecting an UNKEYED profile is a new connect; re-opening one
        // that already holds credentials is an existing connection and always
        // passes (the fail-open rule — a flaky entitlement check must never
        // stand between the user and a host they already have).
        let isKeyed = container.hasGatewayCredentials(forProfileID: profile.id)
        guard container.connectGateVerdict(for: isKeyed ? .existingPairing : .newConnect) == .allow else {
            paywallPresented = true
            return
        }
        // #309 Lane B: the target rides the ROUTE. It used to be assigned to
        // `PairingStore.pairingTargetProfileID` here and cleared by the
        // destination screen's `onDisappear` — a target that outlived a
        // mis-dismissed screen pointed the next visit at the wrong profile.
        router.dismissSheet()
        router.navigate(to: .connectHost(container.connectHostEntry(profileID: profile.id)))
    }

    private func deleteProfile(_ profile: BackendProfile) {
        guard let profilesStore = container.profilesStore else { return }
        do {
            try profilesStore.deleteProfile(id: profile.id)
            deleteErrorMessage = nil
            reachability[profile.id] = nil
        } catch BackendProfilesStore.DeleteError.profileIsActive {
            deleteErrorMessage = "Switch to another profile before deleting the active one."
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private func errorNotice(_ message: String) -> some View {
        Text(message)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Brand.forgeText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoNotice(_ message: String) -> some View {
        Text(message)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Colors.secondaryForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Plugin link (#251-2A)

    /// The active profile's talaria plugin link, MEASURED (#269-A): a live
    /// probe of the events route composed with the held credential —
    /// LIVE · PAIRED / LIVE · NOT PAIRED / NOT LIVE / HOST UNREACHABLE.
    /// Read-only and real — the link pairs itself on its first drain; there
    /// is no button here, because there is no user action that would make
    /// it happen sooner.
    private var talariaLinkPanel: some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: talariaLinkColor, diameter: 6)
            MonoLabel("PLUGIN LINK", size: 9, weight: .medium, tracking: Design.Tracking.mono,
                      color: Design.Colors.secondaryForeground)
            Spacer(minLength: Design.Spacing.xs)
            MonoLabel(talariaLink.label, size: 9, weight: .medium, tracking: Design.Tracking.mono,
                      color: talariaLinkColor)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.server.talariaLink")
        .accessibilityLabel("Plugin link \(talariaLink.label)")
    }

    private var talariaLinkColor: Color {
        switch talariaLink {
        case .livePaired: Design.Brand.accentText
        case .notLive: Design.Brand.forgeText
        case .unknown, .liveNotPaired, .hostUnreachable: Design.Colors.mutedForeground
        }
    }

    private func refreshTalariaLinkState() async {
        // Drop to "—" while the reads are in flight: on a profile switch the
        // held value describes the profile we just left (#269-A keeps that
        // honest decay and adds the probe half — the Keychain no longer
        // decides alone).
        talariaLink = .unknown
        guard let profile = container.profilesStore?.activeProfile else { return }
        async let token = container.talariaDeviceToken(for: profile)
        async let observation = container.talariaPlatformLink?.probeLinkState()
        talariaLink = TalariaLinkDisplayState.compose(
            observation: await observation,
            deviceToken: await token
        )
    }

    // MARK: Host approval mode (#224)

    /// The host's persistent approval mode — upstream's own `/approvals`
    /// switch, reached through the plugin verb behind the pairing's device
    /// auth. Three-valued and response-driven: the picker lands on what the
    /// HOST reports, never on what was tapped (224-APP-E).
    private var hostApprovalPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                MonoLabel("APPROVALS", size: 9, weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                Spacer(minLength: Design.Spacing.xs)
                switch hostApprovalMode {
                case .unknown:
                    MonoLabel("—", size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: Design.Colors.mutedForeground)
                case .unsupported:
                    MonoLabel("HOST PREDATES", size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: Design.Brand.forgeText)
                case .mode(let mode):
                    MonoLabel(mode.uppercased(), size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: Design.Brand.accentText)
                }
            }

            HStack(spacing: 0) {
                ForEach(HostApprovalModeState.selectableModes, id: \.self) { mode in
                    approvalSegment(mode)
                }
            }
            .background(Design.Colors.background.opacity(0.5), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.hairline, lineWidth: 1)
            }
            .disabled(hostApprovalSetInFlight || !isHostApprovalPickerEnabled)
            .opacity(isHostApprovalPickerEnabled ? 1 : 0.45)

            Text(Self.approvalCaption)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)

            if case .unsupported = hostApprovalMode {
                Text(Self.approvalPredatesFootnote)
                    .font(.caption2)
                    .foregroundStyle(Design.Brand.forgeText)
            }

            if let hostApprovalMessage {
                Text(hostApprovalMessage)
                    .font(.caption2)
                    .foregroundStyle(Design.Brand.forgeText)
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
        .accessibilityIdentifier("settings.server.hostApprovalMode")
    }

    private var isHostApprovalPickerEnabled: Bool {
        if case .mode = hostApprovalMode { return true }
        return false
    }

    private func approvalSegment(_ mode: String) -> some View {
        let isCurrent: Bool = {
            if case .mode(let current) = hostApprovalMode { return current == mode }
            return false
        }()
        return Button {
            Task { await setHostApprovalMode(mode) }
        } label: {
            Text(mode.capitalized)
                .font(Design.Typography.caption)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.xs)
                .background(isCurrent ? Design.Brand.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
                .foregroundStyle(isCurrent ? Design.Colors.background : Design.Colors.secondaryForeground)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Approval mode \(mode)")
    }

    private func refreshHostApprovalMode() async {
        hostApprovalMode = .unknown
        hostApprovalMessage = nil
        guard let link = container.talariaPlatformLink else { return }
        let (state, message) = HostApprovalModeState.from(await link.approvalMode(setting: nil))
        hostApprovalMode = state
        hostApprovalMessage = message
    }

    private func setHostApprovalMode(_ mode: String) async {
        guard let link = container.talariaPlatformLink, !hostApprovalSetInFlight else { return }
        hostApprovalSetInFlight = true
        defer { hostApprovalSetInFlight = false }
        let (state, message) = HostApprovalModeState.from(await link.approvalMode(setting: mode))
        hostApprovalMode = state
        hostApprovalMessage = message
    }

    // MARK: Auto-connect (relocated from the retired Relay sub-page)

    private var autoConnectPanel: some View {
        HStack {
            Text("Auto-connect on launch")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            Toggle("", isOn: Binding(
                get: { settingsStore.settings.autoConnectOnLaunch },
                set: { settingsStore.settings.autoConnectOnLaunch = $0 }
            ))
            .labelsHidden()
            .tint(Design.Brand.accentText)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    // MARK: Reachability probes (real data only — M-12)

    private func probeAllProfiles() async {
        // Build fix (2026-07-16): tuple-returning children AND children that
        // capture the View struct both trip "pattern that the region-based
        // isolation checker does not understand" on the iOS 27 SDK. Resolve
        // each profile's key up front (cheap Keychain reads, on the View),
        // then fan out static probes whose closures capture only Sendable
        // values + a MainActor accumulator box — the proven
        // SessionsHermesClient pattern. Probes still overlap.
        var keyed: [(profile: BackendProfile, key: String?)] = []
        for profile in profiles {
            keyed.append((profile, await container.gatewayAPIKey(for: profile)))
        }
        let gathered = ProbeAccumulator()
        // …and the iOS 27 SDK's checker rejects even fully-Sendable captures
        // inside `withTaskGroup` children here (third pattern variant tried).
        // Unstructured Task handles bypass the task-group region machinery:
        // Task<Void, Never> needs only Sendable Void, closures capture only
        // Sendable values, probes still overlap, and we await every handle
        // before reading the box.
        let handles = keyed.map { entry in
            Task { @MainActor in
                gathered.results[entry.profile.id] = await Self.probe(
                    entry.profile, gatewayKey: entry.key
                )
            }
        }
        for handle in handles {
            await handle.value
        }
        for (id, result) in gathered.results {
            reachability[id] = result
        }
    }

    private static func probe(_ profile: BackendProfile, gatewayKey: String?) async -> ServerProfileReachability {
        var result = ServerProfileReachability()
        result.gateway = await probeGateway(profile, gatewayKey: gatewayKey)
        return result
    }

    /// GET {gateway}/v1/models with the profile's key: 2xx = online,
    /// 401/403 = answering but unkeyed, anything else = offline.
    private static func probeGateway(_ profile: BackendProfile, gatewayKey: String?) async -> ServerProbeResult {
        let base = profile.gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let url = URL(string: normalized(base) + "/v1/models") else { return .unknown }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if let key = gatewayKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .offline }
            return ServerProbeResult.classify(statusCode: http.statusCode)
        } catch {
            return .offline
        }
    }


    /// One probe request → HTTP status, nil when no HTTP answer arrived.
    private static func statusCode(for url: URL, bearer: String?) async -> Int? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if let bearer, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    private static func normalized(_ raw: String) -> String {
        var trimmed = raw
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}

/// Region-checker workaround box for the profile reachability probes (M-12).
/// Every child task in the probe group is MainActor-isolated, so writes never
/// race; the MainActor-isolated reference type (implicitly Sendable) is what
/// lets results cross the task-group boundary without moving non-Sendable
/// tuples — or the View struct itself — through it. Same pattern as
/// SessionsHermesClient.ProfileFetchAccumulator.
@MainActor
private final class ProbeAccumulator {
    var results: [UUID: ServerProfileReachability] = [:]
}

// MARK: - Profile editor sheet (add / edit)

/// The editable fields, extracted so validation is unit-testable (M-17).
struct ProfileEditorDraft: Equatable {
    var name: String = ""
    var gatewayBaseURL: String = ""
    var note: String = ""

    init() {}

    init(profile: BackendProfile) {
        name = profile.name
        gatewayBaseURL = profile.gatewayBaseURL
        note = profile.note ?? ""
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give the profile a name."
        }
        let gateway = gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if gateway.isEmpty {
            return "Enter the gateway URL (Sessions API, e.g. http://host:8642)."
        }
        if !gateway.hasPrefix("http://") && !gateway.hasPrefix("https://") {
            return "Gateway URL must be an absolute http(s) URL."
        }
        return nil
    }

    var isValid: Bool { validationMessage == nil }

    /// Applies the draft onto an existing profile (identity + credential
    /// scope preserved) or mints a new one.
    func apply(to existing: BackendProfile?) -> BackendProfile {
        var profile = existing ?? BackendProfile(name: "", gatewayBaseURL: "")
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.gatewayBaseURL = gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.note = trimmedNote.isEmpty ? nil : trimmedNote
        return profile
    }
}

private struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    let existing: BackendProfile?

    @State private var draft = ProfileEditorDraft()
    @State private var gatewayKeyDraft = ""
    @State private var storedGatewayKey = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                HUDScreenBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                        field("Name", text: $draft.name, placeholder: "Mac Mini")
                        field("Gateway URL", text: $draft.gatewayBaseURL, placeholder: "http://100.79.222.100:8642", keyboard: .URL)
                        field("Note", text: $draft.note, placeholder: "Apple ecosystem / Xcode / iMessage")
                        apiKeySection

                        if let message = draft.validationMessage {
                            Text(message)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Brand.forgeText)
                        }

                        GlowButton(title: existing == nil ? "Add Profile" : "Save Changes") {
                            Task { await save() }
                        }
                        .disabled(!draft.isValid || isSaving)
                        .opacity(draft.isValid && !isSaving ? 1 : 0.5)
                    }
                    .padding(Design.Spacing.md)
                }
            }
            .navigationTitle(existing == nil ? "Add Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if let existing {
                draft = ProfileEditorDraft(profile: existing)
                let stored = await container.gatewayAPIKey(for: existing) ?? ""
                storedGatewayKey = stored
                gatewayKeyDraft = stored
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("API Key", size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)
            SecureField("Bearer key from ~/.hermes/.env", text: $gatewayKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Design.Typography.callout.monospaced())
                .foregroundStyle(Design.Colors.foreground)
                .padding(Design.Spacing.md)
                .background(Design.Colors.background.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                        .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                }
            Text("This host's API_SERVER_KEY — each profile keeps its own key in the Keychain.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(label, size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .font(Design.Typography.callout.monospaced())
                .foregroundStyle(Design.Colors.foreground)
                .padding(Design.Spacing.md)
                .background(Design.Colors.background.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                        .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                }
        }
    }

    private func save() async {
        guard draft.isValid, let profilesStore = container.profilesStore else { return }
        isSaving = true
        let profile = draft.apply(to: existing)
        profilesStore.upsert(profile)
        if gatewayKeyDraft != storedGatewayKey {
            await container.saveGatewayAPIKey(gatewayKeyDraft, for: profile)
        }
        isSaving = false
        dismiss()
    }
}
