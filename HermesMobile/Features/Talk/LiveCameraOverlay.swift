import AVFoundation
import SwiftUI
import UIKit

/// Full-screen camera preview that sends periodic snapshots to the Realtime model.
/// Audio is NOT captured — the microphone stays on WebRTC for voice.
struct LiveCameraOverlay: View {
    let onFrameCaptured: (_ frameData: Data, _ isFirstFrame: Bool) -> Void
    let onDismiss: () -> Void

    @State private var captureManager = CameraCaptureManager()
    @State private var isUsingFrontCamera = false
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera preview
            CameraPreviewView(session: captureManager.session)
                .ignoresSafeArea()

            // Controls overlay
            VStack {
                HStack {
                    Spacer()

                    // Flip camera
                    Button {
                        isUsingFrontCamera.toggle()
                        captureManager.switchCamera(front: isUsingFrontCamera)
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, Design.Spacing.sm)

                    // Close camera (back to voice mode)
                    Button {
                        captureManager.stop()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, Design.Spacing.md)
                }
                .padding(.top, Design.Spacing.xl)

                Spacer()

                if permissionDenied {
                    Text("Camera access is required.\nGo to Settings to enable it.")
                        .font(Design.Typography.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, Design.Spacing.xxl)
                } else {
                    // Subtle status
                    Text("Camera active \u{2022} voice continues")
                        .font(Design.Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.bottom, Design.Spacing.xxl)
                }
            }
        }
        .task {
            // Request camera permission, then start
            let granted = await requestCameraPermission()
            if granted {
                captureManager.onFrameCaptured = onFrameCaptured
                captureManager.start(front: isUsingFrontCamera)
            } else {
                permissionDenied = true
            }
        }
        .onDisappear {
            captureManager.stop()
        }
        .statusBarHidden(true)
    }

    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - Camera Preview (UIKit wrapper)

/// A UIView subclass that keeps its AVCaptureVideoPreviewLayer sized correctly.
private final class CameraPreviewUIView: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        layer.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView(session: session)
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

// MARK: - Camera Capture Manager

@MainActor
@Observable
final class CameraCaptureManager: NSObject {
    let session = AVCaptureSession()
    var onFrameCaptured: ((_ frameData: Data, _ isFirstFrame: Bool) -> Void)?

    private var videoOutput: AVCaptureVideoDataOutput?
    private var frameTimer: Timer?
    private var latestCompressedFrame: Data?
    private var isRunning = false
    private let captureQueue = DispatchQueue(label: "hermes.camera.capture", qos: .userInitiated)

    func start(front: Bool) {
        guard !isRunning else { return }
        isRunning = true

        session.beginConfiguration()
        session.sessionPreset = .medium // 480p

        // Add video input (no audio — mic stays on WebRTC)
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            isRunning = false
            return
        }
        session.addInput(input)

        // Add video output for frame capture
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        videoOutput = output

        session.commitConfiguration()

        // Start the session on a background queue to avoid blocking main
        let capturedSession = session
        captureQueue.async {
            capturedSession.startRunning()
        }

        // Periodic frame capture timer (every 1.5 seconds)
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureAndSendFrame()
            }
        }
    }

    func stop() {
        frameTimer?.invalidate()
        frameTimer = nil

        let capturedSession = session
        captureQueue.async {
            capturedSession.stopRunning()
        }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        videoOutput = nil
        latestCompressedFrame = nil
        isRunning = false
    }

    func switchCamera(front: Bool) {
        guard isRunning else { return }
        stop()
        // Small delay to let the session fully stop before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start(front: front)
        }
    }

    private func captureAndSendFrame() {
        guard let imageData = latestCompressedFrame else { return }
        onFrameCaptured?(imageData, false)
    }

    /// Convert a sample buffer to a 512px JPEG at 0.5 quality (~20-40KB).
    nonisolated private static func compressFrame(_ buffer: CMSampleBuffer) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let image = UIImage(cgImage: cgImage)
        let maxDimension: CGFloat = 512
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.5)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Compress on the capture queue immediately, then send the Data to main
        guard let frameData = Self.compressFrame(sampleBuffer) else { return }
        Task { @MainActor [weak self] in
            self?.latestCompressedFrame = frameData
        }
    }
}
