import SwiftUI

struct AppRootView: View {
    @Environment(AppContainer.self) private var container
    // The presentation's color scheme. While the adaptive theme (Comic Book)
    // is active the root forces nothing, so this IS the system appearance;
    // mirrored into ThemeRuntime so palette/art-direction resolution can
    // pick the villain/funnies variant live (Lane L Phase 2).
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasSatisfiedMinimumSplashTime = false
    private static let minimumSplashDuration: Duration = .milliseconds(250)

    var body: some View {
        ZStack {
            Group {
                // #31: no pairing wall. First launch lands in a working chat
                // (local brain); Hermes is a Settings-level upgrade
                // (Settings → Connect Hermes Desktop). The permissions
                // onboarding still runs once right after a successful pair —
                // it primes the SENSOR grants, which are Hermes-gated.
                if container.pairingStore.needsPermissionsOnboarding {
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
        // System chrome (keyboard, sheets, toggles, context menus) follows
        // the theme: light for the light environments, dark for the HUD
        // themes — and nil for the adaptive Comic Book, where the SYSTEM
        // appearance drives (Lane L Phase 2).
        .preferredColorScheme(ThemeRuntime.shared.theme.preferredColorScheme)
        .onChange(of: colorScheme, initial: true) { _, scheme in
            ThemeRuntime.shared.systemColorScheme = scheme
        }
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
