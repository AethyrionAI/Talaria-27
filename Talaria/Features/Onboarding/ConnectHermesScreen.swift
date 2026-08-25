import SwiftUI

struct ConnectHermesScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var setupCode = ""
    // #406: keystrokes edit THIS, not the stores. Every store write from
    // this field fires AppContainer's relay-config hook — a session clear
    // plus a forced bootstrap + inbox load while unpaired — so a per-
    // keystroke write burns ~2 doomed HTTP attempts per character against
    // hosts like "http://1". Commits happen at pair attempt and dismissal.
    @State private var relayURLDraft = ""
    @State private var isScannerPresented = false
    @State private var isManualEntryVisible = false
    @State private var localErrorMessage: String?
    @FocusState private var isSetupCodeFocused: Bool

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            CornerBrackets(arm: Design.Size.bracket, lineWidth: 1.5, inset: Design.Spacing.md)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    heroSection
                    reticleSection
                    entryOptions

                    if isManualEntryVisible {
                        relayConfigurationCard
                        manualEntryCard
                    }

                    if let errorMessage {
                        errorCard(message: errorMessage)
                    }

                    footnoteSection
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.vertical, Design.Spacing.lg)
            }
        }
        .sheet(isPresented: $isScannerPresented) {
            scannerSheet
        }
        .onChange(of: setupCode) { _, newValue in
            let formatted = PhonePairingCode.format(newValue)
            if formatted != newValue {
                setupCode = formatted
            }
        }
        .onAppear {
            relayURLDraft = currentRelayURL
        }
        // Lane M (M-12): a per-profile pair target must not outlive the
        // pairing flow — leaving the screen clears it (success already did).
        .onDisappear {
            // #406: commit BEFORE the target id clears — the commit resolves
            // its destination profile through pairingTargetProfileID.
            commitRelayDraft()
            pairingStore.pairingTargetProfileID = nil
        }
    }

    // MARK: - Lane M: pair target (M-12)

    /// The profile this pairing writes into: the named target from the
    /// Server screen's per-profile Pair action, else the active profile.
    private var targetProfile: BackendProfile? {
        container.profilesStore?.resolvedProfile(id: pairingStore.pairingTargetProfileID)
    }

    // MARK: - Hero (reactor orb + wordmark)

    private var heroSection: some View {
        VStack(spacing: Design.Spacing.xs) {
            ReactorOrb(size: Design.Size.orbOnboarding, style: .onboarding)

            Text("TALARIA")
                .font(Design.Typography.display(25, weight: .bold, relativeTo: .title))
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)
                .padding(.top, Design.Spacing.xs)

            MonoLabel("ESTABLISH UPLINK", tracking: Design.Tracking.monoWide)

            // #31: pairing is the upgrade, not the entry fee — chat already
            // works on-device before this screen is ever opened.
            Text("Chat already works on-device. Connecting your Hermes desktop adds server sessions, sensor analytics, and desktop models.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)
                .padding(.top, Design.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing.md)
    }

    // MARK: - QR reticle

    private var reticleSection: some View {
        VStack(spacing: Design.Spacing.lg) {
            QRReticle()
                .frame(width: 210, height: 210)

            MonoLabel("POINT AT HOST DISPLAY", tracking: Design.Tracking.monoXWide)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing.sm)
    }

    private var relayConfigurationCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                // Lane M (M-12): pairing writes into ONE named profile's slot
                // — say which, so pairing the Mac never reads as touching
                // OJAMD. (The hosted-relay mode is retired, M-13.)
                MonoLabel(
                    "RELAY · \((targetProfile?.name ?? "HERMES").uppercased())",
                    weight: .medium, tracking: Design.Tracking.monoXWide,
                    color: Design.Colors.secondaryForeground
                )

                TextField("https://your-relay.example.com/v1", text: $relayURLDraft)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .font(Design.Typography.mono(13, weight: .regular))
                    .foregroundStyle(Design.Colors.coolForeground)
                    .padding(Design.Spacing.md)
                    .background(Design.Colors.background.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.strongBorder, lineWidth: 1)
                    }
                    .accessibilityLabel("Relay URL")

                Text("This should be your relay API base URL. The app will append pairing and chat endpoints to it.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)

                if let relayValidationMessage {
                    Text(relayValidationMessage)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Brand.forgeText)
                }
            }
            .padding(Design.Spacing.lg)
        }
    }

    private var entryOptions: some View {
        VStack(spacing: Design.Spacing.sm) {
            GlowButton(title: "Scan QR Code", systemImage: "qrcode.viewfinder") {
                localErrorMessage = nil
                isScannerPresented = true
            }
            .accessibilityLabel("Scan QR Code")

            GhostButton(title: "Enter Code Manually", systemImage: "number") {
                localErrorMessage = nil
                withAnimation(Design.Motion.standard) {
                    isManualEntryVisible = true
                }
                isSetupCodeFocused = true
            }
            .accessibilityLabel("Enter Code Manually")
        }
    }

    private var manualEntryCard: some View {
        HUDPanel(cornerRadius: Design.CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                HStack(spacing: Design.Spacing.sm) {
                    let line = Rectangle()
                        .fill(Design.Colors.divider)
                        .frame(height: 1)
                    line
                    MonoLabel("OR ENTER 8-DIGIT CODE", tracking: Design.Tracking.monoWide)
                        .fixedSize()
                    line
                }

                // Visual cyan code boxes overlaying the real (hidden) TextField,
                // so every existing binding / formatting rule stays intact.
                ZStack {
                    CodeBoxRow(code: setupCode, isFocused: isSetupCodeFocused)
                        .allowsHitTesting(false)

                    TextField("", text: $setupCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($isSetupCodeFocused)
                        .foregroundStyle(.clear)
                        .tint(.clear)
                        .accentColor(.clear)
                        .accessibilityLabel("Setup code")
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { isSetupCodeFocused = true }

                Text("Find this on your host under Settings → Devices → Pair Phone.")
                    .font(Design.Typography.mono(10, weight: .regular))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                GlowButton(title: "Pair Device") {
                    Task { await completePairing(using: setupCode) }
                }
                .opacity(pairingStore.isWorking ? 0 : 1)
                .overlay {
                    if pairingStore.isWorking {
                        ProgressView()
                            .tint(Design.Colors.foregroundBright)
                    }
                }
                .disabled(isPairDisabled)
                .opacity(isPairDisabled && !pairingStore.isWorking ? 0.5 : 1)
                .accessibilityLabel("Connect Hermes")
            }
            .padding(Design.Spacing.lg)
        }
    }

    private var isPairDisabled: Bool {
        pairingStore.isWorking || !PhonePairingCode.isComplete(setupCode) || !isRelayConfigurationValid
    }

    private var footnoteSection: some View {
        MonoLabel(
            "END-TO-END ENCRYPTED · DEVICE-BOUND KEY",
            tracking: Design.Tracking.monoWide,
            color: Design.Colors.dimForeground
        )
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, Design.Spacing.sm)
    }

    private var scannerSheet: some View {
        Group {
            if SetupCodeScannerView.isScannerAvailable {
                SetupCodeScannerView(
                    onCodeDetected: { scannedValue in
                        isScannerPresented = false
                        handleScannedValue(scannedValue)
                    },
                    onFailure: { message in
                        isScannerPresented = false
                        localErrorMessage = message
                    }
                )
                .ignoresSafeArea()
            } else {
                ZStack {
                    HUDScreenBackground()
                        .ignoresSafeArea()

                    ContentUnavailableView {
                        Label("Scanner Unavailable", systemImage: "qrcode.viewfinder")
                            .foregroundStyle(Design.Colors.foreground)
                    } description: {
                        Text("QR scanning is not available here. Use the pairing code option instead.")
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    } actions: {
                        GlowButton(title: "Use Pairing Code") {
                            isScannerPresented = false
                            isManualEntryVisible = true
                            isSetupCodeFocused = true
                        }
                        .padding(.horizontal, Design.Spacing.xl)
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var errorMessage: String? {
        pairingStore.lastErrorMessage ?? localErrorMessage
    }

    /// The STORED relay URL for this pairing's target — the TARGET profile's
    /// endpoint (Lane M), falling back to the legacy settings field only in
    /// profile-less constructions. #406: this seeds the draft on appear;
    /// live edits read `relayURLDraft`, and the stores are written only at
    /// the commit moments (pair attempt, QR, dismissal).
    private var currentRelayURL: String {
        // #310: behaviour preserved deliberately. A target profile that
        // exists but carries NO relay resolves to "" (→ "Enter your relay
        // URL."), NOT to the legacy settings field — falling through would
        // silently pair a gateway-only profile against whatever relay the
        // pre-profile record happened to remember.
        if let targetProfile {
            return targetProfile.relayBaseURL ?? ""
        }
        return settingsStore.settings.relayConfiguration.customRelayBaseURL
    }

    private var relayValidationMessage: String? {
        // #406: validation and the pair button's enablement read the DRAFT —
        // the stores may lag it until a commit moment, by design.
        let trimmed = relayURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter your relay URL." }
        guard RelayConfiguration.normalizeBaseURL(trimmed) != nil else {
            return "Relay URL must be an absolute http(s) URL ending with /v1."
        }
        return nil
    }

    private var isRelayConfigurationValid: Bool {
        relayValidationMessage == nil
    }

    /// Writes the TARGET profile's relay endpoint (Lane M): pairing the Mac
    /// must never rewrite OJAMD's relay URL. The legacy settings field is
    /// mirror-written only when the target IS the active profile, keeping the
    /// pre-profile record coherent.
    private func setRelayURL(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profilesStore = container.profilesStore, let target = targetProfile {
            var updated = target
            updated.relayBaseURL = trimmed
            profilesStore.upsert(updated)
            if target.id == profilesStore.activeProfileID {
                // #405: DIRECT assignment, never the canonicalizing init —
                // this setter runs per KEYSTROKE, and canonicalizing the
                // mid-draft "http://" rewrites it to "http:/v1" under the
                // user's cursor (measured; the remaining keystrokes then
                // append). Normalization stays on the read side
                // (activeBaseURLString) and in validation, where it belongs.
                settingsStore.settings.relayConfiguration.customRelayBaseURL = trimmed
            }
        } else {
            // #405: same rule as the mirror-write above.
            settingsStore.settings.relayConfiguration.customRelayBaseURL = trimmed
        }
    }

    /// #406: the single door from the draft to the stores. Writing the
    /// stores fires AppContainer's relay-config hook (session clear +
    /// forced bootstrap + inbox load while unpaired), so this runs only at
    /// commit moments — never per keystroke. `SettingsStore`'s didSet
    /// no-ops on unchanged values, so committing an untouched draft is free.
    private func commitRelayDraft() {
        setRelayURL(relayURLDraft)
    }

    /// Parse a QR code value — either a JSON payload `{"code":"...","relay":"..."}` or a plain pairing code.
    /// When JSON includes a relay URL, auto-configures the TARGET profile's relay before pairing.
    private func handleScannedValue(_ value: String) {
        // Try JSON payload first (new format from connector)
        if let data = value.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String {
            // Auto-fill relay URL from QR if present. #406: into the DRAFT —
            // the commit rides completePairing below, so a failed pair still
            // shows the scanned URL in the field rather than losing it.
            if let relay = json["relay"] as? String, !relay.isEmpty {
                relayURLDraft = relay
            }
            Task { await completePairing(using: code) }
            return
        }

        // Fall back to plain pairing code (backward compatible)
        Task { await completePairing(using: value) }
    }

    private func completePairing(using rawCode: String) async {
        guard isRelayConfigurationValid else {
            localErrorMessage = relayValidationMessage
            return
        }
        // #406: the redeem reads the stores, not the draft — commit first.
        commitRelayDraft()
        let didPair = await pairingStore.pair(using: rawCode)
        if didPair {
            localErrorMessage = nil
            // #31: this screen now lives on the Settings→Connect nav path —
            // clear it so the post-onboarding return lands in chat, not here.
            router.popToRoot()
        } else if pairingStore.lastErrorMessage == nil {
            localErrorMessage = PhonePairingCodeError.invalidFormat.localizedDescription
        }
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Design.Size.iconSmall, weight: .semibold))
                .foregroundStyle(Design.Brand.forge)

            Text(message)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.lg,
                  borderColor: Design.Brand.forge.opacity(0.4))
    }
}

// MARK: - QR reticle (decorative targeting frame)

private struct QRReticle: View {
    var body: some View {
        ZStack {
            // Inner hatch + crosshair surface
            RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                .fill(Design.Colors.surfaceTint)
                .overlay {
                    DiagonalHatch()
                        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
                }
                .overlay {
                    Crosshair()
                }
                .overlay {
                    ScanLine(duration: Design.Motion.reticleDuration, height: 3, intensity: 1.0)
                        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                        .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                }
                .padding(14)

            // Large cyan targeting brackets
            CornerBrackets(arm: 34, lineWidth: 2, color: Design.Brand.accent)
        }
        .accessibilityHidden(true)
    }
}

/// Faint cyan diagonal hatch fill (matches the reference's repeating-linear-gradient).
private struct DiagonalHatch: View {
    var body: some View {
        Canvas { context, size in
            let stroke = GraphicsContext.Shading.color(Design.Colors.accentTint(0.10))
            let step: CGFloat = 16
            var x: CGFloat = -size.height
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                context.stroke(path, with: stroke, lineWidth: 8)
                x += step
            }
        }
        .allowsHitTesting(false)
    }
}

/// Center cyan crosshair (two short glowing strokes).
private struct Crosshair: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Design.Colors.accentTint(0.5))
                .frame(width: 46, height: 1)
            Rectangle()
                .fill(Design.Colors.accentTint(0.5))
                .frame(width: 1, height: 46)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Code box row (cyan mono digit boxes)

/// A visual row of cyan-bordered mono character boxes reflecting `code`
/// (formatted `ABCD-EFGH`). Purely presentational — bindings live on the
/// overlaid TextField. The active box gets a bright border, glow, and a
/// blinking caret.
private struct CodeBoxRow: View {
    let code: String
    let isFocused: Bool

    private static let codeLength = 8
    private static let separatorIndex = 4

    /// Stripped (no dash) uppercased characters, capped to the code length.
    private var characters: [Character] {
        Array(
            code.uppercased()
                .replacingOccurrences(of: "-", with: "")
                .prefix(Self.codeLength)
        )
    }

    /// Index of the next empty box (the active one), or nil if full.
    private var activeIndex: Int? {
        let count = characters.count
        return count < Self.codeLength ? count : nil
    }

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            box(at: 0)
            box(at: 1)
            box(at: 2)
            box(at: 3)
            Text("–")
                .font(Design.Typography.display(16, weight: .medium, relativeTo: .body))
                .foregroundStyle(Design.Colors.dimForeground)
            box(at: 4)
            box(at: 5)
            box(at: 6)
            box(at: 7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func box(at index: Int) -> some View {
        let char: Character? = index < characters.count ? characters[index] : nil
        let isActive = isFocused && activeIndex == index

        ZStack {
            RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                .fill(isActive ? Design.Colors.accentTint(0.08) : Design.Colors.background.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                        .strokeBorder(
                            char != nil ? Design.Colors.strongBorder
                                : (isActive ? Design.Brand.accentText : Design.Colors.divider),
                            lineWidth: isActive ? 1.5 : 1
                        )
                }

            if let char {
                Text(String(char))
                    .font(Design.Typography.display(20, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(Design.Colors.foregroundBright)
            } else if isActive {
                Caret()
            }
        }
        .frame(width: 30, height: 44)
        .modifier(ActiveGlow(active: isActive))
    }
}

private struct ActiveGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.hudGlow(Design.Brand.accent, radius: 14, strength: 0.5)
        } else {
            content
        }
    }
}

/// Blinking cyan caret for the active code box.
private struct Caret: View {
    var body: some View {
        Text("▍")
            .font(Design.Typography.display(20, weight: .medium, relativeTo: .title2))
            .foregroundStyle(Design.Brand.accentText)
            .hudPulse(Design.Motion.caret, from: 1.0, to: 0.0)
    }
}
