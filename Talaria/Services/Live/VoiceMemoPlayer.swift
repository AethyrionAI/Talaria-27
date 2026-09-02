@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Local playback for staged and sent voice memos (#9).
///
/// One shared instance so only one memo plays at a time across composer chips
/// and sent bubbles. Plays the ACTUAL recorded file from disk — if the file is
/// gone (cache cleared, reinstall), callers hide the affordance rather than
/// showing a dead button ("real data only"; see `canPlay(path:)`).
///
/// Session ownership mirrors VoiceMemoRecorder: `.playback` is claimed only
/// while playing and released with `.notifyOthersOnDeactivation`.
@MainActor
@Observable
final class VoiceMemoPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = VoiceMemoPlayer()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.aethyrion.talaria",
        category: "VoiceMemoPlayer"
    )

    /// Path of the memo currently playing, nil when idle.
    private(set) var playingPath: String?

    private var player: AVAudioPlayer?

    /// **#399/#84 — true only between a successful activation here and
    /// our own release.** The voice engines share the ONE `AVAudioSession`, so
    /// a `stop()` that deactivates a session this instance never activated
    /// tears down whatever else owns it. That is the 2026-07-16 flatline (#84)
    /// exactly, and `SpeechOutputService` has carried this same flag since —
    /// this player was the one audio surface still releasing unconditionally,
    /// under a comment asserting *"releasing an inactive session is
    /// harmless."* **That sentence is the claim #84 falsified.**
    @ObservationIgnored private var didActivateAudioSession = false

    /// #198B: single-flight for the user-facing transition. `togglePlayback`
    /// now suspends (session calls run off-main, awaited), and an await is
    /// where a second tap can interleave — #128's device-crash class. A tap
    /// during a transition is DROPPED, restoring the run-to-completion the
    /// synchronous version had.
    @ObservationIgnored private var isTransitioning = false

    /// harness-visible (#216): the deactivation effect, injectable so a test
    /// can drive `stop()` itself and observe whether the guard let the call
    /// through.
    ///
    /// **Why a seam rather than testing the pure decision alone.** A suite
    /// that only exercises `shouldReleaseAudioSession` stays GREEN when the
    /// call in `stop()` is deleted — the fix vanishes and the bars applaud.
    /// #340 measured that shape: eleven green parsing tests survived removing
    /// the `performCreate` wiring they existed to protect.
    ///
    /// #198B: async, and AWAITED at every call site — a deactivation that a
    /// path can follow with an activation must complete first, or the two
    /// race on the one shared session (the entry's hazard ①). Off-main via
    /// `AudioSessionOffMain`, which is the item's point: the sync spelling
    /// logged the `AVAudioSession_iOS.mm:978` main-thread fault.
    @ObservationIgnored var deactivateAudioSession: () async -> Void = {
        try? await AudioSessionOffMain.setActive(
            false,
            options: .notifyOthersOnDeactivation,
            reason: "memo-playback-stop"
        )
    }

    /// #198B: the activation half, seamed for the same reason — the ordering
    /// bar (deactivate THEN activate on one toggle) needs both effects
    /// observable, and #399 proved seam-observed wiring is the half that
    /// catches a deleted fix. Category + activation ride one off-main hop so
    /// their relative order is preserved inside the closure.
    @ObservationIgnored var activateForPlayback: () async throws -> Void = {
        try await AudioSessionOffMain.run(activating: true, reason: "memo-playback-start") { session in
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        }
    }

    func isPlaying(path: String) -> Bool {
        playingPath == path
    }

    /// Whether a play affordance should be offered at all: the audio file
    /// must still exist on disk.
    nonisolated static func canPlay(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Starts playback of `path`, stopping any other memo. Tapping the one
    /// already playing stops it.
    ///
    /// #198B: async — every session transition is AWAITED, so the stop's
    /// deactivation completes before the start's activation by construction
    /// (never `Task { }` a deactivation on a path that can reactivate). The
    /// `isTransitioning` guard restores the tap atomicity the awaits remove.
    func togglePlayback(path: String) async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        if playingPath == path {
            await stopTransition()
            return
        }
        await stopTransition()

        let url = URL(fileURLWithPath: path)
        do {
            try await activateForPlayback()
            didActivateAudioSession = true
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            guard player.play() else {
                Self.logger.error("Voice memo playback: play() returned false")
                await releaseAudioSessionIfOwned()
                return
            }
            self.player = player
            playingPath = path
        } catch {
            Self.logger.error("Voice memo playback failed: \(error.localizedDescription, privacy: .public)")
            await stopTransition()
        }
    }

    /// #198B: unguarded on purpose — the delegate's natural-completion stop
    /// must never be dropped, and every effect inside is idempotent (the
    /// #399 flag makes a second release a no-op), so interleaving with a
    /// guarded toggle at an await is safe.
    func stop() async {
        await stopTransition()
    }

    private func stopTransition() async {
        // #399: release only what this instance activated. A failed start is
        // still covered — the flag is set the moment the activation
        // succeeds, so a start that dies at `AVAudioPlayer(contentsOf:)` or at
        // `play()` still releases; only a start that never activated at all
        // leaves the session alone, which is the whole point.
        player?.stop()
        player = nil
        await releaseAudioSessionIfOwned()
        playingPath = nil
    }

    /// The #84 release, guarded. Returns whether the deactivation ran, so a
    /// test can assert on the decision as well as the effect.
    @discardableResult
    private func releaseAudioSessionIfOwned() async -> Bool {
        guard Self.shouldReleaseAudioSession(didActivate: didActivateAudioSession) else {
            return false
        }
        didActivateAudioSession = false
        await deactivateAudioSession()
        return true
    }

    /// The #84 decision, pure for tests — mirroring
    /// `SpeechOutputService.shouldReleaseAudioSession`'s load-bearing clause:
    /// **never deactivate a session this instance did not activate.** The
    /// player needs only the one input; the read-aloud service also weighs
    /// utterance/stream idleness because it can be mid-queue, which a
    /// single-file player cannot.
    nonisolated static func shouldReleaseAudioSession(didActivate: Bool) -> Bool {
        didActivate
    }

    // MARK: - AVAudioPlayerDelegate

    /// Delegate callbacks arrive off the main actor; hop back to clear state.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            await self.stop()
        }
    }
}
