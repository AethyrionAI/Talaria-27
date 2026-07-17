import Foundation

/// Outcome of a paywall action (purchase or restore). `unlocked` is the only
/// outcome that closes the paywall; everything else stays on-screen with an
/// honest state (see `PaywallPresentation.shouldAutoDismiss`).
enum EntitlementActionOutcome: Equatable, Sendable {
    /// The Connected tier is now entitled.
    case unlocked
    /// The action completed but found no entitlement (e.g. restore with
    /// nothing to restore).
    case notUnlocked
    /// The user backed out of the App Store flow.
    case cancelled
    /// Deferred by the App Store (Ask to Buy / pending approval).
    case pending
    case failed(String)
}

/// The Connected-tier entitlement source (#127). One live implementation
/// (StoreKit 2) and one mock; consumers never touch StoreKit directly —
/// gated entry points ask `ConnectGate` with this service's published state.
@MainActor
protocol EntitlementServiceProtocol: AnyObject {
    /// Current knowledge of the Connected entitlement. Starts `.unknown`
    /// until the first `Transaction.currentEntitlements` scan resolves.
    var entitlementState: ConnectEntitlementState { get }

    /// Convenience: `entitlementState == .entitled`.
    var isConnectedTierUnlocked: Bool { get }

    /// Last DEFINITIVE answer, persisted across launches — the fail-open
    /// input for `ConnectGate` while the live state is `.unknown`.
    var cachedEntitlement: Bool? { get }

    /// The App Store's localized price string for the Connected product;
    /// nil until the product has loaded (the paywall shows "—").
    var connectedProductDisplayPrice: String? { get }

    /// Honest surface for the most recent StoreKit failure, if any.
    var lastErrorMessage: String? { get }

    /// True while a purchase or restore is in flight.
    var isActionInFlight: Bool { get }

    /// Begin the `Transaction.updates` listener and run the launch scan.
    /// Idempotent.
    func start()

    /// Re-scan `Transaction.currentEntitlements` and republish state.
    func refreshEntitlements() async

    /// Fetch the Connected product (for `displayPrice`) if not yet loaded.
    func loadProductIfNeeded() async

    func purchaseConnectedTier() async -> EntitlementActionOutcome

    /// StoreKit 2 restore: `AppStore.sync()` then a re-scan.
    func restorePurchases() async -> EntitlementActionOutcome
}
