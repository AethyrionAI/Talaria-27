import Foundation
import Testing
@testable import Talaria

/// #30 — PCC tier routing through the #27 router: picker gating, per-message
/// usability checks, the honest degradation notice, and tier hand-off to the
/// local backend. The PrivateCloudComputeLanguageModel calls themselves need
/// the entitlement + iOS 27 hardware and are device-verified behind Xcode's
/// "Simulate Apple Foundation Models Availability" states.
@MainActor
struct PrivateCloudRoutingTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "PrivateCloudRoutingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeRouter(
        hermesConfigured: Bool,
        pccSelectable: Bool,
        pccUsable: Bool,
        hermes: ChatBackendRouterTests.StubBackend,
        local: ChatBackendRouterTests.StubBackend
    ) -> ChatBackendRouter {
        let router = ChatBackendRouter(
            hermes: hermes,
            local: local,
            isHermesConfigured: { hermesConfigured },
            hasHermesHost: { hermesConfigured },
            defaults: makeDefaults()
        )
        router.isPrivateCloudSelectable = { pccSelectable }
        router.isPrivateCloudUsable = { pccUsable }
        return router
    }

    // MARK: Picker gating

    @Test func pickerShowsPrivateCloudOnlyWhenActuallyAvailable() {
        let hermes = ChatBackendRouterTests.StubBackend(replyContent: "h")
        let local = ChatBackendRouterTests.StubBackend(replyContent: "l")

        let gated = makeRouter(hermesConfigured: true, pccSelectable: false, pccUsable: false,
                               hermes: hermes, local: local)
        #expect(!gated.selectableBrains.contains(.privateCloud))

        let live = makeRouter(hermesConfigured: true, pccSelectable: true, pccUsable: true,
                              hermes: hermes, local: local)
        #expect(live.selectableBrains.contains(.privateCloud))
    }

    @Test func standaloneDeviceGetsPickerOncePCCExists() {
        // Never-paired + no PCC = one brain, no picker (unchanged #27 rule).
        // Never-paired + PCC live = two local tiers — the picker appears
        // with On-Device / Private Cloud β and no Hermes entry.
        let hermes = ChatBackendRouterTests.StubBackend(replyContent: "h")
        let local = ChatBackendRouterTests.StubBackend(replyContent: "l")

        let bare = makeRouter(hermesConfigured: false, pccSelectable: false, pccUsable: false,
                              hermes: hermes, local: local)
        #expect(!bare.showsBrainPicker)

        let withPCC = makeRouter(hermesConfigured: false, pccSelectable: true, pccUsable: true,
                                 hermes: hermes, local: local)
        #expect(withPCC.showsBrainPicker)
        #expect(withPCC.selectableBrains == [.onDevice, .privateCloud])
    }

    // MARK: Routing + degradation

    @Test func usablePCCPinRoutesPrivateCloudEvenWithoutHermes() {
        let hermes = ChatBackendRouterTests.StubBackend(replyContent: "h")
        let local = ChatBackendRouterTests.StubBackend(replyContent: "l")
        let router = makeRouter(hermesConfigured: false, pccSelectable: true, pccUsable: true,
                                hermes: hermes, local: local)
        router.setPreferredBrain(.privateCloud, forConversation: nil)
        #expect(router.resolvedBrainForNextTurn() == .privateCloud)
        #expect(router.privateCloudFallbackNotice == nil)
    }

    @Test func unusablePCCPinDegradesToOnDeviceWithHonestNotice() {
        let hermes = ChatBackendRouterTests.StubBackend(replyContent: "h")
        let local = ChatBackendRouterTests.StubBackend(replyContent: "l")
        let router = makeRouter(hermesConfigured: true, pccSelectable: true, pccUsable: false,
                                hermes: hermes, local: local)
        router.setPreferredBrain(.privateCloud, forConversation: nil)

        // Per the #30 decision the fallback floor is on-device — never a
        // silent reroute to Hermes.
        #expect(router.resolvedBrainForNextTurn() == .onDevice)
        #expect(router.privateCloudFallbackNotice != nil)

        // Changing the preference clears the stale notice.
        router.setPreferredBrain(.onDevice, forConversation: nil)
        #expect(router.privateCloudFallbackNotice == nil)
    }

    @Test func recoveredPCCClearsTheNoticeOnNextResolution() {
        let hermes = ChatBackendRouterTests.StubBackend(replyContent: "h")
        let local = ChatBackendRouterTests.StubBackend(replyContent: "l")
        // A box rather than a captured `var`: `isPrivateCloudUsable` is an
        // escaping @Sendable closure, so mutating a captured local after the
        // capture is a strict-concurrency warning (and a Swift 6 error). Same
        // `MutableBox` shape the rest of the suite uses. The flip below is the
        // point of the test — it must stay observable through the closure.
        let usable = MutableBox(false)
        let router = ChatBackendRouter(
            hermes: hermes,
            local: local,
            isHermesConfigured: { true },
            hasHermesHost: { true },
            defaults: makeDefaults()
        )
        router.isPrivateCloudSelectable = { true }
        router.isPrivateCloudUsable = { usable.value }
        router.setPreferredBrain(.privateCloud, forConversation: nil)

        #expect(router.resolvedBrainForNextTurn() == .onDevice)
        #expect(router.privateCloudFallbackNotice != nil)

        usable.value = true
        #expect(router.resolvedBrainForNextTurn() == .privateCloud)
        #expect(router.privateCloudFallbackNotice == nil)
    }

    // MARK: Tier hand-off

    @Test func locallyRoutedStreamsCarryTheirTierToTheBackend() async {
        let hermes = ChatBackendRouterTests.StubBackend(replyContent: "h")
        let local = ChatBackendRouterTests.StubBackend(replyContent: "l")
        let router = makeRouter(hermesConfigured: false, pccSelectable: true, pccUsable: true,
                                hermes: hermes, local: local)
        var appliedTiers: [ChatBackendRouter.Brain] = []
        router.applyLocalTier = { appliedTiers.append($0) }

        for await _ in router.sendStreaming(message: "one", attachments: [], clientMessageID: UUID()) {}
        router.setPreferredBrain(.privateCloud, forConversation: nil)
        for await _ in router.sendStreaming(message: "two", attachments: [], clientMessageID: UUID()) {}

        #expect(appliedTiers == [.onDevice, .privateCloud])
        // The finished PCC message carries the beta-labeled brain tag.
        #expect(ChatBackendRouter.transcriptTag(forMessageBrain: ChatBackendRouter.Brain.privateCloud.rawValue) == "PCC β")
    }

    /// Reference cell for state a test flips *after* handing a closure to the
    /// router. Same shape as the copies in `AppStoresTests` and
    /// `SensorOutboxChurnTests`; `@unchecked` is honest here because every test
    /// using it is synchronous and single-threaded.
    private final class MutableBox<T>: @unchecked Sendable {
        var value: T

        init(_ value: T) {
            self.value = value
        }
    }
}
