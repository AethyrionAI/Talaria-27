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
    @Environment(PairingStore.self) private var pairingStore
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
        return NavigationStack(path: router.pathBinding()) {
            ChatScreen(
                messageText: $composerText,
                pendingAttachments: $composerAttachments,
                sessionsModel: sessionsModel
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
                    hostOnline: chatConnectionState == .online
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

    /// Chat-path connection state for the sidebar footer — the same direct
    /// Sessions-API mapping ChatScreen uses (never the relay-sourced state).
    private var chatConnectionState: HermesHostConnectionState {
        ChatConnectionPresentation.effectiveState(chatStore.directConnectionStatus)
    }

    @ViewBuilder
    private func routeDestination(_ route: Route) -> some View {
        switch route {
        case .permissions:
            PermissionsScreen()
        case .capture:
            CaptureScreen()
        case .connectHost:
            // #31: the pairing flow's new home. Unpaired → the full pairing
            // screen (relocated from the removed launch wall); paired → the
            // host status/management screen as before.
            // Lane M (M-12): a per-profile Pair action names its target
            // before navigating here — that always means the pairing flow,
            // even while the ACTIVE profile happens to be paired.
            // #127: the pairing-flow branch is a gated connect entry point —
            // this one seam covers every navigate(.connectHost) call site.
            // Only a NEW connect can hit the paywall (re-pairing an
            // already-paired profile is an existing pairing and always
            // passes); the management screen below stays ungated so a live
            // pairing is never severed. Dormant until the #127 flag flips.
            if pairingStore.pairingTargetProfileID != nil || !pairingStore.isPaired {
                if container.connectGateVerdict(for: pairingFlowAttempt) == .showPaywall {
                    ConnectedPaywallView()
                } else {
                    ConnectHermesScreen()
                }
            } else {
                ConnectHermesHostScreen()
            }
        case .inbox:
            InboxScreen()
        }
    }

    /// #127: classify what the pairing flow would do. A named pair target
    /// that is already paired is a re-pair of an existing pairing (fail
    /// open); everything else reaching the flow is a new connect.
    private var pairingFlowAttempt: ConnectAttempt {
        if let targetID = pairingStore.pairingTargetProfileID,
           container.profileRelaySessions?.isPaired(profileID: targetID) == true {
            return .existingPairing
        }
        return .newConnect
    }

    @ViewBuilder
    private func sheetDestination(_ destination: SheetDestination) -> some View {
        switch destination {
        case .settings:
            NavigationStack {
                // Settings entry: the SYSTEM index (the legacy monolith was removed in T3).
                SystemSettingsScreen()
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
