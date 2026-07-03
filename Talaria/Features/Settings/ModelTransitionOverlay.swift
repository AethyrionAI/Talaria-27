import SwiftUI

/// Model-switch transition surface (#9). Covers the list area while the dual-write
/// (shim set-default + gateway session pin) runs, then branches to success / confirm /
/// error. Header + shim config stay visible underneath (this is an overlay on the list
/// content only). All copy is real: CONFIRM shows the shim's message, ERROR shows the
/// thrown description — nothing is mocked.
///
/// Derived from `ModelsSettingsModel`:
///   • `pendingConfirm != nil`             → CONFIRM (amber, no auto-dismiss)
///   • `applyingModelID != nil`            → ACTIVATING (telemetry + reactor)
///   • activation resolved, no error       → SUCCESS (checkmark, auto-dismiss ~750ms)
///   • activation resolved with an error   → ERROR (Retry / Dismiss; model never mutated)
struct ModelTransitionOverlay: View {
    @Bindable var model: ModelsSettingsModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    private enum Phase { case hidden, activating, success, error }

    @State private var phase: Phase = .hidden
    @State private var shownModel: String = ""
    @State private var step: Int = 0
    @State private var successTask: Task<Void, Never>?
    @State private var watchdogTask: Task<Void, Never>?

    private var confirmActive: Bool { model.pendingConfirm != nil }
    private var visible: Bool { confirmActive || phase != .hidden }

    private var telemetry: [(String, Color)] {
        [
            ("CALIBRATING INFERENCE", Design.Brand.accent),
            (shownModel, Design.Colors.foregroundBright),
            ("HANDSHAKE · OK", Design.Brand.accent),
            ("LOADING WEIGHTS ···", Design.Colors.mutedForeground),
            ("WARM-UP · ONLINE", Design.Brand.accent),
        ]
    }

    var body: some View {
        ZStack {
            if visible {
                scrim
                card.padding(.horizontal, Design.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: confirmActive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.30), value: step)
        .onChange(of: model.applyingModelID) { old, new in
            handleApplyingChange(old: old, new: new)
        }
    }

    // MARK: Transitions

    private func handleApplyingChange(old: String?, new: String?) {
        if let new {
            successTask?.cancel()
            shownModel = new
            step = reduceMotion ? telemetry.count - 1 : 0
            phase = .activating
            startWatchdog()
            if !reduceMotion { advanceTelemetry() }
        } else if old != nil {
            watchdogTask?.cancel()
            if model.pendingConfirm != nil {
                phase = .hidden               // CONFIRM card takes over (derived)
            } else if model.errorMessage != nil {
                phase = .error
            } else {
                phase = .success
                scheduleSuccessDismiss()
            }
        }
    }

    private func advanceTelemetry() {
        Task { @MainActor in
            while phase == .activating && step < telemetry.count - 1 {
                try? await Task.sleep(for: .milliseconds(420))
                if phase == .activating { step += 1 }
            }
        }
    }

    private func scheduleSuccessDismiss() {
        successTask?.cancel()
        successTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            if !Task.isCancelled { phase = .hidden }
        }
    }

    /// Safety net: if the apply() never resolves (e.g. a hung shim), drop the overlay so it
    /// can never visually lock. The real result still surfaces via the applyingModelID
    /// onChange when apply() finally returns. (#9)
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled && phase == .activating { phase = .hidden }
        }
    }

    // MARK: Scrim + card router

    private var scrim: some View {
        Color(hex: 0x06080C, opacity: 0.92)
            .overlay(alignment: .center) {
                RadialGradient(
                    colors: [Design.Colors.accentTint(0.10), .clear],
                    center: .center, startRadius: 0, endRadius: 220
                )
            }
            .ignoresSafeArea()
    }

    @ViewBuilder private var card: some View {
        if confirmActive, let pending = model.pendingConfirm {
            confirmCard(pending)
        } else {
            switch phase {
            case .activating: activatingCard
            case .success:    successCard
            case .error:      errorCard
            case .hidden:     EmptyView()
            }
        }
    }

    // MARK: Cards

    private var activatingCard: some View {
        VStack(spacing: Design.Spacing.lg) {
            ReactorOrb(size: 92, style: .voice)
            VStack(spacing: Design.Spacing.xs) {
                ForEach(Array(telemetry.enumerated()), id: \.offset) { idx, line in
                    MonoLabel(line.0,
                              size: idx == 1 ? 12 : 9,
                              weight: idx == 1 ? .medium : .regular,
                              tracking: Design.Tracking.mono,
                              color: line.1)
                        .opacity(step >= idx ? 1 : 0)
                        .offset(y: step >= idx ? 0 : 4)
                }
            }
            MonoLabel("HOLD · 1–5S · DO NOT CLOSE", size: 8,
                      tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
                .padding(.top, Design.Spacing.xs)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: 320)
        .hudPanel(borderColor: Design.Colors.hairline, innerGlow: true)
    }

    private var successCard: some View {
        VStack(spacing: Design.Spacing.md) {
            ZStack {
                ReactorOrb(size: 92, style: .standard, glowIntensity: Design.Glow.k * 1.7)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Design.Brand.accentBright)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            MonoLabel("MODEL ACTIVATED", size: 11, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Brand.accent)
            MonoLabel(shownModel, size: 13, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
            MonoLabel("NOW ACTIVE · APPLIES TO NEXT TURN", size: 8,
                      tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: 320)
        .hudPanel(borderColor: Design.Colors.accentTint(0.35), innerGlow: true)
    }

    private func confirmCard(_ pending: ModelsSettingsModel.PendingConfirm) -> some View {
        VStack(spacing: Design.Spacing.md) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Brand.forge, blinks: true)
                MonoLabel("PREMIUM MODEL · CONFIRM", size: 10, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Brand.forge)
            }
            MonoLabel(pending.modelID, size: 13, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
            Text(pending.message)
                .font(Design.Typography.body(13, weight: .regular))
                .foregroundStyle(Design.Colors.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Design.Spacing.sm) {
                GhostButton(title: "Cancel") { model.cancelPending() }
                pillButton("Activate", tint: Design.Brand.forge) {
                    Task { await model.confirmPending() }
                }
            }
            .padding(.top, Design.Spacing.xs)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: 340)
        .hudPanel(borderColor: Design.Brand.forge.opacity(0.45), innerGlow: true)
    }

    private var errorCard: some View {
        VStack(spacing: Design.Spacing.md) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Colors.danger, blinks: true)
                MonoLabel("ACTIVATION FAILED", size: 10, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Colors.dangerBright)
            }
            MonoLabel(shownModel, size: 13, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
            if let message = model.errorMessage {
                Text(message)
                    .font(Design.Typography.body(13, weight: .regular))
                    .foregroundStyle(Design.Colors.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MonoLabel("RECOVERABLE · NO STATE MUTATION", size: 8,
                      tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
            HStack(spacing: Design.Spacing.sm) {
                GhostButton(title: "Dismiss") {
                    model.errorMessage = nil
                    phase = .hidden
                }
                pillButton("Retry", tint: Design.Colors.danger, glyph: "arrow.clockwise") {
                    Task { await model.retryLast() }
                }
            }
            .padding(.top, Design.Spacing.xs)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: 340)
        .hudPanel(borderColor: Design.Colors.danger.opacity(0.45), innerGlow: true)
    }

    // MARK: Tinted pill button (GlowButton is cyan-only; CONFIRM/ERROR need amber/red)

    private func pillButton(_ title: String, tint: Color, glyph: String? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.xs) {
                if let glyph {
                    Image(systemName: glyph).font(.system(size: 14, weight: .semibold))
                }
                Text(title.uppercased())
                    .font(Design.Typography.display(15, weight: .semibold, relativeTo: .headline))
                    .tracking(Design.Tracking.button)
            }
            .foregroundStyle(Design.Colors.foregroundBright)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.10)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(tint.opacity(0.6), lineWidth: 1)
            }
            .hudGlow(tint, radius: 20, strength: 0.30, intensity: Design.Glow.k)
        }
        .buttonStyle(.plain)
    }
}
