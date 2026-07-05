import SwiftUI
import UIKit

// MARK: - App Icon picker (Settings → Appearance → App Icon, issue #25)
//
// A data-driven grid: it renders whatever `AppIconCatalog.all` lists and scales
// to an arbitrary number of icons (adaptive columns + scroll), so adding an icon
// never touches this view. Tapping a card drives `AppIconStore`, which calls
// `UIApplication.setAlternateIconName`; the choice is persisted by iOS.
struct AppIconSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = AppIconStore()

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 132), spacing: Design.Spacing.md)]
    private let tileSize: CGFloat = 76

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "App Icon", subtitle: "Home Screen") { dismiss() }

                    if !store.supportsAlternateIcons {
                        notice("This device doesn't support changing the app icon.", tone: .muted)
                    }
                    if let error = store.errorMessage {
                        notice(error, tone: .danger)
                    }

                    grid
                    footer
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("App Icon")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear { store.refresh() }
    }

    // MARK: Grid

    private var grid: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Choose Icon", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            LazyVGrid(columns: columns, spacing: Design.Spacing.md) {
                ForEach(AppIconCatalog.all) { iconCard($0) }
            }
            // Scoped to the grid so Back still works when icons are unsupported.
            .disabled(store.isApplying || !store.supportsAlternateIcons)
            .opacity(store.supportsAlternateIcons ? 1 : 0.5)
        }
    }

    private func iconCard(_ option: AppIconOption) -> some View {
        let selected = option.id == store.selection.id
        return Button {
            Task { await store.select(option) }
        } label: {
            VStack(spacing: Design.Spacing.xs) {
                thumbnail(option, selected: selected)
                MonoLabel(option.displayName.uppercased(), size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foreground)
                    .lineLimit(1)
                if let subtitle = option.subtitle {
                    MonoLabel(subtitle.uppercased(), size: 8, weight: .regular,
                              tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func thumbnail(_ option: AppIconOption, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Design.CornerRadius.lg, style: .continuous)
        return preview(option)
            .frame(width: tileSize, height: tileSize)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(selected ? Design.Brand.accent : Design.Colors.hairline,
                                   lineWidth: selected ? 2 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Design.Brand.accent)
                        .background(Circle().fill(Design.Colors.background))
                        .offset(x: 5, y: 5)
                }
            }
            .shadow(color: selected ? Design.Brand.accent.opacity(0.35) : .clear, radius: 8)
    }

    @ViewBuilder
    private func preview(_ option: AppIconOption) -> some View {
        if let image = UIImage(named: option.previewImageName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // No baked preview (e.g. art not yet added) — a neutral placeholder.
            Rectangle()
                .fill(Design.Colors.surface)
                .overlay {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
        }
    }

    // MARK: Notices + footer

    private enum NoticeTone { case muted, danger }

    private func notice(_ text: String, tone: NoticeTone) -> some View {
        let color = tone == .danger ? Design.Colors.danger : Design.Colors.mutedForeground
        return HStack(spacing: Design.Spacing.sm) {
            Image(systemName: tone == .danger ? "exclamationmark.triangle" : "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer(minLength: 0)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: color.opacity(0.4),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private var footer: some View {
        MonoLabel("SELECTION PERSISTS ACROSS RELAUNCH", size: 9, weight: .regular,
                  tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.lg)
    }
}
