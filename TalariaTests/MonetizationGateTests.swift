import Foundation
import Testing
@testable import Talaria

/// #127 — the monetization scaffold's decision cores. The gate matrix
/// (entitled / not / cached / transient-failure × existing-pairing /
/// new-connect) pins the fail-open rule: an existing pairing NEVER hits the
/// paywall, and a paid user's cached entitlement carries new connects
/// through a StoreKit outage. StoreKit itself (sandbox purchase/restore) is
/// device-land — see the OPEN_ITEMS #127 checklist.
struct MonetizationGateTests {

    private static let allStates: [ConnectEntitlementState] = [.unknown, .entitled, .notEntitled]
    private static let allCaches: [Bool?] = [nil, true, false]
    private static let allAttempts: [ConnectAttempt] = [.newConnect, .existingPairing]

    // MARK: - Dormancy (the scaffold must land inert)

    @Test func scaffoldShipsDormant() {
        // The whole gate is inert until Owen flips this at launch. If this
        // test fails, the flip is happening — delete the test alongside a
        // deliberate launch commit, never as a side effect.
        #expect(MonetizationConfiguration.isEnabled == false)
    }

    @Test func productIDIsTheSingleAgreedPlaceholder() {
        // Must match the App Store Connect product exactly (PR setup steps).
        #expect(MonetizationConfiguration.connectedProductID == "org.aethyrion.talaria27.connected")
    }

    @Test func dormantGateAllowsEveryCombination() {
        for attempt in Self.allAttempts {
            for state in Self.allStates {
                for cache in Self.allCaches {
                    #expect(ConnectGate.verdict(
                        monetizationActive: false,
                        attempt: attempt,
                        state: state,
                        cachedEntitlement: cache
                    ) == .allow)
                }
            }
        }
    }

    // MARK: - The fail-open rule (pinned)

    @Test func existingPairingAlwaysPassesRegardlessOfEntitlement() {
        // CRITICAL: a transient entitlement failure (offline, StoreKit
        // outage) — or even a definitive "not entitled" — must never sever
        // or block an already-configured host.
        for state in Self.allStates {
            for cache in Self.allCaches {
                #expect(ConnectGate.verdict(
                    monetizationActive: true,
                    attempt: .existingPairing,
                    state: state,
                    cachedEntitlement: cache
                ) == .allow)
            }
        }
    }

    // MARK: - New connects (active gate)

    @Test func newConnectEntitledAllows() {
        for cache in Self.allCaches {
            #expect(ConnectGate.verdict(
                monetizationActive: true,
                attempt: .newConnect,
                state: .entitled,
                cachedEntitlement: cache
            ) == .allow)
        }
    }

    @Test func newConnectNotEntitledShowsPaywallEvenWithStaleCache() {
        // A definitive answer beats the cache — a lapsed subscription with a
        // stale cached "paid" must not slip a new connect through.
        for cache in Self.allCaches {
            #expect(ConnectGate.verdict(
                monetizationActive: true,
                attempt: .newConnect,
                state: .notEntitled,
                cachedEntitlement: cache
            ) == .showPaywall)
        }
    }

    @Test func newConnectTransientFailureFallsBackToCache() {
        // Unknown state = the transient-failure lane. Cached-paid fails
        // open; cached-free or no cache fails closed — new connects are the
        // one act that may demand a working entitlement path.
        #expect(ConnectGate.verdict(
            monetizationActive: true, attempt: .newConnect,
            state: .unknown, cachedEntitlement: true
        ) == .allow)
        #expect(ConnectGate.verdict(
            monetizationActive: true, attempt: .newConnect,
            state: .unknown, cachedEntitlement: false
        ) == .showPaywall)
        #expect(ConnectGate.verdict(
            monetizationActive: true, attempt: .newConnect,
            state: .unknown, cachedEntitlement: nil
        ) == .showPaywall)
    }

    // MARK: - Entitlement scan (both product-kind paths, independent of the
    // config constant's current value)

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func nonConsumableGrantsUnlessRevoked() {
        #expect(EntitlementScan.transactionGrantsConnected(
            productID: MonetizationConfiguration.connectedProductID,
            kind: .nonConsumable, revocationDate: nil, expirationDate: nil, now: now
        ))
        #expect(!EntitlementScan.transactionGrantsConnected(
            productID: MonetizationConfiguration.connectedProductID,
            kind: .nonConsumable, revocationDate: now, expirationDate: nil, now: now
        ))
    }

    @Test func subscriptionGrantsWhileUnexpired() {
        #expect(EntitlementScan.transactionGrantsConnected(
            productID: MonetizationConfiguration.connectedProductID,
            kind: .annualSubscription, revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600), now: now
        ))
        // Expired and revoked both refuse.
        #expect(!EntitlementScan.transactionGrantsConnected(
            productID: MonetizationConfiguration.connectedProductID,
            kind: .annualSubscription, revocationDate: nil,
            expirationDate: now.addingTimeInterval(-3600), now: now
        ))
        #expect(!EntitlementScan.transactionGrantsConnected(
            productID: MonetizationConfiguration.connectedProductID,
            kind: .annualSubscription, revocationDate: now,
            expirationDate: now.addingTimeInterval(3600), now: now
        ))
        // currentEntitlements only surfaces active subs, so a nil expiration
        // errs toward the user keeping what they paid for.
        #expect(EntitlementScan.transactionGrantsConnected(
            productID: MonetizationConfiguration.connectedProductID,
            kind: .annualSubscription, revocationDate: nil,
            expirationDate: nil, now: now
        ))
    }

    @Test func foreignProductNeverGrants() {
        for kind in [ConnectedProductKind.nonConsumable, .annualSubscription] {
            #expect(!EntitlementScan.transactionGrantsConnected(
                productID: "org.aethyrion.talaria27.somethingelse",
                kind: kind, revocationDate: nil, expirationDate: nil, now: now
            ))
        }
    }

    // MARK: - Last-known cache

    @Test func cacheUpdatesOnlyOnDefinitiveAnswers() {
        #expect(EntitlementScan.updatedCache(state: .entitled, previous: nil) == true)
        #expect(EntitlementScan.updatedCache(state: .entitled, previous: false) == true)
        #expect(EntitlementScan.updatedCache(state: .notEntitled, previous: true) == false)
        // A transient unknown preserves knowledge — this preserved `true`
        // is exactly what carries a paid user through a StoreKit outage.
        #expect(EntitlementScan.updatedCache(state: .unknown, previous: true) == true)
        #expect(EntitlementScan.updatedCache(state: .unknown, previous: false) == false)
        #expect(EntitlementScan.updatedCache(state: .unknown, previous: nil) == nil)
    }

    // MARK: - DEBUG override combinators

    @Test func debugGateActivatesButNeverDeactivates() {
        #expect(MonetizationDebugRules.effectiveGateActive(configuredEnabled: false, debugGateEnabled: false) == false)
        #expect(MonetizationDebugRules.effectiveGateActive(configuredEnabled: false, debugGateEnabled: true) == true)
        // A launched gate can't be turned off from the Developer screen.
        #expect(MonetizationDebugRules.effectiveGateActive(configuredEnabled: true, debugGateEnabled: false) == true)
        #expect(MonetizationDebugRules.effectiveGateActive(configuredEnabled: true, debugGateEnabled: true) == true)
    }

    @Test func debugOverrideForcesOrPassesThrough() {
        for real in Self.allStates {
            #expect(MonetizationDebugRules.effectiveEntitlementState(real: real, override: .system) == real)
            #expect(MonetizationDebugRules.effectiveEntitlementState(real: real, override: .unlocked) == .entitled)
            #expect(MonetizationDebugRules.effectiveEntitlementState(real: real, override: .locked) == .notEntitled)
        }
    }

    // MARK: - Uplink key-save classification (#127 gate point)

    @Test @MainActor func firstKeySaveIsANewConnect() {
        #expect(UplinkSettingsScreen.keySaveAttempt(existingKey: "") == .newConnect)
        #expect(UplinkSettingsScreen.keySaveAttempt(existingKey: "   ") == .newConnect)
        // Rotating an existing key is maintenance, never gated.
        #expect(UplinkSettingsScreen.keySaveAttempt(existingKey: "abc123") == .existingPairing)
    }
}

/// #127 — paywall presentation logic. Real data only, no dark patterns.
struct PaywallPresentationTests {

    @Test func priceIsNeverHardcoded() {
        // Honest "—" until Product.displayPrice arrives; then the App
        // Store's localized string verbatim.
        #expect(PaywallPresentation.priceLabel(displayPrice: nil) == "—")
        #expect(PaywallPresentation.priceLabel(displayPrice: "$4.99") == "$4.99")
    }

    @Test func purchaseRequiresALoadedProductAndNoActionInFlight() {
        #expect(PaywallPresentation.purchaseEnabled(productLoaded: true, actionInFlight: false))
        #expect(!PaywallPresentation.purchaseEnabled(productLoaded: false, actionInFlight: false))
        #expect(!PaywallPresentation.purchaseEnabled(productLoaded: true, actionInFlight: true))
        #expect(!PaywallPresentation.purchaseEnabled(productLoaded: false, actionInFlight: true))
    }

    @Test func restoreOnlyBlocksWhileActionInFlight() {
        #expect(PaywallPresentation.restoreEnabled(actionInFlight: false))
        #expect(!PaywallPresentation.restoreEnabled(actionInFlight: true))
    }

    @Test func paywallIsAlwaysDismissible() {
        // Pinned: no dark patterns — dismissible even mid-purchase
        // (StoreKit finishes the transaction regardless).
        #expect(PaywallPresentation.dismissEnabled(actionInFlight: false))
        #expect(PaywallPresentation.dismissEnabled(actionInFlight: true))
    }

    @Test func onlyAnActualUnlockAutoDismisses() {
        #expect(PaywallPresentation.shouldAutoDismiss(after: .unlocked))
        #expect(!PaywallPresentation.shouldAutoDismiss(after: .notUnlocked))
        #expect(!PaywallPresentation.shouldAutoDismiss(after: .cancelled))
        #expect(!PaywallPresentation.shouldAutoDismiss(after: .pending))
        #expect(!PaywallPresentation.shouldAutoDismiss(after: .failed("boom")))
    }

    @Test @MainActor func mockServiceUnlockFlowMatchesLiveSemantics() async {
        // The mock is the paywall's test double — its unlock path must move
        // state the way the live service does, or paywall tests lie.
        let mock = MockEntitlementService()
        #expect(!mock.isConnectedTierUnlocked)
        mock.scriptedPurchaseOutcome = .unlocked
        let outcome = await mock.purchaseConnectedTier()
        #expect(outcome == .unlocked)
        #expect(mock.isConnectedTierUnlocked)
        await mock.refreshEntitlements()
        #expect(mock.cachedEntitlement == true)
    }
}
