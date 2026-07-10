import Foundation
import Testing
@testable import Talaria

/// P1 ACCEPTANCE SUITE (OPEN_ITEMS #90 — REQUIRED): condenser fidelity, the
/// #89 probe's one residual risk. The probe validated the transplant
/// MECHANISM with the full Hermes model as an optimistic condensation proxy;
/// the on-device `LocalIntelligenceService` condenser is weaker and needs
/// pruning discipline MORE. These tests are the guardrail:
///
/// - corrections survive at their LATEST value (never the superseded one);
/// - distractors are pruned (pruning discipline = token cost);
/// - the produced priming stays inside the token budget.
///
/// The model-path tests carry an availability condition: they run for real on
/// Apple Intelligence hardware (the Mac-side test run / on-device), and skip
/// honestly where the system model doesn't exist (CI containers). A skip is
/// NOT a pass — the Mac run is the acceptance gate (see OPEN_ITEMS #90).
struct CondenserFidelityTests {

    // MARK: - The messy transcript (2 corrections + 2 distractors)

    /// Correction pairs use token-disjoint values ("3 PM" → "4:30",
    /// "Drake" → "Palmer House") so substring assertions cannot
    /// false-positive against the corrected text.
    static func messyEntries() -> [ConversationJournal.Entry] {
        [
            .init(role: .user, text: "I'm planning my Chicago trip. My flight lands at 3 PM on Friday at O'Hare."),
            .init(role: .assistant, text: "Got it — Chicago on Friday, landing at 3 PM at O'Hare. Want me to plan the evening around that?"),
            // Distractor 1: trivia the conversation never builds on.
            .init(role: .user, text: "Random, but did you know octopuses have three hearts? Anyway."),
            .init(role: .assistant, text: "They do! Back to the trip whenever you're ready."),
            // Correction 1: arrival time supersedes.
            .init(role: .user, text: "Correction — the flight actually lands at 4:30, not earlier."),
            .init(role: .assistant, text: "Updated: landing at 4:30 on Friday."),
            .init(role: .user, text: "I'll be staying at the Drake. Book dinner somewhere near the hotel."),
            .init(role: .assistant, text: "The Drake, noted — I'll look for dinner options nearby."),
            // Distractor 2: unrelated one-off.
            .init(role: .user, text: "Oh, and my cousin's dog is named Waffles. Unrelated."),
            .init(role: .assistant, text: "Waffles is a great name. Back to dinner planning."),
            // Correction 2: hotel supersedes.
            .init(role: .user, text: "Actually we switched hotels — it's the Palmer House now, not the Drake."),
            .init(role: .assistant, text: "Switched: Palmer House. I'll center the dinner search there."),
        ]
    }

    /// Availability probe for the `.enabled` condition below.
    static func onDeviceModelAvailable() async -> Bool {
        await MainActor.run { LocalIntelligenceService().isModelAvailable }
    }

    // MARK: - Acceptance: the condenser path (model-gated)

    @Test(
        "Condensed priming: latest corrected values, no distractors, in budget",
        .enabled("Requires the on-device Apple Intelligence model — run Mac-side / on-device") {
            await CondenserFidelityTests.onDeviceModelAvailable()
        }
    )
    @MainActor
    func condensedPrimingFidelity() async throws {
        let intelligence = LocalIntelligenceService()
        let transplanter = ContextTransplanter(intelligence: intelligence)

        let composition = await transplanter.composePriming(from: Self.messyEntries())
        try #require(
            composition.condensedByModel,
            "model reported available but composition fell back — the condenser path never ran"
        )
        let brief = composition.text.lowercased()

        // (a) Corrections preserved at their LATEST value — and the
        // superseded value never regresses back in.
        #expect(brief.contains("4:30"), "lost the corrected arrival time")
        #expect(!brief.contains("3 pm"), "carried the superseded arrival time")
        #expect(brief.contains("palmer house"), "lost the corrected hotel")
        #expect(!brief.contains("drake"), "carried the superseded hotel")

        // (b) Distractors pruned — every carried fact costs tokens.
        #expect(!brief.contains("octopus"), "carried distractor 1 (octopus trivia)")
        #expect(!brief.contains("three hearts"), "carried distractor 1 (octopus trivia)")
        #expect(!brief.contains("waffles"), "carried distractor 2 (cousin's dog)")

        // (c) Budget discipline, measured with the same tokenizer the
        // composer used.
        let measured = await intelligence.measuredTokenCount(of: composition.text)
        #expect(
            measured <= ContextTransplanter.primingTokenBudget,
            "priming measured \(measured) tokens against a budget of \(ContextTransplanter.primingTokenBudget)"
        )

        // The essentials survived at all — a brief that prunes everything is
        // no context transplant.
        #expect(brief.contains("chicago"), "lost the conversation's core subject")
    }

    @Test(
        "Condensed priming stays in budget on a long journal",
        .enabled("Requires the on-device Apple Intelligence model — run Mac-side / on-device") {
            await CondenserFidelityTests.onDeviceModelAvailable()
        }
    )
    @MainActor
    func condensedPrimingBudgetOnLongJournal() async throws {
        let intelligence = LocalIntelligenceService()
        let transplanter = ContextTransplanter(intelligence: intelligence)

        // ~80 turns of varied content — enough to exceed the priming budget
        // many times over, and to force the model-input tail fitting.
        var entries: [ConversationJournal.Entry] = []
        for index in 0 ..< 40 {
            entries.append(.init(
                role: .user,
                text: "Item \(index): the reading for sensor channel \(index) came back at \(index * 3) units; log it and compare against last week's baseline of \(index * 2) units."
            ))
            entries.append(.init(
                role: .assistant,
                text: "Logged channel \(index) at \(index * 3) units — that's \(index) over the baseline. I'll flag it if the trend continues."
            ))
        }

        let composition = await transplanter.composePriming(from: entries)
        let measured = await intelligence.measuredTokenCount(of: composition.text)
        #expect(
            measured <= ContextTransplanter.primingTokenBudget,
            "long-journal priming measured \(measured) tokens against a budget of \(ContextTransplanter.primingTokenBudget)"
        )
    }

    // MARK: - Deterministic: the fallback path (always runs)

    /// The fallback is verbatim by design — it cannot prune distractors
    /// (deterministic code can't judge relevance, and fabricating
    /// condensation would violate real-data-only). What it MUST do: keep the
    /// newest turns (which carry the corrections at their latest values),
    /// mark omissions honestly, and hold the budget.
    @Test @MainActor
    func fallbackKeepsNewestTurnsAndCorrections() async {
        let intelligence = LocalIntelligenceService()
        let transplanter = ContextTransplanter(intelligence: intelligence)

        let composition = await transplanter.fallbackPriming(
            from: Self.messyEntries(),
            tokenBudget: ContextTransplanter.primingTokenBudget
        )
        #expect(!composition.condensedByModel)
        let text = composition.text.lowercased()
        // The full messy transcript fits the default budget — nothing dropped,
        // and both corrections are present at their latest values.
        #expect(text.contains("4:30"))
        #expect(text.contains("palmer house"))
        #expect(!text.contains("omitted"))
    }

    @Test @MainActor
    func fallbackHoldsBudgetAndCutsOldestFirst() async {
        let intelligence = LocalIntelligenceService()
        let transplanter = ContextTransplanter(intelligence: intelligence)

        // A tight budget forces dropping older turns. The newest turn (the
        // hotel correction) must survive; the drop must be from the front;
        // the omission must be marked. 200 tokens ≈ the preamble plus a
        // couple of turns on either tokenizer (real or chars/3 estimate).
        let budget = 200
        let composition = await transplanter.fallbackPriming(from: Self.messyEntries(), tokenBudget: budget)
        let text = composition.text

        let measured = await intelligence.measuredTokenCount(of: text)
        #expect(measured <= budget, "fallback measured \(measured) tokens against a budget of \(budget)")
        #expect(text.lowercased().contains("palmer house"), "the newest correction fell out of the tail")
        #expect(text.contains("earlier turn"), "omissions must be marked honestly")
        #expect(!text.lowercased().contains("o'hare"), "the oldest turn should have been dropped first")
    }

    @Test @MainActor
    func fallbackSurvivesSingleOversizedTurn() async {
        let intelligence = LocalIntelligenceService()
        let transplanter = ContextTransplanter(intelligence: intelligence)

        let monster = String(repeating: "specification detail, ", count: 400)
        let composition = await transplanter.fallbackPriming(
            from: [.init(role: .user, text: monster)],
            tokenBudget: 200
        )
        let measured = await intelligence.measuredTokenCount(of: composition.text)
        // The single turn ships cut-to-fit rather than failing the transplant.
        #expect(!composition.text.isEmpty)
        #expect(measured <= 200, "oversized single turn measured \(measured) tokens against a budget of 200")
    }

    // MARK: - Deterministic: priming wire format

    @Test
    func primingTextCarriesThePayloadBehindThePreamble() {
        let text = ContextTransplanter.primingText(body: "- Fact one\n- Fact two")
        #expect(text.hasPrefix("[CONTEXT TRANSPLANT"))
        #expect(text.contains("most recent corrected value"))
        #expect(text.hasSuffix("- Fact one\n- Fact two"))
    }

    @Test
    func renderedLinesNameTheSpeakers() {
        #expect(ContextTransplanter.renderedLine(role: .user, text: "hi") == "User: hi")
        #expect(ContextTransplanter.renderedLine(role: .assistant, text: "hello") == "Hermes: hello")
        #expect(ContextTransplanter.renderedBody(lines: ["a", "b"], omittedCount: 0) == "a\nb")
        #expect(ContextTransplanter.renderedBody(lines: ["b"], omittedCount: 3)
            .hasPrefix("(3 earlier turns omitted"))
    }
}
