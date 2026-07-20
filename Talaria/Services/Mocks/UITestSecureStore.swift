import Foundation

/// UITest-only stand-in for the keychain (#135). The standing UI-test
/// harness builds unsigned (`CODE_SIGNING_ALLOWED=NO`), which strips the
/// app's entitlements — and the iOS 27 simulator keychain then rejects
/// every SecItem write, silently (the store helpers ignore statuses). A
/// freshly paired session's tokens vanished on write, so `initialize()`'s
/// no-access-token guard un-paired the app milliseconds after a successful
/// pair (observed on-sim 2026-07-20; the same build signed passes).
///
/// Backing the store with the UITest defaults suite keeps tokens
/// observable and relaunch-durable — the suite name rides
/// `UITEST_DEFAULTS_SUITE` across relaunches, which is exactly the
/// persistence contract the paired-relaunch flow asserts. Constructed ONLY
/// when `UITEST_KEYCHAIN_SERVICE` is set — never a production path.
final class UITestSecureStore: SecureStoreProtocol {
    private let defaults: UserDefaults
    private let namespace: String

    init(serviceName: String, defaults: UserDefaults) {
        self.defaults = defaults
        self.namespace = serviceName
    }

    func store(key: String, value: String) async {
        defaults.set(value, forKey: scopedKey(key))
    }

    func retrieve(key: String) async -> String? {
        defaults.string(forKey: scopedKey(key))
    }

    func delete(key: String) async {
        defaults.removeObject(forKey: scopedKey(key))
    }

    private func scopedKey(_ key: String) -> String {
        "\(namespace).\(key)"
    }
}
