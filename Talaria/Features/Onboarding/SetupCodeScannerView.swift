import SwiftUI
import VisionKit

/// Camera QR scanner with an arc-reactor HUD overlay (targeting reticle +
/// bobbing scan line + mono instruction). The VisionKit scanning logic lives in
/// the internal `ScannerRepresentable`; this view only adds chrome.
struct SetupCodeScannerView: View {
    let onCodeDetected: @MainActor (String) -> Void
    let onFailure: @MainActor (String) -> Void

    static var isScannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            ScannerRepresentable(onCodeDetected: onCodeDetected, onFailure: onFailure)
                .ignoresSafeArea()

            // Darkened HUD vignette + targeting reticle.
            ScannerReticleOverlay()
                .ignoresSafeArea()
        }
    }
}

// MARK: - HUD reticle overlay

private struct ScannerReticleOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    private let reticleSize: CGFloat = 240

    var body: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()

            MonoLabel("ALIGN HOST QR WITHIN FRAME", tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.coolForeground)

            ZStack {
                // Faint cyan frame + center scanning bar.
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.cyanHairline, lineWidth: 1)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Design.Brand.accent, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .hudGlow(Design.Brand.accent, radius: 10, strength: 0.8)
                    .offset(y: reduceMotion ? 0 : (bob ? reticleSize / 2 - 14 : -(reticleSize / 2 - 14)))

                // Large cyan targeting brackets.
                CornerBrackets(arm: 34, lineWidth: 2, color: Design.Brand.accent)
            }
            .frame(width: reticleSize, height: reticleSize)

            MonoLabel("SCANNING…", tracking: Design.Tracking.monoWide)
                .hudPulse(Design.Motion.blink, from: 1.0, to: 0.35)

            Spacer()
            Spacer()
        }
        .padding(Design.Spacing.xl)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Design.Motion.reticleDuration).repeatForever(autoreverses: true)) {
                bob = true
            }
        }
    }
}

// MARK: - VisionKit scanner (logic unchanged)

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCodeDetected: @MainActor (String) -> Void
    let onFailure: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetected: onCodeDetected, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .fullScreen

        do {
            try controller.startScanning()
        } catch {
            Task { @MainActor in
                onFailure("QR scanning could not start on this device.")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCodeDetected: @MainActor (String) -> Void
        private let onFailure: @MainActor (String) -> Void
        private var hasCapturedCode = false

        init(
            onCodeDetected: @escaping @MainActor (String) -> Void,
            onFailure: @escaping @MainActor (String) -> Void
        ) {
            self.onCodeDetected = onCodeDetected
            self.onFailure = onFailure
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasCapturedCode else { return }

            for item in addedItems {
                guard case .barcode(let barcode) = item else { continue }
                guard let payload = barcode.payloadStringValue else { continue }
                hasCapturedCode = true
                Task { @MainActor in
                    onCodeDetected(payload)
                }
                return
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            Task { @MainActor in
                onFailure("QR scanning is unavailable right now.")
            }
        }
    }
}
