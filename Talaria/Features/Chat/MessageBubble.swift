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
        Text(message.content)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Colors.secondaryForeground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.xxs)
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: Design.Spacing.xxs) {
            if message.isVoiceTranscript {
                voiceTranscriptText(message.content)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(Design.Colors.surface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))

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
                        MarkdownContentView(content: message.content, isStreaming: false)
                            .foregroundStyle(Design.Colors.foreground)
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.vertical, Design.Spacing.sm)
                            .background(Design.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
                    }
                }

                HStack(spacing: Design.Spacing.xxs) {
                    Text(message.timestamp, style: .time)
                        .font(Design.Typography.caption2)
                        .foregroundStyle(Design.Colors.secondaryForeground)

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
                        .foregroundStyle(.red)
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
                if !message.content.isEmpty {
                    streamingText
                } else if message.isStreaming {
                    // Content still empty but tool activities exist — show a subtle placeholder
                    streamingPlaceholder
                }

                if !message.toolActivities.isEmpty {
                    ToolActivityRail(
                        activities: message.toolActivities,
                        isStreaming: message.isStreaming
                    )
                } else if let activity = message.toolActivity {
                    toolActivityPill(activity)
                }

                if let diff = message.codeDiff, !diff.isEmpty {
                    InlineDiffView(diff: diff)
                }

                if !message.isStreaming {
                    Text(message.timestamp, style: .time)
                        .font(Design.Typography.caption2)
                        .foregroundStyle(Design.Colors.secondaryForeground)
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
        Text("Voice Mode")
            .font(Design.Typography.caption2)
            .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.6))
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
            showCursor: message.isStreaming
        )
        .foregroundStyle(Design.Colors.foreground)
        .padding(.vertical, Design.Spacing.xxs)
    }

    private var streamingPlaceholder: some View {
        TypingDotsView()
            .padding(.vertical, Design.Spacing.sm)
    }

    private func toolActivityPill(_ label: String) -> some View {
        Text(label)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Colors.secondaryForeground)
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xxs)
            .background(Design.Colors.surface)
            .clipShape(Capsule())
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
        } else {
            HStack(spacing: Design.Spacing.xxs) {
                Image(systemName: "doc")
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                Text(attachment.fileName)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        }
    }

    // MARK: - Context Compaction Banner

    private var compactionBanner: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Colors.secondaryForeground)

            Text("Context compacted")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
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
