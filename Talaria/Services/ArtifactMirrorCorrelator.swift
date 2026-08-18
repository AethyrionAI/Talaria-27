import Foundation

/// The one surface the correlator needs from `ChatStore` — the open
/// thread's identity and messages, plus the sidecar persist. A protocol so
/// #362 3D-A's match rules are testable without the store's DI graph.
@MainActor
protocol ArtifactMirrorTranscript: AnyObject {
    /// The server session id of the thread the transcript currently shows
    /// (nil when no Hermes thread is open). The single-slot conversation
    /// cache means this is the only thread a mirror item can attach to LIVE;
    /// items for other sessions hold until that thread opens or the window
    /// expires.
    var mirrorSessionID: String? { get }
    var mirrorMessages: [Message] { get set }
    /// Persist the open thread's attachment records (the #277 sidecar) so an
    /// attach survives leaving and reopening the thread.
    func persistMirrorAttachments()
}

/// #362 3D-A/3D-D: attaches plugin-mirrored artifacts to the right turn.
///
/// The correlation key is **session + path** — the runs stream records the
/// same path as the `write_file` activity's preview, and both survive a
/// transcript refetch (the host's `turn_id` never reaches the app, so
/// nothing here keys on it). Match precedence, newest message first:
///
/// 1. a pointer-only attachment for the path (the runs plane's Tier-2 prose
///    sweep) → **upgraded in place**, same attachment id, so no second chip;
/// 2. a `write_file`/`create_file` activity for the path on a message with
///    no attachment for that path → a new anchored Tier-1 chip;
/// 3. no match → held (bounded window), retried as the transcript changes;
///    expiry drops the item. **Never attached to a guessed message** — the
///    3A-D honesty rule extended to this channel.
@MainActor
final class ArtifactMirrorCorrelator {

    static let defaultHoldWindow: TimeInterval = 600
    static let maxPending = 16

    private weak var transcript: (any ArtifactMirrorTranscript)?
    private let holdWindow: TimeInterval
    private let clock: () -> Date
    private var pending: [(item: ArtifactMirrorItem, receivedAt: Date)] = []

    init(
        transcript: any ArtifactMirrorTranscript,
        holdWindow: TimeInterval = ArtifactMirrorCorrelator.defaultHoldWindow,
        clock: @escaping () -> Date = Date.init
    ) {
        self.transcript = transcript
        self.holdWindow = holdWindow
        self.clock = clock
    }

    func receive(_ item: ArtifactMirrorItem) {
        if attach(item) { return }
        pending.append((item, clock()))
        if pending.count > Self.maxPending {
            pending.removeFirst(pending.count - Self.maxPending)
        }
    }

    /// Re-runs every held item against the current transcript. `ChatStore`
    /// calls this after streaming updates land and after `openSession`
    /// finishes — the two moments the match target can appear.
    func retryPending() {
        guard !pending.isEmpty else { return }
        let now = clock()
        pending = pending.filter { entry in
            if attach(entry.item) { return false }
            if now.timeIntervalSince(entry.receivedAt) >= holdWindow {
                TalariaLog.verbose(
                    "artifact mirror dropped an expired item for session \(entry.item.sessionID) path \(entry.item.path)"
                )
                return false
            }
            return true
        }
    }

    var pendingCountForDiagnostics: Int { pending.count }

    // MARK: - Matching

    private func attach(_ item: ArtifactMirrorItem) -> Bool {
        guard let transcript, transcript.mirrorSessionID == item.sessionID else { return false }
        var messages = transcript.mirrorMessages

        // Pass 1 — upgrade a pointer-only chip for this path in place.
        for index in messages.indices.reversed() where messages[index].sender.isAgentAuthored {
            guard let slot = messages[index].attachments.firstIndex(where: {
                $0.localStoragePath == nil && Self.attachmentMatchesPath($0, path: item.path)
            }) else { continue }
            let pointer = messages[index].attachments[slot]
            guard let staged = MessageAttachment.agentFile(remotePath: item.path, content: item.content)
            else { return false }
            messages[index].attachments[slot] = MessageAttachment(
                id: pointer.id,
                kind: staged.kind,
                fileName: staged.fileName,
                mimeType: staged.mimeType,
                thumbnailBase64: pointer.thumbnailBase64,
                localStoragePath: staged.localStoragePath,
                voiceMemoAudioPath: pointer.voiceMemoAudioPath,
                remotePath: pointer.remotePath,
                remoteProfileID: pointer.remoteProfileID,
                anchorOffset: pointer.anchorOffset
            )
            transcript.mirrorMessages = messages
            transcript.persistMirrorAttachments()
            return true
        }

        // Pass 2 — a write activity for this path with no chip yet.
        for index in messages.indices.reversed() where messages[index].sender.isAgentAuthored {
            let message = messages[index]
            guard !message.attachments.contains(where: {
                Self.attachmentMatchesPath($0, path: item.path)
            }) else { continue }
            guard let activity = message.toolActivities.first(where: {
                Self.isWriteTool($0.label) && Self.detailMatches($0.detail, path: item.path)
            }) else { continue }
            guard var staged = MessageAttachment.agentFile(remotePath: item.path, content: item.content)
            else { return false }
            staged.anchorOffset = activity.anchorOffset
            messages[index].attachments.append(staged)
            transcript.mirrorMessages = messages
            transcript.persistMirrorAttachments()
            return true
        }

        // Pass 3 (#364) — no unfilled match, but SOME message in this
        // session already carries a chip for the path (stored-args
        // reconstruction or an earlier delivery beat us): the item is
        // settled — consume it rather than holding a duplicate to expiry.
        // Ordered after pass 2 on purpose: same-path-written-twice must
        // fill the unfilled message first, never vanish into this check.
        if messages.contains(where: { message in
            message.sender.isAgentAuthored && message.attachments.contains {
                Self.attachmentMatchesPath($0, path: item.path)
            }
        }) {
            return true
        }

        return false
    }

    private static func isWriteTool(_ label: String) -> Bool {
        label == "write_file" || label == "create_file"
    }

    /// The activity's `detail` is the server preview — the raw path on the
    /// runs plane, but `build_tool_preview` may clip long values, so a
    /// clipped prefix still matches its own path.
    static func detailMatches(_ detail: String?, path: String) -> Bool {
        guard let detail, !detail.isEmpty else { return false }
        if detail == path { return true }
        if detail.hasSuffix("…"), path.hasPrefix(detail.dropLast()) { return true }
        if detail.hasSuffix("..."), path.hasPrefix(detail.dropLast(3)) { return true }
        return false
    }

    /// "Already has a chip for this path" — by the Tier-2 remote path when
    /// present, else by the staged file name Tier 1 derives from the path.
    static func attachmentMatchesPath(_ attachment: MessageAttachment, path: String) -> Bool {
        if let remote = attachment.remotePath, remote == path { return true }
        let leaf = MessageAttachment.lastPathComponentAcrossHosts(path)
        return !leaf.isEmpty && attachment.fileName == leaf
    }
}
