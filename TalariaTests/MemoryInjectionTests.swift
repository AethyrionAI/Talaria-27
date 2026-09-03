import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// #422 Task 10, bar 422-D's injection half — where a memory reaches the
/// model, and what it costs the context window.
///
/// **The shape under test, in one line:** explicit notes ride the
/// INSTRUCTIONS (rebuilt once per note change), retrieved turns ride the
/// PROMPT of the turn that retrieved them through #390's one door, and the
/// tokens both spend are counted so the live session is rebuilt before the
/// model ever meets the #26 overflow.
///
/// **Two things these tests cannot do, said out loud.** The simulator cannot
/// generate on the on-device model at all (#324, re-measured #402), so no test
/// here runs a turn end to end: they drive `preparedSession` and the compose
/// door directly, which is exactly the pair production calls in that order.
/// And `SystemLanguageModel.contextSize` reads **0** on the simulator, so the
/// budget arithmetic below runs against the 1,024-token floor rather than the
/// phone's 7,168 — which is precisely why
/// `injectedMemoryRebuildThreshold(contextBudget:)` is derived from the
/// runtime budget and pinned separately at the phone's number.
@MainActor
@Suite("422-D memory injection")
struct MemoryInjectionTests {

    // MARK: - Fixtures

    private func makeBackend(
        memoryStore: MemoryStore?,
        isMemoryEnabled: (@MainActor () -> Bool)? = nil
    ) -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "memory-injection-\(UUID().uuidString)")!
            ),
            intelligence: LocalIntelligenceService(),
            memoryStore: memoryStore,
            isMemoryEnabled: isMemoryEnabled
        )
    }

    /// A store seeded with turns the lexical retriever will rank against
    /// `hitQuery`. Distinct sessions so the adjacent-chunk de-duplication
    /// keeps all three.
    private func seededStore() throws -> MemoryStore {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let seeds = [
            "my dentist is Doctor Ramirez on Pearl Street",
            "the dentist appointment is always on a Tuesday morning",
            "I switched dentist after moving to Pearl Street",
            "the sourdough starter lives in the back of the fridge",
            "the car insurance renews in November",
        ]
        store.upsertTurnChunks(seeds.enumerated().map { index, text in
            MemoryTurnIndexRecord(
                entryID: UUID(), sessionID: UUID(), messageID: UUID(), chunkIndex: 0,
                text: text, sentAt: Date(timeIntervalSince1970: 1_750_000_000 + Double(index)))
        })
        return store
    }

    private let hitQuery = "who is my dentist on Pearl Street"

    private func compose(_ message: String, savedNote: String? = nil) -> LocalChatBackend.ComposedTurnInput {
        LocalChatBackend.composeTurnInput(
            message: message, attachments: [], imageInputEnabled: false, savedNote: savedNote)
    }

    // MARK: - (a) The router sees the user's own words

    /// **422-D: `routeTurn` receives `nextPrompt` byte-identical whether or
    /// not a prefix exists.**
    ///
    /// The hazard is not hypothetical. The router decides whether a turn is
    /// armed with a device-tool belt at all, from a few-shot classification of
    /// the prompt text — hand it *"On 15 June you said: …"* and a question
    /// about the user's own past becomes, to the classifier, a request that
    /// looks nothing like the one the user typed. The prefix is therefore
    /// composed AFTER `preparedSession` returns, and the spy is what makes
    /// that ordering falsifiable rather than merely readable.
    @Test func theRouterSeesThePromptWithoutTheMemoryPrefix() async throws {
        let store = try seededStore()
        let backend = makeBackend(memoryStore: store)
        let input = compose(hitQuery)

        _ = await backend.preparedSession(
            nextPrompt: input.promptText, attachments: [], excludingClientMessageID: nil)
        let prefix = await backend.memoryPrefix(for: input)
        let prefixed = LocalChatBackend.prefixed(input, with: prefix)

        #expect(backend.lastRoutedPrompt == input.promptText,
                "the router must classify the user's own words")
        #expect(backend.lastRoutedPrompt == hitQuery)
        #expect(!prefix.isEmpty, "precondition: this query must retrieve, or the pin is vacuous")
        #expect(prefixed.promptText != input.promptText,
                "precondition: the prefix must actually change the prompt")
        #expect(prefixed.promptText.hasSuffix(input.promptText),
                "the user's own text survives verbatim at the end of the prefixed prompt")
    }

    /// The same ordering, read off PRODUCTION rather than off a harness. A
    /// test can call the two functions in whatever order it likes; this pins
    /// the order `send` and `streamTurn` actually use. (Same source-witness
    /// pattern as `MemoryHonestyTests`/`GuardrailImageDegradeTests`.)
    @Test func bothTurnPathsPrefixMemoryAfterPreparingTheSession() throws {
        for anchor in ["func send(", "func streamTurn("] {
            // 4,000 chars: `streamTurn`'s `#if DEBUG` forced-trip block sits
            // between its signature and the call, ~3,100 chars in.
            let body = try Self.backendFunctionBody(from: anchor, limit: 4000)
            let prepared = try #require(
                body.range(of: "await preparedSession(nextPrompt:"),
                "\(anchor) no longer calls preparedSession — re-point this pin")
            let prefixed = try #require(
                body.range(of: "await memoryPrefix(for:"),
                "\(anchor) no longer composes a memory prefix — re-point this pin")
            #expect(prepared.lowerBound < prefixed.lowerBound,
                    "\(anchor) must route and fit-check the BARE prompt, then prefix memory")
        }
    }

    // MARK: - (b) The accounting rebuild, and never the #26 overflow retry

    /// **422-D: 30 turns, a 3-hit prefix on every one of them.**
    ///
    /// The asymmetry this measures: a prefix goes into the live
    /// `LanguageModelSession`'s own transcript, while `appendUserMessage`
    /// stores the user's BARE message — so `currentConversation`, the source
    /// every fit estimate reads, never learns the prefix happened. Thirty
    /// turns of that drift is how a session arrives at the #26 overflow with
    /// an estimate that says it fits.
    ///
    /// RED-first evidence (Task 10 report): with the accounting removed —
    /// `injectedMemoryTokensThisSession` neither accumulated nor read — this
    /// test reports `memoryAccountingRebuildCount == 0`.
    @Test func thirtyHitTurnsRebuildOnTheAccountingAndNeverOnOverflow() async throws {
        let store = try seededStore()
        let backend = makeBackend(memoryStore: store)
        let threshold = await backend.injectedMemoryRebuildThreshold()
        let perTurnCeiling = MemoryBudget.memoryBlockTokens(contextSize: 0)
        var everyTurnCarriedHits = true

        for turn in 0..<30 {
            let input = compose(hitQuery)
            _ = await backend.preparedSession(
                nextPrompt: input.promptText, attachments: [],
                excludingClientMessageID: nil)
            let prefix = await backend.memoryPrefix(for: input)
            if !prefix.hasPrefix(MemoryBudget.hitsPreamble) { everyTurnCarriedHits = false }
            // The turn lands in history as the user's BARE words — which is
            // exactly the asymmetry the accounting exists to close.
            backend.appendUserMessage(
                message: input.promptText, attachments: [], clientMessageID: UUID())
            #expect(
                backend.injectedMemoryTokensThisSession <= threshold + perTurnCeiling,
                "turn \(turn): the accumulation ran away — the rebuild is not firing")
        }

        #expect(everyTurnCarriedHits, "precondition: every turn must retrieve, or this is not the bar")
        #expect(backend.memoryAccountingRebuildCount >= 1,
                "30 hit turns must force at least one rebuild on the injected-token accounting")
        #expect(backend.overflowRetryCount == 0,
                "the #26 overflow retry must never be reached on a memory-only accumulation")
    }

    /// The phone's number, pinned where the simulator's 0-token
    /// `contextSize` cannot reach it: on-device 8,192 − 1,024 headroom =
    /// 7,168 of budget, and the threshold is 1,500 exactly.
    @Test func theRebuildThresholdIsFifteenHundredOnThePhone() {
        #expect(LocalChatBackend.injectedMemoryRebuildThreshold(contextBudget: 7168) == 1500)
        // PCC's 32,768 − 4,096 = 28,672 — the flat cap still governs.
        #expect(LocalChatBackend.injectedMemoryRebuildThreshold(contextBudget: 28672) == 1500)
        // A small window gets a proportional threshold instead of one it
        // could never reach before the transcript itself overflowed.
        #expect(LocalChatBackend.injectedMemoryRebuildThreshold(contextBudget: 1024) == 256)
        #expect(LocalChatBackend.injectedMemoryRebuildThreshold(contextBudget: 0) == 128)
    }

    /// `fitsContext` counts what memory has already spent. Without this term
    /// the estimate is low by every prefix injected since the last rebuild,
    /// and the first thing to notice would be the model.
    @Test func fitsContextCountsTheInjectedTokens() async throws {
        let store = try seededStore()
        let backend = makeBackend(memoryStore: store)

        // Identical inputs on both sides — an empty history and a two-word
        // prompt — so the ONLY thing that can move the verdict is the
        // accounting term.
        let before = await backend.fitsContext(
            turns: [], nextPrompt: "and now?", hasImageInContext: false)
        #expect(before, "precondition: instructions + a two-word prompt must fit, or the flip is not the term under test")

        // Inject until the verdict flips. Bounded rather than fixed because
        // the simulator's 1,024-token floor and its `count / 3` token
        // estimate are not the phone's numbers — a hardcoded "six prefixes"
        // would be a pin on this Mac's arithmetic, not on the term.
        var flippedAfter: Int?
        for injection in 1...40 {
            _ = await backend.memoryPrefix(for: compose(hitQuery))
            let fits = await backend.fitsContext(
                turns: [], nextPrompt: "and now?", hasImageInContext: false)
            if !fits { flippedAfter = injection; break }
        }
        #expect(backend.injectedMemoryTokensThisSession > 0,
                "precondition: the prefixes must have been accounted")
        #expect(flippedAfter != nil,
                """
                the fit estimate never noticed 40 injected prefixes \
                (~\(backend.injectedMemoryTokensThisSession) tok) — it is blind to what \
                memory has already spent, which is how a session reaches the #26 overflow \
                while its own estimate says it fits
                """)
    }

    // MARK: - (d) Notes rebuild once per change, never per turn

    /// **422-D: two notes, exactly one rebuild each — and none on the turns
    /// in between.**
    ///
    /// Notes live in the instructions, and a `LanguageModelSession` is stuck
    /// with the instructions it was born with, so a changed note has to
    /// rebuild. The failure mode on the other side is worse than a stale
    /// note: rebuilding per turn replays the whole transcript every time,
    /// which is the ~1 ms/token prefill cost the design refused to pay.
    @Test func aNoteChangeRebuildsTheSessionOncePerChangeNotPerTurn() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let backend = makeBackend(memoryStore: store)
        let quiet = "write a haiku about rain"   // retrieves nothing: no prefix, no accounting

        // Turn 1 builds the first session (no notes yet).
        _ = await backend.preparedSession(nextPrompt: quiet, attachments: [], excludingClientMessageID: nil)
        #expect(backend.memoryNotesRebuildCount == 0)

        store.insertNote("my sister lives in Austin", sourceMessageID: UUID(), sourceSessionID: nil)
        _ = await backend.preparedSession(nextPrompt: quiet, attachments: [], excludingClientMessageID: nil)
        #expect(backend.memoryNotesRebuildCount == 1, "the first note must rebuild once")

        // Two quiet turns: nothing changed, nothing may rebuild.
        _ = await backend.preparedSession(nextPrompt: quiet, attachments: [], excludingClientMessageID: nil)
        _ = await backend.preparedSession(nextPrompt: quiet, attachments: [], excludingClientMessageID: nil)
        #expect(backend.memoryNotesRebuildCount == 1, "an unchanged notes set must NOT rebuild per turn")

        store.insertNote("the spare key is under the blue pot", sourceMessageID: UUID(), sourceSessionID: nil)
        _ = await backend.preparedSession(nextPrompt: quiet, attachments: [], excludingClientMessageID: nil)
        #expect(backend.memoryNotesRebuildCount == 2, "the second note must rebuild once more")

        _ = await backend.preparedSession(nextPrompt: quiet, attachments: [], excludingClientMessageID: nil)
        #expect(backend.memoryNotesRebuildCount == 2)
    }

    /// The notes really do land in the instructions the rebuilt session
    /// carries — the rebuild count above would be satisfied by a session that
    /// rebuilt and then forgot them.
    @Test func theNotesBlockRidesTheInstructions() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let backend = makeBackend(memoryStore: store)
        store.insertNote("my sister lives in Austin", sourceMessageID: UUID(), sourceSessionID: nil)

        let blueprint = await backend.sessionBlueprint(
            for: [], hasImageInContext: false, forceCondense: false)

        #expect(blueprint.instructions.contains(MemoryBudget.notesPreamble))
        #expect(blueprint.instructions.contains("my sister lives in Austin"),
                "verbatim — the note is quoted, never re-worded (ruling 1)")
        #expect(blueprint.instructions.hasPrefix(
            backend.effectiveInstructionsText(hasImageInContext: false)),
            "the persona is unchanged; the notes block is appended to it")
    }

    // MARK: - (e) The toggle: OFF stops retrieval, notes and prefix alike

    /// **Owen's ruling: OFF stops retrieval.** All three halves pinned
    /// together, because two of them passing is exactly the state that reads
    /// as "memory is off" while the third still leaks.
    @Test func theToggleOffStopsRetrievalNotesAndPrefixAlike() async throws {
        let store = try seededStore()
        store.insertNote("my sister lives in Austin", sourceMessageID: UUID(), sourceSessionID: nil)
        let backend = makeBackend(memoryStore: store, isMemoryEnabled: { false })

        let input = compose(hitQuery)
        let prefix = await backend.memoryPrefix(for: input)
        let blueprint = await backend.sessionBlueprint(
            for: [], hasImageInContext: false, forceCondense: false)

        #expect(backend.memoryRetrievalCount == 0, "no retrieval ran")
        #expect(!blueprint.instructions.contains(MemoryBudget.notesPreamble), "no notes block")
        #expect(!blueprint.instructions.contains("my sister lives in Austin"))
        #expect(prefix.isEmpty, "no prompt prefix")
        #expect(LocalChatBackend.prefixed(input, with: prefix).promptText == input.promptText,
                "the prompt reaches the model byte-identical to the un-augmented compose")
        #expect(backend.injectedMemoryTokensThisSession == 0)
    }

    /// The counter the toggle bar reads can actually move — a zero rate
    /// beside a counter that never increments proves nothing.
    @Test func theRetrievalCounterMovesWhenMemoryIsOn() async throws {
        let store = try seededStore()
        let backend = makeBackend(memoryStore: store)
        _ = await backend.memoryPrefix(for: compose(hitQuery))
        #expect(backend.memoryRetrievalCount == 1)
    }

    // MARK: - (f) Hits, the honest no-match line, and silence

    @Test func aHitTurnQuotesTheStoredTurnsDatedAndVerbatim() async throws {
        let backend = makeBackend(memoryStore: try seededStore())
        let input = compose(hitQuery)
        let prompt = LocalChatBackend.prefixed(
            input, with: await backend.memoryPrefix(for: input)).promptText

        #expect(prompt.hasPrefix(MemoryBudget.hitsPreamble))
        #expect(prompt.contains("my dentist is Doctor Ramirez on Pearl Street"),
                "the stored turn is QUOTED — truncation is the only allowed shortening")
        #expect(prompt.hasSuffix(hitQuery))
        #expect(!prompt.contains("the sourdough starter lives in the back of the fridge"),
                "top-k 3 with relative admission — an unrelated turn is not injected")
    }

    /// A question ABOUT the store that the store cannot answer gets the
    /// honest line rather than silence — #417's protective shape: the model
    /// is told there is nothing, so it cannot fill the gap with invention.
    @Test func aMemoryShapedQuestionWithNoHitsGetsTheHonestLine() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        store.upsertTurnChunks([
            MemoryTurnIndexRecord(
                entryID: UUID(), sessionID: UUID(), messageID: UUID(), chunkIndex: 0,
                text: "the sourdough starter lives in the back of the fridge",
                sentAt: Date(timeIntervalSince1970: 1_750_000_000)),
        ])
        let backend = makeBackend(memoryStore: store)
        let input = compose("what do you remember about my kayaking permits")
        let prompt = LocalChatBackend.prefixed(
            input, with: await backend.memoryPrefix(for: input)).promptText

        #expect(prompt.hasPrefix(MemoryBudget.noMemoriesMatch))
        #expect(prompt.hasSuffix(input.promptText))
    }

    /// And an ORDINARY question that retrieves nothing gets no prefix at all.
    /// Silence is the right answer to "what is 15% of 80"; a notice there
    /// would teach the model to discuss its memory on turns that never asked.
    @Test func anOrdinaryNoHitTurnGetsNoPrefixAtAll() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        store.upsertTurnChunks([
            MemoryTurnIndexRecord(
                entryID: UUID(), sessionID: UUID(), messageID: UUID(), chunkIndex: 0,
                text: "the sourdough starter lives in the back of the fridge",
                sentAt: Date(timeIntervalSince1970: 1_750_000_000)),
        ])
        let backend = makeBackend(memoryStore: store)
        let input = compose("what is 15% of 80")

        let prefix = await backend.memoryPrefix(for: input)
        #expect(prefix.isEmpty)
        #expect(backend.injectedMemoryTokensThisSession == 0)
    }

    /// An empty store answers a memory-shaped question honestly too — the
    /// first-run path, where "nothing matches" is the whole truth.
    @Test func anEmptyStoreStillAnswersTheMemoryShapedQuestionHonestly() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let backend = makeBackend(memoryStore: store)
        let input = compose("what do you remember about my dentist")
        let prefix = await backend.memoryPrefix(for: input)
        #expect(prefix.hasPrefix(MemoryBudget.noMemoriesMatch))
    }

    // MARK: - (g) The just-saved turn

    /// **422-E × 422-D:** the turn that stored a note tells the model, in the
    /// same prompt, that it HAS been saved — so the honesty guard's licence
    /// and the model's own sentence describe the same fact.
    ///
    /// The text comes from `ComposedTurnInput.savedNote`, which Task 11's fix
    /// derives from the STORE. Composing it from the message text instead is
    /// how a turn that saved nothing would tell the model it had.
    @Test func theJustSavedTurnStartsWithTheSavedNotice() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let clientMessageID = UUID()
        store.insertNote("my sister lives in Austin",
                         sourceMessageID: clientMessageID, sourceSessionID: nil)
        let backend = makeBackend(memoryStore: store)

        let savedNote = backend.savedNoteThisTurn(clientMessageID: clientMessageID)
        let input = compose("remember that my sister lives in Austin", savedNote: savedNote)
        let prompt = LocalChatBackend.prefixed(
            input, with: await backend.memoryPrefix(for: input)).promptText

        #expect(prompt.hasPrefix(MemoryBudget.justSavedPrefix("my sister lives in Austin")))
        #expect(prompt.hasSuffix(input.promptText))
    }

    /// No note written, no notice — the toggle-off / nil-store / voice-path
    /// shapes `SavedNoteDerivationTests` enumerates all arrive here as
    /// `savedNote == nil`, and must produce no claim of a save.
    @Test func aTurnThatSavedNothingCarriesNoSavedNotice() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let backend = makeBackend(memoryStore: store)
        let input = compose("remember that my sister lives in Austin", savedNote: nil)
        let prefix = await backend.memoryPrefix(for: input)
        #expect(!prefix.contains("HAS been saved"))
    }

    // MARK: - The budget
    //
    // Ruling 1's "a trimmed chunk is a literal PREFIX of its source" is
    // already pinned by `MemoryBudgetTests` against `trimmedHits` itself
    // (Task 9) and is deliberately NOT restated here — a second copy of an
    // assertion is a second thing to keep true, and the weaker of the two
    // copies is the one a future edit satisfies. What this file adds is the
    // half that pin cannot see: that the composed prefix production actually
    // sends stays inside the runtime cap.

    /// The composed prefix never spends more than `memoryBlockTokens` leaves
    /// it — the cap is shared with the notes, so a user with many notes has
    /// less room for retrieved turns rather than a second budget.
    @Test func theHitsBlockStaysInsideWhatTheNotesLeaveOfTheBudget() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let long = String(repeating: "Pearl Street dentist Ramirez appointment ", count: 40)
        store.upsertTurnChunks((0..<3).map { index in
            MemoryTurnIndexRecord(
                entryID: UUID(), sessionID: UUID(), messageID: UUID(), chunkIndex: 0,
                text: long, sentAt: Date(timeIntervalSince1970: 1_750_000_000 + Double(index)))
        })
        let backend = makeBackend(memoryStore: store)
        let intelligence = LocalIntelligenceService()

        let prefix = await backend.memoryPrefix(for: compose(hitQuery))
        #expect(!prefix.isEmpty, "precondition: this must retrieve")
        let tokens = await intelligence.measuredTokenCount(of: prefix)
        #expect(tokens <= MemoryBudget.memoryBlockTokens(contextSize: 0),
                "the block must fit the runtime cap — \(tokens) tok")
        #expect(prefix.contains("…"), "an over-long hit is TRUNCATED, with the cut marked")
    }

    // MARK: - (i) What the reply drew on

    /// **Ruling 2's ids, recorded where they survive.** The
    /// `Message.memoryProvenance` STAMP belongs to lane M4 (its type is not on
    /// this branch); what this lane owes is the fact itself, keyed to the
    /// reply that used it — a `MemoryUseRecord` in the store, which
    /// `ChatStore` reads back by the reply's `id`, plus `lastMemoryUse` for
    /// the turn that just finished.
    @Test func aTurnThatDrewOnMemoryRecordsWhatItUsed() async throws {
        let store = try seededStore()
        store.insertNote("my sister lives in Austin", sourceMessageID: UUID(), sourceSessionID: nil)
        let backend = makeBackend(memoryStore: store)

        _ = await backend.memoryPrefix(for: compose(hitQuery))
        let replyID = UUID()
        backend.recordMemoryUse(replyMessageID: replyID)

        let use = try #require(backend.lastMemoryUse)
        #expect(use.replyMessageID == replyID)
        #expect(!use.entryIDs.isEmpty, "the retrieved turns are named")
        #expect(use.noteIDs.count == 1, "the note in the instructions is named too")

        let recorded = try #require(store.recentUses(limit: 5).first)
        #expect(recorded.replyMessageID == replyID)
        #expect(recorded.store == "local")
        #expect(Set(recorded.entryIDs) == Set(use.entryIDs))
        #expect(Set(recorded.noteIDs) == Set(use.noteIDs))
    }

    /// A reply that drew on nothing writes no row — "nothing" is the absence
    /// of a record, never a row of empty arrays for the RECENTLY USED list to
    /// filter back out.
    @Test func aTurnThatDrewOnNothingRecordsNothing() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let backend = makeBackend(memoryStore: store)

        _ = await backend.memoryPrefix(for: compose("what is 15% of 80"))
        backend.recordMemoryUse(replyMessageID: UUID())

        #expect(backend.lastMemoryUse == nil)
        #expect(store.recentUses(limit: 5).isEmpty)
    }

    /// The same reply id settling twice — a retried turn — updates its row
    /// rather than colliding on the unique key.
    @Test func recordingTheSameReplyTwiceUpdatesOneRow() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let replyID = UUID()
        let first = UUID()
        let second = UUID()

        store.recordUse(replyMessageID: replyID, entryIDs: [first], noteIDs: [])
        store.recordUse(replyMessageID: replyID, entryIDs: [first, second], noteIDs: [])

        let uses = store.recentUses(limit: 10)
        #expect(uses.count == 1)
        #expect(Set(uses[0].entryIDs) == Set([first, second]))
    }

    // MARK: - source helpers (mirrors MemoryHonestyTests' pattern)

    private static func backendFunctionBody(from anchor: String, limit: Int) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Services/Live/LocalChatBackend.swift")
        let source = try #require(
            try? String(contentsOf: path, encoding: .utf8),
            "LocalChatBackend.swift unreadable — these pins must fail loudly, not vacuously"
        )
        let range = try #require(
            source.range(of: anchor),
            "\(anchor) is gone — re-point this pin at its successor")
        return String(source[range.upperBound...].prefix(limit))
    }
}
