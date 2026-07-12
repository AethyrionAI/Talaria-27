import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onRetry: ((Message) -> Void)? = nil
    /// #44: true while ANY message in the transcript is streaming — the
    /// history-mutating menu items (Regenerate, Edit & Resend) are hidden so
    /// they can't truncate under an in-flight run. Copy/Share/Select stay.
    var isTranscriptBusy: Bool = false
    /// #44: re-roll a successful Hermes reply (wired by ChatScreen).
    var onRegenerate: ((Message) -> Void)? = nil
    /// #44: truncate a user turn back into the composer (wired by ChatScreen).
    var onEditResend: ((Message) -> Void)? = nil

    @Environment(SpeechOutputService.self) private var speechOutput
    @Environment(TalkStore.self) private var talkStore

    // #4.15: reasoning disclosure. Collapsed by default; per-bubble state.
    @State private var isReasoningExpanded = false
    // #44: "Select Text" opens the raw content in a selectable sheet —
    // long-press is owned by the context menu, so in-bubble `.textSelection`
    // can't coexist with it.
    @State private var isSelectTextPresented = false
    // #99: which reconstructed agent file is open in the preview sheet.
    @State private var previewedAttachment: MessageAttachment?

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
                withBubbleContextMenu(userBubble)
            }
            .padding(.horizontal, Design.Spacing.md)
        } else {
            HStack(alignment: .top, spacing: Design.Spacing.xs) {
                withBubbleContextMenu(hermesMessage)
                Spacer(minLength: Design.Spacing.xxl)
            }
            .padding(.horizontal, Design.Spacing.md)
        }
    }

    // MARK: - Context Menu (#44)

    /// Long-press menu on settled user/Hermes bubbles. A streaming bubble gets
    /// no menu at all — its content is still moving, so copy would race the
    /// stream and regenerate has no settled turn to re-roll.
    @ViewBuilder
    private func withBubbleContextMenu<Content: View>(_ content: Content) -> some View {
        if message.isStreaming {
            content
        } else {
            content
                .contextMenu { bubbleMenuItems }
                .sheet(isPresented: $isSelectTextPresented) {
                    SelectableTextSheet(text: copyableText)
                }
        }
    }

    @ViewBuilder
    private var bubbleMenuItems: some View {
        if !copyableText.isEmpty {
            Button {
                UIPasteboard.general.string = copyableText
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            ShareLink(item: copyableText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                isSelectTextPresented = true
            } label: {
                Label("Select Text", systemImage: "text.cursor")
            }
        }
        // Re-roll: successful Hermes replies only (failed ones keep the inline
        // Regenerate button), exact senders only — voice-transcript rows are
        // not real turns. Hidden while any run streams (truncation hazard).
        if message.sender == .hermes,
           message.status == .delivered,
           !isTranscriptBusy,
           let onRegenerate {
            Divider()
            Button {
                onRegenerate(message)
            } label: {
                Label("Regenerate", systemImage: "arrow.counterclockwise")
            }
        }
        // Edit & Resend: real user turns that aren't mid-flight.
        if message.sender == .user,
           message.status != .sending,
           !isTranscriptBusy,
           let onEditResend {
            Divider()
            Button {
                onEditResend(message)
            } label: {
                Label("Edit & Resend", systemImage: "pencil")
            }
        }
    }

    /// What Copy/Share/Select operate on: the raw content, except the
    /// synthetic "[N attachment(s)]" placeholder, which isn't user prose.
    private var copyableText: String {
        if !message.attachments.isEmpty,
           message.content.range(of: #"^\[\d+ attachment"#, options: .regularExpression) != nil {
            return ""
        }
        return message.content
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
                // #4.15: reasoning sits above the answer — where it happened.
                // While still content-less the live line renders inside the
                // streaming placeholder instead, so don't double it up here.
                // (Presence/blankness is the disclosure's own guard.)
                if !(message.isStreaming && message.content.isEmpty) {
                    reasoningDisclosure
                }
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
                    HStack(spacing: Design.Spacing.sm) {
                        Text(message.timestamp, style: .time)
                            .font(Design.Typography.monoSmall)
                            .tracking(Design.Tracking.mono)
                            .foregroundStyle(Design.Colors.mutedForeground)

                        // #27: producing-brain tag — transcript honesty across
                        // brain switches and reconnects. Hermes (the default)
                        // stays untagged; on-device / PCC replies are marked.
                        if let brainTag = ChatBackendRouter.transcriptTag(forMessageBrain: message.brain) {
                            MonoLabel(brainTag, size: 8, tracking: Design.Tracking.mono,
                                      color: Design.Colors.dimForeground)
                        }

                        // Read-aloud (#2) — hidden while a Talk session owns
                        // the audio session.
                        if !message.content.isEmpty && !talkStore.isSessionActive {
                            speakerToggle
                        }
                    }

                    // #46: the turn receipt — real usage from this run's
                    // `run.completed`, wall-clock duration, and a dollar
                    // figure only when the serving model's pricing is known
                    // (the "~" marks it as an estimate). Absent entirely for
                    // unmetered turns — no placeholders in a receipt.
                    if let usage = message.usage {
                        turnReceipt(usage)
                    }
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

    // MARK: - Turn Receipt (#46)

    private func turnReceipt(_ usage: TokenUsage) -> some View {
        let cost = ModelPricingCatalog.shared.estimatedCost(for: usage, model: message.servingModel)
        let line = TurnReceiptFormat.receiptLine(
            usage: usage,
            duration: message.turnDuration,
            cost: cost
        )
        return MonoLabel(line, size: 8, tracking: Design.Tracking.mono,
                         color: Design.Colors.dimForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(
                "Turn receipt: \(usage.promptTokens) input tokens, "
                    + "\(usage.completionTokens) output tokens"
                    + (message.turnDuration.map { ", \(Int($0.rounded())) seconds" } ?? "")
                    + (cost.map { ", estimated cost \(TurnReceiptFormat.costLabel($0))" } ?? "")
            )
    }

    // MARK: - Read-Aloud (#2)

    private var isSpeakingThisMessage: Bool {
        speechOutput.speakingMessageID == message.id
    }

    private var speakerToggle: some View {
        Button {
            if isSpeakingThisMessage {
                speechOutput.stop()
            } else {
                speechOutput.speak(message.content, messageID: message.id)
            }
        } label: {
            Image(systemName: isSpeakingThisMessage ? "speaker.slash.fill" : "speaker.wave.2")
                .font(.system(size: Design.Size.iconTiny))
                .foregroundStyle(isSpeakingThisMessage ? Design.Brand.accent : Design.Colors.mutedForeground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeakingThisMessage ? "Stop reading aloud" : "Read aloud")
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
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            TypingDotsView()

            // #4.15: while the model is still reasoning (no answer text yet),
            // show the newest `_thinking` line verbatim under the dots.
            if let reasoning = message.reasoning,
               let line = Self.lastReasoningLine(reasoning) {
                Text(line)
                    .font(Design.Typography.monoSmall)
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.mutedForeground)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Design.Spacing.sm)
    }

    // MARK: - Reasoning Disclosure (#4.15)

    /// Collapsed: chevron + one line — the on-device condensation when
    /// available (#4.8), else the last raw reasoning line. Expanded: the raw
    /// reasoning verbatim. Owns the presence check, and requires actual words:
    /// a whitespace-only `_thinking` stream must not render a blank row.
    @ViewBuilder
    private var reasoningDisclosure: some View {
        if let reasoning = message.reasoning,
           !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Button {
                    withAnimation(Design.Motion.standard) { isReasoningExpanded.toggle() }
                } label: {
                    HStack(spacing: Design.Spacing.xs) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Design.Colors.dimForeground)
                            .rotationEffect(.degrees(isReasoningExpanded ? 90 : 0))

                        MonoLabel(
                            "Reasoning",
                            size: 9,
                            tracking: Design.Tracking.monoWide,
                            color: Design.Colors.dimForeground
                        )

                        if !isReasoningExpanded, let line = collapsedReasoningLine {
                            Text(line)
                                .font(Design.Typography.monoSmall)
                                .tracking(Design.Tracking.mono)
                                .foregroundStyle(Design.Colors.mutedForeground)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isReasoningExpanded ? "Hide reasoning" : "Show reasoning")

                if isReasoningExpanded {
                    Text(reasoning)
                        .font(Design.Typography.monoSmall)
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.Spacing.sm)
                        .hudPanel(
                            cornerRadius: Design.CornerRadius.md,
                            borderColor: Design.Colors.accentTint(0.12),
                            fill: Design.Colors.surface
                        )
                }
            }
        }
    }

    /// The one-liner for the collapsed row: prefer the on-device condensation
    /// (#4.8); fall back to the last raw line so the row is never blank.
    private var collapsedReasoningLine: String? {
        if let summary = message.reasoningSummary, !summary.isEmpty { return summary }
        return message.reasoning.flatMap(Self.lastReasoningLine)
    }

    /// Last non-blank line of the reasoning stream — the "what is it working
    /// out right now" line shown verbatim while streaming, and the collapsed
    /// fallback afterwards. Scans backward without splitting: this runs on
    /// every render of a streaming bubble whose reasoning grows per delta, so
    /// an O(whole-string) split here would be O(N²) across a long think.
    static func lastReasoningLine(_ reasoning: String) -> String? {
        var searchEnd = reasoning.endIndex
        while searchEnd > reasoning.startIndex {
            let lineStart: String.Index
            if let newline = reasoning[..<searchEnd].lastIndex(of: "\n") {
                lineStart = reasoning.index(after: newline)
            } else {
                lineStart = reasoning.startIndex
            }
            let trimmed = reasoning[lineStart ..< searchEnd].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
            guard lineStart > reasoning.startIndex else { return nil }
            searchEnd = reasoning.index(before: lineStart)
        }
        return nil
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
            // Doc/text chip — what was ACTUALLY sent: a file whose text was
            // inlined into the turn (#43), including OCR-extracted
            // `…extracted.md` attachments (#8) and voice-memo transcripts
            // (#9). Images that shipped as image_url parts render as
            // thumbnails in the branch above; a text-inlined file must never
            // masquerade as an image.
            HStack(spacing: Design.Spacing.xxs) {
                // Voice memo (#9): the transcript shipped; the audio stays
                // playable from the bubble — but only while the local file
                // actually exists (no dead play button, real data only).
                if let audioPath = attachment.voiceMemoAudioPath,
                   VoiceMemoPlayer.canPlay(path: audioPath) {
                    let player = VoiceMemoPlayer.shared
                    Button {
                        player.togglePlayback(path: audioPath)
                    } label: {
                        Image(systemName: player.isPlaying(path: audioPath) ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: Design.Size.iconMedium))
                            .foregroundStyle(Design.Brand.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying(path: audioPath) ? "Stop voice memo" : "Play voice memo")
                }
                Image(systemName: attachmentChipIcon(for: attachment))
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

    private func attachmentChipIcon(for attachment: MessageAttachment) -> String {
        if attachment.voiceMemoAudioPath != nil { return "waveform" }
        return attachment.mimeType == "application/pdf" ? "doc.richtext" : "doc.text"
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
        // #99: tap → full-screen in-app preview.
        .sheet(item: $previewedAttachment) { attachment in
            AgentFilePreviewSheet(attachment: attachment)
        }
    }

    /// A tappable file chip that opens the in-app preview sheet (#99); the
    /// share affordance lives in the sheet's toolbar (preview AND share).
    @ViewBuilder
    private func agentFileBubble(_ attachment: MessageAttachment) -> some View {
        if let path = attachment.localStoragePath {
            let url = URL(fileURLWithPath: path)
            Button {
                previewedAttachment = attachment
            } label: {
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

                    Image(systemName: "eye")
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
            .accessibilityLabel("Preview file \(attachment.fileName)")
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

// MARK: - Select Text Sheet (#44)

/// Raw message text with system text selection. Plain text on purpose: the
/// selection surface should hand over exactly what Copy would, not the
/// markdown-rendered view.
private struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HUDScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    Text(text)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.foreground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.Spacing.md)
                }
            }
            .navigationTitle("Select Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Typography.mono(13, weight: .medium))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
        }
    }
}
