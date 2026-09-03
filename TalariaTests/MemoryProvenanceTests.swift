import Foundation
import Testing
@testable import Talaria

/// #422 bar 422-P (chip half) — the provenance chip beside the brain tag, its
/// accessibility label, and the tap-through source sheet.
///
/// Ruling 2 in its positive form: **every memory a reply drew on is visible,
/// with a RESOLVABLE source.** The failure this suite exists to make loud is
/// the quiet one — a chip that claims the reply used memory, a sheet that
/// lists a row, and a source line that renders as nothing because the entry
/// behind it was deleted. A blank line reads as "no source" and is
/// indistinguishable from a layout bug; `source deleted` is a statement.
///
/// Everything here is asserted at the VIEW-MODEL level (the shape
/// `ToolProvenanceTests` uses for the ✓-chip decision functions): the strings
/// and the row list are pure values, so the pins do not depend on SwiftUI
/// rendering and cannot go green against a view that never draws them.
@Suite("422-P provenance chip")
@MainActor
struct MemoryProvenanceTests {

    // MARK: - Fixtures

    private static let entryA = UUID()
    private static let entryB = UUID()
    private static let noteA = UUID()

    /// A resolver pair that knows exactly the ids it was handed and nothing
    /// else — so an id it does NOT know takes the deleted-source path, which
    /// is the same path a real store takes for a row that is gone.
    private func resolvers(
        entries: [UUID: (text: String, sentAt: Date)] = [:],
        notes: [UUID: (text: String, createdAt: Date)] = [:]
    ) -> (entry: (UUID) -> (text: String, sentAt: Date)?,
          note: (UUID) -> (text: String, createdAt: Date)?) {
        ({ entries[$0] }, { notes[$0] })
    }

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    private static let sentAt = date("2026-08-14T09:30:00Z")

    /// The date exactly as the sheet renders it — read from the same
    /// `.medium`-style formatter rather than hardcoded, so the pins assert the
    /// SHAPE of the line ("From your chat on <that date>") without also
    /// pinning the test host's locale.
    private static func rendered(_ date: Date) -> String {
        MemoryProvenanceSheetModel.dateLabel(date)
    }

    // MARK: - The chip label (422-P: distinct pinned labels per case)

    @Test func aLocalReplyThatDrewOnMemorySaysOnDeviceMemory() {
        let model = MemoryProvenanceChipModel(
            provenance: .local(entryIDs: [Self.entryA], noteIDs: [], savedNoteID: nil))
        #expect(model.label == "ON-DEVICE MEMORY")
    }

    @Test func aTurnThatSavedANoteSaysSavedToMemory() {
        let model = MemoryProvenanceChipModel(
            provenance: .local(entryIDs: [], noteIDs: [], savedNoteID: Self.noteA))
        #expect(model.label == "SAVED TO MEMORY")
    }

    @Test func aHostReplyNamesTheMemoryToolThatRan() {
        let model = MemoryProvenanceChipModel(
            provenance: .host(observedTools: ["honcho_search"]))
        #expect(model.label == "HERMES MEMORY · honcho_search")
    }

    /// The bar's own words: `.local` and `.host` render DISTINCT pinned
    /// labels. One label for both would make the transcript claim the host
    /// remembered something the phone remembered, which is ruling 3's
    /// never-merged rule failing in the only place the user can see it.
    @Test func theLocalAndHostChipsAreNeverTheSameWords() {
        let local = MemoryProvenanceChipModel(
            provenance: .local(entryIDs: [Self.entryA], noteIDs: [], savedNoteID: nil))
        let host = MemoryProvenanceChipModel(provenance: .host(observedTools: ["honcho_search"]))
        #expect(local.label != host.label)
        #expect(!local.label.contains("HERMES"),
                "on-device memory never says Hermes — the outward identity is Talaria")
    }

    // MARK: - #371-E: the a11y label carries the same words

    @Test func theAccessibilityLabelCarriesTheChipsOwnWords() {
        for provenance: MemoryProvenance in [
            .local(entryIDs: [Self.entryA], noteIDs: [], savedNoteID: nil),
            .local(entryIDs: [], noteIDs: [], savedNoteID: Self.noteA),
            .host(observedTools: ["honcho_search"]),
        ] {
            let model = MemoryProvenanceChipModel(provenance: provenance)
            #expect(model.accessibilityLabel.contains(model.label),
                    "#371-E: VoiceOver must hear the same claim the chip makes, not a paraphrase")
            #expect(model.accessibilityLabel != model.label,
                    "the label alone does not say the chip is tappable")
        }
    }

    // MARK: - No provenance ⇒ no chip

    @Test func aReplyThatDrewOnNoMemoryMintsNoChip() {
        #expect(MemoryProvenanceChipModel.model(for: nil) == nil,
                "nil is what every pre-#422 cached row decodes to — it must render nothing")
        #expect(MemoryProvenanceChipModel.model(
            for: .local(entryIDs: [Self.entryA], noteIDs: [], savedNoteID: nil)) != nil)
    }

    // MARK: - The sheet: every referenced memory is visible

    @Test func everyReferencedEntryAndNoteGetsItsOwnResolvableSourceLine() {
        let resolve = resolvers(
            entries: [Self.entryA: ("my dentist is Dr. Patel", Self.sentAt),
                      Self.entryB: ("I fly out on the 3rd", Self.sentAt)],
            notes: [Self.noteA: ("I am allergic to penicillin", Self.sentAt)])
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [Self.entryA, Self.entryB],
                               noteIDs: [Self.noteA], savedNoteID: nil),
            resolveEntry: resolve.entry, resolveNote: resolve.note)

        #expect(sheet.rows.count == 3, "three memories were injected — three rows")
        #expect(sheet.rows[0].sourceLine == "From your chat on \(Self.rendered(Self.sentAt))")
        #expect(sheet.rows[0].text == "my dentist is Dr. Patel")
        #expect(sheet.rows[1].text == "I fly out on the 3rd")
        #expect(sheet.rows[2].sourceLine == "You told me on \(Self.rendered(Self.sentAt))",
                "an explicit note is not a chat turn and must not claim to be one")
        #expect(sheet.rows[2].text == "I am allergic to penicillin")
    }

    /// RED-FIRST, and the reason this task exists: an id whose row is gone
    /// must render `source deleted`, NEVER a blank line.
    @Test func anEntryWhoseRowIsGoneRendersSourceDeletedNeverBlank() {
        let resolve = resolvers()   // knows nothing — every id is unresolvable
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [Self.entryA], noteIDs: [], savedNoteID: nil),
            resolveEntry: resolve.entry, resolveNote: resolve.note)

        #expect(sheet.rows.count == 1, "the reference is still visible — ruling 2 has no silent drop")
        #expect(!sheet.rows[0].sourceLine.isEmpty,
                "a blank source line is indistinguishable from a layout bug")
        #expect(sheet.rows[0].sourceLine == "source deleted")
        #expect(sheet.rows[0].text == nil, "there is no text to quote for a row that is gone")
    }

    @Test func aNoteWhoseRowIsGoneRendersSourceDeletedToo() {
        let resolve = resolvers()
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [], noteIDs: [Self.noteA], savedNoteID: nil),
            resolveEntry: resolve.entry, resolveNote: resolve.note)
        #expect(sheet.rows.map(\.sourceLine) == ["source deleted"])
    }

    @Test func aPartlyDeletedSetKeepsTheSurvivorsResolvable() {
        let resolve = resolvers(entries: [Self.entryB: ("I fly out on the 3rd", Self.sentAt)])
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [Self.entryA, Self.entryB], noteIDs: [], savedNoteID: nil),
            resolveEntry: resolve.entry, resolveNote: resolve.note)
        #expect(sheet.rows.map(\.sourceLine) == [
            "source deleted",
            "From your chat on \(Self.rendered(Self.sentAt))",
        ], "order is entryIDs as given — a deleted row does not reshuffle the survivors")
    }

    // MARK: - The sheet: host provenance

    @Test func hostProvenanceListsOneRowPerObservedTool() {
        let resolve = resolvers()
        let sheet = MemoryProvenanceSheetModel(
            provenance: .host(observedTools: ["honcho_search", "honcho_get"]),
            resolveEntry: resolve.entry, resolveNote: resolve.note)
        #expect(sheet.rows.map(\.sourceLine) == [
            "Reported by the host: honcho_search",
            "Reported by the host: honcho_get",
        ])
        #expect(sheet.rows.allSatisfy { $0.text == nil },
                "the host's rows never live here — quoting text would invent one (ruling 3)")
    }

    // MARK: - The note this turn SAVED

    /// "SAVED TO MEMORY" with an empty sheet is the blank ruling 2 forbids,
    /// one level up: the chip makes a claim and the tap-through shows nothing.
    /// The saved note is a memory the reply produced, so it is listed.
    @Test func theNoteThisTurnSavedIsVisibleEvenWhenTheReplyDrewOnNothingElse() {
        let resolve = resolvers(notes: [Self.noteA: ("I am allergic to penicillin", Self.sentAt)])
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [], noteIDs: [], savedNoteID: Self.noteA),
            resolveEntry: resolve.entry, resolveNote: resolve.note)
        #expect(sheet.rows.count == 1)
        #expect(sheet.rows[0].sourceLine == "You told me on \(Self.rendered(Self.sentAt))")
        #expect(sheet.rows[0].text == "I am allergic to penicillin")
    }

    @Test func aSavedNoteThatWasAlsoInjectedIsListedOnce() {
        let resolve = resolvers(notes: [Self.noteA: ("I am allergic to penicillin", Self.sentAt)])
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [], noteIDs: [Self.noteA], savedNoteID: Self.noteA),
            resolveEntry: resolve.entry, resolveNote: resolve.note)
        #expect(sheet.rows.count == 1, "one note, one row — the same memory twice reads as two")
    }

    @Test func provenanceReferencingNothingYieldsNoRowsSoTheSheetCanSaySoHonestly() {
        let resolve = resolvers()
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [], noteIDs: [], savedNoteID: nil),
            resolveEntry: resolve.entry, resolveNote: resolve.note)
        #expect(sheet.rows.isEmpty)
    }

    // MARK: - Resolution through the real store (MemoryStore+Lookup)

    /// The lookup reads a row the INDEXER wrote, by the id provenance carries.
    /// Building the record through the store's own upsert (rather than poking
    /// the context) keeps the pin on the path production uses.
    @Test func theStoreResolvesAnIndexedTurnByItsEntryID() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let entryID = UUID()
        store.upsertTurnChunks([Self.turnChunk(entryID: entryID,
                                               text: "my dentist is Dr. Patel",
                                               sentAt: Self.sentAt)])

        let resolved = try #require(store.turnEntry(id: entryID))
        #expect(resolved.text == "my dentist is Dr. Patel")
        #expect(resolved.sentAt == Self.sentAt)
    }

    /// ⚠️ OWED: `note(id:)`'s POSITIVE path has no store-level pin, because
    /// nothing in the tree writes a `MemoryNoteRecord` yet — the note writer is
    /// a later task in this lane. Seeding one here would have meant either a
    /// test-only writer on `MemoryStore` or reaching into its private context,
    /// and a test-only production API is the smell this fix round removed
    /// elsewhere. **Whichever task adds the note writer must add the pin**:
    /// write a note, then `#expect(store.note(id:)?.text == …)`.
    ///
    /// What IS covered meanwhile: the nil path below (same method), the whole
    /// note branch of the sheet through injected resolvers (four tests above),
    /// and the identically-shaped `turnEntry(id:)` positive path.

    @Test func anIDTheStoreHasNeverSeenResolvesToNil() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        #expect(store.turnEntry(id: UUID()) == nil)
        #expect(store.note(id: UUID()) == nil)
    }

    /// End to end on the path the sheet actually takes: a real store, a
    /// reference to a row it does not hold, and the honest line.
    @Test func aReferenceTheRealStoreCannotResolveRendersSourceDeleted() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let kept = UUID()
        store.upsertTurnChunks([Self.turnChunk(entryID: kept, text: "kept", sentAt: Self.sentAt)])

        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [kept, UUID()], noteIDs: [], savedNoteID: nil),
            resolveEntry: { store.turnEntry(id: $0) },
            resolveNote: { store.note(id: $0) })
        #expect(sheet.rows.map(\.text) == ["kept", nil])
        #expect(sheet.rows[1].sourceLine == "source deleted")
    }

    /// No store at all (a bare container, or a failed SwiftData create) is not
    /// a licence to render blanks either.
    @Test func aMissingStoreStillRendersSourceDeletedForEveryRow() {
        let sheet = MemoryProvenanceSheetModel(
            provenance: .local(entryIDs: [Self.entryA], noteIDs: [Self.noteA], savedNoteID: nil),
            store: nil)
        #expect(sheet.rows.map(\.sourceLine) == ["source deleted", "source deleted"])
    }

    // MARK: - Row construction helpers
    //
    // Text-only initialiser — the embedder was deleted by ruling (bar 422-R,
    // 2026-09-03): no `embedderID`/`vector` columns exist on
    // `MemoryTurnIndexRecord` any more, so this fixture no longer spells them.

    private static func turnChunk(entryID: UUID, text: String, sentAt: Date) -> MemoryTurnIndexRecord {
        MemoryTurnIndexRecord(entryID: entryID, sessionID: UUID(), messageID: UUID(),
                              chunkIndex: 0, text: text, sentAt: sentAt)
    }
}
