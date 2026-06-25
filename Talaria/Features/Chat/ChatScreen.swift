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

    // HUD shells (presentation only — see SessionsDrawer / ModelSelector).
    @State private var sessionsOpen = false
    @State private var sessionsModel = SessionsDrawerModel()
    @State private var modelModel = ModelSelectorModel()

    private let thinkingIndicatorID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    // `body` is split across several `some View` properties so each is a small,
    // independent expression. Applied as one chain, the ~15 modifiers overrun the
    // Swift type-checker's budget ("unable to type-check this expression in
    // reasonable time"), more readily on slower machines (e.g. CI). The split is
    // behavior-preserving: the grouped modifiers are order-independent.
    var body: some View {
        observingContent
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

    private var mainStack: some View {
        ZStack {
            HUDScreenBackground(gridIntensity: 0.4)
                .ignoresSafeArea()

            ScanLine(intensity: 0.32)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                agentIdentityStrip

                if showsConnectionBanner {
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
    }

    private var sessionsOverlay: some View {
        SessionsDrawer(
            isPresented: $sessionsOpen,
            model: sessionsModel,
            hostName: (hostStore.currentHost?.resolvedDisplayName ?? "HERMES HOST"),
            hostDetail: sessionsHostDetail,
            hostOnline: isChatHostOnline
        )
    }

    private var framedContent: some View {
        mainStack
            .overlay { sessionsOverlay }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var lifecycleContent: some View {
        framedContent
            .onAppear { configureChatSeams() }
            .task { await startChatSession() }
            .task { await monitorConnectionStatus() }
            .onDisappear { chatStore.setPollingEnabled(false) }
    }

    private var observingContent: some View {
        lifecycleContent
            .onChange(of: sessionsOpen) { _, isOpen in
                if isOpen { Task { await refreshSessions() } }
            }
            .onChange(of: displayedModelName) { _, newValue in
                modelModel.activeModelNameOverride = newValue
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
    }

    // MARK: - Shell wiring (presentation seams)

    /// Connects the Sessions drawer / Model selector shells to the Hermes
    /// Sessions API (model list + switch, session list + open).
    private func configureChatSeams() {
        modelModel.activeModelNameOverride = displayedModelName
        sessionsModel.onNewChat = { showClearConfirmation = true }
        sessionsModel.onOpenHostSettings = { router.presentSheet(.settings) }
        // Sessions drawer → Hermes Sessions API. Tapping a session loads its
        // full history and continues that thread.
        sessionsModel.onSelectSession = { summary in
            Task { await chatStore.openSession(summary.id) }
        }

        // Model chip → Settings → Models (the shim-backed real picker).
        // No local dropdown — the chip is a shortcut to the full picker.
        modelModel.onChipTap = { [router] in
            router.presentSheet(.settingsModels)
        }

        Task { await refreshSessions() }
    }

    /// Fetches the host's sessions and maps them into the drawer's view models.
    private func refreshSessions() async {
        let infos = await chatStore.loadSessions()
        sessionsModel.sessions = infos.map(Self.sessionSummary(from:))
    }

    /// Initial chat bootstrap: enable polling, refresh relay host + direct
    /// Sessions API health, then load the conversation. Extracted from `body`'s
    /// `.task` to keep that view expression cheap to type-check.
    private func startChatSession() async {
        chatStore.setPollingEnabled(true)
        await hostStore.refresh()
        await chatStore.refreshDirectHealth()
        await chatStore.loadConversationIfNeeded()
    }

    /// Periodically re-checks relay host status and direct Sessions API health
    /// while the chat screen is visible.
    private func monitorConnectionStatus() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { break }
            await hostStore.refresh()
            await chatStore.refreshDirectHealth()
        }
    }

    private static func sessionSummary(from info: HermesSessionInfo) -> SessionsDrawerModel.SessionSummary {
        let title = (info.title?.isEmpty == false)
            ? info.title!
            : ((info.preview?.isEmpty == false) ? info.preview! : "Untitled session")
        let subtitle = (info.preview?.isEmpty == false)
            ? info.preview!
            : "\(info.messageCount) message\(info.messageCount == 1 ? "" : "s")"
        let (group, timeLabel) = sessionGroupAndLabel(for: info.lastActive)
        return .init(
            id: info.id,
            title: title,
            subtitle: subtitle,
            timeLabel: timeLabel,
            group: group,
            isActive: info.isActive,
            isPinned: false,
            badge: info.source == "cron" ? "AUTO" : nil
        )
    }

    private static func sessionGroupAndLabel(for date: Date?) -> (SessionsDrawerModel.Group, String) {
        guard let date else { return (.earlier, "—") }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return (.today, sessionTimeFormatter.string(from: date)) }
        if cal.isDateInYesterday(date) { return (.yesterday, sessionTimeFormatter.string(from: date)) }
        if let days = cal.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return (.earlier, sessionWeekdayFormatter.string(from: date))
        }
        return (.earlier, sessionDateFormatter.string(from: date))
    }

    private static let sessionTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let sessionWeekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let sessionDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private var sessionsHostDetail: String {
        switch effectiveConnectionState {
        case .online: return "LINKED · ONLINE"
        case .offline: return "OFFLINE"
        case .unreachable: return "UNREACHABLE"
        case .notConnected: return "NOT CONNECTED"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation(Design.Motion.standard) { sessionsOpen = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
            }
            .accessibilityLabel("Sessions")
            .allowsHitTesting(!sessionsOpen)
        }
        ToolbarItem(placement: .principal) {
            ModelSelector(model: modelModel, isOnline: isChatHostOnline)
                .allowsHitTesting(!sessionsOpen)
        }
        ToolbarItem(placement: .topBarTrailing) {
            GlassCircleButton(icon: "gearshape", accessibilityLabel: "Open settings") {
                router.presentSheet(.settings)
            }
            .allowsHitTesting(!sessionsOpen)
        }
    }

    /// Connection state for the chat UI. Chat talks **directly** to the Hermes
    /// Sessions API (localhost:8642), not the relay, so the banner and status
    /// indicators must reflect that direct reachability. `hostStore.connectionState`
    /// is relay-sourced and the relay is offline by design, which would otherwise
    /// paint a false "Hermes host offline" banner and a stale/offline model chip.
    private var effectiveConnectionState: HermesHostConnectionState {
        switch chatStore.directConnectionStatus {
        case .connected:
            return .online
        case .error:
            return .offline
        case .connecting, .disconnected:
            // Not yet probed (or a probe is in flight). Stay optimistic so we
            // never flash a false offline state before the first probe resolves.
            return .online
        }
    }

    // Explicitly-typed projections of `effectiveConnectionState`. Keeping these
    // out of `body` as plain Bools keeps that (already large) view expression
    // within the Swift type-checker's complexity budget.
    private var showsConnectionBanner: Bool {
        pairingStore.isPaired && effectiveConnectionState != .online
    }

    private var isChatHostOnline: Bool {
        effectiveConnectionState == .online
    }

    private var displayedModelName: String? {
        // The live model comes from the direct Sessions API path (selection /
        // `/model` switch detection). The relay's `hermesModel` is intentionally
        // not used as a fallback — the relay is offline by design, so it would
        // only ever surface a stale value.
        chatStore.activeModelName
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

    // MARK: - Agent identity strip (HUD telemetry header)

    private var agentIdentityStrip: some View {
        HStack(spacing: Design.Spacing.sm) {
            ReactorOrb(size: Design.Size.orbNav, style: .standard)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Design.Spacing.xs) {
                    Text("HERMES")
                        .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                        .tracking(Design.Tracking.button)
                        .foregroundStyle(Design.Colors.foregroundBright)
                    StatusPip(color: connectionIndicatorColor, diameter: 6,
                              blinks: effectiveConnectionState != .online)
                    MonoLabel(connectionTelemetry, size: 9, tracking: Design.Tracking.mono)
                }
                MonoLabel(messageTelemetry, size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
            }

            Spacer(minLength: Design.Spacing.sm)

            if effectiveContextWindow != nil {
                contextGauge
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xs)
        .padding(.bottom, Design.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.cyanHairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hermes \(connectionStatusLabel)")
    }

    private var contextGauge: some View {
        VStack(alignment: .trailing, spacing: 4) {
            MonoLabel("CTX \(Int(contextProgress * 100))%", size: 10, tracking: Design.Tracking.mono)
            Capsule()
                .fill(Design.Colors.accentTint(0.16))
                .frame(width: 48, height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(contextColor(contextProgress))
                            .frame(width: max(proxy.size.width * contextProgress, 2))
                            .hudGlow(contextColor(contextProgress), radius: 4, strength: 0.8)
                    }
                }
        }
    }

    private var connectionTelemetry: String {
        let host = hostStore.currentHost?.resolvedDisplayName.uppercased()
        switch effectiveConnectionState {
        case .online: return "ONLINE\(host.map { " · \($0)" } ?? "")"
        case .offline: return "OFFLINE"
        case .unreachable: return "UNREACHABLE"
        case .notConnected: return "NO HOST"
        }
    }

    private var messageTelemetry: String {
        let count = chatStore.conversation?.messages.count ?? 0
        return "\(count) MESSAGE\(count == 1 ? "" : "S")"
    }

    private func contextColor(_ progress: Double) -> Color {
        if progress > 0.85 { return Design.Colors.danger }
        if progress > 0.65 { return Design.Brand.forge }
        return Design.Brand.accent
    }

    private var connectionIndicatorColor: Color {
        switch effectiveConnectionState {
        case .online:
            return Design.Brand.accent
        case .offline, .unreachable:
            return Design.Brand.forge
        case .notConnected:
            return Design.Colors.dimForeground
        }
    }

    private var connectionStatusLabel: String {
        switch effectiveConnectionState {
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
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(connectionIndicatorColor)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                MonoLabel(connectionBannerTitle, size: 11, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                Text(connectionBannerMessage)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Spacer()

            Button(connectionBannerActionLabel) {
                connectionBannerAction()
            }
            .font(Design.Typography.mono(11, weight: .medium))
            .foregroundStyle(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.lg, borderColor: Design.Brand.forge.opacity(0.35))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
    }

    private var connectionBannerIcon: String {
        switch effectiveConnectionState {
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
        switch effectiveConnectionState {
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
        switch effectiveConnectionState {
        case .online:
            return "Your Hermes host is connected."
        case .offline:
            return "Your Hermes host isn't responding. Check that it's running and your connection settings."
        case .unreachable:
            return hostStore.lastErrorMessage ?? "Check your relay connection or refresh your session."
        case .notConnected:
            return "Pair a Hermes host from Settings to send messages through your Mac."
        }
    }

    private var connectionBannerActionLabel: String {
        switch effectiveConnectionState {
        case .online, .offline, .notConnected:
            return "Settings"
        case .unreachable:
            return "Retry"
        }
    }

    private func connectionBannerAction() {
        switch effectiveConnectionState {
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
