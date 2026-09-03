import Foundation
import Testing
@testable import Talaria

/// #422 Task 11 fix round 1 (CRITICAL, bars 422-E/422-H) —
/// `LocalChatBackend.savedNoteThisTurn(clientMessageID:)`.
///
/// **The defect this replaces.** `ComposedTurnInput.savedNote` used to be
/// `ExplicitMemoryIntent.parse(message)` — a re-parse of the TEXT, which
/// answers "does this look like a save attempt". That is a different
/// question from "was anything actually saved", and the two diverge on
/// three reachable paths, all pinned below:
/// - the memory toggle OFF — `ChatStore`'s capture parses the text but does
///   not write, per Owen's ruling ("OFF stores nothing");
/// - a nil `memoryStore` — container-creation failure, nothing was ever
///   written anywhere;
/// - a message that parses but has no row — the shape
///   `NativeVoicePipelineService` produces: it calls
///   `backend.sendStreaming` directly with a FRESH `clientMessageID`,
///   bypassing `ChatStore.sendMessage`'s capture entirely, so "Remember
///   that…" said by voice reaches the backend with matching TEXT and no
///   note ever written for that id.
///
/// On all three, reading the text alone would have silenced bar 422-H's
/// honesty guard on a genuine fabrication ("Got it, I'll remember that"
/// with nothing stored) and, once Task 10 injects the prompt, told the
/// model a note "HAS been saved" that never was. The fix: read the STORE,
/// keyed by the `clientMessageID` `ChatStore` stamps as a note's
/// `sourceMessageID` — the same id `send`/`streamTurn` already carry.
@MainActor
@Suite("422-E savedNote derivation (fix round 1, CRITICAL)")
struct SavedNoteDerivationTests {

    private func makeBackend(
        memoryStore: MemoryStore?,
        isMemoryEnabled: (@MainActor () -> Bool)? = nil
    ) -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "saved-note-derivation-\(UUID().uuidString)")!
            ),
            intelligence: LocalIntelligenceService(),
            memoryStore: memoryStore,
            isMemoryEnabled: isMemoryEnabled
        )
    }

    // MARK: - The positive case (sanity: the store IS consulted)

    @Test func aStoredNoteResolvesToItsVerbatimText() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let clientMessageID = UUID()
        store.insertNote("my sister lives in Austin", sourceMessageID: clientMessageID, sourceSessionID: nil)
        let backend = makeBackend(memoryStore: store)

        #expect(backend.savedNoteThisTurn(clientMessageID: clientMessageID) == "my sister lives in Austin")
    }

    // MARK: - The three divergence paths (the defect's RED witnesses)

    /// Path 1: the toggle is OFF. The row exists (seeded directly here,
    /// standing in for "ChatStore wrote it before the toggle flipped") —
    /// the toggle answers for THIS READ, same discipline as
    /// `MemoryIndexer.isEnabled` / `ChatStore.isMemoryEnabled`.
    @Test func toggleOffReadsAsNothingSavedEvenWithARowPresent() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let clientMessageID = UUID()
        store.insertNote("my sister lives in Austin", sourceMessageID: clientMessageID, sourceSessionID: nil)
        let backend = makeBackend(memoryStore: store, isMemoryEnabled: { false })

        #expect(backend.savedNoteThisTurn(clientMessageID: clientMessageID) == nil,
                "the toggle is OFF — nothing was written, regardless of what the text says")
    }

    /// Path 2: a nil store (container-creation failure). Nothing was ever
    /// written anywhere, so there is nothing to read.
    @Test func aNilStoreReadsAsNothingSaved() {
        let backend = makeBackend(memoryStore: nil)
        #expect(backend.savedNoteThisTurn(clientMessageID: UUID()) == nil)
    }

    /// Path 3: **the voice-pipeline case.** A message that PARSES as a save
    /// attempt but has NO ROW — modelled by asking about a `clientMessageID`
    /// no `insertNote` call ever used, exactly the shape
    /// `NativeVoicePipelineService.streamText` produces (a fresh
    /// `UUID()` handed straight to `backend.sendStreaming`, with
    /// `ChatStore.sendMessage`'s capture never having run for it at all).
    @Test func aMessageThatParsesButHasNoRowReadsAsNothingSaved() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let backend = makeBackend(memoryStore: store)

        // No `insertNote` call for this id anywhere — the store is real and
        // reachable, it simply has no row for THIS turn.
        #expect(backend.savedNoteThisTurn(clientMessageID: UUID()) == nil)
    }

    // MARK: - Isolation (a neighboring row must not leak)

    @Test func anUnrelatedNotesSourceIDDoesNotLeak() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        store.insertNote("someone else's turn", sourceMessageID: UUID(), sourceSessionID: nil)
        let backend = makeBackend(memoryStore: store)

        #expect(backend.savedNoteThisTurn(clientMessageID: UUID()) == nil)
    }

    // MARK: - Toggle ON is the honest default

    @Test func aNilToggleClosureDefaultsToEnabled() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let clientMessageID = UUID()
        store.insertNote("my sister lives in Austin", sourceMessageID: clientMessageID, sourceSessionID: nil)
        // isMemoryEnabled left nil — the container-creation-failure shape;
        // must default to enabled, matching `UserSettings.memoryEnabled`'s
        // own documented default.
        let backend = makeBackend(memoryStore: store, isMemoryEnabled: nil)

        #expect(backend.savedNoteThisTurn(clientMessageID: clientMessageID) == "my sister lives in Austin")
    }
}
