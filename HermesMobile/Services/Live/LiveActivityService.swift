import ActivityKit
import Foundation

/// Manages Hermes Live Activities on the Lock Screen and Dynamic Island.
/// Starts activities when voice sessions or tool calls begin, updates on
/// state changes, and ends when the session/task completes.
@MainActor
@Observable
final class LiveActivityService {
    private var currentActivity: Activity<HermesActivityAttributes>?
    private var updateTimer: Timer?
    private var startedAt: Date?

    /// Whether Live Activities are available on this device.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Voice Session

    /// Start a Live Activity for an active voice session.
    func startVoiceSession() {
        guard isAvailable else { return }
        let attributes = HermesActivityAttributes(agentName: "Hermes")
        let state = HermesActivityAttributes.ContentState(
            status: "Listening",
            toolName: nil,
            elapsedSeconds: 0,
            sessionType: "voice"
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
            // Live Activities not supported or disabled by user — silently ignore
        }
    }

    /// Update the Live Activity with new voice state.
    func updateVoiceState(_ status: String, toolName: String? = nil) {
        guard let activity = currentActivity, activity.activityState == .active else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? .now))
        let state = HermesActivityAttributes.ContentState(
            status: status,
            toolName: toolName,
            elapsedSeconds: elapsed,
            sessionType: "voice"
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - Chat / Tool Calls

    /// Start a Live Activity for a chat tool call.
    func startToolCall(toolName: String) {
        guard isAvailable, currentActivity == nil else { return }
        let attributes = HermesActivityAttributes(agentName: "Hermes")
        let state = HermesActivityAttributes.ContentState(
            status: "Working...",
            toolName: toolName,
            elapsedSeconds: 0,
            sessionType: "tool"
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

    /// Update tool call progress.
    func updateToolProgress(_ status: String, toolName: String? = nil) {
        guard let activity = currentActivity, activity.activityState == .active else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? .now))
        let state = HermesActivityAttributes.ContentState(
            status: status,
            toolName: toolName,
            elapsedSeconds: elapsed,
            sessionType: currentActivity != nil ? "tool" : "chat"
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    /// End the current Live Activity.
    func endActivity() {
        guard let activity = currentActivity else { return }
        updateTimer?.invalidate()
        updateTimer = nil
        startedAt = nil

        let finalState = HermesActivityAttributes.ContentState(
            status: "Done",
            toolName: nil,
            elapsedSeconds: 0,
            sessionType: "voice"
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    // MARK: - Timer

    /// Periodically update elapsed time on the Live Activity.
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
        let updated = HermesActivityAttributes.ContentState(
            status: currentState.status,
            toolName: currentState.toolName,
            elapsedSeconds: elapsed,
            sessionType: currentState.sessionType
        )
        Task {
            await activity.update(.init(state: updated, staleDate: nil))
        }
    }
}
