import SwiftUI
import UIKit

// MARK: - App lock cover window (#124)
//
// Snapshot-obscuring approach, stated per the dispatch: a scenePhase-driven
// opaque overlay (the sanctioned simpler option) — but hosted in a DEDICATED
// UIWindow at level .alert + 1 rather than the root view hierarchy. Why:
// sheets, alerts, and fullScreenCovers present in UIKit layers ABOVE the
// window's root SwiftUI view, so a root-ZStack overlay would leave an open
// sheet readable on top of the "lock" — and the app-switcher snapshot has
// the same hole. One topmost window covers every presentation layer, serves
// as both the lock UI and the snapshot obscurer, and needs no legacy
// UIApplication snapshot API (SwiftUI lifecycle friendly).

@MainActor
final class AppLockWindowPresenter {
    private var window: UIWindow?
    private weak var controller: AppLockController?

    func attach(controller: AppLockController) {
        self.controller = controller
        controller.onCoverChanged = { [weak self] cover in
            self?.update(cover: cover)
        }
        update(cover: controller.cover)
    }

    private func update(cover: AppLockCover) {
        cover == .none ? hide() : show()
    }

    private func show() {
        guard let controller else { return }
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.role == .windowApplication }) else { return }
            let host = UIHostingController(
                rootView: AppLockOverlayView(controller: controller)
                    .environment(ThemeRuntime.shared)
            )
            host.view.backgroundColor = .clear
            let overlay = UIWindow(windowScene: scene)
            overlay.rootViewController = host
            overlay.windowLevel = .alert + 1
            window = overlay
        }
        // Kill any active keyboard: its window floats above even .alert level.
        window?.windowScene?.keyWindow?.endEditing(true)
        window?.isHidden = false
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// Both cover faces: `.obscured` renders the splash-alike privacy shield
/// (this is what the app-switcher snapshot captures); `.locked` adds the
/// LOCKED badge and — after a failed/cancelled attempt — the retry button.
/// There is deliberately no other control: the only ways past this view are
/// biometry or the system sheet's passcode fallback.
struct AppLockOverlayView: View {
    @Bindable var controller: AppLockController

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: Design.Spacing.md) {
                ReactorOrb(size: Design.Size.orbOnboarding, style: .onboarding)

                Text("TALARIA")
                    .font(Design.Typography.display(25, weight: .bold, relativeTo: .title))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .padding(.top, Design.Spacing.xs)

                if controller.cover == .locked {
                    MonoLabel("LOCKED", tracking: Design.Tracking.monoWide)

                    if controller.didFailAuthentication {
                        GlowButton(title: "UNLOCK") {
                            Task { await controller.requestUnlock() }
                        }
                        .padding(.top, Design.Spacing.md)
                        .padding(.horizontal, Design.Spacing.xl)
                    }
                }
            }
            .padding(Design.Spacing.xl)
        }
    }
}

extension AppLockScenePhase {
    /// Mapping lives here (not in AppLockCore) to keep the core SwiftUI-free.
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        case .inactive: self = .inactive
        @unknown default: self = .inactive
        }
    }
}
