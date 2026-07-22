import SwiftUI

// MARK: - Navigation Routes

enum Route: Hashable {
    case permissions
    case capture
    case connectHost
    /// #45: the agent→phone Inbox — first reachable entry point (the screen
    /// shipped in every build with zero call sites).
    case inbox
    /// #126: briefing detail. `nil` = latest briefing (widget deep link);
    /// a value = the row the user tapped.
    case briefing(InboxItem?)
    /// #156a: the agent's scheduled cron jobs.
    case tasks
    /// #156a: task detail carries only the job id — both screens read the
    /// same CronJobsStore row, so they can never disagree.
    case taskDetail(String)
}

// MARK: - Sheet Destinations

enum SheetDestination: Identifiable {
    case settings
    case settingsModels
    case attachments
    case newChat

    var id: String {
        switch self {
        case .settings: "settings"
        case .settingsModels: "settingsModels"
        case .attachments: "attachments"
        case .newChat: "newChat"
        }
    }
}

// MARK: - App Tab (kept for backward compatibility during transition)

enum AppTab: String, CaseIterable, Identifiable {
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Chat"
        }
    }

    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Router

@MainActor
@Observable
final class TabRouter {
    var selectedTab: AppTab = .chat
    var activeSheet: SheetDestination?
    var isVoiceOverlayPresented = false
    private var navigationPath: [Route] = []

    func path() -> [Route] {
        navigationPath
    }

    func binding(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.navigationPath },
            set: { self.navigationPath = $0 }
        )
    }

    func pathBinding() -> Binding<[Route]> {
        Binding(
            get: { self.navigationPath },
            set: { self.navigationPath = $0 }
        )
    }

    func navigate(to route: Route, in tab: AppTab? = nil) {
        navigationPath.append(route)
    }

    func popToRoot(for tab: AppTab? = nil) {
        navigationPath = []
    }

    func resetAll() {
        navigationPath.removeAll()
    }

    func presentSheet(_ sheet: SheetDestination) {
        activeSheet = sheet
    }

    func dismissSheet() {
        activeSheet = nil
    }
}
