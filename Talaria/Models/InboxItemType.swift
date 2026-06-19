import SwiftUI

enum InboxItemType: String, Codable, Hashable, Sendable, CaseIterable {
    case approval
    case notification
    case reminder
    case suggestion
    case alert

    var displayLabel: String {
        switch self {
        case .approval: "Approval"
        case .notification: "Notification"
        case .reminder: "Reminder"
        case .suggestion: "Suggestion"
        case .alert: "Alert"
        }
    }

    var displayIcon: String {
        switch self {
        case .approval: "checkmark.seal.fill"
        case .notification: "bell.badge.fill"
        case .reminder: "clock.fill"
        case .suggestion: "lightbulb.fill"
        case .alert: "exclamationmark.triangle.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .approval: .orange
        case .notification: .blue
        case .reminder: .purple
        case .suggestion: .teal
        case .alert: .red
        }
    }
}
