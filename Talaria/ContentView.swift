import SwiftUI

struct MainTabView: View {
    @Environment(TabRouter.self) private var router
    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(PairingStore.self) private var pairingStore

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: router.pathBinding()) {
            ChatScreen()
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
        .onChange(of: talkStore.lastCompletedSession != nil) { _, hasSession in
            if hasSession, let session = talkStore.lastCompletedSession {
                // Composed locally from the captured transcript (#1) — never
                // touches the relay, so it works with the host unreachable.
                chatStore.appendVoiceTranscript(
                    session,
                    postToHermes: settingsStore.settings.postVoiceTranscriptsToHermes
                )
                talkStore.clearLastCompletedSession()
            }
        }
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
            if pairingStore.isPaired {
                ConnectHermesHostScreen()
            } else {
                ConnectHermesScreen()
            }
        }
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
