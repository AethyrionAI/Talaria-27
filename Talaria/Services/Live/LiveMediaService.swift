import AVFoundation
import Photos

@MainActor
final class LiveMediaService: MediaServiceProtocol {

    var cameraAuthorizationStatus: PermissionStatus {
        Self.mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    var photosAuthorizationStatus: PermissionStatus {
        Self.mapPHStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestCameraAuthorization() async -> PermissionStatus {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        if current != .notDetermined {
            return Self.mapAVStatus(current)
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    func requestPhotosAuthorization() async -> PermissionStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != .notDetermined {
            return Self.mapPHStatus(current)
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.mapPHStatus(status)
    }

    // MARK: - Mapping helpers

    private static func mapAVStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized:    .authorized
        case .denied:        .denied
        case .restricted:    .restricted
        @unknown default:    .notDetermined
        }
    }

    private static func mapPHStatus(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized:    .authorized
        case .denied:        .denied
        case .restricted:    .restricted
        case .limited:       .limited
        @unknown default:    .notDetermined
        }
    }
}
