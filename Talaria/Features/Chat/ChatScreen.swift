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
    @Environment(\.scenePhase) private var scenePhase

    // Lane J (J-9): composer draft + staged attachments and the sessions
    // model are OWNED BY MainTabView and passed in. The compact and regular
    // root layouts are different view trees, so a size-class boundary
    // crossing (Stage Manager drag) recreates this screen — anything that
    // must survive it cannot be @State here.
    @Binding var messageText: String
    @Binding var pendingAttachments: [PendingAttachment]
    let sessionsModel: SessionsDrawerModel
    /// #18: the drawer is hosted by MainTabView, above the whole navigation
    /// stack — this screen only opens and closes it.
    @Binding var sessionsOpen: Bool
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
        sessionsOpen: Binding<Bool> = .constant(false),
        showsAtmosphere: Bool = true,
        onConversationSearchShortcut: (() -> Void)? = nil
    ) {
        self._messageText = messageText
        self._pendingAttachments = pendingAttachments
        self.sessionsModel = sessionsModel
        self._sessionsOpen = sessionsOpen
        self.showsAtmosphere = showsAtmosphere
        self.onConversationSearchShortcut = onConversationSearchShortcut
    }

    /// #16: a parsed /alarm staged behind the in-app confirm gate — nothing
    /// schedules until the user confirms (decided policy for alarm writes).
    @State private var pendingAlarmConfirm: AlarmService.AlarmRequest?
    /// #203 (1A): drives re-evaluation of the stall hint. One shared 1s
    /// tick, not a timer per turn — nothing to start, stop, or leak.
    @State private var stallTick: Date = .now
    @State private var showStatusCard = false
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isComposerFocused: Bool

    @State private var showAttachmentPicker = false

    // `/save` success: the written transcript file, offered onward via the
    // share sheet (Save to Files / AirDrop / etc.).
    @State private var exportShareURL: URL?
    @State private var showExportShareSheet = false

    // HUD shells (presentation only — see SessionsDrawer / ModelSelector).
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
    /// #203 (1A): a quiet turn says so. Driven by a 1s tick rather than a
    /// timer per turn — `isStalled` is a pure comparison of two stored
    /// values, so re-evaluating it costs nothing and there is no timer to
    /// leak. The row disappears the moment any token, reasoning delta, or
    /// tool event lands.
    @ViewBuilder
    private var stallHint: some View {
        if ChatStore.isStalled(isStreaming: chatStore.isStreaming,
                               lastActivityAt: chatStore.lastStreamActivityAt,
                               now: stallTick) {
            HStack(spacing: Design.Spacing.xs) {
                ProgressView().scaleEffect(0.6)
                MonoLabel("Still working — tap Stop to cancel.",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.xs)
            .transition(.opacity)
        }
    }

    /// #205: DEBUG-only, and empty in the overwhelmingly common case where
    /// the shape IS production — so it costs a launch-time enum compare and
    /// nothing else. Release compiles it out entirely.
    @ViewBuilder
    private var debugSessionShapeBanner: some View {
        #if DEBUG
        if LocalChatBackend.activeSessionShape != .armedRouted {
            MonoLabel("⚠︎ BRAIN SHAPE OVERRIDE — \(LocalChatBackend.activeSessionShape.rawValue). Not production. Reset in Developer → Batteries.",
                      size: 9, tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.xs)
                .frame(maxWidth: .infinity)
                .background(Design.Brand.forge.opacity(0.85))
        }
        #endif
    }

    var body: some View {
        observingContent
            // #205: a persisted non-production brain shape is INVISIBLE. The
            // Diagnostics picker writes `debug.sessionShape` to UserDefaults
            // on purpose (desk A/B survives an OTA install), but a VALID
            // non-production cell name then persists across every later
            // launch — the whole app runs with a different belt,
            // instructions and routing, indistinguishable from a
            // catastrophic brain regression, with one os_log line as the
            // only signal. Retired names fail to parse and fall back to
            // production; valid ones do not. This is the banner that stops a
            // wasted debugging session.
            //
            // The MODIFIER is conditionally compiled, not just the banner's
            // content: in Release an empty @ViewBuilder made this
            // `safeAreaInset(edge: .top) { EmptyView() }`, and on iOS 27
            // beta 4 that collapsed the chat VStack to the bottom of the
            // screen — the transcript vanished and the identity strip sat on
            // the input bar. Debug (a real zero-height conditional view) was
            // unaffected, so every Debug check was blind to it (#218's
            // family, for UI).
            #if DEBUG
            .safeAreaInset(edge: .top, spacing: 0) { debugSessionShapeBanner }
            #endif
            // #203 (1A): re-evaluate the stall hint once a second while a
            // turn is in flight. Idle chats never tick.
            .task(id: chatStore.isStreaming) {
                guard chatStore.isStreaming else { return }
                while !Task.isCancelled && chatStore.isStreaming {
                    stallTick = .now
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            // #193: was a `.confirmationDialog`, whose cancel role does not
            // render on iOS 26/27 — a consent gate needs a visible decline,
            // so it's an alert now.
            .alert(
                "Schedule on this iPhone?",
                isPresented: Binding(
                    get: { pendingAlarmConfirm != nil },
                    set: { if !$0 { pendingAlarmConfirm = nil } }
                ),
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
                } else if let failure = chatStore.sessionOpenFailure {
                    sessionOpenFailureBanner(failure)
                } else if let notice = container.profileSwitchNotice {
                    // #247 B2: the switch verdict — a dead host is NAMED, and
                    // when every host is dead the banner says to check this
                    // phone's own network instead of letting the user debug
                    // by elimination.
                    routingNoticeBanner(notice, icon: "arrow.left.arrow.right")
                } else if let notice = container.chatBackendRouter?.privateCloudFallbackNotice {
                    routingNoticeBanner(notice, icon: "cloud")
                } else if let notice = container.chatBackendRouter?.automaticFallbackNotice {
                    // #192: automatic routing fell back to on-device (Hermes
                    // unreachable, no explicit pick) — announced, never a
                    // silently moved pill.
                    routingNoticeBanner(notice, icon: "antenna.radiowaves.left.and.right.slash")
                } else if showsPrivateCloudEscalationOffer {
                    privateCloudEscalationBanner
                } else if showsConnectionBanner {
                    connectionBanner
                }
                messageList
                // #203 (1A): the visible half. The Stop lives in the input
                // bar directly below, so the hint sits next to its own
                // remedy. It never cancels — #202B measured this model
                // fabricating when cut off from a tool it expected.
                stallHint
                ChatInputBar(
                    text: $messageText,
                    pendingAttachments: $pendingAttachments,
                    isStreaming: chatStore.isStreaming,
                    isFocused: $isComposerFocused,
                    onSend: sendMessage,
                    onStop: { chatStore.cancelStreaming() },
                    onAttach: { showAttachmentPicker = true },
                    onSlashCommand: handleSlashCommand,
                    onPasteImage: { handleAttachmentResult(.image($0)) },
                    // #306: the mid-turn queue — chip + commit control.
                    queuedChip: chatStore.currentThreadHeldTurn.map {
                        QueuedTurnChipModel(
                            text: $0.text,
                            door: .queued,
                            isSurfaced: $0.phase == .surfaced
                        )
                    },
                    canQueueMessage: chatStore.currentThreadHeldTurn == nil,
                    onQueueMessage: queueComposedMessage,
                    onChipSendNow: { Task { await chatStore.sendHeldTurnNow() } },
                    onChipEdit: editQueuedMessage,
                    onChipCancel: { chatStore.cancelHeldTurn() }
                )
                // Lane J (J-3): same readable measure as the transcript —
                // the composer card (attachment strip included) must not
                // stretch full-bleed at 13".
                .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
            }
        }
    }

    private var framedContent: some View {
        // #18: the drawer used to hang off this view as an `.overlay`, which
        // put it UNDER the navigation toolbar's layer. It is now a sibling of
        // the whole navigation stack in MainTabView; this screen only opens
        // and closes it. Crossing into regular width stops rendering it there
        // structurally, so the old stale-flag reset is gone with it.
        mainStack
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
            Button("New Conversation") { Task { await startNewChat(onProfileID: nil) } }
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
            archivedIDs: container.conversationListState?.state.archivedSessionIDs ?? [],
            // The ordinals must address what the shelf SHOWS — a jump list
            // counting rows the drawer hides is off-by-n by construction.
            showEmptySessions: settingsStore.settings.showEmptySessions
        )
        guard ordinal - 1 < targets.count else { return }
        sessionsOpen = false
        let target = targets[ordinal - 1]
        Task {
            await chatStore.openSession(target.id)
            // J-8: keep the persistent sidebar's list + highlight current.
            await refreshSessions(force: true)
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
            // #123: share-extension payloads ride a separate slot with the
            // same two-path drain (cold launch → onAppear, foreground with
            // the screen mounted → onChange).
            .onAppear { consumeShareSeed() }
            .onChange(of: chatStore.pendingShareSeed) { _, seed in
                if seed != nil { consumeShareSeed() }
            }
            .task { await startChatSession() }
            .task { await monitorConnectionStatus() }
            .task {
                // #235 F2: opening the chat is the user looking at the
                // transcript — one single-shot reconcile; the store's
                // single-flight coalesces with any in-flight pass; instant
                // no-op when nothing is pending.
                await chatStore.reconcilePendingRuns()
            }
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
        // #306 (O2/trap 7): the Stop-restore reads the composer's LIVE text
        // through this seam — an empty composer takes the held text back; a
        // diverged one keeps the user's typing and the hold surfaces on the
        // chip. `@State` storage is reference-backed, so the closure reads
        // the current value, not a capture.
        chatStore.composerLiveText = { messageText }
        // M-15: New Chat just starts one — archiving is non-destructive (the
        // conversation stays in the drawer), so the old "cannot be undone"
        // dialog was wrong on its face and is retired.
        sessionsModel.onNewChat = { Task { await startNewChat(onProfileID: nil) } }
        // M-16: "New chat on <profile>" — target a named backend for the
        // NEXT session without flipping the app-wide default.
        sessionsModel.onNewChatOnProfile = { profileID in
            Task { await startNewChat(onProfileID: profileID) }
        }
        sessionsModel.newChatProfiles = (container.profilesStore?.profiles ?? []).map {
            SessionsDrawerModel.NewChatProfileOption(id: $0.id, name: $0.name)
        }
        sessionsModel.activeNewChatProfileID = container.profilesStore?.activeProfileID
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
                await refreshSessions(force: true)
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
    ///
    /// #175: `force` separates "this view appeared" from "the list actually
    /// changed". Appearances coalesce onto ChatStore's snapshot — several
    /// independent views mount around launch and each used to fetch — while
    /// anything that opened, cleared or created a session fetches for real.
    private func refreshSessions(force: Bool = false) async {
        let infos = await chatStore.loadSessions(force: force)
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
    /// while the chat screen is visible. #175: cadence and the
    /// foreground-only rule live in `ChatHealthPollPolicy` — this used to be
    /// a flat 10s loop that ran while backgrounded too.
    private func monitorConnectionStatus() async {
        var unchangedProbes = 0
        var lastStatus = chatStore.directConnectionStatus
        while !Task.isCancelled {
            let interval = ChatHealthPollPolicy.interval(consecutiveUnchangedProbes: unchangedProbes)
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { break }
            guard ChatHealthPollPolicy.shouldProbe(scenePhase: pollScenePhase) else {
                // Re-probe promptly on return rather than up to a steady
                // interval later.
                unchangedProbes = 0
                continue
            }
            await hostStore.refresh()
            await chatStore.refreshDirectHealth()
            let status = chatStore.directConnectionStatus
            if status == lastStatus {
                unchangedProbes += 1
            } else {
                unchangedProbes = 0
                lastStatus = status
            }
        }
    }

    private var pollScenePhase: ChatHealthPollPolicy.ScenePhaseSnapshot {
        switch scenePhase {
        case .active: .active
        case .inactive: .inactive
        default: .background
        }
    }

    // Internal (not private) since #190: the origin/unresumable mapping is
    // asserted by unit tests through @testable import.
    static func sessionSummary(
        from info: HermesSessionInfo,
        activeProfileID: UUID? = nil
    ) -> SessionsDrawerModel.SessionSummary {
        let title = (info.title?.isEmpty == false)
            ? info.title!
            : ((info.preview?.isEmpty == false) ? info.preview! : "Untitled session")
        let subtitle: String = {
            // #190: a dimmed row's one line is its honest reason, not a
            // preview it can't deliver on.
            if !info.isResumable { return info.unresumableReason ?? "Unavailable" }
            // #180 lane 180-L / #177: step to the NEXT rung when the preview
            // would just repeat the title, instead of printing one string on
            // both lines.
            //
            // Two different causes land here and the fix is one:
            //   • Hermes derives BOTH `title` and `preview` from the first
            //     user message, so the server-fed drawer sends them
            //     near-identical by construction (#177);
            //   • a title-less row has already borrowed the preview AS its
            //     title three lines up, so reusing it here echoes it (#280's
            //     drawer symptom — belted here, NOT closed; 280-A asserts
            //     `conversation.title != Conversation.defaultTitle`, which
            //     this does not touch).
            //
            // The substitution is deliberately KEPT: a row whose only text is
            // its preview should still show it — once. This is
            // `LocalIntelligenceService.fallbackCard`'s rule (`:452-458`,
            // 2026-07-11, from a device-pass FAIL) finally generalized to the
            // server-fed row, and `HostFedListPresentation`'s rule 5
            // corollary in the general case: a fallback may NARROW a claim,
            // never SUBSTITUTE a different one.
            if let preview = info.preview, !preview.isEmpty, preview != title { return preview }
            guard info.messageCount > 0 else { return "No messages" }
            return "\(info.messageCount) message\(info.messageCount == 1 ? "" : "s")"
        }()
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
            badge: profileBadge ?? (info.source == "cron" ? "AUTO" : nil),
            messageCount: info.messageCount,
            origin: info.source == LocalChatBackend.localSessionSource ? .local : .remote,
            isUnresumable: !info.isResumable
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

    // MARK: - Toolbar

    /// #18's root cause, still live: SwiftUI's navigation toolbar renders
    /// ABOVE `.overlay` content, so the drawer cannot cover it. Opacity on the
    /// item's own view is not enough — on iOS 26+ the system draws each item's
    /// glass capsule OUTSIDE that view, so fading the content leaves an empty
    /// capsule floating over the panel. `sharedBackgroundVisibility` is what
    /// takes the material; the two have to travel together.
    ///
    /// Preferred over hiding the whole bar: `.toolbar(.hidden, for:
    /// .navigationBar)` would also drop the bar's height from the safe area
    /// and slide the chat up behind the panel — visible in the peek sliver
    /// while open, and a jump on close.
    private var toolbarBackgroundVisibility: Visibility {
        sessionsOpen ? .hidden : .automatic
    }

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
                .chatChromeSuppressed(sessionsOpen)
            }
            .sharedBackgroundVisibility(toolbarBackgroundVisibility)
        }
        ToolbarItem(placement: .principal) {
            ModelSelector(model: modelModel, isOnline: isChatHostOnline)
                .chatChromeSuppressed(sessionsOpen)
        }
        .sharedBackgroundVisibility(toolbarBackgroundVisibility)
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
            .chatChromeSuppressed(sessionsOpen)
        }
        .sharedBackgroundVisibility(toolbarBackgroundVisibility)
        ToolbarItem(placement: .topBarTrailing) {
            GlassCircleButton(icon: "gearshape", accessibilityLabel: "Open settings") {
                router.presentSheet(.settings)
            }
            .chatChromeSuppressed(sessionsOpen)
        }
        .sharedBackgroundVisibility(toolbarBackgroundVisibility)
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
        // #191: with a local brain active the toolbar pip reports LOCAL
        // readiness — Hermes reachability is not what's answering.
        isLocalBrainActive ? isLocalBrainReady : effectiveConnectionState == .online
    }

    // MARK: - Active-brain header truth (#191)

    /// #191: whether a LOCAL brain (on-device / PCC) will take the next
    /// message — the header must describe that brain, not the Hermes host.
    private var isLocalBrainActive: Bool {
        guard let brain = container.chatBackendRouter?.activeBrain else { return false }
        return brain != .hermes
    }

    private var isLocalBrainReady: Bool {
        container.localChatBackend?.availabilityExplanation == nil
    }

    private var displayedModelName: String? {
        // #191: the pill names the ACTIVE brain's model, never whatever the
        // loaded session shell last reported — a local brain must not wear a
        // Hermes model name (`KIMI-K3` in airplane mode was the filed
        // evidence).
        switch container.chatBackendRouter?.activeBrain {
        case .onDevice:
            return ChatBackendRouter.Brain.onDevice.displayLabel
        case .privateCloud:
            return ChatBackendRouter.Brain.privateCloud.displayLabel
        case .hermes, nil:
            // The live model comes from the direct Sessions API path (selection /
            // `/model` switch detection). The relay's `hermesModel` is intentionally
            // not used as a fallback — the relay is offline by design, so it would
            // only ever surface a stale value.
            return chatStore.activeModelName
        }
    }

    private var effectiveContextWindow: Int? {
        // Deliberately keyed to the Hermes-reported model, not the display
        // pill — #191 changed what the pill SHOWS, and CTX behavior (which
        // works, per the filed evidence) must not move with it.
        chatStore.resolvedContextWindow(fallbackModelName: chatStore.activeModelName)
    }

    private var currentContextTokens: Int? {
        chatStore.currentContextTokens
    }

    /// Context usage as 0.0–1.0. Only meaningful when `currentContextTokens`
    /// is known — the gauge hides otherwise (#25: an unknown numerator must
    /// read as absent, never as "CTX 0%"); the 0 here is just the guard's
    /// unreachable-by-render fallback.
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
                    Text(headerWordmark)
                        .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                        .tracking(Design.Tracking.button)
                        .foregroundStyle(Design.Colors.foregroundBright)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    StatusPip(color: connectionIndicatorColor, diameter: 6,
                              blinks: headerPipBlinks)
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

            // #25: both halves must be known — a context window (denominator)
            // AND a real numerator (a live `run.completed`, or the resume
            // cache the Sessions client reads in openSession). A session with
            // no cached usage — another device's, or one pre-dating the cache
            // — hides the gauge instead of lying 0%.
            if effectiveContextWindow != nil, currentContextTokens != nil {
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
        .accessibilityLabel("\(headerWordmark.capitalized) \(connectionStatusLabel), brain \(container.chatBackendRouter?.activeBrain.displayLabel ?? "Hermes")")
    }

    /// #191: the wordmark is the answering agent's identity — HERMES only
    /// when the Hermes brain will take the next message; TALARIA (the app
    /// itself) while a local brain holds the conversation. The title must
    /// never assert a host that is not answering.
    private var headerWordmark: String {
        isLocalBrainActive ? "TALARIA" : "HERMES"
    }

    private var headerPipBlinks: Bool {
        isLocalBrainActive ? !isLocalBrainReady : effectiveConnectionState != .online
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
        // #191: a local brain's status line may not assert a host — OJAMD is
        // not answering. Local readiness is the only truth it has.
        if isLocalBrainActive {
            return isLocalBrainReady ? "READY" : "UNAVAILABLE"
        }
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
        if isLocalBrainActive {
            return isLocalBrainReady ? Design.Brand.accent : Design.Brand.forge
        }
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
        if isLocalBrainActive {
            return isLocalBrainReady ? "Ready" : "Unavailable"
        }
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
                                // #278: NOT `isStreaming` — a dropped stream
                                // leaves a live run with `streamingMessageID`
                                // already nil, and the menu was offering
                                // history-mutating items straight into it.
                                isTranscriptBusy: chatStore.isTranscriptBusy,
                                onRegenerate: { reply in
                                    Task { await performRegenerate(reply) }
                                },
                                onEditResend: { userMessage in
                                    performEditResend(userMessage)
                                },
                                // #21 Tier 2: fetchable agent files download
                                // on tap from their birth profile's relay.
                                agentFileDownloads: chatStore.agentFileDownloads,
                                onFetchAgentFile: { hostMessage, attachment in
                                    Task { await chatStore.fetchAgentFile(attachment, in: hostMessage) }
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
            // #120 (UITest seam): mirrors the ForEach's rendered array so a
            // black-box test can assert id uniqueness. Inert unless the
            // UITEST_DUPID_PROBE launch env is set (never in shipping builds).
            .overlay(alignment: .top) {
                MessageListIdentityProbe(messages: chatStore.conversation?.messages ?? [])
            }
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

    /// #190B: a session tap that failed to open — the banner form of what
    /// used to be a silent log line. The current thread is unchanged (the
    /// open never adopted anything), so the banner rides above it until the
    /// user dismisses it, opens a session successfully, or starts a new chat.
    private func sessionOpenFailureBanner(_ failure: ChatStore.SessionOpenFailure) -> some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Colors.danger)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                MonoLabel("COULDN'T OPEN CONVERSATION", size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                Text(failure.message)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button {
                chatStore.dismissSessionOpenFailure()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Design.Size.iconSmall, weight: .medium))
                    .foregroundStyle(Design.Colors.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Colors.danger.opacity(0.35))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
        .frame(maxWidth: Design.Layout.chatMeasureMaxWidth)
    }

    // MARK: - Private Cloud β surfaces (#30)

    /// One-line honest routing notice — a PCC pick degraded to on-device
    /// (#30), or automatic routing fell back because Hermes is unreachable
    /// (#192). The router owns setting and clearing both.
    private func routingNoticeBanner(_ notice: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: icon)
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
                // pick-only (#192): the escalation is about THIS conversation
                // outgrowing the window — it must not rewrite the sticky
                // app-wide default.
                container.chatBackendRouter?.setPreferredBrain(.privateCloud, forConversation: chatStore.conversation?.id, updatesDefault: false)
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

    /// #123: pull drained share-extension content into the composer.
    /// APPENDS — a share arriving over a half-typed draft must not destroy
    /// it (unlike the #48 ask-seed, which replaces by contract). Attachments
    /// beyond the per-message cap are dropped, not silently absorbed.
    private func consumeShareSeed() {
        guard let seed = chatStore.consumeShareSeed() else { return }
        if !seed.text.isEmpty {
            messageText = messageText.isEmpty ? seed.text : messageText + "\n" + seed.text
        }
        for attachment in seed.attachments {
            guard pendingAttachments.count < PendingAttachment.maxAttachmentsPerMessage else {
                TalariaLog.event("Share seed: composer full, dropping \(attachment.fileName)")
                break
            }
            pendingAttachments.append(attachment)
        }
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

    /// #306: the queue-commit gesture — hold the composed text against this
    /// thread; it posts only after the running turn completes (the matrix).
    /// Text-only (O5) and never a slash command (a held one would post as
    /// plain prose at fire time). If the turn ended between render and tap,
    /// there is nothing to wait on — fall through to a normal send, which is
    /// what an immediate fire would have done anyway.
    private func queueComposedMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !content.hasPrefix("/") else { return }
        if chatStore.holdComposedTurn(content) {
            messageText = ""
            if settingsStore.settings.hapticFeedbackEnabled {
                HapticEngine.messageSent()
            }
        } else if !chatStore.isTranscriptBusy {
            sendMessage()
        }
        // A depth-1 refusal while the turn still runs leaves the text in the
        // composer — nothing is lost, nothing silently replaced.
    }

    /// #306: chip Edit — the held text comes back to the composer for the
    /// user to rework and re-commit (or send, once the turn is over).
    private func editQueuedMessage() {
        guard let text = chatStore.editHeldTurn() else { return }
        messageText = text
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
            Task { await startNewChat(onProfileID: nil) }

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
        // J-8: surface the fresh session in the persistent sidebar
        // (compact's drawer refetches on its next open regardless).
        // #190B: forced on BOTH outcomes — the walk-away persist runs inside
        // clearConversation's teardown before the Hermes-side clear can
        // throw, so the session list may have changed even when the clear
        // failed; skipping the refresh left the drawer's snapshot without
        // the departing chat.
        await refreshSessions(force: true)
    }

    /// M-15/M-16: starts a new chat, optionally born on a NAMED backend
    /// profile. nil (and the active profile's id) = plain new chat on the
    /// active backend; a non-active id arms the one-shot birth override —
    /// the first message creates the session there, and `activeProfileID`
    /// never changes.
    private func startNewChat(onProfileID profileID: UUID?) async {
        await performClear()
        guard let profileID,
              profileID != container.profilesStore?.activeProfileID,
              let profile = container.profilesStore?.profile(id: profileID) else {
            container.sessionsChatClient?.pendingNewSessionProfileID = nil
            return
        }
        container.sessionsChatClient?.pendingNewSessionProfileID = profileID
        appendSystemMessage("New chat on \(profile.name) — your first message starts the session there.")
    }

    private func performRetry() async {
        guard let messages = chatStore.conversation?.messages, !messages.isEmpty else {
            appendSystemMessage("No messages to retry.")
            return
        }

        // Find the last user-AUTHORED message. #275: matching `.user` alone
        // skipped a DICTATED turn and retried an earlier typed one, wiping
        // the exchange in between.
        guard let lastUserIdx = messages.lastIndex(where: { $0.sender.isUserAuthored }) else {
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

        // Remove everything from the last user message onward (user msg +
        // assistant response + tool msgs). #78/#274: through the store's one
        // truncation primitive — it persists, syncs the journal, and hands the
        // truncated thread to the backend, without which the post-turn merge
        // puts every removed row straight back.
        chatStore.truncateTranscript(from: lastUserIdx, reason: "/retry")

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

        // Walk backwards to find the last user-AUTHORED message (#275: a
        // dictated turn is one, and skipping it undid the wrong exchange).
        guard let lastUserIdx = messages.lastIndex(where: { $0.sender.isUserAuthored }) else {
            appendSystemMessage("No user message found to undo.")
            return
        }

        let removedContent = messages[lastUserIdx].content

        // Truncate through the store's one primitive (#78/#274). This path
        // never persisted at all before, so `/undo` was undone by a relaunch
        // even when the merge left it alone.
        let removedCount = chatStore.truncateTranscript(from: lastUserIdx, reason: "/undo").count

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

// MARK: - Chrome suppression while the sessions drawer is open

private extension View {
    /// Defect 02: the chat chrome was only ever *deafened* while the drawer
    /// was open — it kept its pixels and read straight through a 0.35 scrim on
    /// a light palette. Pixels and taps now leave together.
    ///
    /// `allowsHitTesting` is not animatable, so it flips at the START of the
    /// transition: nothing is tappable while the chrome is still faintly
    /// visible, which is the ordering that matters.
    func chatChromeSuppressed(_ suppressed: Bool) -> some View {
        self
            .opacity(suppressed ? 0 : 1)
            .allowsHitTesting(!suppressed)
            .animation(Design.Motion.standard, value: suppressed)
    }
}
