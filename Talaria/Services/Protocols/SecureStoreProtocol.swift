import Foundation

@MainActor
protocol SecureStoreProtocol {
    func store(key: String, value: String) async
    func retrieve(key: String) async -> String?
    func delete(key: String) async
}
