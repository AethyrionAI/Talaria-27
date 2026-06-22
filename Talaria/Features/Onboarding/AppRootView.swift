import SwiftUI

struct AppRootView: View {
    @Environment(AppContainer.self) private var container
    @State private var hasSatisfiedMinimumSplashTime = false
    private static let minimumSplashDuration: Duration = .milliseconds(250)

    var body: some View {
        ZStack {
            Group {
                if !container.pairingStore.isPaired {
                    ConnectHermesScreen()
                } else if container.pairingStore.needsPermissionsOnboarding {
                    PermissionsOnboardingScreen()
                } else {
                    MainTabView()
                }
            }

            if shouldShowSplash {
                LaunchSplashView()
                    .transition(.opacity)
            }
        }
        .animation(Design.Motion.standard, value: container.pairingStore.isPaired)
        .animation(Design.Motion.standard, value: container.pairingStore.needsPermissionsOnboarding)
        .animation(Design.Motion.gentle, value: shouldShowSplash)
        .task {
            try? await Task.sleep(for: Self.minimumSplashDuration)
            hasSatisfiedMinimumSplashTime = true
        }
    }

    private var shouldShowSplash: Bool {
        container.shouldShowLaunchSplash || (container.pairingStore.isPaired && !hasSatisfiedMinimumSplashTime)
    }
}

private struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            CornerBrackets(arm: Design.Size.bracket, lineWidth: 1.5, inset: Design.Spacing.md)
                .ignoresSafeArea()

            VStack(spacing: Design.Spacing.md) {
                ReactorOrb(size: Design.Size.orbOnboarding, style: .onboarding)

                Text("TALARIA")
                    .font(Design.Typography.display(25, weight: .bold, relativeTo: .title))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .padding(.top, Design.Spacing.xs)

                MonoLabel("ESTABLISH UPLINK", tracking: Design.Tracking.monoWide)
            }
            .padding(Design.Spacing.xl)
        }
    }
}
