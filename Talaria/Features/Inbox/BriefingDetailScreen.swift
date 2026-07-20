import SwiftUI

// #126: full-screen render of a daily-briefing inbox item through the
// existing markdown pipeline — chart fences render + tap through free.
struct BriefingDetailScreen: View {
    @Environment(InboxStore.self) private var inboxStore
    @Environment(SpeechOutputService.self) private var speechOutput

    let item: InboxItem?

    private var briefing: InboxItem? {
        item ?? InboxItem.latestBriefing(in: inboxStore.items)
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if let briefing {
                content(for: briefing)
            } else if inboxStore.isLoading {
                ProgressView()
            } else {
                emptyState
            }
        }
        .navigationTitle("Briefing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let briefing {
                ToolbarItem(placement: .topBarTrailing) {
                    speakerToggle(for: briefing)
                }
            }
        }
        .task(id: briefing?.id) {
            // The deep link can land before any inbox fetch — resolve first,
            // then mark the rendered briefing read (local bookkeeping only).
            if item == nil, inboxStore.items.isEmpty {
                await inboxStore.loadInbox(force: true)
            }
            if let briefing {
                inboxStore.markRead(briefing)
            }
        }
    }

    private func content(for briefing: InboxItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                header(for: briefing)
                MarkdownContentView(content: briefing.body, isStreaming: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func header(for briefing: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Brand.accent, diameter: 7, blinks: false)
                MonoLabel(
                    "BRIEFING · \(briefing.timestamp.formatted(date: .abbreviated, time: .shortened).uppercased())",
                    size: 11,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.secondaryForeground
                )
            }
            Text(briefing.title)
                .font(Design.Typography.screenTitle2)
                .foregroundStyle(Design.Colors.foregroundBright)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Design.Spacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
        }
    }

    // Read-aloud through the SHARED chat instance — the audio-session house
    // law (#106) is enforced inside the service; this view only ever calls
    // speak/stop. Same toggle pattern as MessageBubble's speaker.
    private func speakerToggle(for briefing: InboxItem) -> some View {
        let isSpeakingThis = speechOutput.speakingMessageID == briefing.id
        return Button {
            if isSpeakingThis {
                speechOutput.stop()
            } else {
                speechOutput.speak(briefing.briefingSpeakableText, messageID: briefing.id)
            }
        } label: {
            Image(systemName: isSpeakingThis ? "speaker.slash.fill" : "speaker.wave.2")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeakingThis ? "Stop reading aloud" : "Read briefing aloud")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Briefing Yet")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "sunrise")
                    .foregroundStyle(Design.Brand.accent)
            }
        } description: {
            MonoLabel(
                "THE NEXT DAILY BRIEFING WILL APPEAR HERE",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }
}
