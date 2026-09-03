import Foundation
import Testing
@testable import Talaria

/// #422 bar 422-P (screen half) — the MEMORY screen's view model.
///
/// Everything the screen renders is asserted here as a VALUE, the same shape
/// `MemoryProvenanceTests` uses for the chip: `MemoryScreenModel` is built
/// from injected closures, so every pin runs without SwiftUI and none of them
/// can go green against a view that never draws the row.
///
/// The failures this suite exists to make loud are the quiet ones the rest of
/// #422 has been chasing all lane:
///
///  - a list that silently SHRINKS (a use record whose entry was deleted
///    dropping out, so the screen under-reports what the app remembered);
///  - a count that reads `0` when it is really UNKNOWN — the placeholder that
///    tells a user with a full index that nothing was ever stored;
///  - a Forget everything that empties the store and leaves a BLANK screen,
///    which is indistinguishable from a crash mid-render;
///  - a *Don't use this* that greys a row out on screen while retrieval keeps
///    drawing on it.
@Suite("422-P memory screen")
@MainActor
struct MemoryScreenTests {

    // MARK: - Fixtures

    private static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// Rendered by the SAME formatter the screen uses (shared with the
    /// provenance sheet), so the pins assert the line's SHAPE without also
    /// pinning the test host's locale.
    private static func rendered(_ date: Date) -> String {
        MemoryProvenanceSheetModel.dateLabel(date)
    }

    private func makeStore() throws -> MemoryStore {
        try #require(MemoryStore.make(inMemoryOnly: true))
    }

    @discardableResult
    private func index(_ store: MemoryStore, _ text: String,
                       sessionID: UUID = UUID(), sentAt: Date = Date()) -> UUID {
        let entryID = UUID()
        store.upsertTurnChunks([
            MemoryTurnIndexRecord(entryID: entryID, sessionID: sessionID, messageID: UUID(),
                                  chunkIndex: 0, text: text, sentAt: sentAt)
        ])
        return entryID
    }

    private func makeSettingsStore() -> (SettingsStore, UserDefaultsAppPersistenceStore) {
        let suiteName = "memory-screen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        return (SettingsStore(persistence: persistence), persistence)
    }

    // MARK: - NOTES

    @Test func notesListsEveryNoteWithTheDayTheUserSaidIt() throws {
        let store = try makeStore()
        store.insertNote("I am allergic to penicillin", sourceMessageID: nil, sourceSessionID: nil)
        store.insertNote("my dentist is Dr. Patel", sourceMessageID: nil, sourceSessionID: nil)

        let model = MemoryScreenModel(store: store)
        model.refresh()

        #expect(model.noteRows.count == 2, "every note is listed — none filtered away")
        #expect(model.noteRows.map(\.text).sorted()
                == ["I am allergic to penicillin", "my dentist is Dr. Patel"])
        #expect(model.noteRows.map(\.id) == store.allNotes().map(\.noteID),
                "the screen keeps the store's newest-first order rather than inventing one")
        let stored = try #require(store.allNotes().first)
        #expect(model.noteRows.first?.savedLine
                == "You told me on \(Self.rendered(stored.createdAt))",
                "a note says when the user said it, not when the row was read")
    }

    @Test func anEditedNoteAlsoSaysWhenItWasEdited() throws {
        let store = try makeStore()
        let id = store.insertNote("my dentist is Dr. Patel",
                                  sourceMessageID: nil, sourceSessionID: nil)
        let created = try #require(store.note(id: id)?.createdAt)
        store.updateNote(id, text: "my dentist is Dr. Okafor")

        let model = MemoryScreenModel(store: store)
        model.refresh()

        let row = try #require(model.noteRows.first)
        let editedAt = try #require(store.allNotes().first?.editedAt)
        #expect(row.savedLine
                == "You told me on \(Self.rendered(created)) · edited \(Self.rendered(editedAt))",
                "an edited note must say so — the text on screen is no longer what the user first said")
        #expect(row.text == "my dentist is Dr. Okafor")
    }

    /// Owen's ruling: a note over the cap is saved as its first 500
    /// characters **with a visible notice**. The flag is the store's
    /// (`wasTruncated`, stamped at capture) — never re-derived here from a
    /// length check, because a note that is genuinely 500 characters long was
    /// not truncated and must not claim it was.
    @Test func aTruncatedNoteCarriesTheNoticeAndAnUntruncatedOneDoesNot() throws {
        let store = try makeStore()
        store.insertNote(String(repeating: "a", count: 500),
                         sourceMessageID: nil, sourceSessionID: nil, wasTruncated: true)
        store.insertNote("short", sourceMessageID: nil, sourceSessionID: nil, wasTruncated: false)

        let model = MemoryScreenModel(store: store)
        model.refresh()

        let cut = try #require(model.noteRows.first { $0.text.count == 500 })
        let whole = try #require(model.noteRows.first { $0.text == "short" })
        #expect(cut.truncationNotice == "Saved the first 500 characters.")
        #expect(whole.truncationNotice == nil,
                "a note the cap never touched must not claim it was cut")
    }

    // MARK: - RECENTLY USED

    @Test func recentlyUsedListsEveryUseNewestFirstWithASourceLinePerMemory() throws {
        let store = try makeStore()
        let sentAt = Self.date("2026-08-14T09:30:00Z")
        let entryID = index(store, "my dentist is Dr. Patel", sentAt: sentAt)
        let noteID = store.insertNote("I am allergic to penicillin",
                                      sourceMessageID: nil, sourceSessionID: nil)
        let noteCreated = try #require(store.note(id: noteID)?.createdAt)

        let older = UUID(), newer = UUID()
        store.recordUse(replyMessageID: older, entryIDs: [entryID], noteIDs: [],
                        at: Self.date("2026-08-20T09:00:00Z"))
        store.recordUse(replyMessageID: newer, entryIDs: [], noteIDs: [noteID],
                        at: Self.date("2026-09-01T09:00:00Z"))

        let model = MemoryScreenModel(store: store)
        model.refresh()

        #expect(model.useRows.map(\.id) == [newer, older], "newest first")
        let noteRow = try #require(model.useRows.first?.sources.first)
        #expect(noteRow.sourceLine == "You told me on \(Self.rendered(noteCreated))",
                "an explicit note is not a chat turn and must not claim to be one")
        #expect(noteRow.text == "I am allergic to penicillin")
        let entryRow = try #require(model.useRows.last?.sources.first)
        #expect(entryRow.sourceLine == "From your chat on \(Self.rendered(sentAt))")
        #expect(entryRow.text == "my dentist is Dr. Patel")
    }

    /// The list must not SHRINK when a source is gone: a reply that drew on
    /// two memories keeps two rows, and the missing one says so.
    @Test func aUseWhoseSourceIsGoneSaysSourceDeletedRatherThanVanishing() throws {
        let store = try makeStore()
        let survivor = index(store, "my dentist is Dr. Patel")
        let doomedSession = UUID()
        let doomed = index(store, "I fly out on the 3rd", sessionID: doomedSession)
        let reply = UUID()
        store.recordUse(replyMessageID: reply, entryIDs: [survivor, doomed], noteIDs: [])
        store.deleteSession(doomedSession)

        let model = MemoryScreenModel(store: store)
        model.refresh()

        let sources = try #require(model.useRows.first?.sources)
        #expect(sources.count == 2, "a deleted source is still a row — the list never shrinks silently")
        let gone = try #require(sources.first { $0.id == doomed })
        #expect(gone.sourceLine == "source deleted")
        #expect(gone.text == nil)
        #expect(gone.canExclude == false, "there is nothing left to exclude from retrieval")
        #expect(sources.contains { $0.id == survivor && $0.canExclude })
    }

    /// **Fix round 1, Important item 1.** The bar says *every*
    /// `MemoryUseRecord`, and `recentUses()`'s default page size is 20 — a
    /// number that is right for the provenance stamp's lookup and wrong for a
    /// list. A cap here shows a user with more history a smaller truth about
    /// their own data, with nothing on screen to say a page boundary was hit.
    @Test func recentlyUsedIsNotCappedAtTheStoresDefaultPageSize() throws {
        let store = try makeStore()
        let entryID = index(store, "my dentist is Dr. Patel")
        let replies = (0 ..< 25).map { i -> UUID in
            let reply = UUID()
            store.recordUse(replyMessageID: reply, entryIDs: [entryID], noteIDs: [],
                            at: Date(timeIntervalSince1970: 1_000_000 + Double(i) * 60))
            return reply
        }

        let model = MemoryScreenModel(store: store)
        model.refresh()

        #expect(model.useRows.count == 25,
                "\(model.useRows.count) of 25 use records reached the screen")
        #expect(Set(model.useRows.map(\.id)) == Set(replies), "and they are the same 25")
        #expect(model.useRows.first?.id == replies.last, "still newest-first")
    }

    /// Fix round 1 minor: the list is grouped by REPLY and each group says
    /// when. Two replies drawing on one memory would otherwise render the same
    /// row twice with nothing to tell them apart.
    @Test func everyUseGroupSaysWhenTheReplyUsedIt() throws {
        let store = try makeStore()
        let entryID = index(store, "my dentist is Dr. Patel")
        let usedAt = Self.date("2026-09-01T09:00:00Z")
        store.recordUse(replyMessageID: UUID(), entryIDs: [entryID], noteIDs: [], at: usedAt)
        store.recordUse(replyMessageID: UUID(), entryIDs: [entryID], noteIDs: [],
                        at: Self.date("2026-08-20T09:00:00Z"))

        let model = MemoryScreenModel(store: store)
        model.refresh()

        #expect(model.useRows.count == 2, "one memory used twice is two occasions, not one row")
        #expect(model.useRows.first?.usedLine == "Used on \(Self.rendered(usedAt))")
    }

    // MARK: - Don't use this (bar 422-P: exclusion reaches RETRIEVAL, not just the list)

    @Test func dontUseThisExcludesTheEntryFromTheNextRetrievalOfTheSameQuery() throws {
        let store = try makeStore()
        let dentist = index(store, "my dentist is Dr. Patel")
        index(store, "the car is due for a service in March")
        let query = "who is my dentist"

        let before = MemoryRetriever.retrieve(query: query, candidates: store.candidates())
        #expect(before.contains { $0.candidate.entryID == dentist },
                "the pin is only meaningful if retrieval drew on it to begin with")

        let model = MemoryScreenModel(store: store)
        model.refresh()
        model.excludeEntry(dentist)

        let after = MemoryRetriever.retrieve(query: query, candidates: store.candidates())
        #expect(!after.contains { $0.candidate.entryID == dentist },
                """
                Don't use this must reach RETRIEVAL — a row hidden from the list that still \
                feeds the prompt is the exact failure ruling 2 exists to prevent
                """)
        #expect(store.indexCount() == 2, "exclusion is not a delete — Forget everything is")
    }

    /// **Fix round 1, Important item 3 — the tap has to be VISIBLE.** Before
    /// this, *Don't use this* wrote the flag and re-rendered a byte-identical
    /// row: the same words, the same button, no confirmation, and no way back.
    @Test func dontUseThisMarksTheRowExcludedAndOffersTheWayBack() throws {
        let store = try makeStore()
        let sentAt = Self.date("2026-08-14T09:30:00Z")
        let dentist = index(store, "my dentist is Dr. Patel", sentAt: sentAt)
        store.recordUse(replyMessageID: UUID(), entryIDs: [dentist], noteIDs: [])

        let model = MemoryScreenModel(store: store)
        model.refresh()

        let before = try #require(model.useRows.first?.sources.first)
        #expect(before.isExcluded == false)
        #expect(before.actionLabel == "Don't use this")
        #expect(before.statusLine == "From your chat on \(Self.rendered(sentAt))")

        model.excludeEntry(dentist)

        let excluded = try #require(model.useRows.first?.sources.first)
        #expect(excluded.isExcluded, "the row must know it is excluded")
        #expect(excluded.statusLine == "Excluded · From your chat on \(Self.rendered(sentAt))",
                "the row says so — a re-render identical to the one before it reads as a dead tap")
        #expect(excluded.actionLabel == "Use again",
                "a one-way switch on your own memories is a trap: this row is the only route to it")
        #expect(excluded.text == "my dentist is Dr. Patel",
                "exclusion is not a delete — the words are still the user's and still quotable")
    }

    @Test func useAgainReturnsTheRowToRetrieval() throws {
        let store = try makeStore()
        let dentist = index(store, "my dentist is Dr. Patel")
        index(store, "the car is due for a service in March")
        store.recordUse(replyMessageID: UUID(), entryIDs: [dentist], noteIDs: [])
        let query = "who is my dentist"

        let model = MemoryScreenModel(store: store)
        model.refresh()
        model.excludeEntry(dentist)
        #expect(!MemoryRetriever.retrieve(query: query, candidates: store.candidates())
            .contains { $0.candidate.entryID == dentist }, "precondition: it really was excluded")

        model.restoreEntry(dentist)

        #expect(MemoryRetriever.retrieve(query: query, candidates: store.candidates())
            .contains { $0.candidate.entryID == dentist },
                "Use again must reach retrieval too, or the row lies about being back")
        let row = try #require(model.useRows.first?.sources.first)
        #expect(row.isExcluded == false)
        #expect(row.actionLabel == "Don't use this")
    }

    /// A NOTE is deleted, never excluded — it must not offer either action, or
    /// the button would write an exclusion flag onto an id no turn index holds.
    @Test func aNoteRowOffersNoExclusionAction() throws {
        let store = try makeStore()
        let noteID = store.insertNote("I am allergic to penicillin",
                                      sourceMessageID: nil, sourceSessionID: nil)
        store.recordUse(replyMessageID: UUID(), entryIDs: [], noteIDs: [noteID])

        let model = MemoryScreenModel(store: store)
        model.refresh()

        let row = try #require(model.useRows.first?.sources.first)
        #expect(row.actionLabel == nil)
        #expect(row.isExcluded == false)
    }

    // MARK: - INDEX

    /// `—` while unknown, the real number once read, and **never `0` as a
    /// placeholder**: a zero shown before the count is known tells a user with
    /// a full index that the app remembers nothing about them.
    @Test func theIndexLineIsUnknownUntilItIsReadAndThenReal() throws {
        let store = try makeStore()
        index(store, "my dentist is Dr. Patel")
        index(store, "I fly out on the 3rd")

        let model = MemoryScreenModel(store: store)
        #expect(model.indexCountText == "—", "unread is not zero")
        #expect(model.indexCountText != "0")

        model.refresh()
        #expect(model.indexCountText == "2")
    }

    @Test func aScreenWithNoStoreAtAllStillSaysUnknownRatherThanZero() {
        // The container-creation-failure shape: `MemoryStore.make` returned nil.
        let model = MemoryScreenModel(store: nil)
        model.refresh()
        #expect(model.indexCountText == "—",
                "no store is 'we cannot say', never 'nothing is stored'")
    }

    /// **Fix round 1, Important item 4 — the two halves of one render must
    /// agree.** With no store, the INDEX line correctly says `—` ("we cannot
    /// say") while the empty copy used to say `Nothing saved yet` ("we can, and
    /// it is nothing") — a contradiction on screen at the same instant, and the
    /// false half is the one that makes a claim about the user's data.
    @Test func anUnknownCountIsNotAnEmptyStore() {
        let model = MemoryScreenModel(store: nil)
        model.refresh()
        #expect(model.indexCount == nil)
        #expect(model.isEmpty == false, "unknown is not empty")
        #expect(model.emptyMessage == nil,
                "the empty copy is a claim about the store — it needs a real, READ zero")
    }

    /// The same guard before anything is read at all: a model that has not
    /// refreshed knows nothing and must claim nothing.
    @Test func anUnreadModelClaimsNeitherEmptinessNorACount() throws {
        let store = try makeStore()
        let model = MemoryScreenModel(store: store)
        #expect(model.emptyMessage == nil)
        #expect(model.indexCountText == "—")
    }

    @Test func theIndexSummaryCountsMessagesNotChunks() throws {
        let store = try makeStore()
        let session = UUID(), message = UUID()
        // One message, two chunks — the summary sentence says MESSAGES, so it
        // must not report this as two.
        store.upsertTurnChunks([
            MemoryTurnIndexRecord(entryID: UUID(), sessionID: session, messageID: message,
                                  chunkIndex: 0, text: "my dentist is Dr. Patel", sentAt: Date()),
            MemoryTurnIndexRecord(entryID: UUID(), sessionID: session, messageID: message,
                                  chunkIndex: 1, text: "and the surgery is on Mill Road", sentAt: Date()),
        ])

        let model = MemoryScreenModel(store: store)
        model.refresh()

        #expect(model.indexCountText == "2", "two rows are two rows")
        #expect(model.indexSummary == "Talaria can draw on the 1 message you've sent in on-device chats",
                "the sentence says messages — reporting chunks under that wording would be a false number")
    }

    // MARK: - The toggle (Owen 09-03: this lane's toggle is load-bearing for launch)

    @Test func theToggleWritesThroughTheSettingsStoreAndPersists() throws {
        let store = try makeStore()
        let (settingsStore, persistence) = makeSettingsStore()
        #expect(settingsStore.settings.memoryEnabled, "the documented default is ON")

        let model = MemoryScreenModel(store: store, settingsStore: settingsStore)
        #expect(model.isMemoryEnabled)

        model.setMemoryEnabled(false)

        #expect(model.isMemoryEnabled == false)
        #expect(settingsStore.settings.memoryEnabled == false)
        #expect(persistence.loadUserSettings()?.memoryEnabled == false,
                "OFF must survive a relaunch — the screen is the only place the user can turn it off")
    }

    @Test func theToggleReadsTheSettingsStoreLiveRatherThanACapturedCopy() throws {
        let store = try makeStore()
        let (settingsStore, _) = makeSettingsStore()
        let model = MemoryScreenModel(store: store, settingsStore: settingsStore)

        settingsStore.settings.memoryEnabled = false

        #expect(model.isMemoryEnabled == false,
                "a value captured at construction would still read ON here")
    }

    // MARK: - Forget everything

    @Test func forgetEverythingEmptiesAllThreeEntitiesAndSaysSoHonestly() throws {
        let store = try makeStore()
        let entryID = index(store, "my dentist is Dr. Patel")
        let noteID = store.insertNote("I am allergic to penicillin",
                                      sourceMessageID: nil, sourceSessionID: nil)
        store.recordUse(replyMessageID: UUID(), entryIDs: [entryID], noteIDs: [noteID])

        let model = MemoryScreenModel(store: store)
        model.refresh()
        #expect(!model.isEmpty)
        #expect(model.emptyMessage == nil, "there is something to show, so no empty copy")

        model.forgetEverything()

        #expect(store.indexCount() == 0, "indexed turns")
        #expect(store.noteCount() == 0, "explicit notes")
        #expect(store.recentUses().isEmpty, "use records")
        #expect(model.noteRows.isEmpty)
        #expect(model.useRows.isEmpty)
        #expect(model.indexCountText == "0", "read and genuinely zero — not the unknown placeholder")
        #expect(model.isEmpty)
        #expect(model.emptyMessage
                == "Nothing saved yet — say \"Remember that…\" or just keep chatting.",
                "an emptied screen states its emptiness — a blank one reads as a broken render")
        #expect(model.indexSummary == nil, "there is no honest count sentence to draw")
    }

    // MARK: - Note edit / delete (fix round 1 minor: pinned, and the empty edit surfaced)

    @Test func deletingANoteRemovesItFromTheStoreAndTheList() throws {
        let store = try makeStore()
        let keep = store.insertNote("I am allergic to penicillin",
                                    sourceMessageID: nil, sourceSessionID: nil)
        let doomed = store.insertNote("my dentist is Dr. Patel",
                                      sourceMessageID: nil, sourceSessionID: nil)

        let model = MemoryScreenModel(store: store)
        model.refresh()
        #expect(model.noteRows.count == 2)

        model.deleteNote(doomed)

        #expect(store.note(id: doomed) == nil, "the row is gone from the store, not just the list")
        #expect(model.noteRows.map(\.id) == [keep], "and the list re-read rather than guessing")
    }

    @Test func editingANoteWritesTheUsersNewWordsAndStampsTheEdit() throws {
        let store = try makeStore()
        let id = store.insertNote("my dentist is Dr. Patel",
                                  sourceMessageID: nil, sourceSessionID: nil)
        let model = MemoryScreenModel(store: store)
        model.refresh()

        #expect(model.updateNote(id, text: "  my dentist is Dr. Okafor  "))

        #expect(store.note(id: id)?.text == "my dentist is Dr. Okafor",
                "stored trimmed, and verbatim otherwise — this path never re-words (ruling 1)")
        let row = try #require(model.noteRows.first)
        #expect(row.text == "my dentist is Dr. Okafor")
        #expect(row.savedLine.contains("· edited"), "an edited note says so")
    }

    /// An emptied edit is REFUSED — deleting is the Delete action, and a note
    /// with no text is a row the user can never find again. The refusal is
    /// returned rather than swallowed, so the sheet cannot dismiss as though it
    /// had saved (fix round 1 minor; the Save button is also disabled on empty).
    @Test func anEmptiedEditIsRefusedAndSaysSo() throws {
        let store = try makeStore()
        let id = store.insertNote("my dentist is Dr. Patel",
                                  sourceMessageID: nil, sourceSessionID: nil)
        let model = MemoryScreenModel(store: store)
        model.refresh()

        #expect(model.updateNote(id, text: "   ") == false)

        #expect(store.note(id: id)?.text == "my dentist is Dr. Patel", "the note is untouched")
        #expect(model.noteRows.first?.savedLine.contains("· edited") == false,
                "a refused edit must not stamp an edit date either")
    }

    // MARK: - The host line (ruling 3, said out loud on the one screen about memory)

    @Test func theHostLineAppearsOnlyWhenAHostIsConfigured() throws {
        let store = try makeStore()
        let withoutHost = MemoryScreenModel(store: store, hostConfigured: false)
        #expect(withoutHost.hostLine == nil,
                "a hostless install must not be told about a host it does not have")

        let withHost = MemoryScreenModel(store: store, hostConfigured: true)
        #expect(withHost.hostLine == """
            Your Hermes host keeps its own memory (Honcho, Hindsight…). Talaria never reads \
            or merges it; a Hermes reply is tagged only when the host reports a memory tool \
            call.
            """)
    }

    // MARK: - The screen's own words

    @Test func theScreenNamesItselfInTalariasVoice() {
        #expect(MemoryScreenModel.title == "MEMORY")
        #expect(MemoryScreenModel.subtitle == "WHAT TALARIA REMEMBERS")
        #expect(!MemoryScreenModel.subtitle.contains("Hermes"))
        #expect(!MemoryScreenModel.emptyCopy.contains("Hermes"))
    }
}
