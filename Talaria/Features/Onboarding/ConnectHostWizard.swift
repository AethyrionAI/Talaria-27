import SwiftUI

/// **The Connect Host wizard (#309 Lane B, bar 309-B1).**
///
/// > THE WIZARD IS ENTERED, NEVER IMPOSED.
///
/// That line is the design's own reading of Owen's "skippable wizard" ruling,
/// and it is stricter than what was ruled: there is **no first-launch trigger
/// at all.** Its only entry point is the Settings **Connect Host** row on an
/// install that has no host yet — so first launch still lands in working local
/// chat (#31's no-pairing-wall stance, untouched), and "first-time setup"
/// means "the first time you tap Connect Host."
///
/// **"Not now" is on every step**, and taking it lands in plain chat: no
/// banner, no nag, no empty host slot where a host should be (design B7).
/// Skipping is a finished state, not a deferred one.
struct ConnectHostWizard: View {
    @Environment(AppContainer.self) private var container
    @Environment(TabRouter.self) private var router

    var target: ConnectHostTarget = .activeProfile

    enum Step: Int, CaseIterable, Comparable {
        case choice, connect, check, done
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @State private var step: Step = .choice
    @State private var model: ConnectHostModel?
    @State private var isManualEntryVisible = false
    @State private var isScannerPresented = false
    @State private var scannerMessage: String?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()
            CornerBrackets(arm: Design.Size.bracket, lineWidth: 1.5, inset: Design.Spacing.md)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                progressBars
                if let model {
                    ScrollView {
                        stepBody(model)
                            .padding(.horizontal, Design.Spacing.lg)
                            .padding(.vertical, Design.Spacing.lg)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            if model == nil {
                model = ConnectHostModel(
                    environment: container.makeConnectHostEnvironment(target: target)
                )
            }
        }
        .sheet(isPresented: $isScannerPresented) {
            ConnectHostScannerSheet(
                onPayload: { payload in
                    isScannerPresented = false
                    scannerMessage = nil
                    model?.apply(payload)
                    isManualEntryVisible = true
                },
                onTypeInstead: {
                    isScannerPresented = false
                    isManualEntryVisible = true
                },
                onFailure: { message in
                    isScannerPresented = false
                    scannerMessage = message
                }
            )
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            if step > .choice {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            // On EVERY step — bar 309-B1.
            Button { landInChat() } label: {
                Text(ConnectHostCopy.notNow)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            .accessibilityIdentifier("connectHostWizard.notNow")
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.md)
        .frame(minHeight: Design.Size.minTapTarget)
    }

    private var progressBars: some View {
        HStack(spacing: Design.Spacing.xs) {
            ForEach(Step.allCases, id: \.rawValue) { bar in
                Capsule()
                    .fill(bar <= step ? Design.Brand.accentText : Design.Colors.divider)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.sm)
        .accessibilityHidden(true)
    }

    // MARK: Steps

    @ViewBuilder
    private func stepBody(_ model: ConnectHostModel) -> some View {
        switch step {
        case .choice: choiceStep
        case .connect: connectStep(model)
        case .check: checkStep(model)
        case .done: doneStep(model)
        }
    }

    // MARK: Step 0 — the choice (design A1)

    private var choiceStep: some View {
        VStack(spacing: Design.Spacing.lg) {
            VStack(spacing: Design.Spacing.xs) {
                ReactorOrb(size: Design.Size.orbOnboarding, style: .onboarding)
                Text(ConnectHostCopy.wizardTitle)
                    .font(Design.Typography.display(25, weight: .bold, relativeTo: .title))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .padding(.top, Design.Spacing.xs)
                MonoLabel(ConnectHostCopy.wizardSubtitle, tracking: Design.Tracking.monoWide)
            }
            .frame(maxWidth: .infinity)

            // THE LOCAL PATH IS THE GLOWING ONE — no lock icons, no "limited",
            // no upgrade badge. Local is the recommendation, not the trial.
            Button { landInChat() } label: {
                choiceCard(
                    title: ConnectHostCopy.localOptionTitle,
                    badge: ConnectHostCopy.localOptionBadge,
                    blurb: ConnectHostCopy.localOptionBlurb,
                    footnote: ConnectHostCopy.localOptionFootnote,
                    isPrimary: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("connectHostWizard.startLocally")

            Button { step = .connect } label: {
                choiceCard(
                    title: ConnectHostCopy.hostOptionTitle,
                    badge: nil,
                    blurb: ConnectHostCopy.hostOptionBlurb,
                    footnote: ConnectHostCopy.hostOptionFootnote,
                    isPrimary: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("connectHostWizard.connectMyHost")

            Text(ConnectHostCopy.localIsNotATrial)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choiceCard(
        title: String, badge: String?, blurb: String, footnote: String, isPrimary: Bool
    ) -> some View {
        HUDPanel(
            cornerRadius: Design.CornerRadius.xl,
            borderColor: isPrimary ? Design.Colors.accentTint(0.55) : Design.Colors.hairline
        ) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                HStack(spacing: Design.Spacing.sm) {
                    Text(title)
                        .font(Design.Typography.display(18, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(Design.Colors.foregroundBright)
                    if let badge {
                        MonoLabel(badge, weight: .medium, tracking: Design.Tracking.mono,
                                  color: Design.Brand.accentText)
                    }
                    Spacer()
                    if !isPrimary {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Design.Colors.mutedForeground)
                    }
                }
                Text(blurb)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                MonoLabel(footnote, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
                    .padding(.top, Design.Spacing.xxs)
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(PrimaryChoiceGlow(active: isPrimary))
    }

    // MARK: Step 1 — connect (design A2/A3)

    @ViewBuilder
    private func connectStep(_ model: ConnectHostModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(ConnectHostCopy.scanTitle)
                    .font(Design.Typography.display(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Design.Colors.foregroundBright)
                Text(ConnectHostCopy.scanBlurb)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlowButton(title: ConnectHostCopy.openScanner, systemImage: "qrcode.viewfinder") {
                isScannerPresented = true
            }
            .accessibilityIdentifier("connectHostWizard.openScanner")

            if let scannerMessage {
                Text(scannerMessage)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Brand.forgeText)
            }

            if !isManualEntryVisible {
                HStack(spacing: Design.Spacing.sm) {
                    let rule = Rectangle().fill(Design.Colors.divider).frame(height: 1)
                    rule
                    MonoLabel("OR", tracking: Design.Tracking.monoWide).fixedSize()
                    rule
                }
                Button {
                    withAnimation(Design.Motion.standard) { isManualEntryVisible = true }
                } label: {
                    HStack {
                        Text(ConnectHostCopy.enterManually)
                            .font(Design.Typography.callout)
                            .foregroundStyle(Design.Brand.accentBrightText)
                        Spacer()
                        MonoLabel(ConnectHostCopy.enterManuallyDetail,
                                  tracking: Design.Tracking.mono,
                                  color: Design.Colors.mutedForeground)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Design.Colors.mutedForeground)
                    }
                    .frame(minHeight: Design.Size.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("connectHostWizard.enterManually")

                MonoLabel(ConnectHostCopy.scanSecrecyFootnote, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ConnectHostFieldsCard(
                    model: model,
                    keyHelp: ConnectHostCopy.keyFieldHelp
                )

                GlowButton(title: ConnectHostCopy.checkAndConnect) {
                    step = .check
                    model.startCheck()
                }
                .disabled(!model.canCheck)
                .opacity(model.canCheck ? 1 : 0.5)
                .accessibilityIdentifier("connectHostWizard.check")

                Text(ConnectHostCopy.nothingSavedUntilCheckPasses)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                MonoLabel(ConnectHostCopy.keyFootnote, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Step 2 — the ladder, then A5 or a named failure

    @ViewBuilder
    private func checkStep(_ model: ConnectHostModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            if model.isChecking {
                VStack(spacing: Design.Spacing.md) {
                    ReactorOrb(size: Design.Size.orbPanel, style: .standard)
                    ConnectHostLadderCard(
                        ladder: model.ladder ?? .running,
                        address: model.draft.trimmedGateway
                    )
                    GhostButton(title: ConnectHostCopy.cancel) {
                        model.cancelCheck()
                        step = .connect
                    }
                }
            } else if let failure = model.failure {
                ConnectHostFailureCard(outcome: failure, hostLabel: model.draft.resolvedName)
                ConnectHostLadderCard(
                    ladder: model.ladder ?? .running,
                    address: nil, showsFooter: false
                )

                // Only the guilty field comes back — with the measurement that
                // exonerates the other one still on screen above.
                ConnectHostFieldsCard(
                    model: model,
                    keyHelp: model.guiltyField == .apiKey
                        ? ConnectHostCopy.keyFieldHelpRetype
                        : ConnectHostCopy.keyFieldHelp
                )
                if case .notHermes = failure {
                    Text(ConnectHostCopy.notHermesFieldHint)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Brand.forgeText)
                }

                GlowButton(title: failure.isNoAnswer
                           ? ConnectHostCopy.tryAgain
                           : ConnectHostCopy.checkAgain) {
                    model.startCheck()
                }
                .disabled(!model.canCheck)
                MonoLabel(ConnectHostCopy.nothingWasSaved, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                    .frame(maxWidth: .infinity)
                // EVERY failure keeps the local exit visible — design B4's note.
                GhostButton(title: ConnectHostCopy.keepChattingLocally) { landInChat() }
            } else if let host = model.host {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Design.Brand.accentText)
                            .hudGlow(Design.Brand.accent, radius: 12, strength: 0.4)
                        Text(ConnectHostCopy.hostConnectedTitle)
                            .font(Design.Typography.display(20, weight: .bold, relativeTo: .title2))
                            .foregroundStyle(Design.Colors.foregroundBright)
                    }
                    Text(ConnectHostCopy.hostConnectedBlurb)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.secondaryForeground)

                    ConnectHostCard(host: host)

                    GlowButton(title: ConnectHostCopy.carryOn) { step = .done }
                        .accessibilityIdentifier("connectHostWizard.continue")

                    // "Name this host" is editable HERE and later (the profile
                    // name) — spec §3.4.
                    TextField(ConnectHostCopy.nameThisHost, text: nameBinding(model))
                        .font(Design.Typography.body(14, weight: .regular))
                        .foregroundStyle(Design.Colors.coolForeground)
                        .padding(Design.Spacing.md)
                        .background(Design.Colors.background.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                                .strokeBorder(Design.Colors.strongBorder, lineWidth: 1)
                        }
                        .accessibilityLabel("Name this host")
                }
            }
        }
    }

    private func nameBinding(_ model: ConnectHostModel) -> Binding<String> {
        Binding(
            get: { model.draft.name },
            set: { newValue in
                model.draft.name = newValue
                container.renameConnectedHost(to: newValue, target: target)
            }
        )
    }

    // MARK: Step 3 — done (design A6)

    @ViewBuilder
    private func doneStep(_ model: ConnectHostModel) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ConnectHostCopy.doneTitleTop)
                    .font(Design.Typography.display(30, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Design.Colors.foregroundBright)
                Text(ConnectHostCopy.doneTitleBottom)
                    .font(Design.Typography.display(30, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Design.Brand.accentText)
                    .hudGlow(Design.Brand.accent, radius: 18, strength: 0.35)
            }

            Text(ConnectHostCopy.doneBlurb(host: model.host?.name ?? model.draft.resolvedName))
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                doneRow(ConnectHostCopy.donePickModel, tag: ConnectHostCopy.donePickModelTag)
                Divider().overlay(Design.Colors.divider)
                doneRow(ConnectHostCopy.doneSensors, tag: ConnectHostCopy.doneSensorsTag)
                Divider().overlay(Design.Colors.divider)
                doneRow(ConnectHostCopy.doneAddAnother, tag: ConnectHostCopy.doneAddAnotherTag)
            }

            // The one job of a final step: say where all this lives afterwards.
            Text(ConnectHostCopy.doneWhereItLives)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            GlowButton(title: ConnectHostCopy.startChatting) { landInChat() }
                .accessibilityIdentifier("connectHostWizard.startChatting")
        }
    }

    private func doneRow(_ label: String, tag: String) -> some View {
        HStack {
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            MonoLabel(tag, tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
        }
        .frame(minHeight: Design.Size.minTapTarget - 6)
    }

    // MARK: Navigation

    private func goBack() {
        switch step {
        case .choice: landInChat()
        case .connect: step = .choice
        case .check: step = .connect
        case .done: step = .check
        }
    }

    /// Every exit from this flow ends in the same place: plain chat.
    private func landInChat() {
        router.popToRoot()
    }
}

/// The recommended card glows; the other does not. A modifier so the glow can
/// be absent rather than zero-strength — `hudGlow` on every card would make
/// "recommended" a shade rather than a signal.
private struct PrimaryChoiceGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.hudGlow(Design.Brand.accent, radius: 26, strength: 0.3)
        } else {
            content
        }
    }
}
