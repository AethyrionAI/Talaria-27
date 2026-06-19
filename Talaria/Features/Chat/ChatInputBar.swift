import Speech
import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var pendingAttachments: [PendingAttachment]
    let isStreaming: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    let onSlashCommand: (SlashCommand, String?) -> Void

    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(TabRouter.self) private var router

    @State private var speechService = LiveSpeechService()
    @State private var dictationBaseText = ""

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        let hasRunnableSlashCommand = isSlashMode && hasText && text.trimmingCharacters(in: .whitespacesAndNewlines) != "/" && !hasAttachments
        return hasRunnableSlashCommand || ((hasText || hasAttachments) && !isSlashMode)
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
                }

                // Text input area
                TextField(
                    speechService.isListening ? "Listening..." : "Reply to Hermes",
                    text: $text,
                    axis: .vertical
                )
                    .accessibilityIdentifier("chat.composer")
                    .accessibilityLabel("Reply to Hermes")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.foreground)
                    .lineLimit(1...5)
                    .focused(isFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            handlePrimaryAction()
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
                            .foregroundStyle(Design.Colors.secondaryForeground)
                            .frame(width: 36, height: 36)
                            .background(Design.Colors.surface)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Add attachment")

                    Spacer()

                    // Dictation mic button
                    if !isStreaming {
                        Button {
                            toggleDictation()
                        } label: {
                            Image(systemName: speechService.isListening ? "stop.fill" : "mic")
                                .font(.system(size: Design.Size.iconMedium, weight: .medium))
                                .foregroundStyle(speechService.isListening ? .red : Design.Colors.secondaryForeground)
                                .frame(width: 36, height: 36)
                                .background(speechService.isListening ? Design.Colors.surface : .clear)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(speechService.isListening ? "Stop dictation" : "Start dictation")
                    }

                    // Talk mode button (right side, before send)
                    if !isStreaming && !speechService.isListening && !canSend {
                        Button {
                            router.isVoiceOverlayPresented = true
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: Design.Size.iconMedium, weight: .medium))
                                .foregroundStyle(Design.Colors.foreground)
                                .frame(width: 36, height: 36)
                                .background(Design.Brand.accent)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Start voice mode")
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Send / Stop button
                    actionButton
                }
                .padding(.horizontal, Design.Spacing.sm)
                .padding(.bottom, Design.Spacing.sm)
            }
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xxl))
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
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbData = attachment.thumbnailData,
                   let uiImage = UIImage(data: thumbData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // File icon fallback
                    VStack(spacing: 4) {
                        Image(systemName: fileIcon(for: attachment.mimeType))
                            .font(.system(size: 20))
                            .foregroundStyle(Design.Colors.secondaryForeground)
                        Text(attachment.fileName)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.Colors.surface)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                    .stroke(Design.Colors.divider, lineWidth: 1)
            )

            // Remove button
            Button {
                withAnimation(Design.Motion.quickResponse) {
                    pendingAttachments.removeAll { $0.id == attachment.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.foreground)
                    .background(Circle().fill(Design.Colors.background).padding(2))
            }
            .offset(x: 6, y: -6)
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
                    .foregroundStyle(Design.Colors.foreground)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Stop generating")
        } else if canSend {
            Button(action: handlePrimaryAction) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Design.Colors.background)
                    .frame(width: 36, height: 36)
                    .background(Design.Brand.accent)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Send message")
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Dictation

    private func toggleDictation() {
        if speechService.isListening {
            speechService.stopListening()
            text = mergedDictationText(speechService.transcript)
            dictationBaseText = ""
        } else {
            Task {
                do {
                    dictationBaseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    try await speechService.startListening()
                } catch {
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
