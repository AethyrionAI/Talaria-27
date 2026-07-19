import Foundation
import Testing
@testable import Talaria

/// #46 — turn receipts: pricing-catalog parsing/matching, cost math, and the
/// receipt formatting used by the bubble footer and the status card.
struct TurnReceiptsTests {

    // MARK: - Price-string parsing

    @Test
    func parsesShimPriceDisplayStrings() {
        #expect(ModelPricingCatalog.parsePrice("$5.00") == 5.0)
        #expect(ModelPricingCatalog.parsePrice("$0.09") == 0.09)
        #expect(ModelPricingCatalog.parsePrice("$1,000.50") == 1000.5)
        #expect(ModelPricingCatalog.parsePrice(" $25.00 ") == 25.0)
        #expect(ModelPricingCatalog.parsePrice("3.20") == 3.2)
        #expect(ModelPricingCatalog.parsePrice(nil) == nil)
        #expect(ModelPricingCatalog.parsePrice("") == nil)
        #expect(ModelPricingCatalog.parsePrice("free") == nil)
        #expect(ModelPricingCatalog.parsePrice("$-1.00") == nil)
    }

    // MARK: - Catalog matching

    @MainActor
    private func makeCatalog() -> ModelPricingCatalog {
        let suiteName = "turn-receipts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ModelPricingCatalog(defaults: defaults)
    }

    /// Decodes a miniature shim payload through the same snake_case decoder
    /// the live client uses, so `pricing` decoding is exercised end-to-end.
    private func decodeOptions(_ json: String) throws -> ShimModelOptions {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ShimModelOptions.self, from: Data(json.utf8))
    }

    private static let sampleOptionsJSON = """
    {
      "providers": [
        {
          "slug": "nous",
          "is_current": true,
          "models": ["anthropic/claude-opus-4.8", "deepseek/deepseek-v4-pro"],
          "pricing": {
            "anthropic/claude-opus-4.8": {"input": "$5.00", "output": "$25.00", "cache": "$0.50", "free": false},
            "deepseek/deepseek-v4-pro": {"input": "$1.60", "output": "$3.20", "cache": "$0.14", "free": false},
            "stepfun/step-3.7-flash:free": {"input": null, "output": null, "cache": null, "free": true}
          }
        }
      ],
      "model": "deepseek/deepseek-v4-pro",
      "provider": "nous"
    }
    """

    @Test @MainActor
    func ingestHarvestsParseablePricingAndSkipsFreeRows() throws {
        let catalog = makeCatalog()
        catalog.ingest(try decodeOptions(Self.sampleOptionsJSON))

        #expect(catalog.pricingByModelID.count == 2)
        #expect(catalog.pricing(forModel: "anthropic/claude-opus-4.8")?.inputPerMTok == 5.0)
        // Null price strings (free tier) never become a pricing entry.
        #expect(catalog.pricing(forModel: "stepfun/step-3.7-flash:free") == nil)
    }

    @Test @MainActor
    func pricingLookupToleratesIdSpellings() throws {
        let catalog = makeCatalog()
        catalog.ingest(try decodeOptions(Self.sampleOptionsJSON))

        // Exact (case-insensitive) match.
        #expect(catalog.pricing(forModel: "Anthropic/Claude-Opus-4.8")?.outputPerMTok == 25.0)
        // Gateway `provider:model` spelling and the bare model id both match
        // on the bare name when unambiguous.
        #expect(catalog.pricing(forModel: "deepseek:deepseek-v4-pro")?.inputPerMTok == 1.6)
        #expect(catalog.pricing(forModel: "claude-opus-4.8")?.inputPerMTok == 5.0)
        #expect(catalog.pricing(forModel: "unknown-model") == nil)
        #expect(catalog.pricing(forModel: nil) == nil)
    }

    @Test @MainActor
    func ambiguousBareNameWithDifferentPricesRefusesToGuess() throws {
        let catalog = makeCatalog()
        let json = """
        {
          "providers": [
            {
              "slug": "a",
              "pricing": {"prov-a/shared-model": {"input": "$1.00", "output": "$2.00", "cache": null, "free": false}}
            },
            {
              "slug": "b",
              "pricing": {"prov-b/shared-model": {"input": "$9.00", "output": "$18.00", "cache": null, "free": false}}
            }
          ]
        }
        """
        catalog.ingest(try decodeOptions(json))
        #expect(catalog.pricing(forModel: "shared-model") == nil)
    }

    @Test @MainActor
    func costEstimateUsesPerMillionTokenUnits() throws {
        let catalog = makeCatalog()
        catalog.ingest(try decodeOptions(Self.sampleOptionsJSON))

        let usage = TokenUsage(promptTokens: 100_000, completionTokens: 10_000, totalTokens: 110_000)
        let cost = try #require(catalog.estimatedCost(for: usage, model: "anthropic/claude-opus-4.8"))
        // 0.1M × $5 + 0.01M × $25 = $0.75
        #expect(abs(cost - 0.75) < 0.000001)
        #expect(catalog.estimatedCost(for: usage, model: "no-such-model") == nil)
    }

    @Test @MainActor
    func sessionCostSumsOnlyPricedTurnsAndReportsCoverage() throws {
        let catalog = makeCatalog()
        catalog.ingest(try decodeOptions(Self.sampleOptionsJSON))

        let usage = TokenUsage(promptTokens: 1_000_000, completionTokens: 0, totalTokens: 1_000_000)
        let messages = [
            Message(sender: .user, content: "q", status: .delivered),
            Message(sender: .hermes, content: "a1", status: .delivered,
                    usage: usage, servingModel: "anthropic/claude-opus-4.8"),
            Message(sender: .hermes, content: "a2", status: .delivered,
                    usage: usage, servingModel: "mystery-model"),
            Message(sender: .hermes, content: "unmetered", status: .delivered),
        ]

        let estimate = try #require(catalog.estimatedSessionCost(for: messages))
        #expect(abs(estimate.cost - 5.0) < 0.000001)
        #expect(estimate.costedTurns == 1)

        #expect(catalog.estimatedSessionCost(for: [messages[0], messages[3]]) == nil)
    }

    // MARK: - Receipt persistence (Message round-trip)

    @Test
    func receiptFieldsSurviveTheConversationCacheRoundTrip() throws {
        let original = Message(
            sender: .hermes, content: "a", status: .delivered,
            usage: TokenUsage(promptTokens: 1204, completionTokens: 356, totalTokens: 1560),
            turnDuration: 8.4,
            servingModel: "deepseek/deepseek-v4-pro"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.usage?.promptTokens == 1204)
        #expect(decoded.usage?.completionTokens == 356)
        #expect(decoded.turnDuration == 8.4)
        #expect(decoded.servingModel == "deepseek/deepseek-v4-pro")

        // Pre-#46 caches (no receipt keys) still decode.
        let legacy = Message(sender: .hermes, content: "old", status: .delivered)
        let legacyDecoded = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(legacy))
        #expect(legacyDecoded.usage == nil)
        #expect(legacyDecoded.turnDuration == nil)
    }

    // MARK: - Formatting

    @Test
    func tokenLabelsCompactCleanly() {
        #expect(TurnReceiptFormat.tokenLabel(356) == "356")
        #expect(TurnReceiptFormat.tokenLabel(1_204) == "1.2K")
        #expect(TurnReceiptFormat.tokenLabel(12_000) == "12K")
        #expect(TurnReceiptFormat.tokenLabel(2_400_000) == "2.4M")
        #expect(TurnReceiptFormat.fullTokenLabel(1_204) == "1,204")
    }

    @Test
    func durationLabelsScaleWithMagnitude() {
        #expect(TurnReceiptFormat.durationLabel(8.4) == "8.4S")
        #expect(TurnReceiptFormat.durationLabel(9.0) == "9S")
        #expect(TurnReceiptFormat.durationLabel(42.7) == "43S")
        #expect(TurnReceiptFormat.durationLabel(96) == "1M 36S")
        #expect(TurnReceiptFormat.durationLabel(-1) == "—")
    }

    @Test
    func costLabelsNeverShowZeroForRealMoney() {
        #expect(TurnReceiptFormat.costLabel(0.12) == "$0.12")
        #expect(TurnReceiptFormat.costLabel(0.0042) == "$0.0042")
        #expect(TurnReceiptFormat.costLabel(0.00001) == "<$0.0001")
        #expect(TurnReceiptFormat.costLabel(0) == "$0.00")
    }

    @Test
    func receiptLineOmitsWhatItDoesNotKnow() {
        let usage = TokenUsage(promptTokens: 1204, completionTokens: 356, totalTokens: 1560)
        #expect(
            TurnReceiptFormat.receiptLine(usage: usage, duration: 8.4, cost: 0.0042)
                == "IN 1.2K · OUT 356 · 8.4S · ~$0.0042"
        )
        #expect(
            TurnReceiptFormat.receiptLine(usage: usage, duration: nil, cost: nil)
                == "IN 1.2K · OUT 356"
        )
    }

    // MARK: - Session cost & usage surface (#122)

    /// Decodes the flat usage keys the way the LIST/DETAIL row does, so
    /// `SessionUsage.decodeIfPresent` is exercised against real row JSON.
    private struct UsageRowFixture: Decodable {
        let usage: SessionUsage?
        init(from decoder: Decoder) throws { usage = SessionUsage.decodeIfPresent(from: decoder) }
    }

    private func decodeUsage(_ json: String) throws -> SessionUsage? {
        try JSONDecoder().decode(UsageRowFixture.self, from: Data(json.utf8)).usage
    }

    /// A full `/api/sessions` row modeled on the #25 probe's real shape — every
    /// #122 usage key plus the ignored `has_*` flags and the row's own
    /// title/model/etc. that sit alongside the flat usage keys.
    private static let fullUsageRowJSON = """
    {
      "id": "api_1783825106_6e2766ab",
      "title": "Morning briefing",
      "model": "anthropic/claude-opus-4.8",
      "source": "api_server",
      "message_count": 10,
      "last_active": 1752600000.0,
      "is_active": false,
      "input_tokens": 114754,
      "output_tokens": 2310,
      "cache_read_tokens": 98000,
      "cache_write_tokens": 1200,
      "reasoning_tokens": 540,
      "api_call_count": 5,
      "tool_call_count": 3,
      "estimated_cost_usd": 0.6421,
      "actual_cost_usd": 0.5893,
      "has_system_prompt": true,
      "has_model_config": true
    }
    """

    @Test
    func fullRowDecodesEveryUsageField() throws {
        let usage = try #require(try decodeUsage(Self.fullUsageRowJSON))
        #expect(usage.inputTokens == 114754)
        #expect(usage.outputTokens == 2310)
        #expect(usage.cacheReadTokens == 98000)
        #expect(usage.cacheWriteTokens == 1200)
        #expect(usage.reasoningTokens == 540)
        #expect(usage.apiCallCount == 5)
        #expect(usage.toolCallCount == 3)
        #expect(usage.estimatedCostUSD == 0.6421)
        #expect(usage.actualCostUSD == 0.5893)
    }

    @Test
    func probeShapeRowDecodesTokensAndApiButNoCost() throws {
        // The #25 probe saw only these keys on the wire — the cost keys are
        // absent. Those fields must be nil, the present ones populated.
        let json = """
        {"id": "api_x", "input_tokens": 70271, "output_tokens": 1800,
         "cache_read_tokens": 50000, "reasoning_tokens": 0, "api_call_count": 6,
         "has_system_prompt": true}
        """
        let usage = try #require(try decodeUsage(json))
        #expect(usage.inputTokens == 70271)
        #expect(usage.apiCallCount == 6)
        #expect(usage.reasoningTokens == 0)
        #expect(usage.estimatedCostUSD == nil)
        #expect(usage.actualCostUSD == nil)
        #expect(usage.toolCallCount == nil)
    }

    @Test
    func nullUsageValuesDecodeToNilNotZero() throws {
        let json = """
        {"id": "api_x", "input_tokens": null, "output_tokens": null,
         "api_call_count": null, "estimated_cost_usd": null, "actual_cost_usd": null}
        """
        // All-null usage keys are indistinguishable from absent → nil usage,
        // so the row carries no cost surface (never a row of zeros).
        #expect(try decodeUsage(json) == nil)
    }

    @Test
    func rowWithoutAnyUsageKeyDecodesToNilUsage() throws {
        let json = #"{"id": "api_x", "title": "Just a title", "message_count": 4}"#
        #expect(try decodeUsage(json) == nil)
    }

    @Test
    func malformedUsageFieldDegradesToNilAndNeverThrows() throws {
        // A wrong-typed field drops to nil for that field only; the rest still
        // decode and the call never throws (the #58 tolerant posture).
        let json = """
        {"id": "api_x", "input_tokens": "not-a-number", "output_tokens": 2310,
         "api_call_count": 5, "actual_cost_usd": "free"}
        """
        let usage = try #require(try decodeUsage(json))
        #expect(usage.inputTokens == nil)
        #expect(usage.outputTokens == 2310)
        #expect(usage.apiCallCount == 5)
        #expect(usage.actualCostUSD == nil)
    }

    @Test
    func readoutPrefersActualCostOverEstimate() {
        let usage = SessionUsage(
            inputTokens: 66_400, outputTokens: 1_204, apiCallCount: 5,
            estimatedCostUSD: 0.6421, actualCostUSD: 0.5893
        )
        let d = SessionCostReadout.display(for: usage)
        #expect(d?.costText == "$0.59")
        #expect(d?.costIsEstimated == false)
        #expect(d?.inputText == "66.4k")
        #expect(d?.outputText == "1.2k")
        #expect(d?.apiCallsText == "5")
        #expect(d?.line == "$0.59 · IN 66.4k · OUT 1.2k · 5 CALLS")
    }

    @Test
    func readoutFallsBackToEstimateMarkedWithTilde() {
        let usage = SessionUsage(inputTokens: 500, outputTokens: 200, apiCallCount: 2, estimatedCostUSD: 0.0421)
        let d = SessionCostReadout.display(for: usage)
        #expect(d?.costText == "$0.04")
        #expect(d?.costIsEstimated == true)
        #expect(d?.line == "~$0.04 · IN 500 · OUT 200 · 2 CALLS")
    }

    @Test
    func readoutTreatsZeroActualCostAsUncomputedAndFallsThrough() {
        let usage = SessionUsage(inputTokens: 100, estimatedCostUSD: 0.5, actualCostUSD: 0)
        let d = SessionCostReadout.display(for: usage)
        #expect(d?.costText == "$0.50")
        #expect(d?.costIsEstimated == true)
    }

    @Test
    func readoutShowsSubCentCostAsThreshold() {
        #expect(SessionCostReadout.display(for: SessionUsage(actualCostUSD: 0.004))?.line == "<$0.01")
        #expect(SessionCostReadout.display(for: SessionUsage(estimatedCostUSD: 0.004))?.line == "~<$0.01")
    }

    @Test
    func readoutHidesEntirelyWhenNothingIsKnown() {
        #expect(SessionCostReadout.display(for: nil) == nil)
        #expect(SessionCostReadout.display(for: SessionUsage()) == nil)
        // Present-but-zero everywhere is still "nothing to show" — never zeros.
        let zeros = SessionUsage(inputTokens: 0, outputTokens: 0, apiCallCount: 0,
                                 estimatedCostUSD: 0, actualCostUSD: 0)
        #expect(SessionCostReadout.display(for: zeros) == nil)
    }

    @Test
    func readoutShowsUsageEvenWhenCostIsAbsent() {
        // The #25 probe shape: tokens + api calls, no cost keys. The cost
        // segment is omitted; the rest still render.
        let usage = SessionUsage(inputTokens: 114_754, outputTokens: 2_310, apiCallCount: 5)
        let d = SessionCostReadout.display(for: usage)
        #expect(d?.costText == nil)
        #expect(d?.line == "IN 114.8k · OUT 2.3k · 5 CALLS")
    }

    @Test
    func sessionTokenLabelsAbbreviateWithLowercaseUnits() {
        #expect(SessionCostReadout.positiveTokenText(356) == "356")
        #expect(SessionCostReadout.positiveTokenText(1_000) == "1k")
        #expect(SessionCostReadout.positiveTokenText(66_400) == "66.4k")
        #expect(SessionCostReadout.positiveTokenText(2_400_000) == "2.4m")
        #expect(SessionCostReadout.positiveTokenText(0) == nil)
        #expect(SessionCostReadout.positiveTokenText(nil) == nil)
    }

    @Test
    func sessionCostLabelThresholds() {
        #expect(SessionCostReadout.costLabel(1.24) == "$1.24")
        #expect(SessionCostReadout.costLabel(0.01) == "$0.01")
        #expect(SessionCostReadout.costLabel(0.004) == "<$0.01")
    }
}
