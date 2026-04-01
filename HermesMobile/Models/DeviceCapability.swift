import Foundation

struct DeviceCapability: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let permissionType: PermissionType
    var status: PermissionStatus
    var statusDetail: String?

    init(
        id: UUID = UUID(),
        permissionType: PermissionType,
        status: PermissionStatus = .notDetermined,
        statusDetail: String? = nil
    ) {
        self.id = id
        self.permissionType = permissionType
        self.status = status
        self.statusDetail = statusDetail
    }
}
