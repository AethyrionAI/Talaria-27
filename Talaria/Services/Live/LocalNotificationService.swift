import Foundation
import UserNotifications
import UIKit

/// ChatStore's notification side of a run — authorization priming (#31/#189)
/// and the completion/failure notifies. `LocalNotificationService` is the live
/// conformer; tests inject a spy so the priming trigger is assertable.
@MainActor
protocol LocalNotificationScheduling {
    func requestAuthorizationIfNeeded() async
    func notifyReplyFailed(reason: String)
    /// #226 leg (b): `runId` keys the notification identifier so two
    /// notifications for the SAME run replace rather than stack. Nil when the
    /// run is unidentifiable — see `runCompletedIdentifier`.
    func notifyRunCompleted(preview: String?, runId: String?)
}

/// Local (on-device) notifications for agent runs that finish while the app is
/// backgrounded. Phase 1 of the agent-run background-completion work
/// (OPEN_ITEMS #21 / #38): fired when a reconcile detects a run that completed
/// after the stream was dropped on lock. Authorization is requested lazily on
/// first send; this should later move behind the NOTIFICATIONS settings screen (#10).
@MainActor
final class LocalNotificationService: LocalNotificationScheduling {
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
    /// #226 leg (b) — the identifier that decides whether duplicate
    /// notifications for one run STACK or REPLACE.
    ///
    /// **This used to be a fresh `UUID()` every time**, so iOS coalesced
    /// nothing: the relay's insta-push and the reconcile's local notify
    /// arrived as two separate banners for the same reply — the visible half
    /// of §D4's measured ×3.
    ///
    /// **A nil `runId` falls back to a unique id ON PURPOSE.** A stable
    /// constant would collapse every unidentifiable run onto one banner, so a
    /// second run would silently REPLACE a first the user had not read yet —
    /// trading three banners for a missing one, which is the same defect
    /// wearing the opposite sign.
    nonisolated static func runCompletedIdentifier(runId: String?) -> String {
        "hermes.run.completed.\(runId ?? UUID().uuidString)"
    }

    func notifyRunCompleted(preview: String?, runId: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Hermes finished"
        let trimmed = preview?.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = (trimmed?.isEmpty == false) ? trimmed! : "Your reply is ready."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.runCompletedIdentifier(runId: runId),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
