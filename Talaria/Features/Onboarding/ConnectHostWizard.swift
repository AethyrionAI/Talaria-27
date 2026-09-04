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

    /// #219 (bar DET-A): is the UITest fixture seam armed for THIS step?
    /// Always `false` in Release, and the DEBUG-only type is named only inside
    /// the `#if` — so a Release build carries no reference to it (#218: a
    /// `#if DEBUG` declaration that production code read broke `main`'s Release
    /// build for two days).
    private var isUITestTapBlockFixtureArmed: Bool {
        #if DEBUG
        step == .done && UITestWizardBlockingOverlay.isEnabled
        #else
        false
        #endif
    }

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
                    // A user who scrolls has already told us they want to see
                    // what the keyboard is covering.
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            // #219: half of the fixture seam — and NOT the half that makes
            // anything un-hittable. Turning interaction off here is what makes
            // the fallback tap get SWALLOWED, which is what leaves the wizard
            // standing for the fixture to assert on. It does not change
            // `isHittable` at all: probe 2 of 2026-09-04 had this modifier AND
            // a tap-consuming overlay in place, the tap was genuinely eaten
            // (the wizard stayed up), and XCUITest still reported
            // `isHittable == true`. The lever that decides hittability is the
            // overlay's own accessibility sort priority — stated once, in
            // `UITestWizardBlockingOverlay`.
            // Inert in Release — see `isUITestTapBlockFixtureArmed`.
            .allowsHitTesting(!isUITestTapBlockFixtureArmed)

            #if DEBUG
            // The named blocker, mounted on the DONE step only so the earlier
            // steps stay drivable. It is full-screen, and the modifier above
            // disables the whole step — so it is the DONE step's controls that
            // lose their hit point, of which START CHATTING (the tap that
            // flakes) is the one the fixture takes.
            if isUITestTapBlockFixtureArmed {
                UITestWizardBlockingOverlay()
            }
            #endif
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
                    // **Put the keyboard away before the ladder appears.** The
                    // fields dim for the duration anyway, so a keyboard over a
                    // spinner is noise — and on the step that follows it can
                    // sit over the primary action, which is how CONTINUE ends
                    // up present-but-unreachable.
                    dismissKeyboard()
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

                    // **CONTINUE sits ABOVE the details card, not below it.**
                    // Design A5 draws it under, and on a phone that puts the
                    // step's only forward action below a card whose height
                    // grows with what the probe found (MODELS SEEN appears
                    // only when there is a count) — so on a short screen it
                    // lands below the fold. MEASURED: a gate run reported the
                    // button present and `isHittable=false`, with no keyboard
                    // and no alert, and re-tapping it thirty times changed
                    // nothing because the taps were landing on whatever WAS at
                    // those coordinates.
                    //
                    // The confirmation the user needs is the headline above;
                    // the card is detail, and detail can scroll.
                    GlowButton(title: ConnectHostCopy.carryOn) {
                        commitName(model)
                        step = .done
                    }
                    .accessibilityIdentifier("connectHostWizard.continue")

                    ConnectHostCard(host: host)

                    // "Name this host" is editable HERE and later (the profile
                    // name) — spec §3.4.
                    //
                    // **#406's rule applies to the LABEL too.** An earlier
                    // draft bound this straight through `renameConnectedHost`,
                    // which upserts the profile — a UserDefaults write plus a
                    // Keychain-mirror write PER KEYSTROKE, which is the exact
                    // shape this lane exists to remove, just with a cheaper
                    // payload. The field edits the draft; the commit moments
                    // are submit and CONTINUE.
                    // An explicit Binding, not `$model`: the view's `model` is
                    // an OPTIONAL `@State`, and `$model` projects THAT rather
                    // than the non-optional one this step was handed.
                    TextField(
                        ConnectHostCopy.nameThisHost,
                        text: Binding(get: { model.draft.name },
                                      set: { model.draft.name = $0 })
                    )
                        .onSubmit { commitName(model) }
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
            } else {
                // **A step that can render NOTHING is a dead end with no name,
                // and #180's convention forbids exactly that.** The three
                // branches above cover checking, failed, and connected; a
                // fourth state — not checking, no failure, no host — should be
                // unreachable, and if it ever happens the user must get a
                // sentence and a way out rather than a blank screen under two
                // chrome buttons. (It is also what would have made the
                // full-bundle failure diagnose itself instead of presenting as
                // "the button never appeared".)
                ConnectHostFailureCard(
                    outcome: .noAnswer(detail: "NO ANSWER"),
                    hostLabel: model.draft.resolvedName
                )
                GlowButton(title: ConnectHostCopy.tryAgain) { step = .connect }
                    .accessibilityIdentifier("connectHostWizard.recover")
                GhostButton(title: ConnectHostCopy.keepChattingLocally) { landInChat() }
            }
        }
    }

    /// The label's commit moment. Idempotent and no-ops on an unchanged or
    /// empty name, so calling it from two places costs nothing.
    private func commitName(_ model: ConnectHostModel) {
        container.renameConnectedHost(to: model.draft.name, target: target)
        model.refreshFromStores()
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

    /// The responder-chain hammer. SwiftUI has no first-class "resign whatever
    /// is focused" for a `@FocusState` owned by a child view, and the fields
    /// live in `ConnectHostFieldsCard`; routing focus out of that component
    /// just to dismiss a keyboard would put a second source of truth for focus
    /// into a shared view.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

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

#if DEBUG
/// **#219 DET-A fixture seam.** Reproduces on demand the one failure shape the
/// suite has never been able to reproduce: START CHATTING present at its normal
/// frame, and no hit point for it.
///
/// The gate has lost roughly one run a month to a tap that lands without
/// invoking its action, and every attempt to diagnose it has had to wait for
/// the flake to happen again — which is why a month of gate runs produced no
/// evidence. A seam turns "wait and hope" into a test that runs in seconds.
///
/// Same shape as `MessageListIdentityProbe`'s `UITEST_DUPID_PROBE` gate: a
/// launch-environment flag, read once (launch env is immutable for the process
/// lifetime), absent from the view tree otherwise. One difference, and it is
/// deliberate — this is wrapped in `#if DEBUG`, so a Release build carries no
/// trace of it at all (#218: a `#if DEBUG` declaration that production code
/// read broke `main`'s Release build for two days, invisible to an all-Debug
/// stack of checks).
///
/// **Why 0.1% alpha rather than a fully clear fill.** The overlay's only job is
/// to be what the accessibility hit-test finds at the button's centre. A fixture
/// that silently stopped intercepting would turn the DET-A pin green while
/// proving nothing, so the layer is painted rather than trusting `.clear` to be
/// hit-testable in every rendering path. At 0.001 opacity it is invisible.
private struct UITestWizardBlockingOverlay: View {
    static let identifier = "uitest.overlayBlocksWizard"

    /// **How many taps this layer has swallowed, published as its
    /// accessibility VALUE.**
    ///
    /// Without it neither fixture could tell a tap from no tap: asserting the
    /// outcome case, the `via` arm, the diagnostic's contents and "the wizard
    /// is still up" is all equally satisfied by a helper that emitted the
    /// activities and never tapped at all — which is precisely the claim the
    /// A/B rests on. The counter is the only thing here that goes up *because
    /// a tap was issued*, so it is also the arm's isolating mutation: delete
    /// the fallback tap and both fixtures red on this number.
    @State private var swallowedTaps = 0

    /// Launch-env gate. Inert (and absent from the tree) unless set.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_OVERLAY_BLOCKS_WIZARD"] == "1"
    }

    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.001))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            // A gesture, so the layer genuinely CONSUMES the tap instead of
            // merely sitting over it — the swallowed tap is the whole point of
            // the fixture, and a tap that fell through to the button would
            // complete the connect and prove nothing. It COUNTS what it
            // swallows, which is the only observable a helper that never
            // tapped would fail to produce.
            .onTapGesture { swallowedTaps += 1 }
            // An accessibility element, so the helper's centre-point walk can
            // NAME it rather than reporting an anonymous blocker.
            .accessibilityElement()
            .accessibilityIdentifier(Self.identifier)
            .accessibilityLabel("uitest overlay")
            .accessibilityValue("\(swallowedTaps)")
            // **The lever that actually decides hittability, measured the hard
            // way.** XCUITest resolves "what is on top of this point" from the
            // ORDER of the accessibility snapshot, not from the app's hit
            // testing — and SwiftUI reports a ZStack front-to-back, so the
            // front-most view lands FIRST in the tree and reads as the one
            // underneath. A low sort priority puts this layer last, which is
            // where XCUITest looks for the thing on top.
            .accessibilitySortPriority(-1000)
    }
}
#endif

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
