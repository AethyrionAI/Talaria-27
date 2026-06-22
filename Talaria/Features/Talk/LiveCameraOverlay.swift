@preconcurrency import AVFoundation
import ImageIO
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

            // HUD targeting reticle framing the live feed
            CornerBrackets(
                arm: Design.Size.bracket + 8,
                lineWidth: 1.5,
                color: Design.Colors.accentTint(0.55),
                inset: Design.Spacing.xl
            )
            .ignoresSafeArea()

            // Faint cyan grid for the HUD scan look
            GridOverlay()
                .opacity(0.12)
                .ignoresSafeArea()

            // Controls overlay
            VStack {
                HStack(alignment: .top) {
                    // Live feed telemetry
                    HStack(spacing: Design.Spacing.xs) {
                        StatusPip(color: Design.Brand.accent, diameter: 6, blinks: true)
                        MonoLabel(
                            "VISUAL LINK · LIVE",
                            weight: .medium,
                            tracking: Design.Tracking.monoWide,
                            color: Design.Brand.accent
                        )
                    }
                    .padding(.horizontal, Design.Spacing.sm)
                    .padding(.vertical, Design.Spacing.xs)
                    .background(Design.Colors.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(Design.Colors.cyanHairline, lineWidth: 1) }

                    Spacer()

                    // Flip camera
                    Button {
                        isUsingFrontCamera.toggle()
                        captureManager.switchCamera(front: isUsingFrontCamera)
                    } label: {
                        cameraControlIcon("camera.rotate.fill", size: 18)
                    }
                    .accessibilityLabel("Flip camera")
                    .padding(.trailing, Design.Spacing.sm)

                    // Close camera (back to voice mode)
                    Button {
                        captureManager.stop()
                        onDismiss()
                    } label: {
                        cameraControlIcon("xmark", size: 16)
                    }
                    .accessibilityLabel("Close camera")
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, Design.Spacing.xl)

                Spacer()

                if permissionDenied {
                    VStack(spacing: Design.Spacing.sm) {
                        MonoLabel(
                            "CAMERA ACCESS REQUIRED",
                            weight: .medium,
                            tracking: Design.Tracking.monoWide,
                            color: Design.Brand.forge
                        )

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("OPEN SETTINGS")
                                .font(Design.Typography.mono(11, weight: .medium))
                                .tracking(Design.Tracking.monoWide)
                                .foregroundStyle(Design.Colors.accentBright)
                                .padding(.horizontal, Design.Spacing.lg)
                                .padding(.vertical, Design.Spacing.sm)
                                .background(Design.Colors.accentTint(0.1), in: Capsule())
                                .overlay { Capsule().strokeBorder(Design.Colors.cyanBorder, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, Design.Spacing.xxl)
                } else {
                    // Subtle status
                    MonoLabel(
                        "VOICE CONTINUES \u{2022} FRAME SYNC ACTIVE",
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.accentTint(0.6)
                    )
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

    /// Round HUD camera-control glyph: chip surface + cyan hairline border.
    private func cameraControlIcon(_ systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Design.Colors.accentBright)
            .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
            .background(Design.Colors.surface, in: Circle())
            .overlay { Circle().strokeBorder(Design.Colors.cyanBorder, lineWidth: 1) }
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

        // CRITICAL: prevent AVCaptureSession from reconfiguring the audio session.
        // WebRTC owns the audio session for voice — if the capture session touches
        // it, the peer connection drops and the data channel dies.
        session.automaticallyConfiguresApplicationAudioSession = false

        session.beginConfiguration()
        session.sessionPreset = .high // 720p — good preview quality

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

        // All session changes must happen on the same queue to avoid races
        let capturedSession = session
        captureQueue.async {
            capturedSession.beginConfiguration()
            for input in capturedSession.inputs { capturedSession.removeInput(input) }
            for output in capturedSession.outputs { capturedSession.removeOutput(output) }
            capturedSession.commitConfiguration()
            capturedSession.stopRunning()
        }
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

    // Reuse a single CIContext — creating one per frame is expensive (GPU resource)
    nonisolated private static let sharedCIContext = CIContext()

    /// Convert a sample buffer to a 512px JPEG at 0.5 quality (~20-40KB).
    /// Uses Core Graphics for thread-safe resizing (UIGraphicsImageRenderer is not safe on background queues).
    nonisolated private static func compressFrame(_ buffer: CMSampleBuffer) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let maxDim: CGFloat = 512
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let scale = min(maxDim / max(w, h), 1.0)
        let newW = Int(w * scale), newH = Int(h * scale)

        // Thread-safe Core Graphics resize
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let resized = ctx.makeImage() else { return nil }

        // JPEG encode via ImageIO (thread-safe)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, resized, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
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
