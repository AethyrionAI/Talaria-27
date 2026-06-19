import SwiftUI
import VisionKit

struct SetupCodeScannerView: UIViewControllerRepresentable {
    let onCodeDetected: @MainActor (String) -> Void
    let onFailure: @MainActor (String) -> Void

    static var isScannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

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
