import SwiftUI

/// **Settings → Connect Host (#309 Lane B).**
///
/// Replaces `ConnectHermesHostScreen` ("Pairing & Devices", #412) and the
/// relay half of the Server screen's profile editor. Eight states, one model,
/// and every claim on it either stored or measured — the convention #180's
/// ruling adopted from Owen's design.
///
/// What this screen does NOT do: it never writes a store on a keystroke, and
/// it never saves anything a probe has not just proved. Both are the model's
/// doing (`ConnectHostModel`, bar 309-B4); this file draws its state.
struct ConnectHostScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// Which profile this visit is about. `.activeProfile` for the ordinary
    /// entry; the roster hands a named one; "Add another host" hands `.newHost`.
    var target: ConnectHostTarget = .activeProfile

    @State private var model: ConnectHostModel?
    @State private var isScannerPresented = false
    @State private var scannerMessage: String?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if let model {
                content(model)
            }
        }
        .navigationTitle(ConnectHostCopy.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = ConnectHostModel(
                    environment: container.makeConnectHostEnvironment(target: target)
                )
            }
            model?.refreshFromStores()
        }
        .sheet(isPresented: scannerBinding) {
            ConnectHostScannerSheet(
                onPayload: { payload in
                    isScannerPresented = false
                    scannerMessage = nil
                    model?.apply(payload)
                },
                onTypeInstead: {
                    isScannerPresented = false
                    scannerMessage = nil
                },
                onFailure: { message in
                    isScannerPresented = false
                    scannerMessage = message
                }
            )
        }
        .sheet(isPresented: disconnectBinding) {
            if let model, let host = model.host {
                ConnectHostDisconnectSheet(host: host) {
                    Task { await model.confirmDisconnect() }
                } onCancel: {
                    model.isConfirmingDisconnect = false
                }
            }
        }
    }

    private var scannerBinding: Binding<Bool> {
        Binding(get: { isScannerPresented }, set: { isScannerPresented = $0 })
    }

    private var disconnectBinding: Binding<Bool> {
        Binding(
            get: { model?.isConfirmingDisconnect ?? false },
            set: { model?.isConfirmingDisconnect = $0 }
        )
    }

    @ViewBuilder
    private func content(_ model: ConnectHostModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                statusLine(model)

                switch model.presentation {
                case .empty, .ready, .checking, .failed:
                    editorBody(model)
                case .connected, .quiet, .disconnectConfirm:
                    restingBody(model)
                case .hostList:
                    rosterBody(model)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.lg)
        }
    }

    // MARK: Status line

    @ViewBuilder
    private func statusLine(_ model: ConnectHostModel) -> some View {
        MonoLabel(statusText(model), weight: .medium,
                  tracking: Design.Tracking.monoXWide, color: statusColor(model))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("connectHost.status")
    }

    private func statusText(_ model: ConnectHostModel) -> String {
        switch model.presentation {
        case .empty: ConnectHostCopy.statusNoHost
        case .ready: ConnectHostCopy.statusNotChecked
        case .checking: ConnectHostCopy.statusChecking
        case .failed:
            model.guiltyField == .apiKey
                ? ConnectHostCopy.statusCheckFailedKey
                : ConnectHostCopy.statusCheckFailedAddress
        case .connected, .disconnectConfirm:
            ConnectHostCopy.statusConnected(host: model.host?.name ?? "")
        case .quiet:
            ConnectHostCopy.statusNotAnswering(host: model.host?.name ?? "")
        case .hostList:
            ConnectHostCopy.statusHostCount(
                model.rosterEntries.count,
                active: model.rosterEntries.first(where: \.isActive)?.name ?? ""
            )
        }
    }

    private func statusColor(_ model: ConnectHostModel) -> Color {
        switch model.presentation {
        case .connected: Design.Brand.accentText
        // Forge, never danger-red: nothing is broken and nothing was lost.
        case .failed, .quiet: Design.Brand.forgeText
        default: Design.Colors.secondaryForeground
        }
    }

    // MARK: A1 / A2 / A3 / B1 — the editor

    @ViewBuilder
    private func editorBody(_ model: ConnectHostModel) -> some View {
        if model.presentation == .empty {
            runningLocallyCard
        }

        if let failure = model.failure {
            ConnectHostFailureCard(
                outcome: failure,
                hostLabel: model.draft.resolvedName
            )
            MonoLabel(ConnectHostCopy.nothingWasSaved, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                .accessibilityIdentifier("connectHost.nothingSaved")
        }

        if model.presentation == .checking, let ladder = model.ladder {
            ConnectHostLadderCard(ladder: ladder, address: model.draft.trimmedGateway)
        } else if model.presentation == .failed, let ladder = model.ladder {
            ConnectHostLadderCard(ladder: ladder, address: nil, showsFooter: false)
        }

        // Design A1 leads with the scanner; A2 demotes it to a row once typing
        // has started, and B1 offers it as the alternative to retyping a key.
        if model.draft.trimmedGateway.isEmpty && model.draft.trimmedKey.isEmpty {
            GlowButton(title: ConnectHostCopy.scanHostCode, systemImage: "qrcode.viewfinder") {
                isScannerPresented = true
            }
            .accessibilityIdentifier("connectHost.scan")
            MonoLabel(ConnectHostCopy.orTypeThem, tracking: Design.Tracking.monoWide)
                .frame(maxWidth: .infinity)
        } else {
            GhostButton(title: model.presentation == .failed
                        ? ConnectHostCopy.scanInstead
                        : ConnectHostCopy.scanAHostCodeInstead,
                        systemImage: "qrcode.viewfinder") {
                isScannerPresented = true
            }
        }

        if let scannerMessage {
            Text(scannerMessage)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Brand.forgeText)
        }

        ConnectHostFieldsCard(
            model: model,
            isDimmed: model.presentation == .checking,
            keyHelp: model.guiltyField == .apiKey
                ? ConnectHostCopy.keyFieldHelpScanHint
                : ConnectHostCopy.keyFieldHelpSettings
        )

        if model.presentation == .checking {
            GhostButton(title: ConnectHostCopy.cancel) { model.cancelCheck() }
        } else {
            GlowButton(title: model.presentation == .failed
                       ? ConnectHostCopy.checkAgain
                       : ConnectHostCopy.checkAndConnect) {
                model.startCheck()
            }
            .disabled(!model.canCheck)
            .opacity(model.canCheck ? 1 : 0.5)
            .accessibilityIdentifier("connectHost.check")

            Text(model.canCheck
                 ? ConnectHostCopy.savedOnlyIfTheHostAnswers
                 : ConnectHostCopy.bothValuesNeeded)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }

        onYourHostCard
        MonoLabel(ConnectHostCopy.keyFootnote, tracking: Design.Tracking.mono,
                  color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    /// Design A1's whole point: EMPTY IS NOT AN ERROR — the local brain is
    /// named as the current answer rather than as a missing one.
    private var runningLocallyCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.xl) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                HStack(spacing: Design.Spacing.sm) {
                    StatusPip(color: Design.Brand.accentText, diameter: 7, blinks: true)
                    Text(ConnectHostCopy.runningLocallyTitle)
                        .font(Design.Typography.display(17, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(Design.Colors.foregroundBright)
                }
                MonoLabel(ConnectHostCopy.runningLocallyBlurb,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var onYourHostCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                MonoLabel(ConnectHostCopy.onYourHostHeader, weight: .medium,
                          tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                Text(ConnectHostCopy.onYourHostCommandOne)
                    .font(Design.Typography.mono(12, weight: .regular))
                    .foregroundStyle(Design.Brand.accentText)
                Text(ConnectHostCopy.onYourHostCommandTwo)
                    .font(Design.Typography.mono(12, weight: .regular))
                    .foregroundStyle(Design.Brand.accentText)
                Text(ConnectHostCopy.onYourHostBlurb)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .padding(.top, Design.Spacing.xxs)
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: A4 / B2 — the resting card

    @ViewBuilder
    private func restingBody(_ model: ConnectHostModel) -> some View {
        if let host = model.host {
            ConnectHostCard(host: host)

            if host.reachability == .noAnswer {
                Text(ConnectHostCopy.stillSavedBlurb)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Design.Spacing.sm) {
                GhostButton(title: ConnectHostCopy.checkNow, systemImage: "arrow.clockwise") {
                    Task { await model.recheck() }
                }
                .disabled(model.isChecking)
                GhostButton(title: ConnectHostCopy.editAddress, systemImage: "pencil") {
                    model.beginEditingAddress()
                }
            }

            if model.isChecking, let ladder = model.ladder {
                ConnectHostLadderCard(ladder: ladder, address: host.address, showsFooter: false)
            }

            whatThisHostGivesCard(host)

            if host.reachability == .noAnswer {
                commonCausesCard
            }

            if model.rosterEntries.count > 1 {
                GhostButton(title: ConnectHostCopy.howSwitchingWorksHeader.replacingOccurrences(of: "// ", with: ""),
                            systemImage: "square.stack.3d.up") {
                    model.isShowingHostList = true
                }
            }

            disconnectRow(model, host: host)

            if let outcome = model.lastDisconnectOutcome, outcome == .forgottenHostNotTold {
                Text(ConnectHostCopy.disconnectedHostNotTold)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Brand.forgeText)
            }

            MonoLabel(ConnectHostCopy.chatKeepsWorkingFootnote, tracking: Design.Tracking.mono,
                      color: Design.Colors.dimForeground)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func whatThisHostGivesCard(_ host: ConnectedHost) -> some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                MonoLabel(ConnectHostCopy.whatThisHostGives, weight: .medium,
                          tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                VStack(spacing: 0) {
                    // Real data only (#45): the model count is what the probe
                    // counted, and "—" when nothing has counted yet.
                    giveRow(ConnectHostCopy.desktopModelsRow,
                            host.modelsSeen.map { "\($0) SEEN" } ?? "—")
                    Divider().overlay(Design.Colors.divider)
                    giveRow(ConnectHostCopy.serverSessionsRow, ConnectHostCopy.serverSessionsOn)
                    Divider().overlay(Design.Colors.divider)
                    // Reads the REAL toggle (Settings → Privacy → Share
                    // Sensors with Hermes), which is what spec §4.3 asked be
                    // verified rather than described from the mockup.
                    giveRow(ConnectHostCopy.sensorSharingRow,
                            settingsStore.settings.sensorStreamingEnabled
                                ? ConnectHostCopy.sensorSharingOn
                                : ConnectHostCopy.sensorSharingOff)
                }
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func giveRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            MonoLabel(value, tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
        }
        .frame(minHeight: Design.Size.minTapTarget - 8)
    }

    private var commonCausesCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                MonoLabel(ConnectHostCopy.commonCausesHeader, weight: .medium,
                          tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                Text(ConnectHostCopy.commonCausesBlurb)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func disconnectRow(_ model: ConnectHostModel, host: ConnectedHost) -> some View {
        Button {
            model.isConfirmingDisconnect = true
        } label: {
            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.dangerText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ConnectHostCopy.disconnectRow)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.dangerText)
                    // The blurb tells the truth about BOTH halves, and which
                    // truth depends on what has been MEASURED about the host —
                    // bar 309-B6's copy-follows-mechanism rule, in three
                    // states because there are three answers.
                    Text(Self.disconnectBlurb(for: host))
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .frame(minHeight: Design.Size.minTapTarget)
            .padding(.vertical, Design.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("connectHost.disconnect")
    }

    /// The disconnect row's blurb, per measured state. Extracted and `static`
    /// so a test can pin all three without building a view.
    // harness-visible
    static func disconnectBlurb(for host: ConnectedHost) -> String {
        switch host.reachability {
        case .reachable: ConnectHostCopy.disconnectRowBlurb(host: host.name)
        case .noAnswer: ConnectHostCopy.disconnectRowBlurbUnreachable(host: host.name)
        case .notChecked: ConnectHostCopy.disconnectRowBlurbUnknown(host: host.name)
        }
    }

    // MARK: B3 — more than one machine

    @ViewBuilder
    private func rosterBody(_ model: ConnectHostModel) -> some View {
        ForEach(model.rosterEntries) { entry in
            Button {
                Task {
                    await model.activate(profileID: entry.id)
                    model.isShowingHostList = false
                }
            } label: {
                rosterCard(entry)
            }
            .buttonStyle(.plain)
        }

        GhostButton(title: ConnectHostCopy.addAnotherHost, systemImage: "plus") {
            model.isShowingHostList = false
            router.navigate(to: .connectHost(nil))
        }

        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                MonoLabel(ConnectHostCopy.howSwitchingWorksHeader, weight: .medium,
                          tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.mutedForeground)
                Text(ConnectHostCopy.howSwitchingWorksBlurb)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GhostButton(title: "Done") { model.isShowingHostList = false }
    }

    private func rosterCard(_ entry: ConnectHostRosterEntry) -> some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                HStack(spacing: Design.Spacing.sm) {
                    Text(entry.name)
                        .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(Design.Colors.foregroundBright)
                    if entry.isActive {
                        MonoLabel(ConnectHostCopy.inUseTag, weight: .medium,
                                  tracking: Design.Tracking.mono, color: Design.Brand.accentText)
                    }
                    Spacer()
                }
                Text(entry.address)
                    .font(Design.Typography.mono(12, weight: .regular))
                    .foregroundStyle(Design.Colors.coolForeground)
                HStack(spacing: Design.Spacing.md) {
                    MonoLabel(entry.reachability.label, tracking: Design.Tracking.mono,
                              color: rosterStatusColor(entry.reachability))
                    MonoLabel(entry.keyState.label, tracking: Design.Tracking.mono,
                              color: entry.keyState == .stored
                                  ? Design.Colors.mutedForeground
                                  : Design.Brand.forgeText)
                }
            }
            .padding(Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rosterStatusColor(_ reachability: ConnectHostRosterEntry.Reachability) -> Color {
        switch reachability {
        case .reachable: Design.Brand.accentText
        case .noAnswer: Design.Brand.forgeText
        case .notChecked: Design.Colors.mutedForeground
        }
    }
}
