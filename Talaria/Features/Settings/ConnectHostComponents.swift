import SwiftUI

// MARK: - Shared Connect Host pieces (#309 Lane B)
//
// The wizard and the Settings screen render the SAME eight states, so the
// pieces that draw them live here rather than twice. House components only
// (`HUDPanel`, `MonoLabel`, `GlowButton`/`GhostButton`, `StatusPip`,
// `CornerBrackets`) and forge — never danger-red — for failures: a host that
// did not answer is a warning, not a destructive act.

/// One rung of the probe ladder: the check's name on the left, its verdict on
/// the right, in the verdict's own colour.
struct ConnectHostCheckRow: View {
    let label: String
    let verdict: HostCheckVerdict

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            StatusPip(color: pipColor, diameter: 6, blinks: verdict == .pending)
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer(minLength: Design.Spacing.sm)
            MonoLabel(verdict.detailLabel, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: detailColor)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(verdict.detailLabel)")
    }

    private var pipColor: Color {
        switch verdict {
        case .passed: Design.Brand.accentText
        case .failed: Design.Brand.forgeText
        case .pending: Design.Colors.secondaryForeground
        case .notReached, .notConcluded: Design.Colors.dimForeground
        }
    }

    private var detailColor: Color {
        switch verdict {
        case .passed: Design.Brand.accentText
        case .failed: Design.Brand.forgeText
        case .pending, .notReached, .notConcluded: Design.Colors.mutedForeground
        }
    }
}

/// The three named checks, with the address they are being run against.
///
/// The design's own note: *three named checks — so a failure can point at the
/// one that broke, not at "failed"*. The rows use the RESULT wording once a
/// verdict lands ("Key accepted" rather than "Checking the key"), which is
/// what makes a screenshot of a failure readable on its own.
struct ConnectHostLadderCard: View {
    let ladder: HostProbeLadder
    let address: String?
    var showsFooter = true

    var body: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                MonoLabel(ConnectHostCopy.checkingTitle, weight: .medium,
                          tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.secondaryForeground)

                if let address, !address.isEmpty {
                    Text(address)
                        .font(Design.Typography.mono(12, weight: .regular))
                        .foregroundStyle(Design.Colors.coolForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                VStack(spacing: 0) {
                    ConnectHostCheckRow(
                        label: ConnectHostCopy.checkReachable,
                        verdict: ladder.reachable
                    )
                    Divider().overlay(Design.Colors.divider)
                    ConnectHostCheckRow(
                        label: ladder.keyAccepted == .pending
                            ? ConnectHostCopy.checkKey
                            : ConnectHostCopy.checkKeyResult,
                        verdict: ladder.keyAccepted
                    )
                    Divider().overlay(Design.Colors.divider)
                    ConnectHostCheckRow(
                        label: ladder.hermesGateway == .pending
                            ? ConnectHostCopy.checkHermes
                            : ConnectHostCopy.checkHermesResult,
                        verdict: ladder.hermesGateway
                    )
                }
                .padding(.top, Design.Spacing.xxs)

                if showsFooter {
                    Text(ConnectHostCopy.fiveSecondsAtMost)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .padding(.top, Design.Spacing.xxs)
                }
            }
            .padding(Design.Spacing.lg)
        }
    }
}

/// The two values. `guiltyField` flags exactly one — design B1's *"only the
/// guilty field is flagged"* — and `isDimmed` is design A3: the fields stay on
/// screen while a check runs so a typo is still visible.
struct ConnectHostFieldsCard: View {
    @Bindable var model: ConnectHostModel
    var isDimmed = false
    var showsHelp = true
    var keyHelp: String = ConnectHostCopy.keyFieldHelpSettings

    @FocusState private var focusedField: ConnectHostField?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            gatewayField
            keyField
        }
        .disabled(isDimmed)
        .opacity(isDimmed ? 0.45 : 1)
    }

    private var gatewayField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(ConnectHostCopy.gatewayFieldLabel, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: labelColor(for: .gatewayURL))

            TextField(ConnectHostCopy.gatewayFieldPlaceholder, text: $model.draft.gatewayBaseURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .gatewayURL)
                .font(Design.Typography.mono(13, weight: .regular))
                .foregroundStyle(Design.Colors.coolForeground)
                .padding(Design.Spacing.md)
                .background(Design.Colors.background.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(borderColor(for: .gatewayURL), lineWidth: 1)
                }
                .accessibilityLabel("Gateway URL")

            if let message = model.validationMessage {
                Text(message)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Brand.forgeText)
            } else if showsHelp {
                Text(ConnectHostCopy.gatewayFieldHelp)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                MonoLabel(
                    model.guiltyField == .apiKey
                        ? ConnectHostCopy.keyNeedsAttention
                        : ConnectHostCopy.keyFieldLabel,
                    weight: .medium,
                    tracking: Design.Tracking.monoXWide,
                    color: labelColor(for: .apiKey)
                )
                Spacer()
                // #309 Lane B / spec §3.5: the reveal exists ONLY pre-commit.
                // After a commit the key reads "IN KEYCHAIN" forever, which is
                // rendered by the connected card — not by this field.
                Button {
                    model.isKeyRevealed.toggle()
                } label: {
                    MonoLabel(
                        model.isKeyRevealed ? "HIDE" : ConnectHostCopy.keyRevealPrompt,
                        weight: .medium, tracking: Design.Tracking.mono,
                        color: Design.Brand.accentText
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isKeyRevealed ? "Hide API key" : "Reveal API key")
            }

            Group {
                if model.isKeyRevealed {
                    TextField(ConnectHostCopy.keyFieldPlaceholder, text: $model.draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(ConnectHostCopy.keyFieldPlaceholder, text: $model.draft.apiKey)
                        .textInputAutocapitalization(.never)
                }
            }
            .focused($focusedField, equals: .apiKey)
            .font(Design.Typography.mono(13, weight: .regular))
            .foregroundStyle(Design.Colors.coolForeground)
            .padding(Design.Spacing.md)
            .background(Design.Colors.background.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(borderColor(for: .apiKey), lineWidth: 1)
            }
            .accessibilityLabel("API key")

            if showsHelp {
                Text(keyHelp)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    private func labelColor(for field: ConnectHostField) -> Color {
        model.guiltyField == field ? Design.Brand.forgeText : Design.Colors.secondaryForeground
    }

    private func borderColor(for field: ConnectHostField) -> Color {
        model.guiltyField == field ? Design.Brand.forge.opacity(0.6) : Design.Colors.strongBorder
    }
}

/// The connected host card — design A5 (wizard) and A4/B2 (settings).
///
/// Every row is stored or measured. `LAST ANSWERED` prints `NOT CHECKED` when
/// nothing has been measured in this launch, rather than borrowing a
/// plausible-looking time.
struct ConnectHostCard: View {
    let host: ConnectedHost

    var body: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.xl) {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                HStack(spacing: Design.Spacing.sm) {
                    StatusPip(color: statusColor, diameter: 8, blinks: isReachable)
                    Text(host.name)
                        .font(Design.Typography.display(19, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(Design.Colors.foregroundBright)
                    Spacer()
                }

                MonoLabel(host.reachability.label, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: statusColor)

                VStack(spacing: 0) {
                    Divider().overlay(Design.Colors.divider)
                    detailRow(ConnectHostCopy.addressRowLabel, host.address)
                    Divider().overlay(Design.Colors.divider)
                    // Design A5 vs A4: the card the WIZARD shows right after a
                    // green check can say ACCEPTED, because the probe just
                    // watched the host take the key. A card resting on a stored
                    // credential nobody has re-offered can only say where it
                    // lives — vocabulary rule 1, on one row.
                    detailRow(ConnectHostCopy.keyRowLabel, keyRowValue)
                    if let models = host.modelsSeen {
                        Divider().overlay(Design.Colors.divider)
                        detailRow(ConnectHostCopy.modelsSeenLabel, "\(models)")
                    }
                    Divider().overlay(Design.Colors.divider)
                    detailRow(ConnectHostCopy.lastAnsweredLabel, lastAnsweredLabel)
                }
            }
            .padding(Design.Spacing.lg)
        }
    }

    private var isReachable: Bool {
        if case .reachable = host.reachability { return true }
        return false
    }

    private var keyRowValue: String {
        guard host.hasStoredKey else { return ConnectHostCopy.keyNotStored }
        // `modelsSeen` is only ever non-nil because THIS launch's probe counted
        // them, so it is the honest marker for "just accepted".
        return (host.modelsSeen != nil && isReachable)
            ? ConnectHostCopy.keyAcceptedInKeychain
            : ConnectHostCopy.keyInKeychain
    }

    private var statusColor: Color {
        switch host.reachability {
        case .reachable: Design.Brand.accentText
        case .noAnswer: Design.Brand.forgeText
        // #350: unknown is not good news and not bad news — no accent, no alarm.
        case .notChecked: Design.Colors.secondaryForeground
        }
    }

    private var lastAnsweredLabel: String {
        guard let date = host.lastAnsweredAt else { return ConnectHostCopy.neverAnswered }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.sm) {
            MonoLabel(label, tracking: Design.Tracking.mono,
                      color: Design.Colors.mutedForeground)
            Spacer(minLength: Design.Spacing.sm)
            Text(value)
                .font(Design.Typography.mono(12, weight: .regular))
                .foregroundStyle(Design.Colors.coolForeground)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minHeight: Design.Size.minTapTarget - 12)
        .accessibilityElement(children: .combine)
    }
}

/// A failure card: forge-tinted, headline + blurb + the ladder that names the
/// guilty rung. Never danger-red — nothing has been destroyed, and nothing was
/// even saved.
struct ConnectHostFailureCard: View {
    let outcome: HostProbeOutcome
    let hostLabel: String

    var body: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.xl,
                 borderColor: Design.Brand.forge.opacity(0.4)) {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: symbol)
                        .font(.system(size: Design.Size.iconSmall, weight: .semibold))
                        .foregroundStyle(Design.Brand.forgeText)
                    MonoLabel(title, weight: .medium, tracking: Design.Tracking.monoXWide,
                              color: Design.Brand.forgeText)
                }

                Text(headline)
                    .font(Design.Typography.display(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Design.Colors.foregroundBright)

                Text(blurb)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var symbol: String {
        switch outcome {
        case .noAnswer: "antenna.radiowaves.left.and.right.slash"
        case .keyRefused: "key.slash"
        case .notHermes: "questionmark.square.dashed"
        case .connected: "checkmark.circle"
        }
    }

    private var title: String {
        switch outcome {
        case .noAnswer: ConnectHostCopy.noAnswerTitle
        case .keyRefused: ConnectHostCopy.keyRefusedTitle
        case .notHermes: ConnectHostCopy.notHermesTitle
        case .connected: ConnectHostCopy.hostConnectedTitle
        }
    }

    private var headline: String {
        switch outcome {
        case .noAnswer: ConnectHostCopy.noAnswerHeadline
        case .keyRefused: ConnectHostCopy.keyRefusedHeadline
        case .notHermes: ConnectHostCopy.notHermesHeadline
        case .connected: ConnectHostCopy.hostConnectedBlurb
        }
    }

    private var blurb: String {
        switch outcome {
        case .noAnswer:
            ConnectHostCopy.noAnswerBlurb
        case .keyRefused(let ms):
            // The measured latency is what exonerates the ADDRESS — it is the
            // evidence the sentence is built on, not decoration.
            ConnectHostCopy.keyRefusedBlurb(host: hostLabel, milliseconds: ms)
        case .notHermes:
            ConnectHostCopy.notHermesBlurb
        case .connected:
            ConnectHostCopy.hostConnectedBlurb
        }
    }
}
