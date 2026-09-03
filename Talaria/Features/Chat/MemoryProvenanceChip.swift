import SwiftUI

// MARK: - #422 bar 422-P: the memory provenance chip
//
// Ruling 2 says every memory a reply drew on is VISIBLE, with a resolvable
// source. That is two surfaces: a chip beside the brain tag saying which
// memory answered — on-device, saved, or the host's — and a tap-through sheet
// naming each memory it used, in the user's own words, with the day they said
// them.
//
// The strings and the row list are pure values (`MemoryProvenanceChipModel`,
// `MemoryProvenanceSheetModel`) rather than expressions inside a view body, so
// bar 422-P is pinned without rendering anything. A view-body-only chip would
// have to be asserted through XCUITest, which cannot see the case that matters
// most here: an id whose row is gone.

// MARK: - Chip view model

/// What the chip says, and what VoiceOver hears it say.
///
/// #371-E: the accessibility label carries the SAME WORDS as the chip. A
/// paraphrase is how a label drifts from the claim on screen — the ✓-chip lane
/// learned that in its own form, where the spoken label kept asserting a
/// completion the rendering had already softened.
struct MemoryProvenanceChipModel: Equatable {
    /// Verbatim per #422's naming ruling — the enum owns the strings so the
    /// chip and any other surface cannot drift apart.
    let label: String
    let accessibilityLabel: String

    init(provenance: MemoryProvenance) {
        let label = provenance.chipLabel
        self.label = label
        self.accessibilityLabel = "\(label). Tap to see the sources."
    }

    /// `nil` provenance ⇒ NO chip. That is not a styling choice: `nil` is what
    /// every pre-#422 cached row decodes to (`decodeIfPresent`, the #42
    /// silent-wipe rule), and a chip on those would assert a memory the reply
    /// never had.
    static func model(for provenance: MemoryProvenance?) -> MemoryProvenanceChipModel? {
        provenance.map(MemoryProvenanceChipModel.init(provenance:))
    }
}

// MARK: - Sheet view model

/// The tap-through list: one row per memory the reply referenced, in the order
/// the provenance carries them (indexed turns, then explicit notes, then the
/// note this turn saved if it is not already among them).
///
/// **A row is never dropped and never blank.** An id whose row has been
/// deleted — `reconcileSession` removes the rows of a message the user
/// retried, undid, or regenerated away — still appears, saying `source
/// deleted`. Dropping it would quietly shrink the list under a chip that
/// claims memory was used; blanking the line would look like a layout bug. The
/// honest statement is that the source is gone.
struct MemoryProvenanceSheetModel: Equatable {

    /// One memory. `text` is the user's own words, verbatim (ruling 1 — nothing
    /// in this path paraphrases); `nil` when there are none to quote, which is
    /// both the deleted-source case and every host row.
    struct Row: Equatable, Hashable {
        let sourceLine: String
        let text: String?
    }

    let rows: [Row]

    /// The line an unresolvable id renders. Lowercase and sentence-shaped on
    /// purpose: it is a statement about this row, not a HUD label.
    static let deletedSourceLine = "source deleted"

    init(provenance: MemoryProvenance,
         resolveEntry: (UUID) -> (text: String, sentAt: Date)?,
         resolveNote: (UUID) -> (text: String, createdAt: Date)?) {
        switch provenance {
        case .local(let entryIDs, let noteIDs, let savedNoteID):
            var rows = entryIDs.map { id -> Row in
                guard let entry = resolveEntry(id) else { return Self.deletedRow }
                return Row(sourceLine: "From your chat on \(Self.dateLabel(entry.sentAt))",
                           text: entry.text)
            }
            // The note this turn SAVED is listed too, and it is the reason a
            // "SAVED TO MEMORY" chip is never a chip over an empty sheet — a
            // save is usually the whole of that turn's memory activity, with
            // nothing injected alongside it. Skipped when the same note also
            // rode the injected set: one memory, one row.
            let noteIDs = noteIDs + (savedNoteID.map { noteIDs.contains($0) ? [] : [$0] } ?? [])
            rows += noteIDs.map { id -> Row in
                guard let note = resolveNote(id) else { return Self.deletedRow }
                return Row(sourceLine: "You told me on \(Self.dateLabel(note.createdAt))",
                           text: note.text)
            }
            self.rows = rows

        case .host(let observedTools):
            // Ruling 3: host memory is never merged into the local store, so
            // there is nothing here to resolve and nothing to quote. The chip
            // names the tool that ran; the sheet says who reported it.
            self.rows = observedTools.map { Row(sourceLine: "Reported by the host: \($0)", text: nil) }
        }
    }

    /// The real-store convenience the view uses. A `nil` store — a bare test
    /// container, or a SwiftData container that failed to create — resolves
    /// nothing, so every row states its source is gone rather than rendering
    /// blank.
    @MainActor
    init(provenance: MemoryProvenance, store: MemoryStore?) {
        self.init(provenance: provenance,
                  resolveEntry: { store?.turnEntry(id: $0) },
                  resolveNote: { store?.note(id: $0) })
    }

    private static let deletedRow = Row(sourceLine: deletedSourceLine, text: nil)

    /// Day precision, no time. A source line answers "when did I say this",
    /// and a wall-clock time on a months-old memory reads as false precision.
    // harness-visible — the tests render the same string rather than hardcode a locale.
    static func dateLabel(_ date: Date) -> String { dateFormatter.string(from: date) }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Chip

/// The chip itself: the brain tag's neighbour in the transcript footer, same
/// mono telemetry styling, tapping opens the source sheet.
struct MemoryProvenanceChip: View {
    let provenance: MemoryProvenance

    @State private var isSourcesPresented = false

    var body: some View {
        let model = MemoryProvenanceChipModel(provenance: provenance)
        Button { isSourcesPresented = true } label: {
            MonoLabel(model.label, size: 8, tracking: Design.Tracking.mono,
                      color: Design.Colors.dimForeground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityIdentifier("memory.provenance.chip")
        .sheet(isPresented: $isSourcesPresented) {
            MemoryProvenanceSheet(provenance: provenance)
        }
    }
}

// MARK: - Source sheet

struct MemoryProvenanceSheet: View {
    let provenance: MemoryProvenance

    @Environment(\.dismiss) private var dismiss
    /// Optional on purpose: the sheet renders correctly with no container at
    /// all (previews, bare test hosts, a failed SwiftData create) — every row
    /// simply says its source is gone.
    @Environment(AppContainer.self) private var container: AppContainer?

    var body: some View {
        let model = MemoryProvenanceSheetModel(provenance: provenance,
                                               store: container?.memoryStore)
        VStack(spacing: 0) {
            header
            content(model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { HUDScreenBackground().ignoresSafeArea() }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("MEMORY")
                    .font(Design.Typography.display(22, weight: .semibold, relativeTo: .title2))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                MonoLabel(MemoryProvenanceChipModel(provenance: provenance).label,
                          size: 10, tracking: Design.Tracking.monoWide)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(width: 34, height: 34)
                    .background(Design.Colors.chipSurface,
                                in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close memory sources")
            .accessibilityIdentifier("memory.provenance.close")
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.xl)
        .padding(.bottom, Design.Spacing.md)
    }

    @ViewBuilder
    private func content(_ model: MemoryProvenanceSheetModel) -> some View {
        if model.rows.isEmpty {
            // Real data only: nothing was referenced, so nothing is listed —
            // never a placeholder row standing in for a memory.
            MonoLabel("NO SOURCES RECORDED", size: 10,
                      tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.top, Design.Spacing.xl)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        sourceRow(row)
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xl)
            }
        }
    }

    private func sourceRow(_ row: MemoryProvenanceSheetModel.Row) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            // Sentence-shaped, so a plain caption Text — MonoLabel force-
            // uppercases, which turns "From your chat on 14 Aug 2026" into
            // telemetry.
            Text(row.sourceLine)
                .font(Design.Typography.caption)
                .foregroundStyle(row.text == nil ? Design.Colors.mutedForeground
                                                 : Design.Brand.accentText)
            if let text = row.text {
                // The user's words, verbatim (ruling 1 — nothing in the memory
                // path paraphrases, and that includes this surface).
                Text(text)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        .accessibilityElement(children: .combine)
    }
}
