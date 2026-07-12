import SwiftUI

// MARK: - Conversation search (#96)
//
// Full-corpus search sheet, reachable from the sessions drawer: the local
// `ConversationJournal` (title + full turn text — the durable primary record
// per #93) and the ALREADY-FETCHED Hermes server-session list (title +
// preview; the Sessions API exposes no message bodies without opening a
// session, and search never fetches per keystroke). Results are grouped
// local-first; tapping a server hit routes through the drawer's selection
// seam, so it opens exactly as a drawer row tap would.

// MARK: Debounced search model

@MainActor
@Observable
final class ConversationSearchModel {

    struct Results: Hashable, Sendable {
        var local: [ConversationSearch.LocalHit] = []
        var server: [ConversationSearch.ServerHit] = []
        var isEmpty: Bool { local.isEmpty && server.isEmpty }
    }

    var query = "" {
        didSet { queryChanged() }
    }

    private(set) var results = Results()
    /// True once a non-empty query has actually resolved — separates the
    /// type-to-search prompt from an honest NO MATCHES state.
    private(set) var hasSearched = false

    /// Corpus seams, wired by the screen (already-fetched data only — the
    /// providers do no I/O). Tests inject fixtures here.
    var journalEntriesProvider: @MainActor () -> [ConversationJournal.Entry] = { [] }
    var serverSessionsProvider: @MainActor () -> [HermesSessionInfo] = { [] }

    /// Keystroke debounce (#96): typing only reschedules; the corpus scan
    /// runs after the pause.
    var debounceInterval: Duration = .milliseconds(250)

    private var pendingSearch: Task<Void, Never>?

    private func queryChanged() {
        pendingSearch?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pendingSearch = nil
            results = Results()
            hasSearched = false
            return
        }
        pendingSearch = Task { [debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            performSearch(trimmed)
        }
    }

    /// The debounced work — callable directly (submit-on-return, tests).
    func performSearch(_ trimmedQuery: String) {
        results = Results(
            local: ConversationSearch.searchJournal(
                entries: journalEntriesProvider(),
                query: trimmedQuery
            ),
            server: ConversationSearch.searchSessions(
                serverSessionsProvider(),
                query: trimmedQuery
            )
        )
        hasSearched = true
    }
}

// MARK: Search screen

struct ConversationSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChatStore.self) private var chatStore

    /// The live drawer model: server hits route through the SAME selection
    /// seam a drawer row tap uses, and pin/archive badges read the stores the
    /// drawer already wired onto it.
    var drawerModel: SessionsDrawerModel
    /// Host callback — closes the drawer behind this sheet after a selection.
    var onDidSelect: () -> Void = {}

    @State private var model = ConversationSearchModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, Design.Spacing.lg)
            corpusStat
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.xs)
            resultsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { HUDScreenBackground().ignoresSafeArea() }
        .presentationDragIndicator(.visible)
        .onAppear {
            model.journalEntriesProvider = { [chatStore] in
                chatStore.journal?.entries ?? []
            }
            model.serverSessionsProvider = { [chatStore] in
                chatStore.lastLoadedSessions
            }
            searchFocused = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("SEARCH")
                    .font(Design.Typography.display(22, weight: .semibold, relativeTo: .title2))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                MonoLabel("LOCAL JOURNAL + FETCHED SESSIONS", size: 10, tracking: Design.Tracking.monoWide)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(width: 34, height: 34)
                    .background(Design.Colors.chipSurface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            // J-4: Esc closes the search sheet (hardware keyboards only).
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.xl)
        .padding(.bottom, Design.Spacing.md)
    }

    // MARK: Search field

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.mutedForeground)
            TextField(
                "",
                text: $model.query,
                prompt: Text("Search conversations…").foregroundStyle(Design.Colors.dimForeground)
            )
            .font(Design.Typography.body(13))
            .foregroundStyle(Design.Colors.foreground)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit {
                let trimmed = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { model.performSearch(trimmed) }
            }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .frame(height: 42)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    /// Honest reach telemetry: exactly what this search can see right now.
    private var corpusStat: some View {
        MonoLabel(
            "\(chatStore.journal?.entries.count ?? 0) LOCAL TURNS · \(chatStore.lastLoadedSessions.count) SERVER SESSIONS",
            size: 9,
            tracking: Design.Tracking.mono,
            color: Design.Colors.dimForeground
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.Spacing.xs) {
                if model.results.isEmpty {
                    emptyState
                } else {
                    if !model.results.local.isEmpty {
                        localHeader
                        ForEach(model.results.local) { hit in
                            localRow(hit)
                        }
                    }
                    if !model.results.server.isEmpty {
                        MonoLabel("SERVER SESSIONS", size: 9, tracking: Design.Tracking.monoXWide,
                                  color: Design.Colors.dimForeground)
                            .padding(.top, Design.Spacing.xs)
                            .padding(.horizontal, Design.Spacing.xxs)
                        ForEach(model.results.server) { hit in
                            serverRow(hit)
                        }
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.xl)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: Design.Spacing.xs) {
            if trimmed.isEmpty {
                MonoLabel("TYPE TO SEARCH", size: 10, tracking: Design.Tracking.monoWide,
                          color: Design.Colors.mutedForeground)
                MonoLabel("LOCAL TURNS MATCH ON FULL TEXT · SERVER SESSIONS ON TITLE + PREVIEW",
                          size: 8, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
                    .multilineTextAlignment(.center)
            } else if model.hasSearched {
                MonoLabel("NO MATCHES", size: 10, tracking: Design.Tracking.monoWide,
                          color: Design.Colors.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing.xl)
        .padding(.horizontal, Design.Spacing.md)
    }

    // MARK: Local journal results

    private var localHeader: some View {
        HStack(spacing: Design.Spacing.xs) {
            MonoLabel("LOCAL JOURNAL", size: 9, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.dimForeground)
            if let title = chatStore.conversation?.title {
                MonoLabel("· \(title)", size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
                    .hudSingleLine()
            }
            // #97: the journal's own flags — the durable per-conversation copy.
            if drawerModel.journal?.isPinned == true {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Design.Brand.accent)
                    .accessibilityLabel("Pinned")
            }
            if drawerModel.journal?.isArchived == true {
                MonoLabel("ARCHIVED", size: 8, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
            }
            Spacer()
        }
        .padding(.top, Design.Spacing.xs)
        .padding(.horizontal, Design.Spacing.xxs)
    }

    private func localRow(_ hit: ConversationSearch.LocalHit) -> some View {
        Button {
            // The local journal IS the conversation already on the chat
            // surface beneath — opening it means closing search + drawer.
            dismiss()
            onDidSelect()
        } label: {
            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                MonoLabel(hit.role == .user ? "YOU" : "HERMES", size: 8,
                          tracking: Design.Tracking.mono,
                          color: hit.role == .user ? Design.Colors.secondaryForeground : Design.Brand.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Design.Colors.chipSurface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
                            .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
                    }
                Text(hit.snippet)
                    .font(Design.Typography.body(13))
                    .foregroundStyle(Design.Colors.foreground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPanel(cornerRadius: Design.CornerRadius.md,
                      borderColor: Design.Colors.divider,
                      fill: Design.Colors.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Matching turn from \(hit.role == .user ? "you" : "Hermes"): \(hit.snippet)")
    }

    // MARK: Server session results

    private func serverRow(_ hit: ConversationSearch.ServerHit) -> some View {
        Button {
            selectServerHit(hit)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(hit.displayTitle)
                        .font(Design.Typography.body(14, weight: hit.isActive ? .medium : .regular))
                        .foregroundStyle(hit.isActive ? Design.Colors.foregroundBright : Design.Colors.foreground)
                        .lineLimit(1)
                    Spacer()
                    MonoLabel(ConversationSearch.timeLabel(for: hit.lastActive), size: 9,
                              color: hit.isActive ? Design.Brand.accent : Design.Colors.dimForeground)
                }
                Text(hit.displayDetail)
                    .font(Design.Typography.body(12))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: Design.Spacing.xs) {
                    MonoLabel("\(hit.messageCount) MSG\(hit.messageCount == 1 ? "" : "S")",
                              size: 8, tracking: Design.Tracking.mono,
                              color: Design.Colors.dimForeground)
                    if hit.isActive {
                        MonoLabel("● CURRENT", size: 8, tracking: Design.Tracking.mono,
                                  color: Design.Brand.accent)
                    }
                    if drawerModel.listState?.isPinned(hit.id) == true {
                        HStack(spacing: 2) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 6))
                            MonoLabel("PINNED", size: 8, tracking: Design.Tracking.mono,
                                      color: Design.Brand.accent)
                        }
                        .foregroundStyle(Design.Brand.accent)
                    }
                    if drawerModel.listState?.isArchived(hit.id) == true {
                        MonoLabel("ARCHIVED", size: 8, tracking: Design.Tracking.mono,
                                  color: Design.Colors.dimForeground)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPanel(cornerRadius: Design.CornerRadius.md,
                      borderColor: hit.isActive ? Design.Colors.accentTint(0.4) : Design.Colors.divider,
                      fill: hit.isActive ? Design.Colors.accentTint(0.1) : Design.Colors.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hit.displayTitle)\(hit.isActive ? ", current session" : "")")
    }

    private func selectServerHit(_ hit: ConversationSearch.ServerHit) {
        // Route through the drawer's selection seam so a search hit opens the
        // conversation EXACTLY as the equivalent drawer row tap would. The
        // corpus and the drawer list come from the same fetch, so the summary
        // lookup only misses if the list refreshed mid-search — the fallback
        // carries the same id, which is all selection consumes.
        let summary = drawerModel.sessions.first { $0.id == hit.id }
            ?? SessionsDrawerModel.SessionSummary(
                id: hit.id,
                title: hit.displayTitle,
                subtitle: hit.displayDetail,
                timeLabel: ConversationSearch.timeLabel(for: hit.lastActive),
                group: .earlier,
                isActive: hit.isActive
            )
        dismiss()
        drawerModel.selectSession(summary)
        onDidSelect()
    }
}
