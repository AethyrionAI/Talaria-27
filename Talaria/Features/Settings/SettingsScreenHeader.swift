import SwiftUI

// MARK: - Settings sub-screen header
//
// Shared HUD header for the Settings drill-down screens (UPLINK, APPEARANCE,
// SESSIONS, DIAGNOSTICS), per design/Settings.dc.html: a glass back-chevron
// followed by a left-aligned Chakra title with a JetBrains-Mono subtitle.
//
// `onBack` pops the NavigationStack via the caller's `@Environment(\.dismiss)`.
// At the stack root (the SYSTEM index) dismiss closes the Settings sheet instead,
// so the index uses its own xmark header rather than this one.
struct SettingsScreenHeader: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            GlassCircleButton(icon: "chevron.left", accessibilityLabel: "Back", action: onBack)

            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(title.uppercased())
                    .font(Design.Typography.screenTitle2)
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    // Neon title treatment where the theme curates one
                    // (ThemeArtDirection.titleGlow) — inert everywhere else.
                    .hudTitleGlow()

                MonoLabel(
                    subtitle,
                    size: 10,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.mutedForeground
                )
            }

            Spacer(minLength: Design.Spacing.xs)
        }
        .padding(.top, Design.Spacing.xs)
    }
}
