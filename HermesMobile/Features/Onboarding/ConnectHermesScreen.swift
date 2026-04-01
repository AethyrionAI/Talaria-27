import SwiftUI

struct ConnectHermesScreen: View {
    @Environment(PairingStore.self) private var pairingStore

    @State private var setupCode = ""
    @State private var isScannerPresented = false
    @State private var isManualEntryVisible = false
    @State private var localErrorMessage: String?
    @FocusState private var isSetupCodeFocused: Bool

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    heroSection
                    entryOptions

                    if isManualEntryVisible {
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Connect Your Hermes")
                .font(Design.Typography.heroTitle)
                .foregroundStyle(.primary)

            Text("On the machine running Hermes, finish connector setup and run `hermes-mobile-connector pair-phone`. Then scan the QR code or enter the 8-character code here.")
                .font(Design.Typography.body)
                .foregroundStyle(.secondary)
        }
        .padding(Design.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private var entryOptions: some View {
        VStack(spacing: Design.Spacing.sm) {
            Button {
                localErrorMessage = nil
                isScannerPresented = true
            } label: {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    .font(Design.Typography.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .accessibilityLabel("Scan QR Code")

            Button {
                localErrorMessage = nil
                withAnimation(Design.Motion.standard) {
                    isManualEntryVisible = true
                }
                isSetupCodeFocused = true
            } label: {
                Label("Enter Pairing Code", systemImage: "number")
                    .font(Design.Typography.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Enter Setup Code")
        }
    }

    private var manualEntryCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("Phone Pairing Code")
                .font(Design.Typography.sectionTitle)

            TextField("ABCD-EFGH", text: $setupCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(Design.Typography.callout.monospaced())
                .padding(Design.Spacing.md)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
                .focused($isSetupCodeFocused)
                .accessibilityLabel("Setup code")

            Button {
                Task { await completePairing(using: setupCode) }
            } label: {
                if pairingStore.isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect Hermes")
                        .font(Design.Typography.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(pairingStore.isWorking || !PhonePairingCode.isComplete(setupCode))
            .accessibilityLabel("Connect Hermes")
        }
        .padding(Design.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.xl))
    }

    private var scannerSheet: some View {
        Group {
            if SetupCodeScannerView.isScannerAvailable {
                SetupCodeScannerView(
                    onCodeDetected: { code in
                        isScannerPresented = false
                        Task { await completePairing(using: code) }
                    },
                    onFailure: { message in
                        isScannerPresented = false
                        localErrorMessage = message
                    }
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView {
                    Label("Scanner Unavailable", systemImage: "qrcode.viewfinder")
                } description: {
                    Text("QR scanning is not available here. Use the pairing code option instead.")
                } actions: {
                    Button("Use Pairing Code") {
                        isScannerPresented = false
                        isManualEntryVisible = true
                        isSetupCodeFocused = true
                    }
                    .buttonStyle(.glassProminent)
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var errorMessage: String? {
        pairingStore.lastErrorMessage ?? localErrorMessage
    }

    private func completePairing(using rawCode: String) async {
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
                .foregroundStyle(.primary)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
    }
}
