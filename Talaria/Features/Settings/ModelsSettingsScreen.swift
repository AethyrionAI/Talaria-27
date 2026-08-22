import SwiftUI

// MARK: - Models settings screen (Settings → MODELS)
//
// #223 Lane 5: gateway-native picker. Lists providers/models straight from
// `GET /api/model/options` (auth state, setup warnings, pricing), and a tap
// persists ONE pick per backend profile — applied to every subsequent turn as
// a per-turn `require_model_lock` (see GatewayModelCatalog.swift). apply() is
// instant and touches no network; the HOST DEFAULT row clears the pick so the
// host's own default rules again. The shim, its dual-write, and the
// expensive-model confirm guard retired with this rewrite.

// MARK: View model

@MainActor
@Observable
final class ModelsSettingsModel {
    typealias CatalogFetch = @MainActor () async throws -> GatewayModelCatalog

    private let fetchCatalog: CatalogFetch
    private let readSelection: () -> ModelSelection?
    private let writeSelection: (ModelSelection?) -> Void

    var catalog: GatewayModelCatalog?
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var statusMessage: String?
    /// Kept for the transition overlay's phase machine; apply() is synchronous
    /// now, so this is set and cleared within one call.
    var applyingModelID: String?
    /// Last apply() target, captured so the transition overlay's Retry can re-run it.
    private(set) var lastAppliedSlug: String?
    private(set) var lastAppliedModel: String?

    init(
        fetchCatalog: @escaping CatalogFetch,
        readSelection: @escaping () -> ModelSelection?,
        writeSelection: @escaping (ModelSelection?) -> Void
    ) {
        self.fetchCatalog = fetchCatalog
        self.readSelection = readSelection
        self.writeSelection = writeSelection
    }

    /// The active profile's persisted pick (nil = following the host default).
    var selection: ModelSelection? { readSelection() }

    // MARK: Loading

    func load() async {
        if catalog == nil { isLoading = true }
        errorMessage = nil
        do {
            catalog = try await fetchCatalog()
            if let catalog { ModelPricingCatalog.shared.ingest(catalog) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// "Refresh models" — a plain re-fetch of /api/model/options (the gateway
    /// serves its live provider inventory; no cache knob to bust).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        statusMessage = nil
        do {
            catalog = try await fetchCatalog()
            if let catalog { ModelPricingCatalog.shared.ingest(catalog) }
            statusMessage = "Refreshed just now"
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isRefreshing = false
    }

    // MARK: Apply (#223 Lane 5 — persist the pick; no network)

    /// Tap handler. Persists the pick on the active profile — every subsequent
    /// turn carries it as `provider` + `model` + `require_model_lock: true`.
    /// Instant by design: no shim POST, no session pin, nothing to await.
    func apply(providerSlug: String, modelID: String) {
        guard applyingModelID == nil else { return }
        applyingModelID = modelID
        lastAppliedSlug = providerSlug
        lastAppliedModel = modelID
        errorMessage = nil
        writeSelection(ModelSelection(provider: providerSlug, modelID: modelID))
        statusMessage = "Locked → \(modelID) · applies to every turn"
        applyingModelID = nil
    }

    /// HOST DEFAULT row: clear the pick — turns carry no model fields and the
    /// host's own default rules again.
    func applyHostDefault() {
        writeSelection(nil)
        statusMessage = "Following the host default"
    }

    /// Re-run the last apply() target (driven by the transition overlay's Retry).
    func retryLast() async {
        guard let slug = lastAppliedSlug, let id = lastAppliedModel else { return }
        apply(providerSlug: slug, modelID: id)
    }

    // MARK: Derived

    /// Host's current default pair from the catalog top level. On the v0.20.0
    /// payload the top-level `provider` IS a row slug (unlike the old shim
    /// payload, where they could differ).
    var hostDefaultProvider: String? { catalog?.provider }
    var hostDefaultModel: String? { catalog?.model }

    var hostDefaultIsActive: Bool { selection == nil }

    /// Checkmark truth: an explicit pick wins; with no pick, the host's
    /// current pair reads as active.
    func isActive(providerSlug: String, modelID: String) -> Bool {
        if let selection {
            return selection.provider == providerSlug && selection.modelID == modelID
        }
        return providerSlug == catalog?.provider && modelID == catalog?.model
    }

    var authenticatedProviders: [GatewayProviderEntry] {
        let auth = (catalog?.providers ?? []).filter(\.authenticated)
        let currentSlug = catalog?.provider
        return auth.sorted { lhs, rhs in
            let lhsCurrent = lhs.slug == currentSlug
            let rhsCurrent = rhs.slug == currentSlug
            if lhsCurrent != rhsCurrent { return lhsCurrent }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var needsSetupCount: Int {
        (catalog?.providers ?? []).filter { !$0.authenticated }.count
    }
}

// MARK: - Screen

struct ModelsSettingsScreen: View {
    // #252: deck pages supply the background and top bar; the screen keeps
    // owning its content, tasks, and sheets in both presentations.
    var embedded: Bool = false
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var model: ModelsSettingsModel?

    var body: some View {
        ZStack {
            if !embedded {
                HUDScreenBackground()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if !embedded {
                        header
                    }
                    if embedded {
                        SubsystemHero(
                            motif: .barChart,
                            title: SettingsSubsystem.models.title,
                            status: SettingsCardValues.models(
                                activeModelName: container.chatStore.activeModelName,
                                brainLabel: container.chatBackendRouter?.activeBrain.monoLabel),
                            statusColor: container.chatStore.activeModelName?.isEmpty == false
                                ? Design.Brand.accent : Design.Colors.mutedForeground,
                            chip: SettingsSubsystem.models.chip,
                            accented: container.chatStore.activeModelName?.isEmpty == false
                        )
                    }
                    // #27: brain picker — only once any Hermes host exists
                    // (a never-paired device has one brain, nothing to pick).
                    if let brainRouter = container.chatBackendRouter, brainRouter.showsBrainPicker {
                        brainSection(brainRouter)
                    }
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
                // #223 Lane 5: catalog from the gateway, pick persisted on the
                // active profile via the container (which also feeds the live
                // client's per-turn lock).
                model = ModelsSettingsModel(
                    fetchCatalog: { [weak container] in
                        guard let client = container?.sessionsChatClient else {
                            throw SessionsHermesClient.SessionsClientError.notConfigured("No gateway configured \u{2014} pair a Hermes host first.")
                        }
                        return try await client.fetchModelCatalog()
                    },
                    readSelection: { [weak container] in container?.activeModelSelection },
                    writeSelection: { [weak container] selection in
                        container?.applyModelSelection(selection)
                    }
                )
            }
            await model?.load()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            GlassCircleButton(icon: "chevron.left", accessibilityLabel: "Back") { dismiss() }
                // J-4: Esc closes the Models sheet (hardware keyboards only).
                .keyboardShortcut(.cancelAction)
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

    /// Brain pick: Automatic (routing rules decide) / Hermes / On-Device —
    /// Private Cloud β joins with #30. #192 (sticky mode): an explicit pick
    /// sets the app-wide default new chats inherit, plus this conversation's
    /// override; the checkmark reflects what will actually route.
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
            color = Design.Brand.forgeText
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

    // MARK: Content (freshness + refresh + providers)

    @ViewBuilder
    private func content(_ model: ModelsSettingsModel) -> some View {
        VStack(spacing: Design.Spacing.lg) {
            freshnessBar(model)

            if model.isLoading {
                ProgressView().tint(Design.Brand.accent).padding(.top, Design.Spacing.lg)
            } else if let error = model.errorMessage, model.catalog == nil {
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
                hostDefaultRow(model)
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
                MonoLabel("MODEL CATALOG", size: 8, tracking: Design.Tracking.monoWide,
                          color: Design.Colors.mutedForeground)
                Text("gateway \u{00b7} /api/model/options")
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
    }

    /// #223 Lane 5: the pick-clearing row. Selected when no pick exists —
    /// turns carry no model fields and the host's own default rules.
    private func hostDefaultRow(_ model: ModelsSettingsModel) -> some View {
        Button {
            model.applyHostDefault()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "server.rack")
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(model.hostDefaultIsActive ? Design.Brand.accent : Design.Colors.mutedForeground)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Host default")
                        .font(Design.Typography.body(14, weight: model.hostDefaultIsActive ? .bold : .regular))
                        .foregroundStyle(model.hostDefaultIsActive ? Design.Colors.foregroundBright : Design.Colors.foreground)
                    MonoLabel(
                        hostDefaultDetail(model),
                        size: 9,
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.secondaryForeground
                    )
                }
                Spacer(minLength: Design.Spacing.sm)
                if model.hostDefaultIsActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
            .padding(Design.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Colors.hairline,
                  fill: Design.Colors.surface)
    }

    private func hostDefaultDetail(_ model: ModelsSettingsModel) -> String {
        guard let provider = model.hostDefaultProvider, let modelID = model.hostDefaultModel else {
            return "\u{2014}"
        }
        return "\(provider) \u{00b7} \(modelID)".uppercased()
    }

    private func providerSection(_ provider: GatewayProviderEntry, model: ModelsSettingsModel) -> some View {
        let isCurrent = provider.slug == model.hostDefaultProvider
        return VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: isCurrent ? Design.Brand.accent : Design.Colors.dimForeground, diameter: 6)
                MonoLabel(provider.name, size: 10, weight: .medium, tracking: Design.Tracking.monoWide,
                          color: isCurrent ? Design.Brand.accentBright : Design.Colors.secondaryForeground)
                Spacer()
                MonoLabel("\(provider.models.count)", size: 9, color: Design.Colors.dimForeground)
            }
            VStack(spacing: 0) {
                ForEach(provider.models, id: \.self) { id in
                    modelRow(provider: provider, id: id, model: model)
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity)
            .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Colors.hairline,
                      fill: Design.Colors.surface)
        }
    }

    private func modelRow(provider: GatewayProviderEntry, id: String, model: ModelsSettingsModel) -> some View {
        let active = model.isActive(providerSlug: provider.slug, modelID: id)
        let applying = model.applyingModelID == id
        return Button {
            model.apply(providerSlug: provider.slug, modelID: id)
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

}
