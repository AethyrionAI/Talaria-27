// AskHermesLongRunSupport.swift — Tier B of the Ask Hermes intent (#6).
//
// iOS 27 beta adoption of `LongRunningIntent` + `performBackgroundTask {}` +
// `CancellableIntent` (WWDC26 session 345) so an agent run can survive past
// the ~30 s background-intent cap with real progress and a Stop control.
//
// ENTIRELY FLAG-GATED AND CURRENTLY DISABLED: this was written in a cloud
// session with no iOS 27 SDK to compile against, and the exact protocol
// shapes below are best guesses. `TALARIA_IOS27_INTENTS` is intentionally
// defined nowhere. To enable, a Mac session must:
//   1. Verify every "iOS 27 beta API — verify against SDK" comment below
//      against the real Xcode-beta SDK and fix mismatches.
//   2. Add `TALARIA_IOS27_INTENTS` to SWIFT_ACTIVE_COMPILATION_CONDITIONS in
//      project.yml (app target), then `xcodegen generate` + build.
//   3. Decide whether Tier A's 25 s budget in AskHermesIntent.perform()
//      should be lifted when the long-running path is active.
// Until then AskHermesIntent ships Tier A alone (stable API only).

#if TALARIA_IOS27_INTENTS

import AppIntents
import Foundation

// iOS 27 beta API — verify against SDK: whether LongRunningIntent /
// CancellableIntent live in AppIntents or a new module, and their exact
// availability annotations.
@available(iOS 27.0, *)
extension AskHermesIntent: LongRunningIntent, CancellableIntent {

    // iOS 27 beta API — verify against SDK: the assumed shape is a background
    // continuation entry point that the system invokes when the intent
    // outlives its foreground window, handing over a `Progress` that drives
    // Siri's progress UI. WWDC26-345 shows it as `performBackgroundTask {}` —
    // the closure/parameter arrangement here is a guess.
    func performBackgroundTask(progress: Progress) async throws {
        let chatStore = await AppContainer.sharedDefault().chatStore
        await AskHermesProgressDriver.drive(progress, chatStore: chatStore)
    }

    // iOS 27 beta API — verify against SDK: CancellableIntent's stop hook
    // (name assumed `cancel()`). Wires Siri's Stop control to the existing
    // run-interruption path — the same seam the in-app stop button uses,
    // which finalizes and persists any partial reply (#6 acceptance).
    @MainActor
    func cancel() async {
        AppContainer.sharedDefault().chatStore.cancelStreaming()
    }
}

/// Maps REAL ChatStore streaming signals onto the system `Progress` while a
/// long run is in flight. An agent run is open-ended, so there is no honest
/// denominator — the bar stays indeterminate (totalUnitCount ≤ 0) and actual
/// activity surfaces through a monotonic completed-unit counter plus a
/// description sourced from live state: tool starts (`toolActivities`) and
/// streamed-content growth (`assistant.delta` arrivals). Nothing here is
/// synthesized on a timer — no events, no movement ("real data only").
@available(iOS 27.0, *)
enum AskHermesProgressDriver {

    @MainActor
    static func drive(_ progress: Progress, chatStore: ChatStore) async {
        // iOS 27 beta API — verify against SDK: whether the system supplies a
        // preconfigured Progress or expects the intent to configure it.
        progress.totalUnitCount = -1 // indeterminate: open-ended agent run

        var lastEventCount: Int64 = 0
        while chatStore.isStreaming, !Task.isCancelled {
            if let streamingID = chatStore.streamingMessageID,
               let message = chatStore.conversation?.messages.first(where: { $0.id == streamingID }) {
                // Real signals only: one unit per tool start, one per 100
                // streamed characters. Both only grow, so the counter is
                // monotonic by construction.
                let events = Int64(message.toolActivities.count) + Int64(message.content.count / 100)
                if events > lastEventCount {
                    lastEventCount = events
                    progress.completedUnitCount = events
                    if let tool = message.toolActivity {
                        progress.localizedAdditionalDescription = "Running \(tool)"
                    } else if message.content.isEmpty {
                        progress.localizedAdditionalDescription = "Hermes is thinking"
                    } else {
                        progress.localizedAdditionalDescription = "Streaming reply"
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }
}

#endif
