import SwiftUI

enum ConnectionStatus: String, Codable, Hashable, Sendable {
    case connected
    case connecting
    case disconnected
    case error

    var displayLabel: String {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        case .error: "Error"
        }
    }

    var displayIcon: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .disconnected: "xmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .secondary
        case .error: .red
        }
    }
}
