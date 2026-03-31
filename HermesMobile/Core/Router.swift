import SwiftUI

// MARK: - Tab Definition

enum AppTab: String, CaseIterable, Identifiable {
    case home
    // Add more tabs as needed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        }
    }
}

// MARK: - Navigation Routes

enum Route: Hashable {
    // Define navigation destinations here
    // case detail(Item)
    // case settings
}

// MARK: - Sheet Destinations

enum SheetDestination: Identifiable {
    // Define sheet presentations here
    // case compose
    // case editProfile

    var id: String {
        switch self {
        default: "default"
        }
    }
}

// MARK: - Tab Router

@MainActor
@Observable
final class TabRouter {
    var selectedTab: AppTab = .home
    private var paths: [AppTab: [Route]] = [:]

    func path(for tab: AppTab) -> [Route] {
        paths[tab, default: []]
    }

    func binding(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.paths[tab, default: []] },
            set: { self.paths[tab] = $0 }
        )
    }

    func navigate(to route: Route, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        paths[target, default: []].append(route)
    }

    func popToRoot(for tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        paths[target] = []
    }

    func resetAll() {
        paths.removeAll()
    }
}
