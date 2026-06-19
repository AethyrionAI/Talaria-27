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
    @State private var animateGlyph = false

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            Circle()
                .fill(Design.Brand.accent.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 48)
                .scaleEffect(animateGlyph ? 1.06 : 0.94)

            VStack(spacing: Design.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(Design.Colors.surface)
                        .frame(width: 108, height: 108)
                    Circle()
                        .stroke(Design.Brand.accent.opacity(0.35), lineWidth: 1)
                        .frame(width: 108, height: 108)

                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Design.Brand.accentGradient)
                        .scaleEffect(animateGlyph ? 1.04 : 0.96)
                }

                VStack(spacing: Design.Spacing.xs) {
                    Text("Hermes")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Design.Colors.foreground)

                    Text("Mobile companion")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }

                ProgressView()
                    .tint(Design.Brand.accent)
                    .controlSize(.small)
            }
            .padding(Design.Spacing.xl)
        }
        .task {
            withAnimation(Design.Motion.breathe) {
                animateGlyph = true
            }
        }
    }
}
