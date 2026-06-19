import Foundation

@MainActor
protocol SyncCoordinatorProtocol {
    var syncStatus: SyncStatus { get }
    func sync() async
}
