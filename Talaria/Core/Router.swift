import SwiftUI

// MARK: - Navigation Routes

enum Route: Hashable {
    case permissions
    case capture
    /// #309 Lane B: the Connect Host seam. The associated value is the profile
    /// the flow is about — `nil` means the ACTIVE profile, which is every
    /// entry point except the Server screen's per-profile row.
    ///
    /// It used to be a bare case, with the target smuggled through
    /// `PairingStore.pairingTargetProfileID` — a mutable store field set
    /// before navigating and cleared on the way out, which meant the
    /// destination depended on state a screen had to remember to reset. The
    /// route carries it now, so a stale target cannot exist.
    case connectHost(UUID?)
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
    /// #156b: read-only browser over the agent's installed skills.
    case skills
    /// #156d: read-only usage/cost panel over the agent's sessions.
    case insights
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
