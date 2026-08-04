import Foundation
import Testing
@testable import Talaria

/// #223 Lane 5, bar L5-C — the rewritten picker model: gateway-sourced list,
/// pick persisted per profile with NO network on the apply path, HOST DEFAULT
/// row semantics, and decode tolerance on the new BackendProfile fields.
@MainActor
struct ModelsPickerModelTests {

    /// Scripted seams: a counting catalog fetch + an in-memory selection slot.
    private final class Harness {
        var fetchCount = 0
        var storedSelection: ModelSelection?
        var writeCount = 0

        @MainActor
        func makeModel(catalogJSON: String = ModelOptionsFixture.json) -> ModelsSettingsModel {
            ModelsSettingsModel(
                fetchCatalog: { [weak self] in
                    self?.fetchCount += 1
                    return try JSONDecoder().decode(GatewayModelCatalog.self, from: Data(catalogJSON.utf8))
                },
                readSelection: { [weak self] in self?.storedSelection },
                writeSelection: { [weak self] selection in
                    self?.storedSelection = selection
                    self?.writeCount += 1
                }
            )
        }
    }

    @Test
    func loadPopulatesProvidersAndHostDefaultPair() async {
        let harness = Harness()
        let model = harness.makeModel()
        await model.load()
        #expect(model.errorMessage == nil)
        #expect(model.authenticatedProviders.count == 13)
        #expect(model.hostDefaultProvider == "kimi-coding")
        #expect(model.hostDefaultModel == "kimi-k3")
        // Current provider sorts first.
        #expect(model.authenticatedProviders.first?.slug == "kimi-coding")
    }

    @Test
    func applyPersistsThePickAndTouchesNoNetwork() async {
        let harness = Harness()
        let model = harness.makeModel()
        await model.load()
        let fetchesAfterLoad = harness.fetchCount

        model.apply(providerSlug: "nous", modelID: "deepseek/deepseek-v4-flash-0731")

        #expect(harness.storedSelection == ModelSelection(provider: "nous", modelID: "deepseek/deepseek-v4-flash-0731"))
        #expect(harness.fetchCount == fetchesAfterLoad)   // NO network on apply
        #expect(model.applyingModelID == nil)             // clears synchronously
        #expect(model.isActive(providerSlug: "nous", modelID: "deepseek/deepseek-v4-flash-0731"))
        #expect(!model.hostDefaultIsActive)
    }

    @Test
    func hostDefaultRowClearsThePick() async {
        let harness = Harness()
        harness.storedSelection = ModelSelection(provider: "nous", modelID: "deepseek/deepseek-v4-flash-0731")
        let model = harness.makeModel()
        await model.load()

        model.applyHostDefault()

        #expect(harness.storedSelection == nil)
        #expect(model.hostDefaultIsActive)
        // With no pick, the host's current pair reads as active.
        #expect(model.isActive(providerSlug: "kimi-coding", modelID: "kimi-k3"))
        #expect(!model.isActive(providerSlug: "nous", modelID: "deepseek/deepseek-v4-flash-0731"))
    }

    @Test
    func pickWinsOverHostCurrentForTheCheckmark() async {
        let harness = Harness()
        harness.storedSelection = ModelSelection(provider: "nous", modelID: "deepseek/deepseek-v4-pro")
        let model = harness.makeModel()
        await model.load()

        #expect(model.isActive(providerSlug: "nous", modelID: "deepseek/deepseek-v4-pro"))
        // The host's own current pair is NOT active while a pick exists.
        #expect(!model.isActive(providerSlug: "kimi-coding", modelID: "kimi-k3"))
    }

    @Test
    func loadFailureSurfacesTheErrorPanelMessage() async {
        let harness = Harness()
        let model = harness.makeModel(catalogJSON: "not json")
        await model.load()
        #expect(model.errorMessage != nil)
        #expect(model.catalog == nil)
    }

    // MARK: - BackendProfile decode tolerance (the new pick fields)

    @Test
    func backendProfileWithoutPickFieldsDecodesAndRoundTrips() throws {
        // Old-format JSON: no selectedModelProvider/selectedModelID keys.
        let legacy = #"{"id":"11111111-2222-3333-4444-555555555555","name":"OJAMD","gatewayBaseURL":"http://100.110.102.59:8642","relayBaseURL":"http://100.110.102.59:8000/v1"}"#
        let profile = try JSONDecoder().decode(BackendProfile.self, from: Data(legacy.utf8))
        #expect(profile.selectedModelProvider == nil)
        #expect(profile.selectedModelID == nil)

        var picked = profile
        picked.selectedModelProvider = "nous"
        picked.selectedModelID = "deepseek/deepseek-v4-flash-0731"
        let data = try JSONEncoder().encode(picked)
        let decoded = try JSONDecoder().decode(BackendProfile.self, from: data)
        #expect(decoded.selectedModelProvider == "nous")
        #expect(decoded.selectedModelID == "deepseek/deepseek-v4-flash-0731")
    }
}
