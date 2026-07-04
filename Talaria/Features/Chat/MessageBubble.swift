import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onRetry: ((Message) -> Void)? = nil

    private var isUser: Bool { message.sender == .user || message.sender == .voiceUser }
    private var isHermes: Bool { message.sender == .hermes || message.sender == .voiceHermes }
    private var isCompactionMessage: Bool { message.content.hasPrefix("[CONTEXT COMPACTION]") }
    private var isBudgetWarning: Bool { message.content.contains("[BUDGET WARNING:") }

    var body: some View {
        if message.sender == .system && message.content.contains("[Voice session ended]") {
            VoiceSessionBanner(duration: message.voiceSessionDuration)
        } else if message.sender == .system {
            systemMessage
        } else if isCompactionMessage {
            compactionBanner
        } else if isUser {
            HStack(alignment: .top, spacing: Design.Spacing.xs) {
                Spacer(minLength: Design.Spacing.xxl)
                userBubble
            }
            .padding(.horizontal, Design.Spacing.md)
        } else {
            HStack(alignment: .top, spacing: Design.Spacing.xs) {
                hermesMessage
                Spacer(minLength: Design.Spacing.xxl)
            }
            .padding(.horizontal, Design.Spacing.md)
        }
    }

    // MARK: - System Message

    private var systemMessage: some View {
        Text(message.content.uppercased())
            .font(Design.Typography.monoSmall)
            .tracking(Design.Tracking.monoWide)
            .foregroundStyle(Design.Colors.mutedForeground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.xxs)
    }

    // MARK: - User Bubble

    /// Cyan-tinted user bubble shape — 16pt corners with the bottom-trailing
    /// corner tightened (per the HUD chat reference `16 16 4 16`).
    private var userBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Design.CornerRadius.xl,
            bottomLeadingRadius: Design.CornerRadius.xl,
            bottomTrailingRadius: Design.CornerRadius.xs,
            topTrailingRadius: Design.CornerRadius.xl
        )
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: Design.Spacing.xxs) {
            if message.isVoiceTranscript {
                voiceTranscriptText(message.content)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.accentTint(0.1), in: userBubbleShape)
                    .overlay {
                        userBubbleShape.strokeBorder(Design.Colors.accentTint(0.28), lineWidth: 1)
                    }

                voiceModeLabel
            } else {
                VStack(alignment: .trailing, spacing: Design.Spacing.xxs) {
                    // Attachment thumbnails
                    if !message.attachments.isEmpty {
                        attachmentGrid(message.attachments)
                    }

                    // Text content (skip if it's just the auto-generated attachment placeholder)
                    let isAttachmentPlaceholder = !message.attachments.isEmpty
                        && message.content.range(of: #"^\[\d+ attachment"#, options: .regularExpression) != nil
                    if !message.content.isEmpty && !isAttachmentPlaceholder {
                        MarkdownContentView(content: message.content, isStreaming: false, textColor: Design.Colors.foregroundBright)
                            .foregroundStyle(Design.Colors.foregroundBright)
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.vertical, Design.Spacing.sm)
                            .background(Design.Colors.accentTint(0.1), in: userBubbleShape)
                            .overlay {
                                userBubbleShape.strokeBorder(Design.Colors.accentTint(0.28), lineWidth: 1)
                            }
                    }
                }

                HStack(spacing: Design.Spacing.xxs) {
                    Text(message.timestamp, style: .time)
                        .font(Design.Typography.monoSmall)
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Colors.mutedForeground)

                    Image(systemName: message.status.displayIcon)
                        .font(.system(size: Design.Size.iconTiny))
                        .foregroundStyle(message.status.displayColor)
                        .accessibilityLabel(message.status.rawValue)
                }
            }

            if message.status == .failed {
                Button { onRetry?(message) } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.danger)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isVoiceTranscript ? "Voice" : "You"): \(message.content). \(message.status.rawValue)")
    }

    // MARK: - Hermes Message

    private var hermesMessage: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            if message.isVoiceTranscript {
                voiceTranscriptText(message.content)
                    .padding(.vertical, Design.Spacing.xxs)

                voiceModeLabel
            } else if message.isStreaming && message.content.isEmpty && message.toolActivities.isEmpty {
                streamingPlaceholder
            } else {
                if message.toolActivities.isEmpty {
                    if !message.content.isEmpty {
                        streamingText
                    } else if message.isStreaming {
                        streamingPlaceholder
                    }
                    if let activity = message.toolActivity {
                        toolActivityPill(activity)
                    }
                } else {
                    // #10: tool-call chips render inline at the point in the
                    // content where each call actually fired, and persist as
                    // part of the message.
                    interleavedTranscript

                    if message.isStreaming && message.content.isEmpty {
                        streamingPlaceholder
                    }
                }

                if let diff = message.codeDiff, !diff.isEmpty {
                    InlineDiffView(diff: diff)
                }

                // #21 Tier 1: files the agent wrote, reconstructed from the stream.
                if !message.attachments.isEmpty {
                    hermesAttachments(message.attachments)
                }

                if !message.isStreaming {
                    Text(message.timestamp, style: .time)
                        .font(Design.Typography.monoSmall)
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Colors.mutedForeground)
                }

                if message.status == .failed {
                    Button { onRetry?(message) } label: {
                        Label("Regenerate", systemImage: "arrow.counterclockwise")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Brand.accent)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hermes: \(message.content)")
        .accessibilityAddTraits(message.isStreaming ? .updatesFrequently : [])
    }

    // MARK: - Voice Transcript Components

    private func voiceTranscriptText(_ content: String) -> some View {
        Text("\u{201C}\(content)\u{201D}")
            .font(Design.Typography.body.italic())
            .foregroundStyle(Design.Colors.foreground.opacity(0.85))
    }

    private var voiceModeLabel: some View {
        MonoLabel(
            "Voice Mode",
            size: 9,
            tracking: Design.Tracking.mono,
            color: Design.Colors.dimForeground
        )
    }

    // MARK: - Interleaved Transcript (#10)

    /// One ordered slice of an assistant turn: either a run of streamed text or
    /// a group of tool calls that fired at that point in the content.
    enum TranscriptSegment: Identifiable {
        case text(String, offset: Int)
        case tools([ToolActivity], offset: Int)

        var id: String {
            switch self {
            case .text(_, let offset): "text-\(offset)"
            case .tools(let group, let offset): "tools-\(offset)-\(group.first?.id.uuidString ?? "")"
            }
        }
    }

    /// Splits the assistant content at each tool call's anchor so chips render
    /// where the model actually invoked them. Anchors are non-decreasing while
    /// streaming; clamping keeps reloaded history (anchor 0) and any stale
    /// cache safe. Consecutive calls at the same anchor share one chip group.
    static func transcriptSegments(content: String, activities: [ToolActivity]) -> [TranscriptSegment] {
        guard !activities.isEmpty else {
            return content.isEmpty ? [] : [.text(content, offset: 0)]
        }
        let characters = Array(content)
        var segments: [TranscriptSegment] = []
        var cursor = 0
        var group: [ToolActivity] = []
        var groupAnchor = 0

        func emitText(upTo end: Int) {
            guard end > cursor else { return }
            let slice = String(characters[cursor ..< end])
            if !slice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(slice, offset: cursor))
            }
            cursor = end
        }
        func emitGroup() {
            guard !group.isEmpty else { return }
            segments.append(.tools(group, offset: groupAnchor))
            group = []
        }

        for activity in activities {
            let anchor = min(max(activity.anchorOffset, cursor), characters.count)
            if group.isEmpty || anchor != groupAnchor {
                emitGroup()
                emitText(upTo: anchor)
                groupAnchor = anchor
            }
            group.append(activity)
        }
        emitGroup()
        emitText(upTo: characters.count)
        return segments
    }

    @ViewBuilder
    private var interleavedTranscript: some View {
        let segments = Self.transcriptSegments(
            content: message.content,
            activities: message.toolActivities
        )
        let lastID = segments.last?.id
        ForEach(segments) { segment in
            switch segment {
            case .text(let slice, _):
                MarkdownContentView(
                    content: isBudgetWarning ? Self.strippingBudgetWarnings(from: slice) : slice,
                    isStreaming: message.isStreaming,
                    showCursor: message.isStreaming && segment.id == lastID,
                    textColor: Design.Colors.coolForeground
                )
                .foregroundStyle(Design.Colors.coolForeground)
                .padding(.vertical, Design.Spacing.xxs)
            case .tools(let group, _):
                ToolActivityRail(
                    activities: group,
                    isStreaming: message.isStreaming && group.contains(where: \.isActive)
                )
            }
        }
    }

    // MARK: - Streaming Components

    @ViewBuilder
    private var streamingText: some View {
        let displayContent = isBudgetWarning
            ? Self.strippingBudgetWarnings(from: message.content)
            : message.content

        MarkdownContentView(
            content: displayContent,
            isStreaming: message.isStreaming,
            showCursor: message.isStreaming,
            textColor: Design.Colors.coolForeground
        )
        .foregroundStyle(Design.Colors.coolForeground)
        .padding(.vertical, Design.Spacing.xxs)
    }

    private var streamingPlaceholder: some View {
        TypingDotsView()
            .padding(.vertical, Design.Spacing.sm)
    }

    private func toolActivityPill(_ label: String) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: Design.Brand.accent, diameter: 6)
            Text(label.uppercased())
                .font(Design.Typography.monoSmall)
                .tracking(Design.Tracking.mono)
                .foregroundStyle(Design.Colors.coolForeground)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xxs + 1)
        .hudPanel(
            cornerRadius: Design.CornerRadius.full,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
    }

    // MARK: - Attachment Grid

    @ViewBuilder
    private func attachmentGrid(_ attachments: [MessageAttachment]) -> some View {
        let columns = attachments.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: Design.Spacing.xxs) {
            ForEach(attachments) { attachment in
                attachmentCell(attachment)
            }
        }
        .frame(maxWidth: 140)
    }

    @ViewBuilder
    private func attachmentCell(_ attachment: MessageAttachment) -> some View {
        let thumbnailImage: UIImage? = {
            if let base64 = attachment.thumbnailBase64,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                return image
            }
            if let localStoragePath = attachment.localStoragePath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: localStoragePath)),
               let image = UIImage(data: data) {
                return image
            }
            return nil
        }()

        if attachment.kind == "image",
           let uiImage = thumbnailImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 120, maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                }
        } else {
            HStack(spacing: Design.Spacing.xxs) {
                Image(systemName: "doc")
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(Design.Brand.accent)
                Text(attachment.fileName)
                    .font(Design.Typography.mono(11, relativeTo: .caption))
                    .foregroundStyle(Design.Colors.coolForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .hudPanel(
                cornerRadius: Design.CornerRadius.md,
                borderColor: Design.Colors.accentTint(0.18),
                fill: Design.Colors.surface
            )
        }
    }

    // MARK: - Agent File Bubbles (#21 Tier 1)

    @ViewBuilder
    private func hermesAttachments(_ attachments: [MessageAttachment]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            ForEach(attachments) { attachment in
                agentFileBubble(attachment)
            }
        }
        .padding(.top, Design.Spacing.xxs)
    }

    /// A tappable file chip that hands the staged file to the system share sheet
    /// (`ShareLink` covers Save to Files, AirDrop, Quick Look, etc.).
    @ViewBuilder
    private func agentFileBubble(_ attachment: MessageAttachment) -> some View {
        if let path = attachment.localStoragePath {
            let url = URL(fileURLWithPath: path)
            ShareLink(item: url) {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "doc.text")
                        .font(.system(size: Design.Size.iconSmall))
                        .foregroundStyle(Design.Brand.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.fileName)
                            .font(Design.Typography.mono(12, relativeTo: .caption))
                            .foregroundStyle(Design.Colors.coolForeground)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(Self.fileSubtitle(for: url, fileName: attachment.fileName))
                            .font(Design.Typography.monoSmall)
                            .tracking(Design.Tracking.mono)
                            .foregroundStyle(Design.Colors.mutedForeground)
                    }

                    Spacer(minLength: Design.Spacing.sm)

                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: Design.Size.iconTiny))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
                .hudPanel(
                    cornerRadius: Design.CornerRadius.md,
                    borderColor: Design.Colors.accentTint(0.18),
                    fill: Design.Colors.surface
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 280, alignment: .leading)
            .accessibilityLabel("Share file \(attachment.fileName)")
        }
    }

    /// "MARKDOWN · 2 KB" style caption — file type from extension, size read
    /// from disk (omitted if unavailable).
    static func fileSubtitle(for url: URL, fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.uppercased()
        let typeLabel = ext.isEmpty ? "FILE" : ext
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return "\(typeLabel) · \(formatted)"
        }
        return typeLabel
    }

    // MARK: - Context Compaction Banner

    private var compactionBanner: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: Design.Size.iconTiny))
                .foregroundStyle(Design.Colors.mutedForeground)

            MonoLabel(
                "Context Compacted",
                size: 9,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.sm)
    }

    // MARK: - Budget Warning Stripping

    /// Strips `[BUDGET WARNING: ...]` lines injected by the Hermes agent into
    /// tool result messages.  These are internal agent housekeeping and should
    /// not be shown to the user verbatim.
    static func strippingBudgetWarnings(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\[BUDGET WARNING:[^\]]*\]"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
