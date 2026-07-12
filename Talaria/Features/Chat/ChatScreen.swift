import SwiftUI

struct ChatScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(ChatStore.self) private var chatStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(InboxStore.self) private var inboxStore
    @Environment(TabRouter.self) private var router

    @State private var messageText = ""
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var showClearConfirmation = false
    /// #16: a parsed /alarm staged behind the in-app confirm gate — nothing
    /// schedules until the user confirms (decided policy for alarm writes).
    @State private var pendingAlarmConfirm: AlarmService.AlarmRequest?
    @State private var showStatusCard = false
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isComposerFocused: Bool

    @State private var showAttachmentPicker = false

    // `/save` success: the written transcript file, offered onward via the
    // share sheet (Save to Files / AirDrop / etc.).
    @State private var exportShareURL: URL?
    @State private var showExportShareSheet = false

    // HUD shells (presentation only — see SessionsDrawer / ModelSelector).
    @State private var sessionsOpen = false
    @State private var sessionsModel = SessionsDrawerModel()
    @State private var modelModel = ModelSelectorModel()

    private let thinkingIndicatorID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    // #46: stable scroll anchor for the status card (it renders after the
    // last message, so scrolling to the last message can leave it off-screen).
    private let statusCardID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // `body` is split across several `some View` properties so each is a small,
    // independent expression. Applied as one chain, the ~15 modifiers overrun the
    // Swift type-checker's budget ("unable to type-check this expression in
    // reasonable time"), more readily on slower machines (e.g. CI). The split is
    // behavior-preserving: the grouped modifiers are order-independent.
    var body: some View {
        observingContent
            .confirmationDialog(
                "Clear Conversation",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    Task { await performClear() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will archive the current conversation and start a new session. This cannot be undone.")
            }
            .confirmationDialog(
                "Schedule on this iPhone?",
                isPresented: Binding(
                    get: { pendingAlarmConfirm != nil },
                    set: { if !$0 { pendingAlarmConfirm = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingAlarmConfirm
            ) { request in
                Button("Schedule") {
                    pendingAlarmConfirm = nil
                    Task { await scheduleAlarm(request) }
                }
                Button("Cancel", role: .cancel) { pendingAlarmConfirm = nil }
            } message: { request in
                Text("Set \(request.summary)? It will ring through Silent mode and Focus.")
            }
            .sheet(isPresented: $showAttachmentPicker) {
                AttachmentPickerSheet { result in
                    handleAttachmentResult(result)
                }
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.hidden)
                // Lane J (J-3): detents only apply in compact — in a regular
                // (iPad) window this sheet becomes a form-sheet card, and
                // without a fitted height its 220pt of content floats in a
                // mostly empty full-height card. Compact behavior unchanged.
                .presentationSizing(.form.fitted(horizontal: false, vertical: true))
            }
            .sheet(isPresented: $showExportShareSheet) {
                if let exportShareURL {
                    ShareSheet(activityItems: [exportShareURL])
                }
            }
    }

    private var mainStack: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScanLine(intensity: 0.32)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                agentIdentityStrip

                // #31: the standalone brain can't run (Apple Intelligence off /
                // unsupported / downloading) and no Hermes is carrying chat —
                // show the honest explanation state, never a dead screen.
                // #30: a PCC pin that degraded to on-device gets its one-line
                // notice; a conversation outgrowing the on-device window gets
                // the escalation offer (user decides, never silent).
                if let explanation = standaloneUnavailableExplanation {
                    standaloneUnavailableBanner(explanation)
                } else if let notice = container.chatBackendRouter?.privateCloudFallbackNotice {
                    privateCloudNoticeBanner(notice)
                } else if showsPrivateCloudEscalationOffer {
                    privateCloudEscalationBanner
                } else if showsConnectionBanner {
                    connectionBanner
                }
                messageList
                ChatInputBar(
                    text: $messageText,
                    pendingAttachments: $pendingAttachments,
                    isStreaming: chatStore.isStreaming,
                    isFocused: $isComposerFocused,
                    onSend: sendMessage,
                    onStop: { chatStore.cancelStreaming() },
                    onAttach: { showAttachmentPicker = true },
                    onSlashCommand: handleSlashCommand,
                    onPasteImage: { handleAttachmentResult(.image($0)) }
                )
                // Lane J (J-3): same readable measure as the transcript —
                // the composer card (attachment strip included) must not
                // stretch full-bleed at 13".
                .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
            }
        }
    }

    private var sessionsOverlay: some View {
        SessionsDrawer(
            isPresented: $sessionsOpen,
            model: sessionsModel,
            hostName: (hostStore.currentHost?.resolvedDisplayName ?? "HERMES HOST"),
            hostDetail: sessionsHostDetail,
            hostOnline: isChatHostOnline
        )
    }

    private var framedContent: some View {
        mainStack
            .overlay {
                if sessionsOpen {
                    sessionsOverlay
                }
            }
            // Animate the outer conditional so the drawer's move/opacity
            // transitions play on close too — closes were previously
            // torn down unanimated, so the panel popped instead of sliding (#42).
            .animation(Design.Motion.standard, value: sessionsOpen)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var lifecycleContent: some View {
        framedContent
            .onAppear { configureChatSeams() }
            // #48: hermes://ask?q=… — the seed can land before this screen
            // exists (cold launch → onAppear) or while it's on screen
            // (warm launch → onChange). Both paths drain the same store slot.
            .onAppear { consumeComposerSeed() }
            .onChange(of: chatStore.pendingComposerSeed) { _, seed in
                if seed != nil { consumeComposerSeed() }
            }
            .task { await startChatSession() }
            .task { await monitorConnectionStatus() }
            .onDisappear { chatStore.setPollingEnabled(false) }
    }

    private var observingContent: some View {
        lifecycleContent
            .onChange(of: sessionsOpen) { _, isOpen in
                if isOpen { Task { await refreshSessions() } }
            }
            .onChange(of: displayedModelName) { _, newValue in
                modelModel.activeModelNameOverride = newValue
            }
            .onChange(of: chatStore.conversation?.messages.count ?? 0) {
                guard chatStore.streamingMessageID == nil else { return }
                scrollToBottom()
            }
            .onChange(of: chatStore.pendingMessageSentAt) {
                guard chatStore.streamingMessageID == nil else { return }
                scrollToBottom()
            }
            .onChange(of: container.toolConfirmationCenter.pending?.id) { _, newValue in
                // #29: bring a freshly staged confirmation card into view.
                if let newValue {
                    withAnimation(Design.Motion.standard) {
                        scrollProxy?.scrollTo(newValue, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatStore.streamingMessageID) { old, new in
                if let new, old == nil {
                    scrollToResponseTop(new)
                }
                if old != nil && new == nil && settingsStore.settings.hapticFeedbackEnabled {
                    HapticEngine.responseReceived()
                }
            }
    }

    // MARK: - Shell wiring (presentation seams)

    /// Connects the Sessions drawer / Model selector shells to the Hermes
    /// Sessions API (model list + switch, session list + open).
    private func configureChatSeams() {
        modelModel.activeModelNameOverride = displayedModelName
        sessionsModel.onNewChat = { showClearConfirmation = true }
        sessionsModel.onOpenHostSettings = { router.presentSheet(.settings) }
        // Sessions drawer → Hermes Sessions API. Tapping a session loads its
        // full history and continues that thread.
        sessionsModel.onSelectSession = { summary in
            Task { await chatStore.openSession(summary.id) }
        }

        // Model chip → Settings → Models (the shim-backed real picker).
        // No local dropdown — the chip is a shortcut to the full picker.
        modelModel.onChipTap = { [router] in
            router.presentSheet(.settingsModels)
        }

        Task { await refreshSessions() }
    }

    /// Fetches the host's sessions and maps them into the drawer's view models.
    private func refreshSessions() async {
        let infos = await chatStore.loadSessions()
        sessionsModel.sessions = infos.map(Self.sessionSummary(from:))
    }

    /// Initial chat bootstrap: enable polling, refresh relay host + direct
    /// Sessions API health, then load the conversation. Extracted from `body`'s
    /// `.task` to keep that view expression cheap to type-check.
    private func startChatSession() async {
        chatStore.setPollingEnabled(true)
        await hostStore.refresh()
        await chatStore.refreshDirectHealth()
        await chatStore.loadConversationIfNeeded()
    }

    /// Periodically re-checks relay host status and direct Sessions API health
    /// while the chat screen is visible.
    private func monitorConnectionStatus() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { break }
            await hostStore.refresh()
            await chatStore.refreshDirectHealth()
        }
    }

    private static func sessionSummary(from info: HermesSessionInfo) -> SessionsDrawerModel.SessionSummary {
        let title = (info.title?.isEmpty == false)
            ? info.title!
            : ((info.preview?.isEmpty == false) ? info.preview! : "Untitled session")
        let subtitle = (info.preview?.isEmpty == false)
            ? info.preview!
            : "\(info.messageCount) message\(info.messageCount == 1 ? "" : "s")"
        let (group, timeLabel) = sessionGroupAndLabel(for: info.lastActive)
        return .init(
            id: info.id,
            title: title,
            subtitle: subtitle,
            timeLabel: timeLabel,
            group: group,
            isActive: info.isActive,
            isPinned: false,
            badge: info.source == "cron" ? "AUTO" : nil
        )
    }

    private static func sessionGroupAndLabel(for date: Date?) -> (SessionsDrawerModel.Group, String) {
        guard let date else { return (.earlier, "—") }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return (.today, sessionTimeFormatter.string(from: date)) }
        if cal.isDateInYesterday(date) { return (.yesterday, sessionTimeFormatter.string(from: date)) }
        if let days = cal.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return (.earlier, sessionWeekdayFormatter.string(from: date))
        }
        return (.earlier, sessionDateFormatter.string(from: date))
    }

    private static let sessionTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let sessionWeekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let sessionDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private var sessionsHostDetail: String {
        switch effectiveConnectionState {
        case .online: return "LINKED · ONLINE"
        case .offline: return "OFFLINE"
        case .unreachable: return "UNREACHABLE"
        case .notConnected: return "NOT CONNECTED"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation(Design.Motion.standard) { sessionsOpen = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
            }
            .accessibilityLabel("Sessions")
            .allowsHitTesting(!sessionsOpen)
        }
        ToolbarItem(placement: .principal) {
            ModelSelector(model: modelModel, isOnline: isChatHostOnline)
                .allowsHitTesting(!sessionsOpen)
        }
        ToolbarItem(placement: .topBarTrailing) {
            // #45: first reachable entry to the agent→phone Inbox. The pip is
            // real data — it appears only when unread items actually exist.
            GlassCircleButton(icon: "tray", accessibilityLabel: inboxAccessibilityLabel) {
                router.navigate(to: .inbox)
            }
            .overlay(alignment: .topTrailing) {
                if inboxStore.unreadCount > 0 {
                    StatusPip(color: Design.Brand.forge, diameter: 7)
                        .offset(x: -3, y: 3)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(!sessionsOpen)
        }
        ToolbarItem(placement: .topBarTrailing) {
            GlassCircleButton(icon: "gearshape", accessibilityLabel: "Open settings") {
                router.presentSheet(.settings)
            }
            .allowsHitTesting(!sessionsOpen)
        }
    }

    private var inboxAccessibilityLabel: String {
        let unread = inboxStore.unreadCount
        return unread > 0 ? "Open inbox. \(unread) unread." : "Open inbox"
    }

    /// Connection state for the chat UI. Chat talks **directly** to the Hermes
    /// Sessions API (localhost:8642), not the relay, so the banner and status
    /// indicators must reflect that direct reachability. `hostStore.connectionState`
    /// is relay-sourced and the relay is offline by design, which would otherwise
    /// paint a false "Hermes host offline" banner and a stale/offline model chip.
    private var effectiveConnectionState: HermesHostConnectionState {
        switch chatStore.directConnectionStatus {
        case .connected:
            return .online
        case .error:
            return .offline
        case .connecting, .disconnected:
            // Not yet probed (or a probe is in flight). Stay optimistic so we
            // never flash a false offline state before the first probe resolves.
            return .online
        }
    }

    // Explicitly-typed projections of `effectiveConnectionState`. Keeping these
    // out of `body` as plain Bools keeps that (already large) view expression
    // within the Swift type-checker's complexity budget.
    private var showsConnectionBanner: Bool {
        pairingStore.isPaired && effectiveConnectionState != .online
    }

    private var isChatHostOnline: Bool {
        effectiveConnectionState == .online
    }

    private var displayedModelName: String? {
        // The live model comes from the direct Sessions API path (selection /
        // `/model` switch detection). The relay's `hermesModel` is intentionally
        // not used as a fallback — the relay is offline by design, so it would
        // only ever surface a stale value.
        chatStore.activeModelName
    }

    private var effectiveContextWindow: Int? {
        chatStore.resolvedContextWindow(fallbackModelName: displayedModelName)
    }

    private var currentContextTokens: Int? {
        chatStore.currentContextTokens
    }

    /// Context usage as 0.0–1.0. Shows 0 when no usage data yet.
    private var contextProgress: Double {
        guard let usedTokens = currentContextTokens,
              let maxCtx = effectiveContextWindow, maxCtx > 0
        else { return 0 }
        return min(Double(usedTokens) / Double(maxCtx), 1.0)
    }

    // MARK: - Agent identity strip (HUD telemetry header)

    private var agentIdentityStrip: some View {
        HStack(spacing: Design.Spacing.sm) {
            ReactorOrb(size: Design.Size.orbNav, style: .standard)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Design.Spacing.xs) {
                    // #42: the wordmark can never give up width — squeezed, it
                    // character-wraps (HE/RM/ES). The telemetry label next to
                    // it absorbs the pressure instead (shrink, then truncate).
                    Text("HERMES")
                        .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                        .tracking(Design.Tracking.button)
                        .foregroundStyle(Design.Colors.foregroundBright)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    StatusPip(color: connectionIndicatorColor, diameter: 6,
                              blinks: effectiveConnectionState != .online)
                    MonoLabel(connectionTelemetry, size: 9, tracking: Design.Tracking.mono)
                        .hudSingleLine()
                }
                MonoLabel(messageTelemetry, size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
                    .hudSingleLine()
            }

            Spacer(minLength: Design.Spacing.sm)

            // #27: always-visible brain indicator; becomes the picker menu
            // once any Hermes host exists.
            if let brainRouter = container.chatBackendRouter {
                brainIndicator(brainRouter)
            }

            if effectiveContextWindow != nil {
                contextGauge
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xs)
        .padding(.bottom, Design.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hermes \(connectionStatusLabel), brain \(container.chatBackendRouter?.activeBrain.displayLabel ?? "Hermes")")
    }

    // MARK: - Brain indicator + picker (#27)

    @ViewBuilder
    private func brainIndicator(_ brainRouter: ChatBackendRouter) -> some View {
        if brainRouter.showsBrainPicker {
            Menu {
                brainPickerEntries(brainRouter)
            } label: {
                brainChip(brainRouter.activeBrain, showsChevron: true)
            }
            .accessibilityLabel("Chat brain: \(brainRouter.activeBrain.displayLabel). Tap to change.")
        } else {
            brainChip(brainRouter.activeBrain, showsChevron: false)
                .accessibilityLabel("Chat brain: \(brainRouter.activeBrain.displayLabel)")
        }
    }

    @ViewBuilder
    private func brainPickerEntries(_ brainRouter: ChatBackendRouter) -> some View {
        let conversationID = chatStore.conversation?.id
        let current = brainRouter.preferredBrain(forConversation: conversationID)
        Button {
            brainRouter.setPreferredBrain(nil, forConversation: conversationID)
        } label: {
            if current == nil {
                Label("Automatic", systemImage: "checkmark")
            } else {
                Text("Automatic")
            }
        }
        ForEach(brainRouter.selectableBrains, id: \.rawValue) { brain in
            Button {
                brainRouter.setPreferredBrain(brain, forConversation: conversationID)
            } label: {
                if current == brain {
                    Label(brain.displayLabel, systemImage: "checkmark")
                } else {
                    Label(brain.displayLabel, systemImage: brain.glyph)
                }
            }
        }
    }

    private func brainChip(_ brain: ChatBackendRouter.Brain, showsChevron: Bool) -> some View {
        HStack(spacing: Design.Spacing.xxs) {
            Image(systemName: brain.glyph)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Design.Brand.accent)
            // #42: the pill reserves its widest label's width (ON-DEVICE) so
            // it can never wrap inside itself and keeps one size across brain
            // switches.
            ZStack {
                MonoLabel(ChatBackendRouter.Brain.widestMonoLabel, size: 9,
                          tracking: Design.Tracking.mono)
                    .hidden()
                MonoLabel(brain.monoLabel, size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.coolForeground)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Design.Colors.dimForeground)
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xxs + 1)
        .hudPanel(
            cornerRadius: Design.CornerRadius.full,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
    }

    private var contextGauge: some View {
        VStack(alignment: .trailing, spacing: 4) {
            MonoLabel("CTX \(Int(contextProgress * 100))%", size: 10, tracking: Design.Tracking.mono)
                .hudSingleLine()
            Capsule()
                .fill(Design.Colors.accentTint(0.16))
                .frame(width: 48, height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(contextColor(contextProgress))
                            .frame(width: max(proxy.size.width * contextProgress, 2))
                            .hudGlow(contextColor(contextProgress), radius: 4, strength: 0.8)
                    }
                }
        }
        // #46: the gauge opens the session status card — the display half of
        // the usage that was always decoded (StatusCardView shipped dead;
        // showStatusCard was only ever set false).
        .contentShape(Rectangle())
        .onTapGesture { toggleStatusCard() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Context \(Int(contextProgress * 100)) percent. Shows session status and turn receipts.")
    }

    /// #46: toggle from the CTX gauge; opening scrolls the card into view
    /// (it renders below the last message).
    private func toggleStatusCard() {
        withAnimation(Design.Motion.standard) {
            showStatusCard.toggle()
        }
        guard showStatusCard else { return }
        withAnimation(Design.Motion.standard) {
            scrollProxy?.scrollTo(statusCardID, anchor: .bottom)
        }
    }

    /// #46: the newest Hermes turn that carries a receipt — drives the
    /// LAST TURN duration/cost rows on the status card.
    private var lastMeteredTurn: Message? {
        chatStore.conversation?.messages.last(where: { $0.sender == .hermes && $0.usage != nil })
    }

    private var lastMeteredTurnCost: Double? {
        guard let turn = lastMeteredTurn, let usage = turn.usage else { return nil }
        return ModelPricingCatalog.shared.estimatedCost(for: usage, model: turn.servingModel)
    }

    private var sessionCostEstimate: (cost: Double, costedTurns: Int)? {
        guard let messages = chatStore.conversation?.messages else { return nil }
        return ModelPricingCatalog.shared.estimatedSessionCost(for: messages)
    }

    private var connectionTelemetry: String {
        let host = hostStore.currentHost?.resolvedDisplayName.uppercased()
        switch effectiveConnectionState {
        case .online: return "ONLINE\(host.map { " · \($0)" } ?? "")"
        case .offline: return "OFFLINE"
        case .unreachable: return "UNREACHABLE"
        case .notConnected: return "NO HOST"
        }
    }

    private var messageTelemetry: String {
        let count = chatStore.conversation?.messages.count ?? 0
        return "\(count) MESSAGE\(count == 1 ? "" : "S")"
    }

    private func contextColor(_ progress: Double) -> Color {
        if progress > 0.85 { return Design.Colors.danger }
        if progress > 0.65 { return Design.Brand.forge }
        return Design.Brand.accent
    }

    private var connectionIndicatorColor: Color {
        switch effectiveConnectionState {
        case .online:
            return Design.Brand.accent
        case .offline, .unreachable:
            return Design.Brand.forge
        case .notConnected:
            return Design.Colors.dimForeground
        }
    }

    private var connectionStatusLabel: String {
        switch effectiveConnectionState {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .unreachable:
            return "Unreachable"
        case .notConnected:
            return "Not Connected"
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Design.Spacing.md) {
                    if let messages = chatStore.conversation?.messages {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                onRetry: { failedMessage in
                                    Task { await chatStore.retryMessage(failedMessage) }
                                },
                                isTranscriptBusy: chatStore.isStreaming,
                                onRegenerate: { reply in
                                    Task { await performRegenerate(reply) }
                                },
                                onEditResend: { userMessage in
                                    performEditResend(userMessage)
                                }
                            )
                            .id(message.id)
                        }
                    }

                    if let sentAt = chatStore.pendingMessageSentAt,
                       chatStore.streamingMessageID == nil {
                        ThinkingIndicatorView(startTime: sentAt)
                            .id(thinkingIndicatorID)
                            .transition(.opacity)
                    }

                    // #29: a side-effecting tool is suspended on the confirm
                    // gate — the card renders in the transcript until the
                    // user approves (with edits) or cancels.
                    if let pendingConfirmation = container.toolConfirmationCenter.pending {
                        ToolConfirmationCard(
                            center: container.toolConfirmationCenter,
                            confirmation: pendingConfirmation
                        )
                        .id(pendingConfirmation.id)
                        .transition(.opacity)
                    }

                    if showStatusCard {
                        StatusCardView(
                            connectionLabel: connectionStatusLabel,
                            messageCount: chatStore.conversation?.messages.count ?? 0,
                            conversationID: chatStore.conversation?.id,
                            tokenUsage: chatStore.lastTokenUsage,
                            dismissAction: { showStatusCard = false },
                            lastTurnDuration: lastMeteredTurn?.turnDuration,
                            lastTurnCost: lastMeteredTurnCost,
                            sessionTotals: chatStore.sessionUsageTotals,
                            sessionCost: sessionCostEstimate
                        )
                        .id(statusCardID)
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, Design.Spacing.md)
                // Lane J (J-3): readable measure on wide windows. The scroll
                // view stays full-bleed; only the content column is capped
                // (ScrollView centers narrower content on the cross axis).
                .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            .redacted(reason: chatStore.isLoading ? .placeholder : [])
            .onTapGesture {
                isComposerFocused = false
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    // MARK: - Standalone availability (#31)

    /// Non-nil while the NEXT message would route to the on-device brain and
    /// that brain is unavailable — the message carries reason-specific enable
    /// instructions (#26's honest unavailability strings).
    private var standaloneUnavailableExplanation: String? {
        guard let brainRouter = container.chatBackendRouter,
              brainRouter.activeBrain != .hermes else { return nil }
        return container.localChatBackend?.availabilityExplanation
    }

    private func standaloneUnavailableBanner(_ explanation: String) -> some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Brand.forge)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                MonoLabel("ON-DEVICE INTELLIGENCE UNAVAILABLE", size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                Text(explanation)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button("Connect") {
                router.dismissSheet()
                router.navigate(to: .connectHost)
            }
            .font(Design.Typography.mono(11, weight: .medium))
            .foregroundStyle(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Brand.forge.opacity(0.35))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
        .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Private Cloud β surfaces (#30)

    /// One-line honest notice: a PCC-pinned conversation degraded to
    /// on-device (unavailable / daily quota). The router clears it when PCC
    /// recovers or the preference changes.
    private func privateCloudNoticeBanner(_ notice: String) -> some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "cloud")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Brand.forge)
            Text(notice)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
            Spacer()
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Brand.forge.opacity(0.35))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
        .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
        .accessibilityElement(children: .combine)
    }

    /// The conversation outgrew the on-device context window and PCC is
    /// actually available — offer the 32K tier once. The user decides.
    private var showsPrivateCloudEscalationOffer: Bool {
        container.localChatBackend?.shouldOfferPrivateCloudEscalation == true
            && container.chatBackendRouter?.activeBrain == .onDevice
    }

    private var privateCloudEscalationBanner: some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "cloud")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Brand.accent)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                MonoLabel("CONVERSATION GETTING LONG", size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                Text("Continue on Private Cloud β? Larger context, same privacy — labeled beta.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button("Not now") {
                container.localChatBackend?.dismissPrivateCloudEscalationOffer()
            }
            .font(Design.Typography.mono(11, weight: .medium))
            .foregroundStyle(Design.Colors.mutedForeground)

            Button("Continue on β") {
                container.chatBackendRouter?.setPreferredBrain(.privateCloud, forConversation: chatStore.conversation?.id)
                container.localChatBackend?.dismissPrivateCloudEscalationOffer()
            }
            .font(Design.Typography.mono(11, weight: .medium))
            .foregroundStyle(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Colors.accentTint(0.35))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
        .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
        .accessibilityElement(children: .combine)
    }

    private var connectionBanner: some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: connectionBannerIcon)
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(connectionIndicatorColor)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                MonoLabel(connectionBannerTitle, size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                Text(connectionBannerMessage)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button(connectionBannerActionLabel) {
                connectionBannerAction()
            }
            .font(Design.Typography.mono(11, weight: .medium))
            .foregroundStyle(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Brand.forge.opacity(0.35))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
        .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
    }

    private var connectionBannerIcon: String {
        switch effectiveConnectionState {
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

    private var connectionBannerTitle: String {
        switch effectiveConnectionState {
        case .online:
            return "Hermes host online"
        case .offline:
            return "Hermes host offline"
        case .unreachable:
            return "Could not refresh host status"
        case .notConnected:
            return "No Hermes host connected"
        }
    }

    private var connectionBannerMessage: String {
        switch effectiveConnectionState {
        case .online:
            return "Your Hermes host is connected."
        case .offline:
            return "Your Hermes host isn't responding. Check that it's running and your connection settings."
        case .unreachable:
            return hostStore.lastErrorMessage ?? "Check your relay connection or refresh your session."
        case .notConnected:
            return "Pair a Hermes host from Settings to send messages through your Mac."
        }
    }

    private var connectionBannerActionLabel: String {
        switch effectiveConnectionState {
        case .online, .offline, .notConnected:
            return "Settings"
        case .unreachable:
            return "Retry"
        }
    }

    private func connectionBannerAction() {
        switch effectiveConnectionState {
        case .unreachable:
            Task { await hostStore.refresh() }
        case .online, .offline, .notConnected:
            router.presentSheet(.settings)
        }
    }

    // MARK: - Actions

    /// #48: pull a `hermes://ask?q=…` payload into the composer and focus it.
    /// Seed-only — the user reviews and taps send; an externally fired URL
    /// must never auto-send a turn.
    private func consumeComposerSeed() {
        guard let seed = chatStore.consumeComposerSeed() else { return }
        messageText = seed
        isComposerFocused = true
    }

    /// #44: context-menu Regenerate — re-roll any successful Hermes reply.
    private func performRegenerate(_ reply: Message) async {
        await chatStore.regenerateReply(reply)
        scrollToBottom()
    }

    /// #44: context-menu Edit & Resend — truncate from the user turn (the
    /// `/undo` semantics) and stage its text + restorable attachments back
    /// into the composer for the user to edit and send.
    private func performEditResend(_ userMessage: Message) {
        guard let turn = chatStore.extractTurnForEditing(userMessage) else { return }
        messageText = turn.text
        pendingAttachments = turn.attachments
        isComposerFocused = true
    }

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !content.isEmpty || !attachments.isEmpty else { return }
        messageText = ""
        pendingAttachments = []

        if settingsStore.settings.hapticFeedbackEnabled {
            HapticEngine.messageSent()
        }

        Task {
            if content.hasPrefix("/") && attachments.isEmpty {
                await dispatchTypedSlashCommand(content)
            } else {
                await chatStore.sendMessage(content, attachments: attachments)
            }
            scrollToBottom()
        }
    }

    func handleAttachmentResult(_ result: AttachmentResult) {
        guard pendingAttachments.count < PendingAttachment.maxAttachmentsPerMessage else { return }
        switch result {
        case .image(let image):
            if let attachment = PendingAttachment.image(image) {
                pendingAttachments.append(attachment)
            }
        case .file(let url):
            if let attachment = PendingAttachment.file(at: url) {
                pendingAttachments.append(attachment)
            }
        case .voiceMemo(let attachment):
            // Staged by the recorder flow (#9) — transcript data + audio path.
            pendingAttachments.append(attachment)
        }
    }

    private func handleSlashCommand(_ command: SlashCommand, _ argument: String?) {
        // Agent pass-through: send the raw slash command text as a chat message.
        // The Hermes agent processes it natively — same as Discord/Telegram.
        guard command.isLocal else {
            let messageText: String
            if let arg = argument?.trimmingCharacters(in: .whitespacesAndNewlines), !arg.isEmpty {
                messageText = "/\(command.name) \(arg)"
            } else {
                messageText = "/\(command.name)"
            }
            Task { await sendSlashAsMessage(messageText) }
            return
        }

        // Local commands handled by the iOS app directly.
        switch command.name {
        case "new", "reset", "clear":
            showClearConfirmation = true

        case "history":
            showConversationHistory()

        case "save":
            do {
                let fileURL = try chatStore.exportConversationToFile()
                appendSystemMessage("Conversation saved to Documents folder as \(fileURL.lastPathComponent).")
                exportShareURL = fileURL
                showExportShareSheet = true
            } catch {
                appendSystemMessage("Couldn't save the conversation: \(error.localizedDescription)")
            }

        case "retry":
            Task { await performRetry() }

        case "undo":
            performUndo()

        case "title":
            if let name = argument?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                chatStore.setConversationTitle(name)
                appendSystemMessage("Session title set: \(name)")
            } else {
                let current = chatStore.conversation?.title ?? Conversation.defaultTitle
                let id = chatStore.conversation.map { String($0.id.uuidString.prefix(8)) } ?? "—"
                // #4.8: the on-device preview, when the first exchange has
                // been summarized.
                let previewLine = chatStore.conversation?.generatedPreview.map { "\nPreview: \($0)" } ?? ""
                appendSystemMessage("Session ID: \(id)…\nTitle: \(current)\(previewLine)\nUsage: /title <your session title>")
            }

        case "alarm":
            // #16: parse → stage → confirm gate. Scheduling happens only in
            // scheduleAlarm(_:) after the dialog's explicit confirm.
            let trimmedArg = argument?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedArg.isEmpty {
                appendSystemMessage("Usage: /alarm 6:30am [label] for an alarm, or /alarm 25m [label] for a timer.")
            } else if let request = AlarmService.parse(trimmedArg) {
                pendingAlarmConfirm = request
            } else {
                appendSystemMessage("Couldn't read a time from \"\(trimmedArg)\". Try /alarm 6:30am, /alarm 18:45, or /alarm 25m.")
            }

        default:
            break
        }
    }

    /// #16: runs only after the confirm gate. Success and failure both land in
    /// the transcript so the command always has a visible receipt.
    private func scheduleAlarm(_ request: AlarmService.AlarmRequest) async {
        do {
            try await container.alarmService.schedule(request)
            appendSystemMessage("Scheduled \(request.summary) — it will ring through Silent mode and Focus.")
        } catch {
            appendSystemMessage("Couldn't schedule the \(request.kindNoun): \(error.localizedDescription)")
        }
    }

    /// Sends a slash command as a regular chat message to the Hermes agent.
    private func sendSlashAsMessage(_ text: String) async {
        await chatStore.sendMessage(text, attachments: [])
        scrollToBottom()
    }

    private func dispatchTypedSlashCommand(_ text: String) async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/") else {
            await chatStore.sendMessage(raw, attachments: [])
            return
        }

        let body = String(raw.dropFirst())
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return }

        let commandName = String(first).lowercased()
        let argument = parts.count > 1 ? String(parts[1]) : nil
        let localCommand = (chatStore.commandCatalog + SlashCommand.localCommands)
            .first { $0.name == commandName && $0.suggestedArgument == nil && $0.isLocal }

        if let localCommand {
            handleSlashCommand(localCommand, argument)
        } else {
            await sendSlashAsMessage(raw)
        }
    }

    private func performClear() async {
        do {
            try await chatStore.clearConversation()
            showStatusCard = false
        } catch {
            // Conversation unchanged on failure — user can retry
        }
    }

    private func performRetry() async {
        guard let messages = chatStore.conversation?.messages, !messages.isEmpty else {
            appendSystemMessage("No messages to retry.")
            return
        }

        // Find the last user message
        guard let lastUserIdx = messages.lastIndex(where: { $0.sender == .user }) else {
            appendSystemMessage("No user message found to retry.")
            return
        }

        let lastUserMessage = messages[lastUserIdx]
        let lastUserContent = lastUserMessage.content
        let attachments = lastUserMessage.attachments.compactMap(PendingAttachment.restore)
        let normalizedContent: String
        if !lastUserMessage.attachments.isEmpty,
           lastUserContent.range(of: #"^\[\d+ attachment"#, options: .regularExpression) != nil {
            normalizedContent = ""
        } else {
            normalizedContent = lastUserContent
        }

        // Remove everything from the last user message onward (user msg + assistant response + tool msgs)
        chatStore.conversation?.messages.removeSubrange(lastUserIdx...)

        appendSystemMessage("Retrying: \"\(String(lastUserContent.prefix(60)))\(lastUserContent.count > 60 ? "..." : "")\"")

        // Re-send the message through the full pipeline
        await chatStore.sendMessage(normalizedContent, attachments: attachments)
        scrollToBottom()
    }

    private func performUndo() {
        guard let messages = chatStore.conversation?.messages, !messages.isEmpty else {
            appendSystemMessage("No messages to undo.")
            return
        }

        // Walk backwards to find the last user message
        guard let lastUserIdx = messages.lastIndex(where: { $0.sender == .user }) else {
            appendSystemMessage("No user message found to undo.")
            return
        }

        let removedContent = messages[lastUserIdx].content
        let removedCount = messages.count - lastUserIdx

        // Truncate history to before the last user message
        chatStore.conversation?.messages.removeSubrange(lastUserIdx...)

        let remaining = chatStore.conversation?.messages.count ?? 0
        appendSystemMessage("Undid \(removedCount) message\(removedCount == 1 ? "" : "s"). Removed: \"\(String(removedContent.prefix(60)))\(removedContent.count > 60 ? "..." : "")\"\n\(remaining) message\(remaining == 1 ? "" : "s") remaining.")
    }

    private func showConversationHistory() {
        guard let messages = chatStore.conversation?.messages, !messages.isEmpty else {
            appendSystemMessage("No conversation history yet.")
            return
        }

        let previewLimit = 200
        var lines: [String] = ["── Conversation History ──"]
        var visibleIndex = 0

        for msg in messages {
            guard msg.sender == .user || msg.sender == .hermes else { continue }
            visibleIndex += 1
            let role = msg.sender == .user ? "You" : "Hermes"
            let preview = msg.content.prefix(previewLimit)
            let suffix = msg.content.count > previewLimit ? "..." : ""
            lines.append("[\(role) #\(visibleIndex)] \(preview)\(suffix)")
        }

        lines.append("\(visibleIndex) visible message\(visibleIndex == 1 ? "" : "s"), \(messages.count) total")
        appendSystemMessage(lines.joined(separator: "\n"))
    }

    private func appendSystemMessage(_ text: String) {
        let msg = Message(sender: .system, content: text, status: .delivered)
        chatStore.conversation?.messages.append(msg)
        scrollToBottom()
    }

    private func scrollToBottom() {
        let targetID: UUID
        if chatStore.pendingMessageSentAt != nil {
            targetID = thinkingIndicatorID
        } else if let lastID = chatStore.conversation?.messages.last?.id {
            targetID = lastID
        } else {
            return
        }
        withAnimation(Design.Motion.standard) {
            scrollProxy?.scrollTo(targetID, anchor: .bottom)
        }
    }

    private func scrollToResponseTop(_ id: UUID) {
        // Keep the start of the assistant response in view; without this,
        // a bottom-anchored ScrollView fights the growing message and feels flickery.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy?.scrollTo(id, anchor: .top)
        }
    }
}
