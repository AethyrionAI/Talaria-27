import Foundation

@MainActor
protocol MediaServiceProtocol {
    var cameraAuthorizationStatus: PermissionStatus { get }
    var photosAuthorizationStatus: PermissionStatus { get }
    func requestCameraAuthorization() async -> PermissionStatus
    func requestPhotosAuthorization() async -> PermissionStatus
}
