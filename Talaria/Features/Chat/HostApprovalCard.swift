import SwiftUI

/// #304 (Phase 3 slice 3B): the HOST's approval card — a SIBLING of
/// `ToolConfirmationCard` (#29), rendered beside it in the transcript, and
/// deliberately distinguishable from it at a glance: that card is the PHONE
/// asking about its own tool ("Confirm", hand icon, editable fields); this
/// one is a REMOTE HOST asking about ITS action ("HOST APPROVAL", antenna
/// icon, the actor named, nothing editable). The two can be on screen at the
/// same moment.
///
/// Honesty rules, each a bar:
/// - The buttons are EXACTLY the choices the host offered (`question.choices`
///   as received) — never a hardcoded four (bar 304-A). Unknown choices
///   render as themselves.
/// - `command` is shown AS RECEIVED — already redacted host-side; never
///   reformatted, re-highlighted, or truncated — and never presented as a
///   command when it is the MCP-elicitation consent MESSAGE. Nor is this
///   card ever a surface to reconstruct written files from (3A-D).
/// - The degraded shape (`question == nil`, bar 304-D(i)) offers Deny alone
///   and says it cannot show what it would deny — the answer channel is
///   stream-independent, so the Deny still lands.
/// - O1 (Owen, 2026-08-09): `once`/`deny` are one tap; `always`/`session`
///   (and any unknown choice, fail-safe) sit behind a second confirm naming
///   the consequence. `session` reads "THIS RUN" — it scopes to the run id,
///   not the conversation.
/// - VoiceOver labels state the CONSEQUENCE, not the choice name (224-1D).
///
/// Theme discipline: every color is a `Design` token (forge header treatment
/// like the sibling card), so all four themes — including light Paper Tape —
/// resolve it from the palette with no hardcoded values.
struct HostApprovalCard: View {
    let store: HostApprovalStore
    let approval: RunApprovalRequest
    /// The actor line: the birth profile's name when resolvable, else the
    /// frozen endpoint's host. Real data only — never a guess.
    let actorLabel: String

    private var offeredChoices: [String] {
        // The degraded shape offers exactly Deny — the one answer that is
        // safe to offer without knowing the question.
        approval.question?.choices ?? ["deny"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            header

            if let question = approval.question {
                questionBody(question)
            } else {
                degradedBody
            }

            if let notice = store.transportNotice {
                transportRow(notice)
            }

            if let pending = store.pendingConsequenceChoice {
                consequenceConfirm(pending)
            } else {
                choiceRow
            }
        }
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Brand.forge.opacity(0.55),
            fill: Design.Colors.surface
        )
        .padding(.horizontal, Design.Spacing.md)
    }

    private var header: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Brand.forge)
            MonoLabel("HOST APPROVAL", size: 9, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Brand.forge)
            Spacer()
            MonoLabel(actorLabel.uppercased(), size: 9,
                      tracking: Design.Tracking.mono,
                      color: Design.Colors.mutedForeground)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Host approval from \(actorLabel)")
    }

    @ViewBuilder
    private func questionBody(_ question: RunApprovalRequest.Question) -> some View {
        Text(question.isElicitation
            ? "\(actorLabel) asks for your consent"
            : "\(actorLabel) wants to run something")
            .font(Design.Typography.body(15, weight: .medium))
            .foregroundStyle(Design.Colors.foregroundBright)

        // The host's own words, verbatim. An elicitation is a MESSAGE and
        // renders as prose; everything else renders monospaced — but never
        // reformatted, highlighted, or truncated either way.
        Text(question.command)
            .font(question.isElicitation
                ? Design.Typography.body(14)
                : Design.Typography.callout.monospaced())
            .foregroundStyle(Design.Colors.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Design.Colors.accentTint(0.06), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.hairline, lineWidth: 1)
            }

        if let description = question.description, !description.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.sm) {
                MonoLabel("MATCHED", size: 9,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.mutedForeground)
                Text(description)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var degradedBody: some View {
        // Bar 304-D(i): honest absence — the stream that carried the
        // question is gone; only the park is knowable. Nothing is invented.
        Text("\(actorLabel) is waiting on an approval. This connection can't show you what it is — you can deny it, or reopen the conversation to see.")
            .font(Design.Typography.body(14))
            .foregroundStyle(Design.Colors.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func transportRow(_ notice: String) -> some View {
        // #264: could-not-reach keeps the card live — one truth, one line.
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Brand.forge)
            Text(notice)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Brand.forge)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Could not reach the host. The approval is still waiting. You can try again.")
    }

    private var choiceRow: some View {
        // Wrapping layout: the host can offer any number of choices and the
        // labels must never truncate to fit a row.
        FlowingChoiceRow(spacing: Design.Spacing.sm) {
            ForEach(offeredChoices, id: \.self) { choice in
                choiceButton(choice)
            }
        }
    }

    private func choiceButton(_ choice: String) -> some View {
        let isDeny = choice == "deny"
        return Button {
            Task { await store.requestChoice(choice) }
        } label: {
            Text(RunApprovalRequest.buttonLabel(for: choice))
                .font(Design.Typography.mono(11, weight: .medium))
                .tracking(Design.Tracking.mono)
                .foregroundStyle(isDeny ? Design.Colors.mutedForeground : Design.Brand.accentBright)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.xs)
                .background(Design.Colors.accentTint(isDeny ? 0.0 : 0.10), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        isDeny ? Design.Colors.hairline : Design.Colors.accentTint(0.4),
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .disabled(store.isPosting)
        // 224-1D: the consequence, not the choice name.
        .accessibilityLabel(RunApprovalRequest.accessibilityLabel(for: choice, host: actorLabel))
    }

    @ViewBuilder
    private func consequenceConfirm(_ choice: String) -> some View {
        // O1's second confirm: the consequence named before anything posts.
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Brand.forge)
            Text(RunApprovalRequest.consequenceStatement(for: choice, host: actorLabel))
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Brand.forge)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Caution: \(RunApprovalRequest.consequenceStatement(for: choice, host: actorLabel))")

        HStack(spacing: Design.Spacing.sm) {
            Button {
                store.cancelPendingChoice()
            } label: {
                Text("BACK")
                    .font(Design.Typography.mono(11, weight: .medium))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.mutedForeground)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
                    .overlay { Capsule().strokeBorder(Design.Colors.hairline, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back — nothing is sent, the choices return")

            Button {
                Task { await store.confirmPendingChoice() }
            } label: {
                Text("CONFIRM \(RunApprovalRequest.buttonLabel(for: choice))")
                    .font(Design.Typography.mono(11, weight: .medium))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Brand.forge)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
                    .background(Design.Brand.forge.opacity(0.12), in: Capsule())
                    .overlay { Capsule().strokeBorder(Design.Brand.forge.opacity(0.4), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(store.isPosting)
            .accessibilityLabel(RunApprovalRequest.accessibilityLabel(for: choice, host: actorLabel))

            Spacer()
        }
    }
}

/// The terminal-notice row (bar 304-C's rendering surface once the card is
/// gone): the window closed, the run vanished, the host rejected the answer
/// — each distinct, none dressed as success.
struct HostApprovalNoticeRow: View {
    let notice: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
            Image(systemName: "info.circle")
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Colors.mutedForeground)
            Text(notice)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.hairline,
            fill: Design.Colors.surface
        )
        .padding(.horizontal, Design.Spacing.md)
        .accessibilityElement(children: .combine)
    }
}

/// A minimal wrapping HStack for the choice buttons: lays children in rows,
/// wrapping when the host offers more (or longer) choices than one row
/// holds — labels never truncate to fit.
struct FlowingChoiceRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
