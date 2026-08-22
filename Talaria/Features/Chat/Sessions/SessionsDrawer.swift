import SwiftUI

// MARK: - Sessions drawer (UI shell)
//
// Left slide-in panel listing chat sessions. The list surface itself is
// `ConversationListPane` — the "2b" thumb-anchored shelf, shared verbatim with
// the regular-width split-view sidebar (Lane J, J-8). Only the slide-in chrome
// (width, gradient, edge highlight, backdrop, dismissal) is drawer-specific.

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

    /// #190: which source a session row came from. Drives the leading-gutter
    /// origin glyph — and only once BOTH origins are present in the list
    /// (`showsOriginGlyphs`); a single-source list carries no marker at all.
    enum SessionOrigin: Hashable {
        case local
        case remote

        /// Same iconography as `ChatBackendRouter.Brain.glyph` — the drawer
        /// and the header pill speak one visual language.
        var glyphSystemName: String {
            switch self {
            case .local: "iphone"
            case .remote: "desktopcomputer"
            }
        }
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
        /// Messages the host reported for this session. Drives the
        /// empty-session filter: `fetchSessionList` already asks for
        /// `?min_messages=1` and the gateway silently ignores it
        /// (OPEN_ITEMS #187), so the rule has to live on this side.
        var messageCount: Int = 0
        /// #190: the row's source. Nil (placeholders, pre-#190 callers)
        /// never renders a glyph.
        var origin: SessionOrigin? = nil
        /// #190: true for remote stubs no configured host can open — the row
        /// renders dimmed with its reason as the subtitle, and does not
        /// respond to taps. Never hidden: hiding lies about history.
        var isUnresumable: Bool = false
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

    /// Mirrors `UserSettings.showEmptySessions`, wired by the pane. OFF (the
    /// default) hides zero-message rows — see `grouped`.
    var showEmptySessions = false

    /// The rows the user can actually see, flattened. The header stat and any
    /// count that claims to describe the shelf reads THIS, never `sessions` —
    /// "14 THREADS" over 9 rows is the same class of lie the empty filter
    /// exists to remove.
    var visibleSessions: [SessionSummary] {
        grouped().flatMap(\.items)
    }

    /// #190: origin markers appear only once sessions from MORE THAN ONE
    /// source coexist — free-tier users have exactly one source, and a
    /// marker there is pure noise.
    var showsOriginGlyphs: Bool {
        Self.showsOriginGlyphs(sessions: sessions)
    }

    nonisolated static func showsOriginGlyphs(sessions: [SessionSummary]) -> Bool {
        Set(sessions.compactMap(\.origin)).count > 1
    }

    /// Header telemetry, e.g. "14 THREADS · 2 ACTIVE". At zero active the
    /// clause is suppressed entirely rather than reading "0 ACTIVE" — the
    /// stat is a sentence, and a sentence that reflows on every fetch is what
    /// made the old header collide with its own chrome.
    var headerStat: String {
        let visible = visibleSessions
        let threads = "\(visible.count) THREAD\(visible.count == 1 ? "" : "S")"
        let active = visible.filter(\.isActive).count
        return active > 0 ? "\(threads) · \(active) ACTIVE" : threads
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

    /// Sessions filtered by `searchText`, the empty-session rule and the
    /// pin/archive overlay (#97), grouped and ordered for display.
    func grouped() -> [(group: Group, items: [SessionSummary])] {
        Self.grouped(
            sessions: sessions,
            query: searchText,
            pinnedIDs: listState?.state.pinnedSessionIDs ?? [],
            archivedIDs: listState?.state.archivedSessionIDs ?? [],
            showingArchived: showingArchived,
            showEmptySessions: showEmptySessions
        )
    }

    /// The drawer's data-source rule, pure so tests can drive it directly:
    /// query filter (case/diacritic-insensitive, title + subtitle), then the
    /// empty-session filter, then the overlay — pinned rows float to the
    /// PINNED section regardless of their recency group, with NO pin cap
    /// (ChatGPT caps at 3; we deliberately don't); archived rows are hidden
    /// from the main list and shown alone when `showingArchived` is on. Order
    /// within a section is the fetch order (recency), untouched.
    ///
    /// `showEmptySessions` defaults to `true` (no filtering) so callers that
    /// have no user setting to consult — and every pre-existing test — keep
    /// the historical behavior; the pane passes the real preference.
    static func grouped(
        sessions: [SessionSummary],
        query: String,
        pinnedIDs: Set<String>,
        archivedIDs: Set<String>,
        showingArchived: Bool,
        showEmptySessions: Bool = true
    ) -> [(group: Group, items: [SessionSummary])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trimmed.isEmpty
            ? sessions
            : sessions.filter {
                $0.title.localizedStandardContains(trimmed)
                    || $0.subtitle.localizedStandardContains(trimmed)
            }

        // #187: hide zero-message rows, with two exemptions. The ACTIVE
        // session is not optional — tapping New Chat creates a zero-message
        // session, and without this it would be invisible in the shelf that
        // just opened and the current-row bar would have nothing to mark. A
        // PINNED session is an explicit user act, which outranks a heuristic.
        let filtered = showEmptySessions
            ? matching
            : matching.filter {
                $0.messageCount > 0
                    || $0.isActive
                    || $0.isPinned
                    || pinnedIDs.contains($0.id)
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
        // #190: an unresumable row is visible history, not a destination —
        // one choke point covers the drawer, the sidebar, and search hits.
        guard !summary.isUnresumable else { return }
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
                       timeLabel: "7:00", group: .pinned, isPinned: true,
                       badge: "AUTO · DAILY", messageCount: 12),
        SessionSummary(id: "today-resched", title: "Reschedule afternoon",
                       subtitle: "4 events moved · note to Sarah queued",
                       timeLabel: "09:41", group: .today, isActive: true,
                       messageCount: 8),
        SessionSummary(id: "today-invoice", title: "Invoice triage",
                       subtitle: "3 approved · 1 flagged for review",
                       timeLabel: "08:12", group: .today, messageCount: 5),
        SessionSummary(id: "yday-tokyo", title: "Tokyo trip planning",
                       subtitle: "Flights + hotel shortlisted",
                       timeLabel: "Tue", group: .yesterday, messageCount: 22),
        SessionSummary(id: "yday-review", title: "Codebase review",
                       subtitle: "12 files · 3 diffs proposed",
                       timeLabel: "Tue", group: .yesterday, messageCount: 31),
    ]
}

// MARK: Drawer view

struct SessionsDrawer: View {
    @Binding var isPresented: Bool
    var model: SessionsDrawerModel
    /// Footer host status line (driven by the host screen).
    var hostName: String = "HERMES HOST"
    // #350: the defaults must not assert reachability (only previews/tests
    // ever fall back to them — both live call sites pass measured values).
    var hostDetail: String = "LINKED · —"
    var hostOnline: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// What the panel leaves behind: enough chat to read as a layer over the
    /// conversation rather than a floating card, and no more. A fixed 320pt
    /// panel left 73pt of unusable chat on a 393pt phone and grew worse on a
    /// Pro Max — the sliver is the design intent, so it is what stays fixed.
    private static let peekSliver: CGFloat = 32
    /// Compact width is not always a phone (Stage Manager, Slide Over). Past
    /// this the shelf stops being a shelf and becomes a page.
    private static let maxPanelWidth: CGFloat = 480
    private static let fallbackPanelWidth: CGFloat = 320

    private var reduceMotion: Bool {
        systemReduceMotion || ThemeRuntime.shared.appReduceMotion
    }

    private func panelWidth(in available: CGFloat) -> CGFloat {
        guard available > Self.peekSliver else { return Self.fallbackPanelWidth }
        return min(available - Self.peekSliver, Self.maxPanelWidth)
    }

    /// Hosted at the window root (MainTabView), so the panel's CONTENT gets
    /// the device safe area for free — only the atmosphere ignores it, which
    /// is the whole of defect 01: the gradient runs under the status bar and
    /// home indicator while the header starts at the inset, not 48pt from the
    /// panel top. No UIKit inset read, no orientation bookkeeping.
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if isPresented {
                    backdrop
                        .transition(.opacity)
                    panel
                        .frame(width: panelWidth(in: proxy.size.width))
                        .transition(panelTransition)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(Design.Motion.standard, value: isPresented)
        }
        .onAppear {
            // The Archived filter is a transient view — every drawer open
            // starts on the main list. (Drawer-only semantics: the split-view
            // sidebar is persistent and keeps its filter state.)
            model.showingArchived = false
        }
    }

    /// §5: Reduce Motion targets TRAVEL, not substitution. The panel stops
    /// sliding in from the leading edge and cross-fades in place over the same
    /// duration, on both channels — so the chat never disappears before the
    /// panel has arrived. The chrome cross-fade itself (ChatScreen's toolbar)
    /// is exactly the substitution the setting asks *for*, and stays.
    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .leading)
    }

    // MARK: Backdrop

    private var backdrop: some View {
        Design.Colors.scrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { isPresented = false }
            .accessibilityLabel("Close sessions")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Panel

    private var panel: some View {
        // Lane J (J-8): the list surface is the shared ConversationListPane —
        // the SAME component the split-view sidebar embeds (extracted, not
        // forked). Only the slide-in chrome is drawer-specific.
        ConversationListPane(
            model: model,
            hostName: hostName,
            hostDetail: hostDetail,
            hostOnline: hostOnline,
            dismissHost: { isPresented = false },
            actionAnchor: .bottom
        )
        // Only the atmosphere bleeds past the safe area — the pane's content
        // keeps the window's real insets (defect 01).
        .background { drawerBackground.ignoresSafeArea() }
        .overlay(alignment: .leading) {
            // Bright cyan edge highlight.
            LinearGradient(
                colors: [.clear, Design.Brand.accent.opacity(0.5), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 2)
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Design.Colors.strongBorder)
                .frame(width: 1)
                .ignoresSafeArea()
        }
    }

    private var drawerBackground: some View {
        Design.Colors.drawerGradient
    }
}

// MARK: - Conversation list pane (Lane J, J-8 · the 2b shelf)

/// The conversation-list surface itself: a 40pt telemetry header, a scrolling
/// session list with soft scroll edges, and a thumb-anchored action dock
/// carrying the four-up nav rail, the single search field, New, and the host
/// footer.
///
/// One component, two anchors (§7): at regular width `actionAnchor` flips to
/// `.top` and the SAME VStack emits the SAME elements in the other order —
/// 2b *becomes* the top-anchored 2a variant. There is no second layout.
struct ConversationListPane: View {

    /// Where the action dock sits. Nil derives it from the horizontal size
    /// class; explicit values exist for previews and tests.
    enum ActionAnchor { case top, bottom }

    var model: SessionsDrawerModel
    /// Footer host status line (driven by the host screen).
    var hostName: String = "HERMES HOST"
    // #350: see the drawer note — defaults must not assert reachability.
    var hostDetail: String = "LINKED · —"
    var hostOnline: Bool = false
    /// Drawer chrome seam: non-nil when the pane lives in the slide-in
    /// drawer — list actions dismiss the drawer and the header shows a
    /// close X (with Esc bound). Nil in the split-view sidebar, where the
    /// pane is a persistent column and nothing dismisses.
    var dismissHost: (() -> Void)? = nil
    /// §7: the regular-width sidebar's ✕ is a *column* toggle, not a
    /// dismissal — a separate seam because `dismissHost` also fires on every
    /// row tap, which must never collapse the sidebar.
    var collapseHost: (() -> Void)? = nil
    var actionAnchor: ActionAnchor? = nil

    // #96/#97: the pane wires its own store seams (ChatScreen stays
    // untouched — Lane F constraint). Both are optional-tolerant: absent
    // environment objects would crash, but these are injected at the app
    // root; previews/tests drive the model directly instead.
    @Environment(AppContainer.self) private var container
    @Environment(ChatStore.self) private var chatStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showSearch = false
    /// The query handed to the full-corpus sheet by the SEARCH EVERYTHING row.
    @State private var searchSeed = ""
    @State private var scrolledFromTop = false
    @State private var scrolledFromBottom = false

    // Lane J (J-9): ⌘K in regular width focuses the inline filter field.
    @FocusState private var filterFieldFocused: Bool

    // MARK: Metrics
    //
    // §2's pt budget. The dock is what the thumb has memorised, so its own
    // geometry is fixed — Dynamic Type grows the line boxes inside it, never
    // the spacing around them.
    private enum Metrics {
        static let headerRow: CGFloat = 40
        static let gapAboveList: CGFloat = 8
        static let dockPad: CGFloat = 11        // + 1pt hairline = 12
        static let rail: CGFloat = 44
        static let dockGap: CGFloat = 10
        static let footerPad: CGFloat = 7       // + 1pt hairline = 8
        static let hostFooter: CGFloat = 52
        static let topFade: CGFloat = 24
        static let bottomFade: CGFloat = 28
        static let currentBar: CGFloat = 3
        static let textLeading: CGFloat = 12
        static let newPillCollapsed: CGFloat = 56
    }

    /// VoiceOver traversal (§6). 2b deliberately breaks reading-order =
    /// visual-order: the dock is at the bottom because that is where a thumb
    /// is, and VoiceOver does not have a thumb. Higher priority reads first.
    private enum Order {
        static let header: Double = 70
        static let search: Double = 60
        static let newChat: Double = 50
        static let list: Double = 40
        static let rail: Double = 30
        static let host: Double = 20
        static let close: Double = 10
    }

    // MARK: Derived state

    private var resolvedAnchor: ActionAnchor {
        actionAnchor ?? (horizontalSizeClass == .regular ? .top : .bottom)
    }

    /// §2: opaque on compact (the drawer paints `drawerGradient` behind the
    /// pane), transparent on regular so the window-spanning atmosphere shows
    /// through both columns. Keyed off the drawer seam rather than the size
    /// class — a NavigationSplitView column is free to report `.compact`, and
    /// the question here is literally "did the drawer paint a gradient behind
    /// me", which only the drawer knows.
    private var isOpaquePanel: Bool { dismissHost != nil }

    private var railDropsCaptions: Bool { dynamicTypeSize >= .xxLarge }
    private var newCollapsesToIcon: Bool { dynamicTypeSize >= .xxLarge }
    private var footerDropsStatusLine: Bool { dynamicTypeSize >= .accessibility1 }
    private var searchRowHeight: CGFloat { dynamicTypeSize >= .xxLarge ? 54 : 48 }
    private var groupHeaderHeight: CGFloat { dynamicTypeSize >= .xxLarge ? 30 : 26 }

    private var fadeTopColor: Color {
        isOpaquePanel ? Design.Colors.drawerEdgeTop : Design.Colors.background
    }
    private var fadeBottomColor: Color {
        isOpaquePanel ? Design.Colors.drawerEdgeBottom : Design.Colors.background
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            if resolvedAnchor == .top { dock }
            listSurface
            if resolvedAnchor == .bottom { dock }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { dismissHost?() }
        .onAppear {
            model.listState = container.conversationListState
            model.journal = chatStore.journal
            model.showEmptySessions = settingsStore.settings.showEmptySessions
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
        .onChange(of: settingsStore.settings.showEmptySessions) { _, show in
            model.showEmptySessions = show
        }
        .onChange(of: model.searchFieldFocusRequested) { _, requested in
            guard requested, model.consumeSearchFieldFocusRequest() else { return }
            filterFieldFocused = true
        }
        .sheet(isPresented: $showSearch) {
            ConversationSearchScreen(
                drawerModel: model,
                initialQuery: searchSeed,
                onDidSelect: { dismissHost?() }
            )
        }
    }

    // MARK: Header (§01)

    /// 40pt: telemetry and the ✕, nothing else. The old two-line wordmark
    /// stack is gone — it is what pushed content into the safe-area inset.
    private var header: some View {
        HStack(spacing: Design.Spacing.xs) {
            MonoLabel(model.headerStat, size: 10, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.secondaryForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(Order.header)
            Spacer(minLength: 0)
            headerDismissButton
        }
        .padding(.horizontal, Design.Spacing.md)
        .frame(height: Metrics.headerRow)
        .padding(.bottom, Metrics.gapAboveList)
        .overlay(alignment: .bottom) {
            hairline.opacity(resolvedAnchor == .bottom && scrolledFromTop ? 1 : 0)
        }
    }

    @ViewBuilder
    private var headerDismissButton: some View {
        if let dismissHost {
            Button { dismissHost() } label: { headerGlyph("xmark") }
                .buttonStyle(.plain)
                // J-4: Esc closes the drawer overlay (hardware keyboards only).
                .keyboardShortcut(.cancelAction)
                .hoverEffect(.highlight)
                .accessibilityLabel("Close sessions")
                .accessibilitySortPriority(Order.close)
        } else if let collapseHost {
            // §7: in a column there is nothing to dismiss — Esc goes quiet and
            // the glyph becomes the sidebar toggle.
            Button { collapseHost() } label: { headerGlyph("sidebar.leading") }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel("Hide sessions column")
                .accessibilitySortPriority(Order.close)
        }
    }

    private func headerGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Design.Colors.secondaryForeground)
            .frame(width: Design.Size.minTapTarget, height: Metrics.headerRow)
            .contentShape(Rectangle())
    }

    // MARK: List surface (§05)

    private var listSurface: some View {
        sessionList
            // The dock is a sibling, not an overlay (§2's budget), so the
            // only thing the last row has to clear is the bottom fade.
            .contentMargins(.bottom, Metrics.bottomFade, for: .scrollContent)
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(
                    fromTop: geometry.contentOffset.y + geometry.contentInsets.top > 1,
                    fromBottom: geometry.contentOffset.y + geometry.containerSize.height
                        < geometry.contentSize.height + geometry.contentInsets.bottom - 1
                )
            } action: { _, edges in
                scrolledFromTop = edges.fromTop
                scrolledFromBottom = edges.fromBottom
            }
            .overlay(alignment: .top) {
                edgeFade(colors: [fadeTopColor, fadeTopColor.opacity(0)],
                         height: Metrics.topFade)
            }
            .overlay(alignment: .bottom) {
                edgeFade(colors: [fadeBottomColor.opacity(0), fadeBottomColor],
                         height: Metrics.bottomFade)
            }
            .accessibilitySortPriority(Order.list)
    }

    /// Scroll-edge state, read in one pass so both hairlines share a source.
    private struct ScrollEdges: Equatable {
        var fromTop: Bool
        var fromBottom: Bool
    }

    private func edgeFade(colors: [Color], height: CGFloat) -> some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
    }

    // The list stays a `List` (not the ScrollView it replaced): #97's pin and
    // archive ride `.swipeActions`, which exists nowhere else. All chrome is
    // stripped — clear backgrounds, hidden separators — so the rows can carry
    // their own hairlines inset to the text leading (§2: no card borders).
    private var sessionList: some View {
        List {
            ForEach(model.grouped(), id: \.group.id) { entry in
                Section {
                    ForEach(entry.items) { item in
                        row(for: item)
                    }
                } header: {
                    groupHeader(entry.group)
                }
            }
            if model.grouped().isEmpty {
                emptyStateRow
            }
            searchEverythingRow
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private func row(for item: SessionsDrawerModel.SessionSummary) -> some View {
        SessionRow(summary: item, showsOriginGlyph: model.showsOriginGlyphs) {
            model.selectSession(item)
            dismissHost?()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: Design.Spacing.md,
                                  bottom: 0, trailing: Design.Spacing.md))
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

    private func groupHeader(_ group: SessionsDrawerModel.Group) -> some View {
        MonoLabel(group.rawValue, size: 9, tracking: Design.Tracking.monoXWide,
                  color: Design.Colors.dimForeground)
            .padding(.leading, Metrics.currentBar + Metrics.textLeading)
            .frame(height: groupHeaderHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Sticky headers scroll over live rows — without a backdrop the
            // mono glyphs read on top of a title.
            .background(fadeTopColor)
            .listRowInsets(EdgeInsets(top: 0, leading: Design.Spacing.md,
                                      bottom: 0, trailing: Design.Spacing.md))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyStateRow: some View {
        MonoLabel(emptyStateText, size: 9, tracking: Design.Tracking.monoWide,
                  color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Design.Spacing.lg)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: Design.Spacing.md,
                                      bottom: 0, trailing: Design.Spacing.md))
    }

    private var emptyStateText: String {
        if model.showingArchived { return "No archived sessions match" }
        if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No sessions match"
        }
        return "No sessions yet"
    }

    /// §03: the single field filters as you type, and this row — always the
    /// last one — is the ONLY route to the full-corpus screen. The header
    /// chip that used to duplicate it is gone.
    private var searchEverythingRow: some View {
        Button {
            searchSeed = model.searchText
            showSearch = true
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                MonoLabel(searchEverythingTitle, size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Design.Brand.accent)
            .padding(.leading, Metrics.currentBar + Metrics.textLeading)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: Design.Spacing.md,
                                  bottom: 0, trailing: Design.Spacing.md))
        .accessibilityLabel(searchEverythingAccessibilityLabel)
    }

    private var trimmedQuery: String {
        model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchEverythingTitle: String {
        trimmedQuery.isEmpty ? "Search everything" : "Search everything for \"\(trimmedQuery)\""
    }

    private var searchEverythingAccessibilityLabel: String {
        trimmedQuery.isEmpty
            ? "Search everything"
            : "Search everything for \(trimmedQuery)"
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
        .tint(Design.Brand.forgeText)
    }

    // MARK: Dock (§04, §2)

    /// 184pt of controls the thumb has memorised. Emitted below the list at
    /// compact width and above it at regular — same elements, other order.
    private var dock: some View {
        VStack(spacing: 0) {
            if resolvedAnchor == .bottom {
                hairline.opacity(scrolledFromBottom ? 1 : 0)
                Spacer(minLength: 0).frame(height: Metrics.dockPad)
            }
            navRail
                .padding(.horizontal, Design.Spacing.md)
            Spacer(minLength: 0).frame(height: Metrics.dockGap)
            searchAndNewRow
                .padding(.horizontal, Design.Spacing.md)
            Spacer(minLength: 0).frame(height: Metrics.dockGap)
            hairline
            Spacer(minLength: 0).frame(height: Metrics.footerPad)
            hostFooter
                .padding(.horizontal, Design.Spacing.md)
            if resolvedAnchor == .top {
                Spacer(minLength: 0).frame(height: Metrics.dockPad)
                hairline.opacity(scrolledFromTop ? 1 : 0)
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Design.Colors.divider)
            .frame(height: 1)
    }

    /// §04: four 40pt rows plus `hudPanel` chrome collapse into one 44pt
    /// four-up rail. Every destination stays exactly one tap away.
    private var navRail: some View {
        HStack(spacing: 0) {
            railItem(icon: "clock.arrow.2.circlepath", caption: "TASKS",
                     label: "Scheduled tasks") {
                container.router.navigate(to: .tasks)
                dismissHost?()
            }
            railItem(icon: "sparkles", caption: "SKILLS", label: "Skills") {
                container.router.navigate(to: .skills)
                dismissHost?()
            }
            railItem(icon: "chart.bar.xaxis", caption: "INSIGHTS", label: "Insights") {
                container.router.navigate(to: .insights)
                dismissHost?()
            }
            railItem(icon: model.showingArchived ? "chevron.left" : "archivebox",
                     caption: model.showingArchived ? "BACK" : "ARCHIVE",
                     label: archiveAccessibilityLabel,
                     isOn: model.showingArchived,
                     showsPip: !model.showingArchived && model.archivedCount > 0) {
                withAnimation(Design.Motion.standard) { model.showingArchived.toggle() }
            }
        }
        .frame(height: Metrics.rail)
        .accessibilitySortPriority(Order.rail)
    }

    private var archiveAccessibilityLabel: String {
        if model.showingArchived { return "Back to sessions" }
        let n = model.archivedCount
        return "Archived, \(n) session\(n == 1 ? "" : "s")"
    }

    private func railItem(
        icon: String,
        caption: String,
        label: String,
        isOn: Bool = false,
        showsPip: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: railDropsCaptions ? 20 : 16, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        if showsPip {
                            StatusPip(color: Design.Brand.accent, diameter: 5)
                                .offset(x: 5, y: -2)
                        }
                    }
                if !railDropsCaptions {
                    // §6: the visible caption is decoration — the Button's own
                    // label always reads the full word, so dropping the caption
                    // at XXL changes nothing VoiceOver hears.
                    MonoLabel(caption, size: 8, weight: .medium,
                              tracking: Design.Tracking.mono,
                              color: isOn ? Design.Brand.accent : Design.Colors.dimForeground)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isOn ? Design.Brand.accent : Design.Colors.secondaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.rail)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }

    private var searchAndNewRow: some View {
        HStack(spacing: 6) {
            searchField
            newChatButton
        }
        .frame(height: searchRowHeight)
    }

    private var searchField: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.mutedForeground)
            TextField(
                "",
                text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
                prompt: Text("Filter sessions…").foregroundStyle(Design.Colors.dimForeground)
            )
            .font(Design.Typography.body(13))
            .foregroundStyle(Design.Colors.foreground)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel("Filter sessions")
            .submitLabel(.search)
            .onSubmit {
                searchSeed = model.searchText
                showSearch = true
            }
            // J-9: ⌘K's focus target in regular width.
            .focused($filterFieldFocused)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            } else if horizontalSizeClass == .regular {
                MonoLabel("⌘K", size: 9, color: Design.Brand.accent)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Design.Colors.accentTint(0.08),
                                in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .frame(maxWidth: .infinity)
        .frame(height: searchRowHeight)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        .accessibilitySortPriority(Order.search)
    }

    /// §2: a 1.5pt full-strength accent border and an `accentBright` label —
    /// deliberately NOT a solid fill. Solid accent is the live-state
    /// signifier; a permanently-lit slab of it devalues the current-row bar.
    private var newChatButton: some View {
        Button {
            model.newChat()
            dismissHost?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: newCollapsesToIcon ? 17 : 13, weight: .semibold))
                if !newCollapsesToIcon {
                    Text("NEW")
                        .font(Design.Typography.display(13, weight: .semibold, relativeTo: .headline))
                        .tracking(Design.Tracking.button)
                }
            }
            .foregroundStyle(Design.Brand.accentBright)
            .padding(.horizontal, newCollapsesToIcon ? 0 : Design.Spacing.sm)
            .frame(minWidth: Metrics.newPillCollapsed)
            .frame(height: searchRowHeight)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Brand.accent, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
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
        .accessibilityLabel("New chat")
        .accessibilitySortPriority(Order.newChat)
    }

    /// §06: a fixed 52pt box that never reflows. The hostname degrades from
    /// the MIDDLE — `OWENS-MAC-….LOCAL` keeps both the machine and the
    /// `.local` suffix, where tail truncation would eat the suffix outright.
    private var hostFooter: some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: hostOnline ? Design.Brand.accent : Design.Brand.forge, diameter: 8)
                // §4 at AX1 the status LINE leaves the footer; the pip is what
                // carries the state from then on, so it stops being decoration.
                .accessibilityHidden(!footerDropsStatusLine)
                .accessibilityLabel("Host status")
                .accessibilityValue(hostDetail)
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(hostName, size: 11, weight: .medium,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.coolForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.middle)
                    .allowsTightening(false)
                if !footerDropsStatusLine {
                    MonoLabel(hostDetail, size: 9, tracking: Design.Tracking.mono)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.onOpenHostSettings?()
                dismissHost?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Host settings")
        }
        .frame(height: Metrics.hostFooter)
        .accessibilitySortPriority(Order.host)
    }
}

// MARK: - Session row

/// A bare row on a hairline — no card, no border, no fill. The current row is
/// marked by THREE signals, none of them lightness-of-fill: a 3pt accent bar
/// in a gutter every row reserves, the title stepping to `foregroundBright` at
/// medium weight, and the timestamp moving to the accent. `accentTint(.12)`
/// sits inside the drawer gradient's own range on Deep Field and does not
/// carry, which is why fill is not one of them.
private struct SessionRow: View {
    let summary: SessionsDrawerModel.SessionSummary
    /// #190: on only when sessions from more than one source coexist —
    /// computed by the model, never per-row.
    var showsOriginGlyph: Bool = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasSubtitle: Bool { !summary.subtitle.isEmpty }

    /// §4: rows grow, never reflow. `lineLimit(1)` is absolute at every size,
    /// so growth is the line boxes only.
    private var minimumHeight: CGFloat {
        let grown = dynamicTypeSize >= .xxLarge
        if hasSubtitle { return grown ? 62 : 52 }
        return grown ? 45 : 40
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // #190: the origin glyph lives in the 15pt gutter every row
                // already reserves (bar + text leading) — no new horizontal
                // room, which is why it isn't a text badge.
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(summary.isActive ? Design.Brand.accent : .clear)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                    if showsOriginGlyph, let origin = summary.origin {
                        Image(systemName: origin.glyphSystemName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Design.Colors.dimForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.leading, 3)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 15)
                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    if hasSubtitle { subtitleLine }
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: minimumHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // #190: unresumable rows are visible history, dimmed — never
            // hidden, never navigable.
            .opacity(summary.isUnresumable ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(summary.isUnresumable)
        // Lane J (J-5): pointer affordance on iPad — inert without a pointer.
        .hoverEffect(.highlight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.divider)
                .frame(height: 1)
                // §2: hairlines inset to the text leading, not the row edge.
                .padding(.leading, 15)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(summary.isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
            Text(summary.title)
                .font(Design.Typography.body(14, weight: summary.isActive ? .medium : .regular))
                .foregroundStyle(summary.isActive
                                 ? Design.Colors.foregroundBright
                                 : Design.Colors.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(TrailingFade())
            MonoLabel(summary.timeLabel, size: 9,
                      color: summary.isActive ? Design.Brand.accent : Design.Colors.dimForeground)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var subtitleLine: some View {
        HStack(spacing: Design.Spacing.xs) {
            Text(summary.subtitle)
                .font(Design.Typography.body(12))
                .foregroundStyle(summary.isActive
                                 ? Design.Colors.coolForeground
                                 : Design.Colors.secondaryForeground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(TrailingFade())
            if let badge = summary.badge {
                MonoLabel(badge, size: 8, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// §6: one element per row, and the current row is a TRAIT (`.isSelected`),
    /// never a shape VoiceOver has to infer.
    private var accessibilityLabel: String {
        var parts = [summary.title]
        if hasSubtitle { parts.append(summary.subtitle) }
        parts.append(summary.timeLabel)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Horizontal fade (§05)

/// The same fade language the scroll edges use, run horizontally: text that
/// reaches the trailing edge dissolves instead of stopping on a hard cut.
/// Applied to a full-width frame, so a short string never touches it.
private struct TrailingFade: ViewModifier {
    var width: CGFloat = 16

    func body(content: Content) -> some View {
        content.mask {
            HStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            }
        }
    }
}
