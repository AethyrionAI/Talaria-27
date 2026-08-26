import SwiftUI

// MARK: - Root layout decision (Lane J, J-8)

/// The root chat surface's layout, decided by horizontal size class ONLY
/// (never device idiom — an iPad window can be iPhone-narrow in Slide Over
/// and must get the compact layout). Pure so the compact-parity property is
/// testable: every non-regular input renders today's iPhone tree.
enum RootLayoutPlan: Equatable {
    case compactStack
    case regularSplit

    static func plan(for sizeClass: UserInterfaceSizeClass?) -> RootLayoutPlan {
        sizeClass == .regular ? .regularSplit : .compactStack
    }
}

/// Lane J (J-9): sidebar visibility persists across launches as a Bool —
/// the pure mapping is extracted so the round trip is testable.
enum SidebarVisibilityPersistence {
    static func visibility(fromPersisted visible: Bool) -> NavigationSplitViewVisibility {
        visible ? .all : .detailOnly
    }

    static func persisted(from visibility: NavigationSplitViewVisibility) -> Bool {
        visibility != .detailOnly
    }
}

struct MainTabView: View {
    @Environment(AppContainer.self) private var container
    @Environment(TabRouter.self) private var router
    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Lane J (J-9): chat state that must survive the compact↔regular
    // boundary. The two root branches are different view trees, so a
    // size-class change (Stage Manager drag) recreates ChatScreen — anything
    // that must not reset lives HERE (MainTabView keeps its identity across
    // the transition) and is passed down.
    @State private var composerText = ""
    @State private var composerAttachments: [PendingAttachment] = []
    @State private var sessionsModel = SessionsDrawerModel()
    /// #18: the sessions drawer is hosted HERE, not inside ChatScreen — see
    /// `compactStack`. Crossing into regular width therefore stops rendering
    /// it structurally, which is what the old `onChange(horizontalSizeClass)`
    /// reset inside ChatScreen was emulating.
    @State private var sessionsOpen = false

    // Lane J (J-9): sidebar visibility, persisted across launches.
    @AppStorage("chatSidebarVisible") private var sidebarVisiblePersisted = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            switch RootLayoutPlan.plan(for: horizontalSizeClass) {
            case .compactStack:
                compactStack
            case .regularSplit:
                regularSplit
            }
        }
        .onChange(of: talkStore.lastCompletedSession != nil) { _, hasSession in
            if hasSession, let session = talkStore.lastCompletedSession {
                // Composed locally from the captured transcript (#1) — never
                // touches the relay, so it works with the host unreachable.
                // Native-engine sessions (#18) skip the context turn: every
                // utterance already rode the chat backend as a real turn, so
                // posting the transcript again would duplicate context.
                chatStore.appendVoiceTranscript(
                    session,
                    postToHermes: settingsStore.settings.postVoiceTranscriptsToHermes
                        && session.engine == .realtime
                )
                talkStore.clearLastCompletedSession()
            }
        }
    }

    // MARK: Compact (today's iPhone tree, untouched — J-8 parity bar)

    private var compactStack: some View {
        @Bindable var router = router
        return ZStack {
            NavigationStack(path: router.pathBinding()) {
                ChatScreen(
                    messageText: $composerText,
                    pendingAttachments: $composerAttachments,
                    sessionsModel: sessionsModel,
                    sessionsOpen: $sessionsOpen
                )
                .navigationDestination(for: Route.self) { route in
                    routeDestination(route)
                }
            }
            .sheet(item: $router.activeSheet) { destination in
                sheetDestination(destination)
            }
            .fullScreenCover(isPresented: $router.isVoiceOverlayPresented) {
                VoiceOverlayScreen()
            }

            // #18's root cause, fixed at the layer instead of the alpha: the
            // navigation toolbar composites ABOVE `.overlay` content, so a
            // drawer hosted inside ChatScreen could never cover it. Fading the
            // items left the system's own bar layer drawing over the panel and
            // its header. Hiding the whole bar worked, but dropped its height
            // from the safe area and slid the chat up ~57pt behind the panel —
            // visible in the peek sliver, and a jump on close.
            //
            // As a SIBLING of the whole NavigationStack the drawer is simply
            // above it, nothing reflows, and it inherits the window's real
            // safe area — which is what "the panel owns its own safe-area
            // inset" was asking for all along.
            if sessionsOpen {
                SessionsDrawer(
                    isPresented: $sessionsOpen,
                    model: sessionsModel,
                    hostName: hostStore.currentHost?.resolvedDisplayName ?? "HERMES HOST",
                    hostDetail: ChatConnectionPresentation.sessionsHostDetail(chatConnectionState),
                    hostOnline: chatConnectionState == .online
                )
            }
        }
        // Animate the outer conditional so the panel's transitions play on
        // close too — closes were previously torn down unanimated, so the
        // panel popped instead of sliding (#42).
        .animation(Design.Motion.standard, value: sessionsOpen)
    }

    // MARK: Regular (Lane J split view — J-8/J-9)

    private var regularSplit: some View {
        @Bindable var router = router
        return ZStack {
            // J-9: ONE theme atmosphere spanning the whole window, behind
            // both columns — ChatScreen suppresses its per-screen copy here.
            HUDScreenBackground()
                .ignoresSafeArea()
            ScanLine(intensity: 0.32)
                .ignoresSafeArea()

            NavigationSplitView(columnVisibility: $columnVisibility) {
                ConversationListPane(
                    model: sessionsModel,
                    hostName: hostStore.currentHost?.resolvedDisplayName ?? "HERMES HOST",
                    hostDetail: ChatConnectionPresentation.sessionsHostDetail(chatConnectionState),
                    hostOnline: chatConnectionState == .online,
                    // §7: in a column there is nothing to dismiss — the pane's
                    // ✕ becomes the sidebar toggle. Deliberately NOT
                    // `dismissHost`, which also fires on every row tap.
                    collapseHost: { columnVisibility = .detailOnly },
                    // §7: 2b becomes 2a here — the SAME VStack, dock on top.
                    // Stated rather than derived: a split-view column is free
                    // to report `.compact` and would flip the layout back.
                    actionAnchor: .top
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
                .toolbarBackground(.hidden, for: .navigationBar)
                // J-9: the column must not paint a system background over
                // the window-spanning atmosphere. Compile-risk flagged in
                // the PR — if this placement doesn't exist on this SDK,
                // delete and revisit column transparency on the Mac.
                .containerBackground(.clear, for: .navigation)
            } detail: {
                NavigationStack(path: router.pathBinding()) {
                    ChatScreen(
                        messageText: $composerText,
                        pendingAttachments: $composerAttachments,
                        sessionsModel: sessionsModel,
                        showsAtmosphere: false,
                        onConversationSearchShortcut: {
                            // ⌘K in regular: reveal the sidebar if hidden and
                            // focus its inline filter field directly (J-9).
                            columnVisibility = .all
                            sessionsModel.requestSearchFieldFocus()
                        }
                    )
                    .navigationDestination(for: Route.self) { route in
                        routeDestination(route)
                    }
                    // J-9: same transparency requirement as the sidebar column.
                    .containerBackground(.clear, for: .navigation)
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
        .sheet(item: $router.activeSheet) { destination in
            sheetDestination(destination)
        }
        .fullScreenCover(isPresented: $router.isVoiceOverlayPresented) {
            VoiceOverlayScreen()
        }
        .onAppear {
            columnVisibility = SidebarVisibilityPersistence.visibility(fromPersisted: sidebarVisiblePersisted)
        }
        .onChange(of: columnVisibility) { _, visibility in
            sidebarVisiblePersisted = SidebarVisibilityPersistence.persisted(from: visibility)
        }
    }

    /// Chat-path connection state for the sidebar footer — the same one
    /// derivation ChatScreen uses (never the relay-sourced state).
    ///
    /// #264 half 2: this is the FIFTH site of that signal and the one the
    /// 08-09 inventory missed, because it is not spelled
    /// `effectiveConnectionState` and a grep for that name cannot see it.
    private var chatConnectionState: HermesHostConnectionState {
        ConnectionSignal.chatState(direct: chatStore.directConnectionStatus)
    }

    @ViewBuilder
    private func routeDestination(_ route: Route) -> some View {
        switch route {
        case .permissions:
            PermissionsScreen()
        case .capture:
            CaptureScreen()
        case .connectHost(let profileID):
            // **#309 Lane B: the wizard is ENTERED, never imposed.** This is
            // its ONLY presentation site, and it is reached only by an
            // explicit tap — Settings' Connect Host row, the Server screen's
            // per-profile row, the chat header's connect affordance. There is
            // no launch-time branch anywhere that lands here (bar 309-B1).
            //
            // An install with no host yet gets the WIZARD; one that already
            // has credentials gets the manual screen, which is the
            // always-available path. Same model behind both.
            //
            // #127: this seam is still the one gated connect entry point.
            // Only a NEW connect can hit the paywall — re-opening a host you
            // already have is never severed. Dormant until the #127 flag flips.
            if container.connectGateVerdict(for: connectAttempt(for: profileID)) == .showPaywall {
                ConnectedPaywallView()
            } else if hasHost(profileID) {
                ConnectHostScreen(target: connectTarget(for: profileID))
            } else {
                ConnectHostWizard(target: connectTarget(for: profileID))
            }
        case .inbox:
            InboxScreen()
        case .briefing(let item):
            BriefingDetailScreen(item: item)
        case .tasks:
            TasksScreen()
        case .taskDetail(let jobID):
            TaskDetailScreen(jobID: jobID)
        case .skills:
            SkillsScreen()
        case .insights:
            InsightsScreen()
        }
    }

    /// #127: classify what the connect flow would do. A profile that ALREADY
    /// has a working host is an existing connection (fail open); everything
    /// else reaching the flow is a new connect.
    ///
    /// **#309 Lane C re-homed the predicate; Lane B moved the TARGET off a
    /// store field and onto the route.** It used to ask
    /// `ProfileRelaySessionFactory.isPaired` — "does this profile hold a
    /// relay-era pairing record?" — which the retirement made permanently true
    /// for every profile that ever paired (the record persists its own relay
    /// URL and nothing clears it) and permanently false for a gateway-only
    /// one. Both answers were wrong for #127's question, which is whether the
    /// user already has this host set up.
    private func connectAttempt(for profileID: UUID?) -> ConnectAttempt {
        hasHost(profileID) ? .existingPairing : .newConnect
    }

    /// Whether the named profile (or the active one) already holds a host this
    /// app could route a turn to. The same predicate the whole app uses — not
    /// a sibling of it.
    private func hasHost(_ profileID: UUID?) -> Bool {
        guard let id = profileID ?? container.profilesStore?.activeProfileID else { return false }
        return container.hasGatewayCredentials(forProfileID: id)
    }

    private func connectTarget(for profileID: UUID?) -> ConnectHostTarget {
        guard let profileID else { return .activeProfile }
        return .profile(profileID)
    }

    @ViewBuilder
    private func sheetDestination(_ destination: SheetDestination) -> some View {
        switch destination {
        case .settings:
            NavigationStack {
                // #252: Subsystem Channels root (1c). SystemSettingsScreen retired (Task 8).
                SettingsChannelsScreen()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case .settingsModels:
            NavigationStack {
                ModelsSettingsScreen()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case .attachments:
            EmptyView()
        case .newChat:
            EmptyView()
        }
    }
}
