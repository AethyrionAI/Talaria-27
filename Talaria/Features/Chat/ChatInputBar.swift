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
    /// #306: the composer-attached chip for a held mid-turn message (nil =
    /// nothing held for this thread). A chip, never a transcript bubble —
    /// the identity ruling.
    let queuedChip: QueuedTurnChipModel?
    /// #306: whether a queue-commit is available (a turn in flight, depth 1
    /// free). The commit control renders only while this is true.
    let canQueueMessage: Bool
    let onQueueMessage: () -> Void
    let onChipSendNow: () -> Void
    let onChipEdit: () -> Void
    let onChipCancel: () -> Void
    /// #357-E/G/H: the RUNNING turn's door status (steer submitted/applied,
    /// interrupt in flight; nil = no attempt). Distinct from `queuedChip`,
    /// which is the NEXT turn's held message — both can be on screen at once
    /// (steer outstanding + a second send held).
    let doorStatusChip: DoorStatusChipModel?
    /// #357-E: a door chosen EXPLICITLY from the commit control's menu — the
    /// non-default doors stay reachable regardless of Owen's plain-send
    /// setting.
    let onExplicitDoor: (ComposerDoor) -> Void

    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore
    /// #173: the floor needs to know where THIS turn is bound, and only the
    /// router knows — `ChatStore` carries `activeModelName` (a Hermes-side
    /// label) but not the brain. `ChatScreen` already reads the router the
    /// same way for its brain chip.
    @Environment(AppContainer.self) private var container
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

    /// #315: THE composer door — which commit path the composer OFFERS for the
    /// draft as it stands. It had been decided twice, independently, in two
    /// places (`actionButton` and the hardware-keyboard Return handler), which
    /// is how a door predicate can be right on one and wrong on the other.
    /// One resolution, two call sites, and a unit can watch it.
    ///
    /// Not to be confused with #306's `ComposerDoor` (`ComposerDoor.swift`),
    /// which is the door's NAME on the chip once a commit has been made
    /// (`QUEUED` / `STEERED` / `INTERRUPTED`). This one is the question
    /// asked one step earlier: which door is even open.
    enum CommitDoor: Equatable {
        /// A turn is in flight and this draft can be HELD: the queue-commit
        /// control alongside Stop. Committing never posts (#306).
        case queueCommit
        /// A turn is in flight and this draft cannot be held (slash draft, the
        /// thread's single hold slot taken, or nothing to commit): Stop only.
        /// **Never plain Send** — that is the door #315 closed.
        case busyNoCommit
        /// Idle transcript, sendable draft: plain Send, posts now.
        case send
        /// Idle, content staged but not transmittable (#8): the dimmed inert
        /// arrow beside the forge hint.
        case blockedByAttachments
        /// Idle with nothing to commit — no control.
        case inert
    }

    /// The door's resolution, from the STORE's own predicate plus the draft's
    /// facts. Taking the store rather than a mirrored flag is deliberate:
    /// #278's ruling is that the surface and the store must read the same
    /// predicate, and a copy passed down as a prop is exactly where the two
    /// drift apart.
    ///
    /// **#315: `isTranscriptBusy`, not `isStreaming`.** A dropped stream
    /// leaves `streamingMessageID` nil with `pendingRun` very much alive —
    /// the #278 window, minutes long — and on `isStreaming` the composer
    /// offered plain Send for all of it. That send posts into the live run,
    /// and `attemptReconcile`'s `timestamp > pending.sentAt` adoption can
    /// then pair the dropped run's recovery with the manual turn's reply:
    /// someone else's reasoning re-attached, a fabricated duration, the old
    /// prompt re-paired, nothing erroring. #307's mechanism exactly, driven
    /// by the user instead of by the drain. This is the same predicate the
    /// fire gate (`fireHeldTurnIfReady`), the drain
    /// (`drainComposeOutboxIfPossible`) and the bubble menu already read —
    /// the door was the last surface still asking the weaker question.
    @MainActor
    static func resolveDoor(
        store: ChatStore,
        canSend: Bool,
        canQueueMessage: Bool,
        isSlashMode: Bool,
        sendBlockedByAttachments: Bool
    ) -> CommitDoor {
        if store.isTranscriptBusy {
            return canQueueMessage && canSend && !isSlashMode ? .queueCommit : .busyNoCommit
        }
        if canSend { return .send }
        if sendBlockedByAttachments { return .blockedByAttachments }
        return .inert
    }

    private var door: CommitDoor {
        Self.resolveDoor(
            store: chatStore,
            canSend: canSend,
            canQueueMessage: canQueueMessage,
            isSlashMode: isSlashMode,
            sendBlockedByAttachments: sendBlockedByAttachments
        )
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
                // #357: the running turn's door status — above the held
                // chip so the two read in turn order (this turn, then the
                // next).
                if let doorStatusChip {
                    doorStatusStrip(doorStatusChip)
                }

                // #306: the held-message chip — composer-attached, above the
                // input, so the queued text is visible, editable and
                // cancellable for as long as it is held.
                if let queuedChip {
                    queuedTurnChip(queuedChip)
                }

                // Attachment preview strip
                if !pendingAttachments.isEmpty {
                    attachmentPreviewStrip
                    if pendingAttachments.contains(where: { !$0.isTransmittable }) {
                        untransmittableHint
                    }
                    // #173: the never-claim floor. Shown BEFORE the send, in
                    // the tray, so the user learns what the model can see
                    // while they can still decide — not after a confident
                    // reply has already implied it saw the picture.
                    if let visionCaption {
                        visionCapabilityHint(visionCaption)
                    }
                }

                // Text input area
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .accessibilityIdentifier("chat.composer")
                        .accessibilityLabel("Reply to Hermes")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.foreground)
                        .tint(Design.Brand.accentText)
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
                            // #306: mid-turn, Return routes to the HOLD —
                            // the same door the on-screen queue-commit
                            // control offers — instead of refusing.
                            // #315: and it is now literally the same door —
                            // one resolution, read here and by `actionButton`.
                            switch door {
                            case .queueCommit:
                                handleQueueAction()
                                return .handled
                            case .send:
                                handlePrimaryAction()
                                return .handled
                            case .busyNoCommit, .blockedByAttachments, .inert:
                                return .ignored
                            }
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
                                .foregroundStyle(speechService.isListening ? Design.Colors.dangerText : Design.Colors.mutedForeground)
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
                                .foregroundStyle(Design.Brand.accentBrightText)
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
        // #315: the door can now change without `isStreaming` changing — the
        // reconcile window opens and closes on `pendingRun` alone. Without
        // this the control set would swap in a hard cut at both edges.
        .animation(Design.Motion.quickResponse, value: door)
        .animation(Design.Motion.quickResponse, value: canSend)
        .animation(Design.Motion.quickResponse, value: queuedChip)
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
                            .foregroundStyle(Design.Brand.accentText)
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
                        .tint(Design.Brand.accentText)
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
                color: Design.Brand.forgeText
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xxs)
    }

    // MARK: - #173: the never-claim floor

    /// The caption owed for what is currently staged, or nil.
    ///
    /// Resolved from the ROUTER's `activeBrain` rather than from whether a
    /// host is merely configured: what matters is where this turn will
    /// actually go. `.privateCloud` folds into `.onDevice` because #30 routes
    /// it through the local backend that owns the PCC session — so its image
    /// story is the local one, not the host's.
    private var visionCaption: String? {
        guard AttachmentCapabilityCopy.carriesImage(
            pendingAttachments, isImage: { $0.kind == .image }
        ) else { return nil }
        // A nil router means nothing has resolved a brain yet. Default to
        // the HERMES wording, which is the honest one for an unknown: it
        // claims nothing, where the on-device string asserts a definite
        // blindness we would not have established.
        let destination: AttachmentCapabilityCopy.Destination =
            container.chatBackendRouter?.activeBrain == .onDevice ? .onDevice : .hermesHost
        return AttachmentCapabilityCopy.caption(for: destination, carriesImageAttachment: true)
    }

    /// Deliberately the same visual weight as `untransmittableHint` — this is
    /// information about what will happen to the attachment, not an error.
    /// **It never gates `canSend`**; bar 173-C pins that the send proceeds
    /// with its attachments intact.
    private func visionCapabilityHint(_ text: String) -> some View {
        HStack(spacing: Design.Spacing.xxs) {
            Image(systemName: "eye.slash")
                .font(.system(size: Design.Size.iconTiny))
                .foregroundStyle(Design.Colors.mutedForeground)
            Text(text)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xxs)
        .accessibilityIdentifier("chat.visionCapabilityHint")
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
        switch door {
        case .queueCommit:
            // #306 T5: the third state — while a run is in flight the composer
            // offers BOTH the queue-commit control and Stop, not one replacing
            // the other. Which of the two `busy` doors applies (commit
            // available or not) is `resolveDoor`'s decision, not this view's:
            // there is text to commit, the thread's single hold slot is free
            // (depth 1), and the draft isn't a slash command (a held slash
            // turn would post as plain prose at fire time — refuse it
            // honestly).
            HStack(spacing: Design.Spacing.xs) {
                queueCommitButton
                stopButton
            }
        case .busyNoCommit:
            // #315: nothing this draft can commit while a run is live — Stop
            // and nothing else. Note what is NOT here: the plain Send arrow.
            HStack(spacing: Design.Spacing.xs) {
                stopButton
            }
        case .send:
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
        case .blockedByAttachments:
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
        case .inert:
            EmptyView()
        }
    }

    /// The Stop control, exactly as it has always rendered (#306 moved it
    /// into the third-state HStack without restyling it).
    private var stopButton: some View {
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
    }

    /// #357-E: the door a plain tap on the commit control takes right now —
    /// the same pure resolution `ChatScreen` dispatches through (the #278
    /// discipline: surface and store read one predicate), so the badge can
    /// name the door honestly instead of always wearing the queue clock.
    private var plainSendDoor: ComposerDoor {
        ComposerDoor.resolvePlainSend(
            setting: settingsStore.settings.midTurnSendAction,
            streamLostRunLive: chatStore.isInReconcileWindow,
            runIDAvailable: chatStore.canSteerActiveTurn,
            steerAttemptOutstanding: chatStore.steerAttemptOutstanding
        )
    }

    /// #357-E/I: which doors the commit control's long-press menu offers —
    /// feasibility from the same store facts the resolver reads.
    private var availableExplicitDoors: [ComposerDoor] {
        ComposerDoor.explicitDoors(
            streamLostRunLive: chatStore.isInReconcileWindow,
            runIDAvailable: chatStore.canSteerActiveTurn,
            steerAttemptOutstanding: chatStore.steerAttemptOutstanding,
            holdSlotFree: canQueueMessage
        )
    }

    /// #306: the queue-commit control — the send arrow wearing the door's
    /// badge. Committing HOLDS the message against this thread (or, when
    /// Owen's setting picks steer, submits it against the running turn); the
    /// label never says "sent" (C1). Long-press names every open door
    /// explicitly (#357-E).
    private var queueCommitButton: some View {
        Button(action: handleQueueAction) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Design.Colors.foregroundBright)
                .frame(width: 38, height: 38)
                .background(Design.Colors.accentTint(0.12), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(Design.Colors.accentTint(0.6), lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: plainSendDoor == .steered ? "arrow.triangle.branch" : "clock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Design.Brand.accentBrightText)
                        .padding(2)
                        .background(Circle().fill(Design.Colors.surface))
                        .offset(x: 4, y: -4)
                }
                .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .hoverEffect(.highlight)
        .accessibilityLabel(plainSendDoor == .steered ? "Steer the running turn" : "Queue message")
        .contextMenu {
            ForEach(availableExplicitDoors, id: \.self) { door in
                Button { handleExplicitDoor(door) } label: {
                    switch door {
                    case .queued:
                        Label("Queue — after this turn", systemImage: "clock")
                    case .steered:
                        Label("Steer the running turn", systemImage: "arrow.triangle.branch")
                    case .interrupted:
                        Label("Stop & send as a new message", systemImage: "stop.circle")
                    }
                }
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    /// #357-E/G/H: the running turn's door status — name + honesty state,
    /// nothing else. Control-free on purpose: a steer that has reached the
    /// host can be neither edited nor recalled (contrast the queued chip's
    /// Edit/Cancel). Never a transcript row (#282/identity ruling).
    private func doorStatusStrip(_ chip: DoorStatusChipModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            MonoLabel(
                chip.doorName,
                size: 9,
                tracking: Design.Tracking.mono,
                color: chip.state == .interrupting ? Design.Brand.forgeText : Design.Brand.accentBrightText
            )
            Text(chip.text)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.foreground)
                .lineLimit(2)
            Text(chip.statusLine)
                .font(Design.Typography.caption2)
                .foregroundStyle(Design.Colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.sm)
        .padding(.bottom, Design.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.doorStatusChip")
    }

    /// #306: the held-message chip — the door name, the text, its status,
    /// and the affordances: Edit and Cancel while waiting; Send now, Edit
    /// and Discard once surfaced (the turn it waited on produced no answer).
    private func queuedTurnChip(_ chip: QueuedTurnChipModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            HStack(spacing: Design.Spacing.xs) {
                MonoLabel(
                    chip.door.displayName,
                    size: 9,
                    tracking: Design.Tracking.mono,
                    color: chip.isSurfaced ? Design.Brand.forgeText : Design.Brand.accentBrightText
                )
                Spacer()
                if chip.isSurfaced {
                    Button(action: onChipSendNow) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: Design.Size.iconSmall, weight: .medium))
                            .foregroundStyle(Design.Brand.accentBrightText)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Send queued message now")
                    .accessibilityIdentifier("chat.queuedChip.sendNow")
                }
                Button(action: onChipEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: Design.Size.iconSmall, weight: .medium))
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .hoverEffect(.highlight)
                .accessibilityLabel("Edit queued message")
                .accessibilityIdentifier("chat.queuedChip.edit")
                Button(action: onChipCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: Design.Size.iconSmall, weight: .medium))
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .hoverEffect(.highlight)
                .accessibilityLabel(chip.isSurfaced ? "Discard queued message" : "Cancel queued message")
                .accessibilityIdentifier("chat.queuedChip.cancel")
            }
            Text(chip.text)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.foreground)
                .lineLimit(2)
            Text(chip.statusLine)
                .font(Design.Typography.caption2)
                .foregroundStyle(chip.isSurfaced ? Design.Brand.forgeText : Design.Colors.mutedForeground)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.sm)
        .padding(.bottom, Design.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.queuedChip")
    }

    /// #306: the queue gesture — same dictation settling as the send
    /// gesture, then the hold instead of the post.
    private func handleQueueAction() {
        settleDictationIntoText()
        onQueueMessage()
    }

    /// #357-E: an explicit door from the commit control's menu — same
    /// dictation settling, then the chosen door instead of the resolved one.
    private func handleExplicitDoor(_ door: ComposerDoor) {
        settleDictationIntoText()
        onExplicitDoor(door)
    }

    /// A live dictation session's transcript merges into the draft before
    /// any commit gesture acts on it.
    private func settleDictationIntoText() {
        guard speechService.isListening else { return }
        speechService.stopListening()
        text = mergedDictationText(speechService.transcript)
        dictationBaseText = ""
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
