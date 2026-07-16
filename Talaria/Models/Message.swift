import Foundation

/// A lightweight attachment reference stored on a message for display.
struct MessageAttachment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: String       // "image" or "file"
    let fileName: String
    let mimeType: String
    /// Base64-encoded thumbnail (for images) — small enough to cache/persist.
    let thumbnailBase64: String?
    let localStoragePath: String?
    /// Local path of the source audio when this is a voice memo (#9): the
    /// transcript is what shipped; the audio stays playable from the sent
    /// bubble. Optional + synthesized Codable ⇒ pre-#9 caches (no key) still
    /// decode.
    let voiceMemoAudioPath: String?
    /// #21 Tier 2: the AGENT_FILES_DIR-relative path of an agent-written file
    /// whose bytes never rode the SSE stream (binaries — the 2026-07-16 probe).
    /// The relay's `GET /v1/device/files` serves it; a nil `localStoragePath`
    /// alongside a non-nil `remotePath` renders as a fetchable bubble. Only
    /// ever the whitelist-relative form — never an arbitrary host path.
    /// Optional + synthesized Codable ⇒ pre-#21 caches still decode.
    let remotePath: String?
    /// Lane M (#114): the birth profile of the session that announced this
    /// file — a fetch MUST hit THAT profile's relay (a Mac-hosted session's
    /// file lives in the Mac relay's whitelist, an OJAMD session's in
    /// OJAMD's). Nil collapses to the active profile at fetch time
    /// (pre-Lane-M records, profile-less constructions).
    let remoteProfileID: UUID?

    init(
        id: UUID = UUID(),
        kind: String,
        fileName: String,
        mimeType: String,
        thumbnailBase64: String? = nil,
        localStoragePath: String? = nil,
        voiceMemoAudioPath: String? = nil,
        remotePath: String? = nil,
        remoteProfileID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.thumbnailBase64 = thumbnailBase64
        self.localStoragePath = localStoragePath
        self.voiceMemoAudioPath = voiceMemoAudioPath
        self.remotePath = remotePath
        self.remoteProfileID = remoteProfileID
    }

    init(from pending: PendingAttachment) {
        self.id = pending.id
        self.kind = pending.kind.rawValue
        self.fileName = pending.fileName
        self.mimeType = pending.mimeType
        self.thumbnailBase64 = pending.thumbnailBase64
        self.localStoragePath = pending.localStoragePath
        self.voiceMemoAudioPath = pending.voiceMemoAudioPath
        self.remotePath = nil
        self.remoteProfileID = nil
    }
}

struct Message: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let clientMessageID: UUID?
    let sender: MessageSender
    var content: String
    let timestamp: Date
    let jobID: UUID?
    var status: MessageStatus
    var toolActivity: String?
    var toolActivities: [ToolActivity]
    var codeDiff: CodeDiff?
    /// Raw reasoning streamed over the `_thinking` channel (#4.15). Persisted
    /// with the message so the disclosure survives relaunch; nil for models
    /// that don't reason (and for pre-#4.15 caches).
    var reasoning: String?
    /// One-line on-device condensation of `reasoning` (#4.8 × #4.15).
    /// Generated after the turn completes while the app is foregrounded; nil
    /// until then — the UI falls back to the last raw reasoning line.
    var reasoningSummary: String?
    /// Which brain produced this assistant message (#27) —
    /// `ChatBackendRouter.Brain` raw value ("hermes" / "on-device" /
    /// "private-cloud-beta"). Stamped by the router at `.finished` so the
    /// transcript stays honest across brain switches and reconnects; nil for
    /// user/system messages and pre-#27 caches.
    var brain: String?
    /// Per-turn token usage from this turn's `run.completed` (#46). Stamped at
    /// `.finished` — previously each turn overwrote the last in
    /// `ChatStore.lastTokenUsage` and the report was rendered nowhere. Nil for
    /// user/system messages, pre-#46 caches, and iOS 26 local-brain turns
    /// (real data only — never estimated).
    var usage: TokenUsage?
    /// Wall-clock seconds from optimistic send to `.finished` (#46) — the
    /// duration `pendingMessageSentAt` used to measure and discard.
    var turnDuration: TimeInterval?
    /// Model that served this turn (#46) — what per-turn cost estimates key
    /// their pricing on. Nil when the active model wasn't known at finish.
    var servingModel: String?
    /// P1 (#90): this system message announces a context transplant into a
    /// fresh server session, and its `usage` is the priming turn's real cost.
    /// Separates priming spend from metered chat turns in the session totals.
    /// False for everything else (and absent in pre-#90 caches).
    var isContextPriming: Bool
    var isStreaming: Bool
    var voiceSessionDuration: TimeInterval?
    var attachments: [MessageAttachment]

    /// Whether this message was transcribed from a voice session.
    var isVoiceTranscript: Bool {
        sender == .voiceUser || sender == .voiceHermes
    }

    init(
        id: UUID = UUID(),
        clientMessageID: UUID? = nil,
        sender: MessageSender,
        content: String,
        timestamp: Date = .now,
        jobID: UUID? = nil,
        status: MessageStatus = .sent,
        toolActivity: String? = nil,
        toolActivities: [ToolActivity] = [],
        codeDiff: CodeDiff? = nil,
        reasoning: String? = nil,
        reasoningSummary: String? = nil,
        brain: String? = nil,
        usage: TokenUsage? = nil,
        turnDuration: TimeInterval? = nil,
        servingModel: String? = nil,
        isContextPriming: Bool = false,
        isStreaming: Bool = false,
        voiceSessionDuration: TimeInterval? = nil,
        attachments: [MessageAttachment] = []
    ) {
        self.id = id
        self.clientMessageID = clientMessageID
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.jobID = jobID
        self.status = status
        self.toolActivity = toolActivity
        self.toolActivities = toolActivities
        self.codeDiff = codeDiff
        self.reasoning = reasoning
        self.reasoningSummary = reasoningSummary
        self.brain = brain
        self.usage = usage
        self.turnDuration = turnDuration
        self.servingModel = servingModel
        self.isContextPriming = isContextPriming
        self.isStreaming = isStreaming
        self.voiceSessionDuration = voiceSessionDuration
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id, clientMessageID, sender, content, timestamp, jobID, status, attachments, toolActivities
        case voiceSessionDuration
        case reasoning, reasoningSummary
        case brain
        case usage, turnDuration, servingModel
        case isContextPriming
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        clientMessageID = try container.decodeIfPresent(UUID.self, forKey: .clientMessageID)
        sender = try container.decode(MessageSender.self, forKey: .sender)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        jobID = try container.decodeIfPresent(UUID.self, forKey: .jobID)
        status = try container.decode(MessageStatus.self, forKey: .status)
        attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
        toolActivity = nil
        // Persisted with the message (#10) so the tool timeline survives the
        // conversation cache; absent in pre-#10 caches.
        toolActivities = try container.decodeIfPresent([ToolActivity].self, forKey: .toolActivities) ?? []
        codeDiff = nil
        // Persisted with the message (#4.15) so the reasoning disclosure
        // survives relaunch; absent in pre-#4.15 caches.
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        reasoningSummary = try container.decodeIfPresent(String.self, forKey: .reasoningSummary)
        // Producing brain (#27); absent in pre-#27 caches.
        brain = try container.decodeIfPresent(String.self, forKey: .brain)
        // Turn receipt (#46); absent in pre-#46 caches.
        usage = try container.decodeIfPresent(TokenUsage.self, forKey: .usage)
        turnDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .turnDuration)
        servingModel = try container.decodeIfPresent(String.self, forKey: .servingModel)
        // Context-transplant notice (#90); absent in pre-#90 caches.
        isContextPriming = try container.decodeIfPresent(Bool.self, forKey: .isContextPriming) ?? false
        isStreaming = false
        // Persisted with the message (#1) so the voice-session banner keeps its
        // duration across relaunch; absent in older caches.
        voiceSessionDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .voiceSessionDuration)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(clientMessageID, forKey: .clientMessageID)
        try container.encode(sender, forKey: .sender)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(status, forKey: .status)
        if !attachments.isEmpty {
            try container.encode(attachments, forKey: .attachments)
        }
        if !toolActivities.isEmpty {
            try container.encode(toolActivities, forKey: .toolActivities)
        }
        try container.encodeIfPresent(voiceSessionDuration, forKey: .voiceSessionDuration)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(reasoningSummary, forKey: .reasoningSummary)
        try container.encodeIfPresent(brain, forKey: .brain)
        try container.encodeIfPresent(usage, forKey: .usage)
        try container.encodeIfPresent(turnDuration, forKey: .turnDuration)
        try container.encodeIfPresent(servingModel, forKey: .servingModel)
        if isContextPriming {
            try container.encode(isContextPriming, forKey: .isContextPriming)
        }
    }
}


// MARK: - Agent-generated files (#21 Tier 1)

extension MessageAttachment {
    /// Reconstructs a shareable file attachment from an agent `write_file` tool
    /// call. The agent writes files to its own host working dir and the Sessions
    /// API never delivers them to the phone — but the SSE `tool.started` event
    /// carries the bytes inline (`args.content`), so the client rebuilds the file
    /// locally and stages it for the share sheet. Text content only (Tier 1).
    /// Returns nil if the content can't be staged to disk.
    static func agentFile(remotePath: String, content: String) -> MessageAttachment? {
        let lastComponent = lastPathComponentAcrossHosts(remotePath)
        let fileName = lastComponent.isEmpty ? "agent_output.txt" : lastComponent
        guard let data = content.data(using: .utf8),
              let storedPath = stageAgentFile(data: data, preferredFileName: fileName)
        else { return nil }
        return MessageAttachment(
            kind: "file",
            fileName: fileName,
            mimeType: inferredMimeType(forFileName: fileName),
            thumbnailBase64: nil,
            localStoragePath: storedPath
        )
    }

    /// Stages bytes into the same `App Support/Talaria/Attachments` directory the
    /// composer uses for outgoing attachments. Self-contained (mirrors the
    /// `PendingAttachment` staging) so the existing upload path stays untouched.
    private static func stageAgentFile(data: Data, preferredFileName: String) -> String? {
        guard let destination = agentFileStagingDestination(preferredFileName: preferredFileName) else {
            return nil
        }
        do {
            try data.write(to: destination, options: .atomic)
            return destination.path
        } catch {
            return nil
        }
    }

    /// A unique destination inside the Attachments staging directory, with the
    /// directory created — shared by the Tier 1 (bytes) and Tier 2 (downloaded
    /// file) staging paths.
    private static func agentFileStagingDestination(preferredFileName: String) -> URL? {
        let fileManager = FileManager.default
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let attachmentDirectory = baseDirectory
            .appendingPathComponent("Talaria", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        do {
            try fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
        let sanitized = sanitizeAgentFileName(preferredFileName)
        return attachmentDirectory.appendingPathComponent("\(UUID().uuidString)-\(sanitized)")
    }

    /// Path tail for display across BOTH agent hosts: OJAMD's `write_file`
    /// paths use Windows `\` separators, which `NSString`'s path methods
    /// don't split on — a naive `lastPathComponent` would name the file
    /// "O:\Hermes\MobileDL\report.pdf" instead of "report.pdf".
    static func lastPathComponentAcrossHosts(_ path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return (normalized as NSString).lastPathComponent
    }

    private static func sanitizeAgentFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = fileName.components(separatedBy: invalidCharacters).joined(separator: "_")
        return cleaned.isEmpty ? "agent_output.txt" : cleaned
    }

    /// Best-effort MIME inference from the file extension. Text types cover the
    /// Tier 1 reconstructions (string `args.content`); the binary entries exist
    /// for Tier 2 fetchables (#21) — the relay's own `mimetypes` guess governs
    /// the actual response, this only drives client-side chip presentation.
    /// Defaults to `text/plain` (the long-standing Tier 1 behavior).
    static func inferredMimeType(forFileName fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let map: [String: String] = [
            "txt": "text/plain", "log": "text/plain", "text": "text/plain",
            "md": "text/markdown", "markdown": "text/markdown",
            "json": "application/json", "csv": "text/csv", "tsv": "text/tab-separated-values",
            "yml": "application/yaml", "yaml": "application/yaml", "toml": "text/plain",
            "xml": "text/xml", "html": "text/html", "htm": "text/html", "css": "text/css",
            "swift": "text/x-swift", "py": "text/x-python", "js": "text/javascript",
            "ts": "text/typescript", "sh": "text/x-shellscript", "rtf": "text/rtf",
            "ini": "text/plain", "conf": "text/plain", "env": "text/plain",
            "pdf": "application/pdf", "png": "image/png", "jpg": "image/jpeg",
            "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
            "heic": "image/heic", "svg": "image/svg+xml", "zip": "application/zip",
            "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav",
            "mp4": "video/mp4", "mov": "video/quicktime",
        ]
        return map[ext] ?? "text/plain"
    }
}

// MARK: - Agent-generated files (#21 Tier 2)

extension MessageAttachment {
    /// A file the agent produced on the host whose bytes never rode the SSE
    /// stream (binaries — verified by the 2026-07-16 probe: host-side
    /// `terminal` writes never invoke `write_file`, and binary content appears
    /// nowhere in tool args). Carries only the AGENT_FILES_DIR-relative path;
    /// the bytes arrive later via the relay's `/v1/device/files` route, at
    /// which point `staged(atLocalPath:)` flips this into a Tier 1 attachment.
    static func fetchableAgentFile(name: String, remotePath: String, profileID: UUID?) -> MessageAttachment {
        let fileName = name.isEmpty ? "agent_output" : name
        return MessageAttachment(
            kind: "file",
            fileName: fileName,
            mimeType: inferredMimeType(forFileName: fileName),
            thumbnailBase64: nil,
            localStoragePath: nil,
            remotePath: remotePath,
            remoteProfileID: profileID
        )
    }

    /// A copy of this attachment with downloaded bytes staged locally — same
    /// identity, so the transcript row updates in place and the bubble becomes
    /// a normal Tier 1 bubble (preview + ShareLink).
    func staged(atLocalPath path: String) -> MessageAttachment {
        MessageAttachment(
            id: id,
            kind: kind,
            fileName: fileName,
            mimeType: mimeType,
            thumbnailBase64: thumbnailBase64,
            localStoragePath: path,
            voiceMemoAudioPath: voiceMemoAudioPath,
            remotePath: remotePath,
            remoteProfileID: remoteProfileID
        )
    }

    /// Stages a downloaded temp file into the Attachments directory (#21
    /// Tier 2). Moved, not copied — the download is already on disk and a
    /// binary must never double up in memory or storage. Returns the staged
    /// path, or nil when the move fails (the temp file is left for the system
    /// to reap).
    static func stageFetchedAgentFile(from temporaryURL: URL, preferredFileName: String) -> String? {
        guard let destination = agentFileStagingDestination(preferredFileName: preferredFileName) else {
            return nil
        }
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }
}
