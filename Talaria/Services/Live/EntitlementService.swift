import Foundation
import StoreKit
import os

private let entitlementLog = Logger(subsystem: "org.aethyrion.talaria", category: "Entitlements")

// MARK: - Connected-tier entitlement service (#127, StoreKit 2)
//
// Publishes `isConnectedTierUnlocked` from `Transaction.currentEntitlements`
// (launch scan) plus a `Transaction.updates` listener, with the last
// definitive answer cached in UserDefaults so the connect gate can fail open
// for paid users while StoreKit is unreachable. Both product-type paths
// (non-consumable / annual subscription) ride
// `MonetizationConfiguration.productKind` — flipping that constant is the
// entire pricing migration. Dormant by default: the service runs (correct
// StoreKit hygiene — unfinished transactions must always be observed), but
// nothing consults its state until `MonetizationConfiguration.isEnabled` or
// the DEBUG gate toggle activates `ConnectGate`.
@MainActor
@Observable
final class EntitlementService: EntitlementServiceProtocol {
    static let cachedEntitlementDefaultsKey = "org.aethyrion.talaria27.monetization.lastKnownEntitlement"

    private(set) var entitlementState: ConnectEntitlementState = .unknown
    private(set) var cachedEntitlement: Bool?
    private(set) var connectedProductDisplayPrice: String?
    private(set) var lastErrorMessage: String?
    private(set) var isActionInFlight = false

    var isConnectedTierUnlocked: Bool {
        entitlementState == .entitled
    }

    private let defaults: UserDefaults
    private var connectedProduct: Product?
    private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.cachedEntitlementDefaultsKey) != nil {
            cachedEntitlement = defaults.bool(forKey: Self.cachedEntitlementDefaultsKey)
        }
    }

    // MARK: Lifecycle

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handleTransactionUpdate(update)
            }
        }
        Task { [weak self] in
            await self?.refreshEntitlements()
        }
    }

    private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        // Finish verified transactions regardless of product match — an
        // unfinished transaction re-delivers forever. Unverified ones are
        // left unfinished for StoreKit to retry.
        if case .verified(let transaction) = update {
            await transaction.finish()
        }
        await refreshEntitlements()
    }

    // MARK: Entitlement scan

    func refreshEntitlements() async {
        // `currentEntitlements` reads the device's transaction cache, so the
        // scan is definitive by construction; `.unknown` survives only as
        // the pre-first-scan state (and in future service variants that can
        // fail). The pinned transient-failure rules live in `ConnectGate`.
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if EntitlementScan.transactionGrantsConnected(
                productID: transaction.productID,
                kind: MonetizationConfiguration.productKind,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate,
                now: Date()
            ) {
                owned = true
            }
        }
        entitlementState = owned ? .entitled : .notEntitled
        persistCache(for: entitlementState)
        entitlementLog.notice("entitlement scan: connected tier \(owned ? "ENTITLED" : "not entitled", privacy: .public)")
    }

    private func persistCache(for state: ConnectEntitlementState) {
        let updated = EntitlementScan.updatedCache(state: state, previous: cachedEntitlement)
        cachedEntitlement = updated
        if let updated {
            defaults.set(updated, forKey: Self.cachedEntitlementDefaultsKey)
        }
    }

    // MARK: Product

    func loadProductIfNeeded() async {
        if connectedProduct != nil { return }
        do {
            let products = try await Product.products(for: [MonetizationConfiguration.connectedProductID])
            if let product = products.first {
                connectedProduct = product
                connectedProductDisplayPrice = product.displayPrice
                lastErrorMessage = nil
            } else {
                // Expected until the product exists in App Store Connect.
                lastErrorMessage = "Product not available — App Store Connect setup pending."
            }
        } catch {
            lastErrorMessage = "Couldn't reach the App Store: \(error.localizedDescription)"
        }
    }

    // MARK: Purchase / restore

    func purchaseConnectedTier() async -> EntitlementActionOutcome {
        guard !isActionInFlight else { return .failed("Another App Store action is in progress.") }
        isActionInFlight = true
        defer { isActionInFlight = false }

        await loadProductIfNeeded()
        guard let product = connectedProduct else {
            return .failed(lastErrorMessage ?? "Product not available.")
        }

        do {
            // `purchase()` is the same call for both product kinds — the
            // kind decides scan + paywall copy, not the purchase path.
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                    return isConnectedTierUnlocked ? .unlocked : .notUnlocked
                case .unverified:
                    return .failed("The App Store couldn't verify this purchase.")
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Unrecognized purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> EntitlementActionOutcome {
        guard !isActionInFlight else { return .failed("Another App Store action is in progress.") }
        isActionInFlight = true
        defer { isActionInFlight = false }

        do {
            try await AppStore.sync()
        } catch {
            // A cancelled sign-in lands here too — surface it honestly.
            return .failed(error.localizedDescription)
        }
        await refreshEntitlements()
        return isConnectedTierUnlocked ? .unlocked : .notUnlocked
    }
}
