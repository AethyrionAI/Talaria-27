import Foundation
import Observation

// MARK: - Turn receipts (#46)
//
// Per-turn tokens/cost/time were always on the wire (`run.completed` usage,
// `pendingMessageSentAt`) and the pricing was always in the shim's model
// payload — decoded and thrown away. This file is the keep-it half: a
// persisted pricing catalog harvested from the picker's existing fetches,
// plus the display formatting for the bubble-footer receipts and the
// session status card.
//
// Every dollar figure is an ESTIMATE and labeled as such: usage carries no
// cache-read split, so cached turns over-estimate, and pricing strings imply
// per-1M-token units without stating them.

/// Per-1M-token pricing for one model, parsed from the shim's display strings
/// (`"$5.00"` → 5.0).
struct ModelPricing: Codable, Hashable, Sendable {
    let inputPerMTok: Double
    let outputPerMTok: Double
}

@MainActor
@Observable
final class ModelPricingCatalog {
    static let shared = ModelPricingCatalog()

    /// Keyed by normalized (lowercased) model id as the shim reports it —
    /// usually `provider/model` ("anthropic/claude-opus-4.8"), sometimes bare
    /// ("kimi-k2.7-code").
    private(set) var pricingByModelID: [String: ModelPricing] = [:]

    private let defaults: UserDefaults
    private static let defaultsKey = "talaria.modelPricingCatalog.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([String: ModelPricing].self, from: data) {
            pricingByModelID = stored
        }
    }

    /// Harvests pricing from a shim payload the picker already fetched.
    /// Merges (payloads can be partial when providers are unauthenticated)
    /// and persists so estimates survive relaunch and shim downtime.
    func ingest(_ options: ShimModelOptions) {
        var merged = pricingByModelID
        for provider in options.providers {
            for (modelID, display) in provider.pricing ?? [:] {
                if let input = Self.parsePrice(display.input),
                   let output = Self.parsePrice(display.output) {
                    merged[Self.normalize(modelID)] = ModelPricing(
                        inputPerMTok: input,
                        outputPerMTok: output
                    )
                }
            }
        }
        guard merged != pricingByModelID else { return }
        pricingByModelID = merged
        if let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Pricing lookup tolerant of the three id spellings in play: catalog
    /// keys are `provider/model` or bare; the gateway's active-model string
    /// can be `provider:model`. Exact match first, then match on the bare
    /// model name — but only when that's unambiguous (same model name under
    /// two providers with different prices returns nil rather than a guess).
    func pricing(forModel modelID: String?) -> ModelPricing? {
        guard let modelID, !modelID.isEmpty else { return nil }
        let normalized = Self.normalize(modelID)
        if let exact = pricingByModelID[normalized] { return exact }

        let bare = Self.bareModelName(normalized)
        let candidates = Set(
            pricingByModelID
                .filter { Self.bareModelName($0.key) == bare }
                .map(\.value)
        )
        return candidates.count == 1 ? candidates.first : nil
    }

    /// Estimated dollars for one turn. Over-estimates cached turns (usage has
    /// no cache-read split) — callers must label it an estimate.
    func estimatedCost(for usage: TokenUsage, model: String?) -> Double? {
        guard let pricing = pricing(forModel: model) else { return nil }
        return Double(usage.promptTokens) / 1_000_000 * pricing.inputPerMTok
            + Double(usage.completionTokens) / 1_000_000 * pricing.outputPerMTok
    }

    /// Session-total estimate over every metered Hermes turn — plus context
    /// transplant priming turns (#90): priming is real spend and must land in
    /// the total. Returns the summed cost plus how many of the metered items
    /// it actually covers — partial coverage (a turn served by an unpriced
    /// model) must be shown honestly, never passed off as the full total.
    func estimatedSessionCost(for messages: [Message]) -> (cost: Double, costedTurns: Int)? {
        var cost = 0.0
        var costed = 0
        for message in messages where message.sender == .hermes || message.isContextPriming {
            guard let usage = message.usage else { continue }
            if let turnCost = estimatedCost(for: usage, model: message.servingModel) {
                cost += turnCost
                costed += 1
            }
        }
        return costed > 0 ? (cost, costed) : nil
    }

    /// "$5.00" → 5.0. Tolerates whitespace and a bare number; nil for
    /// anything else (never guess a price).
    nonisolated static func parsePrice(_ display: String?) -> Double? {
        guard let display else { return nil }
        let cleaned = display
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    /// Case normalization only. NOTE: the shim payload is decoded with
    /// `.convertFromSnakeCase`, which also rewrites dictionary keys — model
    /// ids containing `_` would arrive mangled. None do today (`/`, `.`, `-`,
    /// `:` only); if one appears, its pricing simply won't match (estimate
    /// shows nothing rather than something wrong).
    nonisolated static func normalize(_ modelID: String) -> String {
        modelID.lowercased()
    }

    /// Last path component across both separators:
    /// "anthropic/claude-opus-4.8" → "claude-opus-4.8",
    /// "deepseek:deepseek-v4-pro" → "deepseek-v4-pro".
    nonisolated static func bareModelName(_ modelID: String) -> String {
        modelID
            .split(separator: "/").last.map(String.init)?
            .split(separator: ":").last.map(String.init) ?? modelID
    }
}

// MARK: - Receipt formatting

/// Formatting for the compact bubble-footer receipt and the status card.
/// Pure + `nonisolated` so it's unit-testable off the main actor.
enum TurnReceiptFormat {
    /// Compact token count: 356 → "356", 1_204 → "1.2K", 2_400_000 → "2.4M".
    static func tokenLabel(_ count: Int) -> String {
        switch count {
        case ..<1_000:
            return "\(count)"
        case ..<1_000_000:
            return trimmedOneDecimal(Double(count) / 1_000) + "K"
        default:
            return trimmedOneDecimal(Double(count) / 1_000_000) + "M"
        }
    }

    /// Full token count with separators: 1204 → "1,204".
    static func fullTokenLabel(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }

    /// 8.4 → "8.4S", 42.7 → "43S", 96 → "1M 36S".
    static func durationLabel(_ seconds: TimeInterval) -> String {
        guard seconds >= 0 else { return "—" }
        if seconds < 10 { return trimmedOneDecimal(seconds) + "S" }
        if seconds < 60 { return "\(Int(seconds.rounded()))S" }
        let whole = Int(seconds.rounded())
        return "\(whole / 60)M \(whole % 60)S"
    }

    /// Dollar estimate, always prefixed "~" by callers' copy. Two decimals
    /// from a cent up; four below; a floor for dust so it never shows $0.0000.
    static func costLabel(_ cost: Double) -> String {
        guard cost >= 0 else { return "—" }
        if cost >= 0.01 { return String(format: "$%.2f", cost) }
        if cost >= 0.0001 { return String(format: "$%.4f", cost) }
        return cost > 0 ? "<$0.0001" : "$0.00"
    }

    /// The one-line bubble footer: "IN 1.2K · OUT 356 · 8.4S · ~$0.0042".
    /// Cost and duration appear only when real (no placeholders in a receipt).
    static func receiptLine(usage: TokenUsage, duration: TimeInterval?, cost: Double?) -> String {
        var parts = [
            "IN \(tokenLabel(usage.promptTokens))",
            "OUT \(tokenLabel(usage.completionTokens))",
        ]
        if let duration { parts.append(durationLabel(duration)) }
        if let cost { parts.append("~\(costLabel(cost))") }
        return parts.joined(separator: " · ")
    }

    private static func trimmedOneDecimal(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}

// MARK: - Session cost & usage surface (#122)
//
// Session-level `input_tokens` etc. are CUMULATIVE billing figures — each turn
// re-sends the whole history, so they over-read superlinearly against context
// occupancy (a 10-message session measured 90% of a 128k window). The #25
// probe banned them as a context meter for exactly that reason and pointed at
// this: they are the right shape for a session-COST surface. The wire serves
// them per session on `GET /api/sessions` (list) and `GET /api/sessions/{id}`
// (detail); this is the decode + the honest display readout.

/// Cumulative billing + usage for one Hermes session, from the Sessions
/// LIST/DETAIL endpoints (#122).
///
/// Every field is optional and tolerantly decoded. The #25 probe (2026-07-16)
/// observed only the token/api-count keys on the wire; the cost keys arrived
/// later, and an old or sparse session omits some or all of them. Absent or
/// malformed → nil, never a throw and never a wrong number (the #58
/// tolerant-decode posture). These are a spend surface, NEVER a context meter.
struct SessionUsage: Hashable, Sendable {
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var cacheReadTokens: Int? = nil
    var cacheWriteTokens: Int? = nil
    var reasoningTokens: Int? = nil
    var apiCallCount: Int? = nil
    var toolCallCount: Int? = nil
    var estimatedCostUSD: Double? = nil
    var actualCostUSD: Double? = nil

    /// True when no field carries a value — the caller stores nothing (the
    /// honest-absence rule: an all-absent usage must not render a row of zeros).
    var isEmpty: Bool {
        inputTokens == nil && outputTokens == nil && cacheReadTokens == nil
            && cacheWriteTokens == nil && reasoningTokens == nil
            && apiCallCount == nil && toolCallCount == nil
            && estimatedCostUSD == nil && actualCostUSD == nil
    }
}

extension SessionUsage {
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case reasoningTokens = "reasoning_tokens"
        case apiCallCount = "api_call_count"
        case toolCallCount = "tool_call_count"
        case estimatedCostUSD = "estimated_cost_usd"
        case actualCostUSD = "actual_cost_usd"
    }

    /// Tolerantly reads the flat usage keys that ride alongside a session
    /// LIST/DETAIL row. Returns nil when NONE are present so callers store
    /// nothing. A single malformed field degrades to nil for that field only;
    /// it never throws (mirrors the `StoredMessage.toolCalls` posture in
    /// `SessionsHermesClient`).
    static func decodeIfPresent(from decoder: Decoder) -> SessionUsage? {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return nil }
        func int(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
        func money(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
        let usage = SessionUsage(
            inputTokens: int(.inputTokens),
            outputTokens: int(.outputTokens),
            cacheReadTokens: int(.cacheReadTokens),
            cacheWriteTokens: int(.cacheWriteTokens),
            reasoningTokens: int(.reasoningTokens),
            apiCallCount: int(.apiCallCount),
            toolCallCount: int(.toolCallCount),
            estimatedCostUSD: money(.estimatedCostUSD),
            actualCostUSD: money(.actualCostUSD)
        )
        return usage.isEmpty ? nil : usage
    }
}

/// The compact, honest cost/usage readout for a single session's detail row
/// (#122). Pure so it's fully unit-tested. Returns nil when there is nothing
/// honest to show — an absent or all-zero usage renders NO row (never
/// "$0.00"/"0" for the unknown; the #25 honest-absence rule, which matters even
/// more for money than for context).
enum SessionCostReadout {
    struct Display: Equatable {
        /// The cost figure WITHOUT the estimate marker: "$1.24", "<$0.01".
        /// Nil when no meaningful (> 0) cost is known.
        let costText: String?
        /// True when `costText` came from `estimatedCostUSD` (→ "~" prefix).
        let costIsEstimated: Bool
        /// Cumulative input tokens, abbreviated ("66.4k"); nil when absent/0.
        let inputText: String?
        /// Cumulative output tokens, abbreviated; nil when absent/0.
        let outputText: String?
        /// API call count as a plain integer string; nil when absent/0.
        let apiCallsText: String?

        /// The single monospace line the row renders, segments joined by
        /// " · ", e.g. "~$0.01 · IN 66.4k · OUT 1.2k · 5 CALLS". MonoLabel
        /// restyles to uppercase for the HUD; the lowercase unit here is the
        /// canonical (unit-tested) format.
        var line: String {
            var parts: [String] = []
            if let costText {
                parts.append((costIsEstimated ? "~" : "") + costText)
            }
            if let inputText { parts.append("IN \(inputText)") }
            if let outputText { parts.append("OUT \(outputText)") }
            if let apiCallsText { parts.append("\(apiCallsText) CALLS") }
            return parts.joined(separator: " · ")
        }
    }

    /// The row's display, or nil to hide it entirely (no honest data).
    static func display(for usage: SessionUsage?) -> Display? {
        guard let usage else { return nil }
        let (costText, estimated) = cost(for: usage)
        let inputText = positiveTokenText(usage.inputTokens)
        let outputText = positiveTokenText(usage.outputTokens)
        let apiCallsText = positiveCountText(usage.apiCallCount)
        guard costText != nil || inputText != nil || outputText != nil || apiCallsText != nil else {
            return nil
        }
        return Display(
            costText: costText,
            costIsEstimated: estimated,
            inputText: inputText,
            outputText: outputText,
            apiCallsText: apiCallsText
        )
    }

    /// Prefer a real actual cost; fall back to the estimate (marked `~`). A
    /// cost of 0 or negative is treated as "not meaningfully known" and
    /// omitted rather than rendered as "$0.00" — the honest-absence rule for
    /// money. Falling through a zero `actualCostUSD` to a positive estimate is
    /// deliberate: a literal 0 there reads as "not computed", not "free".
    static func cost(for usage: SessionUsage) -> (text: String?, estimated: Bool) {
        if let actual = usage.actualCostUSD, actual > 0 {
            return (costLabel(actual), false)
        }
        if let estimate = usage.estimatedCostUSD, estimate > 0 {
            return (costLabel(estimate), true)
        }
        return (nil, false)
    }

    /// "$1.24" at a cent and up; "<$0.01" for a real sub-cent cost. Callers
    /// prepend "~" for estimates. Assumes value > 0 (`cost(for:)` filters 0).
    static func costLabel(_ value: Double) -> String {
        value >= 0.01 ? String(format: "$%.2f", value) : "<$0.01"
    }

    /// Abbreviated token count, LOWERCASE unit per the dispatch: 356 → "356",
    /// 66_400 → "66.4k", 2_400_000 → "2.4m". Nil for absent or non-positive.
    static func positiveTokenText(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        switch count {
        case ..<1_000:
            return "\(count)"
        case ..<1_000_000:
            return trimmedOneDecimal(Double(count) / 1_000) + "k"
        default:
            return trimmedOneDecimal(Double(count) / 1_000_000) + "m"
        }
    }

    /// A plain positive integer as a string; nil for absent or non-positive.
    static func positiveCountText(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return "\(count)"
    }

    private static func trimmedOneDecimal(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}
