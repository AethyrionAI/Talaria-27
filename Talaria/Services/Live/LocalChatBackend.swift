import Foundation
import FoundationModels
import ImageIO
import UIKit
import os

/// On-device chat brain (#26): Apple's FoundationModels framework behind the
/// same `HermesClientProtocol` seam as `SessionsHermesClient`, so ChatStore's
/// streaming consumer, read-aloud, persistence, and the sessions drawer work
/// unmodified — with zero desktop setup.
///
/// One `LanguageModelSession` per conversation, created lazily with the
/// assistant persona + current date + device context as instructions and the
/// conversation history replayed as a `Transcript` on restore. The context
/// window is read from the model at RUNTIME (`model.contextSize` — 8192 on
/// iPhone 17 Pro Max / iOS 27, 4096 on 26.0; never hardcoded). When a
/// conversation approaches that budget, older turns are condensed through
/// `LocalIntelligenceService`'s deterministic trimming helpers and the session
/// is recreated as [condensed memory] + recent verbatim turns — overflow
/// degrades to summarized memory, never errors.
///
/// Real-data-only: the backend never fabricates. Model unavailable → honest
/// explanation state; `GenerationError` → plain-language `.failed` reasons;
/// token usage is reported only where the OS actually provides it
/// (`LanguageModelSession.usage`, iOS 27) — never estimated client-side.
///
/// **File layout (#216, 2026-08-01).** This file was ~5,730 lines, well over
/// half of it DEBUG-only measurement harness. Those now live in sibling
/// files — `LocalChatBackend+Harnesses.swift`, `+IntentRouting.swift`,
/// `+Battery.swift` — leaving this one the production brain. Swift's
/// `private` is FILE-scoped, so the members those harnesses reach are marked
/// `// harness-visible`: they are `internal` for that reason ALONE, and
/// nothing outside this type and its harnesses should touch them.
@MainActor
@Observable
final class LocalChatBackend: HermesClientProtocol {

    /// Model identifiers exposed by `availableModels()` and accepted by
    /// `switchModel`. PCC appears only when the entitlement + availability
    /// check actually passes (#30) — never assumed.
    nonisolated static let onDeviceModelID = "on-device"
    nonisolated static let privateCloudModelID = "private-cloud-beta"

    /// The two tiers the local brain can run (#30). PCC is a MODE of this
    /// backend — one seam, never a third client. On-device is the permanent
    /// free floor; PCC is opportunistic and visibly labeled beta.
    enum LocalModelTier: String, Sendable {
        case onDevice = "on-device"
        case privateCloud = "private-cloud-beta"
    }

    /// `HermesSessionInfo.source` tag for locally-produced conversations, so
    /// the sessions drawer can distinguish the standalone thread from server
    /// history once both exist (#27 transcript honesty).
    nonisolated static let localSessionSource = "local"

    static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalChatBackend")  // harness-visible

    /// Tokens reserved out of the context window for the model's reply (the
    /// window is shared between input and output) — and, since #102, also
    /// the enforced `maximumResponseTokens` cap, so the reply can never
    /// overflow its reservation. Tier-aware: PCC's 32K window exists for
    /// long-form output, so capping it at the on-device 1024 would gut the
    /// tier's whole point.
    nonisolated static func responseHeadroomTokens(for tier: LocalModelTier) -> Int {
        tier == .privateCloud ? 4096 : 1024
    }

    /// Explicit generation options for every chat turn (#102). Passing no
    /// options leaves sampling to an UNDOCUMENTED system default and imposes
    /// no response-token bound at all — Apple's docs (verified 2026-07-12):
    /// with `maximumResponseTokens` unset "the model is allowed to produce
    /// the longest answer its context size supports", the best-fit mechanism
    /// for the observed phrase-loop + thermal "serious". Three explicit
    /// choices:
    /// - Nucleus sampling: guarantees non-greedy decoding (under greedy, a
    ///   temperature is a no-op — and whether the system default is greedy
    ///   is undocumented). 0.9 is the standard conversational threshold.
    /// - Temperature 0.7: moderate on Apple's documented 0–1 scale
    ///   (1 = no adjustment, lower sharpens toward determinism).
    /// - Token cap = the tier's reply headroom, the same reservation the
    ///   context budget carves out, now enforced. Hitting it terminates the
    ///   response early with NO error (documented), so a runaway reply
    ///   degrades to truncation instead of a thermal event.
    nonisolated static func chatGenerationOptions(for tier: LocalModelTier) -> GenerationOptions {
        GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.9),
            temperature: 0.7,
            maximumResponseTokens: responseHeadroomTokens(for: tier)
        )
    }
    /// Per-turn cap when older turns are condensed into memory: enough for the
    /// gist of a turn, small enough that memory never crowds out live context.
    static let condensedPerTurnTokens = 120
    /// Cap on the whole condensed-memory block appended to the instructions.
    static let condensedMemoryTokens = 1024

    var connectionStatus: ConnectionStatus = .disconnected
    /// #197 — how many turns this backend silently re-ran after a
    /// tool-argument decode failure. The retry must never HIDE the defect:
    /// the underlying decode failure is still unexplained (#208 cleared the
    /// token cap), so every recovery logs a notice and lands here where
    /// Diagnostics can read it.
    private(set) var toolDecodeRetryCount = 0
    /// #338-E — how many turns the honesty guard corrected in this process.
    ///
    /// Counted, not merely logged, so #337's fabrication rate can be read from
    /// PRODUCTION behaviour instead of re-derived from battery cells. Same
    /// reasoning as `toolDecodeRetryCount` above: a mitigation that hides its
    /// own defect is worse than the defect.
    private(set) var honestyGuardFireCount = 0  // harness-visible
    /// #338-E — the last claim the guard caught, for the instruments and for a
    /// device-log reader who wants the offending sentence without the log.
    private(set) var lastHonestyGuardClaim: ActionClaimDetector.Claim?  // harness-visible
    var currentConversation: Conversation?

    var model: SystemLanguageModel { SystemLanguageModel.default }  // harness-visible
    var session: LanguageModelSession?  // harness-visible
    /// The tier the NEXT session runs on (#30). Switching invalidates the
    /// live session; the replayed (condensed) transcript is the handover.
    private(set) var activeTier: LocalModelTier = .onDevice
    /// One-shot escalation offer (#30): set when on-device condensation first
    /// kicks in while PCC is available — the user decides, never silent.
    private(set) var shouldOfferPrivateCloudEscalation = false
    private var escalationOfferDismissed = false
    /// Device tool belt (#28), installed by AppContainer after construction.
    /// Empty = the tool-less #26 configuration (tests, early boot).
    private(set) var tools: [any Tool] = []
    /// Bridges the belt's invocations onto `StreamingUpdate.toolActivity` —
    /// pointed at the live stream's continuation for the duration of a turn.
    private(set) var toolRelay: ToolEventRelay?
    /// Tool names the LIVE session was created with (#176). The offered belt
    /// is conditioned on whether the conversation carries an image, and a
    /// session is stuck with the tool list it was born with — so when the
    /// condition flips (an image arrives, or a fresh thread has none) the
    /// session has to be recreated to match.
    private var sessionToolNames: [String] = []
    /// #196 (PROMOTED 2026-07-28): the current turn's route — true when the
    /// router judged this turn answerable without the device. Set per turn
    /// in `preparedSession` before the session gates consult it; the #176
    /// recreate seam then swaps the session automatically when the route
    /// flips between turns. Device evidence for the promotion: battery-4
    /// 60/60 content AND clean on canary/haiku/norway, router probe
    /// 200/200 both directions, armed control diseased in the same run.
    private var turnRoutedToolless = false
    /// #257 lever 1b: true when THIS turn's settled reply gets the
    /// deterministic capability block appended — captured at ROUTE time
    /// (routed toolless AND `isCapabilityQuestion`), so a mid-turn #229/#232
    /// disarm can never retroactively arm the append. Consulted once, at the
    /// reply's settle point in `send` / `streamTurn`.
    private var turnAppendsCapabilityAnswer = false
    /// The memory block synthesized by the last condensation, kept for
    /// diagnostics. Session-lifetime only: rebuilds re-derive it from the full
    /// message history, which the Conversation always retains.
    private(set) var condensedMemory: String?
    private var didAttemptCacheRestore = false

    /// Shared trimming/token-measuring helpers (#4.8) — reused so the
    /// tokenizer-facing surface (and its iOS 26.4 gate) lives in one place.
    private let intelligence: LocalIntelligenceService
    /// The UserDefaults conversation cache — written by ChatStore — stays the
    /// restore source for kill/relaunch continuity (#26). Since #190 it is no
    /// longer the sessions backing: that's `sessionStore`.
    private let persistence: any AppPersistenceStoreProtocol
    /// #190: keyed, durable session storage. Nil only when the SwiftData
    /// container failed to create — sessions then degrade to the pre-#190
    /// single-slot behavior instead of crashing at boot.
    private let sessionStore: (any LocalSessionStoring)?
    /// #190: whether a conversation belongs to the standalone path — the one
    /// discriminator shared by the walk-away persist (ChatStore side) and the
    /// legacy-cache adoption here. Defaults to "everything is local", the
    /// correct reading for never-paired devices and standalone tests;
    /// AppContainer wires the real rule (no configured host, or a
    /// local-brained turn in the transcript).
    private let isLocalThread: @MainActor (Conversation) -> Bool
    /// One-shot legacy adoption gate (#190 Phase 3) — see
    /// `adoptLegacySingleSlotIfNeeded`.
    private var didAttemptLegacyAdoption = false
    /// #422 Task 11 fix round 1 (CRITICAL): the local memory store, injected
    /// the same way AppContainer wires `ChatStore.memoryIndexer` — Task 10
    /// needs it for retrieval anyway, and THIS fix needs it so
    /// `savedNoteThisTurn` can answer "did this turn really write a memory"
    /// from the STORE rather than by re-parsing the message text. Nil
    /// (tests, container-creation failure) means every turn honestly reads
    /// as having saved nothing.
    private let memoryStore: MemoryStore?
    /// #422 Task 11 fix round 1: the memory master switch, read live on
    /// every call — same discipline as `MemoryIndexer.isEnabled` /
    /// `ChatStore.isMemoryEnabled`, a closure rather than a captured `Bool`
    /// so a mid-session flip takes effect on the very next turn. Nil
    /// defaults to enabled.
    private let isMemoryEnabled: (@MainActor () -> Bool)?

    // MARK: - #422 Task 10 (bar 422-D): injected-memory accounting
    //
    // The hazard this state exists for is one asymmetry. A memory prefix is
    // prepended to the PROMPT, so it enters the live `LanguageModelSession`'s
    // own transcript and stays there for the rest of the session — but
    // `appendUserMessage` stores the user's BARE message, so
    // `currentConversation` (the source `fitsContext` and `sessionBlueprint`
    // both read) never knows the prefix happened. Left unaccounted, the fit
    // estimate drifts low by the sum of every prefix injected since the last
    // rebuild, and the first thing that notices is the model, mid-turn, as
    // the #26 overflow — the retry this lane must never provoke.

    /// Tokens of memory prefix injected into the LIVE session's transcript
    /// since it was last built. Reset by `rebuildSession`, because a rebuild
    /// replays from `currentConversation`, which carries no prefixes.
    private(set) var injectedMemoryTokensThisSession = 0  // harness-visible

    /// Rebuild the session once the accumulation passes this. Deliberately
    /// far below the window: the point is to rebuild while there is still
    /// room for the NEXT turn's prefix plus its answer, not to rebuild at the
    /// edge of an overflow we are already inside.
    nonisolated static let injectedMemoryRebuildTokens = 1_500

    /// The accumulation that forces a rebuild, for a given prompt budget.
    ///
    /// **1,500 is the phone's number and it is not a coincidence** — the
    /// on-device window is 8,192 with 1,024 of reply headroom, so the budget
    /// is 7,168, a quarter of which is 1,792, and the flat cap wins: this
    /// returns exactly 1,500 there, as bar 422-D pins.
    ///
    /// The quarter-of-budget arm exists for every SMALLER window, where a
    /// flat 1,500 would be a threshold the session could never reach before
    /// the transcript itself overflowed — which is the same failure as having
    /// no accounting at all, only harder to see. Same ground rule as every
    /// other budget in this file: read the window at runtime, never hardcode
    /// a device's number and hope.
    nonisolated static func injectedMemoryRebuildThreshold(contextBudget: Int) -> Int {
        min(injectedMemoryRebuildTokens, max(128, contextBudget / 4))
    }

    /// The live threshold for THIS backend's active tier.
    func injectedMemoryRebuildThreshold() async -> Int {  // harness-visible
        Self.injectedMemoryRebuildThreshold(
            contextBudget: max(1024, await activeContextSize() - Self.responseHeadroomTokens(for: activeTier)))
    }

    /// How many rebuilds the accumulation above caused. Counted rather than
    /// only logged, for the same reason `toolDecodeRetryCount` is: a
    /// mitigation that hides how often it fires is a mitigation nobody can
    /// falsify.
    private(set) var memoryAccountingRebuildCount = 0  // harness-visible
    /// How many rebuilds the explicit-notes set changing caused — the pin for
    /// "once per note change, never per turn."
    private(set) var memoryNotesRebuildCount = 0  // harness-visible
    /// How many times `rebuildForOverflowRetry` ran. The #26 retry is the
    /// thing the accounting exists to keep at zero.
    private(set) var overflowRetryCount = 0  // harness-visible
    /// How many times this backend actually ran a retrieval — the toggle-OFF
    /// bar's witness (a rate of zero is only meaningful next to a counter
    /// that can move).
    private(set) var memoryRetrievalCount = 0  // harness-visible
    /// The prompt the ROUTER was handed for the current turn. Bar 422-D's
    /// first half: the router must classify the user's own words, never the
    /// memory prefix, so this is recorded at the routing call site and
    /// compared byte-for-byte against the un-prefixed compose output.
    private(set) var lastRoutedPrompt: String?  // harness-visible

    /// Identity of the explicit-notes set the LIVE session's instructions
    /// carry. `nil` until a session is built. Compared against
    /// `currentNotesFingerprint()` on every turn; a mismatch is the ONLY
    /// thing that rebuilds for notes, which is what keeps the rebuild
    /// once-per-change rather than once-per-turn.
    private var sessionNotesFingerprint: String?

    /// The composed notes block, cached against the fingerprint it was built
    /// from. Recomposing per turn would spend a tokenizer round trip on text
    /// that changes only when the user saves, edits or deletes a note.
    private var notesBlockCache: (fingerprint: String, text: String, noteIDs: [UUID])?

    /// What THIS turn's prompt drew on, held until the reply settles and has
    /// an id to key it to. Cleared by `recordMemoryUse`.
    private var pendingMemoryUse: (entryIDs: [UUID], noteIDs: [UUID])?

    /// The memories the last settled reply drew on.
    ///
    /// **This is the branch's provenance surface, and it is deliberately not
    /// `Message.memoryProvenance`** — that type belongs to lane M4 and does
    /// not exist here. ChatStore reads the durable half from
    /// `MemoryStore.recentUses(limit:)`, keyed on the reply's `id`; this
    /// property is the same fact without a store round trip, for the turn
    /// that just finished.
    private(set) var lastMemoryUse: MemoryUse?  // harness-visible

    /// The ids one reply drew on. `replyMessageID` is the `Message.id`
    /// `send` returns / `streamTurn` yields on `.finished`, which ChatStore's
    /// resolved-slot swap preserves.
    struct MemoryUse: Sendable, Equatable {
        let replyMessageID: UUID
        let entryIDs: [UUID]
        let noteIDs: [UUID]
    }

    init(
        persistence: any AppPersistenceStoreProtocol,
        intelligence: LocalIntelligenceService,
        sessionStore: (any LocalSessionStoring)? = nil,
        isLocalThread: @escaping @MainActor (Conversation) -> Bool = { _ in true },
        memoryStore: MemoryStore? = nil,
        isMemoryEnabled: (@MainActor () -> Bool)? = nil
    ) {
        self.persistence = persistence
        self.intelligence = intelligence
        self.sessionStore = sessionStore
        self.isLocalThread = isLocalThread
        self.memoryStore = memoryStore
        self.isMemoryEnabled = isMemoryEnabled
    }

    /// **#422 Task 11 fix round 1 (CRITICAL, bar 422-E/422-H).** Whether THIS
    /// turn's send actually wrote a memory — read from the STORE, never
    /// re-derived from the message text.
    ///
    /// The bug this replaces: `ComposedTurnInput.savedNote` used to be
    /// `ExplicitMemoryIntent.parse(message)`, which answers "does this text
    /// LOOK like a save attempt" — a different question from "was anything
    /// saved", and the two diverge on three reachable paths:
    /// - the memory toggle OFF (ChatStore's capture parses the text but
    ///   does not write, per Owen's ruling);
    /// - a nil `memoryStore` (container-creation failure) — nothing was
    ///   ever written anywhere;
    /// - the voice pipeline (`NativeVoicePipelineService` calls
    ///   `backend.sendStreaming` directly with a FRESH `clientMessageID`,
    ///   bypassing `ChatStore.sendMessage`'s capture entirely).
    ///
    /// On all three the old code would have silenced bar 422-H's honesty
    /// guard on a genuine fabrication ("Got it, I'll remember that" with
    /// nothing stored) and, once Task 10 injects the prompt, told the model
    /// a note "HAS been saved" that never was.
    ///
    /// `clientMessageID` is the id ChatStore's capture stamps as a note's
    /// `sourceMessageID` — the same id `send`/`streamTurn` already carry for
    /// this turn, so nothing new crosses the `HermesClientProtocol`
    /// boundary.
    func savedNoteThisTurn(clientMessageID: UUID) -> String? {  // harness-visible
        guard isMemoryEnabled?() ?? true else { return nil }
        return memoryStore?.note(forSourceMessageID: clientMessageID)?.text
    }

    // MARK: - #422 Task 10 (bar 422-D): memory injection
    //
    // Two destinations, and the split is the design rather than a convenience.
    //
    // **Explicit notes go to the INSTRUCTIONS.** They are standing facts the
    // user asked to be held, they do not depend on what this turn asks, and
    // an instructions block is the one part of a session that survives every
    // turn without being re-sent. Putting them in the prompt instead would
    // re-pay their cost on every turn and let a long conversation drift away
    // from them.
    //
    // **Retrieved turns go to the PROMPT of the turn that retrieved them**,
    // through `composeTurnInput`/`makeTurnPrompt` — #390's one door. They are
    // an answer to THIS question; a hit that stayed in the instructions would
    // still be quoted at the model ten turns after it stopped being relevant.
    //
    // Nothing here re-words anything (ruling 1). The only shortening is
    // `MemoryBudget`'s truncation, and the only text this file adds is
    // `MemoryBudget`'s own pinned preambles.

    /// Whether memory may read anything at all this turn — the master switch,
    /// read LIVE (a closure, not a captured Bool) so a mid-session flip takes
    /// effect on the very next turn. Nil defaults to enabled, matching
    /// `UserSettings.memoryEnabled`'s own documented default.
    private var memoryIsOn: Bool { isMemoryEnabled?() ?? true }

    /// Identity of the notes set as it stands RIGHT NOW. Empty string means
    /// "no notes" — including the toggle-off and no-store cases, which is
    /// correct: with memory off the session must carry no notes block, and
    /// flipping the toggle therefore reads as a change and rebuilds.
    private func currentNotesFingerprint() -> String {
        guard memoryIsOn, let memoryStore else { return "" }
        return memoryStore.allNotes().prefix(MemoryBudget.maxNotes)
            .map { "\($0.noteID.uuidString)@\(($0.editedAt ?? $0.createdAt).timeIntervalSince1970)" }
            .joined(separator: "|")
    }

    /// The explicit-notes block for the instructions, plus the ids it
    /// carries. Cached against the fingerprint so the tokenizer runs only
    /// when the notes actually changed.
    private func memoryNotesBlock() async -> (text: String, noteIDs: [UUID]) {
        let fingerprint = currentNotesFingerprint()
        if let cache = notesBlockCache, cache.fingerprint == fingerprint {
            return (cache.text, cache.noteIDs)
        }
        guard memoryIsOn, let memoryStore else {
            notesBlockCache = (fingerprint, "", [])
            return ("", [])
        }
        let rows = Array(memoryStore.allNotes().prefix(MemoryBudget.maxNotes))
        guard !rows.isEmpty else {
            notesBlockCache = (fingerprint, "", [])
            return ("", [])
        }
        let text = await MemoryBudget.composeNotesBlock(
            rows.map { (text: $0.text, createdAt: $0.createdAt) },
            using: intelligence)
        let block = (text: text, noteIDs: rows.map(\.noteID))
        notesBlockCache = (fingerprint, block.text, block.noteIDs)
        return block
    }

    /// The instructions a session built for this turn would carry: the
    /// persona for this turn's belt, plus the explicit-notes block.
    ///
    /// ONE definition, read by `sessionBlueprint` (which builds the session)
    /// and `fitsContext` (which decides whether to keep it). A second
    /// estimate here is exactly the drift that makes a fit check lie.
    ///
    /// An EMPTY base is left empty: #196's `-noinstr` cells carry no
    /// instructions entry at all, and appending a notes block would silently
    /// convert such a cell into an instructions-bearing session mid-run.
    /// Production instructions are never empty.
    private func instructionsWithMemoryNotes(hasImageInContext: Bool) async -> String {
        let base = effectiveInstructionsText(hasImageInContext: hasImageInContext)
        let notes = await memoryNotesBlock().text
        guard !base.isEmpty, !notes.isEmpty else { return base }
        return base + "\n\n" + notes
    }

    /// This turn's prompt, with the memory prefix in front of it — the ONE
    /// place a retrieved memory reaches the model.
    ///
    /// **Called AFTER `preparedSession`, and that order is the bar** (422-D):
    /// the router classifies the user's own words, and the fit check sizes
    /// the turn the user actually sent. A prefix in either would let a
    /// retrieved memory decide whether the turn gets a tool belt.
    ///
    /// Order inside the prefix: the just-saved notice first (it is a fact
    /// about THIS turn, and the model has to not contradict it), then the
    /// retrieved quotes or — only for a question ABOUT the store — the
    /// honest "nothing matches" line. An ordinary question that retrieves
    /// nothing gets NO prefix at all: silence is the correct answer to "what
    /// is 15% of 80", and a notice there would teach the model to talk about
    /// its memory on turns that never asked.
    /// Composed ONCE per turn and accounted ONCE — the `savedNote`
    /// discipline, for the same reason: the #408 guardrail leg recomposes
    /// the turn input, and a prefix recomputed there would run a second
    /// retrieval and charge the window twice for one turn's memories.
    /// `prefixed(_:with:)` is what re-applies it to the recomposed input.
    func memoryPrefix(for input: ComposedTurnInput) async -> String {  // harness-visible
        let prompt = input.promptText
        var pieces: [String] = []
        // The just-saved notice is a fact about THIS turn and is never
        // trimmed — it quotes the user's own words back (≤ 500 chars by
        // `ExplicitMemoryIntent`'s cap), and a truncated "we saved …" would
        // misreport what is in the store. It is COUNTED, though: fix round
        // 1's finding was that it sat outside the cap entirely, so a long
        // note plus three hits could spend well past `memoryBlockTokens`.
        // Counting it against the hits budget is what makes the cap cover
        // the whole block — notes + notice + hits — rather than the hits
        // alone.
        if let savedNote = input.savedNote {
            pieces.append(MemoryBudget.justSavedPrefix(savedNote))
        }
        let noticeTokens = pieces.isEmpty
            ? 0
            : await intelligence.measuredTokenCount(of: pieces.joined(separator: "\n\n"))

        var entryIDs: [UUID] = []
        // Read ONCE and passed down (fix round 1, minor): `memoryNotesBlock`
        // fetches the notes table, and asking it twice in one pass is a
        // second fetch for an answer that cannot have changed between them.
        let notes = await memoryNotesBlock()
        let noteIDs = notes.noteIDs
        if memoryIsOn, let memoryStore, !MemoryRetriever.shouldSkip(prompt) {
            memoryRetrievalCount += 1
            let hits = MemoryRetriever.retrieve(query: prompt, candidates: memoryStore.candidates())
            if hits.isEmpty {
                // The no-match line needs no budgeting of its own: it exists
                // ONLY on the branch where no hit was admitted, so it can
                // never compete with one for the cap.
                if MemoryRetriever.isMemoryShapedQuestion(prompt) {
                    pieces.append(MemoryBudget.noMemoriesMatch)
                }
            } else {
                let admitted = await admittedHitsBlock(
                    hits, notesBlock: notes.text, noticeTokens: noticeTokens)
                if !admitted.block.isEmpty {
                    pieces.append(admitted.block)
                    entryIDs = admitted.entryIDs
                }
            }
        }

        // Recorded even when nothing was PREFIXED: a reply produced while the
        // notes block sat in the instructions drew on those notes, and ruling
        // 2 chips it. `nil` is the honest "this reply drew on nothing".
        pendingMemoryUse = (entryIDs.isEmpty && noteIDs.isEmpty) ? nil : (entryIDs, noteIDs)

        guard !pieces.isEmpty else { return "" }
        let prefix = pieces
            .map { $0.trimmingCharacters(in: .newlines) }
            .joined(separator: "\n\n") + "\n\n"
        injectedMemoryTokensThisSession += await intelligence.measuredTokenCount(of: prefix)
        Self.logger.notice("memory: injected \(entryIDs.count, privacy: .public) hit(s) + \(noteIDs.count, privacy: .public) note(s); ~\(self.injectedMemoryTokensThisSession, privacy: .public) prefix tok in this session (#422)")
        return prefix
    }

    /// The composed turn input with this turn's memory prefix in front of
    /// its text. Images and `savedNote` ride through untouched — the prefix
    /// is text, and #390's one door still assembles the Prompt.
    nonisolated static func prefixed(  // harness-visible
        _ input: ComposedTurnInput, with memoryPrefix: String
    ) -> ComposedTurnInput {
        guard !memoryPrefix.isEmpty else { return input }
        return ComposedTurnInput(
            promptText: memoryPrefix + input.promptText,
            images: input.images,
            savedNote: input.savedNote
        )
    }

    /// Head-trims the hits and drops the lowest-ranked ones until the block
    /// fits what the notes AND this turn's just-saved notice left of
    /// `memoryBlockTokens`.
    ///
    /// The cap is shared on purpose: `memoryBlockTokens` is what local memory
    /// may spend of the window IN TOTAL, so a user with eight notes — or a
    /// turn that just saved a 500-character one — has less room for retrieved
    /// turns, not a second budget. Dropping from the TAIL is what makes the
    /// cap a ranking decision rather than a truncation of the best hit.
    ///
    /// The one thing that can still exceed the cap is a notice larger than
    /// the whole block budget, which drives `hitsBudget` to 0 and admits no
    /// hits at all. That is deliberate and it is the only honest option: the
    /// notice is the user's verbatim words and trimming it would misreport
    /// what was stored. Bounded by construction — a note is ≤ 500 characters.
    private func admittedHitsBlock(
        _ hits: [MemoryHit], notesBlock: String, noticeTokens: Int
    ) async -> (block: String, entryIDs: [UUID]) {
        let blockBudget = MemoryBudget.memoryBlockTokens(contextSize: await activeContextSize())
        let notesTokens = notesBlock.isEmpty
            ? 0
            : await intelligence.measuredTokenCount(of: notesBlock)
        let hitsBudget = max(0, blockBudget - notesTokens - noticeTokens)

        let trimmed = await MemoryBudget.trimmedHits(
            hits.map { (text: $0.candidate.text, sentAt: $0.candidate.sentAt) },
            using: intelligence)
        var kept = Array(zip(hits.map(\.candidate.entryID), trimmed))
        while !kept.isEmpty {
            let block = MemoryBudget.composeHitsPrefix(kept.map(\.1))
            if await MemoryBudget.fits(block, in: hitsBudget, using: intelligence) {
                return (block, kept.map(\.0))
            }
            kept.removeLast()
        }
        return ("", [])
    }

    /// Keys this turn's drawn-on ids to the reply that used them, at the
    /// reply's settle point on both turn paths.
    ///
    /// The durable half is the store row — `Message.memoryProvenance` is lane
    /// M4's type and cannot be stamped from this branch, so ChatStore reads
    /// the ids back by the reply's id (`MemoryStore.recentUses`), or off
    /// `lastMemoryUse` for the turn that just finished.
    func recordMemoryUse(replyMessageID: UUID) {  // harness-visible
        guard let use = pendingMemoryUse else {
            lastMemoryUse = nil
            return
        }
        pendingMemoryUse = nil
        lastMemoryUse = MemoryUse(
            replyMessageID: replyMessageID, entryIDs: use.entryIDs, noteIDs: use.noteIDs)
        memoryStore?.recordUse(
            replyMessageID: replyMessageID, entryIDs: use.entryIDs, noteIDs: use.noteIDs)
    }

    /// Installs the device tool belt (#28). Invalidates the live session so
    /// the next turn is created with the tools (and tool-aware instructions).
    func installTools(_ tools: [any Tool], relay: ToolEventRelay) {
        self.tools = tools
        self.toolRelay = relay
        // #225: the belt gets its per-turn bound with it. Installed here rather
        // than at each call site so a future tool cannot be added ungoverned —
        // the governor is a property of HAVING a belt, not of remembering to
        // arm one (#144's lesson: a guard that depends on being remembered is
        // the thing that failed).
        relay.governor = ToolCallGovernor()
        session = nil
        sessionToolNames = []
    }

    /// #225 — resets the per-turn tool budget. **Called at the START of every
    /// turn, both paths.** Without this the counters leak across turns and
    /// every turn after the twelfth tool call of the session goes silently
    /// toolless, which is a worse and far less visible bug than the spiral this
    /// bounds. Pinned by `theBudgetResetsForEachTurn`.
    private func beginToolTurn() {
        // #228: one call resets the governor's budget AND the instrument's
        // per-turn counters — split resets could describe different turns.
        toolRelay?.beginTurn()
    }

    /// Honest explanation for the CURRENT unavailability, nil when the model
    /// is available (#31). Drives the standalone chat's explanation state —
    /// re-read live each render, so enabling Apple Intelligence in Settings
    /// clears it on return without a relaunch.
    var availabilityExplanation: String? {
        if case .unavailable(let reason) = model.availability {
            return Self.unavailabilityMessage(for: reason)
        }
        return nil
    }

    // MARK: - Private Cloud Compute tier (#30)

    /// Master gate: whether this BINARY may construct
    /// `PrivateCloudComputeLanguageModel` at all.
    ///
    /// **Apple GRANTED the entitlement on 2026-08-20** (#72), and
    /// `com.apple.developer.private-cloud-compute` now reads back from the
    /// signed product — verified with `codesign -d --entitlements`, not
    /// assumed from a portal page. So the July condition this flag was
    /// created for is discharged... **on device.**
    ///
    /// **⛔ THE SIMULATOR IS EXCLUDED, AND THE MEASURED REASON IS NOT THE ONE
    /// YOU WOULD GUESS.** Simulator builds strip entitlements
    /// (`CODE_SIGNING_ALLOWED=NO` — the same mechanism that strips HealthKit
    /// and silently kills keychain writes), so a sim binary is an UNENTITLED
    /// binary; `codesign -d --entitlements` on the installed sim app returns
    /// an EMPTY dict.
    ///
    /// The expected hazard was the 2026-07-13 SIGTRAP. **It did not
    /// reproduce.** Measured 2026-08-20 by removing this exclusion and
    /// running the bars: the unentitled sim constructed
    /// `PrivateCloudComputeLanguageModel()` and read `quotaUsage` **without
    /// trapping at all**. So do not repeat "it crashes" as though it were
    /// current — on beta5's simulator it does not.
    ///
    /// **What the same run DID find is worse, and it is why this flag
    /// survives.** With no entitlement, `.isAvailable` returned **`true`**,
    /// `quotaUsage` returned a usable status, and `availableModels()` offered
    /// `private-cloud-beta`. The SDK does not merely lack the vocabulary to
    /// say "not entitled" (`Availability.UnavailableReason` has exactly
    /// `.deviceNotEligible` and `.systemNotReady`) — **it affirmatively
    /// reports AVAILABLE.** Gating on availability alone, which is what #72's
    /// own plan first said to do, would put a beta tier in the picker and
    /// route real turns to a service the binary has no right to use.
    /// Bar 72-A/B turn that into RED TESTS: the mutation failed all three.
    ///
    /// **Why a compile-time fact and not a runtime entitlement read.**
    /// `SecTask.h` is absent from the public iOS SDK (checked against beta5),
    /// so `SecTaskCopyValueForEntitlement` would be private API — an App
    /// Review risk taken to guard a condition the BUILD SYSTEM already
    /// guarantees. A device build lacking the entitlement cannot be produced:
    /// signing fails at `GatherProvisioningInputs`, which is exactly how it
    /// failed on 2026-08-20 before an Apple account was signed in. That
    /// failure is the guard (bar 72-C).
    ///
    /// **This is only the FIRST of two facts.** Every site below still asks
    /// `isAvailable` / `quotaUsage` afterwards: this flag answers "may this
    /// binary touch the type", the SDK answers "is the service usable on this
    /// device right now". Neither substitutes for the other —
    /// `Availability.UnavailableReason` has exactly two cases
    /// (`.deviceNotEligible`, `.systemNotReady`) and **cannot express "not
    /// entitled"**, so availability alone would never have caught the crash.
    ///
    /// #154: this flag is the SOLE build-side gate on every PCC site. Each of
    /// them used to read `#available(iOS 27.0, *), Self.pccGrantConfirmed` —
    /// but the shipping floor is 27.0, so the version clause was always true
    /// and only made the sites LOOK like they had an iOS-26 fallback.
    static let pccGrantConfirmed: Bool = {
        #if targetEnvironment(simulator)
        // No entitlement in a sim binary ⇒ never construct. See above.
        // (#402, 2026-08-24: partially superseded on the FACTS — a sim binary
        // DOES carry the entitlement, in the simulated-entitlements section
        // `codesign -d --entitlements` cannot see, and modelmanagerd honors
        // it. The GATE stays false here regardless, because generation on a
        // sim still fails on an unresolvable asset and `isAvailable` still
        // reads true — the turn plane must not offer a tier that cannot run.
        // Metadata reads ride `pccMetadataObservable` below instead.)
        false
        #else
        true
        #endif
    }()

    /// **#403: the metadata plane's OWN gate — may this binary construct
    /// `PrivateCloudComputeLanguageModel` to READ (availability, quota,
    /// contextSize), as opposed to taking turns.**
    ///
    /// On device this is exactly `pccGrantConfirmed`. On a DEBUG simulator
    /// build it is `true` — the carve-out that makes the quota tile
    /// sim-testable. The safety basis is measured, not argued: the
    /// 2026-07-13 construction SIGTRAP did not reproduce on 2026-08-20
    /// (beta5, unentitled binary), and #402 re-confirmed on runtime 24A5423a
    /// — construction and every metadata read ran clean, with the simulated
    /// entitlement honored ("Client … entitled with
    /// com.apple.developer.private-cloud-compute" in the sim's own log).
    ///
    /// **What this gate must never feed: the turn plane.** Generation on a
    /// sim fails instantly ("assets required for the session are
    /// unavailable", #402) while `isAvailable` reads true there — so a
    /// turn-plane site pointed here would offer a tier that cannot run.
    /// `PrivateCloudGateTests` pins the split with mutation-red tests
    /// (403-A).
    static let pccMetadataObservable: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        pccGrantConfirmed
        #endif
    }()

    /// Whether PCC exists for this install at all: grant confirmed, iOS 27+,
    /// entitlement granted, device/region eligible. Denied/pending Apple
    /// approval reads as unavailable — the on-device path is unaffected.
    var isPrivateCloudAvailable: Bool {
        guard Self.pccGrantConfirmed else { return false }
        return PrivateCloudComputeLanguageModel().isAvailable
    }

    /// Whether the Private Cloud SETTINGS surface (tile + screen + quota row)
    /// should exist for this install — the display plane only. On device this
    /// equals `isPrivateCloudAvailable`; under the #403 DEBUG-sim carve-out
    /// it lights so the tile is testable. Never consult this for routing —
    /// `setPreferredTier` and the router read the turn-plane facts.
    var isPrivateCloudObservable: Bool {
        guard Self.pccMetadataObservable else { return false }
        return PrivateCloudComputeLanguageModel().isAvailable
    }

    /// Whether PCC can take a turn RIGHT NOW: available and not over the
    /// daily quota. The router consults this per new message, so a
    /// rate-limited tier degrades to on-device with a visible indicator
    /// change instead of failing turns.
    var isPrivateCloudUsable: Bool {
        guard Self.pccGrantConfirmed else { return false }
        let pcc = PrivateCloudComputeLanguageModel()
        return pcc.isAvailable && !pcc.quotaUsage.isLimitReached
    }

    /// Version-agnostic quota snapshot for persistent UI (Settings → Models)
    /// — status, not alerts, per the PCC design guidance. Nil pre-iOS 27 or
    /// while PCC is unavailable.
    struct PrivateCloudStatus: Equatable, Sendable {
        enum Quota: Equatable, Sendable {
            case belowLimit(approaching: Bool)
            case limitReached
            /// **#391: the SDK reported a status this build does not know.**
            /// It used to be folded into `belowLimit(approaching: false)` —
            /// i.e. an unrecognised value was rendered to the user as good
            /// news. This arm involves no guessing: it fires only when
            /// `QuotaUsage.Status` is a case we cannot name, which IS
            /// unknown, and it renders as unknown.
            case unknown
        }

        let quota: Quota

        /// **#391: carried in EVERY arm, not only on `limitReached`.**
        ///
        /// The OS exposes `resetDate` independently of the status, and this
        /// type used to read it only inside the limit-reached branch — so on
        /// the far more common below-limit path a date the OS had supplied
        /// was discarded before anything could show it. Owen's ruling
        /// (2026-08-21): *"print what it shows. If it's nil, it's nil. Same
        /// with the optional reset date."* `nil` is a real answer here and
        /// renders as one.
        let resetDate: Date?

        let hasLimitIncreaseSuggestion: Bool
    }

    func privateCloudStatus() -> PrivateCloudStatus? {
        guard Self.pccMetadataObservable else { return nil }
        let pcc = PrivateCloudComputeLanguageModel()
        guard pcc.isAvailable else { return nil }
        let usage = pcc.quotaUsage
        // #391: the SDK's four facts are extracted here and MAPPED by a pure
        // function below, so the mapping — including "carry the reset date on
        // every arm" — is assertable without a `PrivateCloudComputeLanguageModel`.
        // Reading `usage` is untestable; deciding what it means need not be.
        let isApproaching: Bool?
        if case .belowLimit(let info) = usage.status {
            isApproaching = info.isApproachingLimit
        } else {
            isApproaching = nil
        }
        return PrivateCloudStatus.make(
            isLimitReached: usage.isLimitReached,
            isApproachingLimit: isApproaching,
            resetDate: usage.resetDate,
            hasLimitIncreaseSuggestion: usage.limitIncreaseSuggestion != nil
        )
    }

    /// Presents the system's iCloud+ upgrade path for more PCC access.
    func showPrivateCloudLimitIncreaseOptions() {
        guard Self.pccMetadataObservable else { return }
        PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
    }

    /// Applies the tier for the NEXT turn (called by the router per message).
    /// PCC requested while unavailable degrades to on-device — the router
    /// already made that visible via its own resolution.
    func setPreferredTier(privateCloud: Bool) {
        let tier: LocalModelTier = (privateCloud && isPrivateCloudAvailable) ? .privateCloud : .onDevice
        guard tier != activeTier else { return }
        activeTier = tier
        // Recreate on next send: the replayed (condensed where needed)
        // transcript IS the escalation handover context.
        session = nil
        Self.logger.notice("local tier → \(tier.rawValue, privacy: .public)")
    }

    /// User answered the escalation offer (either way) — one offer per
    /// conversation; cleared by clearConversation.
    func dismissPrivateCloudEscalationOffer() {
        shouldOfferPrivateCloudEscalation = false
        escalationOfferDismissed = true
    }

    #if DEBUG
    /// #335 `// harness-visible`: put the #30 escalation-offer flag back where
    /// the instrument found it.
    ///
    /// `condensation-fit` calls production's own condenser, and arming this
    /// offer is the one side effect that call has. **Restoring is not the
    /// instrument editing production behaviour — it is a measurement putting
    /// back what it perturbed**, so a run never leaves the user an offer they
    /// did not earn. `dismissPrivateCloudEscalationOffer()` is the wrong tool
    /// for it: that also sets `escalationOfferDismissed`, which would suppress
    /// a REAL offer for the rest of the conversation. Lives here because the
    /// flag's setter is file-private, and stays `#if DEBUG` so no production
    /// path can reach it. (Inert today — `pccGrantConfirmed` is false, so the
    /// offer cannot arm at all; written for the day that changes rather than
    /// left as a landmine.)
    func restorePrivateCloudEscalationOffer(_ value: Bool) {  // harness-visible
        shouldOfferPrivateCloudEscalation = value
    }
    #endif

    /// PCC context window, fetched once per process and cached — the window
    /// is a fixed property of the model class, not live state. (The beta-27
    /// SDK exposes `contextSize` as `async throws` on PCC, unlike the sync
    /// on-device accessor.)
    private var pccContextSize: Int?

    /// The context budget follows the ACTIVE tier's model, read at runtime —
    /// 32K on PCC vs the on-device window; neither is ever hardcoded. If the
    /// PCC fetch fails, falls back to the on-device window: a conservative
    /// budget that can never over-commit the larger tier.
    private func activeContextSize() async -> Int {
        if Self.pccGrantConfirmed, activeTier == .privateCloud {
            if let cached = pccContextSize { return cached }
            if let size = try? await PrivateCloudComputeLanguageModel().contextSize {
                pccContextSize = size
                return size
            }
        }
        return model.contextSize
    }

    // MARK: - HermesClientProtocol

    func connect() async {
        switch model.availability {
        case .available:
            connectionStatus = .connected
        case .unavailable(let reason):
            Self.logger.notice("connect: on-device model unavailable — \(Self.unavailabilityMessage(for: reason), privacy: .public)")
            connectionStatus = .error
        }
    }

    func disconnect() async {
        session = nil
        connectionStatus = .disconnected
    }

    func send(
        message: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) async -> Message {
        if case .unavailable(let reason) = model.availability {
            connectionStatus = .error
            return Message(sender: .system, content: Self.unavailabilityMessage(for: reason), status: .failed)
        }
        // #390: composed ONCE, before the retry loop — every retry leg
        // re-assembles the same Prompt from it, so a condense/tool retry
        // keeps its images. Token-fit (`nextPrompt`) reads the TEXT side;
        // image cost is invisible to the counter either way.
        // #408: `var` because the guardrail arm below re-composes it ONCE,
        // with the images demoted — the only thing in this turn that may.
        // #422 fix round 1: `savedNote` is read from the STORE, not the
        // text — see `savedNoteThisTurn`.
        var turnInput = Self.composeTurnInput(
            message: message, attachments: attachments,
            imageInputEnabled: turnImageInputEnabled(),
            savedNote: savedNoteThisTurn(clientMessageID: clientMessageID)
        )
        let prompt = turnInput.promptText
        var liveSession = await preparedSession(nextPrompt: prompt, attachments: attachments, excludingClientMessageID: clientMessageID)
        // #422 bar 422-D: memory joins the turn AFTER routing and the fit
        // check, and rides #390's one door. Composed once here; the #408
        // degrade leg re-applies THIS prefix rather than retrieving again.
        let memoryPrefix = await memoryPrefix(for: turnInput)
        turnInput = Self.prefixed(turnInput, with: memoryPrefix)
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        // #225: fresh tool budget for this turn.
        beginToolTurn()
        // #228: measure the recorded session budgets only once the turn is
        // over, on every exit path — measuring mid-turn killed the turn.
        defer { flushSessionBudgetMeasurements() }

        // #197: the sync path has no visible stream, but a tool that ran
        // this turn is still observable activity — retrying would run it
        // again. Chained (not replaced) so a harness's observer survives.
        // Locked because tools may emit off the main actor.
        let sawToolActivity = OSAllocatedUnfairLock(initialState: false)
        // #338: the honesty guard's one input — the names of the tool calls
        // that ACTUALLY ran this turn, read off the same relay events the tool
        // chips ride. Refused calls never reach here (`ToolEventRelay.started`
        // returns before emitting), so this is admitted calls only.
        //
        // Deliberately accumulated ACROSS a #232 / #229 / #197 retry: a tool
        // that ran before the phase cut staged a real confirmation card, and
        // the guard must stay quiet for that turn even though the retried leg
        // ran toolless.
        //
        // Created ONCE, outside the retry loop below, which is what makes the
        // accumulation-across-legs property true rather than incidental.
        let toolCallRecorder = TurnToolCallRecorder()
        let previousEmit = toolRelay?.emit
        toolCallRecorder.install(on: toolRelay) { event in
            sawToolActivity.withLock { $0 = true }
            previousEmit?(event)
        }
        defer { toolRelay?.emit = previousEmit }

        var didCondenseRetry = false
        var didToolDecodeRetry = false
        var didToolPhaseCutRetry = false
        // #408: at most one image-degrade leg per turn, and the count the
        // reply's note reads. 0 means "this turn never degraded", which is
        // every turn but the declined-image one.
        var didGuardrailImageDegrade = false
        var degradedImageCount = 0
        while true {
            do {
                let response = try await liveSession.respond(to: Self.makeTurnPrompt(turnInput), options: effectiveGenerationOptions())
                connectionStatus = .connected
                let usage = currentTokenUsage()
                // #102: the sync path has no stream to break, but a capped
                // looped reply still returns as a normal success — collapse
                // it before it becomes replayable history, mirroring the
                // streaming trip.
                let collapsed = Self.collapsingDegenerateTail(response.content)
                if collapsed != response.content {
                    // The live session's internal transcript holds the full
                    // loop — rebuild the next turn from our (collapsed)
                    // history instead of trusting it.
                    session = nil
                    Self.logger.notice("send: degenerate tail collapsed in sync reply — session invalidated (#102)")
                }
                // #257 lever 1b: the deterministic capability block lands
                // here — once, on the settled reply, after the collapse
                // check (so an append can never read as a degenerate tail).
                let content = Self.settledReplyContent(
                    collapsed, appendingCapabilityAnswer: turnAppendsCapabilityAnswer)
                // #338: the honesty guard. Reads the MODEL's text (never our
                // own appended blocks) and appends a correction when the turn
                // claimed a device action nothing executed.
                let guarded = honestyGuardedReply(
                    modelText: collapsed,
                    settledText: content,
                    recorder: toolCallRecorder,
                    // #422 Task 11 / bar 422-H: the deterministic note path
                    // already wrote the row (ChatStore, before this turn was
                    // dispatched) — the same fact this turn's own compose
                    // step derived from the same message.
                    savedNote: turnInput.savedNote != nil)
                // #408-D: the same settle point, for the same reason — after
                // the model's text has settled, appended so the answer
                // survives verbatim. Identity on every turn that did not
                // degrade.
                let noted = Self.replyNotingGuardrailImageDegrade(
                    guarded, degradedImageCount: degradedImageCount)
                let reply = Message(sender: .hermes, content: noted, status: .delivered)
                appendAssistantMessage(reply, usage: usage)
                // #422 bar 422-D / ruling 2: key this turn's drawn-on ids to
                // the reply that used them, at the settle point.
                recordMemoryUse(replyMessageID: reply.id)
                return reply
            } catch {
                if !didToolPhaseCutRetry, Self.isToolPhaseCut(error) {
                    // #232: the refusal grind's structural end — retry ONCE as
                    // a routed-toolless turn (empty belt + the toolless
                    // instruction set). This turn's tool results are lost with
                    // the dead session's transcript (#102's rule); for
                    // grind-shaped turns they are noise by definition.
                    didToolPhaseCutRetry = true
                    turnRoutedToolless = true
                    session = nil
                    Self.logger.notice("send: tool phase cut after \(ToolPhaseCutError.refusalThreshold) refusals — retrying toolless (#232)")
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: false)
                    continue
                }
                if !didCondenseRetry, Self.isContextOverflow(error) {
                    // Overflow degrades to summarized memory, never errors:
                    // rebuild with condensation forced and retry exactly once,
                    // toolless (#229) — re-arming the belt restored the
                    // overflow the retry exists to escape.
                    didCondenseRetry = true
                    Self.logger.notice("send: context window exceeded — condensing and retrying toolless (#229)")
                    liveSession = await rebuildForOverflowRetry(attachments: attachments, excludingClientMessageID: clientMessageID)
                    continue
                }
                if Self.shouldRetryToolDecodeFailure(
                    error,
                    turnHadObservableActivity: sawToolActivity.withLock { $0 },
                    didAlreadyRetry: didToolDecodeRetry
                ) {
                    didToolDecodeRetry = true
                    toolDecodeRetryCount += 1
                    let toolName = (error as? LanguageModelSession.ToolCallError)?.tool.name ?? "unknown"
                    Self.logger.notice("send: \(toolName, privacy: .public) argument decode failed before anything ran — retrying the turn once (#197)")
                    // Mid-turn throw → the live session's transcript state
                    // is unknowable (#102's rule) — rebuild from our history.
                    session = nil
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: false)
                    continue
                }
                if Self.shouldDegradeImagesAfterGuardrail(
                    error,
                    tierIsOnDevice: activeTier == .onDevice,
                    turnCarriedImages: !turnInput.images.isEmpty,
                    didAlreadyDegrade: didGuardrailImageDegrade
                ) {
                    // #408: the on-device safety layer declined the picture.
                    // Retry ONCE with it demoted to #390-B's placeholder —
                    // the shape this turn would have had before #390 flipped
                    // the tier sighted, and the one that completes.
                    didGuardrailImageDegrade = true
                    degradedImageCount = turnInput.images.count
                    // #422 fix round 1: reuse the ALREADY-DERIVED savedNote —
                    // same message, same clientMessageID, same turn, so the
                    // store answer cannot have changed between legs.
                    // #422 bar 422-D: re-apply THIS turn's already-composed
                    // memory prefix — same reason `savedNote` is reused, and
                    // a second retrieval here would charge the window twice.
                    turnInput = Self.prefixed(
                        Self.degradedTurnInput(message: message, attachments: attachments, savedNote: turnInput.savedNote),
                        with: memoryPrefix)
                    Self.logger.notice("send: on-device guardrail declined a sighted turn — retrying once with \(degradedImageCount, privacy: .public) image(s) demoted to the OCR placeholder (#408)")
                    // The declined prompt may already sit in the live
                    // session's transcript, and retrying on it would hand the
                    // guardrail the same picture again — so rebuild from OUR
                    // history (#102's rule), which replays text-only by
                    // construction (390-A).
                    session = nil
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: false)
                    continue
                }
                connectionStatus = .error
                return Message(sender: .system, content: failureMessageForActiveTier(error), status: .failed)
            }
        }
    }

    func sendStreaming(
        message content: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) -> AsyncStream<StreamingUpdate> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.yield(.failed("The on-device brain was deallocated before the send started."))
                    continuation.finish()
                    return
                }
                await self.streamTurn(
                    message: content,
                    attachments: attachments,
                    clientMessageID: clientMessageID,
                    into: continuation
                )
                continuation.finish()
                // #228: the turn is fully over — measure the recorded
                // session budgets now, when the model runtime is quiet.
                self.flushSessionBudgetMeasurements()
            }
        }
    }

    func streamTurn(  // harness-visible
        message: String,
        attachments: [PendingAttachment],
        clientMessageID: UUID,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async {
        #if DEBUG
        // #120 (UITest seam): a model-free synthetic turn armed only by the
        // UITEST_DUPID_PROBE launch env. It runs the production append →
        // finish machinery — append the reply to `currentConversation`, then
        // dwell past one poll interval BEFORE yielding `.finished` — so the
        // 2s poll tick's `loadConversation()` merge deterministically lands
        // in the exact window that seeds a duplicate id (#120). Placed ahead
        // of the availability gate so a clean CI simulator with no on-device
        // model still exercises the path. Inert in every non-UITest run.
        if Self.isUITestIdentityProbeEnabled {
            await runUITestIdentityTurn(
                message: message,
                attachments: attachments,
                clientMessageID: clientMessageID,
                into: continuation
            )
            return
        }
        #endif

        if case .unavailable(let reason) = model.availability {
            connectionStatus = .error
            continuation.yield(.failed(Self.unavailabilityMessage(for: reason)))
            return
        }

        #if DEBUG
        // #134 forced-trip harness: a one-shot turn armed from Settings →
        // Diagnostics that replays synthetic degenerate snapshots through this
        // exact path, so the #102 breaker and the #110 read-aloud retraction
        // can finally be observed tripping on device (the live model's own
        // guardrails defeat every organic loop repro). Everything downstream —
        // delta diffing, breaker, collapse, finish — is the production
        // machinery, unmodified.
        if let copies = Self.debugForcedTripCopies {
            Self.debugForcedTripCopies = nil
            let holdsLiveStream = Self.debugForcedTripHoldsLiveSDKStream
            Self.debugForcedTripHoldsLiveSDKStream = false
            await runDebugForcedTripTurn(
                message: message,
                attachments: attachments,
                clientMessageID: clientMessageID,
                copies: copies,
                holdLiveSDKStream: holdsLiveStream,
                into: continuation
            )
            return
        }
        #endif

        // #390: composed ONCE, before the retry loop — see `send`.
        // #408: `var` for the same reason it is there — the guardrail arm
        // below re-composes it ONCE, with the images demoted.
        // #422 fix round 1: `savedNote` is read from the STORE, not the
        // text — see `savedNoteThisTurn`.
        var turnInput = Self.composeTurnInput(
            message: message, attachments: attachments,
            imageInputEnabled: turnImageInputEnabled(),
            savedNote: savedNoteThisTurn(clientMessageID: clientMessageID)
        )
        let prompt = turnInput.promptText
        var liveSession = await preparedSession(nextPrompt: prompt, attachments: attachments, excludingClientMessageID: clientMessageID)
        // #422 bar 422-D: see `send`'s identical call — memory joins the turn
        // AFTER routing and the fit check, through #390's one door.
        let memoryPrefix = await memoryPrefix(for: turnInput)
        turnInput = Self.prefixed(turnInput, with: memoryPrefix)
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        // #225: fresh tool budget for this turn.
        beginToolTurn()

        // #197: any observable activity — a tool event, a text delta, a
        // reasoning delta — makes the turn non-retryable: a tool that
        // completed would run AGAIN on a retried turn, and painted text
        // would restart mid-bubble. Locked because tools may emit off the
        // main actor.
        let sawObservableActivity = OSAllocatedUnfairLock(initialState: false)
        // #338: see `send` — the honesty guard's one input, admitted calls
        // only, accumulated across any retry leg because the recorder is
        // created ONCE, outside the loop below.
        let toolCallRecorder = TurnToolCallRecorder()

        // #28: tool invocations surface on the existing toolActivity channel
        // for the duration of this turn — the tool-chip UI renders them free.
        toolCallRecorder.install(on: toolRelay) { event in
            sawObservableActivity.withLock { $0 = true }
            continuation.yield(.toolActivity(event))
        }
        defer { toolRelay?.emit = nil }

        var didCondenseRetry = false
        var didToolDecodeRetry = false
        var didToolPhaseCutRetry = false
        // #408: see `send`. Deliberately NOT gated on `sawObservableActivity`
        // the way #197's retry is: a guardrail decline of an image is an
        // INPUT-side verdict (all four recorded specimens streamed nothing),
        // and on the output-side case the repaint costs a transient
        // double-paint that the `.finished` consumer's resolved-slot swap
        // then replaces with the retried leg's text — #232's accepted
        // trade, not a new one.
        var didGuardrailImageDegrade = false
        var degradedImageCount = 0
        while true {
            do {
                // FM snapshots are cumulative — diff against what has already
                // been emitted so ChatStore's `.textDelta`-appending consumer
                // works unmodified.
                var emitted = ""
                var latestFull = ""
                // #30: PCC reasoning is a SEPARATE channel (the #4.15 rule) —
                // reasoning transcript entries diff onto reasoningDelta,
                // never folded into the answer text.
                var emittedReasoning = ""
                var didTripRepetitionBreaker = false
                var repetitionBreaker = RepetitionBreaker()
                let stream = liveSession.streamResponse(to: Self.makeTurnPrompt(turnInput), options: effectiveGenerationOptions())
                for try await snapshot in stream {
                    if Task.isCancelled { break }
                    latestFull = snapshot.content
                    if let delta = Self.streamDelta(from: emitted, to: latestFull) {
                        emitted += delta
                        sawObservableActivity.withLock { $0 = true }
                        continuation.yield(.textDelta(delta))
                    }
                    if activeTier == .privateCloud {
                        let reasoningFull = Self.reasoningText(from: Array(snapshot.transcriptEntries))
                        if let delta = Self.streamDelta(from: emittedReasoning, to: reasoningFull) {
                            emittedReasoning += delta
                            sawObservableActivity.withLock { $0 = true }
                            continuation.yield(.reasoningDelta(delta))
                        }
                    }
                    // #102: a model stuck in a phrase loop would otherwise
                    // burn until the token cap. The breaker arms on the
                    // first qualifying repetition and abandons the stream
                    // only when the run keeps GROWING — bounded legitimate
                    // repetition (identical code rows, a requested refrain)
                    // ends, disarms, and streams through untouched.
                    if repetitionBreaker.shouldAbandon(afterObserving: Self.degenerateTailRepetitionRun(in: latestFull)) {
                        didTripRepetitionBreaker = true
                        Self.logger.notice("streamTurn: degenerate tail repetition escalated after \(latestFull.count, privacy: .public) chars — abandoning the stream, collapsing the looped tail (#102)")
                        // Keep the reply up to ONE copy of the loop: the
                        // full run is noise by definition, and replaying it
                        // into rebuilt sessions re-primes the loop.
                        latestFull = Self.collapsingDegenerateTail(latestFull)
                        break
                    }
                }
                connectionStatus = .connected
                // #257 lever 1b: the deterministic capability block lands
                // HERE — exactly once, after the model's text has fully
                // settled (post-loop, post-breaker), never mid-stream. No
                // `.textDelta` carries it; the `.finished` consumer replaces
                // the streamed placeholder content with this message's
                // content (ChatStore's resolved-slot swap), so the block
                // appears once in the bubble and once in stored history.
                let settled = Self.settledReplyContent(
                    latestFull, appendingCapabilityAnswer: turnAppendsCapabilityAnswer)
                // #338: the honesty guard, at the same settle point and for
                // the same reason the capability block lands here — after the
                // model's text has fully settled, never mid-stream. No
                // `.textDelta` carries the correction; the `.finished`
                // consumer's resolved-slot swap puts it in the bubble once.
                let guarded = honestyGuardedReply(
                    modelText: latestFull,
                    settledText: settled,
                    recorder: toolCallRecorder,
                    // #422 Task 11 / bar 422-H: see `send`'s identical call.
                    savedNote: turnInput.savedNote != nil)
                // #408-D: same settle point, same append rule — see `send`.
                let noted = Self.replyNotingGuardrailImageDegrade(
                    guarded, degradedImageCount: degradedImageCount)
                // `latestFull` is authoritative: if a snapshot ever rewrote
                // earlier text (no incremental delta exists for that), the
                // finished message still carries the model's real final text.
                var reply = Message(sender: .hermes, content: noted, status: .delivered)
                if !emittedReasoning.isEmpty { reply.reasoning = emittedReasoning }
                let usage = currentTokenUsage()
                appendAssistantMessage(reply, usage: usage)
                // #422 bar 422-D / ruling 2: see `send`'s identical call.
                recordMemoryUse(replyMessageID: reply.id)
                if didTripRepetitionBreaker {
                    // The abandoned session's internal transcript state is
                    // unknowable — rebuild the next turn from OUR message
                    // history (the durable source) instead of trusting it.
                    session = nil
                }
                continuation.yield(.finished(reply, usage, nil))
                return
            } catch {
                if !didToolPhaseCutRetry, Self.isToolPhaseCut(error) {
                    // #232: see `send` — the grind's structural end. Any text
                    // already streamed is abandoned with the dead session; the
                    // toolless retry repaints from scratch (grind turns have
                    // streamed nothing — the model was inside the tool loop).
                    didToolPhaseCutRetry = true
                    turnRoutedToolless = true
                    session = nil
                    Self.logger.notice("streamTurn: tool phase cut after \(ToolPhaseCutError.refusalThreshold) refusals — retrying toolless (#232)")
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: false)
                    continue
                }
                if !didCondenseRetry, Self.isContextOverflow(error) {
                    // #26's condense + #229's disarm: see rebuildForOverflowRetry.
                    didCondenseRetry = true
                    Self.logger.notice("streamTurn: context window exceeded — condensing and retrying toolless (#229)")
                    liveSession = await rebuildForOverflowRetry(attachments: attachments, excludingClientMessageID: clientMessageID)
                    continue
                }
                if Self.shouldRetryToolDecodeFailure(
                    error,
                    turnHadObservableActivity: sawObservableActivity.withLock { $0 },
                    didAlreadyRetry: didToolDecodeRetry
                ) {
                    didToolDecodeRetry = true
                    toolDecodeRetryCount += 1
                    let toolName = (error as? LanguageModelSession.ToolCallError)?.tool.name ?? "unknown"
                    Self.logger.notice("streamTurn: \(toolName, privacy: .public) argument decode failed before anything ran — retrying the turn once (#197)")
                    // Mid-turn throw → the live session's transcript state
                    // is unknowable (#102's rule) — rebuild from our history.
                    session = nil
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: false)
                    continue
                }
                if Self.shouldDegradeImagesAfterGuardrail(
                    error,
                    tierIsOnDevice: activeTier == .onDevice,
                    turnCarriedImages: !turnInput.images.isEmpty,
                    didAlreadyDegrade: didGuardrailImageDegrade
                ) {
                    // #408: see `send` — the declined picture is demoted to
                    // #390-B's placeholder and the turn is re-run once.
                    didGuardrailImageDegrade = true
                    degradedImageCount = turnInput.images.count
                    // #422 fix round 1: reuse the ALREADY-DERIVED savedNote —
                    // same message, same clientMessageID, same turn, so the
                    // store answer cannot have changed between legs.
                    // #422 bar 422-D: re-apply THIS turn's already-composed
                    // memory prefix — same reason `savedNote` is reused, and
                    // a second retrieval here would charge the window twice.
                    turnInput = Self.prefixed(
                        Self.degradedTurnInput(message: message, attachments: attachments, savedNote: turnInput.savedNote),
                        with: memoryPrefix)
                    Self.logger.notice("streamTurn: on-device guardrail declined a sighted turn — retrying once with \(degradedImageCount, privacy: .public) image(s) demoted to the OCR placeholder (#408)")
                    session = nil
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: false)
                    continue
                }
                connectionStatus = .error
                continuation.yield(.failed(failureMessageForActiveTier(error)))
                return
            }
        }
    }

    /// #30: a failed PCC turn names its tier and what happens next — the
    /// router's per-message resolution moves the NEXT turn on-device when the
    /// tier stays rate-limited/unavailable (visible indicator change).
    private func failureMessageForActiveTier(_ error: Error) -> String {
        let base = Self.failureMessage(for: error)
        guard activeTier == .privateCloud else { return base }
        return "Private Cloud β: \(base) The next message continues on-device if the tier stays unavailable."
    }

    /// Concatenated reasoning text from a snapshot's transcript entries (#30).
    /// Reasoning segments never appear in the response content — this is the
    /// only place they surface.
    @available(iOS 27.0, *)
    nonisolated static func reasoningText(from entries: [Transcript.Entry]) -> String {
        entries.compactMap { entry -> String? in
            guard case .reasoning(let reasoning) = entry else { return nil }
            let text = reasoning.segments.compactMap { segment -> String? in
                if case .text(let textSegment) = segment { return textSegment.content }
                return nil
            }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.joined(separator: "\n")
    }

    func loadConversation() async -> Conversation {
        restoreFromCacheIfNeeded()
        if let currentConversation { return currentConversation }
        let fresh = Conversation(title: Conversation.defaultTitle)
        currentConversation = fresh
        return fresh
    }

    /// #78: adopt a consumer-side truncation (regenerate, edit-and-resend).
    ///
    /// This backend holds TWO copies of the thread and both have to follow:
    /// `currentConversation`, which ChatStore merges back over its rendered
    /// transcript at the end of every turn and on every poll tick (leave it
    /// alone and the removed rows come straight back), and the live
    /// `LanguageModelSession`, which carries its own `Transcript`. A re-roll
    /// that left the session alive would re-ask the question with the
    /// original answer still in context — the truncation would be undone in
    /// the model's reply instead of in the transcript. The next turn
    /// rebuilds the session by replaying the truncated history, which is
    /// exactly the handover `openSession`/`installTools` already use.
    func adoptTruncatedConversation(_ conversation: Conversation) {
        currentConversation = conversation
        session = nil
        sessionToolNames = []
        Self.logger.notice("adopted a consumer truncation: thread is now \(conversation.messages.count) message(s); live session invalidated (#78)")
    }

    func clearConversation() async throws -> Conversation {
        session = nil
        condensedMemory = nil
        // #30: the escalation offer is per-conversation.
        shouldOfferPrivateCloudEscalation = false
        escalationOfferDismissed = false
        // #233: the wee-hour AM/PM ask is per-conversation.
        toolRelay?.endConversationToolState()
        let fresh = Conversation(title: Conversation.defaultTitle)
        currentConversation = fresh
        return fresh
    }

    // MARK: - Model controls

    func availableModels() async throws -> [String] {
        // PCC appears ONLY when the entitlement + availability check passes
        // (#30) — a denied/pending Apple application never fakes a tier.
        var models = [Self.onDeviceModelID]
        if isPrivateCloudAvailable {
            models.append(Self.privateCloudModelID)
        }
        return models
    }

    /// Matches Sessions API semantics the UI already knows: the switch applies
    /// to the NEXT session. The response text carries the authoritative
    /// "Context: N tokens" for the CTX meter's denominator (#4) — read from
    /// the model at runtime, never hardcoded.
    @discardableResult
    func switchModel(_ identifier: String) async throws -> String? {
        switch identifier {
        case Self.onDeviceModelID:
            setPreferredTier(privateCloud: false)
        case Self.privateCloudModelID where isPrivateCloudAvailable:
            setPreferredTier(privateCloud: true)
        default:
            throw LocalChatBackendError.unknownModel(identifier)
        }
        return Self.modelSwitchResponseText(modelID: identifier, contextSize: await activeContextSize())
    }

    // MARK: - Sessions (#190: backed by the keyed store; the single-slot
    // cache remains only the kill/relaunch restore path)

    func listSessions() async throws -> [HermesSessionInfo] {
        restoreFromCacheIfNeeded()
        adoptLegacySingleSlotIfNeeded()
        guard let sessionStore else {
            // Degraded mode (container creation failed): the pre-#190 single
            // slot, honestly — one live conversation or nothing.
            guard let conversation = currentConversation, !conversation.messages.isEmpty else { return [] }
            return [Self.sessionInfo(for: conversation)]
        }
        let currentID = currentConversation?.id
        var infos = sessionStore.sessionSummaries().map {
            Self.sessionInfo(for: $0, isActive: $0.id == currentID)
        }
        if let current = currentConversation, !current.messages.isEmpty, isLocalThread(current) {
            // The live thread outranks its stored row — the store's copy is
            // frozen at the last walk-away and may lag the conversation.
            infos.removeAll { $0.id == current.id.uuidString }
            infos.append(Self.sessionInfo(for: current))
        }
        return infos.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    func openSession(_ id: String) async throws -> Conversation {
        restoreFromCacheIfNeeded()
        adoptLegacySingleSlotIfNeeded()
        if let conversation = currentConversation, conversation.id.uuidString == id {
            // Recreate the LanguageModelSession on next send so the reopened
            // history is replayed into the transcript.
            session = nil
            return conversation
        }
        guard let uuid = UUID(uuidString: id) else {
            throw LocalChatBackendError.sessionNotFound(id)
        }
        guard let stored = sessionStore?.conversation(withID: uuid) else {
            // #190B: a row that EXISTS but yields no conversation is a
            // transcript decode failure, not an unknown id — folding the two
            // together would tell the user a stored session doesn't exist.
            // The store already logged the decode error; this is the honest
            // user-facing half.
            if sessionStore?.hasSession(withID: uuid) == true {
                throw LocalChatBackendError.sessionUnreadable(id)
            }
            throw LocalChatBackendError.sessionNotFound(id)
        }
        // Persistence of the DEPARTING thread is not this path's job: it
        // lives in ChatStore's abandonPendingRun — #184's one teardown
        // primitive, which every context switch already routes through.
        currentConversation = stored
        session = nil
        condensedMemory = nil
        // #30: the escalation offer is per-conversation.
        shouldOfferPrivateCloudEscalation = false
        escalationOfferDismissed = false
        // #233: the wee-hour AM/PM ask is per-conversation.
        toolRelay?.endConversationToolState()
        return stored
    }

    /// #190 Phase 3: adopt the single-slot cached conversation into the keyed
    /// store. Runs once per process before any sessions read; the id-keyed
    /// upsert makes it idempotent across relaunches (running twice can never
    /// produce two copies), and the cache itself is deliberately untouched —
    /// it stays the kill/relaunch restore path. Beyond the one-time upgrade
    /// migration, this is also the standing catch-up for a thread that was
    /// live when the process died: no walk-away ran, so the cache alone
    /// holds its newest turns.
    private func adoptLegacySingleSlotIfNeeded() {
        guard !didAttemptLegacyAdoption, let sessionStore else { return }
        didAttemptLegacyAdoption = true
        guard let cached = persistence.loadConversationCache(),
              !cached.messages.isEmpty,
              isLocalThread(cached) else { return }
        sessionStore.upsertSession(cached)
    }

    func reconcileFromServer() async -> Conversation? {
        // No server: a local run either finishes in-process or fails honestly.
        nil
    }

    // MARK: - Session lifecycle

    /// Returns the live session when the next turn still fits its context;
    /// otherwise rebuilds (condensing as needed). Also the lazy-creation path.
    func preparedSession(  // harness-visible
        nextPrompt: String,
        attachments: [PendingAttachment],
        excludingClientMessageID: UUID?
    ) async -> LanguageModelSession {
        restoreFromCacheIfNeeded()
        if currentConversation == nil {
            currentConversation = Conversation(title: Conversation.defaultTitle)
        }
        // #196 (PROMOTED): classify THIS turn before any gate reads the
        // route. One extra guided generation (~0.6s measured on device,
        // greedy); errors fail safe to armed inside the router. In DEBUG
        // the A/B picker can pin a legacy cell, which disables routing for
        // the launch so every non-routed cell stays pure.
        // #176: the turn's incoming attachments count. This runs BEFORE the
        // user message is appended, so the stored conversation doesn't know
        // about the image being sent right now.
        //
        // #207 (PROMOTED): hoisted ABOVE the router. It used to be computed
        // six lines BELOW the routing call and never passed, so the router
        // could not tell an image was attached and sent "what does this
        // say?" toolless — 0/4 reading prompts, measured twice.
        let hasImage = ConversationImageSource.hasImage(in: currentConversation, incoming: attachments)
        if Self.turnRoutingEnabled {
            // #202D: classify WITH the previous assistant turn. Drawn from
            // the same `transcriptTurns` source `rebuildSession` replays, so
            // the router sees exactly the turn the model will see. Without
            // it, "Yes please" after an offer is just conversation and routes
            // toolless — 6/6 in #202A, and the resulting disarmed turn then
            // LIED about having acted in 10/12 cases (#202B).
            let priorAssistantTurn = Self.transcriptTurns(
                from: currentConversation?.messages ?? [],
                excludingClientMessageID: excludingClientMessageID
            ).last { $0.role == .assistant }?.text ?? ""
            // #257: ONE generation carries both fields — the gate Bool and
            // the capability-question Bool. The append decision is frozen
            // here, at route time (see `turnAppendsCapabilityAnswer`).
            // #422 bar 422-D: the router sees the user's OWN words. The
            // memory prefix is composed after this call returns
            // (`memoryPrefix(for:)` + `prefixed(_:with:)`), so a retrieved
            // memory can never decide whether this turn gets a tool belt.
            // Recorded rather than merely true-by-reading: the spy is what
            // makes the ordering falsifiable.
            lastRoutedPrompt = nextPrompt
            let route = await routeTurn(
                prompt: nextPrompt, context: priorAssistantTurn, hasImage: hasImage)
            turnRoutedToolless = !route.needsDeviceTool
            turnAppendsCapabilityAnswer = Self.turnAppendsCapabilityAnswer(
                routedToolless: turnRoutedToolless,
                isCapabilityQuestion: route.isCapabilityQuestion)
            Self.logger.notice("router: turn routed \(self.turnRoutedToolless ? "toolless" : "armed", privacy: .public) cap=\(route.isCapabilityQuestion, privacy: .public) ctx=\(priorAssistantTurn.isEmpty ? "none" : "prior-turn", privacy: .public) img=\(hasImage, privacy: .public) (#207)")
        } else {
            turnRoutedToolless = false
            turnAppendsCapabilityAnswer = false
        }
        if let session {
            let offered = effectiveOfferedTools(hasImageInContext: hasImage)
            let notesFingerprint = currentNotesFingerprint()
            if offered.map(\.name) != sessionToolNames {
                Self.logger.notice("preparedSession: offered tool set changed for this turn — recreating the session (#176)")
            } else if notesFingerprint != sessionNotesFingerprint {
                // #422 bar 422-D: the notes block lives in the INSTRUCTIONS,
                // and a session is stuck with the instructions it was born
                // with — so a saved, edited or deleted note has to rebuild.
                // Gated on the fingerprint rather than on "a note exists", so
                // this fires ONCE per change and never per turn.
                memoryNotesRebuildCount += 1
                Self.logger.notice("preparedSession: the explicit-notes set changed — rebuilding so the instructions carry it (#422)")
            } else if injectedMemoryTokensThisSession > 0,
                      injectedMemoryTokensThisSession >= (await injectedMemoryRebuildThreshold()) {
                // #422 bar 422-D: prefixes have accumulated inside the live
                // session's own transcript, where `currentConversation`
                // cannot see them. Rebuild from the (prefix-free) history
                // before the drift reaches the model as a #26 overflow.
                memoryAccountingRebuildCount += 1
                Self.logger.notice("preparedSession: ~\(self.injectedMemoryTokensThisSession, privacy: .public) tok of memory prefix have accumulated in this session — rebuilding before the window overflows (#422)")
            } else {
                let turns = Self.transcriptTurns(
                    from: currentConversation?.messages ?? [],
                    excludingClientMessageID: excludingClientMessageID
                )
                if await fitsContext(turns: turns, nextPrompt: nextPrompt, hasImageInContext: hasImage) {
                    return session
                }
                Self.logger.notice("preparedSession: context budget approached — condensing older turns (#26)")
            }
        }
        return await rebuildSession(
            attachments: attachments,
            excludingClientMessageID: excludingClientMessageID,
            forceCondense: false
        )
    }

    @discardableResult
    func rebuildSession(  // harness-visible
        attachments: [PendingAttachment],
        excludingClientMessageID: UUID?,
        forceCondense: Bool
    ) async -> LanguageModelSession {
        let turns = Self.transcriptTurns(
            from: currentConversation?.messages ?? [],
            excludingClientMessageID: excludingClientMessageID
        )
        // #176: one image-presence read drives BOTH the offered belt and the
        // instructions' capability list, so the persona can never advertise a
        // tool this session wasn't given.
        let hasImage = ConversationImageSource.hasImage(in: currentConversation, incoming: attachments)
        let blueprint = await sessionBlueprint(
            for: turns,
            hasImageInContext: hasImage,
            forceCondense: forceCondense
        )
        condensedMemory = blueprint.condensedMemory
        // #422 bar 422-D: the fresh session replays `currentConversation`,
        // which holds the user's bare messages — every prefix injected into
        // the OLD session's transcript is gone with it, so the accounting
        // starts over. The fingerprint is read here, alongside the blueprint
        // that just composed the block, so the session and the identity we
        // will compare it against can never describe different note sets.
        //
        // Known and accepted residual: a MID-TURN rebuild (the #229 overflow
        // retry, #232's phase cut, #197's decode retry, #408's degrade) resets
        // the counter while this turn's prefix is about to be re-sent into the
        // fresh session — so that one prefix goes unaccounted until the next
        // turn's `memoryPrefix` call. It is one turn of undercount on paths
        // that are already shedding far more than a prefix's worth of context
        // (a disarmed belt, a forced condensation), and re-adding it here
        // would double-count every ORDINARY rebuild, which is the common case.
        injectedMemoryTokensThisSession = 0
        sessionNotesFingerprint = currentNotesFingerprint()
        let offered = effectiveOfferedTools(hasImageInContext: hasImage)
        let fresh = makeSession(from: blueprint, offering: offered)
        session = fresh
        recordSessionBudgetIfVerbose(offered: offered, transcript: fresh.transcript)
        return fresh
    }

    /// #229: the #26 overflow retry must not re-arm the belt. Filed on device
    /// evidence: the armed retry condensed, rebuilt — and re-armed 13 tools
    /// (~1470 tok measured, L0-C) into the 8,192-token window it had just
    /// overflowed by 26 tokens, then overflowed again. The retry is now a
    /// routed-toolless turn (#232's shape): condensed history, empty belt,
    /// the toolless instruction set — both via the `turnRoutedToolless` gate.
    /// The disarm is per-turn by construction: the next turn's
    /// `preparedSession` re-routes from scratch. Pre-turn condensation keeps
    /// the belt on purpose — the router armed that turn and nothing failed;
    /// only the mid-turn overflow RETRY disarms.
    func rebuildForOverflowRetry(  // harness-visible
        attachments: [PendingAttachment],
        excludingClientMessageID: UUID?
    ) async -> LanguageModelSession {
        // #422 bar 422-D: counted, not merely logged. The injected-token
        // accounting exists to keep this number at zero on memory turns, and
        // a mitigation nobody can count is a mitigation nobody can falsify.
        overflowRetryCount += 1
        turnRoutedToolless = true
        return await rebuildSession(
            attachments: attachments,
            excludingClientMessageID: excludingClientMessageID,
            forceCondense: true
        )
    }

    /// #228 (Lane 0.2): the number nobody had ever seen on the night #225's
    /// cap was falsified — what the armed belt itself costs in tokens against
    /// the window, before the user's first word. One line per session BUILD,
    /// which includes #26's mid-turn condense-and-rebuild.
    ///
    /// **REVISED 2026-08-02, same night, after the device falsified L0-D.**
    /// The first shape measured DURING the turn (fire-and-forget at build):
    /// its tokenizer round-trips shared the FM client plumbing with the live
    /// stream, and their teardown swept the turn's prewarm sessions and
    /// invalidated its InferenceProvider connection — ModelManagerError 1001,
    /// surfaced as "LanguageModelError -1", killing the turn in one second.
    /// The sim could never catch this (no model). So: VALUES are captured
    /// here, synchronously and for free; the tokenizer round-trips and the
    /// log line run only at `flushSessionBudgetMeasurements()`, after the
    /// turn has fully ended and the model runtime is quiet.
    ///
    /// Counts come from the model's OWN tokenizer
    /// (`SystemLanguageModel.tokenCount(for:)`); where it is unavailable —
    /// the sim has no model — the line shows "—" and never invents.
    func recordSessionBudgetIfVerbose(offered: [any Tool], transcript: Transcript) {  // harness-visible
        guard TalariaLog.isVerbose else { return }
        pendingSessionBudgets.append((toolCount: offered.count, tools: offered, transcript: transcript))
    }

    /// Session builds awaiting their post-turn measurement. One entry per
    /// build — a #26 overflow turn legitimately holds two.
    private(set) var pendingSessionBudgets: [(toolCount: Int, tools: [any Tool], transcript: Transcript)] = []  // harness-visible

    /// Drains the queue and measures OUTSIDE the turn. Called from both send
    /// paths once the turn is over; the spawned task contends with nothing
    /// unless the user fires the next turn within its ~100ms of tokenizer
    /// work — an accepted, narrow window in a diagnostic mode.
    func flushSessionBudgetMeasurements() {  // harness-visible
        guard !pendingSessionBudgets.isEmpty else { return }
        let pending = pendingSessionBudgets
        pendingSessionBudgets = []
        Task { [model] in
            // #101's freed-budget number: what the FULL installed belt would
            // have cost this turn. Measured directly here, ONCE per flush
            // (the installed belt doesn't change between queued entries) —
            // NOT by reusing the offered-belt measurement when the counts
            // match. In DEBUG, `effectiveOfferedTools` can run the offered
            // set through `shapedBelt`, whose `.armedRemfix`/`.armedFix`/
            // `.armedNoschema` cells map tools to modified copies: same
            // count, same names, different description/schema content. A
            // count- or name-based equality check would silently mislabel
            // that shaped belt's cost as the full belt's — exactly the cells
            // built to test description/schema changes (#284 review
            // finding). Direct measurement has no such blind spot.
            let fullBelt = await MainActor.run { self.tools }
            let fullBeltTokens: Int?
            if fullBelt.isEmpty {
                fullBeltTokens = 0
            } else {
                fullBeltTokens = try? await model.tokenCount(for: fullBelt)
            }
            for entry in pending {
                // An empty belt (a routed-toolless turn) costs 0 by
                // definition — knowable without a tokenizer, never "—".
                let toolTokens: Int?
                if entry.tools.isEmpty {
                    toolTokens = 0
                } else {
                    toolTokens = try? await model.tokenCount(for: entry.tools)
                }
                let transcriptTokens = try? await model.tokenCount(for: entry.transcript)
                let line = Self.sessionBudgetLogLine(
                    toolCount: entry.toolCount,
                    toolTokens: toolTokens,
                    transcriptTokens: transcriptTokens,
                    window: await self.activeContextSize(),
                    fullBeltTokens: fullBeltTokens
                )
                Self.logger.notice("\(line, privacy: .public)")
            }
        }
    }

    /// #232: the cut arrives bare (thrown straight through a tool wrapper) or
    /// wrapped in the SDK's `ToolCallError` — both mean the same thing: the
    /// tool phase is over, retry this turn toolless.
    nonisolated static func isToolPhaseCut(_ error: Error) -> Bool {
        if error is ToolPhaseCutError { return true }
        return (error as? LanguageModelSession.ToolCallError)?.underlyingError is ToolPhaseCutError
    }

    /// Pure and pinned by test — the grep key a device-run log gets read by.
    nonisolated static func sessionBudgetLogLine(
        toolCount: Int,
        toolTokens: Int?,
        transcriptTokens: Int?,
        window: Int,
        fullBeltTokens: Int?
    ) -> String {
        let tools = toolTokens.map(String.init) ?? "—"
        let transcript = transcriptTokens.map(String.init) ?? "—"
        let free: String
        if let toolTokens, let transcriptTokens {
            free = "~\(window - toolTokens - transcriptTokens) free"
        } else {
            free = "free —"
        }
        // #101: the full-belt contrast — what the whole installed belt would
        // have cost this turn, so a narrowed (or toolless) turn shows the
        // freed budget. Unknown stays honest — "—", never a fabricated 0.
        // The tag stays last — every line in this file ends on "(#228)".
        let fullBelt = fullBeltTokens.map { "\($0)tok" } ?? "—"
        return "session budget: \(toolCount) tool(s) ~\(tools) tok + transcript ~\(transcript) tok of window \(window) — \(free) fullBelt=\(fullBelt) (#228)"
    }

    /// What a recreated session should contain: instructions (base persona,
    /// plus condensed memory of dropped turns when the history no longer fits)
    /// and the verbatim turn suffix to replay.
    struct SessionBlueprint {
        let instructions: String
        let verbatimTurns: [TranscriptTurn]
        let condensedMemory: String?
    }

    /// **Widened from `private` by #335 — `// harness-visible`, private in
    /// spirit.** Swift's `private` is FILE-scoped and the `condensation-fit`
    /// instrument lives in `LocalChatBackend+Preflight.swift`; this is the ONE
    /// seam that lets a SYNTHETIC transcript into production's real condenser,
    /// and it is the right seam rather than a convenient one. The instrument
    /// must not reimplement condensation — a measurement of a lookalike
    /// measures nothing — and must not read the user's real conversation,
    /// which would be unrepeatable and would answer a question about that
    /// day's chat rather than about the mechanism (#210's residual is the
    /// mechanism). Production reaches this through `rebuildSession`, which
    /// supplies the turns from `currentConversation`; the instrument supplies
    /// its own and changes nothing else.
    func sessionBlueprint(  // harness-visible
        for turns: [TranscriptTurn],
        hasImageInContext: Bool,
        forceCondense: Bool
    ) async -> SessionBlueprint {
        // #422 bar 422-D: the explicit-notes block rides the INSTRUCTIONS,
        // and it is folded in HERE rather than at the concatenation below so
        // that both exits carry it — the cheap byte-bound early return as
        // well as the condensing path — and so every budget number computed
        // from `baseInstructions` already counts what the notes cost.
        let baseInstructions = await instructionsWithMemoryNotes(hasImageInContext: hasImageInContext)
        // Budget from the model at RUNTIME — never hardcoded (#26 ground rule).
        let contextBudget = max(1024, await activeContextSize() - Self.responseHeadroomTokens(for: activeTier))

        // Cheap upper bound first: every token is at least one UTF-8 byte, so
        // a byte total inside the budget can never overflow it — skip the
        // tokenizer round trip for the common short-history case.
        let byteTotal = baseInstructions.utf8.count + turns.reduce(0) { $0 + $1.text.utf8.count }
        if !forceCondense, byteTotal <= contextBudget {
            return SessionBlueprint(instructions: baseInstructions, verbatimTurns: turns, condensedMemory: nil)
        }

        var counts: [Int] = []
        counts.reserveCapacity(turns.count)
        for turn in turns {
            counts.append(await intelligence.measuredTokenCount(of: turn.text))
        }
        let instructionTokens = await intelligence.measuredTokenCount(of: baseInstructions)
        let available = max(512, contextBudget - instructionTokens)

        var split = Self.verbatimSplitIndex(turnTokenCounts: counts, availableBudget: available)
        if forceCondense, split == 0, turns.count > 1 {
            // The live session overflowed even though our estimate said the
            // history fits (tokenizer estimates are approximate) — drop at
            // least the older half so the retry actually has room.
            split = turns.count / 2
        }
        guard split > 0 else {
            return SessionBlueprint(instructions: baseInstructions, verbatimTurns: turns, condensedMemory: nil)
        }

        // #30: the conversation just outgrew the on-device window — offer the
        // 32K PCC tier ONCE per conversation, only when it's actually
        // available. The user decides; nothing escalates silently.
        if activeTier == .onDevice, !escalationOfferDismissed, isPrivateCloudAvailable {
            shouldOfferPrivateCloudEscalation = true
        }

        var memoryLines: [String] = []
        for turn in turns[..<split] {
            let head = await intelligence.trimmed(turn.text, toTokenBudget: Self.condensedPerTurnTokens)
            memoryLines.append("\(turn.role == .user ? "User" : "Talaria"): \(head)")
        }
        let memory = await intelligence.trimmed(
            memoryLines.joined(separator: "\n"),
            toTokenBudget: Self.condensedMemoryTokens
        )
        #if DEBUG
        // #196 `-noinstr` cells: NO instructions means no instructions even
        // when condensation fires — the memory block has nowhere to live,
        // so the condensed turns are DROPPED outright (kept in
        // `condensedMemory` for diagnostics only). Without this, the
        // preamble concatenation below would silently convert the cell
        // into an instructions-bearing session mid-conversation.
        // Production base instructions are never empty.
        if baseInstructions.isEmpty {
            Self.logger.notice("sessionBlueprint: \(split, privacy: .public) condensed turn(s) DROPPED — the -noinstr cell carries no instructions entry for memory (#196)")
            return SessionBlueprint(
                instructions: "",
                verbatimTurns: Array(turns[split...]),
                condensedMemory: memory
            )
        }
        #endif
        let instructions = baseInstructions + "\n\n" + Self.condensedMemoryPreamble + "\n" + memory
        Self.logger.notice("sessionBlueprint: condensed \(split) older turn(s) into memory; \(turns.count - split) replayed verbatim (#26)")
        return SessionBlueprint(
            instructions: instructions,
            verbatimTurns: Array(turns[split...]),
            condensedMemory: memory
        )
    }

    /// Whether instructions + full history + the next prompt fit the runtime
    /// context budget. Byte count is a safe upper bound for token count, so
    /// the tokenizer only runs once histories actually get long.
    func fitsContext(turns: [TranscriptTurn], nextPrompt: String, hasImageInContext: Bool) async -> Bool {  // harness-visible
        // #422 bar 422-D: the SAME instructions `sessionBlueprint` would
        // build (notes included) — a fit check reading a different
        // instructions text than the session carries is the drift that makes
        // "it fits" a guess.
        let baseInstructions = await instructionsWithMemoryNotes(hasImageInContext: hasImageInContext)
        let contextSize = await activeContextSize()
        // #422 bar 422-D, FIX ROUND 1: reserve room for THIS turn's prefix.
        //
        // `injectedMemoryTokensThisSession` covers turns 1…N−1 — the prefixes
        // already in the live transcript. It cannot cover turn N's, because
        // this check runs BEFORE retrieval (bar 422-D's own ordering: the
        // router and the fit check see the user's bare words). So every
        // generation used to carry one unaccounted prefix — ~330 tokens
        // typically, ~460 with a just-saved notice, two of them on a retry
        // leg that reset the counter — against 1,024 tokens of reply
        // headroom.
        //
        // The reserve is one whole `memoryBlockTokens`: the most this turn
        // could possibly spend, taken unconditionally while memory is ON
        // because at this point nobody knows yet whether the turn will
        // retrieve. Paying up to 800 tokens of the phone's 7,168 to
        // guarantee the next prefix has somewhere to land is the trade —
        // rebuild a little early, never overflow mid-turn.
        //
        // With memory OFF the reserve is not taken at all: no retrieval, no
        // notes block, no prefix, so there is nothing to reserve for and the
        // budget is byte-for-byte what it was before this lane.
        let contextBudget = max(
            256,
            max(1024, contextSize - Self.responseHeadroomTokens(for: activeTier))
                - (memoryIsOn ? MemoryBudget.memoryBlockTokens(contextSize: contextSize) : 0))
        // #422 bar 422-D: the prefixes already inside the LIVE session's
        // transcript. `turns` comes from `currentConversation`, which stores
        // the user's bare messages, so without this term the estimate is low
        // by everything memory has injected since the last rebuild — and the
        // first thing to notice would be the model, as the #26 overflow.
        //
        // Yes, a TOKEN count is being added to a BYTE total here, and it is
        // sound in the only direction that matters: every token is at least
        // one byte, so the real token total is still ≤ `byteTotal`, and the
        // fast path's guarantee ("inside the budget in bytes ⇒ inside it in
        // tokens") survives. The alternative — omitting it from the cheap
        // bound — would let the fast path return `true` for a session the
        // slow path would have rejected, which is the one outcome this term
        // exists to prevent.
        let byteTotal = baseInstructions.utf8.count
            + nextPrompt.utf8.count
            + injectedMemoryTokensThisSession
            + turns.reduce(0) { $0 + $1.text.utf8.count }
        if byteTotal <= contextBudget { return true }
        var tokens = injectedMemoryTokensThisSession
        tokens += await intelligence.measuredTokenCount(of: baseInstructions)
        tokens += await intelligence.measuredTokenCount(of: nextPrompt)
        for turn in turns {
            tokens += await intelligence.measuredTokenCount(of: turn.text)
            if tokens > contextBudget { return false }
        }
        return tokens <= contextBudget
    }

    private func makeSession(from blueprint: SessionBlueprint, offering offered: [any Tool]) -> LanguageModelSession {
        #if DEBUG
        // #196: device A/B runs are self-labeling — Console shows which
        // cell built this session.
        Self.logger.notice("session shape: \(Self.activeSessionShape.rawValue, privacy: .public) — \(offered.count, privacy: .public) tool(s) registered (#196)")
        #endif
        let entries = Self.transcriptEntries(
            instructions: blueprint.instructions,
            verbatimTurns: blueprint.verbatimTurns
        )
        // Tools come from the #28 belt, gated for this turn by #176 (empty
        // until AppContainer installs the belt). The transcript's Instructions
        // entry carries no toolDefinitions — the session's `tools:` parameter
        // is the operative wiring; if tool-calling misbehaves on replayed
        // sessions, populate `Transcript.ToolDefinition`s here (flagged for
        // device verify).
        //
        // Recorded so `preparedSession` can tell when the live session's tool
        // list has gone stale against the current turn's context.
        sessionToolNames = offered.map(\.name)
        //
        // #30: both SystemLanguageModel and PrivateCloudComputeLanguageModel
        // conform to LanguageModel (iOS 27) — the session API is unified, so
        // the PCC tier is one argument, not a second code path.
        if Self.pccGrantConfirmed, activeTier == .privateCloud {
            return LanguageModelSession(
                model: PrivateCloudComputeLanguageModel(),
                tools: offered,
                transcript: Transcript(entries: entries)
            )
        }
        return LanguageModelSession(model: model, tools: offered, transcript: Transcript(entries: entries))
    }

    /// The transcript entries a rebuilt session replays: the instructions
    /// block — when there IS one: the #196 `-noinstr` cells carry none, and
    /// an empty string means the transcript simply has no instructions
    /// entry (production instructions are never empty, so the guard is
    /// inert outside the DEBUG instrument) — followed by the verbatim
    /// turns. Static + nonisolated so the no-instructions-entry constraint
    /// is unit-pinned.
    nonisolated static func transcriptEntries(
        instructions: String,
        verbatimTurns: [TranscriptTurn]
    ) -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = []
        if !instructions.isEmpty {
            entries.append(.instructions(Transcript.Instructions(
                id: UUID().uuidString,
                segments: [.text(Transcript.TextSegment(id: UUID().uuidString, content: instructions))],
                toolDefinitions: []
            )))
        }
        for turn in verbatimTurns {
            let segment = Transcript.Segment.text(
                Transcript.TextSegment(id: UUID().uuidString, content: turn.text)
            )
            switch turn.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(
                    id: UUID().uuidString,
                    segments: [segment],
                    options: GenerationOptions(),
                    responseFormat: nil
                )))
            case .assistant:
                entries.append(.response(Transcript.Response(
                    id: UUID().uuidString,
                    assetIDs: [],
                    segments: [segment]
                )))
            }
        }
        return entries
    }

    // MARK: - Session-shape seam (#196, reworked from #194/176C)

    /// The tools this session should REGISTER, after the #176 turn gate. In
    /// DEBUG the #196 session-shape instrument can empty the belt (the
    /// `toolless` cell); Release compiles down to the production expression.
    func effectiveOfferedTools(hasImageInContext hasImage: Bool) -> [any Tool] {  // harness-visible
        // #196 (PROMOTED): a routed-toolless turn registers NO belt — the
        // full structural cure, not a call gate (nocall proved schemas in
        // context sustain the disclaimer tic on their own). Only ever true
        // when routing is enabled for this launch.
        if turnRoutedToolless { return [] }
        #if DEBUG
        guard Self.activeSessionShape.registersTools else { return [] }
        return Self.shapedBelt(
            from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: hasImage),
            shape: Self.activeSessionShape
        )
        #else
        return DeviceToolBelt.offeredTools(from: tools, hasImageInContext: hasImage)
        #endif
    }

    /// The generation options for this turn's respond/stream call. In DEBUG
    /// the #196 instrument reroutes through the shaped variant — identity
    /// for every cell but `armed-nocall`, which is the one cell whose
    /// treatment lives in the OPTIONS, not the belt or the text. This is
    /// the clean live-path seam the dispatch asked about: nocall works from
    /// the Diagnostics picker, not only in the battery. Release compiles
    /// down to the production expression.
    func effectiveGenerationOptions() -> GenerationOptions {  // harness-visible
        #if DEBUG
        return Self.shapedGenerationOptions(
            Self.chatGenerationOptions(for: activeTier),
            shape: Self.activeSessionShape
        )
        #else
        return Self.chatGenerationOptions(for: activeTier)
        #endif
    }

    /// The base instructions for this turn's session. In DEBUG the #196
    /// instrument reroutes through the shaped variants (the `armed` control
    /// cell delegates straight back to production); Release compiles down to
    /// the production expression.
    func effectiveInstructionsText(hasImageInContext hasImage: Bool) -> String {  // harness-visible
        // #196 (PROMOTED): a routed-toolless turn speaks the licensed bare
        // branch — the toolless-lic2 payload, the text that measured 60/60
        // content and clean on device.
        // #385: `activeTier` rides every production path. All three branches,
        // because the toolless branch is the one a routed turn actually takes
        // (#196) — gating only the armed branch would have left the common
        // case telling the same lie.
        if turnRoutedToolless {
            return Self.productionToollessInstructions(
                deviceContext: Self.deviceContextLine(),
                tier: activeTier,
                hasImageTools: hasImage
            )
        }
        #if DEBUG
        return Self.instructionsText(
            for: Self.activeSessionShape,
            deviceContext: Self.deviceContextLine(),
            tier: activeTier,
            hasTools: !tools.isEmpty,
            hasImageTools: hasImage
        )
        #else
        return Self.instructionsText(
            deviceContext: Self.deviceContextLine(),
            tier: activeTier,
            hasTools: !tools.isEmpty,
            hasImageTools: hasImage
        )
        #endif
    }

    // MARK: - #257 lever 1b: the deterministic capability answer

    /// The append decision, pure and pinned: ONLY a turn the router routed
    /// TOOLLESS and flagged as a capability question appends the block. An
    /// armed capability question appends nothing (the armed persona already
    /// carries the registry enumeration, #284), and a toolless
    /// non-capability turn appends nothing (that unsolicited block is
    /// exactly the over-serving bar 257-1-B exists to catch).
    nonisolated static func turnAppendsCapabilityAnswer(
        routedToolless: Bool, isCapabilityQuestion: Bool
    ) -> Bool {
        routedToolless && isCapabilityQuestion
    }

    /// The ONE settle-point composition (#202D): `send` and `streamTurn`
    /// both produce their final reply text through this function, and the
    /// capability-detection probe scores the same composition — so the text
    /// a measured arm speaks can never drift from the text production
    /// speaks. The block comes from `CapabilityRegistry.capabilityAnswerBlock`
    /// — the only source of that text — and is APPENDED (the 1b shape): the
    /// model's own reply survives verbatim as the prefix, so a
    /// false-positive detection costs an unsolicited true block, never a
    /// destroyed answer. Zero generation; the arity of a `for` loop cannot
    /// compress (#297's run `A04154D7` is why the model never recites this).
    nonisolated static func settledReplyContent(
        _ modelText: String, appendingCapabilityAnswer: Bool
    ) -> String {
        guard appendingCapabilityAnswer else { return modelText }
        let block = CapabilityRegistry.capabilityAnswerBlock()
        guard !block.isEmpty else { return modelText }
        guard !modelText.isEmpty else { return block }
        return modelText + "\n\n" + block
    }

    // MARK: - #338: the honesty guard

    /// **The honesty guard's ONE input, and the only place in the app where
    /// `.started` is filtered for it.**
    ///
    /// It exists as a type rather than two inline closures because the review
    /// of #338 found that both `.started` blocks could be DELETED with the
    /// whole suite still green: every test called `honestyGuardedReply`
    /// directly with a hand-built array, so nothing pinned where that array
    /// came from — and a guard reading an always-empty array fires on every
    /// honest tool-executing turn. One shared filter is one thing a test can
    /// hold (`HonestyGuardWiringTests.theRecorder…`).
    ///
    /// Three properties it owns, each pinned by test:
    /// - **`.started` only.** `ToolCallEvent.Phase` has exactly two cases
    ///   (`StreamingUpdate.swift`), and `.completed` describes the SAME call —
    ///   counting it would double a turn's apparent tool count.
    /// - **Admitted calls only**, which is free: `ToolEventRelay.started`
    ///   returns before emitting when the #225 governor refuses, so a refused
    ///   call never reaches this at all.
    /// - **Never reset mid-turn.** A tool that ran before #232's phase cut
    ///   staged a real confirmation card, so the guard must stay quiet for the
    ///   whole turn even though the retried leg ran toolless. Production gets
    ///   this by creating the recorder OUTSIDE the retry loop.
    ///
    /// Lock-backed rather than actor-isolated because tools emit off the main
    /// actor — the same reason the activity flags beside it are locked.
    final class TurnToolCallRecorder: Sendable {
        private let recorded = OSAllocatedUnfairLock(initialState: [String]())

        /// Admitted tool-call names this turn, in emit order.
        var executedToolNames: [String] { recorded.withLock { $0 } }

        /// The filter. Everything above depends on this one `guard`.
        func record(_ event: ToolCallEvent) {
            guard event.phase == .started else { return }
            recorded.withLock { $0.append(event.name) }
        }

        /// Installs the recorder on the relay for the duration of a turn,
        /// forwarding every event on to the caller's own observer.
        ///
        /// Recording happens BEFORE forwarding so a forwarding closure that
        /// throws or traps cannot silently cost the guard its input.
        @MainActor
        func install(
            on relay: ToolEventRelay?,
            forwardingTo forward: @escaping (ToolCallEvent) -> Void
        ) {
            relay?.emit = { [self] event in
                record(event)
                forward(event)
            }
        }
    }

    /// **THE USER-FACING CORRECTION. This string is OWEN'S RULING, not the
    /// lane's — it is deliberately the ONE place the copy lives, so approving
    /// or changing it is a one-line edit with no other consequence.**
    ///
    /// The #338 entry's default, implemented as written: *"keep the model's
    /// text but append a visibly distinct honest correction, rather than
    /// silently rewriting the model — silent rewriting is its own trust problem
    /// and forecloses diagnosis."* So the model's reply survives verbatim as
    /// the prefix; this is added, never substituted, and nothing is deleted.
    ///
    /// Three things it deliberately does NOT do: it does not blame the user, it
    /// does not promise that asking again will work (#337 measured 0 creations
    /// in 90 tries — a promise here would be a second false claim), and it does
    /// not name a tracker item at the user.
    /// Copy RULED by Owen 2026-08-12 (#338): the tighter of the two the lane
    /// proposed — same honesty, less self-flagellation, and it still names which
    /// text to distrust. He declined a retry suggestion for the reason recorded
    /// above: #337 measured 0 creations in 90 attempts, so inviting a retry
    /// would be a second broken promise.
    nonisolated static let honestyCorrectionNotice =
        "⚠️ **Nothing was created.** No reminder, alarm, or event was written to your "
        + "device — the reply above is inaccurate."

    /// **#422 bar 422-H — the same correction, for the memory artifact.**
    ///
    /// A SECOND constant rather than a widening of the one above, because the
    /// action copy names the wrong subject: telling a user *"No reminder,
    /// alarm, or event was written to your device"* after the model promised
    /// to remember their sister's address is a true sentence about something
    /// they did not ask for, and reads as a non-sequitur rather than a
    /// correction.
    ///
    /// It keeps every property Owen ruled on for the action copy (#338): it
    /// does not blame the user, it does not promise that asking again will
    /// work, and it names which text to distrust. It adds one thing the action
    /// copy does not need — **what to say instead**, because unlike a reminder
    /// there is no card the user could have tapped, so the honest reply has to
    /// point at the affordance that does work.
    ///
    /// Wording pinned by the #422 plan's naming rule (CLAUDE.md, Owen
    /// 2026-08-27): the outward identity is TALARIA on every phone-facing
    /// surface.
    nonisolated static let memoryCorrectionNotice =
        "⚠️ **Nothing was saved to memory.** Talaria only remembers what you ask "
        + "it to with \"Remember that…\" — the reply above is inaccurate."

    /// The correction that belongs to a claim. One switch, so a new kind
    /// cannot silently inherit copy that names the wrong artifact.
    nonisolated static func correctionNotice(
        for kind: ActionClaimDetector.ClaimKind
    ) -> String {
        switch kind {
        case .memoryCreation: memoryCorrectionNotice
        case .firstPersonCreation, .passiveCompletion, .presentStateSet,
             .presentStateOn, .impersonatedCard: honestyCorrectionNotice
        }
    }

    /// Appends a correction to a settled reply. Pure, so the exact composition
    /// is testable without a model.
    nonisolated static func appendingCorrection(_ notice: String, to text: String) -> String {
        guard !text.isEmpty else { return notice }
        return text + "\n\n" + notice
    }

    /// The action correction's composition, unchanged and still named — #338's
    /// tests pin this spelling.
    nonisolated static func appendingHonestyCorrection(to text: String) -> String {
        appendingCorrection(honestyCorrectionNotice, to: text)
    }

    /// #338-E's log line — pure and pinned by test, because it is the grep key
    /// a device-run log gets read by. `.notice` and NOT gated behind
    /// `TalariaLog.isVerbose`: a firing means the app was about to lie to the
    /// user, which is never a verbose-only event.
    nonisolated static func honestyGuardLogLine(
        kind: ActionClaimDetector.ClaimKind, executedCalls: Int, fireCount: Int
    ) -> String {
        "honesty-guard FIRED \(kind.rawValue) — \(executedCalls) tool call(s) executed this turn, "
            + "\(fireCount) firing(s) this session (#338)"
    }

    /// **The guard, applied at the one settle point.** Returns the text the user
    /// actually sees.
    ///
    /// - Parameters:
    ///   - modelText: what the MODEL said, before any block this app appends.
    ///     Passing the settled text here instead would let the guard read its
    ///     own output back in.
    ///   - settledText: the composed reply the correction attaches to.
    ///   - executedToolNames: admitted tool calls this turn, in emit order.
    ///   - priorActionToolExecutedInConversation: whether an action tool ran
    ///     EARLIER in this conversation. Production reads it off the relay's
    ///     conversation-scoped latch; the default keeps every existing test
    ///     honest at the strictest setting.
    ///   - savedNote: whether the explicit-note path really wrote a memory
    ///     THIS turn (#422 bar 422-H). The one fact that licenses a
    ///     `memoryCreation` claim, and it licenses nothing else. Default
    ///     `false` — the strict reading, so every existing caller keeps the
    ///     behaviour it had.
    ///
    /// Never throws and never returns less than it was given (#197: the tool
    /// path gains no throw; #338: the model's text is never rewritten or
    /// deleted). On a normal successful turn this is an identity function —
    /// bar 338-D's "adds no user-visible change to a normal turn".
    func honestyGuardedReply(  // harness-visible
        modelText: String,
        settledText: String,
        executedToolNames: [String],
        priorActionToolExecutedInConversation: Bool = false,
        savedNote: Bool = false
    ) -> String {
        guard let claim = ActionClaimDetector.unfulfilledClaim(
            in: modelText,
            executedToolNames: executedToolNames,
            priorActionToolExecutedInConversation: priorActionToolExecutedInConversation,
            savedNote: savedNote
        ) else { return settledText }
        honestyGuardFireCount += 1
        lastHonestyGuardClaim = claim
        Self.logger.notice("\(Self.honestyGuardLogLine(kind: claim.kind, executedCalls: executedToolNames.count, fireCount: self.honestyGuardFireCount), privacy: .public)")
        return Self.appendingCorrection(Self.correctionNotice(for: claim.kind), to: settledText)
    }

    /// **The production entry point** — the overload both turn paths call, and
    /// the ONE place the guard's LIVE inputs are read.
    ///
    /// The pure overload takes three facts. Two are read from live state
    /// here — the recorder's names and the relay's conversation latch. The
    /// third, `savedNote`, is NOT: it is passed in by the caller, because the
    /// explicit-note path is deterministic and leaves nothing on the relay to
    /// read. Its default is `false`, so a caller that does not pass it keeps
    /// the strict reading.
    ///
    /// Separated from the pure overload above so the recorder and the relay
    /// latch are read HERE rather than at two call sites that could drift
    /// apart. The pure overload stays the unit-testable core.
    func honestyGuardedReply(  // harness-visible
        modelText: String,
        settledText: String,
        recorder: TurnToolCallRecorder,
        savedNote: Bool = false
    ) -> String {
        honestyGuardedReply(
            modelText: modelText,
            settledText: settledText,
            executedToolNames: recorder.executedToolNames,
            priorActionToolExecutedInConversation:
                toolRelay?.actionToolExecutedThisConversation ?? false,
            savedNote: savedNote)
    }

    // MARK: - Conversation bookkeeping

    /// One-shot restore from the UserDefaults conversation cache (written by
    /// ChatStore) so a kill/relaunch continues with context.
    private func restoreFromCacheIfNeeded() {
        guard !didAttemptCacheRestore, currentConversation == nil else { return }
        didAttemptCacheRestore = true
        guard let cached = persistence.loadConversationCache() else { return }
        currentConversation = cached
        Self.logger.notice("restored \(cached.messages.count) cached message(s) for transcript replay (#26)")
    }

    func appendUserMessage(message: String, attachments: [PendingAttachment], clientMessageID: UUID) {  // harness-visible
        if currentConversation == nil {
            currentConversation = Conversation(title: Conversation.defaultTitle)
        }
        // Mirrors ChatStore's optimistic display content so the post-turn
        // metadata merge dedupes by id instead of duplicating the turn.
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent = trimmed.isEmpty && !attachments.isEmpty
            ? "[\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")]"
            : trimmed
        let userMessage = Message(
            id: clientMessageID,
            clientMessageID: clientMessageID,
            sender: .user,
            content: displayContent,
            status: .delivered,
            attachments: attachments.map { MessageAttachment(from: $0) }
        )
        currentConversation?.messages.append(userMessage)
        currentConversation?.lastActivity = userMessage.timestamp
    }

    func appendAssistantMessage(_ reply: Message, usage: TokenUsage?) {  // harness-visible
        currentConversation?.messages.append(reply)
        currentConversation?.lastActivity = reply.timestamp
        if let usage {
            currentConversation?.latestUsage = usage
        }
    }

    /// Real token usage from the OS: `LanguageModelSession.usage` (iOS 27).
    /// Usage is never estimated client-side (real-data-only; the CTX meter
    /// shows "—" rather than a guess), so nil here means "no session yet".
    /// #154: the iOS-26 `return nil` fallback this used to carry became
    /// unreachable when the floor moved to 27.0 — deleted, not preserved.
    private func currentTokenUsage() -> TokenUsage? {
        guard let session else { return nil }
        let usage = session.usage
        return TokenUsage(
            promptTokens: usage.input.totalTokenCount,
            completionTokens: usage.output.totalTokenCount,
            totalTokens: usage.totalTokenCount
        )
    }

    // MARK: - Pure helpers (unit-tested)

    /// A replayable conversation turn extracted from the message history.
    struct TranscriptTurn: Equatable, Sendable {
        enum Role: Equatable, Sendable {
            case user
            case assistant
        }

        let role: Role
        let text: String
    }

    /// Maps the persisted message history onto replayable turns: delivered
    /// user/Hermes messages (voice turns included — they're real conversation
    /// content), skipping system banners, failed/in-flight sends, streaming
    /// placeholders, and the message currently being sent (`excluded` — it is
    /// the live prompt, not history).
    nonisolated static func transcriptTurns(
        from messages: [Message],
        excludingClientMessageID excluded: UUID? = nil
    ) -> [TranscriptTurn] {
        messages.compactMap { message in
            guard message.status == .delivered, !message.isStreaming else { return nil }
            if let excluded, message.id == excluded || message.clientMessageID == excluded { return nil }
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch message.sender {
            case .user, .voiceUser:
                return TranscriptTurn(role: .user, text: text)
            case .hermes, .voiceHermes:
                return TranscriptTurn(role: .assistant, text: text)
            case .system:
                return nil
            }
        }
    }

    /// The incremental delta between the text already emitted and a cumulative
    /// stream snapshot. Nil when the snapshot adds nothing, or when it rewrote
    /// earlier text (no safe increment exists — the finished message carries
    /// the authoritative final text instead).
    nonisolated static func streamDelta(from emitted: String, to snapshot: String) -> String? {
        guard !snapshot.isEmpty, snapshot != emitted else { return nil }
        guard snapshot.hasPrefix(emitted) else { return nil }
        let delta = String(snapshot.dropFirst(emitted.count))
        return delta.isEmpty ? nil : delta
    }

    // MARK: Tail-repetition breaker (#102)

    /// Detection thresholds — deliberately conservative: judging legitimate
    /// repetition (lists, code, separator art, refrains) as a loop would
    /// truncate a good reply, so everything below errs toward letting the
    /// token cap (`chatGenerationOptions`) be the backstop instead.
    /// The shortest phrase treated as a loop unit. Anything shorter (repeated
    /// Latin syllables, `}` lines, `---|` table art) never qualifies — except
    /// CJK phrases, which pack a whole phrase into a few characters (see
    /// `repetitionUnitQualifies`).
    private nonisolated static let repetitionMinimumUnitLength = 8
    /// The longest phrase checked as a loop unit. 128 covers full-sentence
    /// loops, a common small-model degeneration shape.
    private nonisolated static let repetitionMaximumUnitLength = 128
    /// Consecutive exact copies of the unit required at the tail before a
    /// run is even DETECTED (arming, not yet abandoning — see
    /// `RepetitionBreaker`).
    private nonisolated static let repetitionMinimumRepeats = 6
    /// Total characters a detected run must cover (short units need
    /// proportionally more copies).
    private nonisolated static let repetitionMinimumSpan = 192
    /// Escalation floor: the breaker never abandons below this many copies,
    /// however early the run was detected.
    nonisolated static let repetitionEscalationRepeats = 12
    /// The scan is bounded to this tail window so it stays cheap on every
    /// stream snapshot. Sized so escalation stays observable for the largest
    /// unit: `repetitionEscalationRepeats × repetitionMaximumUnitLength`
    /// (1536) fits with headroom.
    private nonisolated static let repetitionScanWindow = 2048

    /// A detected degenerate run at the tail of a stream snapshot.
    /// `nonisolated`: nested types infer the class's @MainActor otherwise,
    /// and the nonisolated unit tests construct these directly.
    nonisolated struct TailRepetitionRun: Equatable, Sendable {
        let unitLength: Int
        let repeats: Int
    }

    /// Streaming breaker state (#102): cumulative snapshots judge PREFIXES of
    /// the reply, and a prefix of legitimate output can be tail-repetitive
    /// even when the completed text is not (twelve identical data rows, a
    /// requested refrain). So detection alone never abandons: the breaker
    /// ARMS on the first qualifying run, DISARMS when the tail stops
    /// qualifying (the bounded run ended — the closing bracket arrived), and
    /// abandons only when the same run keeps growing to twice its armed size
    /// (with an absolute floor) — a signature only a genuinely stuck loop
    /// produces.
    nonisolated struct RepetitionBreaker {
        private(set) var armedRepeats: Int?

        // Explicit: private(set) would otherwise restrict the synthesized
        // memberwise initializer below internal, and the tests construct one.
        init() {}

        mutating func shouldAbandon(afterObserving run: TailRepetitionRun?) -> Bool {
            guard let run else {
                armedRepeats = nil
                return false
            }
            guard let armed = armedRepeats else {
                armedRepeats = run.repeats
                return false
            }
            if run.repeats < armed {
                // A different (or re-started) run — re-arm at the lower count
                // rather than measuring the new run against the old baseline.
                armedRepeats = run.repeats
                return false
            }
            // The scan window bounds what a single observation can report
            // (`repetitionScanWindow / unitLength` copies), so the escalation
            // threshold is clamped to that ceiling — otherwise a run that
            // armed high off one coarse snapshot could never be seen to
            // double, and the breaker would silently never fire.
            let maxObservable = LocalChatBackend.repetitionScanWindow / run.unitLength
            let threshold = min(max(LocalChatBackend.repetitionEscalationRepeats, armed * 2), maxObservable)
            return run.repeats >= threshold
        }
    }

    /// The qualifying degenerate run `text` currently ends in, nil when the
    /// tail is healthy. Tail-anchored: a snapshot stream only ever grows at
    /// the end, so a loop the model is currently stuck in always reaches the
    /// tail — while a recovered loop earlier in the text never qualifies.
    /// Alignment doesn't matter: a periodic tail matches at its period even
    /// when the snapshot cuts mid-unit.
    nonisolated static func degenerateTailRepetitionRun(in text: String) -> TailRepetitionRun? {
        let window = Array(text.suffix(repetitionScanWindow))
        let count = window.count
        guard count >= repetitionMinimumSpan else { return nil }
        var unitLength = repetitionMinimumUnitLength
        while unitLength <= repetitionMaximumUnitLength, unitLength * 2 <= count {
            // Count consecutive copies of the last `unitLength` characters,
            // walking backward from the anchor at the very end.
            var repeats = 1
            var blockStart = count - unitLength * 2
            scan: while blockStart >= 0 {
                for offset in 0 ..< unitLength {
                    if window[blockStart + offset] != window[count - unitLength + offset] { break scan }
                }
                repeats += 1
                blockStart -= unitLength
            }
            if repeats >= repetitionMinimumRepeats,
               repeats * unitLength >= repetitionMinimumSpan,
               repetitionUnitQualifies(window, unitStart: count - unitLength, unitLength: unitLength) {
                return TailRepetitionRun(unitLength: unitLength, repeats: repeats)
            }
            unitLength += 1
        }
        return nil
    }

    /// Convenience over `degenerateTailRepetitionRun` for the unit tests and
    /// any caller that only needs the verdict.
    nonisolated static func hasDegenerateTailRepetition(_ text: String) -> Bool {
        degenerateTailRepetitionRun(in: text) != nil
    }

    /// `text` with a detected degenerate tail run collapsed to a single copy
    /// of the looped unit. The full run is noise by definition, and a reply
    /// stored verbatim would replay it into every rebuilt session's
    /// transcript — re-priming the very loop the breaker just cut. Text with
    /// a healthy tail passes through unchanged.
    nonisolated static func collapsingDegenerateTail(_ text: String) -> String {
        guard let run = degenerateTailRepetitionRun(in: text) else { return text }
        // The scan window bounds what the detector can SEE; the actual run
        // may extend further back. Walk the full text (only on a trip, cost
        // proportional to the run) so every copy is removed, not just the
        // in-window ones.
        let chars = Array(text)
        let count = chars.count
        let unitStart = count - run.unitLength
        var totalRepeats = 1
        var blockStart = count - run.unitLength * 2
        scan: while blockStart >= 0 {
            for offset in 0 ..< run.unitLength {
                if chars[blockStart + offset] != chars[unitStart + offset] { break scan }
            }
            totalRepeats += 1
            blockStart -= run.unitLength
        }
        return String(text.dropLast((totalRepeats - 1) * run.unitLength))
    }

    /// A unit only counts as a loop when it carries words (pure punctuation
    /// runs are separator art) and is not itself a shorter loop — "la la la "
    /// is judged at its fundamental 3-character period (below the minimum,
    /// so Latin syllable refrains never qualify), not at a 9-character
    /// multiple. Exception: a CJK phrase packs a whole phrase into a few
    /// characters, so a CJK-bearing fundamental period of 4+ still counts.
    private nonisolated static func repetitionUnitQualifies(_ window: [Character], unitStart: Int, unitLength: Int) -> Bool {
        var hasWordCharacter = false
        for index in unitStart ..< (unitStart + unitLength) where window[index].isLetter || window[index].isNumber {
            hasWordCharacter = true
            break
        }
        guard hasWordCharacter else { return false }
        // Only divisor periods can reproduce the same tail, so only they are
        // checked; ascending order finds the fundamental period first.
        for period in 1 ..< unitLength where unitLength % period == 0 {
            var matchesPeriod = true
            for index in (unitStart + period) ..< (unitStart + unitLength) {
                if window[index] != window[index - period] {
                    matchesPeriod = false
                    break
                }
            }
            if matchesPeriod {
                return period >= 4 && containsCJKCharacter(window, start: unitStart, length: period)
            }
        }
        return true
    }

    /// Whether the range contains a CJK scalar (Han, Hiragana, Katakana,
    /// Hangul) — the scripts whose phrases are short enough to loop below
    /// the Latin minimum unit length.
    private nonisolated static func containsCJKCharacter(_ window: [Character], start: Int, length: Int) -> Bool {
        for index in start ..< (start + length) {
            for scalar in window[index].unicodeScalars {
                switch scalar.value {
                case 0x4E00...0x9FFF, 0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
                    return true
                default:
                    continue
                }
            }
        }
        return false
    }

    /// The TEXT side of one turn: the user's message plus text attachments
    /// inlined through the shared delimiter surface (`AttachmentInlining`,
    /// #8/#43). #390: an image reaching THIS function is a blind one by
    /// construction — `composeTurnInput` already lifted every decodable
    /// image the arm allows into real model input — so the placeholder is
    /// honest again: it describes only turns where the model truly cannot
    /// see the picture, on either tier.
    nonisolated static func composePrompt(message: String, attachments: [PendingAttachment]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else { return trimmed }
        var sections: [String] = []
        if !trimmed.isEmpty { sections.append(trimmed) }
        for attachment in attachments {
            switch attachment.kind {
            case .file where PendingAttachment.isInlinableTextMime(attachment.mimeType):
                sections.append(AttachmentInlining.delimitedTextPart(
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType,
                    content: String(decoding: attachment.data, as: UTF8.self)
                ))
            case .image:
                sections.append("[Attached image \"\(attachment.fileName)\" — this model can't view the picture, only text read from it. If the picture itself matters to the request, say honestly that you can't see it.]")
            case .file:
                sections.append("[Attachment \"\(attachment.fileName)\" (\(attachment.mimeType)) has no on-device representation and was not delivered.]")
            }
        }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - #390: true image input (current turn only)

    /// One current-turn image bound for the model as REAL input.
    struct TurnImage {
        let label: String
        let cgImage: CGImage
    }

    /// A composed turn: the text prompt (message + inlined/degraded
    /// attachments) plus the images that ride as model input. Images appear
    /// on EXACTLY ONE side — as a `TurnImage` when the arm is enabled and
    /// the bytes decode, else as the honest placeholder inside `promptText`
    /// (390-B's fallback, which is also the ONLY route for history images).
    ///
    /// - `savedNote`: **#422 Task 11, fix round 1.** The verbatim text of
    ///   the note THIS TURN actually wrote, or `nil` when it wrote none —
    ///   an explicit PARAMETER now, not derived inside `composeTurnInput`
    ///   (a `nonisolated static` function has no MainActor access to the
    ///   store). The caller (`send`/`streamTurn`) computes it via
    ///   `savedNoteThisTurn(clientMessageID:)`, which reads the STORE —
    ///   re-deriving it from the message text alone was the bug: text that
    ///   merely LOOKS like a save attempt is not the same fact as a note
    ///   that was actually written (the toggle off, a nil store, and the
    ///   voice pipeline's direct `sendStreaming` call all produce matching
    ///   text with nothing saved). Deliberately the raw note text, not the
    ///   composed prompt prefix — `MemoryBudget.justSavedPrefix(_:)` is
    ///   Task 10's call to make, at its one door (`makeTurnPrompt`); this
    ///   only carries the fact.
    struct ComposedTurnInput {
        let promptText: String
        let images: [TurnImage]
        let savedNote: String?
    }

    /// #390-F DISCHARGED 2026-08-25: ON since the flip PR that also
    /// published the privacy policy's image sentence (Owen's approved
    /// wording + explicit publish go, both same day). ⛔ Turning this OFF
    /// again is a product decision with a policy implication — it needs
    /// its own ruling and the pin in `ImageInputCompositionTests` re-cut
    /// with it, never a drive-by.
    nonisolated static let pccImageInputEnabled = true

    /// Whether images ride as REAL model input for the given tier: the
    /// runtime capability read (#388's probe surface) AND, for PCC, the
    /// 390-F arm gate. One function so the compose path and the input
    /// bar's caption can never disagree about what this turn does.
    nonisolated static func imageInputCapability(forPrivateCloud: Bool) -> Bool {
        if forPrivateCloud {
            guard pccImageInputEnabled else { return false }
            return PrivateCloudComputeLanguageModel().capabilities.contains(.vision)
        }
        return SystemLanguageModel.default.capabilities.contains(.vision)
    }

    func turnImageInputEnabled() -> Bool {
        Self.imageInputCapability(forPrivateCloud: activeTier == .privateCloud)
    }

    nonisolated static func decodeAttachedImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Partitions the turn: each `.image` attachment rides as a `TurnImage`
    /// when the arm is enabled AND its bytes decode; everything else —
    /// files, undecodable images, the disabled-arm case — flows through
    /// `composePrompt`'s text handling, where images get the honest
    /// placeholder (390-B). CURRENT-TURN attachments only, by signature:
    /// nothing here reads history, which is what keeps 390-A's rule true
    /// at the source rather than by filtering.
    ///
    /// `savedNote` (fix round 1): the caller's ALREADY-DERIVED answer to
    /// "did this turn write a memory" — see `savedNoteThisTurn`. No default:
    /// every call site must say explicitly, so a new one cannot silently
    /// regress to "nil means nothing was saved" being the accidental
    /// default rather than a checked answer.
    nonisolated static func composeTurnInput(
        message: String,
        attachments: [PendingAttachment],
        imageInputEnabled: Bool,
        savedNote: String?
    ) -> ComposedTurnInput {
        var images: [TurnImage] = []
        var textBound: [PendingAttachment] = []
        for attachment in attachments {
            if attachment.kind == .image, imageInputEnabled,
               let decoded = decodeAttachedImage(attachment.data) {
                images.append(TurnImage(label: attachment.fileName, cgImage: decoded))
            } else {
                textBound.append(attachment)
            }
        }
        return ComposedTurnInput(
            promptText: composePrompt(message: message, attachments: textBound),
            images: images,
            savedNote: savedNote
        )
    }

    /// The ONE door from a decoded image to the model (pinned by
    /// `ImageInputCompositionTests` — a second construction site is a
    /// second door the seam tests cannot see). Text-only turns assemble
    /// byte-identically to the pre-#390 `Prompt(prompt)` path.
    nonisolated static func makeTurnPrompt(_ input: ComposedTurnInput) -> Prompt {
        guard !input.images.isEmpty else { return Prompt(input.promptText) }
        return Prompt {
            input.promptText
            input.images.map { Attachment($0.cgImage).label($0.label).promptRepresentation }
        }
    }

    /// Index where the verbatim tail starts: the newest turns that fit half
    /// the available budget (the rest is room for condensed memory + the turn
    /// in flight). 0 = everything fits verbatim. The newest turn is always
    /// kept, even when it alone exceeds the share.
    nonisolated static func verbatimSplitIndex(turnTokenCounts: [Int], availableBudget: Int) -> Int {
        guard !turnTokenCounts.isEmpty else { return 0 }
        let total = turnTokenCounts.reduce(0, +)
        if total <= availableBudget { return 0 }
        let verbatimBudget = max(availableBudget / 2, 256)
        var accumulated = 0
        var index = turnTokenCounts.count
        while index > 0 {
            let next = accumulated + turnTokenCounts[index - 1]
            if next > verbatimBudget, index != turnTokenCounts.count { break }
            accumulated = next
            index -= 1
        }
        return index
    }

    static let condensedMemoryPreamble = """
    ## Earlier conversation (condensed)
    Older turns were condensed to fit the on-device context window. Treat them \
    as prior conversation memory:
    """

    /// The armed branch opens by licensing tool-free answering and creation
    /// (#176B/#194): with no such clause the on-device model treats the belt
    /// as its job description — every turn routes to a tool, "write a poem"
    /// deflects to reminders/weather, and one permission denial becomes every
    /// later turn's answer. Keep the "use tools" instruction scoped to the
    /// user's own data, never to general knowledge, and keep the recovery
    /// sentence: a failed tool is information about the tool, not the reply.
    ///
    /// 176C Part 2 (#194): the prose belt roster — the sentence enumerating
    /// the tools — was the convicted creative suppressor and is gone from the
    /// armed branch. The tools' native `Tool.description` metadata, already
    /// registered on the session, is the ONLY enumeration; the instructions
    /// therefore can never claim a tool the session wasn't given. The
    /// #176/#148 vision gate lives structurally in
    /// `DeviceToolBelt.offeredTools`; `hasImageTools` is kept for call-site
    /// stability but no longer varies this text.
    ///
    /// #196 measurement seams, the `includeBeltRoster` precedent: production
    /// call sites never pass either flag, so both production branches are
    /// byte-identical with the defaults. `includeCompositionLicensingSentence`
    /// inserts ONLY the composition-licensing sentence into the armed
    /// licensing clause (the `armed-complic` / `armed-fix` cells — the first
    /// battery's knowledge-denial finding: composing about world knowledge
    /// was refused as retrieval). `includeToollessLicensingClause` swaps ONLY
    /// the bare branch for its licensed form (the `toolless-lic` cell — the
    /// bare branch never received #176B's clause and measured 0/10 on
    /// composition with the purest denials). The first battery's
    /// `includeDirectnessSentence` (measured loser) and
    /// `includeHonestyAndRecoveryClauses` thermometer (measured NOT the
    /// source: 10/10 reminder grabs with the clauses gone) are retired.
    // MARK: - Promoted instruction clauses (#202C, #202D, #204)
    //
    // **These ship. They are read by `instructionsText` below on every
    // production turn** — the battery only re-reads them so a rollback cell can
    // be pinned as "production MINUS exactly this string".
    //
    // They lived in the `#if DEBUG` harness region from #202C (2026-07-30) until
    // 2026-08-01, because that is where the lane that measured them was working
    // when they were promoted. **That combination — a production reference to a
    // DEBUG-only declaration — does not compile in Release, so `main` could not
    // be archived for two days and nobody saw it:** the suite builds Debug,
    // corded device installs build Debug, and the external audit's independent
    // verification was `build-for-testing`, also Debug. `ota-stage.sh` defaults
    // to Release and would have failed at archive on the next OTA.
    //
    // **The rule this earns: a promoted string is production code and moves out
    // of the harness in the same commit that promotes it.** And a lane that
    // changes what compiles under which configuration is verified with a
    // Release build, because a green Debug suite cannot see it.

    /// #204: the promoted dead-end carve-out, hoisted so the rollback cell can
    /// be pinned as "production MINUS exactly this string". Promoted at
    /// #200M/#200O; re-verified there only against a CROSS-RUN baseline.
    nonisolated static let deadEndCarveoutClause = " If you can't identify a person named in an event, that's fine — create the event with the name exactly as the user gave it."

    /// #202C: targets the CLAIM (not the output format, which the payload
    /// already mandated and #202B violated anyway) and is SCOPED to action
    /// requests so it cannot resurrect #196's tic.
    nonisolated static let toollessHonestyClause = " If the user asks you to create, set, add, schedule, or change something on their device — including agreeing to an offer you made earlier — you cannot do it on this turn: say so in one plain sentence and stop. Never say or imply that you have created, set, added, or scheduled anything, and never write out a tool call."

    /// #202D: v1 kept. Its claim ban and tool-syntax ban took the disease
    /// from 9/10 to 0/10 and are carried over verbatim in spirit. What v2
    /// adds is the fix for v1's OWN defect: "on this turn" was rendered as
    /// "on this device" 7/10 times, so v2 names the accurate phrasing that
    /// 3/10 of v1's refusals found unaided ("right now"), bans the
    /// capability reading outright, and points at the path that actually
    /// works — a direct request routes ARMED and creates (production 20/20).
    nonisolated static let toollessHonestyClauseV2 = " If the user asks you to create, set, add, schedule, or change something on their device — including agreeing to an offer you made earlier — you cannot do it on this turn. Say in one plain sentence that you can't do it right now, and invite them to ask you for it directly. Never suggest that you or this app lack the ability to do it at all — the limit is this turn, not the app. Never say or imply that you have created, set, added, or scheduled anything, and never write out a tool call."

    /// #284: the armed blurb's generated enumeration. Vision is appended
    /// here (never via the families list) so the persona mentions image
    /// reading exactly when the session was actually given those tools.
    nonisolated static func armedEnumeration(
        families: [CapabilityGroup], hasImageTools: Bool
    ) -> String {
        var all = families.filter { $0 != .vision }
        if hasImageTools { all.append(.vision) }
        return CapabilityRegistry.armedCapabilityEnumeration(families: all)
    }

    /// #297: the toolless capability index — one registry-generated
    /// sentence offering the #257 conversational fix on the toolless-lic2
    /// branch, so a fresh "What can you do?" turn can name what it CAN
    /// offer instead of only stonewalling. Fixed to the full non-vision
    /// catalog via `armedEnumeration`, never a hand-written list (#257's
    /// root cause) and never the caller's narrowed `armedCapabilityFamilies`
    /// — a toolless turn registers no belt at all (#196's structural cure),
    /// so there is no "armed subset" for this branch, only the full offer.
    /// Vision is excluded outright (`hasImageTools: false`, not merely
    /// unlisted): it is image-gated (#176) and irrelevant here regardless,
    /// since a toolless turn was never given image tools either.
    ///
    /// **Frame is an em-dash appositive, not a fused possessive** — the
    /// first cut fused the generated list straight onto "the user's" and
    /// broke on the two `displayPhrase`s that already carry "their" (health,
    /// location): "the user's their health and activity". `displayPhrase`
    /// was designed for the ARMED sentence's own appositive shape ("Use the
    /// tools for the user's own data — their health and activity, their
    /// location, … — instead of guessing at it"), so this mirrors that
    /// shape instead of re-deriving new phrasing — the phrases are correct,
    /// the frame around them was not.
    nonisolated static let toollessCapabilityIndexSentence =
        " You can also read the user's own device data when asked — \(LocalChatBackend.armedEnumeration(families: CapabilityGroup.allCases, hasImageTools: false)) — so offer to, rather than saying you can't."

    nonisolated static func instructionsText(
        deviceContext: String,
        date: Date = .now,
        // #385: WHERE the compute happens. Defaulted to `.onDevice` because
        // every harness and battery measures that tier — but production
        // passes `activeTier`, so a PCC session is never handed the
        // on-device identity. This axis was the ONE thing this function was
        // not parameterised on (tools, images and three toolless clauses all
        // were), and a device pass caught the model telling a user its
        // conversation never leaves the phone while it ran on Apple's
        // servers. Bar 385-A.
        tier: LocalModelTier = .onDevice,
        hasTools: Bool = false,
        hasImageTools: Bool = false,
        // #284: the armed blurb's capability list, generated from the
        // registry so it can never go stale again (#257's root cause was a
        // hand-written copy). Default = the full non-vision catalog; stage 3
        // passes the turn's armed subset. Vision joins via hasImageTools —
        // the #176 image gate, not the caller's list.
        armedCapabilityFamilies: [CapabilityGroup] = CapabilityGroup.allCases.filter { $0 != .vision },
        includeCompositionLicensingSentence: Bool = false,
        includeToollessLicensingClause: Bool = false,
        includeToollessLic2Clause: Bool = false,
        includeActionDestallClause: Bool = true,
        includeFindFirstCarveout: Bool = true,
        includeLookupSpiralCarveout: Bool = false,
        includeCardNarrationClause: Bool = true,
        includeDayDefaultClause: Bool = false,
        includeDeadEndCarveout: Bool = true,
        includeCompositionAnswerClause: Bool = false,
        includeCardCorrectionClause: Bool = false,
        includeToollessHonestyClause: Bool = false,
        includeToollessHonestyClauseV2: Bool = false,
        // #297: the toolless capability index (spec §4's contingency,
        // #284 plan Task 12). Default OFF — production ships this false
        // until Owen's device A/B (bars 297-A/B/C) clears it. Applies only
        // on the `includeToollessLic2Clause` branch, appended AFTER
        // `includeToollessHonestyClauseV2` — order matters, the honesty
        // clause must never be displaced.
        includeToollessCapabilityIndex: Bool = false
    ) -> String {
        let day = date.formatted(date: .complete, time: .omitted)
        // #196 second battery: the composition-licensing sentence — the
        // `armed-complic` / `armed-fix` instruction treatment. "summarize
        // Norway" was refused as "can't access external knowledge" across
        // every tool cell: the model equates composing about world knowledge
        // with retrieval. This sentence licenses composition specifically.
        let composition = "You know a great deal about the world — places, people, history, ideas — and writing about it needs no internet, database, or lookup: composing from your own knowledge is not retrieval. "
        // #202C: the toolless branch's honesty clause. #202B measured this
        // branch asserting a completed create on 10/12 accept turns and
        // typing raw tool syntax on 2/12 — while the payload ALREADY said
        // "no external tools in this mode" and "never JSON, XML, code
        // blocks, or tool syntax". Restating either was therefore pointless:
        // this clause targets the CLAIM itself, and is SCOPED to action
        // requests so it cannot resurrect #196's disclaimer tic on the
        // words-only turns the payload was promoted to protect.
        let toollessHonesty = Self.toollessHonestyClause
        // #176's absorbing-state exits — the honesty sentence and the
        // recovery clause. Real jobs in production. (The armed-noneg
        // thermometer that lifted them is retired: measured NOT the tic's
        // source — 10/10 reminder grabs with them gone.)
        let honestyAndRecovery = " When a tool reports that a permission isn't granted or no data exists, relay that honestly — never invent a value. A failed or denied tool is never the answer to the user's question: answer as well as you can without that tool, and don't repeat a denial you've already given in this conversation."
        // #200D (PROMOTED 2026-07-28, #200C verdict on run FFC92E35): the
        // de-stall clause, default-on. #200B falsified the tool-text seam
        // (the "which list?" stall fires at response planning, before any
        // tool schema is engaged); from HERE the same words measured
        // calendar 0/9 → 8/10, alarm 8/10 → 10/10, remind off zero, and
        // grabs DOWN 9/10 → 3/9 (the asks-for antecedent sharpens
        // licensing in both directions). Explicit `false` is the pinned
        // rollback seam — the pre-promotion text, byte-identical.
        let actionDestall = " When the user asks for a reminder, alarm, or calendar event and says what and when, create it right away — never ask which list, which calendar, or for other optional details first; leave optional fields empty and the defaults apply."
        // #200G (PROMOTED 2026-07-29, #200F verdict on the corded a656004
        // run): the find-first carve-out, default-on. Apple's own CATALOG
        // planner documents find-first-on-ambiguity (#200E proved it
        // model-baked: the forced first call was readReminders 10/10) and
        // an explicit reminders-vs-calendar preference rule — these two
        // sentences carve the "remind me" intent out of both, and from
        // HERE they measured remind 9/10 vs 1/10 control (lifetime control
        // 1/60) with ZERO readReminders calls. Explicit `false` is the
        // pinned rollback seam — the pre-promotion text, byte-identical.
        let findFirstCarveout = " 'Remind me' means create the reminder — do not search existing reminders first. Reminders and calendar events are different tools — prefer a reminder when the user asks to be reminded."
        // #200H spiralfix cell: the lookup-spiral carve-out, one sentence
        // per disease. The identity hunt (searchConversations/lookupContact/
        // searchPlaces loops on "Sam" — every excluded trial across
        // #200F/#200G, incl. an 8,192-token context overflow) and the
        // location misbind (searchPlaces("Sam") → Sam's Club / Pluckers
        // Wing Bar 500 miles away bound as the lunch location). Measured
        // cell only; never defaults on without a battery verdict.
        //
        // #200I reword, EVENT-SCOPED. v1 said "an event or reminder" and
        // won the calendar (9/10, best ever, zero casualties) while
        // bleeding onto intents it never named a treatment for: grabs
        // doubled, remind sagged to 4/10. Naming reminders made it read as
        // guidance about reminders. v2 names only the event path it was
        // measured on, and "before creating the event" states the create
        // as the destination instead of only forbidding the search — the
        // shape that made the #200D and #200G clauses work.
        let lookupSpiralCarveout = " A person's name in an event title is just part of the title — never search contacts, conversations, or places to identify them before creating the event. Only include an event location the user themselves gave; a place search result is never the location."
        // #200J cardfix cell, PROMOTED #200K (default true). #200I's
        // largest failure bucket was 10 zero-tool trials — 9 of the remind
        // misses, in BOTH cells — where the model typed the card out
        // ("**Title:** Test Talaria / **Due:** … / Would you like to
        // proceed?") and called nothing, waiting on an answer a
        // single-turn battery can never give. Production already says a
        // card is shown; that evidently reads as description, not as
        // "so don't do it yourself". This names the impersonation and
        // points at the call — and #200J measured it dead: 3 narrations in
        // control, ZERO in 40 treatment trials, remind 5/10 → 8/10.
        // Explicit `false` is the pinned rollback, byte-identical to the
        // pre-promotion text.
        let cardNarrationClause = " The confirmation card is shown automatically when you call an action tool — never write the card out, list the details back for approval, or ask whether to proceed; make the call and let the card do the asking."
        // #200K datefix cell: the residual remind disease. #200J's two
        // remaining treatment misses were both zero-tool date
        // interrogations ("Could you clarify the due date?", "a specific
        // date or keep it open for today?"). The #200D clause licenses
        // empty OPTIONAL fields; a bare clock time reads as an AMBIGUOUS
        // REQUIRED one, so permission doesn't reach it — this names the
        // resolution instead. Measured cell only.
        let dayDefaultClause = " A time with no day means the next time that clock time comes around — never ask which day."
        // #200M deadendfix cell, PROMOTED #200O (default true) on two
        // independent runs: calendar 17/20 (85%) vs 10/19 (53%) for
        // production, +32 points, same direction and size both times,
        // Sam dead-ends 5→~0 and 4→1, remind level pooled (18/20 vs
        // 19/20). Explicit `false` is the pinned rollback.
        //
        // The v2 carve-out reduced to the only part
        // #200L showed it earns. In that run the treated cell's hunt calls
        // fell just 23 → 16 and one trial still ran away to 20 calls (17
        // consecutive searchConversations) — but the DEAD END went to
        // zero: 5 "couldn't find Sam, so I'm asking" misses in production,
        // none treated. v2 converts hunt→ask into hunt→create; it never
        // stopped the hunt. So v3 says that and nothing else.
        //
        // Dropped on purpose, and pinned as absent: v2's search
        // prohibition (the part that plausibly moved the reminder path —
        // pooled over #200I+#200L it cost remind −20 points) and v2's
        // location sentence (unearned: every accepted event across
        // #200J/#200K/#200L was a bare title with no location bound).
        let deadEndCarveout = Self.deadEndCarveoutClause
        // #200O grabfix cell: the grab disease. Grabs are the only number
        // in this program that moved the WRONG way while everything else
        // improved (4/8 → 4/10 → 7/10 → 15/20 → 9/10 → 9/10), and that is
        // not a coincidence — six lanes have spent their words raising
        // create-pressure, and the haiku prompt is swept up in it. The
        // specimen is the META-GRAB: a reminder titled with the request
        // itself ("Write a haiku about sledding"), and in #200N one trial
        // produced BOTH a reminder and a calendar event for a poem.
        //
        // The armed paragraph already says composing "needs no tool" —
        // but that is permission, and #200J proved permission is not
        // enough (the model knew the confirmation card existed and
        // impersonated it anyway). This names the artifact instead.
        let compositionAnswerClause = " When the user asks you to write something, the writing itself is the answer — never also create a reminder, event, or alarm about writing it."
        // #200P stallfix cell: the conserved stall — zero-tool
        // interrogation, 12 of 30 remind trials in #200O. It survives
        // field-by-field treatment: #200K's datefix closed the date
        // question and the model asked about the list instead, same
        // count, different field. And it cannot be fixed by restating the
        // promoted #200D clause, which already forbids asking and is
        // ignored ~40% of the time in a bad run.
        //
        // What worked in #200J was naming the CARD as the thing the model
        // was standing in for. This names the card as where a missing
        // detail gets fixed, so the question has somewhere to go instead
        // of being asked. Measured cell only.
        let cardCorrectionClause = " A missing detail is never a reason to ask first — create it with the default and let the confirmation card be where the user changes it."
        let capabilities: String
        if hasTools {
            capabilities = "Be direct, warm, and concise. Answering from what you know, writing and composing, summarizing, and ordinary conversation are your job and need no tool — facts you know are not guesses, and general knowledge is not device data. "
                + (includeCompositionLicensingSentence ? composition : "")
                // #337-F-2b PROMOTED 2026-08-15 on Owen's ruling. The sentence
                // is no longer written out here: it was a byte-for-byte DUPLICATE
                // of `DeviceActionClauses.armedBlurbCardSentence`, and every
                // measurement arm manipulates that constant by string match — so
                // a promotion that edited only this line would have left the arms
                // silently targeting a sentence production no longer shipped.
                // One home now; the arms and production cannot drift.
                + "Use the tools for the user's own data — \(Self.armedEnumeration(families: armedCapabilityFamilies, hasImageTools: hasImageTools)) — instead of guessing at it."
                + DeviceActionClauses.armedBlurbShippingSentence
                + (includeActionDestallClause ? actionDestall : "")
                + (includeFindFirstCarveout ? findFirstCarveout : "")
                + (includeLookupSpiralCarveout ? lookupSpiralCarveout : "")
                + (includeCardNarrationClause ? cardNarrationClause : "")
                + (includeDayDefaultClause ? dayDefaultClause : "")
                + (includeDeadEndCarveout ? deadEndCarveout : "")
                + (includeCompositionAnswerClause ? compositionAnswerClause : "")
                + (includeCardCorrectionClause ? cardCorrectionClause : "")
                + honestyAndRecovery
        } else if includeToollessLic2Clause {
            // #196 battery 4, toolless-lic2: the licensed bare branch plus
            // the two device-observed canary fixes — a math/facts license
            // (third battery: the licensing sentence covers writing, not
            // calculation; the bare branch denied arithmetic 20/20) and an
            // explicit output-format mandate in Apple's own template
            // convention (kills the degenerate `response_format` JSON
            // wrapper the licensed branch produced on 4/20 canary trials).
            capabilities = "Be direct, warm, and concise. Answering from what you know, writing and composing, summarizing, and ordinary conversation are your job — facts you know are not guesses, and writing about the world from your own knowledge needs no internet or lookup. Simple math and everyday factual questions you answer directly yourself. Reply in plain conversational prose — never JSON, XML, code blocks, or tool syntax unless the user asks for them. You have no internet access and no external tools in this mode; when you genuinely don't know something, say so plainly instead of guessing."
                + (includeToollessHonestyClause ? toollessHonesty : "")
                + (includeToollessHonestyClauseV2 ? Self.toollessHonestyClauseV2 : "")
                + (includeToollessCapabilityIndex ? Self.toollessCapabilityIndexSentence : "")
        } else if includeToollessLicensingClause {
            // #196 toolless-lic cell: the bare branch, licensed. Composition
            // licensed up front; the no-internet honesty caveat KEPT — the
            // branch must still forbid guessing at what the model truly
            // doesn't know (current events, the user's data).
            capabilities = "Be direct, warm, and concise. Answering from what you know, writing and composing, summarizing, and ordinary conversation are your job — facts you know are not guesses, and writing about the world from your own knowledge needs no internet or lookup. You have no internet access and no external tools in this mode; when you genuinely don't know something, say so plainly instead of guessing."
        } else {
            capabilities = """
            Be direct, warm, and concise. You have no internet access and no external tools in this mode — when you don't know something or can't do it on-device, say so plainly instead of guessing.
            """
        }
        return """
        \(Self.identitySentence(for: tier))
        Today is \(day).
        \(deviceContext)
        \(capabilities)
        """
    }

    /// #385 — the identity line, per tier. **Kept adjacent on purpose:** bar
    /// 385-C requires these two to be DIFFERENT strings, and the shortcut a
    /// later "simplify the duplication" lane reaches for is one tier-neutral
    /// sentence that satisfies both bars' prose while failing the ruling.
    /// Seeing them together is what makes that shortcut look wrong.
    nonisolated static func identitySentence(for tier: LocalModelTier) -> String {
        switch tier {
        case .onDevice:
            // TRUE on this tier, and deliberately unchanged (bar 385-B).
            // Owen explicitly rejected stripping the location clause from
            // both tiers: the fix is to stop GENERALISING a true sentence,
            // not to go quiet about it.
            return "You are Talaria, the user's personal assistant, running entirely on their iPhone with Apple's on-device foundation model. The conversation is private and never leaves the device."
        case .privateCloud:
            // Ruled 2026-08-20. Names the tier; does NOT vouch for it.
            //
            // The rejected alternative stated Apple's guarantees outright
            // ("not stored, not accessible to Apple") — more useful, and a
            // SECOND-ORDER version of the defect being fixed: the app
            // asserting, in the assistant's voice, a privacy property it
            // cannot itself verify. Naming the tier is ours to assert.
            // Vouching for it is not.
            return "You are Talaria, the user's personal assistant, running on Apple's Private Cloud Compute rather than on the device itself. If the user asks where their data goes, say plainly that this tier sends the request to Apple's servers for processing, and point them to Apple's Private Cloud Compute documentation rather than characterising the guarantees yourself."
        }
    }

    static func deviceContextLine() -> String {  // harness-visible
        let device = UIDevice.current
        return "Device: \(device.model) running iOS \(device.systemVersion)."
    }

    /// The `/model`-style response `switchModel` returns; ChatStore parses the
    /// "Context: N tokens" line for the CTX denominator (#4).
    nonisolated static func modelSwitchResponseText(modelID: String, contextSize: Int) -> String {
        "Model switched to `\(modelID)` — Apple on-device foundation model.\nContext: \(contextSize) tokens"
    }

    nonisolated static func sessionInfo(for conversation: Conversation) -> HermesSessionInfo {
        HermesSessionInfo(
            id: conversation.id.uuidString,
            title: Conversation.isPlaceholderTitle(conversation.title) ? nil : conversation.title,
            preview: conversation.generatedPreview ?? conversation.lastMessage?.content,
            model: onDeviceModelID,
            source: localSessionSource,
            messageCount: conversation.messages.count,
            lastActive: conversation.lastActivity,
            isActive: true
        )
    }

    /// Row form (#190): a stored session listed without decoding its
    /// transcript — the store's denormalized columns carry everything here.
    nonisolated static func sessionInfo(for summary: LocalSessionSummary, isActive: Bool) -> HermesSessionInfo {
        HermesSessionInfo(
            id: summary.id.uuidString,
            title: summary.title == Conversation.defaultTitle ? nil : summary.title,
            preview: summary.preview,
            model: onDeviceModelID,
            source: localSessionSource,
            messageCount: summary.messageCount,
            lastActive: summary.lastActivity,
            isActive: isActive
        )
    }

    // MARK: - Honest failure states

    nonisolated static func unavailabilityMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "On-device intelligence isn't available: this device doesn't support Apple Intelligence. Connect a Hermes desktop in Settings to chat."
        case .appleIntelligenceNotEnabled:
            return "On-device intelligence is turned off. Enable Apple Intelligence in Settings → Apple Intelligence & Siri, then try again."
        case .modelNotReady:
            return "The on-device model is still getting ready (downloading or optimizing). Try again in a few minutes."
        @unknown default:
            return "On-device intelligence is unavailable right now for a reason this version of Talaria doesn't recognize."
        }
    }

    /// #210: does this error mean "the prompt did not fit"?
    ///
    /// The typed case is the documented shape and stays the fast path. But it
    /// is NOT the shape the device actually produces: both real overflows in
    /// the run records arrived as an NSError-style chain with **no enum case
    /// name** —
    ///
    /// ```
    /// Provided 8,583 tokens, but the maximum allowed is 8,192.::…
    /// (TokenGenerationInference.DecoderModelError error 3.)::inferenceFailed::…
    /// ```
    ///
    /// — and `GenerationError` declares no `CustomStringConvertible` in the
    /// beta-4 swiftinterface, so `String(describing:)` on one WOULD print its
    /// case. The cast therefore failed, **#26's condense-and-retry never fired,
    /// and the turn died instead of degrading to summarized memory.**
    ///
    /// The content check requires BOTH halves of the sentence — a token count
    /// AND the ceiling — so an unrelated error mentioning "maximum allowed"
    /// cannot trip it. Being wrong costs one forced-condensation retry, which
    /// `didCondenseRetry` already caps at one; being wrong the other way costs
    /// the whole turn, which is what has been happening.
    ///
    /// Mutation-verified: restoring the pre-#210 body fails exactly
    /// `recognizesTheOverflowShapeTheDeviceActuallySends` and
    /// `recognizesTheSecondRecordedOverflow`, and nothing else.
    nonisolated static func isContextOverflow(_ error: Error) -> Bool {
        // #198: the TYPED successor first. `LanguageModelError` (iOS 27)
        // replaces the deprecated `GenerationError`, and #209's pooled data
        // says it is what the device actually throws — which is very likely
        // WHY #210's original cast failed and the guard never fired. Its
        // payload even carries `contextSize`/`tokenCount` as integers, so this
        // arm needs no string parsing at all.
        if let modelError = error as? LanguageModelError,
           case .contextSizeExceeded = modelError { return true }
        if legacyIsContextOverflow(error) { return true }
        // #210's content check stays as the backstop. It is what caught the two
        // real overflows in the record, and until a device run confirms which
        // TYPE those arrived as, removing it would be trading a measured
        // behaviour for an inferred one.
        let described = String(describing: error)
        return described.contains("maximum allowed is")
            && described.range(of: #"[Pp]rovided [\d,]+ tokens"#,
                               options: .regularExpression) != nil
    }

    /// Plain-language reasons for `.failed(String)` — never a bare error dump
    /// for the cases the on-device model actually produces.
    nonisolated static func failureMessage(for error: Error) -> String {
        // #197 FIX: a tool throw must never render internals. `ToolCallError`
        // carries the LIVE tool instance, and its description reflects that
        // struct's stored properties — which is how the transcript ended up
        // showing the tool's full description string, `RELAY:
        // TALARIA.TOOLEVENTRELAY`, and a live pointer
        // (`<TALARIA.DEVICELOCATIONPROVIDER: 0x108BD0B00>`) on 2026-07-27.
        // Only `tool.name` is safe to surface.
        //
        // The #176 recovery clause cannot help here: this class throws ABOVE
        // `call()` (the argument-DECODE layer), so it kills the turn upstream
        // of the model and no tool can catch it. **The message therefore has
        // to do the recovering** — name what failed, and name what works.
        // Same shape as #201B's continuation and #202D's clause v2, both of
        // which measured well.
        if let toolError = error as? LanguageModelSession.ToolCallError {
            return "Talaria couldn't read the arguments for \(toolError.tool.name) on that turn. Ask again and it should go through."
        }
        // #198: `LanguageModelError` (iOS 27) is the SUCCESSOR to the now-
        // deprecated `GenerationError`, and #209's pooled data says it is what
        // the device actually throws — bucket E, `Error Domain=FoundationModels
        // .LanguageModelError`, was 80.6% of all recorded errors. It is matched
        // FIRST; the deprecated type is kept below because it is still declared
        // in the beta-4 SDK and nothing guarantees which one a given failure
        // arrives as.
        if let modelError = error as? LanguageModelError {
            switch modelError {
            case .contextSizeExceeded:
                return "This conversation outgrew the on-device model's memory even after condensing older turns. Start a new chat to continue."
            case .guardrailViolation:
                return "Apple's on-device safety guardrails declined this request."
            case .rateLimited:
                return "The on-device model is rate-limited right now. Give it a moment and try again."
            case .refusal:
                return "The on-device model declined to answer this request."
            case .unsupportedLanguageOrLocale:
                return "The on-device model doesn't support this language or locale yet."
            case .timeout:
                return "The on-device model timed out on that turn. Ask again and it should go through."
            // These three have NO counterpart in the deprecated enum — they are
            // new surface, and saying "unsupported" plainly beats inventing a
            // cause (#212's lesson: a message naming the wrong reason sends the
            // reader to check something that is not broken).
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide:
                return "The on-device model couldn't satisfy this request's format or capability."
            @unknown default:
                return modelError.localizedDescription
            }
        }
        if let legacy = legacyGenerationErrorMessage(for: error) { return legacy }
        let described = error.localizedDescription
        return described.isEmpty ? "The on-device model failed to respond." : described
    }

    // MARK: - #197: retry-once on tool-argument decode failure

    /// #197 (GO, Owen 2026-08-02) — whether a failed turn is re-run, once,
    /// silently. TRUE only when ALL THREE hold:
    ///
    /// 1. The error is the argument-DECODE class: `ToolCallError` whose
    ///    underlying error is the generation layer's parse failure. That
    ///    class throws ABOVE `call()`, so the failing tool NEVER EXECUTED —
    ///    a retry cannot double-fire its side effect. An error a tool threw
    ///    from inside `call()` (#200H's readHealth proved tools do throw)
    ///    may have completed its work first, so unknown provenance never
    ///    retries.
    /// 2. The turn produced NO observable activity — no text delta, no
    ///    reasoning delta, no tool event. A DIFFERENT tool that already
    ///    completed this turn would run AGAIN on the retried turn; visible
    ///    text would restart mid-bubble. The observed specimen (spurious
    ///    WeatherTool grab as the turn's first action) is exactly the
    ///    nothing-shown shape, so this constraint costs almost no coverage.
    /// 3. It has not retried already — the second failure surfaces the
    ///    #197 message ("Ask again and it should go through").
    nonisolated static func shouldRetryToolDecodeFailure(
        _ error: Error,
        turnHadObservableActivity: Bool,
        didAlreadyRetry: Bool
    ) -> Bool {
        !didAlreadyRetry
            && !turnHadObservableActivity
            && isToolArgumentDecodeFailure(error)
    }

    /// The decode class: typed check first, then #210's lesson applied from
    /// day one — nothing guarantees which TYPE the parse failure arrives as
    /// on device, so a narrow content backstop matches the recorded phrase.
    nonisolated static func isToolArgumentDecodeFailure(_ error: Error) -> Bool {
        guard let toolError = error as? LanguageModelSession.ToolCallError else { return false }
        let underlying = toolError.underlyingError
        if legacyIsDecodingFailure(underlying) { return true }
        return String(describing: underlying).contains("Failed to parse generated content")
            || underlying.localizedDescription.contains("Failed to parse generated content")
    }

    // MARK: - #408: a guardrail-declined image turn degrades ONCE to the OCR path

    /// The guardrail class — typed successor first, #198's shape.
    ///
    /// This is the on-device safety model's decline, and #390 is what made it
    /// reachable on a SIGHTED turn for the first time: the picture reaches the
    /// model and the safety layer refuses it, at GENERATION time. No
    /// compose-time check can catch that class, which is precisely why
    /// #390-B's fallback (decode failure, arm off, no vision) left this turn
    /// with no route at all.
    nonisolated static func isGuardrailViolation(_ error: Error) -> Bool {
        if let modelError = error as? LanguageModelError,
           case .guardrailViolation = modelError { return true }
        return legacyIsGuardrailViolation(error)
    }

    /// #198's quarantine pattern — the DEPRECATED enum's guardrail arm, held
    /// in its own `@available` declaration so the call site stays quiet.
    /// Delete with `GenerationError`, alongside its siblings below.
    @available(iOS, deprecated: 27.0, message: "Delete with GenerationError; LanguageModelError.guardrailViolation is the successor (#198).")
    nonisolated static func legacyIsGuardrailViolation(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else { return false }
        if case .guardrailViolation = generationError { return true }
        return false
    }

    /// #408 (RULED 2026-08-25, route (a)) — whether a failed turn re-runs
    /// ONCE with its images demoted to #390-B's honest placeholder. TRUE only
    /// when ALL FOUR hold:
    ///
    /// 1. **It is a guardrail decline.** Nothing else in the error space is
    ///    helped by removing the picture, and an arm that fired on every
    ///    error would re-run turns that failed for reasons a demote cannot
    ///    touch.
    /// 2. **The tier is ON-DEVICE.** PCC described the very photo the
    ///    on-device layer declined — same image, 12:43 vs 14:42 on 2026-08-25
    ///    — so a PCC guardrail decline is a different question and stays a
    ///    plain error.
    /// 3. **The turn actually carried images as MODEL INPUT.** A text-only
    ///    decline cannot be helped by demoting nothing (408-C), and a turn
    ///    whose pictures already rode as the placeholder — arm off,
    ///    undecodable bytes — has nothing left to demote. Reading
    ///    `ComposedTurnInput.images` answers both for free, because
    ///    `composeTurnInput` has already put every non-sighted attachment on
    ///    the text side.
    /// 4. **It has not degraded already** (408-B). The n=4 reading is that
    ///    the guardrail's verdict is stable per image, so a second attempt
    ///    buys nothing and a loop costs the turn; a decline on the DEGRADED
    ///    retry surfaces as a plain error.
    nonisolated static func shouldDegradeImagesAfterGuardrail(
        _ error: Error,
        tierIsOnDevice: Bool,
        turnCarriedImages: Bool,
        didAlreadyDegrade: Bool
    ) -> Bool {
        !didAlreadyDegrade
            && tierIsOnDevice
            && turnCarriedImages
            && isGuardrailViolation(error)
    }

    /// #408-A: THE degrade — and deliberately not a new code path. It is
    /// `composeTurnInput` with the arm forced off: the SAME call #390-B's
    /// compose-time fallback makes for an undecodable image or a vision-less
    /// tier. A second partitioner would be a second home for the
    /// placeholder's wording and the file/image split, and the two would
    /// drift the first time either is edited.
    ///
    /// **Catch-site scope, and why two arms are the whole of it:**
    /// `makeTurnPrompt` is the ONE door from a decoded image to the model
    /// (pinned by `ImageInputCompositionTests`), and it has exactly two call
    /// sites — `send` and `streamTurn`. Both carry this arm, so no
    /// image-carrying production turn is left dead-ending. Every other
    /// `respond`/`streamResponse` in the tree (the router's guided
    /// generations, `LocalIntelligenceService`'s condensation, the DEBUG
    /// instruments) builds a text-only `Prompt` and cannot raise this class
    /// on an image. A THIRD image-carrying turn path would need its own arm.
    nonisolated static func degradedTurnInput(
        message: String, attachments: [PendingAttachment], savedNote: String?
    ) -> ComposedTurnInput {
        composeTurnInput(message: message, attachments: attachments, imageInputEnabled: false, savedNote: savedNote)
    }

    /// #408-D: what the reply says happened.
    ///
    /// PRODUCTION COPY (#218's rule — this is read on a real turn, so it
    /// lives outside every `#if DEBUG`). Register deliberately matches
    /// `composePrompt`'s image placeholder, the sentence the model itself
    /// receives on the degraded leg. Three things it must do and one it must
    /// not: name the TIER (PCC saw this picture — an unqualified "safety
    /// declined it" would read as Talaria's own refusal), name the true cause
    /// (#212), say what the answer is therefore built from — and never
    /// promise that trying again will work, because the measured verdict is
    /// stable per image.
    ///
    /// "any text read from it" is the honest scope: OCR is the user's own
    /// #8 extraction, so the degraded turn carries the picture's text only
    /// when they asked for it. Claiming the text was read would be a
    /// fabrication on the turns where it wasn't.
    nonisolated static func guardrailImageDegradeNote(imageCount: Int) -> String {
        let subject = imageCount == 1 ? "the attached image," : "the attached images,"
        let object = imageCount == 1 ? "it" : "them"
        let pictures = imageCount == 1 ? "the picture itself" : "the pictures themselves"
        return "[Apple's on-device safety layer declined \(subject) so this turn ran without \(object) — "
            + "the answer above uses your message and any text read from \(object), not \(pictures).]"
    }

    /// The settle-point composition for the note (#257 lever 1b's shape, and
    /// for its reason): APPENDED, so the model's own reply survives verbatim
    /// as the prefix and a note can never destroy an answer. `0` — every turn
    /// that did not degrade — is the identity function.
    nonisolated static func replyNotingGuardrailImageDegrade(
        _ settledText: String, degradedImageCount: Int
    ) -> String {
        guard degradedImageCount > 0 else { return settledText }
        let note = guardrailImageDegradeNote(imageCount: degradedImageCount)
        guard !settledText.isEmpty else { return note }
        return settledText + "\n\n" + note
    }

    /// #198's quarantine pattern: the DEPRECATED enum's arm, deleted with
    /// the symbol. `LanguageModelError` declares NO decode counterpart
    /// (verified against the beta-4 swiftinterface, 2026-08-02), so this
    /// deprecated case plus the content backstop above are the whole class.
    @available(iOS, deprecated: 27.0, message: "Delete with GenerationError (#198).")
    nonisolated static func legacyIsDecodingFailure(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else { return false }
        if case .decodingFailure = generationError { return true }
        return false
    }

    /// #198: the DEPRECATED `GenerationError` overflow case, quarantined for
    /// the same reason as `legacyGenerationErrorMessage` — see its note. Delete
    /// both together when the symbol goes.
    @available(iOS, deprecated: 27.0, message: "Delete with GenerationError; LanguageModelError.contextSizeExceeded is the successor (#198).")
    nonisolated static func legacyIsContextOverflow(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else { return false }
        if case .exceededContextWindowSize = generationError { return true }
        return false
    }

    /// #198: the DEPRECATED `GenerationError` arm, quarantined.
    ///
    /// Kept because deprecated is not removed — the beta-4 SDK still declares
    /// it, and nothing guarantees which type a given failure arrives as. Held
    /// in its own `@available`-annotated function so the deprecation warning
    /// stops firing at the call site and the remaining #198 surface stays
    /// legible; Swift silences deprecation inside a declaration that is itself
    /// marked deprecated.
    ///
    /// **This does NOT remove the beta-5 risk and is not pretending to.** If a
    /// seed deletes `GenerationError`, this function stops compiling and must
    /// be deleted — at which point its four unique cases (`concurrentRequests`,
    /// `assetsUnavailable`, `decodingFailure`, `unsupportedGuide`) become
    /// unreachable by construction, since the type that carries them no longer
    /// exists. Deleting it then costs nothing; deleting it NOW would drop
    /// handling for a throw that is still possible today.
    @available(iOS, deprecated: 27.0, message: "Delete with GenerationError; LanguageModelError is the successor (#198).")
    nonisolated static func legacyGenerationErrorMessage(for error: Error) -> String? {
        guard let generationError = error as? LanguageModelSession.GenerationError else { return nil }
        switch generationError {
        case .exceededContextWindowSize:
            return "This conversation outgrew the on-device model's memory even after condensing older turns. Start a new chat to continue."
        case .guardrailViolation:
            return "Apple's on-device safety guardrails declined this request."
        case .rateLimited:
            return "The on-device model is rate-limited right now. Give it a moment and try again."
        case .concurrentRequests:
            return "The on-device model is still working on the previous request. Wait for it to finish, then try again."
        case .assetsUnavailable:
            return "The on-device model's assets aren't available right now — Apple Intelligence may still be downloading."
        case .refusal:
            return "The on-device model declined to answer this request."
        case .unsupportedLanguageOrLocale:
            return "The on-device model doesn't support this language or locale yet."
        case .decodingFailure:
            return "The on-device model produced a response Talaria couldn't decode."
        case .unsupportedGuide:
            return "The on-device model couldn't satisfy the requested output format."
        @unknown default:
            return generationError.localizedDescription
        }
    }
}

enum LocalChatBackendError: LocalizedError {
    case unknownModel(String)
    case sessionNotFound(String)
    /// #190B: the session's row exists but its stored transcript failed to
    /// decode — distinct from an unknown id so the failure the user sees
    /// tells the truth about what went wrong.
    case sessionUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let id):
            return "The on-device brain has no model \"\(id)\"."
        case .sessionNotFound(let id):
            return "No local conversation \"\(id)\" is stored on this device."
        case .sessionUnreadable:
            return "This conversation is stored on the device, but its transcript couldn't be read."
        }
    }
}

extension LocalChatBackend.PrivateCloudStatus {

    /// **#391: the quota row as FIELDS, not as a sentence.**
    ///
    /// Owen's ruling (2026-08-21): *"Print what it shows. If it's nil, it's
    /// nil. Same with the optional reset date. But when it starts showing a
    /// number, it'll already be there."* So the row always carries a RESETS
    /// field, and an absent reset date renders `—` rather than being omitted
    /// — the absence is the information. A user who sees `RESETS —` beside a
    /// status can tell the app was not told when the window turns over; a row
    /// that silently dropped the field could not convey that.
    ///
    /// Pure and `now`-injected so the today-vs-later branch is assertable
    /// without a clock (the `resolveBareClock(_:now:)` precedent from #340).
    static func quotaRowLabel(
        quota: Quota,
        resetDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        // #404: assembled from the SAME field formatters the visual row
        // renders, so the VoiceOver sentence and the on-screen fields can
        // never disagree. Output is byte-identical to the pre-#404 form —
        // the #391 pins run against it unchanged.
        "PRIVATE CLOUD β · \(quotaStateText(quota)) · RESETS \(resetFieldText(resetDate, now: now, calendar: calendar))"
    }

    /// The QUOTA field's value, one arm per SDK fact (#391: an unrecognised
    /// status says so — it does not say "you're fine").
    static func quotaStateText(_ quota: Quota) -> String {
        switch quota {
        case .belowLimit(approaching: false): "BELOW DAILY LIMIT"
        case .belowLimit(approaching: true): "NEARING DAILY LIMIT"
        case .limitReached: "DAILY LIMIT REACHED"
        case .unknown: "STATUS —"
        }
    }

    /// `—` for nil; a bare time when the reset falls today (the common case,
    /// where a date would be noise); date + time otherwise, because "resets
    /// at 9:00" is ambiguous and useless if the turnover is tomorrow — which
    /// is precisely the case Owen named as the one worth surfacing.
    static func resetFieldText(
        _ resetDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let resetDate else { return "—" }
        if calendar.isDate(resetDate, inSameDayAs: now) {
            return resetDate.formatted(date: .omitted, time: .shortened)
        }
        return resetDate.formatted(date: .abbreviated, time: .shortened)
    }
}

extension LocalChatBackend.PrivateCloudStatus {

    /// **#391: the pure mapping from the OS's facts to what the row shows.**
    ///
    /// `isApproachingLimit == nil` means the SDK reported a status this build
    /// cannot name — which is `unknown`, not reassurance. That arm used to be
    /// folded into `belowLimit(approaching: false)`.
    ///
    /// `resetDate` is passed through on EVERY arm. The bug this closes was in
    /// the plumbing rather than the formatting: the date was read only inside
    /// the limit-reached branch, so on the below-limit path a value the OS had
    /// supplied never reached the view at all.
    static func make(
        isLimitReached: Bool,
        isApproachingLimit: Bool?,
        resetDate: Date?,
        hasLimitIncreaseSuggestion: Bool
    ) -> Self {
        let quota: Quota
        if isLimitReached {
            quota = .limitReached
        } else if let isApproachingLimit {
            quota = .belowLimit(approaching: isApproachingLimit)
        } else {
            quota = .unknown
        }
        return .init(
            quota: quota,
            resetDate: resetDate,
            hasLimitIncreaseSuggestion: hasLimitIncreaseSuggestion
        )
    }
}
