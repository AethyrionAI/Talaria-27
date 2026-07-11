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
