import SwiftUI

struct ChatScreen: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(TabRouter.self) private var router

    @State private var messageText = ""
    @State private var scrollPosition: ScrollPosition = .init(idType: Message.ID.self)

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if hostStore.isHostOnline == false {
                    hostOfflineBanner
                }
                messageList
                ChatInputBar(
                    text: $messageText,
                    onSend: sendMessage,
                    onPenTap: openCapture
                )
            }
        }
        .navigationTitle("Hermes Agent")
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            chatStore.setPollingEnabled(true)
            await hostStore.refresh()
            await chatStore.loadConversationIfNeeded()
        }
        .onDisappear {
            chatStore.setPollingEnabled(false)
        }
        .onChange(of: chatStore.conversation?.messages.count ?? 0) {
            scrollToBottom()
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: Design.Spacing.md) {
                if let messages = chatStore.conversation?.messages {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
            }
            .padding(.vertical, Design.Spacing.md)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .redacted(reason: chatStore.isLoading ? .placeholder : [])
    }

    private var hostOfflineBanner: some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text("Hermes host offline")
                    .font(Design.Typography.callout)
                Text("Messages will queue until your Hermes host reconnects.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Settings") {
                router.selectedTab = .settings
            }
            .buttonStyle(.glass)
            .font(Design.Typography.caption)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            GlassCircleButton(icon: "line.3.horizontal") {
                router.activeSheet = .conversationList
            }
            .accessibilityLabel("Conversations")
        }

        ToolbarItem(placement: .principal) {
            StatusIndicator(status: sessionStore.state.connectionStatus)
        }

        ToolbarItem(placement: .topBarTrailing) {
            GlassCircleButton(icon: "square.and.pencil") {
                router.activeSheet = .newConversation
            }
            .accessibilityLabel("New conversation")
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        messageText = ""

        Task {
            await chatStore.sendMessage(content)
            scrollToBottom()
        }
    }

    private func openCapture() {
        router.navigate(to: .capture)
    }

    private func scrollToBottom() {
        if let lastID = chatStore.conversation?.messages.last?.id {
            withAnimation(Design.Motion.standard) {
                scrollPosition.scrollTo(id: lastID, anchor: .bottom)
            }
        }
    }
}
