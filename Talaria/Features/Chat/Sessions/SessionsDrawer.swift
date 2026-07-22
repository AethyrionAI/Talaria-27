import SwiftUI

// MARK: - Sessions drawer (UI shell)
//
// Left slide-in panel listing chat sessions, per the "02 UPLINK · CHAT" design.
// This is a presentation shell with a clean wiring seam: all data lives in
// `SessionsDrawerModel` behind `// TODO: wire to Sessions API`, and user actions
// surface through callbacks. No backend integration here.

// MARK: View model (wiring seam)

@MainActor
@Observable
final class SessionsDrawerModel {

    enum Group: String, CaseIterable, Identifiable {
        case pinned = "PINNED"
        case today = "TODAY"
        case yesterday = "YESTERDAY"
        case earlier = "EARLIER"
        case archived = "ARCHIVED"
        var id: String { rawValue }
    }

    struct SessionSummary: Identifiable, Hashable {
        let id: String
        var title: String
        var subtitle: String
        var timeLabel: String
        var group: Group
        var isActive: Bool = false
        var isPinned: Bool = false
        /// Optional mono badge, e.g. "AUTO · DAILY".
        var badge: String? = nil
    }

    // Wired to Hermes Sessions API — ChatScreen.refreshSessions() populates
    // this from chatStore.loadSessions() on drawer open and on initial load.
    var sessions: [SessionSummary] = []

    var searchText: String = ""

    /// #97: the Archived filter — on, the list shows ONLY archived rows.
    var showingArchived = false

    /// #97: pin/archive overlay for server-session rows, wired by the drawer
    /// view from AppContainer (this shell owns no stores of its own). Nil
    /// until first drawer open — the list renders un-overlaid, exactly the
    /// pre-#97 drawer.
    var listState: ConversationListStateStore? = nil

    /// #97: the conversation journal, wired from ChatStore — lets pin/archive
    /// on the row carrying the current conversation's hop mirror onto the
    /// journal's durable flags.
    var journal: ConversationJournalStore? = nil

    /// Header telemetry, e.g. "14 THREADS · 2 ACTIVE".
    var headerStat: String {
        let active = sessions.filter(\.isActive).count
        return "\(sessions.count) THREADS · \(active) ACTIVE"
    }

    /// Lane M (M-16): one entry per backend profile for the New Chat
    /// context menu — "fire a task at the Mac without leaving OJAMD-land".
    struct NewChatProfileOption: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    /// Populated by the host screen when profiles exist; the context menu
    /// only renders with two or more (a single backend has nothing to pick).
    var newChatProfiles: [NewChatProfileOption] = []
    /// The active profile's id, so the menu can mark the default target.
    var activeNewChatProfileID: UUID? = nil

    // Wiring seams — the host screen connects these to real behavior later.
    var onNewChat: (() -> Void)? = nil
    /// Lane M (M-16): new chat born on a NAMED profile, without flipping the
    /// app-wide default.
    var onNewChatOnProfile: ((UUID) -> Void)? = nil
    var onSelectSession: ((SessionSummary) -> Void)? = nil
    var onOpenHostSettings: (() -> Void)? = nil
    /// Lane J (J-8): asks the host screen to re-fetch the session list. The
    /// drawer refreshes on every open (ChatScreen's onChange); the persistent
    /// split-view sidebar uses this seam on mount instead.
    var onRefreshRequest: (() -> Void)? = nil

    /// Sessions filtered by `searchText` and the pin/archive overlay (#97),
    /// grouped and ordered for display.
    func grouped() -> [(group: Group, items: [SessionSummary])] {
        Self.grouped(
            sessions: sessions,
            query: searchText,
            pinnedIDs: listState?.state.pinnedSessionIDs ?? [],
            archivedIDs: listState?.state.archivedSessionIDs ?? [],
            showingArchived: showingArchived
        )
    }

    /// The drawer's data-source rule, pure so tests can drive it directly:
    /// query filter (case/diacritic-insensitive, title + subtitle), then the
    /// overlay — pinned rows float to the PINNED section regardless of their
    /// recency group, with NO pin cap (ChatGPT caps at 3; we deliberately
    /// don't); archived rows are hidden from the main list and shown alone
    /// when `showingArchived` is on. Order within a section is the fetch
    /// order (recency), untouched.
    static func grouped(
        sessions: [SessionSummary],
        query: String,
        pinnedIDs: Set<String>,
        archivedIDs: Set<String>,
        showingArchived: Bool
    ) -> [(group: Group, items: [SessionSummary])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? sessions
            : sessions.filter {
                $0.title.localizedStandardContains(trimmed)
                    || $0.subtitle.localizedStandardContains(trimmed)
            }

        if showingArchived {
            let archived = filtered
                .filter { archivedIDs.contains($0.id) }
                .map { row in
                    var adjusted = row
                    adjusted.group = .archived
                    adjusted.isPinned = adjusted.isPinned || pinnedIDs.contains(row.id)
                    return adjusted
                }
            return archived.isEmpty ? [] : [(.archived, archived)]
        }

        var pinned: [SessionSummary] = []
        var unpinned: [SessionSummary] = []
        for row in filtered where !archivedIDs.contains(row.id) {
            if row.isPinned || pinnedIDs.contains(row.id) {
                var adjusted = row
                adjusted.isPinned = true
                adjusted.group = .pinned
                pinned.append(adjusted)
            } else {
                unpinned.append(row)
            }
        }

        var result: [(group: Group, items: [SessionSummary])] = []
        if !pinned.isEmpty { result.append((.pinned, pinned)) }
        for group in [Group.today, .yesterday, .earlier] {
            let items = unpinned.filter { $0.group == group }
            if !items.isEmpty { result.append((group, items)) }
        }
        return result
    }

    /// Overlay-aware pin state (placeholder rows may carry their own flag).
    func isPinned(_ summary: SessionSummary) -> Bool {
        summary.isPinned || (listState?.isPinned(summary.id) ?? false)
    }

    func isArchived(_ summary: SessionSummary) -> Bool {
        listState?.isArchived(summary.id) ?? false
    }

    /// Archived rows among the CURRENTLY FETCHED sessions — stale overlay ids
    /// (sessions the host no longer returns) don't count.
    var archivedCount: Int {
        guard let listState else { return 0 }
        return sessions.filter { listState.isArchived($0.id) }.count
    }

    func togglePin(_ summary: SessionSummary) {
        guard let listState else { return }
        // Toggle off the DISPLAYED state (row flag OR overlay), so the action
        // always inverts what the user sees.
        listState.setPinned(!isPinned(summary), sessionID: summary.id)
        mirrorFlagsToJournalIfCurrent(summary.id)
    }

    func toggleArchive(_ summary: SessionSummary) {
        guard let listState else { return }
        listState.toggleArchived(sessionID: summary.id)
        mirrorFlagsToJournalIfCurrent(summary.id)
        // Un-archiving the last row leaves an empty filter view — fall back
        // to the main list rather than stranding the user on nothing.
        if showingArchived && archivedCount == 0 {
            showingArchived = false
        }
    }

    /// #97: the row carrying the current conversation's active hop IS the
    /// local conversation — mirror its overlay flags onto the journal, whose
    /// copy rides the durable conversation identity (session ids are
    /// ephemeral per-hop handles, #93).
    private func mirrorFlagsToJournalIfCurrent(_ sessionID: String) {
        guard let listState, let journal,
              journal.activeHop?.apiSessionId == sessionID else { return }
        journal.setPinned(listState.isPinned(sessionID))
        journal.setArchived(listState.isArchived(sessionID))
    }

    func selectSession(_ summary: SessionSummary) {
        onSelectSession?(summary)
    }

    func newChat() {
        onNewChat?()
    }

    /// M-16: new chat targeting a named profile.
    func newChat(onProfile profileID: UUID) {
        onNewChatOnProfile?(profileID)
    }

    /// Lane J (J-9): ⌘K in regular width focuses the visible pane's inline
    /// filter field. Request/consume semantics (not a toggle) so a request
    /// made while the sidebar is hidden is honored once on mount and a stale
    /// flag can never steal focus later.
    private(set) var searchFieldFocusRequested = false

    func requestSearchFieldFocus() {
        searchFieldFocusRequested = true
    }

    func consumeSearchFieldFocusRequest() -> Bool {
        defer { searchFieldFocusRequested = false }
        return searchFieldFocusRequested
    }

    static let placeholders: [SessionSummary] = [
        SessionSummary(id: "pin-briefing", title: "Morning Briefing",
                       subtitle: "Daily digest · weather, calendar, inbox",
                       timeLabel: "7:00", group: .pinned, isPinned: true, badge: "AUTO · DAILY"),
        SessionSummary(id: "today-resched", title: "Reschedule afternoon",
                       subtitle: "4 events moved · note to Sarah queued",
                       timeLabel: "09:41", group: .today, isActive: true),
        SessionSummary(id: "today-invoice", title: "Invoice triage",
                       subtitle: "3 approved · 1 flagged for review",
                       timeLabel: "08:12", group: .today),
        SessionSummary(id: "yday-tokyo", title: "Tokyo trip planning",
                       subtitle: "Flights + hotel shortlisted",
                       timeLabel: "Tue", group: .yesterday),
        SessionSummary(id: "yday-review", title: "Codebase review",
                       subtitle: "12 files · 3 diffs proposed",
                       timeLabel: "Tue", group: .yesterday),
    ]
}

// MARK: Drawer view

struct SessionsDrawer: View {
    @Binding var isPresented: Bool
    var model: SessionsDrawerModel
    /// Footer host status line (driven by the host screen).
    var hostName: String = "HERMES HOST"
    var hostDetail: String = "LINKED"
    var hostOnline: Bool = true

    private let panelWidth: CGFloat = 320

    var body: some View {
        ZStack(alignment: .leading) {
            if isPresented {
                backdrop
                    .transition(.opacity)
                panel
                    .frame(width: panelWidth)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(Design.Motion.standard, value: isPresented)
        .ignoresSafeArea()
        .onAppear {
            // The Archived filter is a transient view — every drawer open
            // starts on the main list. (Drawer-only semantics: the split-view
            // sidebar is persistent and keeps its filter state.)
            model.showingArchived = false
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        Design.Colors.scrim
            .contentShape(Rectangle())
            .onTapGesture { isPresented = false }
            .accessibilityLabel("Close sessions")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Panel

    private var panel: some View {
        // Lane J (J-8): the list surface is the shared ConversationListPane —
        // the SAME component the split-view sidebar embeds (extracted, not
        // forked). Only the slide-in chrome (width, gradient, edge highlight,
        // backdrop, dismissal) is drawer-specific.
        ConversationListPane(
            model: model,
            hostName: hostName,
            hostDetail: hostDetail,
            hostOnline: hostOnline,
            dismissHost: { isPresented = false }
        )
        .background(drawerBackground)
        .overlay(alignment: .leading) {
            // Bright cyan edge highlight.
            LinearGradient(
                colors: [.clear, Design.Brand.accent.opacity(0.5), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 2)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Design.Colors.strongBorder)
                .frame(width: 1)
        }
    }

    private var drawerBackground: some View {
        Design.Colors.drawerGradient
    }
}

// MARK: - Conversation list pane (Lane J, J-8)

/// The conversation-list surface itself: header, inline filter, New Chat,
/// grouped session list with pin/archive, archived filter row, host footer,
/// and the full-corpus search sheet. Lane F built this as the drawer's
/// panel; Lane J extracted it verbatim so the split-view sidebar and the
/// drawer render ONE component — F's surfaces exist exactly once.
struct ConversationListPane: View {
    var model: SessionsDrawerModel
    /// Footer host status line (driven by the host screen).
    var hostName: String = "HERMES HOST"
    var hostDetail: String = "LINKED"
    var hostOnline: Bool = true
    /// Drawer chrome seam: non-nil when the pane lives in the slide-in
    /// drawer — list actions dismiss the drawer and the header shows a
    /// close X (with Esc bound). Nil in the split-view sidebar, where the
    /// pane is a persistent column and nothing dismisses.
    var dismissHost: (() -> Void)? = nil

    // #96/#97: the pane wires its own store seams (ChatScreen stays
    // untouched — Lane F constraint). Both are optional-tolerant: absent
    // environment objects would crash, but these are injected at the app
    // root; previews/tests drive the model directly instead.
    @Environment(AppContainer.self) private var container
    @Environment(ChatStore.self) private var chatStore
    @State private var showSearch = false

    // Lane J (J-9): ⌘K in regular width focuses the inline filter field.
    @FocusState private var filterFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, Design.Spacing.lg)
            newChatButton
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.sm)
            sessionList
            if model.archivedCount > 0 || model.showingArchived {
                archivedFilterRow
            }
            tasksRow
            skillsRow
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            model.listState = container.conversationListState
            model.journal = chatStore.journal
            // Sidebar context only: the drawer already refreshes on every
            // open via ChatScreen's onChange — no double fetch there.
            if dismissHost == nil {
                model.onRefreshRequest?()
            }
            // A ⌘K focus request can land while the pane is unmounted
            // (sidebar hidden) — honor it once on mount.
            if model.consumeSearchFieldFocusRequest() {
                filterFieldFocused = true
            }
        }
        .onChange(of: model.searchFieldFocusRequested) { _, requested in
            guard requested, model.consumeSearchFieldFocusRequest() else { return }
            filterFieldFocused = true
        }
        .sheet(isPresented: $showSearch) {
            ConversationSearchScreen(
                drawerModel: model,
                onDidSelect: { dismissHost?() }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("SESSIONS")
                    .font(Design.Typography.display(22, weight: .semibold, relativeTo: .title2))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                MonoLabel(model.headerStat, size: 10, tracking: Design.Tracking.monoWide)
            }
            Spacer()
            // #96: full conversation search (local journal + fetched server
            // sessions) — the inline field below only filters this list.
            Button { showSearch = true } label: {
                headerChipIcon("text.magnifyingglass")
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Search all conversations")
            if let dismissHost {
                Button { dismissHost() } label: {
                    headerChipIcon("xmark")
                }
                .buttonStyle(.plain)
                // J-4: Esc closes the drawer overlay (hardware keyboards only).
                .keyboardShortcut(.cancelAction)
                .hoverEffect(.highlight)
                .accessibilityLabel("Close sessions")
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.xxl)
        .padding(.bottom, Design.Spacing.md)
    }

    private func headerChipIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Design.Colors.secondaryForeground)
            .frame(width: 34, height: 34)
            .background(Design.Colors.chipSurface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
            }
    }

    private var searchField: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.mutedForeground)
            TextField("", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
                      prompt: Text("Search conversations…").foregroundStyle(Design.Colors.dimForeground))
                .font(Design.Typography.body(13))
                .foregroundStyle(Design.Colors.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // J-9: ⌘K's focus target in regular width.
                .focused($filterFieldFocused)
            MonoLabel("⌘K", size: 9, color: Design.Brand.accent)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Design.Colors.accentTint(0.08), in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs))
        }
        .padding(.horizontal, Design.Spacing.sm)
        .frame(height: 42)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    private var newChatButton: some View {
        GlowButton(title: "New Chat", systemImage: "plus", height: 46) {
            model.newChat()
            dismissHost?()
        }
        // M-16: with more than one backend profile, long-press offers "New
        // chat on <profile>" — the session is born on that host, the default
        // stays put. A single backend keeps the plain button.
        .contextMenu {
            if model.newChatProfiles.count > 1 {
                ForEach(model.newChatProfiles) { option in
                    Button {
                        model.newChat(onProfile: option.id)
                        dismissHost?()
                    } label: {
                        if option.id == model.activeNewChatProfileID {
                            Label("New chat on \(option.name)", systemImage: "checkmark")
                        } else {
                            Text("New chat on \(option.name)")
                        }
                    }
                }
            }
        }
    }

    // A List (not the previous ScrollView) so rows get native swipe actions
    // (#97). All chrome is stripped — clear backgrounds, hidden separators,
    // row insets reproducing the old stack spacing — so the HUD panel rows
    // render as before.
    private var sessionList: some View {
        List {
            if model.showingArchived && model.grouped().isEmpty {
                MonoLabel("NO ARCHIVED SESSIONS MATCH", size: 9,
                          tracking: Design.Tracking.monoWide,
                          color: Design.Colors.dimForeground)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Design.Spacing.lg, leading: Design.Spacing.md,
                        bottom: Design.Spacing.xs, trailing: Design.Spacing.md
                    ))
            }
            ForEach(model.grouped(), id: \.group.id) { entry in
                MonoLabel(entry.group.rawValue, size: 9, tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.dimForeground)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Design.Spacing.sm,
                        leading: Design.Spacing.md + Design.Spacing.xxs,
                        bottom: Design.Spacing.xxs,
                        trailing: Design.Spacing.md
                    ))
                ForEach(entry.items) { item in
                    SessionRow(summary: item) { model.selectSession(item); dismissHost?() }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: Design.Spacing.xxs, leading: Design.Spacing.md,
                            bottom: Design.Spacing.xxs, trailing: Design.Spacing.md
                        ))
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            pinAction(for: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            archiveAction(for: item)
                        }
                        .contextMenu {
                            pinAction(for: item)
                            archiveAction(for: item)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 12)
    }

    private func pinAction(for item: SessionsDrawerModel.SessionSummary) -> some View {
        Button {
            withAnimation(Design.Motion.standard) { model.togglePin(item) }
        } label: {
            Label(model.isPinned(item) ? "Unpin" : "Pin",
                  systemImage: model.isPinned(item) ? "pin.slash" : "pin")
        }
        .tint(Design.Brand.accent)
    }

    private func archiveAction(for item: SessionsDrawerModel.SessionSummary) -> some View {
        Button {
            withAnimation(Design.Motion.standard) { model.toggleArchive(item) }
        } label: {
            Label(model.isArchived(item) ? "Unarchive" : "Archive",
                  systemImage: model.isArchived(item) ? "tray.and.arrow.up" : "archivebox")
        }
        .tint(Design.Brand.forge)
    }

    /// #97: the Archived filter row at the drawer bottom — enters the
    /// archived-only view, and exits it. Hidden while nothing is archived.
    private var archivedFilterRow: some View {
        Button {
            withAnimation(Design.Motion.standard) { model.showingArchived.toggle() }
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: model.showingArchived ? "chevron.left" : "archivebox")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                MonoLabel(model.showingArchived ? "BACK TO SESSIONS" : "ARCHIVED",
                          size: 10, weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                Spacer()
                if !model.showingArchived {
                    MonoLabel("\(model.archivedCount)", size: 10,
                              tracking: Design.Tracking.mono,
                              color: Design.Colors.dimForeground)
                }
            }
            .padding(.horizontal, Design.Spacing.sm)
            .frame(height: 40)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xs)
        .accessibilityLabel(model.showingArchived
            ? "Back to sessions"
            : "Archived, \(model.archivedCount) session\(model.archivedCount == 1 ? "" : "s")")
    }

    /// #156a: entry to the agent's scheduled jobs — the drawer is the app's
    /// navigation home, and future agent surfaces (156b skills) can join it.
    private var tasksRow: some View {
        Button {
            container.router.navigate(to: .tasks)
            dismissHost?()
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                MonoLabel("SCHEDULED TASKS", size: 10, weight: .medium,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Design.Colors.dimForeground)
            }
            .padding(.horizontal, Design.Spacing.sm)
            .frame(height: 40)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xs)
        .accessibilityLabel("Scheduled tasks")
    }

    /// #156b: entry to the installed-skills browser — unconditional like
    /// tasksRow; the screen owns its not-configured state.
    private var skillsRow: some View {
        Button {
            container.router.navigate(to: .skills)
            dismissHost?()
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                MonoLabel("SKILLS", size: 10, weight: .medium,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Design.Colors.dimForeground)
            }
            .padding(.horizontal, Design.Spacing.sm)
            .frame(height: 40)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xs)
        .accessibilityLabel("Skills")
    }

    private var footer: some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: hostOnline ? Design.Brand.accent : Design.Brand.forge, diameter: 8)
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(hostName, size: 11, weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Colors.coolForeground)
                MonoLabel(hostDetail, size: 9, tracking: Design.Tracking.mono)
            }
            Spacer()
            Button { model.onOpenHostSettings?(); dismissHost?() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
            }
            .hoverEffect(.highlight)
            .accessibilityLabel("Host settings")
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.sm)
        .padding(.bottom, Design.Spacing.xl)
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let summary: SessionsDrawerModel.SessionSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                leadingGlyph
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(summary.title)
                            .font(Design.Typography.body(14, weight: summary.isActive ? .medium : .regular))
                            .foregroundStyle(summary.isActive ? Design.Colors.foregroundBright : Design.Colors.foreground)
                            .lineLimit(1)
                        Spacer()
                        MonoLabel(summary.timeLabel, size: 9,
                                  color: summary.isActive ? Design.Brand.accent : Design.Colors.dimForeground)
                    }
                    Text(summary.subtitle)
                        .font(Design.Typography.body(12))
                        .foregroundStyle(summary.isActive ? Design.Colors.coolForeground : Design.Colors.secondaryForeground)
                        .lineLimit(1)
                    if summary.isActive {
                        badge("● CURRENT", color: Design.Brand.accent, tint: 0.14)
                    } else if let badge = summary.badge {
                        self.badge(badge, color: Design.Colors.secondaryForeground, tint: 0.06, neutral: true)
                    }
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPanel(
                cornerRadius: Design.CornerRadius.md,
                borderColor: summary.isActive ? Design.Colors.accentTint(0.4) : Design.Colors.divider,
                fill: summary.isActive ? Design.Colors.accentTint(0.1) : Design.Colors.surface
            )
        }
        .buttonStyle(.plain)
        // Lane J (J-5): pointer affordance on iPad — inert without a pointer.
        .hoverEffect(.highlight)
        .accessibilityLabel("\(summary.title), \(summary.subtitle)\(summary.isActive ? ", current session" : "")")
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if summary.isActive {
            StatusPip(color: Design.Brand.accent, diameter: 7).padding(.top, 5)
        } else if summary.isPinned {
            Image(systemName: "diamond.fill")
                .font(.system(size: 9))
                .foregroundStyle(Design.Brand.accent)
                .padding(.top, 3)
        } else {
            Image(systemName: "hexagon")
                .font(.system(size: 10))
                .foregroundStyle(Design.Colors.mutedForeground)
                .padding(.top, 3)
        }
    }

    private func badge(_ text: String, color: Color, tint: Double, neutral: Bool = false) -> some View {
        MonoLabel(text, size: 8, tracking: Design.Tracking.mono, color: color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                (neutral ? Design.Colors.chipSurface : Design.Colors.accentTint(tint)),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
                    .strokeBorder(neutral ? Design.Colors.chipBorder : Design.Colors.accentTint(0.4), lineWidth: 1)
            }
            .padding(.top, 4)
    }
}
