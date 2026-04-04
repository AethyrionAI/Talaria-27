import SwiftUI

struct MainTabView: View {
    @Environment(TabRouter.self) private var router
    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore

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
                Task {
                    await chatStore.injectVoiceTranscript(
                        voiceSessionId: session.voiceSessionId,
                        duration: session.duration
                    )
                    talkStore.clearLastCompletedSession()
                }
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
            ConnectHermesHostScreen()
        }
    }

    @ViewBuilder
    private func sheetDestination(_ destination: SheetDestination) -> some View {
        switch destination {
        case .settings:
            NavigationStack {
                SettingsScreen()
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
