import Foundation

/// Scriptable entitlement source for tests and previews (#127). Every
/// published field is settable and every action returns a scripted outcome
/// while mutating state the way the live service would.
@MainActor
@Observable
final class MockEntitlementService: EntitlementServiceProtocol {
    var entitlementState: ConnectEntitlementState = .unknown
    var cachedEntitlement: Bool?
    var connectedProductDisplayPrice: String?
    var lastErrorMessage: String?
    var isActionInFlight = false

    var isConnectedTierUnlocked: Bool {
        entitlementState == .entitled
    }

    /// What `purchaseConnectedTier()` / `restorePurchases()` return; when
    /// `.unlocked`, the call also flips `entitlementState` to `.entitled`.
    var scriptedPurchaseOutcome: EntitlementActionOutcome = .unlocked
    var scriptedRestoreOutcome: EntitlementActionOutcome = .notUnlocked

    private(set) var startCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var loadProductCallCount = 0
    private(set) var purchaseCallCount = 0
    private(set) var restoreCallCount = 0

    func start() {
        startCallCount += 1
    }

    func refreshEntitlements() async {
        refreshCallCount += 1
        cachedEntitlement = EntitlementScan.updatedCache(state: entitlementState, previous: cachedEntitlement)
    }

    func loadProductIfNeeded() async {
        loadProductCallCount += 1
    }

    func purchaseConnectedTier() async -> EntitlementActionOutcome {
        purchaseCallCount += 1
        if scriptedPurchaseOutcome == .unlocked {
            entitlementState = .entitled
        }
        return scriptedPurchaseOutcome
    }

    func restorePurchases() async -> EntitlementActionOutcome {
        restoreCallCount += 1
        if scriptedRestoreOutcome == .unlocked {
            entitlementState = .entitled
        }
        return scriptedRestoreOutcome
    }
}
