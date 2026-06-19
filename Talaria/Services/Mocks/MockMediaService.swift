import Foundation

@MainActor
@Observable
final class MockMediaService: MediaServiceProtocol {
    var cameraAuthorizationStatus: PermissionStatus = .notDetermined
    var photosAuthorizationStatus: PermissionStatus = .notDetermined

    func requestCameraAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        cameraAuthorizationStatus = .authorized
        return .authorized
    }

    func requestPhotosAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        photosAuthorizationStatus = .authorized
        return .authorized
    }
}
