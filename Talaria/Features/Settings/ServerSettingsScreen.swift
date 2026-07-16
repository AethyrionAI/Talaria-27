import SwiftUI

// MARK: - Server settings screen (Settings → SERVER, Lane M / OPEN_ITEMS #114)
//
// The backend-profile switcher: one card per named backend (OJAMD, Mac Mini),
// showing active state, live reachability (gateway answer + shim /healthz —
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
    var shim: ServerProbeResult = .unknown
}

struct ServerSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var reachability: [UUID: ServerProfileReachability] = [:]
    @State private var pendingActivation: BackendProfile?
    @State private var editorTarget: ProfileEditorTarget?
    @State private var pendingForget: BackendProfile?
    @State private var deleteErrorMessage: String?

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

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Server", subtitle: "Backend Profiles") { dismiss() }
                    profileCards
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
        .confirmationDialog(
            "Switch backend?",
            isPresented: Binding(
                get: { pendingActivation != nil },
                set: { if !$0 { pendingActivation = nil } }
            ),
            titleVisibility: .visible,
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
        .confirmationDialog(
            "Forget this pairing?",
            isPresented: Binding(
                get: { pendingForget != nil },
                set: { if !$0 { pendingForget = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingForget
        ) { profile in
            Button("Forget \(profile.name) Pairing", role: .destructive) {
                pendingForget = nil
                Task {
                    await pairingStore.forgetPairing(profileID: profile.id)
                    await probeAllProfiles()
                }
            }
            Button("Cancel", role: .cancel) { pendingForget = nil }
        } message: { profile in
            Text("Disconnects \(profile.name)'s relay pairing only. Other profiles are untouched; you'll need to pair again to resume its sensor path.")
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .add:
                ProfileEditorSheet(existing: nil)
            case .edit(let profile):
                ProfileEditorSheet(existing: profile)
            }
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
        let isSensorDestination = container.profilesStore?.sensorDestinationProfileID == profile.id
        let isPaired = container.profileRelaySessions?.isPaired(profileID: profile.id) ?? false
        let probes = reachability[profile.id] ?? ServerProfileReachability()

        return Button {
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
                                    .foregroundStyle(Design.Brand.accent)
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
                            tag("ACTIVE", color: Design.Brand.accent)
                        }
                        if isSensorDestination {
                            tag("SENSORS", color: Design.Colors.secondaryForeground)
                        }
                    }
                }

                HStack(spacing: Design.Spacing.md) {
                    statusRow("GATEWAY", result: probes.gateway)
                    statusRow("SHIM", result: profile.shimBaseURL == nil ? .unknown : probes.shim)
                    Spacer(minLength: 0)
                    MonoLabel(isPaired ? "PAIRED" : "NOT PAIRED", size: 9, weight: .medium,
                              tracking: Design.Tracking.mono,
                              color: isPaired ? Design.Brand.accent : Design.Colors.mutedForeground)
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
        .accessibilityLabel("\(profile.name)\(isActive ? ", active" : ""), \(isPaired ? "paired" : "not paired")")
        .contextMenu {
            Button {
                editorTarget = .edit(profile)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                startPairing(profile)
            } label: {
                Label(isPaired ? "Re-Pair" : "Pair", systemImage: "link")
            }
            if isPaired {
                Button(role: .destructive) {
                    pendingForget = profile
                } label: {
                    Label("Forget Pairing", systemImage: "link.badge.plus")
                }
            }
            if !isSensorDestination {
                Button {
                    container.profilesStore?.setSensorDestination(profile.id)
                } label: {
                    Label("Route Sensors Here", systemImage: "sensor")
                }
            }
            if !isActive && !isSensorDestination {
                Button(role: .destructive) {
                    deleteProfile(profile)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
        case .online: Design.Brand.accent
        case .unauthorized: Design.Brand.forge
        case .offline: Design.Colors.danger
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
            editorTarget = .add
        }
    }

    private func startPairing(_ profile: BackendProfile) {
        pairingStore.pairingTargetProfileID = profile.id
        router.dismissSheet()
        router.navigate(to: .connectHost)
    }

    private func deleteProfile(_ profile: BackendProfile) {
        guard let profilesStore = container.profilesStore else { return }
        do {
            try profilesStore.deleteProfile(id: profile.id)
            deleteErrorMessage = nil
            reachability[profile.id] = nil
        } catch BackendProfilesStore.DeleteError.profileIsActive {
            deleteErrorMessage = "Switch to another profile before deleting the active one."
        } catch BackendProfilesStore.DeleteError.profileIsSensorDestination {
            deleteErrorMessage = "Route sensors to another profile before deleting this one."
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private func errorNotice(_ message: String) -> some View {
        Text(message)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Brand.forge)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .tint(Design.Brand.accent)
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
                gathered.results[entry.profile.id] = await Self.probe(entry.profile, gatewayKey: entry.key)
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
        result.shim = await probeShim(profile)
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

    /// GET {shim}/healthz — the shim's unauthenticated health route.
    private static func probeShim(_ profile: BackendProfile) async -> ServerProbeResult {
        guard let raw = profile.shimBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: normalized(raw) + "/healthz") else { return .unknown }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .offline }
            return ServerProbeResult.classify(statusCode: http.statusCode)
        } catch {
            return .offline
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
    var relayBaseURL: String = ""
    var shimBaseURL: String = ""
    var note: String = ""

    init() {}

    init(profile: BackendProfile) {
        name = profile.name
        gatewayBaseURL = profile.gatewayBaseURL
        relayBaseURL = profile.relayBaseURL
        shimBaseURL = profile.shimBaseURL ?? ""
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
        let relay = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !relay.isEmpty, RelayConfiguration.normalizeBaseURL(relay) == nil {
            return "Relay URL must be an absolute http(s) URL ending with /v1."
        }
        let shim = shimBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shim.isEmpty, !shim.hasPrefix("http://") && !shim.hasPrefix("https://") {
            return "Shim URL must be an absolute http(s) URL."
        }
        return nil
    }

    var isValid: Bool { validationMessage == nil }

    /// Applies the draft onto an existing profile (identity + credential
    /// scope preserved) or mints a new one.
    func apply(to existing: BackendProfile?) -> BackendProfile {
        var profile = existing ?? BackendProfile(name: "", gatewayBaseURL: "", relayBaseURL: "")
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.gatewayBaseURL = gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let relay = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.relayBaseURL = RelayConfiguration.normalizeBaseURL(relay) ?? relay
        let shim = shimBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.shimBaseURL = shim.isEmpty ? nil : shim
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
                        field("Relay URL", text: $draft.relayBaseURL, placeholder: "http://100.79.222.100:8000/v1", keyboard: .URL)
                        field("Models Shim URL", text: $draft.shimBaseURL, placeholder: "http://100.79.222.100:8765", keyboard: .URL)
                        field("Note", text: $draft.note, placeholder: "Apple ecosystem / Xcode / iMessage")
                        apiKeySection

                        if let message = draft.validationMessage {
                            Text(message)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Brand.forge)
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
