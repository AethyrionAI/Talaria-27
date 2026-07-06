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
    func togglePlayback(path: String) {
        if playingPath == path {
            stop()
            return
        }
        stop()

        let url = URL(fileURLWithPath: path)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            guard player.play() else {
                Self.logger.error("Voice memo playback: play() returned false")
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            self.player = player
            playingPath = path
        } catch {
            Self.logger.error("Voice memo playback failed: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func stop() {
        // Deactivate unconditionally — a failed start can leave the session
        // active with no player; releasing an inactive session is harmless.
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        playingPath = nil
    }

    // MARK: - AVAudioPlayerDelegate

    /// Delegate callbacks arrive off the main actor; hop back to clear state.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
