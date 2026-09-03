import SwiftUI

// MARK: - #422 bar 422-P — the MEMORY screen (Settings → SESSIONS → Memory)
//
// The one place a person can see, correct and erase what the app remembers
// about them. Ruling 2 ("every stored row carries a resolvable source") is a
// promise about this screen more than anywhere else: a memory the user cannot
// find is a memory they cannot delete.
//
// It lives UNDER SESSIONS rather than as an eleventh deck card — Owen's
// ruling, and the deck-order pins (`deckOrderIsTenAndStable`) hold it there.
//
// The whole screen is driven by `MemoryScreenModel`, which is built from
// injected closures and holds no SwiftUI: every string, row and count below is
// pinned as a VALUE by `MemoryScreenTests`, so no bar can go green against a
// view that never draws it.

/// The view model. Reads through closures so the pins run without SwiftUI, and
/// so a screen with **no store at all** (a `MemoryStore.make` that returned
/// nil) is an ordinary, honest state rather than a special case.
@MainActor
@Observable
final class MemoryScreenModel {

    // MARK: The screen's own words
    //
    // Owen's naming ruling (CLAUDE.md, 2026-08-27): the outward identity is
    // TALARIA. On-device memory is Talaria's own, so nothing here says Hermes
    // — except `hostLine`, which is about the HOST's memory and is
    // host-meaning by construction. Pinned in `NamingSweepTests`.

    static let title = "MEMORY"
    static let subtitle = "WHAT TALARIA REMEMBERS"

    /// What an empty screen says. **Never a blank list**: a blank one is
    /// indistinguishable from a render that failed, and this screen's whole
    /// job is to be believed about the contents of the store.
    static let emptyCopy = "Nothing saved yet — say \"Remember that…\" or just keep chatting."

    /// Ruling 3, said out loud on the one screen about memory. Shown only when
    /// a host is configured — telling a hostless install about a host's memory
    /// would be describing something the user does not have.
    static let hostLine = """
        Your Hermes host keeps its own memory (Honcho, Hindsight…). Talaria never reads \
        or merges it; a Hermes reply is tagged only when the host reports a memory tool \
        call.
        """

    /// Owen's ruling on the 500-character cap: save the first 500 **with a
    /// visible notice**. Driven by the row's stored `wasTruncated` flag, never
    /// re-derived from `text.count == 500` — a note that is genuinely 500
    /// characters long was not cut, and must not say it was.
    static let truncationNotice = "Saved the first 500 characters."

    /// The house rule, applied to a number: show `—` where a value is not
    /// knowable. A `0` here would tell a user with a full index that the app
    /// remembers nothing about them.
    static let unknownCount = "—"

    /// **An honest bound, not a silent one** (#422 final review, I4). The
    /// earlier fix made RECENTLY USED unbounded to satisfy "every
    /// `MemoryUseRecord`", which traded a silent cap for an unbounded render:
    /// a non-lazy stack plus one store resolve per source per refresh, growing
    /// with the user's whole history. The list is bounded again — but it SAYS
    /// so, with the true total, which is the difference between a limit and a
    /// lie.
    static let recentlyUsedLimit = 50

    /// `nonisolated` because `SourceRow` — a nested VALUE type, and therefore
    /// outside this class's actor — builds its own words from them.
    nonisolated static let dontUseThisLabel = "Don't use this"
    nonisolated static let useAgainLabel = "Use again"
    nonisolated static let excludedMarker = "Excluded"

    // MARK: Rows

    struct NoteRow: Identifiable, Equatable {
        let id: UUID
        let text: String
        /// `You told me on <date>`, plus ` · edited <date>` once it has been
        /// edited — the text on screen is then no longer what the user first
        /// said, and the row owes them that.
        let savedLine: String
        let truncationNotice: String?
    }

    /// One memory a reply drew on. Carries its own id because the row is
    /// actionable (*Don't use this*), which the provenance sheet's row is not.
    struct SourceRow: Identifiable, Equatable {
        enum Kind: Equatable { case entry, note }
        let id: UUID
        let kind: Kind
        /// The user's own words, verbatim (ruling 1). `nil` when the row is
        /// gone — the line then says so rather than rendering blank.
        let text: String?
        let sourceLine: String
        /// Whether retrieval is currently forbidden to draw on this row.
        ///
        /// **The row has to SAY this** (fix round 1, Important item 3). Before
        /// it did, *Don't use this* wrote the flag and then re-rendered an
        /// identical row with an identical button: nothing confirmed the tap
        /// landed, and nothing offered a way back. Exclusion is not a delete —
        /// the words are still the user's and still quotable — so the row
        /// stays and changes its state instead of disappearing.
        let isExcluded: Bool

        /// Only an indexed turn that still exists can be excluded from
        /// retrieval: a note is deleted rather than excluded, and a row that
        /// is already gone has nothing left to hide.
        var isExcludable: Bool { kind == .entry && text != nil }
        var canExclude: Bool { isExcludable && !isExcluded }
        var canUseAgain: Bool { isExcludable && isExcluded }

        /// The button's words, or `nil` when there is no action to offer.
        var actionLabel: String? {
            if canExclude { return MemoryScreenModel.dontUseThisLabel }
            if canUseAgain { return MemoryScreenModel.useAgainLabel }
            return nil
        }

        /// What the row says about itself, exclusion included.
        var statusLine: String {
            isExcluded ? "\(MemoryScreenModel.excludedMarker) · \(sourceLine)" : sourceLine
        }
    }

    struct UseRow: Identifiable, Equatable {
        /// The reply's own `Message.id` — the key the store records against.
        let id: UUID
        let at: Date
        let sources: [SourceRow]
        /// When the reply that used these memories was answered.
        ///
        /// The list is GROUPED by reply rather than flattened (fix round 1
        /// minor): two replies can draw on the same memory, and a flat list
        /// would show the identical row twice with nothing to tell them apart
        /// — which reads as a duplicate-rendering bug rather than as two
        /// occasions.
        var usedLine: String { "Used on \(MemoryProvenanceSheetModel.dateLabel(at))" }
    }

    // MARK: Dependencies

    /// Everything the screen touches, as closures. Defaults describe an empty,
    /// storeless install, so a partially-wired model is honest rather than
    /// crashy.
    struct Dependencies {
        var notes: () -> [(noteID: UUID, text: String, createdAt: Date,
                           editedAt: Date?, wasTruncated: Bool)] = { [] }
        var uses: () -> [(replyMessageID: UUID, store: String,
                          entryIDs: [UUID], noteIDs: [UUID], at: Date)] = { [] }
        var resolveEntry: (UUID) -> (text: String, sentAt: Date)? = { _ in nil }
        var resolveNote: (UUID) -> (text: String, createdAt: Date)? = { _ in nil }
        /// `nil` = not knowable (no store), which renders as `—`.
        var indexCount: () -> Int? = { nil }
        var indexedMessageCount: () -> Int? = { nil }
        /// The entry ids retrieval is currently forbidden to use.
        var excludedEntryIDs: () -> Set<UUID> = { [] }
        var setExcluded: (UUID, Bool) -> Void = { _, _ in }
        var deleteNote: (UUID) -> Void = { _ in }
        var updateNote: (UUID, String) -> Void = { _, _ in }
        var forgetEverything: () -> Void = { }
        var isMemoryEnabled: () -> Bool = { true }
        var setMemoryEnabled: (Bool) -> Void = { _ in }
        var hostConfigured: () -> Bool = { false }
    }

    private let dependencies: Dependencies

    // MARK: State

    private(set) var noteRows: [NoteRow] = []
    /// The rows the screen RENDERS — at most `recentlyUsedLimit` of them.
    private(set) var useRows: [UseRow] = []
    /// How many use records the store actually holds, which is what
    /// `recentlyUsedNotice` reports and what makes the bound honest.
    private(set) var totalUseCount = 0

    /// `nil` until `refresh()` has actually read a count, and for a screen with
    /// no store at all. **Not zero** — see `unknownCount`.
    private(set) var indexCount: Int?
    private(set) var indexedMessageCount: Int?

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    /// The production wiring. A `nil` store is the container-creation-failure
    /// shape and stays a first-class state: nothing resolves, every count is
    /// unknown, and no write goes anywhere.
    /// - Parameter forgetEverything: how to forget, WHOLE. Defaults to the
    ///   store's own erase, which is right for a test and NOT right for the
    ///   app: production passes `AppContainer.forgetLocalMemory`, which also
    ///   parks the backfill cursor and stops an in-flight walk (fix round 1,
    ///   Important item 2). Erasing the rows alone leaves a cursor pointing
    ///   into the middle of the user's history, and the next launch walks the
    ///   forgotten sessions straight back in.
    convenience init(store: MemoryStore?,
                     settingsStore: SettingsStore? = nil,
                     hostConfigured: Bool = false,
                     forgetEverything: (() -> Void)? = nil) {
        var dependencies = Dependencies()
        if let store {
            dependencies.notes = { store.allNotes() }
            // Unbounded from the STORE, bounded by the SCREEN with a line that
            // names the total (I4). Fetching everything is what lets the count
            // be true; rendering everything is what made it expensive.
            dependencies.uses = { store.recentUses(limit: nil) }
            dependencies.resolveEntry = { store.turnEntry(id: $0) }
            dependencies.resolveNote = { store.note(id: $0) }
            dependencies.indexCount = { store.indexCount() }
            dependencies.indexedMessageCount = { store.indexedMessageCount() }
            dependencies.excludedEntryIDs = { store.excludedEntryIDs() }
            // MESSAGE-level (I6): a long turn is several rows, and hiding only
            // the chunk that happened to be retrieved leaves its siblings
            // feeding the prompt.
            dependencies.setExcluded = { store.setExcludedForEntry($0, $1) }
            dependencies.deleteNote = { store.deleteNote($0) }
            dependencies.updateNote = { store.updateNote($0, text: $1) }
            dependencies.forgetEverything = { store.forgetEverything() }
        }
        if let forgetEverything { dependencies.forgetEverything = forgetEverything }
        if let settingsStore {
            // Read LIVE rather than captured, the same discipline as
            // `ChatStore.isMemoryEnabled`: the toggle the user just flipped on
            // another screen must be what this one shows.
            dependencies.isMemoryEnabled = { settingsStore.settings.memoryEnabled }
            dependencies.setMemoryEnabled = { settingsStore.settings.memoryEnabled = $0 }
        }
        dependencies.hostConfigured = { hostConfigured }
        self.init(dependencies: dependencies)
    }

    // MARK: Derived copy

    var indexCountText: String {
        indexCount.map(String.init) ?? Self.unknownCount
    }

    /// The corpus sentence, in the user's own vocabulary: they wrote MESSAGES.
    /// Backed by `MemoryStore.indexedMessageCount()` rather than the row count
    /// beside it, because one long message is several rows and reporting rows
    /// under this wording would inflate the number.
    ///
    /// `nil` while the count is unknown or genuinely zero — there is no honest
    /// sentence to draw from a number nobody has read, and an empty store is
    /// what `emptyMessage` is for.
    var indexSummary: String? {
        guard let count = indexedMessageCount, count > 0 else { return nil }
        return "Talaria can draw on the \(count) message\(count == 1 ? "" : "s") "
            + "you've sent in on-device chats"
    }

    /// `nil` when everything is on screen; otherwise the line that says what
    /// is not. Never silently truncate a list about someone's own data.
    var recentlyUsedNotice: String? {
        guard totalUseCount > Self.recentlyUsedLimit else { return nil }
        return "Showing the most recent \(Self.recentlyUsedLimit) of \(totalUseCount)"
    }

    var hostLine: String? {
        dependencies.hostConfigured() ? Self.hostLine : nil
    }

    /// **A real, READ zero** (fix round 1, Important item 4). It used to
    /// coalesce an unknown count to 0, so a screen with no store at all said
    /// `Nothing saved yet` and `—` in the same render: one half claiming the
    /// store is empty, the other admitting we cannot see it. Unknown is not
    /// empty, and the copy is a claim about the user's data.
    var isEmpty: Bool {
        noteRows.isEmpty && useRows.isEmpty && indexCount == 0
    }

    /// Non-nil exactly when the screen has nothing to list, so the view can
    /// never render an empty scroll view and call it done.
    var emptyMessage: String? { isEmpty ? Self.emptyCopy : nil }

    var isMemoryEnabled: Bool { dependencies.isMemoryEnabled() }

    // MARK: Reads

    func refresh() {
        indexCount = dependencies.indexCount()
        indexedMessageCount = dependencies.indexedMessageCount()
        let excluded = dependencies.excludedEntryIDs()
        noteRows = dependencies.notes().map { note in
            NoteRow(
                id: note.noteID,
                text: note.text,
                savedLine: Self.savedLine(createdAt: note.createdAt, editedAt: note.editedAt),
                truncationNotice: note.wasTruncated ? Self.truncationNotice : nil)
        }
        let allUses = dependencies.uses()
        totalUseCount = allUses.count
        useRows = allUses.prefix(Self.recentlyUsedLimit).map { use in
            var sources = use.entryIDs.map { id -> SourceRow in
                guard let entry = dependencies.resolveEntry(id) else { return Self.deletedRow(id, .entry) }
                return SourceRow(
                    id: id, kind: .entry, text: entry.text,
                    sourceLine: "From your chat on \(MemoryProvenanceSheetModel.dateLabel(entry.sentAt))",
                    isExcluded: excluded.contains(id))
            }
            sources += use.noteIDs.map { id -> SourceRow in
                guard let note = dependencies.resolveNote(id) else { return Self.deletedRow(id, .note) }
                return SourceRow(
                    id: id, kind: .note, text: note.text,
                    sourceLine: "You told me on \(MemoryProvenanceSheetModel.dateLabel(note.createdAt))",
                    isExcluded: false)
            }
            return UseRow(id: use.replyMessageID, at: use.at, sources: sources)
        }
    }

    // MARK: Writes

    /// *Don't use this* — the row stays in the store (exclusion is not a
    /// delete; Forget everything is the only eraser) but leaves the retrieval
    /// candidate set, so the very next turn cannot draw on it.
    func excludeEntry(_ entryID: UUID) {
        dependencies.setExcluded(entryID, true)
        refresh()
    }

    /// *Use again* — the way back. Exclusion is reversible by construction
    /// (the row was never deleted), and a one-way switch on a list of one's
    /// own memories is a trap: the user has no other route to that row.
    func restoreEntry(_ entryID: UUID) {
        dependencies.setExcluded(entryID, false)
        refresh()
    }

    func deleteNote(_ noteID: UUID) {
        dependencies.deleteNote(noteID)
        refresh()
    }

    /// Edits a note. **Returns whether the edit was applied** (fix round 1
    /// minor): an emptied edit is refused — deleting is the Delete action, and
    /// a note whose text is blank is a row the user can never find again — but
    /// a refusal that returned nothing let the sheet dismiss as though it had
    /// saved. The caller now knows, and the sheet's Save is disabled on empty
    /// so the refusal is visible before it happens rather than after.
    @discardableResult
    func updateNote(_ noteID: UUID, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        dependencies.updateNote(noteID, trimmed)
        refresh()
        return true
    }

    func setMemoryEnabled(_ enabled: Bool) {
        dependencies.setMemoryEnabled(enabled)
    }

    /// Owen's ruling: this is the ONLY reset. It erases all three entities and
    /// the screen then states its emptiness — a re-read rather than a local
    /// clear, so what the screen shows afterwards is what the store actually
    /// holds.
    func forgetEverything() {
        dependencies.forgetEverything()
        refresh()
    }

    // MARK: Line building

    private static func savedLine(createdAt: Date, editedAt: Date?) -> String {
        let base = "You told me on \(MemoryProvenanceSheetModel.dateLabel(createdAt))"
        guard let editedAt else { return base }
        return base + " · edited \(MemoryProvenanceSheetModel.dateLabel(editedAt))"
    }

    private static func deletedRow(_ id: UUID, _ kind: SourceRow.Kind) -> SourceRow {
        // The provenance sheet's own words, borrowed rather than re-spelled:
        // two surfaces saying the same thing about the same absence.
        SourceRow(id: id, kind: kind, text: nil,
                  sourceLine: MemoryProvenanceSheetModel.deletedSourceLine,
                  isExcluded: false)
    }
}

// MARK: - The screen

struct MemoryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore

    @State private var model: MemoryScreenModel?
    @State private var showForgetConfirm = false
    @State private var editingNote: MemoryScreenModel.NoteRow?
    @State private var editingText = ""

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: MemoryScreenModel.title,
                                         subtitle: MemoryScreenModel.subtitle) { dismiss() }
                    if let model {
                        if let empty = model.emptyMessage {
                            emptyPanel(empty)
                        } else {
                            notesSection(model)
                            recentlyUsedSection(model)
                        }
                        indexSection(model)
                        if let hostLine = model.hostLine {
                            footerNote(hostLine)
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle(MemoryScreenModel.title)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                model = MemoryScreenModel(
                    store: container.memoryStore,
                    settingsStore: settingsStore,
                    hostConfigured: container.hasGatewayCredentials,
                    // NOT `store.forgetEverything()` — forgetting is also
                    // parking the backfill cursor and stopping an in-flight
                    // walk, or the erased history comes back on the next
                    // launch (fix round 1, Important item 2).
                    // Captured strongly on purpose: the environment holds the
                    // container for this view's whole life, the container holds
                    // no reference back to this model, and a `weak` capture here
                    // only earns an ImplicitStrongCapture warning for a cycle
                    // that does not exist.
                    forgetEverything: { container.forgetLocalMemory() })
            }
            model?.refresh()
        }
        // #193: destructive confirmations are `.alert`, not
        // `.confirmationDialog` — the cancel role does not render on iOS 26/27.
        .alert("Forget everything?", isPresented: $showForgetConfirm) {
            Button("Forget Everything", role: .destructive) { model?.forgetEverything() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes every note and every indexed message on this device. "
                 + "This cannot be undone.")
        }
        .sheet(item: $editingNote) { note in
            editSheet(note)
        }
    }

    // MARK: NOTES

    @ViewBuilder
    private func notesSection(_ model: MemoryScreenModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Notes", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                if model.noteRows.isEmpty {
                    infoRow("No notes yet")
                } else {
                    ForEach(Array(model.noteRows.enumerated()), id: \.element.id) { index, note in
                        noteRow(model, note)
                        if index < model.noteRows.count - 1 { divider }
                    }
                }
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func noteRow(_ model: MemoryScreenModel, _ note: MemoryScreenModel.NoteRow) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Text(note.text)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            MonoLabel(note.savedLine, size: 9, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            if let notice = note.truncationNotice {
                MonoLabel(notice, size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.forgeText)
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") {
                editingText = note.text
                editingNote = note
            }
            Button("Delete", role: .destructive) { model.deleteNote(note.id) }
        }
    }

    private func editSheet(_ note: MemoryScreenModel.NoteRow) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                MonoLabel("// Your words, kept verbatim", size: 10,
                          tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                TextEditor(text: $editingText)
                    .font(Design.Typography.callout)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(Design.Spacing.sm)
                    .hudPanel(
                        cornerRadius: Design.CornerRadius.md,
                        borderColor: Design.Colors.accentTint(0.14),
                        fill: Design.Colors.background.opacity(0.5),
                        innerGlow: false
                    )
                Spacer()
            }
            .padding(Design.Spacing.md)
            .background(Design.Colors.background)
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingNote = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // The model refuses an emptied edit (deleting is the
                        // Delete action). Only dismiss when it took.
                        if model?.updateNote(note.id, text: editingText) == true {
                            editingNote = nil
                        }
                    }
                    // Disabled rather than silently refused: the refusal is
                    // visible BEFORE the tap, not after a sheet has closed on
                    // an edit that never saved (fix round 1 minor).
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: RECENTLY USED

    @ViewBuilder
    private func recentlyUsedSection(_ model: MemoryScreenModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Recently used", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            LazyVStack(spacing: 0) {
                if model.useRows.isEmpty {
                    infoRow("No reply has drawn on memory yet")
                } else {
                    // Grouped by REPLY, not flattened: two replies can draw on
                    // the same memory, and one flat list would render the same
                    // row twice with nothing to tell them apart.
                    ForEach(Array(model.useRows.enumerated()), id: \.element.id) { index, use in
                        VStack(alignment: .leading, spacing: 0) {
                            MonoLabel(use.usedLine, size: 9, weight: .medium,
                                      tracking: Design.Tracking.monoWide,
                                      color: Design.Colors.dimForeground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Design.Spacing.md)
                                .padding(.top, Design.Spacing.sm)
                            ForEach(use.sources) { source in
                                sourceRow(model, source)
                            }
                        }
                        if index < model.useRows.count - 1 { divider }
                    }
                    if let notice = model.recentlyUsedNotice {
                        divider
                        MonoLabel(notice, size: 9, weight: .medium,
                                  tracking: Design.Tracking.monoWide,
                                  color: Design.Colors.mutedForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.vertical, Design.Spacing.sm)
                    }
                }
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func sourceRow(_ model: MemoryScreenModel,
                           _ source: MemoryScreenModel.SourceRow) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            if let text = source.text {
                Text(text)
                    .font(Design.Typography.callout)
                    .foregroundStyle(source.isExcluded
                                     ? Design.Colors.mutedForeground
                                     : Design.Colors.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Design.Spacing.sm) {
                MonoLabel(source.statusLine, size: 9, weight: .medium,
                          tracking: Design.Tracking.mono,
                          color: source.text == nil
                              ? Design.Colors.dimForeground
                              : source.isExcluded
                                  ? Design.Brand.forgeText
                                  : Design.Colors.mutedForeground)
                Spacer(minLength: Design.Spacing.xs)
                if let action = source.actionLabel {
                    Button(action) {
                        if source.isExcluded {
                            model.restoreEntry(source.id)
                        } else {
                            model.excludeEntry(source.id)
                        }
                    }
                    .font(Design.Typography.caption)
                    .foregroundStyle(source.isExcluded
                                     ? Design.Brand.accentBrightText
                                     : Design.Colors.dangerBrightText)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    // MARK: INDEX

    private func indexSection(_ model: MemoryScreenModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Index", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                HStack(spacing: Design.Spacing.sm) {
                    Text("Memory")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isMemoryEnabled },
                        set: { model.setMemoryEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(Design.Brand.accentText)
                }
                Text("Off stops both remembering and drawing on memory. What is already "
                     + "stored is kept — Forget everything is the only eraser.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)

                HStack(spacing: Design.Spacing.sm) {
                    MonoLabel("INDEXED ENTRIES", size: 9, weight: .medium,
                              tracking: Design.Tracking.monoWide,
                              color: Design.Colors.mutedForeground)
                    Spacer()
                    MonoLabel(model.indexCountText, size: 11, weight: .medium,
                              tracking: Design.Tracking.mono,
                              color: Design.Brand.accentBrightText)
                }
                if let summary = model.indexSummary {
                    Text(summary)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
            }
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )

            forgetRow
        }
    }

    private var forgetRow: some View {
        Button {
            showForgetConfirm = true
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Text("Forget Everything")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.dangerBrightText)
                Spacer()
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Colors.dangerBrightText)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Design.Colors.danger.opacity(0.07),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.md)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.danger.opacity(0.34), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared bits

    private func emptyPanel(_ copy: String) -> some View {
        Text(copy)
            .font(Design.Typography.callout)
            .foregroundStyle(Design.Colors.secondaryForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
    }

    private func infoRow(_ text: String) -> some View {
        HStack {
            MonoLabel(text, size: 10, tracking: Design.Tracking.mono,
                      color: Design.Colors.mutedForeground)
            Spacer()
        }
        .padding(Design.Spacing.md)
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.hairline)
            .frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    private func footerNote(_ text: String) -> some View {
        Text(text)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Colors.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Design.Spacing.xs)
    }
}
