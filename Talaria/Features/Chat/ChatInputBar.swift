import Speech
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
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .accessibilityIdentifier("chat.composer")
                        .accessibilityLabel("Reply to Hermes")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.foreground)
                        .tint(Design.Brand.accent)
                        .focused(isFocused)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(minHeight: 22, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .writingToolsBehavior(.complete)

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
                        .accessibilityLabel(speechService.isListening ? "Stop dictation" : "Start dictation")
                    }

                    // Talk mode button (right side, before send)
                    if !isStreaming && !speechService.isListening && !canSend {
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
            .accessibilityLabel("Send message")
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
