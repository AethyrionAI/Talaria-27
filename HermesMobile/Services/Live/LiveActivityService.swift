import ActivityKit
import Foundation

/// Manages Hermes Live Activities on the Lock Screen and Dynamic Island.
@MainActor
@Observable
final class LiveActivityService {
    private var currentActivity: Activity<HermesActivityAttributes>?
    private var updateTimer: Timer?
    private var startedAt: Date?

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Voice Session

    func startVoiceSession() {
        guard isAvailable else { return }
        let attributes = HermesActivityAttributes(agentName: "Hermes")
        let state = HermesActivityAttributes.ContentState(
            status: "Listening", toolName: nil, elapsedSeconds: 0, sessionType: "voice"
        )
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            startedAt = .now
            startUpdateTimer()
        } catch {
            // Live Activities not supported or disabled — silently ignore
        }
    }

    func updateVoiceState(_ status: String, toolName: String? = nil) {
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? .now))
        let state = HermesActivityAttributes.ContentState(
            status: status, toolName: toolName, elapsedSeconds: elapsed, sessionType: "voice"
        )
        updateActivity(with: state)
    }

    // MARK: - Chat / Tool Calls

    func startToolCall(toolName: String) {
        guard isAvailable, currentActivity == nil else { return }
        let attributes = HermesActivityAttributes(agentName: "Hermes")
        let state = HermesActivityAttributes.ContentState(
            status: "Working...", toolName: toolName, elapsedSeconds: 0, sessionType: "tool"
        )
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            startedAt = .now
            startUpdateTimer()
        } catch {
            // Silently ignore
        }
    }

    func updateToolProgress(_ status: String, toolName: String? = nil) {
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? .now))
        let state = HermesActivityAttributes.ContentState(
            status: status, toolName: toolName, elapsedSeconds: elapsed, sessionType: "tool"
        )
        updateActivity(with: state)
    }

    // MARK: - End

    func endActivity() {
        guard let activity = currentActivity else { return }
        updateTimer?.invalidate()
        updateTimer = nil
        startedAt = nil
        currentActivity = nil

        let finalContent = ActivityContent(
            state: HermesActivityAttributes.ContentState(
                status: "Done", toolName: nil, elapsedSeconds: 0, sessionType: "voice"
            ),
            staleDate: nil
        )
        // Capture the activity ID and end it in a detached task to avoid sendability issues
        let activityID = activity.id
        Task.detached {
            for activity in Activity<HermesActivityAttributes>.activities where activity.id == activityID {
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

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickElapsedTime()
            }
        }
    }

    private func tickElapsedTime() {
        guard let activity = currentActivity, activity.activityState == .active else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? .now))
        let currentState = activity.content.state
        let state = HermesActivityAttributes.ContentState(
            status: currentState.status,
            toolName: currentState.toolName,
            elapsedSeconds: elapsed,
            sessionType: currentState.sessionType
        )
        updateActivity(with: state)
    }
}
