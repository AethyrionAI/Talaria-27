import Foundation
import Testing
@testable import Talaria

/// #223 Lane 5, bar L5-B — the gateway catalog DTOs decode the REAL
/// /api/model/options payload (OJAMD, v0.20.0, captured during the #241
/// re-test), and TurnRuntime decodes the runtime blocks that ride every
/// 0.20.0 chat response and SSE event.
struct GatewayModelCatalogTests {

    private func decodeCatalog() throws -> GatewayModelCatalog {
        try JSONDecoder().decode(GatewayModelCatalog.self, from: Data(ModelOptionsFixture.json.utf8))
    }

    @Test
    func realPayloadDecodesWithHostCurrentPairAndAllProviders() throws {
        let catalog = try decodeCatalog()
        // Top-level current pair — the HOST DEFAULT row's data source.
        #expect(catalog.provider == "kimi-coding")
        #expect(catalog.model == "kimi-k3")
        #expect(catalog.providers.count == 42)
        #expect(catalog.providers.filter(\.authenticated).count == 13)
    }

    @Test
    func authenticatedProviderCarriesModelsFeaturedAndNoWarning() throws {
        let catalog = try decodeCatalog()
        let nous = try #require(catalog.providers.first { $0.slug == "nous" })
        #expect(nous.name == "Nous Portal")
        #expect(nous.authenticated)
        #expect(nous.models.count == 35)
        #expect(nous.warning == nil)
        #expect(nous.featuredModels?.count == 31)
    }

    @Test
    func unauthenticatedProviderCarriesSetupWarningAndNoModels() throws {
        let catalog = try decodeCatalog()
        let fireworks = try #require(catalog.providers.first { $0.slug == "fireworks" })
        #expect(!fireworks.authenticated)
        #expect(fireworks.warning == "paste FIREWORKS_API_KEY to activate")
        #expect(fireworks.models.isEmpty)
    }

    @Test
    func pricingRowsDecodePaidDiscountedAndFreeShapes() throws {
        let catalog = try decodeCatalog()
        let nous = try #require(catalog.providers.first { $0.slug == "nous" })
        let pricing = try #require(nous.pricing)
        let flash = try #require(pricing["deepseek/deepseek-v4-flash-0731"])
        #expect(flash.input == "$0.01")
        #expect(flash.output == "$0.02")
        #expect(flash.free == false)
        #expect(flash.discountPercent == 90)
        let freeRow = try #require(pricing["tencent/hy3:free"])
        #expect(freeRow.free == true)
        #expect(freeRow.input == "free")
    }

    // MARK: - TurnRuntime (the per-turn runtime block)

    @Test
    func turnRuntimeDecodesTheProbeThreeShape() throws {
        // Verbatim shape from handoffs/241-retest-2026-08-03/241-probe3-response.txt.
        let json = #"{"provider": "nous", "model": "deepseek/deepseek-v4-flash-0731", "route_source": "raw_request", "requested": {"provider": "nous", "model": "deepseek/deepseek-v4-flash-0731"}, "model_lock": "confirmed"}"#
        let runtime = try JSONDecoder().decode(TurnRuntime.self, from: Data(json.utf8))
        #expect(runtime.provider == "nous")
        #expect(runtime.model == "deepseek/deepseek-v4-flash-0731")
        #expect(runtime.routeSource == "raw_request")
        #expect(runtime.modelLock == "confirmed")
    }

    @Test
    func turnRuntimeToleratesEmptyAndPartialBlocks() throws {
        let empty = try JSONDecoder().decode(TurnRuntime.self, from: Data("{}".utf8))
        #expect(empty.provider == nil)
        #expect(empty.model == nil)
        #expect(empty.modelLock == nil)
        let partial = try JSONDecoder().decode(TurnRuntime.self, from: Data(#"{"provider": "kimi-coding", "model": "hermes-agent"}"#.utf8))
        #expect(partial.provider == "kimi-coding")
        #expect(partial.routeSource == nil)
    }
}
