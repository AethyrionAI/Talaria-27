import ActivityKit
import Foundation

/// Manages Hermes Live Activities on the Lock Screen and Dynamic Island.
@MainActor
@Observable
final class LiveActivityService {
    private var currentActivity: Activity<HermesActivityAttributes>?
    private var startedAt: Date?

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // harness-visible (#250 R2, 2026-08-10) — private in spirit; widened only
    // so the throwaway-activity trigger's bar (250T-B) can assert against the
    // SERVICE'S OWN handle instead of a parallel test double. This is the same
    // `currentActivity` the production start paths set and `endActivity()`
    // clears, so a zombie check here is a check on production's bookkeeping.
    var hasActiveActivity: Bool { currentActivity != nil }

    /// What the last start attempt actually did.
    ///
    /// **Why this exists (#326, 2026-08-11).** Both start paths swallow
    /// `Activity.request` errors on purpose — a refused Live Activity must never
    /// break a chat turn or a voice session. But swallowing them also made a
    /// refusal *indistinguishable from never having tried*, and that is what let
    /// a test assert `hasActiveActivity == isAvailable`: an equality that only
    /// holds if ActivityKit vends whenever it reports enabled.
    ///
    /// **It does not.** Measured on the iOS 27.0 simulator host, 2026-08-11:
    /// the sixth concurrent Live Activity throws
    /// `ActivityAuthorizationError.targetMaximumExceeded`
    /// (`com.apple.ActivityKit.ActivityAuthorization`, code 5) while
    /// `areActivitiesEnabled` is still `true`, and the ceiling is **per app**,
    /// not per attributes type — activities of an unrelated type starve ours.
    enum StartOutcome: Equatable, Sendable {
        /// No start has been attempted on this instance.
        case notAttempted
        /// `isAvailable` was false, so the guard returned before requesting.
        case suppressed
        /// An already-running system activity was adopted; nothing was requested.
        case adopted
        /// `Activity.request` succeeded and its handle is held.
        case vended
        /// `Activity.request` threw. ActivityKit refused despite being enabled.
        case refused(String)

        /// Whether this outcome should have left `currentActivity` set. The
        /// harness bar compares against THIS rather than against
        /// `areActivitiesEnabled`, which is a different question.
        var leftAHandle: Bool { self == .adopted || self == .vended }
    }

    // harness-visible (#326, 2026-08-11) — see `StartOutcome` above.
    private(set) var lastStartOutcome: StartOutcome = .notAttempted

    // MARK: - Voice Session

    func startVoiceSession() {
        guard isAvailable else {
            lastStartOutcome = .suppressed
            return
        }
        let now = Date.now
        adoptExistingActivityIfNeeded()
        let attributes = HermesActivityAttributes(agentName: "Hermes")
        let state = HermesActivityAttributes.ContentState(
            status: "Listening", toolName: nil, elapsedSeconds: 0, startDate: now, sessionType: "voice"
        )
        if currentActivity != nil {
            startedAt = now
            lastStartOutcome = .adopted
            updateActivity(with: state)
            return
        }
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            startedAt = now
            lastStartOutcome = .vended
        } catch {
            // Live Activities not supported, disabled, or over the per-app
            // ceiling — never break the session over it, but do RECORD it.
            lastStartOutcome = .refused(String(describing: error))
        }
    }

    func updateVoiceState(_ status: String, toolName: String? = nil) {
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? .now))
        let state = HermesActivityAttributes.ContentState(
            status: status, toolName: toolName, elapsedSeconds: elapsed, startDate: startedAt, sessionType: "voice"
        )
        updateActivity(with: state)
    }

    // MARK: - Chat / Tool Calls

    func startToolCall(toolName: String) {
        guard isAvailable else {
            lastStartOutcome = .suppressed
            return
        }
        let now = Date.now
        adoptExistingActivityIfNeeded()
        let attributes = HermesActivityAttributes(agentName: "Hermes")
        let state = HermesActivityAttributes.ContentState(
            status: "Working...", toolName: toolName, elapsedSeconds: 0, startDate: now, sessionType: "tool"
        )
        if currentActivity != nil {
            startedAt = now
            lastStartOutcome = .adopted
            updateActivity(with: state)
            return
        }
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            startedAt = now
            lastStartOutcome = .vended
        } catch {
            // Never break a turn over a Live Activity — but do RECORD it.
            lastStartOutcome = .refused(String(describing: error))
        }
    }

    func updateToolProgress(_ status: String, toolName: String? = nil) {
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? .now))
        let state = HermesActivityAttributes.ContentState(
            status: status, toolName: toolName, elapsedSeconds: elapsed, startDate: startedAt, sessionType: "tool"
        )
        updateActivity(with: state)
    }

    // MARK: - End

    func endActivity() {
        startedAt = nil
        currentActivity = nil

        let finalContent = ActivityContent(
            state: HermesActivityAttributes.ContentState(
                status: "Done", toolName: nil, elapsedSeconds: 0, startDate: nil, sessionType: "voice"
            ),
            staleDate: nil
        )
        Task.detached {
            for activity in Activity<HermesActivityAttributes>.activities {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Private

    private func updateActivity(with state: HermesActivityAttributes.ContentState) {
        guard let activity = currentActivity, activity.activityState == .active else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        let activityID = activity.id
        Task.detached {
            for activity in Activity<HermesActivityAttributes>.activities where activity.id == activityID {
                await activity.update(content)
            }
        }
    }

    // MARK: - App Lifecycle

    /// Called when the app returns to foreground. No timer to restart —
    /// the widget uses Text(timerInterval:) which ticks natively via the OS.
    func handleAppDidBecomeActive() {
        adoptExistingActivityIfNeeded()
    }

    static func endAllActivities() {
        let finalContent = ActivityContent(
            state: HermesActivityAttributes.ContentState(
                status: "Done", toolName: nil, elapsedSeconds: 0, startDate: nil, sessionType: "voice"
            ),
            staleDate: nil
        )
        Task.detached {
            for activity in Activity<HermesActivityAttributes>.activities {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }

    private func adoptExistingActivityIfNeeded() {
        guard currentActivity == nil else { return }
        if let activity = Activity<HermesActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
            currentActivity = activity
            startedAt = activity.content.state.startDate
        }
    }
}
