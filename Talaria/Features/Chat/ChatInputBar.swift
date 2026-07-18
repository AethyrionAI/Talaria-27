import Speech
import os
import SwiftUI
import UIKit

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var pendingAttachments: [PendingAttachment]
    let isStreaming: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    let onSlashCommand: (SlashCommand, String?) -> Void
    let onPasteImage: (UIImage) -> Void

    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(TabRouter.self) private var router
    @Environment(SettingsStore.self) private var settingsStore

    @State private var speechService = LiveSpeechService()
    @State private var dictationBaseText = ""

    // Text extraction (#8): ids of chips with an OCR pass in flight, and the
    // last failure surfaced as an alert.
    @State private var extractingAttachmentIDs: Set<UUID> = []
    @State private var extractionFailureMessage: String?

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        let hasRunnableSlashCommand = isSlashMode && hasText && text.trimmingCharacters(in: .whitespacesAndNewlines) != "/" && !hasAttachments
        return (hasRunnableSlashCommand || ((hasText || hasAttachments) && !isSlashMode))
            && !sendBlockedByAttachments
    }

    /// Send is held while (a) a staged attachment has no wire representation —
    /// a raw PDF must be extracted or removed, otherwise it would silently
    /// never transmit, which is exactly #43's pathology — or (b) an extraction
    /// is in flight for a staged chip. (b) is a deliberate choice over racing
    /// the original image out mid-OCR: the user explicitly asked for text, so
    /// the send waits the second or two extraction takes. (#8)
    private var sendBlockedByAttachments: Bool {
        pendingAttachments.contains { !$0.isTransmittable }
            || pendingAttachments.contains { extractingAttachmentIDs.contains($0.id) }
    }

    private var isSlashMode: Bool {
        text.hasPrefix("/")
    }

    /// Parses the command and any trailing argument from the text field.
    private var parsedSlashInput: (command: String, argument: String?) {
        let raw = String(text.dropFirst()).lowercased()
        let parts = raw.split(separator: " ", maxSplits: 1)
        let cmd = parts.first.map(String.init) ?? raw
        let arg = parts.count > 1 ? String(parts[1]) : nil
        return (cmd, arg)
    }

    /// Uses the dynamic catalog from ChatStore (fetched from the Hermes host).
    /// Falls back to the built-in list if the catalog hasn't loaded yet.
    private var filteredCommands: [SlashCommand] {
        let query = parsedSlashInput.command.lowercased()
        let argument = parsedSlashInput.argument?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = chatStore.commandCatalog.filter(\.showInAutocomplete)

        if query.isEmpty {
            return all.filter { $0.suggestedArgument == nil }
        }

        if let exact = all.first(where: { $0.name == query && $0.suggestedArgument == nil }), exact.acceptsArgument {
            let argumentSuggestions = all.filter { command in
                command.name == query
                    && command.suggestedArgument != nil
                    && (argument == nil
                        || argument!.isEmpty
                        || command.suggestedArgument!.lowercased().hasPrefix(argument!))
            }
            if !argumentSuggestions.isEmpty {
                return argumentSuggestions
            }
            return [exact]
        }

        return all.filter {
            $0.suggestedArgument == nil && $0.name.hasPrefix(query)
        }
    }

    var body: some View {
        VStack(spacing: Design.Spacing.xs) {
            if isSlashMode && !filteredCommands.isEmpty {
                SlashCommandMenu(commands: filteredCommands) { command in
                    let arg = command.suggestedArgument ?? (command.acceptsArgument ? parsedSlashInput.argument : nil)
                    text = ""
                    onSlashCommand(command, arg)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Composer container
            VStack(spacing: 0) {
                // Attachment preview strip
                if !pendingAttachments.isEmpty {
                    attachmentPreviewStrip
                    if pendingAttachments.contains(where: { !$0.isTransmittable }) {
                        untransmittableHint
                    }
                }

                // Text input area
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .accessibilityIdentifier("chat.composer")
                        .accessibilityLabel("Reply to Hermes")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.foreground)
                        .tint(Design.Brand.accent)
                        .focused(isFocused)
                        // Lane J (J-4): hardware-keyboard Return sends;
                        // ⇧Return (or any modified Return) falls through and
                        // inserts a newline. Software keyboards never emit
                        // key presses, so on-screen Return behavior — and
                        // all of iPhone-without-a-keyboard — is untouched.
                        .onKeyPress(keys: [.return], phases: .down) { press in
                            guard press.modifiers.isDisjoint(with: [.shift, .option, .control, .command]) else {
                                return .ignored
                            }
                            guard !isStreaming, canSend else { return .ignored }
                            handlePrimaryAction()
                            return .handled
                        }
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(minHeight: 22, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        // #4: .complete froze the device on iOS 27 beta 2
                        // (broken PresentWritingToolsResult handoff), so the
                        // full tier is opt-in via the Developer flag until a
                        // beta fixes it. .automatic = today's safe baseline.
                        .writingToolsBehavior(
                            settingsStore.settings.composerWritingToolsEnabled ? .complete : .automatic
                        )

                    if text.isEmpty {
                        Text(speechService.isListening ? "Listening…" : "Message Hermes…")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.mutedForeground)
                            .allowsHitTesting(false)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, pendingAttachments.isEmpty ? Design.Spacing.sm : Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xs)

                // Bottom action bar
                HStack(spacing: Design.Spacing.xs) {
                    // + Attachment button
                    Button(action: onAttach) {
                        Image(systemName: "plus")
                            .font(.system(size: Design.Size.iconMedium, weight: .medium))
                            .foregroundStyle(Design.Colors.mutedForeground)
                            .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    // Lane J (J-5): pointer affordance — inert without a pointer.
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Add attachment")

                    // Paste image from clipboard (#31)
                    if !isStreaming {
                        Button {
                            pasteImageFromClipboard()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                                .foregroundStyle(Design.Colors.mutedForeground)
                                .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .hoverEffect(.highlight)
                        .accessibilityLabel("Paste image")
                        .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    // Dictation mic button
                    if !isStreaming {
                        Button {
                            toggleDictation()
                        } label: {
                            Image(systemName: speechService.isListening ? "stop.fill" : "mic")
                                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                                .foregroundStyle(speechService.isListening ? Design.Colors.danger : Design.Colors.mutedForeground)
                                .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                                .background {
                                    if speechService.isListening {
                                        Circle()
                                            .fill(Design.Colors.accentTint(0.1))
                                            .frame(width: 36, height: 36)
                                            .overlay(Circle().strokeBorder(Design.Colors.danger.opacity(0.4), lineWidth: 1).frame(width: 36, height: 36))
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .hoverEffect(.highlight)
                        .accessibilityLabel(speechService.isListening ? "Stop dictation" : "Start dictation")
                    }

                    // Talk mode button (right side, before send). Hidden while
                    // send is blocked on attachments (#8) — the dimmed send
                    // arrow takes that slot to explain the held state.
                    if !isStreaming && !speechService.isListening && !canSend && !sendBlockedByAttachments {
                        Button {
                            router.isVoiceOverlayPresented = true
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                                .foregroundStyle(Design.Brand.accentBright)
                                .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                                .background {
                                    Circle()
                                        .fill(Design.Colors.accentTint(0.12))
                                        .frame(width: 36, height: 36)
                                        .overlay(Circle().strokeBorder(Design.Colors.strongBorder, lineWidth: 1).frame(width: 36, height: 36))
                                }
                                .contentShape(Rectangle())
                        }
                        .hoverEffect(.highlight)
                        .accessibilityLabel("Start voice mode")
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Send / Stop button
                    actionButton
                }
                .padding(.horizontal, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xs)
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.xl,
                borderColor: Design.Colors.strongBorder,
                fill: Design.Colors.surface,
                innerGlow: true
            )
            .padding(.horizontal, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.md)
        }
        .animation(Design.Motion.quickResponse, value: isSlashMode)
        .animation(Design.Motion.quickResponse, value: isStreaming)
        .animation(Design.Motion.quickResponse, value: canSend)
        .onAppear {
            speechService.onTranscriptChange = { partialTranscript in
                text = mergedDictationText(partialTranscript)
            }
            speechService.onAutoStop = { finalTranscript in
                text = mergedDictationText(finalTranscript)
                dictationBaseText = ""
            }
        }
        .alert(
            "Text extraction failed",
            isPresented: Binding(
                get: { extractionFailureMessage != nil },
                set: { if !$0 { extractionFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(extractionFailureMessage ?? "")
        }
    }

    // MARK: - Attachment Preview Strip

    private var attachmentPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.sm) {
                ForEach(pendingAttachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.xxs)
        }
    }

    private func attachmentThumbnail(_ attachment: PendingAttachment) -> some View {
        let isExtracting = extractingAttachmentIDs.contains(attachment.id)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let thumbData = attachment.thumbnailData,
                   let uiImage = UIImage(data: thumbData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // File icon fallback — this is also what an extracted-text
                    // chip shows (no thumbnail is carried over, #8), so the
                    // flip from image thumb to text-doc chip is visible.
                    // Voice memos (#9) get a waveform: transcript ships, audio
                    // stays local for playback.
                    VStack(spacing: 4) {
                        Image(systemName: attachment.isVoiceMemo ? "waveform" : fileIcon(for: attachment.mimeType))
                            .font(.system(size: 20))
                            .foregroundStyle(Design.Brand.accent)
                        Text(attachment.fileName)
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.coolForeground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.Colors.surface)
                }
            }
            .frame(width: Design.Size.thumbnailSmall, height: Design.Size.thumbnailSmall)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                    .strokeBorder(Design.Colors.hairline, lineWidth: 1)
            )
            .overlay {
                // OCR-in-flight scrim (#8)
                if isExtracting {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                        .fill(Design.Colors.scrim)
                    ProgressView()
                        .controlSize(.small)
                        .tint(Design.Brand.accent)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Forge badge: this chip has no wire representation yet — an
                // un-extracted PDF never *looks* sendable (#8).
                if !attachment.isTransmittable && !isExtracting {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: Design.Size.iconTiny))
                        .foregroundStyle(Design.Brand.forge)
                        .padding(3)
                        .background(Circle().fill(Design.Colors.background))
                        .offset(x: 4, y: 4)
                        .accessibilityLabel("Not sendable yet — extract text first")
                }
            }
            .contextMenu {
                // Explicit per-attachment extraction (#8) — never automatic;
                // the default for images stays "send the actual image".
                if attachment.isExtractable && !isExtracting {
                    Button {
                        extractText(from: attachment)
                    } label: {
                        Label("Extract text", systemImage: "text.viewfinder")
                    }
                }
                // Local playback of a staged voice memo's audio (#9) — only
                // while the file actually exists (no dead buttons).
                if let audioPath = attachment.voiceMemoAudioPath,
                   VoiceMemoPlayer.canPlay(path: audioPath) {
                    Button {
                        VoiceMemoPlayer.shared.togglePlayback(path: audioPath)
                    } label: {
                        Label(
                            VoiceMemoPlayer.shared.isPlaying(path: audioPath) ? "Stop playback" : "Play memo",
                            systemImage: VoiceMemoPlayer.shared.isPlaying(path: audioPath) ? "stop.circle" : "play.circle"
                        )
                    }
                }
                Button(role: .destructive) {
                    withAnimation(Design.Motion.quickResponse) {
                        pendingAttachments.removeAll { $0.id == attachment.id }
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }

            // Remove button
            Button {
                withAnimation(Design.Motion.quickResponse) {
                    pendingAttachments.removeAll { $0.id == attachment.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .background(Circle().fill(Design.Colors.background).padding(2))
            }
            .offset(x: 6, y: -6)
        }
    }

    /// Forge banner under the chips while a staged file has no wire shape
    /// (un-extracted PDF): send is held until it's extracted or removed, so
    /// an untransmittable attachment can never silently ride a sent message (#8).
    private var untransmittableHint: some View {
        HStack(spacing: Design.Spacing.xxs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Design.Size.iconTiny))
                .foregroundStyle(Design.Brand.forge)
            MonoLabel(
                "PDF SENDS AS EXTRACTED TEXT — HOLD CHIP TO EXTRACT",
                size: 9,
                tracking: Design.Tracking.mono,
                color: Design.Brand.forge
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xxs)
    }

    // MARK: - Text Extraction (#8)

    /// Runs on-device OCR (`DocumentTextExtractor`) and swaps the staged
    /// image/PDF for the resulting text attachment IN PLACE, so the chip shows
    /// exactly what will transmit. If the user removes the chip mid-OCR, the
    /// result is discarded rather than re-staged.
    private func extractText(from attachment: PendingAttachment) {
        extractingAttachmentIDs.insert(attachment.id)
        Task {
            do {
                let extracted = try await DocumentTextExtractor.extractText(from: attachment)
                if let index = pendingAttachments.firstIndex(where: { $0.id == attachment.id }) {
                    withAnimation(Design.Motion.quickResponse) {
                        pendingAttachments[index] = PendingAttachment.extractedText(from: attachment, text: extracted)
                    }
                }
            } catch {
                extractionFailureMessage = error.localizedDescription
            }
            extractingAttachmentIDs.remove(attachment.id)
        }
    }

    private func fileIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }

    @ViewBuilder
    private var actionButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .frame(width: 38, height: 38)
                    .background(Design.Colors.accentTint(0.12), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.strongBorder, lineWidth: 1)
                    }
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .hoverEffect(.highlight)
            .accessibilityLabel("Stop generating")
        } else if canSend {
            Button(action: handlePrimaryAction) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(
                            colors: [Design.Colors.accentTint(0.3), Design.Colors.accentTint(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.accentTint(0.6), lineWidth: 1)
                    }
                    .hudGlow(Design.Brand.accent, radius: 16, strength: 0.4)
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .hoverEffect(.highlight)
            .accessibilityLabel("Send message")
            .transition(.scale.combined(with: .opacity))
        } else if sendBlockedByAttachments {
            // Dimmed, inert send arrow: content is staged but not yet
            // transmittable (un-extracted PDF, or OCR in flight). Paired with
            // the forge hint banner so the held state is self-explanatory (#8).
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Design.Colors.mutedForeground)
                .frame(width: 38, height: 38)
                .background(Design.Colors.surface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                }
                .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                .accessibilityLabel("Send unavailable — extract text from or remove the attachment")
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Clipboard

    /// Reads an image off the system pasteboard and routes it through the same
    /// attachment pipeline the photo picker uses, so pasted and picked images are
    /// indistinguishable downstream (#31).
    private func pasteImageFromClipboard() {
        guard let image = UIPasteboard.general.image else { return }
        onPasteImage(image)
    }

    // MARK: - Dictation

    private static let dictationLogger = Logger(subsystem: "org.aethyrion.talaria", category: "Dictation")

    private func toggleDictation() {
        if speechService.isListening {
            speechService.stopListening()
            text = mergedDictationText(speechService.transcript)
            dictationBaseText = ""
        } else {
            Task {
                do {
                    dictationBaseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    Self.dictationLogger.notice("dictation start requested")
                    try await speechService.startListening()
                    Self.dictationLogger.notice("dictation listening")
                } catch {
                    // #131: this catch used to swallow the failure silently —
                    // the mic button just 'did nothing'. Name the error so the
                    // next device tap identifies the culprit.
                    Self.dictationLogger.notice("dictation start FAILED: \(String(describing: error), privacy: .public)")
                    dictationBaseText = ""
                }
            }
        }
    }

    private func handlePrimaryAction() {
        if speechService.isListening {
            speechService.stopListening()
            text = mergedDictationText(speechService.transcript)
            dictationBaseText = ""
        }
        onSend()
    }

    private func mergedDictationText(_ transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = dictationBaseText.trimmingCharacters(in: .whitespacesAndNewlines)

        if base.isEmpty { return trimmedTranscript }
        if trimmedTranscript.isEmpty { return base }
        return "\(base) \(trimmedTranscript)"
    }
}
