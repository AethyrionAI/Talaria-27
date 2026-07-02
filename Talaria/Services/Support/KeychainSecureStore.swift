import Foundation
import Security

@MainActor
final class KeychainSecureStore: SecureStoreProtocol {
    private let serviceName: String

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    func store(key: String, value: String) async {
        storeSync(key: key, value: value)
    }

    func retrieve(key: String) async -> String? {
        retrieveSync(key: key)
    }

    func delete(key: String) async {
        deleteSync(key: key)
    }

    // MARK: Synchronous variants
    //
    // SecItem calls are synchronous at the OS level; these exist for @MainActor
    // sync paths that can't await — e.g. the persistence store's pairing-config
    // load, which runs during store construction (#41).

    func storeSync(key: String, value: String) {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    func retrieveSync(key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard
            status == errSecSuccess,
            let data = item as? Data
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func deleteSync(key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
    }
}
