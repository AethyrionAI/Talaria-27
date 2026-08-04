import Foundation

// MARK: - Gateway model catalog (#223 Lane 5)
//
// DTOs for `GET /api/model/options` on the v0.20.0 gateway — the picker's
// data source after the models shim retired. Decoded with a bare JSONDecoder:
// snake_case fields get explicit CodingKeys, unknown keys are ignored by
// synthesis, and per-entry decode is tolerant so one malformed provider row
// can't sink the whole catalog.

/// Top-level payload: the host's CURRENT default pair plus the provider list.
/// The current pair backs the picker's HOST DEFAULT row.
struct GatewayModelCatalog: Decodable, Sendable {
    let provider: String?
    let model: String?
    let providers: [GatewayProviderEntry]
}

struct GatewayProviderEntry: Decodable, Sendable {
    let slug: String
    let name: String
    let authenticated: Bool
    /// Setup hint for unauthenticated providers (e.g. "paste FIREWORKS_API_KEY
    /// to activate") — shown on the needs-setup rows the shim used to build.
    let warning: String?
    let models: [String]
    let featuredModels: [String]?
    /// Pricing display strings keyed by model id — the same vocabulary the
    /// shim payload carried ("$8.00", "free"), consumed by ModelPricingCatalog.
    let pricing: [String: GatewayModelPricing]?

    private enum CodingKeys: String, CodingKey {
        case slug, name, authenticated, warning, models, pricing
        case featuredModels = "featured_models"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        authenticated = (try? c.decodeIfPresent(Bool.self, forKey: .authenticated)) ?? false
        warning = (try? c.decodeIfPresent(String.self, forKey: .warning)) ?? nil
        models = (try? c.decodeIfPresent([String].self, forKey: .models)) ?? []
        featuredModels = (try? c.decodeIfPresent([String].self, forKey: .featuredModels)) ?? nil
        pricing = (try? c.decodeIfPresent([String: GatewayModelPricing].self, forKey: .pricing)) ?? nil
    }
}

extension GatewayProviderEntry: Identifiable {
    var id: String { slug }
}

struct GatewayModelPricing: Decodable, Sendable {
    let input: String?
    let output: String?
    let cache: String?
    let free: Bool?
    let discountPercent: Int?

    private enum CodingKeys: String, CodingKey {
        case input, output, cache, free
        case discountPercent = "discount_percent"
    }
}

/// The per-turn `runtime` block every v0.20.0 chat response and SSE event
/// carries: which provider/model ACTUALLY served the turn, where the route
/// came from, and whether a requested lock was honored (#241 re-test,
/// 2026-08-03). Every field tolerant — an older gateway simply yields nils.
struct TurnRuntime: Decodable, Sendable, Equatable {
    let provider: String?
    let model: String?
    let routeSource: String?
    let modelLock: String?

    private enum CodingKeys: String, CodingKey {
        case provider, model
        case routeSource = "route_source"
        case modelLock = "model_lock"
    }
}

/// One picked model, persisted per backend profile (#223 Lane 5). Encoded
/// onto every chat turn as provider + model + `require_model_lock: true` —
/// NEVER a bare `model`, which the gateway echoes and silently ignores (#241).
struct ModelSelection: Equatable, Sendable {
    let provider: String
    let modelID: String
}
