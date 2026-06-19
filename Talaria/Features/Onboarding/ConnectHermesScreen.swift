import SwiftUI

struct ConnectHermesScreen: View {
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore

    @State private var setupCode = ""
    @State private var isScannerPresented = false
    @State private var isManualEntryVisible = false
    @State private var localErrorMessage: String?
    @FocusState private var isSetupCodeFocused: Bool

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    heroSection
                    entryOptions

                    if isManualEntryVisible {
                        relayConfigurationCard
                        manualEntryCard
                    }

                    if let errorMessage {
                        errorCard(message: errorMessage)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
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
    }

    // Hermes caduceus — braille art from the Hermes Agent TUI
    private static let caduceus = """
    ⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⣀⣀⠀⢀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⢀⣠⣴⣾⣿⣿⣇⠸⣿⣿⠇⣸⣿⣿⣷⣦⣄⡀⠀⠀⠀⠀⠀
    ⢀⣠⣴⣶⠿⠋⣩⡿⣿⡿⠻⣿⡇⢠⡄⢸⣿⠟⢿⣿⢿⣍⠙⠿⣶⣦⣄⡀
    ⠀⠉⠉⠁⠶⠟⠋⠀⠉⠀⢀⣈⣁⡈⢁⣈⣁⡀⠀⠉⠀⠙⠻⠶⠈⠉⠉⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⡿⠛⢁⡈⠛⢿⣿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠿⣿⣦⣤⣈⠁⢠⣴⣿⠿⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠻⢿⣿⣦⡉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢷⣦⣈⠛⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣴⠦⠈⠙⠿⣦⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⣤⡈⠁⢤⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠷⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠑⢶⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠁⢰⡆⠈⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠳⠈⣡⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    """

    private var heroSection: some View {
        VStack(spacing: Design.Spacing.md) {
            // Caduceus art
            Text(Self.caduceus)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.0),     // #FFD700 gold
                            Color(red: 0.80, green: 0.50, blue: 0.20),   // #CD7F32 bronze
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Hermes iOS")
                .font(Design.Typography.heroTitle)
                .foregroundStyle(Design.Colors.foreground)

            Text("Run `hermes-mobile pair-phone` on your Hermes host, then scan the QR code to connect.")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Design.Spacing.lg)
        .padding(.horizontal, Design.Spacing.md)
    }

    private var relayConfigurationCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("Relay")
                .font(Design.Typography.sectionTitle)
                .foregroundStyle(Design.Colors.foreground)

            if relayConfiguration.canUseHosted {
                Picker("Relay Mode", selection: relayModeBinding) {
                    Text(RelayMode.custom.displayLabel).tag(RelayMode.custom)
                    Text(RelayMode.hosted.displayLabel).tag(RelayMode.hosted)
                }
                .pickerStyle(.segmented)
            }

            if relayConfiguration.relayMode == .custom {
                TextField("https://your-relay.example.com/v1", text: customRelayURLBinding)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .font(Design.Typography.callout.monospaced())
                    .foregroundStyle(Design.Colors.foreground)
                    .padding(Design.Spacing.md)
                    .background(Design.Colors.surface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                    .accessibilityLabel("Relay URL")

                Text("This should be your relay API base URL. The app will append pairing and chat endpoints to it.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            } else if let hostedRelayBaseURL = relayConfiguration.hostedRelayBaseURL {
                Text(hostedRelayBaseURL)
                    .font(Design.Typography.callout.monospaced())
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            if let relayValidationMessage {
                Text(relayValidationMessage)
                    .font(Design.Typography.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(Design.Spacing.lg)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private var entryOptions: some View {
        VStack(spacing: Design.Spacing.sm) {
            Button {
                localErrorMessage = nil
                isScannerPresented = true
            } label: {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
            }
            .background(Design.Brand.accent)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .accessibilityLabel("Scan QR Code")

            Button {
                localErrorMessage = nil
                withAnimation(Design.Motion.standard) {
                    isManualEntryVisible = true
                }
                isSetupCodeFocused = true
            } label: {
                Label("Enter Code Manually", systemImage: "number")
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
            }
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .accessibilityLabel("Enter Code Manually")
        }
    }

    private var manualEntryCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("Phone Pairing Code")
                .font(Design.Typography.sectionTitle)
                .foregroundStyle(Design.Colors.foreground)

            TextField("ABCD-EFGH", text: $setupCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(Design.Typography.callout.monospaced())
                .foregroundStyle(Design.Colors.foreground)
                .padding(Design.Spacing.md)
                .background(Design.Colors.surface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                .focused($isSetupCodeFocused)
                .accessibilityLabel("Setup code")

            Button {
                Task { await completePairing(using: setupCode) }
            } label: {
                if pairingStore.isWorking {
                    ProgressView()
                        .tint(Design.Colors.foreground)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect Hermes")
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.foreground)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Design.Spacing.sm)
            .background(Design.Brand.accent)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .disabled(pairingStore.isWorking || !PhonePairingCode.isComplete(setupCode) || !isRelayConfigurationValid)
            .opacity(pairingStore.isWorking || !PhonePairingCode.isComplete(setupCode) || !isRelayConfigurationValid ? 0.5 : 1)
            .accessibilityLabel("Connect Hermes")
        }
        .padding(Design.Spacing.lg)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
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
                    Design.Colors.background
                        .ignoresSafeArea()

                    ContentUnavailableView {
                        Label("Scanner Unavailable", systemImage: "qrcode.viewfinder")
                            .foregroundStyle(Design.Colors.foreground)
                    } description: {
                        Text("QR scanning is not available here. Use the pairing code option instead.")
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    } actions: {
                        Button("Use Pairing Code") {
                            isScannerPresented = false
                            isManualEntryVisible = true
                            isSetupCodeFocused = true
                        }
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.foreground)
                        .padding(.horizontal, Design.Spacing.lg)
                        .padding(.vertical, Design.Spacing.sm)
                        .background(Design.Brand.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var errorMessage: String? {
        pairingStore.lastErrorMessage ?? localErrorMessage
    }

    private var relayConfiguration: RelayConfiguration {
        settingsStore.settings.relayConfiguration
    }

    private var relayValidationMessage: String? {
        relayConfiguration.validationMessage
    }

    private var isRelayConfigurationValid: Bool {
        relayValidationMessage == nil
    }

    private var relayModeBinding: Binding<RelayMode> {
        Binding(
            get: { settingsStore.settings.relayConfiguration.relayMode },
            set: { newValue in
                var relayConfiguration = settingsStore.settings.relayConfiguration
                relayConfiguration.relayMode = newValue
                settingsStore.settings.relayConfiguration = relayConfiguration
            }
        )
    }

    private var customRelayURLBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.relayConfiguration.customRelayBaseURL },
            set: { newValue in
                var relayConfiguration = settingsStore.settings.relayConfiguration
                relayConfiguration.customRelayBaseURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsStore.settings.relayConfiguration = relayConfiguration
            }
        )
    }

    /// Parse a QR code value — either a JSON payload `{"code":"...","relay":"..."}` or a plain pairing code.
    /// When JSON includes a relay URL, auto-configures the relay before pairing.
    private func handleScannedValue(_ value: String) {
        // Try JSON payload first (new format from connector)
        if let data = value.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String {
            // Auto-fill relay URL from QR if present
            if let relay = json["relay"] as? String, !relay.isEmpty {
                var config = settingsStore.settings.relayConfiguration
                config.relayMode = .custom
                config.customRelayBaseURL = relay
                settingsStore.settings.relayConfiguration = config
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
        let didPair = await pairingStore.pair(using: rawCode)
        if didPair {
            localErrorMessage = nil
        } else if pairingStore.lastErrorMessage == nil {
            localErrorMessage = PhonePairingCodeError.invalidFormat.localizedDescription
        }
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
    }
}
