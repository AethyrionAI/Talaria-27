import SwiftUI

struct ChatScreen: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var messageText = ""
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var showClearConfirmation = false
    @State private var showStatusCard = false
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isComposerFocused: Bool

    @State private var showAttachmentPicker = false
    private let thinkingIndicatorID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if hostStore.isHostOnline == false {
                    hostOfflineBanner
                }
                messageList
                ChatInputBar(
                    text: $messageText,
                    pendingAttachments: $pendingAttachments,
                    isStreaming: chatStore.isStreaming,
                    isFocused: $isComposerFocused,
                    onSend: sendMessage,
                    onStop: { chatStore.cancelStreaming() },
                    onAttach: { showAttachmentPicker = true },
                    onSlashCommand: handleSlashCommand
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            chatStore.setPollingEnabled(true)
            await hostStore.refresh()
            await chatStore.loadConversationIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await hostStore.refresh()
            }
        }
        .onDisappear {
            chatStore.setPollingEnabled(false)
        }
        .onChange(of: chatStore.conversation?.messages.count ?? 0) {
            scrollToBottom()
        }
        .onChange(of: chatStore.pendingMessageSentAt) {
            scrollToBottom()
        }
        .onChange(of: chatStore.streamingMessageID) { old, new in
            if old != nil && new == nil && settingsStore.settings.hapticFeedbackEnabled {
                HapticEngine.responseReceived()
            }
        }
        .confirmationDialog(
            "Clear Conversation",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task { await performClear() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will archive the current conversation and start a new session. This cannot be undone.")
        }
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentPickerSheet { result in
                handleAttachmentResult(result)
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            GlassCircleButton(icon: "gearshape.fill") {
                router.presentSheet(.settings)
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Design.Spacing.md) {
                    if let messages = chatStore.conversation?.messages {
                        ForEach(messages) { message in
                            MessageBubble(message: message) { failedMessage in
                                Task { await chatStore.retryMessage(failedMessage) }
                            }
                            .id(message.id)
                        }
                    }

                    if let sentAt = chatStore.pendingMessageSentAt,
                       chatStore.streamingMessageID == nil {
                        ThinkingIndicatorView(startTime: sentAt)
                            .id(thinkingIndicatorID)
                            .transition(.opacity)
                    }

                    if showStatusCard {
                        StatusCardView(
                            isHostOnline: hostStore.isHostOnline,
                            messageCount: chatStore.conversation?.messages.count ?? 0,
                            conversationID: chatStore.conversation?.id,
                            tokenUsage: chatStore.lastTokenUsage,
                            dismissAction: { showStatusCard = false }
                        )
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, Design.Spacing.md)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .redacted(reason: chatStore.isLoading ? .placeholder : [])
            .onTapGesture {
                isComposerFocused = false
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    private var hostOfflineBanner: some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text("Hermes host offline")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Text("Messages will queue until your Hermes host reconnects.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button("Settings") {
                router.presentSheet(.settings)
            }
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
    }

    // MARK: - Actions

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !content.isEmpty || !attachments.isEmpty else { return }
        messageText = ""
        pendingAttachments = []

        if settingsStore.settings.hapticFeedbackEnabled {
            HapticEngine.messageSent()
        }

        Task {
            await chatStore.sendMessage(content, attachments: attachments)
            scrollToBottom()
        }
    }

    func handleAttachmentResult(_ result: AttachmentResult) {
        guard pendingAttachments.count < PendingAttachment.maxAttachmentsPerMessage else { return }
        switch result {
        case .image(let image):
            if let attachment = PendingAttachment.image(image) {
                pendingAttachments.append(attachment)
            }
        case .file(let url):
            if let attachment = PendingAttachment.file(at: url) {
                pendingAttachments.append(attachment)
            }
        }
    }

    private func handleSlashCommand(_ command: SlashCommand, _ argument: String?) {
        // Agent pass-through: send the raw slash command text as a chat message.
        // The Hermes agent processes it natively — same as Discord/Telegram.
        guard command.isLocal else {
            let messageText: String
            if let arg = argument?.trimmingCharacters(in: .whitespacesAndNewlines), !arg.isEmpty {
                messageText = "/\(command.name) \(arg)"
            } else {
                messageText = "/\(command.name)"
            }
            Task { await sendSlashAsMessage(messageText) }
            return
        }

        // Local commands handled by the iOS app directly.
        switch command.name {
        case "new", "reset", "clear":
            showClearConfirmation = true

        case "history":
            showConversationHistory()

        case "save":
            chatStore.exportConversationToFile()
            appendSystemMessage("Conversation saved to Documents folder.")

        case "retry":
            Task { await performRetry() }

        case "undo":
            performUndo()

        case "title":
            if let name = argument?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                chatStore.setConversationTitle(name)
                appendSystemMessage("Session title set: \(name)")
            } else {
                let current = chatStore.conversation?.title ?? "Hermes"
                let id = chatStore.conversation.map { String($0.id.uuidString.prefix(8)) } ?? "—"
                appendSystemMessage("Session ID: \(id)…\nTitle: \(current)\nUsage: /title <your session title>")
            }

        default:
            break
        }
    }

    /// Sends a slash command as a regular chat message to the Hermes agent.
    private func sendSlashAsMessage(_ text: String) async {
        await chatStore.sendMessage(text, attachments: [])
        scrollToBottom()
    }

    private func performClear() async {
        do {
            try await chatStore.clearConversation()
            showStatusCard = false
        } catch {
            // Conversation unchanged on failure — user can retry
        }
    }

    private func performRetry() async {
        guard let messages = chatStore.conversation?.messages, !messages.isEmpty else {
            appendSystemMessage("No messages to retry.")
            return
        }

        // Find the last user message
        guard let lastUserIdx = messages.lastIndex(where: { $0.sender == .user }) else {
            appendSystemMessage("No user message found to retry.")
            return
        }

        let lastUserMessage = messages[lastUserIdx]
        let lastUserContent = lastUserMessage.content
        let attachments = lastUserMessage.attachments.compactMap(PendingAttachment.restore)
        let normalizedContent: String
        if !lastUserMessage.attachments.isEmpty,
           lastUserContent.range(of: #"^\[\d+ attachment"#, options: .regularExpression) != nil {
            normalizedContent = ""
        } else {
            normalizedContent = lastUserContent
        }

        // Remove everything from the last user message onward (user msg + assistant response + tool msgs)
        chatStore.conversation?.messages.removeSubrange(lastUserIdx...)

        appendSystemMessage("Retrying: \"\(String(lastUserContent.prefix(60)))\(lastUserContent.count > 60 ? "..." : "")\"")

        // Re-send the message through the full pipeline
        await chatStore.sendMessage(normalizedContent, attachments: attachments)
        scrollToBottom()
    }

    private func performUndo() {
        guard let messages = chatStore.conversation?.messages, !messages.isEmpty else {
            appendSystemMessage("No messages to undo.")
            return
        }

        // Walk backwards to find the last user message
        guard let lastUserIdx = messages.lastIndex(where: { $0.sender == .user }) else {
            appendSystemMessage("No user message found to undo.")
            return
        }

        let removedContent = messages[lastUserIdx].content
        let removedCount = messages.count - lastUserIdx

        // Truncate history to before the last user message
        chatStore.conversation?.messages.removeSubrange(lastUserIdx...)

        let remaining = chatStore.conversation?.messages.count ?? 0
        appendSystemMessage("Undid \(removedCount) message\(removedCount == 1 ? "" : "s"). Removed: \"\(String(removedContent.prefix(60)))\(removedContent.count > 60 ? "..." : "")\"\n\(remaining) message\(remaining == 1 ? "" : "s") remaining.")
    }

    private func showConversationHistory() {
        guard let messages = chatStore.conversation?.messages, !messages.isEmpty else {
            appendSystemMessage("No conversation history yet.")
            return
        }

        let previewLimit = 200
        var lines: [String] = ["── Conversation History ──"]
        var visibleIndex = 0

        for msg in messages {
            guard msg.sender == .user || msg.sender == .hermes else { continue }
            visibleIndex += 1
            let role = msg.sender == .user ? "You" : "Hermes"
            let preview = msg.content.prefix(previewLimit)
            let suffix = msg.content.count > previewLimit ? "..." : ""
            lines.append("[\(role) #\(visibleIndex)] \(preview)\(suffix)")
        }

        lines.append("\(visibleIndex) visible message\(visibleIndex == 1 ? "" : "s"), \(messages.count) total")
        appendSystemMessage(lines.joined(separator: "\n"))
    }

    private func appendSystemMessage(_ text: String) {
        let msg = Message(sender: .system, content: text, status: .delivered)
        chatStore.conversation?.messages.append(msg)
        scrollToBottom()
    }

    private func scrollToBottom() {
        let targetID: UUID
        if chatStore.pendingMessageSentAt != nil {
            targetID = thinkingIndicatorID
        } else if let lastID = chatStore.conversation?.messages.last?.id {
            targetID = lastID
        } else {
            return
        }
        withAnimation(Design.Motion.standard) {
            scrollProxy?.scrollTo(targetID, anchor: .bottom)
        }
    }
}
