import SwiftUI

/// What tapping an Inbox row does. Extracted from the view so the one
/// non-obvious rule is pinned by a test instead of by a comment.
///
/// #126: briefings open their detail screen, which marks them read there.
/// #251-2A: everything else USED to be a no-op — platform items are plain
/// notifications with no detail screen and no action buttons, so nothing on
/// the row could ever reach `markRead` and the unread pip stuck forever.
///
/// Actionable rows stay a no-op deliberately: `markRead` moves `.pending` →
/// `.opened` and then recomputes `isActionable` from that status, so marking
/// one read on tap would silently strip its Approve / Dismiss buttons.
enum InboxRowTapAction: Equatable {
    case openBriefing
    case markRead
    /// Named `ignore` rather than `none` on purpose — a `.none` case shadows
    /// `Optional.none` at every comparison site.
    case ignore

    static func resolve(for item: InboxItem) -> InboxRowTapAction {
        if item.isBriefing { return .openBriefing }
        return item.isActionable ? .ignore : .markRead
    }
}

struct InboxScreen: View {
    @Environment(InboxStore.self) private var inboxStore
    @Environment(TabRouter.self) private var router
    /// #354: clear-all is real deletion of the only copy — it fires only
    /// through the alert below.
    @State private var confirmingClearAll = false

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if inboxStore.items.isEmpty {
                // Scrollable so pull-to-refresh works from the empty and
                // unreachable states too, not just the list.
                ScrollView {
                    Group {
                        if inboxStore.lastErrorMessage != nil {
                            unreachableState
                        } else {
                            emptyState
                        }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            } else {
                itemList
            }
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        // #45: reachable by navigation push now — the nav bar must stay
        // visible for the back affordance (the hidden-toolbar treatment
        // predated any call site).
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // #354: bulk prune, offered only while something is deletable.
            if inboxStore.items.contains(where: { inboxStore.canDelete($0) }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { confirmingClearAll = true }
                        .font(Design.Typography.mono(12, weight: .medium))
                        .tint(Design.Colors.danger)
                        .accessibilityLabel("Clear all inbox items")
                }
            }
        }
        // #193: an alert, not a confirmationDialog — the dialog's cancel role
        // does not render on iOS 26/27, and a destructive gate needs a
        // visible decline.
        .alert("Clear all inbox items?", isPresented: $confirmingClearAll) {
            Button("Clear All", role: .destructive) { inboxStore.clearAllInboxItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Agent messages exist only on this device — the server copy was dropped on delivery. This cannot be undone.")
        }
        .task { await inboxStore.loadInbox(force: true) }
        .refreshable { await inboxStore.loadInbox(force: true) }
    }

    // MARK: - List

    // #354: a `List` (not the ScrollView it replaced) because swipe-to-delete
    // rides `.swipeActions` — the SessionsDrawer precedent. All chrome is
    // stripped (clear backgrounds, hidden separators) so the rows keep their
    // own hudPanel cards.
    private var itemList: some View {
        List {
            header
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: Design.Spacing.sm, leading: Design.Spacing.md,
                    bottom: Design.Spacing.md, trailing: Design.Spacing.md))

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
                        switch InboxRowTapAction.resolve(for: item) {
                        case .openBriefing:
                            router.navigate(to: .briefing(item))
                        case .markRead:
                            inboxStore.markRead(item)
                        case .ignore:
                            break
                        }
                    }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: Design.Spacing.sm / 2, leading: Design.Spacing.md,
                    bottom: Design.Spacing.sm / 2, trailing: Design.Spacing.md))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // #354: only owned rows (platform + local copies) offer
                    // delete; relay rows keep their dismiss lifecycle.
                    if inboxStore.canDelete(item) {
                        Button(role: .destructive) {
                            inboxStore.delete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
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
                .fill(Design.Colors.hairline)
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

    // MARK: - Unreachable State (#45)

    /// The fetch failed — say so. Real data only: an unreachable relay must
    /// never read as "All Caught Up" (and never show demo items).
    private var unreachableState: some View {
        ContentUnavailableView {
            Label {
                Text("Inbox Unreachable")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(Design.Brand.forge)
            }
        } description: {
            MonoLabel(
                "COULD NOT REACH THE RELAY — PULL TO RETRY",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
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
