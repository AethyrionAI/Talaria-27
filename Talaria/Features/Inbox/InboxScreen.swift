import SwiftUI

struct InboxScreen: View {
    @Environment(InboxStore.self) private var inboxStore
    @Environment(TabRouter.self) private var router

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            if inboxStore.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle("Inbox")
        .toolbar { toolbarContent }
    }

    // MARK: - List

    private var itemList: some View {
        ScrollView {
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
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
        .redacted(reason: inboxStore.isLoading ? .placeholder : [])
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "All Caught Up",
            systemImage: "tray",
            description: Text("No new items from Hermes. Check back later.")
                .foregroundStyle(Design.Colors.secondaryForeground)
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if inboxStore.unreadCount > 0 {
                Text("\(inboxStore.unreadCount) new")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }
}
