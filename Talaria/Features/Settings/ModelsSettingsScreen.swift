import SwiftUI

// MARK: - Models settings screen (Settings → MODELS)
//
// Wires the live Talaria models shim (OJAMD tailnet) into the HUD. Lists the
// authenticated providers/models, marks the active model, refreshes the shim's
// per-provider cache on demand, and — on tap — DUAL-WRITES the selection:
//   1. current session  → ChatStore.selectModel (gateway `/model <id>`)
//   2. persistent default → shim POST /models/default (new-session scope)
// The expensive-model guard surfaces as a confirm dialog.

// MARK: View model

@MainActor
@Observable
final class ModelsSettingsModel {
    private let shim: ModelsShimClient
    private let chat: ChatStore

    var options: ShimModelOptions?
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var statusMessage: String?
    /// The model id currently mid dual-write (drives per-row spinner + disable).
    var applyingModelID: String?
    /// Pending expensive-model confirmation, if the shim asked for one.
    var pendingConfirm: PendingConfirm?
    /// Last apply() target, captured so the transition overlay's Retry can re-run it.
    private(set) var lastAppliedSlug: String?
    private(set) var lastAppliedModel: String?

    /// Optimistic active pointer set right after a successful set-default. The shim
    /// caches its GET payload for an hour and does NOT bust the cache on set, so a
    /// `refresh=0` re-GET still reports the OLD current; this override keeps the
    /// checkmark truthful until a manual "Refresh models" reconciles against ground.
    private var activeOverride: ActiveOverride?

    struct ActiveOverride: Equatable { let slug: String; let model: String }

    struct PendingConfirm: Identifiable {
        let id = UUID()
        let providerSlug: String
        let modelID: String
        let message: String
    }

    init(shim: ModelsShimClient, chat: ChatStore) {
        self.shim = shim
        self.chat = chat
    }

    // MARK: Loading

    /// Initial / re-entrant load. Uses the cached compile (no `refresh`).
    func load() async {
        if options == nil { isLoading = true }
        errorMessage = nil
        do {
            options = try await shim.fetchModels(refresh: false)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// "Refresh models" — busts the shim's per-provider disk cache (re-hits every
    /// provider's live `/v1/models`). Genuinely slow (~20–60s); always async with a
    /// spinner and never blocks the rest of the UI.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        statusMessage = nil
        do {
            options = try await shim.fetchModels(refresh: true)
            // Fresh payload is ground truth — drop any optimistic override.
            activeOverride = nil
            statusMessage = "Refreshed \(compiledAgoText ?? "just now")"
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isRefreshing = false
    }

    // MARK: Dual write

    /// Tap handler. Persists the default via the shim first (so the expensive guard
    /// can interrupt before we touch the live session), then pins the current
    /// session via `/model`, and moves the checkmark optimistically (the shim caches
    /// its GET payload, so we don't trust an immediate re-GET — "Refresh" reconciles).
    func apply(providerSlug: String, modelID: String, confirmExpensive: Bool = false) async {
        guard applyingModelID == nil else { return }
        applyingModelID = modelID
        lastAppliedSlug = providerSlug
        lastAppliedModel = modelID
        errorMessage = nil
        statusMessage = nil
        defer { applyingModelID = nil }

        do {
            let outcome = try await shim.setDefault(
                provider: providerSlug, model: modelID, confirmExpensive: confirmExpensive
            )
            switch outcome {
            case .confirmRequired(let message):
                pendingConfirm = PendingConfirm(providerSlug: providerSlug, modelID: modelID, message: message)
                return
            case .success:
                // The shim caches its GET payload for an hour and does NOT bust it on
                // set, so a `refresh=0` re-GET would still show the OLD current. Move
                // the active pointer optimistically; "Refresh models" reconciles later.
                activeOverride = ActiveOverride(slug: providerSlug, model: modelID)
                statusMessage = "Default → \(modelID) · pinning session…"
                // Pin the live session (gateway `/model`) in the BACKGROUND. It is
                // non-fatal and can be slow (~37s+) or hang when the gateway is offline,
                // so it must not hold `applyingModelID` open — that would freeze the
                // transition overlay and disable every model row (#9).
                pinSessionInBackground(modelID: modelID)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Pins the live session to the new model via the gateway `/model` command, OFF the
    /// blocking apply() path. Non-fatal and possibly slow/hanging, so it runs detached and
    /// only refreshes the status line if this model is still the chosen default. (#9)
    private func pinSessionInBackground(modelID: String) {
        Task { @MainActor in
            let sessionOK = await chat.selectModel(modelID)
            guard activeOverride?.model == modelID else { return }
            statusMessage = sessionOK
                ? "Default → \(modelID) · pinned this session"
                : "Default → \(modelID) · session pin unavailable (gateway offline?)"
        }
    }

    func confirmPending() async {
        guard let pending = pendingConfirm else { return }
        pendingConfirm = nil
        await apply(providerSlug: pending.providerSlug, modelID: pending.modelID, confirmExpensive: true)
    }

    func cancelPending() {
        pendingConfirm = nil
    }

    /// Re-run the last apply() target (driven by the transition overlay's Retry).
    func retryLast() async {
        guard let slug = lastAppliedSlug, let id = lastAppliedModel else { return }
        await apply(providerSlug: slug, modelID: id)
    }

    // MARK: Derived

    /// Active model = the row whose id == top-level `model`, inside the provider
    /// with is_current == true. (Provider slug != top-level `provider` for kimi.)
    func isActive(providerSlug: String, modelID: String) -> Bool {
        if let activeOverride {
            return activeOverride.slug == providerSlug && activeOverride.model == modelID
        }
        guard let options else { return false }
        guard let row = options.providers.first(where: { $0.slug == providerSlug }) else { return false }
        return row.current && modelID == options.model
    }

    var authenticatedProviders: [ShimProviderRow] {
        let auth = (options?.providers ?? []).filter { $0.isAuthenticated }
        // Current provider first, then by display name.
        return auth.sorted { lhs, rhs in
            if lhs.current != rhs.current { return lhs.current }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var needsSetupCount: Int {
        (options?.providers ?? []).filter { !$0.isAuthenticated }.count
    }

    var compiledAgoText: String? { Self.compiledAgo(from: options?.compiledAt) }

    // MARK: ISO8601 freshness (tolerant: handles `Z` and `+00:00`, 0–6 frac digits)

    static func compiledAgo(from iso: String?) -> String? {
        guard let iso, let date = parseISO(iso) else { return nil }
        let secs = Date().timeIntervalSince(date)
        if secs < 1 { return "just now" }
        if secs < 60 { return "\(Int(secs))s ago" }
        if secs < 3600 { return "\(Int(secs / 60)) min ago" }
        if secs < 86_400 { return "\(Int(secs / 3600))h ago" }
        return "\(Int(secs / 86_400))d ago"
    }

    static func parseISO(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // Strip a fractional-seconds group the formatters choke on, then retry.
        if let r = s.range(of: #"\.[0-9]+"#, options: .regularExpression) {
            var stripped = s
            stripped.removeSubrange(r)
            if let d = plain.date(from: stripped) { return d }
        }
        return nil
    }
}

// MARK: - Screen

struct ModelsSettingsScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var model: ModelsSettingsModel?
    @State private var tokenDraft = ""
    @State private var tokenSaving = false
    @State private var tokenJustSaved = false

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    header
                    // #27: brain picker — only once any Hermes host exists
                    // (a never-paired device has one brain, nothing to pick).
                    if let brainRouter = container.chatBackendRouter, brainRouter.showsBrainPicker {
                        brainSection(brainRouter)
                    }
                    shimConfigSection
                    if let model {
                        content(model)
                    } else {
                        ProgressView()
                            .tint(Design.Brand.accent)
                            .padding(.top, Design.Spacing.xl)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }

            // Transition overlay is pinned to the viewport (not the scrolling content) so
            // it stays put during a model switch. (#9)
            if let model {
                ModelTransitionOverlay(model: model)
            }
        }
        .navigationTitle("Models")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                model = ModelsSettingsModel(shim: container.modelsShimClient, chat: container.chatStore)
            }
            tokenDraft = container.modelsShimToken
            await model?.load()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            GlassCircleButton(icon: "chevron.left", accessibilityLabel: "Back") { dismiss() }
            Spacer()
            Text("MODELS")
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)
            Spacer()
            // Balance the leading back button so the title stays centered.
            Color.clear.frame(width: Design.Size.glassCircleButton, height: Design.Size.glassCircleButton)
        }
        .padding(.top, Design.Spacing.xs)
    }

    // MARK: Chat brain (#27)

    /// Per-conversation brain pin: Automatic (routing rules decide) / Hermes /
    /// On-Device — Private Cloud β joins with #30. Applies to the CURRENT
    /// conversation (or the next one to start when none exists yet).
    private func brainSection(_ brainRouter: ChatBackendRouter) -> some View {
        let conversationID = container.chatStore.conversation?.id
        let current = brainRouter.preferredBrain(forConversation: conversationID)
        return SettingsSectionView(title: "Chat Brain") {
            VStack(spacing: 0) {
                brainRow(
                    label: "Automatic",
                    glyph: "wand.and.stars",
                    detail: "Hermes when reachable, on-device otherwise",
                    isActive: current == nil
                ) {
                    brainRouter.setPreferredBrain(nil, forConversation: conversationID)
                }
                ForEach(brainRouter.selectableBrains, id: \.rawValue) { brain in
                    brainRow(
                        label: brain.displayLabel,
                        glyph: brain.glyph,
                        detail: nil,
                        isActive: current == brain
                    ) {
                        brainRouter.setPreferredBrain(brain, forConversation: conversationID)
                    }
                }
                // #30: PCC quota as PERSISTENT status, not an alert — below /
                // nearing / reached, with the system's upgrade path when the
                // OS offers one.
                if let status = container.localChatBackend?.privateCloudStatus() {
                    privateCloudQuotaRow(status)
                }
                MonoLabel(
                    "ROUTING NEXT MESSAGE: \(brainRouter.activeBrain.monoLabel)",
                    size: 8,
                    tracking: Design.Tracking.mono,
                    color: Design.Colors.dimForeground
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Design.Spacing.xs)
            }
        }
    }

    private func privateCloudQuotaRow(_ status: LocalChatBackend.PrivateCloudStatus) -> some View {
        let label: String
        let color: Color
        switch status.quota {
        case .belowLimit(approaching: false):
            label = "PRIVATE CLOUD β · BELOW DAILY LIMIT"
            color = Design.Colors.mutedForeground
        case .belowLimit(approaching: true):
            label = "PRIVATE CLOUD β · NEARING DAILY LIMIT"
            color = Design.Brand.forge
        case .limitReached(let resetDate):
            let resets = resetDate.map { " · RESETS \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            label = "PRIVATE CLOUD β · DAILY LIMIT REACHED\(resets)"
            color = Design.Colors.danger
        }
        return HStack(spacing: Design.Spacing.sm) {
            MonoLabel(label, size: 8, tracking: Design.Tracking.mono, color: color)
            Spacer()
            if status.hasLimitIncreaseSuggestion {
                Button("Show options") {
                    container.localChatBackend?.showPrivateCloudLimitIncreaseOptions()
                }
                .font(Design.Typography.mono(10, weight: .medium))
                .foregroundStyle(Design.Brand.accent)
            }
        }
        .padding(.top, Design.Spacing.xs)
    }

    private func brainRow(
        label: String,
        glyph: String,
        detail: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: glyph)
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(isActive ? Design.Brand.accent : Design.Colors.mutedForeground)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Design.Typography.body(14, weight: isActive ? .bold : .regular))
                        .foregroundStyle(isActive ? Design.Colors.foregroundBright : Design.Colors.foreground)
                    if let detail {
                        Text(detail)
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    }
                }
                Spacer(minLength: Design.Spacing.sm)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
            .padding(.vertical, Design.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Shim config (URL + token)

    private var shimConfigSection: some View {
        SettingsSectionView(title: "Shim Uplink") {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    MonoLabel("Shim URL", size: 9, weight: .medium, color: Design.Colors.mutedForeground)
                    TextField("http://ojamd:8765", text: shimURLBinding)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .font(Design.Typography.callout.monospaced())
                        .foregroundStyle(Design.Colors.foreground)
                        .padding(Design.Spacing.md)
                        .modifier(ShimFieldBackground())
                    Text("Talaria models-shim endpoint on OJAMD (tailnet).")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }

                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    MonoLabel("Bearer Token", size: 9, weight: .medium, color: Design.Colors.mutedForeground)
                    SecureField("Token from ~/.hermes/talaria_shim_token", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Design.Typography.callout.monospaced())
                        .foregroundStyle(Design.Colors.foreground)
                        .padding(Design.Spacing.md)
                        .modifier(ShimFieldBackground())
                    HStack {
                        Text(container.modelsShimToken.isEmpty ? "No token stored." : "Token stored in Keychain.")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                        Spacer()
                        Button {
                            Task { await saveToken() }
                        } label: {
                            HStack(spacing: Design.Spacing.xs) {
                                if tokenSaving { ProgressView().controlSize(.mini) }
                                Text((tokenJustSaved ? "Saved" : "Save").uppercased())
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
                        .disabled(tokenDraft == container.modelsShimToken)
                    }
                }
            }
        }
    }

    // MARK: Content (freshness + refresh + providers)

    @ViewBuilder
    private func content(_ model: ModelsSettingsModel) -> some View {
        VStack(spacing: Design.Spacing.lg) {
            freshnessBar(model)

            if model.isLoading {
                ProgressView().tint(Design.Brand.accent).padding(.top, Design.Spacing.lg)
            } else if let error = model.errorMessage, model.options == nil {
                errorPanel(error, model)
            } else {
                if let status = model.statusMessage {
                    MonoLabel(status, size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: Design.Brand.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.errorMessage {
                    MonoLabel(error, size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: Design.Colors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.authenticatedProviders) { provider in
                    providerSection(provider, model: model)
                }
                if model.needsSetupCount > 0 {
                    MonoLabel("\(model.needsSetupCount) MORE PROVIDERS NEED SETUP", size: 8,
                              tracking: Design.Tracking.mono, color: Design.Colors.dimForeground)
                        .padding(.top, Design.Spacing.xs)
                }
            }
        }
    }

    private func freshnessBar(_ model: ModelsSettingsModel) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel("COMPILED", size: 8, tracking: Design.Tracking.monoWide,
                          color: Design.Colors.mutedForeground)
                Text(model.compiledAgoText ?? "—")
                    .font(Design.Typography.mono(12, weight: .medium))
                    .foregroundStyle(Design.Colors.coolForeground)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                HStack(spacing: Design.Spacing.xs) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    }
                    Text(model.isRefreshing ? "Refreshing…" : "Refresh")
                        .font(Design.Typography.body(13, weight: .medium))
                }
                .foregroundStyle(Design.Brand.accentBright)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.xs)
                .background(Design.Colors.accentTint(0.10), in: Capsule())
                .overlay { Capsule().strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Colors.hairline,
                  fill: Design.Colors.surface)
        .overlay(alignment: .bottomLeading) {
            if model.isRefreshing {
                Text("Re-checking every provider — 20–60s.")
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .padding(.leading, Design.Spacing.md)
                    .offset(y: 18)
            }
        }
    }

    private func providerSection(_ provider: ShimProviderRow, model: ModelsSettingsModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: provider.current ? Design.Brand.accent : Design.Colors.dimForeground, diameter: 6)
                MonoLabel(provider.displayName, size: 10, weight: .medium, tracking: Design.Tracking.monoWide,
                          color: provider.current ? Design.Brand.accentBright : Design.Colors.secondaryForeground)
                Spacer()
                MonoLabel("\(provider.modelIDs.count)", size: 9, color: Design.Colors.dimForeground)
            }
            VStack(spacing: 0) {
                ForEach(provider.modelIDs, id: \.self) { id in
                    modelRow(provider: provider, id: id, model: model)
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity)
            .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Colors.hairline,
                      fill: Design.Colors.surface)
        }
    }

    private func modelRow(provider: ShimProviderRow, id: String, model: ModelsSettingsModel) -> some View {
        let active = model.isActive(providerSlug: provider.slug, modelID: id)
        let applying = model.applyingModelID == id
        return Button {
            Task { await model.apply(providerSlug: provider.slug, modelID: id) }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Text(id)
                    .font(Design.Typography.body(14, weight: active ? .bold : .regular))
                    .foregroundStyle(active ? Design.Colors.foregroundBright : Design.Colors.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Design.Spacing.sm)
                if applying {
                    ProgressView().controlSize(.mini)
                } else if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
            .padding(.vertical, Design.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.applyingModelID != nil)
    }

    private func errorPanel(_ message: String, _ model: ModelsSettingsModel) -> some View {
        VStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Design.Brand.forge)
            Text(message)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)
            GhostButton(title: "Retry", systemImage: "arrow.clockwise") {
                Task { await model.load() }
            }
            .frame(maxWidth: 160)
        }
        .padding(Design.Spacing.lg)
        .frame(maxWidth: .infinity)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Colors.hairline,
                  fill: Design.Colors.surface)
    }

    // MARK: Bindings / actions

    private var shimURLBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.modelsShimBaseURL },
            set: { settingsStore.settings.modelsShimBaseURL = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func saveToken() async {
        tokenSaving = true
        await container.saveModelsShimToken(tokenDraft)
        tokenSaving = false
        tokenJustSaved = true
        // Re-load now that auth may be available.
        await model?.load()
        try? await Task.sleep(for: .seconds(1.5))
        tokenJustSaved = false
    }
}

// MARK: - Field background (matches the Hermes API fields)

private struct ShimFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Design.Colors.chipSurface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
            }
    }
}
