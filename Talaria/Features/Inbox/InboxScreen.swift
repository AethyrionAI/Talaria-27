import SwiftUI

struct InboxScreen: View {
    @Environment(InboxStore.self) private var inboxStore
    @Environment(TabRouter.self) private var router

    var body: some View {
        ZStack {
            HUDScreenBackground(gridIntensity: 0.35)
                .ignoresSafeArea()

            if inboxStore.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle("Inbox")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: - List

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                LazyVStack(spacing: Design.Spacing.sm) {
                    ForEach(inboxStore.items) { item in
                        InboxItemRow(
                            item: item,
                            onPrimaryAction: {
                                Task { await inboxStore.performPrimaryAction(for: item) }
                            },
                            onSecondaryAction: {
                                Task { await inboxStore.dismiss(item) }
                            },
                            onOpenDetails: {
                                // Inbox detail navigation deprecated — no-op
                            }
                        )
                    }
                }
                .padding(.top, Design.Spacing.md)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
        .redacted(reason: inboxStore.isLoading ? .placeholder : [])
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("DIRECTIVES")
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)

            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Brand.forge, diameter: 7, blinks: true)
                MonoLabel(
                    statusLine,
                    size: 11,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.secondaryForeground
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Design.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.cyanHairline)
                .frame(height: 1)
        }
    }

    private var awaitingCount: Int {
        inboxStore.items.filter { $0.isActionable && !$0.isRead }.count
    }

    private var statusLine: String {
        let count = awaitingCount
        let padded = String(format: "%02d", count)
        return "\(padded) AWAITING AUTHORIZATION"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("All Caught Up")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "tray")
                    .foregroundStyle(Design.Brand.accent)
            }
        } description: {
            MonoLabel(
                "NO PENDING DIRECTIVES FROM HERMES",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }
}
