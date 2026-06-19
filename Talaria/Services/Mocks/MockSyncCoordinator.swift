import Foundation

@MainActor
@Observable
final class MockSyncCoordinator: SyncCoordinatorProtocol {
    var syncStatus: SyncStatus = .synced

    func sync() async {
        syncStatus = .syncing
        try? await Task.sleep(for: .seconds(1.5))
        syncStatus = .synced
    }
}
