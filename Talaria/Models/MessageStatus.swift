import SwiftUI

enum MessageStatus: String, Codable, Hashable, Sendable {
    case sending
    case working
    case sent
    case delivered
    case failed
    /// P1 offline compose outbox (#90): composed while the Sessions API was
    /// unreachable; parked durably and auto-sent when it's reachable again.
    case queued

    /// #278: whether this row has SETTLED. A truncation that removes an
    /// unsettled row is removing something still in motion — and `.working`
    /// is the case that made this necessary: a stream that drops (leaving the
    /// chat screen mid-run) leaves the user row `.working` with the run still
    /// live server-side, which the old `!= .sending` check waved straight
    /// through. Exhaustive on purpose: a new status has to answer this.
    var isSettled: Bool {
        switch self {
        case .sending, .working, .queued: false
        case .sent, .delivered, .failed: true
        }
    }

    var displayIcon: String {
        switch self {
        case .sending: "arrow.up.circle"
        case .working: "clock.arrow.circlepath"
        case .sent: "checkmark"
        case .delivered: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .queued: "tray.and.arrow.up"
        }
    }

    var displayColor: Color {
        switch self {
        case .sending: .secondary
        case .working: .secondary
        case .sent: .secondary
        case .delivered: .green
        case .failed: .red
        case .queued: .secondary
        }
    }
}
