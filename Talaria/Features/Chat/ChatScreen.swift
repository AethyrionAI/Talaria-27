import SwiftUI

struct ChatScreen: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
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
                if pairingStore.isPaired, hostStore.connectionState != .online {
                    connectionBanner
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
            guard chatStore.streamingMessageID == nil else { return }
            scrollToBottom()
        }
        .onChange(of: chatStore.pendingMessageSentAt) {
            guard chatStore.streamingMessageID == nil else { return }
            scrollToBottom()
        }
        .onChange(of: chatStore.streamingMessageID) { old, new in
            if let new, old == nil {
                scrollToResponseTop(new)
            }
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
        ToolbarItem(placement: .topBarLeading) {
            modelStatusChip
        }
        ToolbarItem(placement: .topBarTrailing) {
            GlassCircleButton(icon: "gearshape", accessibilityLabel: "Open settings") {
                router.presentSheet(.settings)
            }
        }
    }

    @State private var showContextPopover = false

    private var displayedModelName: String? {
        chatStore.activeModelName ?? hostStore.currentHost?.hermesModel
    }

    private var effectiveContextWindow: Int? {
        chatStore.resolvedContextWindow(fallbackModelName: displayedModelName)
    }

    private var currentContextTokens: Int? {
        chatStore.currentContextTokens
    }

    /// Context usage as 0.0–1.0. Shows 0 when no usage data yet.
    private var contextProgress: Double {
        guard let usedTokens = currentContextTokens,
              let maxCtx = effectiveContextWindow, maxCtx > 0
        else { return 0 }
        return min(Double(usedTokens) / Double(maxCtx), 1.0)
    }

    // MARK: - Compact chip: 🟢 model-name [ring%]

    private var modelStatusChip: some View {
        Button {
            showContextPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 6, height: 6)

                if let model = displayedModelName {
                    ViewThatFits(in: .horizontal) {
                        chipModelText(model)
                        chipModelText(compactModelName(model))
                    }
                }

                contextRing(progress: contextProgress)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .popover(isPresented: $showContextPopover) {
            contextPopoverContent
                .presentationCompactAdaptation(.popover)
        }
    }

    private func chipModelText(_ model: String) -> some View {
        Text(model)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Design.Colors.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
    }

    private func contextRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Design.Colors.divider, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(contextColor(progress), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }

    // MARK: - Popover: Context Window X of Y (%)

    private var contextPopoverContent: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            HStack(spacing: Design.Spacing.xs) {
                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 7, height: 7)

                if let model = displayedModelName {
                    Text(model)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Design.Colors.foreground)
                        .lineLimit(1)
                } else {
                    Text("Model unavailable")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
            }

            if let maxCtx = effectiveContextWindow, maxCtx > 0 {
                let total = formatTokenCount(maxCtx)

                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text("Context Window")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .textCase(.uppercase)

                    if let usedTokens = currentContextTokens {
                        let progress = min(Double(usedTokens) / Double(maxCtx), 1.0)
                        let used = formatTokenCount(usedTokens)

                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(used)
                                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Design.Colors.foreground)
                            Text("/")
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .foregroundStyle(Design.Colors.secondaryForeground)
                            Text(total)
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .foregroundStyle(Design.Colors.secondaryForeground)
                        }

                        HStack(spacing: Design.Spacing.sm) {
                            Capsule()
                                .fill(Design.Colors.surface)
                                .overlay(alignment: .leading) {
                                    GeometryReader { proxy in
                                        Capsule()
                                            .fill(contextColor(progress))
                                            .frame(width: max(proxy.size.width * progress, 3))
                                    }
                                }
                                .frame(height: 8)

                            Text("\(Int(progress * 100))%")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Design.Colors.secondaryForeground)
                        }

                        Text("\(max(maxCtx - usedTokens, 0).formatted()) prompt tokens remaining")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    } else {
                        Text(total)
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Design.Colors.foreground)

                        Text("Total window available now. Usage appears after the first Hermes response.")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    }
                }
            } else {
                Text("Context window unavailable for the active model.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
        .frame(width: 230, alignment: .leading)
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.lg)
    }

    private func contextColor(_ progress: Double) -> Color {
        if progress > 0.85 { return .red }
        if progress > 0.65 { return .orange }
        return Design.Brand.accent
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return compactDecimal(Double(count) / 1_000_000, suffix: "M")
        } else if count >= 1_000 {
            return compactDecimal(Double(count) / 1_000, suffix: "K")
        }
        return "\(count)"
    }

    private func compactModelName(_ model: String) -> String {
        guard model.count > 16 else { return model }
        return String(model.prefix(16)) + "…"
    }

    private func compactDecimal(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == floor(rounded) {
            return "\(Int(rounded))\(suffix)"
        }
        return String(format: "%.1f%@", rounded, suffix)
    }

    private var connectionIndicatorColor: Color {
        switch hostStore.connectionState {
        case .online:
            return .green
        case .offline, .unreachable:
            return .orange
        case .notConnected:
            return .gray
        }
    }

    private var connectionStatusLabel: String {
        switch hostStore.connectionState {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .unreachable:
            return "Unreachable"
        case .notConnected:
            return "Not Connected"
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
                            connectionLabel: connectionStatusLabel,
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
            .scrollDismissesKeyboard(.interactively)
            .redacted(reason: chatStore.isLoading ? .placeholder : [])
            .onTapGesture {
                isComposerFocused = false
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    private var connectionBanner: some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: connectionBannerIcon)
                .foregroundStyle(connectionIndicatorColor)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text(connectionBannerTitle)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Text(connectionBannerMessage)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button(connectionBannerActionLabel) {
                connectionBannerAction()
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

    private var connectionBannerIcon: String {
        switch hostStore.connectionState {
        case .online:
            return "desktopcomputer"
        case .offline:
            return "desktopcomputer.trianglebadge.exclamationmark"
        case .unreachable:
            return "wifi.exclamationmark"
        case .notConnected:
            return "desktopcomputer"
        }
    }

    private var connectionBannerTitle: String {
        switch hostStore.connectionState {
        case .online:
            return "Hermes host online"
        case .offline:
            return "Hermes host offline"
        case .unreachable:
            return "Could not refresh host status"
        case .notConnected:
            return "No Hermes host connected"
        }
    }

    private var connectionBannerMessage: String {
        switch hostStore.connectionState {
        case .online:
            return "Your Hermes host is connected."
        case .offline:
            return "Messages will queue until your Hermes host reconnects."
        case .unreachable:
            return hostStore.lastErrorMessage ?? "Check your relay connection or refresh your session."
        case .notConnected:
            return "Pair a Hermes host from Settings to send messages through your Mac."
        }
    }

    private var connectionBannerActionLabel: String {
        switch hostStore.connectionState {
        case .online, .offline, .notConnected:
            return "Settings"
        case .unreachable:
            return "Retry"
        }
    }

    private func connectionBannerAction() {
        switch hostStore.connectionState {
        case .unreachable:
            Task { await hostStore.refresh() }
        case .online, .offline, .notConnected:
            router.presentSheet(.settings)
        }
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
            if content.hasPrefix("/") && attachments.isEmpty {
                await dispatchTypedSlashCommand(content)
            } else {
                await chatStore.sendMessage(content, attachments: attachments)
            }
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

    private func dispatchTypedSlashCommand(_ text: String) async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/") else {
            await chatStore.sendMessage(raw, attachments: [])
            return
        }

        let body = String(raw.dropFirst())
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return }

        let commandName = String(first).lowercased()
        let argument = parts.count > 1 ? String(parts[1]) : nil
        let localCommand = (chatStore.commandCatalog + SlashCommand.localCommands)
            .first { $0.name == commandName && $0.suggestedArgument == nil && $0.isLocal }

        if let localCommand {
            handleSlashCommand(localCommand, argument)
        } else {
            await sendSlashAsMessage(raw)
        }
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

    private func scrollToResponseTop(_ id: UUID) {
        // Keep the start of the assistant response in view; without this,
        // a bottom-anchored ScrollView fights the growing message and feels flickery.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy?.scrollTo(id, anchor: .top)
        }
    }
}
