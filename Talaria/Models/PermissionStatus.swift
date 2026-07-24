import SwiftUI

enum PermissionStatus: String, Codable, Hashable, Sendable {
    case notDetermined
    case authorized
    case authorizedWhenInUse
    case authorizedAlways
    case limited
    case denied
    case restricted
    case unsupported

    var displayLabel: String {
        switch self {
        case .notDetermined: "Not Set"
        case .authorized: "Enabled"
        case .authorizedWhenInUse: "While Using"
        case .authorizedAlways: "Always"
        case .limited: "Limited"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .unsupported: "Unavailable"
        }
    }

    var displayColor: Color {
        switch self {
        case .notDetermined: .secondary
        case .authorized, .authorizedWhenInUse, .authorizedAlways: .green
        case .limited: .orange
        case .denied: .red
        case .restricted: .orange
        case .unsupported: .secondary
        }
    }

    var actionLabel: String? {
        switch self {
        case .notDetermined: "Enable"
        case .authorized, .authorizedWhenInUse, .authorizedAlways: nil
        case .limited: "Manage"
        case .denied: "Open Settings"
        case .restricted: nil
        case .unsupported: nil
        }
    }
}

enum LocationAuthorizationLevel: String, Codable, Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always

    var displayLabel: String {
        switch self {
        case .notDetermined: "Not Set"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .whenInUse: "While Using"
        case .always: "Always"
        }
    }
}

enum LocationAccuracyLevel: String, Codable, Hashable, Sendable {
    case unknown
    case full
    case reduced

    var displayLabel: String {
        switch self {
        case .unknown: "Unknown Accuracy"
        case .full: "Full Accuracy"
        case .reduced: "Reduced Accuracy"
        }
    }
}
