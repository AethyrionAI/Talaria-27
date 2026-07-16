import SwiftUI

/// Lane J (J-8): connection presentation shared by ChatScreen and the
/// split-view sidebar footer (MainTabView) — one mapping, two surfaces.
enum ChatConnectionPresentation {
    /// Chat talks directly to the Sessions API — the relay-sourced host
    /// state must not paint chat status (see ChatScreen's original note).
    static func effectiveState(_ direct: ConnectionStatus) -> HermesHostConnectionState {
        switch direct {
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

    static func sessionsHostDetail(_ state: HermesHostConnectionState) -> String {
        switch state {
        case .online: return "LINKED · ONLINE"
        case .offline: return "OFFLINE"
        case .unreachable: return "UNREACHABLE"
        case .notConnected: return "NOT CONNECTED"
        }
    }
}

struct ChatScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(ChatStore.self) private var chatStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(InboxStore.self) private var inboxStore
    @Environment(TabRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Lane J (J-9): composer draft + staged attachments and the sessions
    // model are OWNED BY MainTabView and passed in. The compact and regular
    // root layouts are different view trees, so a size-class boundary
    // crossing (Stage Manager drag) recreates this screen — anything that
    // must survive it cannot be @State here.
    @Binding var messageText: String
    @Binding var pendingAttachments: [PendingAttachment]
    let sessionsModel: SessionsDrawerModel
    /// False in the regular split layout, where MainTabView draws ONE
    /// atmosphere spanning the whole window behind both columns (J-9).
    var showsAtmosphere: Bool = true
    /// Regular width overrides ⌘K (focus the sidebar's inline filter field)
    /// instead of this screen's default (present the search sheet).
    var onConversationSearchShortcut: (() -> Void)? = nil

    init(
        messageText: Binding<String>,
        pendingAttachments: Binding<[PendingAttachment]>,
        sessionsModel: SessionsDrawerModel,
        showsAtmosphere: Bool = true,
        onConversationSearchShortcut: (() -> Void)? = nil
    ) {
        self._messageText = messageText
        self._pendingAttachments = pendingAttachments
        self.sessionsModel = sessionsModel
        self.showsAtmosphere = showsAtmosphere
        self.onConversationSearchShortcut = onConversationSearchShortcut
    }

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
    @State private var modelModel = ModelSelectorModel()

    // Lane J (J-4): ⌘K presents the Lane F search screen directly from the
    // chat surface — no need to open the drawer first. Same screen, same
    // model, same selection seam as the drawer's magnifying-glass button.
    @State private var showConversationSearch = false

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
            .sheet(isPresented: $showConversationSearch) {
                // J-4 (⌘K): the search screen dismisses itself on selection;
                // opening a hit routes through the drawer model's existing
                // selection seam (wired in configureChatSeams).
                ConversationSearchScreen(drawerModel: sessionsModel)
            }
    }

    private var mainStack: some View {
        ZStack {
            // J-9: suppressed in the regular split layout — MainTabView draws
            // one atmosphere behind both columns instead of per-column copies.
            if showsAtmosphere {
                HUDScreenBackground()
                    .ignoresSafeArea()

                ScanLine(intensity: 0.32)
                    .ignoresSafeArea()
            }

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
                // J-8: the drawer is the COMPACT list surface; regular width
                // has the persistent sidebar instead.
                if sessionsOpen && horizontalSizeClass != .regular {
                    sessionsOverlay
                }
            }
            .onChange(of: horizontalSizeClass) { _, newClass in
                // Crossing into regular (Stage Manager drag) with the drawer
                // open: the sidebar takes over — don't leave a stale overlay
                // flag that would pop the drawer back on the return trip.
                if newClass == .regular { sessionsOpen = false }
            }
            // Animate the outer conditional so the drawer's move/opacity
            // transitions play on close too — closes were previously
            // torn down unanimated, so the panel popped instead of sliding (#42).
            .animation(Design.Motion.standard, value: sessionsOpen)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.hidden, for: .navigationBar)
            .background { shortcutBridge }
    }

    // MARK: - Hardware keyboard shortcuts (Lane J, J-4)

    /// Zero-size, invisible buttons that exist only to register hardware
    /// keyboard shortcuts while the chat surface is on screen (their labels
    /// feed the iPadOS ⌘-hold discoverability HUD). Presented sheets take
    /// shortcut precedence, so these go quiet behind Settings/search/etc.
    /// Key assignments live in `ChatKeyboardShortcuts` (testable table).
    private var shortcutBridge: some View {
        Group {
            Button("New Conversation") { showClearConfirmation = true }
                .keyboardShortcut(ChatKeyboardShortcuts.newConversation.key,
                                  modifiers: ChatKeyboardShortcuts.newConversation.modifiers)
            Button("Search Conversations") { openConversationSearch() }
                .keyboardShortcut(ChatKeyboardShortcuts.conversationSearch.key,
                                  modifiers: ChatKeyboardShortcuts.conversationSearch.modifiers)
            Button("Settings") { router.presentSheet(.settings) }
                .keyboardShortcut(ChatKeyboardShortcuts.openSettings.key,
                                  modifiers: ChatKeyboardShortcuts.openSettings.modifiers)
            ForEach(1..<(ChatKeyboardShortcuts.sessionJumpCount + 1), id: \.self) { ordinal in
                Button("Open Conversation \(ordinal)") { openSessionJump(ordinal) }
                    .keyboardShortcut(ChatKeyboardShortcuts.sessionJump(ordinal).key,
                                      modifiers: ChatKeyboardShortcuts.sessionJump(ordinal).modifiers)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// ⌘K — present the Lane F full-corpus search. Wires the same store
    /// seams the drawer wires on open, so badges and selection behave
    /// identically whichever entry point raised the screen; closes the
    /// drawer rather than stacking a second presentation host. In regular
    /// width MainTabView overrides this to focus the sidebar's inline
    /// filter field directly (J-9).
    private func openConversationSearch() {
        if let onConversationSearchShortcut {
            onConversationSearchShortcut()
            return
        }
        sessionsModel.listState = container.conversationListState
        sessionsModel.journal = chatStore.journal
        sessionsOpen = false
        showConversationSearch = true
    }

    /// ⌘1…⌘9 — open the nth conversation in drawer order (pinned first,
    /// then recency; archived unreachable). No-op until the session list
    /// has been fetched (configureChatSeams / drawer open) or when fewer
    /// than n sessions exist — honest nothing, no fabricated target.
    private func openSessionJump(_ ordinal: Int) {
        let targets = ChatKeyboardShortcuts.sessionJumpTargets(
            sessions: sessionsModel.sessions,
            pinnedIDs: container.conversationListState?.state.pinnedSessionIDs ?? [],
            archivedIDs: container.conversationListState?.state.archivedSessionIDs ?? []
        )
        guard ordinal - 1 < targets.count else { return }
        sessionsOpen = false
        let target = targets[ordinal - 1]
        Task {
            await chatStore.openSession(target.id)
            // J-8: keep the persistent sidebar's list + highlight current.
            await refreshSessions()
        }
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
            Task {
                await chatStore.openSession(summary.id)
                // J-8: the persistent sidebar has no drawer-open refresh to
                // move the CURRENT highlight — re-fetch after the switch.
                // Neutral in compact: the drawer is closed by now and would
                // refetch on its next open anyway.
                await refreshSessions()
            }
        }
        // J-8: the persistent sidebar re-fetches on mount through this seam
        // (the drawer path refreshes via onChange(sessionsOpen) as before).
        sessionsModel.onRefreshRequest = { Task { await refreshSessions() } }

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
        let activeProfileID = container.profilesStore?.activeProfileID
        sessionsModel.sessions = infos.map {
            Self.sessionSummary(from: $0, activeProfileID: activeProfileID)
        }
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

    private static func sessionSummary(
        from info: HermesSessionInfo,
        activeProfileID: UUID? = nil
    ) -> SessionsDrawerModel.SessionSummary {
        let title = (info.title?.isEmpty == false)
            ? info.title!
            : ((info.preview?.isEmpty == false) ? info.preview! : "Untitled session")
        let subtitle = (info.preview?.isEmpty == false)
            ? info.preview!
            : "\(info.messageCount) message\(info.messageCount == 1 ? "" : "s")"
        let (group, timeLabel) = sessionGroupAndLabel(for: info.lastActive)
        // M-5: sessions living on a NON-ACTIVE backend profile carry their
        // host's name as the row badge; same-host rows keep the AUTO badge.
        let profileBadge: String? = {
            guard let profileID = info.profileID, profileID != activeProfileID else { return nil }
            return (info.profileName ?? "Remote").uppercased()
        }()
        return .init(
            id: info.id,
            title: title,
            subtitle: subtitle,
            timeLabel: timeLabel,
            group: group,
            isActive: info.isActive,
            isPinned: false,
            badge: profileBadge ?? (info.source == "cron" ? "AUTO" : nil)
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
        ChatConnectionPresentation.sessionsHostDetail(effectiveConnectionState)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // J-8: the hamburger opens the compact drawer; in regular width the
        // NavigationSplitView sidebar toggle owns that slot instead.
        if horizontalSizeClass != .regular {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(Design.Motion.standard) { sessionsOpen = true }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                }
                // Lane J (J-5): pointer affordance on iPad — inert without a pointer.
                .hoverEffect(.highlight)
                .accessibilityLabel("Sessions")
                .allowsHitTesting(!sessionsOpen)
            }
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
        ChatConnectionPresentation.effectiveState(chatStore.directConnectionStatus)
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
            // Lane J (J-5): the picker chip is tappable chrome; the static
            // chip below is not interactive and gets no hover.
            .hoverEffect(.highlight)
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
        // Lane J (J-5): pointer affordance on iPad — inert without a pointer.
        .hoverEffect(.highlight)
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
            .onAppear {
                let isFreshScrollSurface = (scrollProxy == nil)
                scrollProxy = proxy
                // J-9: a size-class boundary crossing recreates this screen
                // with the conversation already loaded — land back at the
                // transcript tail instead of the top. Unreachable in today's
                // iPhone flow (first appear always precedes the async load,
                // and pop-returns keep this view alive), so compact behavior
                // is untouched.
                if isFreshScrollSurface, let lastID = chatStore.conversation?.messages.last?.id {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
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
            // J-8: surface the fresh session in the persistent sidebar
            // (compact's drawer refetches on its next open regardless).
            await refreshSessions()
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
