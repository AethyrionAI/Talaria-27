import AVFoundation
import SwiftUI

// MARK: - Scanner sheet (#309 Lane B, bar 309-B5)

/// The QR arm, in its three honest states (design B1–B3):
/// live camera · camera refused · no camera on this device.
///
/// **The scan is SUGAR on the typed arm.** Every state keeps a way to type the
/// two values, and the refused state PROMOTES it rather than pushing the user
/// through a permissions trip for a convenience — the design's own note.
struct ConnectHostScannerSheet: View {
    let onPayload: @MainActor (TalariaPairPayload) -> Void
    let onTypeInstead: @MainActor () -> Void
    let onFailure: @MainActor (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var decodeMessage: String?

    private var cameraAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    var body: some View {
        Group {
            if !SetupCodeScannerView.isScannerAvailable {
                unavailableSheet
                    .presentationDetents([.medium])
            } else if cameraAuthorization == .denied || cameraAuthorization == .restricted {
                blockedSheet
                    .presentationDetents([.medium])
            } else {
                liveScanner
            }
        }
    }

    // MARK: B1 — live

    private var liveScanner: some View {
        ZStack {
            SetupCodeScannerView(
                onCodeDetected: handleScan,
                onFailure: { message in onFailure(message) }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button { onTypeInstead() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Design.Colors.foregroundBright)
                            .padding(Design.Spacing.md)
                    }
                    .accessibilityLabel("Close scanner")
                }
                Spacer()
                VStack(spacing: Design.Spacing.xs) {
                    MonoLabel(ConnectHostCopy.scannerPointAtCode, weight: .medium,
                              tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.foregroundBright)
                    Text(ConnectHostCopy.scannerWhereItIs)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .multilineTextAlignment(.center)
                    if let decodeMessage {
                        Text(decodeMessage)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Brand.forgeText)
                            .multilineTextAlignment(.center)
                            .padding(.top, Design.Spacing.xxs)
                    }
                    // The escape hatch stays ON SCREEN — the design's note.
                    GhostButton(title: ConnectHostCopy.scannerTypeInstead) { onTypeInstead() }
                        .padding(.top, Design.Spacing.sm)
                }
                .padding(Design.Spacing.lg)
                .background(Design.Colors.scrim)
            }
        }
    }

    private func handleScan(_ scanned: String) {
        switch TalariaPairPayload.decode(scanned) {
        case .success(let payload):
            onPayload(payload)
        case .failure(let reason):
            // A stale relay-era QR lands HERE, named, instead of being carried
            // into a flow that cannot complete (#412's shape).
            decodeMessage = reason.message
        }
    }

    // MARK: B2 — camera refused

    private var blockedSheet: some View {
        ZStack {
            HUDScreenBackground().ignoresSafeArea()
            VStack(spacing: Design.Spacing.md) {
                Image(systemName: "video.slash")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Design.Brand.forgeText)
                MonoLabel(ConnectHostCopy.scannerBlockedTitle, weight: .medium,
                          tracking: Design.Tracking.monoXWide, color: Design.Brand.forgeText)
                Text(ConnectHostCopy.scannerBlockedHeadline)
                    .font(Design.Typography.display(18, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(Design.Colors.foregroundBright)
                Text(ConnectHostCopy.scannerBlockedBlurb)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // TYPED ARM PROMOTED, permission trip demoted — scanning was
                // only ever sugar, so a refused camera is not a dead end.
                GlowButton(title: ConnectHostCopy.scannerTypeTheValues) { onTypeInstead() }
                GhostButton(title: ConnectHostCopy.scannerOpenSettings) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            .padding(Design.Spacing.xl)
        }
    }

    // MARK: B3 — no camera at all

    private var unavailableSheet: some View {
        ZStack {
            HUDScreenBackground().ignoresSafeArea()
            VStack(spacing: Design.Spacing.md) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                MonoLabel(ConnectHostCopy.scannerUnavailableTitle, weight: .medium,
                          tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.secondaryForeground)
                Text(ConnectHostCopy.scannerUnavailableHeadline)
                    .font(Design.Typography.display(18, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .multilineTextAlignment(.center)
                Text(ConnectHostCopy.scannerUnavailableBlurb)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                GlowButton(title: ConnectHostCopy.scannerTypeTheValues) { onTypeInstead() }
            }
            .padding(Design.Spacing.xl)
        }
    }
}

// MARK: - Disconnect confirm (#309 Lane B, design B4)

/// One button, both halves spelled out — what used to be "Revoke Host" plus
/// "Disconnect" on two rows that did different things.
///
/// The second bullet has TWO forms because the second half has two outcomes:
/// a reachable host is told, and an unreachable one keeps its record until
/// someone runs `hermes talaria unpair` there. Saying the first when the
/// second is true is exactly the class of promise this lane exists to remove.
struct ConnectHostDisconnectSheet: View {
    let host: ConnectedHost
    let onConfirm: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        ZStack {
            HUDScreenBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    MonoLabel(ConnectHostCopy.disconnectSheetTitle(host: host.name),
                              weight: .medium, tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.dangerText)

                    Text(ConnectHostCopy.disconnectTwoThings)
                        .font(Design.Typography.display(18, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(Design.Colors.foregroundBright)

                    step(number: "1",
                         title: ConnectHostCopy.disconnectStepOneTitle,
                         blurb: ConnectHostCopy.disconnectStepOneBlurb)

                    if hostCanBeTold {
                        step(number: "2",
                             title: ConnectHostCopy.disconnectStepTwoTitle(host: host.name),
                             blurb: ConnectHostCopy.disconnectStepTwoBlurb)
                    } else {
                        step(number: "2",
                             title: ConnectHostCopy.disconnectStepTwoTitleUnreachable(host: host.name),
                             blurb: ConnectHostCopy.disconnectStepTwoBlurbUnreachable)
                    }

                    Text(ConnectHostCopy.disconnectReassurance)
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    GlowButton(title: ConnectHostCopy.disconnectConfirm) { onConfirm() }
                        .accessibilityIdentifier("connectHost.disconnectConfirm")
                    GhostButton(title: ConnectHostCopy.disconnectCancel) { onCancel() }
                }
                .padding(Design.Spacing.lg)
            }
        }
    }

    /// `.notChecked` counts as "can be told": the POST is attempted and the
    /// result reported. Only a MEASURED no-answer earns the second form.
    private var hostCanBeTold: Bool {
        host.reachability != .noAnswer
    }

    private func step(number: String, title: String, blurb: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            Text(number)
                .font(Design.Typography.mono(12, weight: .bold))
                .foregroundStyle(Design.Brand.accentText)
                .frame(width: 22, height: 22)
                .background(Design.Colors.accentTint(0.12))
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Design.Colors.strongBorder, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Text(blurb)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
