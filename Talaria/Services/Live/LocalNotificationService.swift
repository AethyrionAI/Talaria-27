import Foundation
import UserNotifications
import UIKit

/// Local (on-device) notifications for agent runs that finish while the app is
/// backgrounded. Phase 1 of the agent-run background-completion work
/// (OPEN_ITEMS #21 / #38): fired when a reconcile detects a run that completed
/// after the stream was dropped on lock. Authorization is requested lazily on
/// first send; this should later move behind the NOTIFICATIONS settings screen (#10).
@MainActor
final class LocalNotificationService {
    private var didRequestAuthorization = false

    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// #47: a lock-screen reply that could not be delivered — surfaced
    /// honestly instead of the typed text vanishing.
    func notifyReplyFailed(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Reply not sent"
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = trimmed.isEmpty
            ? "Hermes couldn't accept the reply. Open Talaria to retry."
            : trimmed
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "hermes.reply.failed.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Schedules an immediate local notification announcing a finished run.
    /// Caller only invokes this when the app is not active.
    func notifyRunCompleted(preview: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Hermes finished"
        let trimmed = preview?.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = (trimmed?.isEmpty == false) ? trimmed! : "Your reply is ready."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "hermes.run.completed.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
