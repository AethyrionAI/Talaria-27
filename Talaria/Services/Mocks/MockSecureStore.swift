import Foundation

@MainActor
@Observable
final class MockSecureStore: SecureStoreProtocol {
    private var store: [String: String] = [:]

    func store(key: String, value: String) async {
        store[key] = value
    }

    func retrieve(key: String) async -> String? {
        store[key]
    }

    func delete(key: String) async {
        store.removeValue(forKey: key)
    }
}
