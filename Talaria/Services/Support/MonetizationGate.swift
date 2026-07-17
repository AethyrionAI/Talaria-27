import Foundation

// MARK: - Monetization scaffold (#127) — configuration + the connect gate
//
// Freemium (Owen, 2026-07-17): the FREE tier is the complete standalone app
// (on-device model, native voice, OCR, widgets, health tiles); the PAID
// "Connected" tier is the BYOK/connect-your-own-host feature set (pairing,
// backend profiles, sensor uplink, agent inbox, realtime voice). Users pay
// for connectivity, not compute — they bring their own host and keys.
//
// The whole gate ships DORMANT: `MonetizationConfiguration.isEnabled` is
// false until Owen flips it at launch, so nothing shipped-free today changes
// behavior. Gating wraps CONNECT ENTRY POINTS only (the pairing flow, the
// add-profile action, the first-key uplink save) — never a live connection:
// an existing pairing keeps working even when entitlement checks fail.

/// Which App Store product backs the Connected tier. Both code paths are
/// implemented everywhere this is consulted (entitlement scan, paywall copy)
/// so the pricing decision stays open until App Store Connect setup.
enum ConnectedProductKind: String, Sendable {
    case nonConsumable
    case annualSubscription
}

enum MonetizationConfiguration {
    /// The dormancy flag. False = the gate is inert everywhere and the app
    /// behaves exactly as before this scaffold landed. Flipped to true (one
    /// line) at launch, after the App Store Connect product exists.
    static let isEnabled = false

    /// Single source for the product id — placeholder until the product is
    /// created in App Store Connect (must match exactly).
    static let connectedProductID = "org.aethyrion.talaria27.connected"

    /// The product type the paywall and entitlement scan assume. Flipping
    /// this constant is the entire migration between the two pricing shapes.
    static let productKind: ConnectedProductKind = .nonConsumable
}

// MARK: - Entitlement state

/// What we currently know about the Connected entitlement. `unknown` is the
/// honest transient state — before the first StoreKit scan resolves, or when
/// a check failed — and is exactly where the cached last-known answer (and
/// the fail-open rule for existing pairings) matters.
enum ConnectEntitlementState: Equatable, Sendable {
    case unknown
    case entitled
    case notEntitled
}

/// What the user is trying to do at a gated entry point. The distinction IS
/// the fail-open rule: only the act of connecting something NEW is ever
/// gated; anything already configured keeps working unconditionally.
enum ConnectAttempt: Equatable, Sendable {
    case newConnect
    case existingPairing
}

enum ConnectGateVerdict: Equatable, Sendable {
    case allow
    case showPaywall
}

// MARK: - The gate decision (pure — MonetizationGateTests)

enum ConnectGate {
    /// The one decision function every gated entry point calls.
    ///
    /// Pinned rules (in priority order):
    ///  1. Dormant gate → allow everything (the scaffold ships inert).
    ///  2. Existing pairings ALWAYS pass — a transient entitlement failure
    ///     (offline, StoreKit outage) must never sever a live connection.
    ///  3. A definitive answer decides new connects: entitled → allow,
    ///     not entitled → paywall (the cache never overrides a fresh answer).
    ///  4. Unknown state falls back to the cached last-known entitlement:
    ///     cached-entitled fails open, anything else fails closed — a new
    ///     connect is the one act that may demand a working entitlement path.
    static func verdict(
        monetizationActive: Bool,
        attempt: ConnectAttempt,
        state: ConnectEntitlementState,
        cachedEntitlement: Bool?
    ) -> ConnectGateVerdict {
        guard monetizationActive else { return .allow }
        guard attempt == .newConnect else { return .allow }
        switch state {
        case .entitled:
            return .allow
        case .notEntitled:
            return .showPaywall
        case .unknown:
            return cachedEntitlement == true ? .allow : .showPaywall
        }
    }
}

// MARK: - Entitlement scan rules (pure)

enum EntitlementScan {
    /// Whether one StoreKit transaction grants the Connected tier. Both
    /// product-type paths live here so flipping
    /// `MonetizationConfiguration.productKind` never touches scan logic:
    /// a non-consumable is owned unless revoked; a subscription must also
    /// be unexpired (a nil expiration is treated as active — StoreKit only
    /// surfaces current entitlements, and honesty here errs toward the
    /// user keeping what they paid for).
    static func transactionGrantsConnected(
        productID: String,
        kind: ConnectedProductKind,
        revocationDate: Date?,
        expirationDate: Date?,
        now: Date
    ) -> Bool {
        guard productID == MonetizationConfiguration.connectedProductID else { return false }
        guard revocationDate == nil else { return false }
        switch kind {
        case .nonConsumable:
            return true
        case .annualSubscription:
            guard let expirationDate else { return true }
            return expirationDate > now
        }
    }

    /// The last-known cache updates only on DEFINITIVE answers; a transient
    /// unknown preserves whatever we knew — that preserved value is what
    /// lets a paid user start a new connect while StoreKit is unreachable.
    static func updatedCache(state: ConnectEntitlementState, previous: Bool?) -> Bool? {
        switch state {
        case .entitled: true
        case .notEntitled: false
        case .unknown: previous
        }
    }
}

// MARK: - Paywall presentation rules (pure)

enum PaywallPresentation {
    /// Real data only: the App Store's localized `Product.displayPrice` or
    /// an honest "—" while it hasn't loaded — never a hardcoded price.
    static func priceLabel(displayPrice: String?) -> String {
        displayPrice ?? "—"
    }

    static func purchaseEnabled(productLoaded: Bool, actionInFlight: Bool) -> Bool {
        productLoaded && !actionInFlight
    }

    static func restoreEnabled(actionInFlight: Bool) -> Bool {
        !actionInFlight
    }

    /// Pinned: the paywall is ALWAYS dismissible — no dark patterns, not
    /// even while a purchase is in flight (StoreKit finishes it regardless).
    static func dismissEnabled(actionInFlight: Bool) -> Bool {
        true
    }

    /// The sheet closes itself only when the tier actually unlocked; every
    /// other outcome leaves it up with its honest error/state visible.
    static func shouldAutoDismiss(after outcome: EntitlementActionOutcome) -> Bool {
        outcome == .unlocked
    }
}

// MARK: - DEBUG override rules (pure) + storage

/// Developer-screen entitlement override so device testing doesn't require
/// sandbox purchases: `system` = real StoreKit state (sandbox round-trips
/// still testable), `unlocked`/`locked` force a definitive answer.
enum MonetizationEntitlementOverride: String, CaseIterable, Sendable {
    case system
    case unlocked
    case locked
}

enum MonetizationDebugRules {
    /// The DEBUG gate toggle activates the (config-dormant) gate for this
    /// build only; it can never deactivate a launched gate.
    static func effectiveGateActive(configuredEnabled: Bool, debugGateEnabled: Bool) -> Bool {
        configuredEnabled || debugGateEnabled
    }

    static func effectiveEntitlementState(
        real: ConnectEntitlementState,
        override: MonetizationEntitlementOverride
    ) -> ConnectEntitlementState {
        switch override {
        case .system: real
        case .unlocked: .entitled
        case .locked: .notEntitled
        }
    }
}

#if DEBUG
/// UserDefaults-backed storage for the Developer-screen override. Kept out
/// of `UserSettings` deliberately: the flags must have zero Release surface
/// (this whole type compiles out), and a persisted-settings blob is forever.
@MainActor
enum MonetizationDebugSettings {
    static let gateEnabledDefaultsKey = "org.aethyrion.talaria27.monetization.debug.gateEnabled"
    static let overrideDefaultsKey = "org.aethyrion.talaria27.monetization.debug.entitlementOverride"

    static var gateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: gateEnabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: gateEnabledDefaultsKey) }
    }

    static var entitlementOverride: MonetizationEntitlementOverride {
        get {
            guard let raw = UserDefaults.standard.string(forKey: overrideDefaultsKey),
                  let value = MonetizationEntitlementOverride(rawValue: raw) else { return .system }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: overrideDefaultsKey) }
    }
}
#endif
