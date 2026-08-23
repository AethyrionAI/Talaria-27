import SwiftUI

/// Model-switch transition surface (#9 → #223 Lane 5). apply() is a synchronous
/// local persist now, so ACTIVATING is one animation frame and SUCCESS follows
/// immediately; ERROR only ever carries a load/refresh failure. The CONFIRM
/// phase (the shim's expensive-model guard) retired with the shim.
///
/// Derived from `ModelsSettingsModel`:
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

    private var visible: Bool { phase != .hidden }

    private var telemetry: [(String, Color)] {
        [
            ("CALIBRATING INFERENCE", Design.Brand.accentText),
            (shownModel, Design.Colors.foregroundBright),
            ("HANDSHAKE · OK", Design.Brand.accentText),
            ("LOADING WEIGHTS ···", Design.Colors.mutedForeground),
            ("WARM-UP · ONLINE", Design.Brand.accentText),
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
            if model.errorMessage != nil {
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
        // Theme background at near-full strength (Deep Field: #06080C @ .92,
        // byte-identical to the pre-theming constant).
        Design.Colors.background.opacity(0.92)
            .overlay(alignment: .center) {
                RadialGradient(
                    colors: [Design.Colors.accentTint(0.10), .clear],
                    center: .center, startRadius: 0, endRadius: 220
                )
            }
            .ignoresSafeArea()
    }

    @ViewBuilder private var card: some View {
        switch phase {
        case .activating: activatingCard
        case .success:    successCard
        case .error:      errorCard
        case .hidden:     EmptyView()
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
            MonoLabel("APPLYING LOCK", size: 8,
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
                    .foregroundStyle(Design.Brand.accentBrightText)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            MonoLabel("MODEL ACTIVATED", size: 11, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Brand.accentText)
            MonoLabel(shownModel, size: 13, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
            MonoLabel("NOW ACTIVE · APPLIES TO NEXT TURN", size: 8,
                      tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: 320)
        .hudPanel(borderColor: Design.Colors.accentTint(0.35), innerGlow: true)
    }

    private var errorCard: some View {
        VStack(spacing: Design.Spacing.md) {
            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Colors.danger, blinks: true)
                MonoLabel("ACTIVATION FAILED", size: 10, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Colors.dangerBrightText)
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
                pillButton("Retry", tint: Design.Colors.dangerText, glyph: "arrow.clockwise") {
                    Task { await model.retryLast() }
                }
            }
            .padding(.top, Design.Spacing.xs)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: 340)
        .hudPanel(borderColor: Design.Colors.danger.opacity(0.45), innerGlow: true)
    }

    // MARK: Tinted pill button (GlowButton is cyan-only; ERROR needs red)

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
