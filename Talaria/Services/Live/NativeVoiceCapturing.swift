@preconcurrency import AVFoundation
import Foundation
import os
@preconcurrency import Speech

// MARK: - #428: the two capture seams
//
// Both protocols here exist for ONE reason: `NativeVoiceCaptureController
// .start(muted:)` used to carry four `await`s (locale support probe, locale
// reservation, `bestAvailableAudioFormat`, `prepareToAnalyze`) between the
// session configuration and the tap install. Actor serialization does not
// survive an await, so a `stop()` arriving in that window returns before the
// start it was meant to cancel finishes installing a tap — the #428 defect.
// Collapsing those four awaits behind ONE injectable call is what lets a test
// park a start at a known suspension point and interleave a real teardown.
//
// This file is a PURE MOVE of code that lived in
// `NativeVoicePipelineService.swift`; the behaviour it describes is the
// behaviour that shipped.

/// The capture controller's output channel — volatile transcription text,
/// finalized utterances, and terminal failures.
///
/// Lifted out of `NativeVoiceCaptureController.Event` (#428) so a test double
/// can vend the same stream without owning an `AVAudioEngine`.
enum NativeVoiceCaptureEvent: Sendable {
    case volatile(String)
    case finalized(String)
    case failed(String)
}

/// The mic → transcription capture stack, as the pipeline service sees it.
///
/// `: Actor` is load-bearing: the conforming type serializes its own start /
/// stop, and the requirements below are therefore isolated to it — which is
/// what lets `setMuted` and `stop` stay synchronous at the definition while
/// every caller still crosses the actor with `await`.
/// #436: WHO moved the capture generation.
///
/// #428's ticket records THAT a `stop()` interleaved with a parked start, and
/// that was enough to stop the start installing a tap behind a finished
/// shutdown. It is NOT enough to decide what the session owes the user
/// afterwards, because the two ends of that decision are opposites: a
/// supersession caused by a TEARDOWN must stay silent (#428 ruling 2 — the
/// session is going away and any paint would be a repaint of a dead session),
/// while one caused by a stop on a session that is still LIVE leaves
/// `.connected` / `.listening` with no capture chain behind it and owes either
/// a re-armed chain or an honest ended state.
///
/// Three cases, and the middle one is why an origin is needed rather than a
/// bool: a newer `start()` also bumps the generation, and re-arming behind a
/// newer start is the #82 thrash the restart breaker exists to stop.
enum CaptureStopOrigin: Sendable, Equatable {
    /// A session teardown owns the pipeline. Silence, byte-for-byte (#428
    /// ruling 2).
    case teardown
    /// A restart's own leading stop, or a newer `start(muted:)`'s. Somebody is
    /// rebuilding the chain and will install their own — re-arming here is the
    /// #82 thrash.
    case restart
    /// A stop on a session nobody is tearing down and nobody is rebuilding
    /// for: the analyzer's own failure path (`emit(.failed)` → `stop()`, the
    /// #436 trace), or a bare `stop()` from a caller that will not put a chain
    /// back. **This is the only origin that owes a repair**, and it is the
    /// fail-safe default for the same reason — silence is the defect, so an
    /// unclassified stop must read as the arm that acts, never as the arm that
    /// stays quiet.
    case bareStop

    /// The archive rendering. Lowercase and hyphenated so a grep over a device
    /// log reads `origin=bare-stop` without shell quoting.
    var logLabel: String {
        switch self {
        case .teardown: "teardown"
        case .restart: "restart"
        case .bareStop: "bare-stop"
        }
    }
}

protocol NativeVoiceCapturing: Actor {
    func isTranscriptionSupported() async -> Bool
    func setMuted(_ muted: Bool)
    func start(muted: Bool) async throws -> AsyncStream<NativeVoiceCaptureEvent>
    /// #436: every stop names its origin. There is deliberately NO defaulted
    /// `stop()` overload — a default would let a new call site inherit an
    /// origin it never thought about, and the origin is what decides whether a
    /// superseded start repairs the session or stays silent.
    func stop(origin: CaptureStopOrigin)
}

/// Which transcriber flavor the assembly settled on. The two consume loops are
/// shape-identical but typed to their module's own `Result`, so the choice has
/// to survive the seam instead of being erased to `any SpeechModule`.
enum TranscriberChoice: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)
}

/// Everything a capture start needs from the (async, cancellable) analyzer
/// assembly, so the engine stretch that follows can be entirely synchronous.
///
/// `@unchecked Sendable`: `AVAudioFormat` carries no Sendable conformance.
/// It is immutable in practice and is only read (never mutated) after the
/// assembly returns.
struct SpeechAnalysisAssembly: @unchecked Sendable {
    let analyzer: SpeechAnalyzer
    let analyzerFormat: AVAudioFormat
    /// Non-nil when `AssetInventory.reserve` actually took the reservation —
    /// the datum `releaseResources` hands back. The actor no longer stores it
    /// (#428, 428-B2: the hook below is the single release mechanism), so this
    /// is the assembly's own record of what was reserved rather than a value
    /// anything downstream reads.
    let reservedLocale: Locale?
    let transcriber: TranscriberChoice
    /// **The one way to give back what this assembly took** (#428, 428-B2).
    ///
    /// An assembly owns two live resources — a prepared `SpeechAnalyzer` and
    /// (sometimes) an `AssetInventory` locale reservation — and there are now
    /// TWO paths that must give them back: `stop()`, which releases the
    /// assembly the actor adopted, and a SUPERSEDED start, which must release
    /// an assembly the actor never adopted at all. Two hand-written copies of
    /// "cancel the analyzer, release the locale" is how the second path would
    /// silently grow a leak, so the assembly carries the release itself and
    /// both paths call this.
    ///
    /// Idempotence is the caller's business: each path nils out its reference
    /// after calling, and the two paths are mutually exclusive by construction
    /// (adoption happens in `startEngine`, which a superseded start never
    /// reaches).
    let releaseResources: @Sendable () async -> Void
}

/// The one seam the whole #428 lane rests on: every suspension point between
/// "the audio session is configured" and "a tap is installed" lives behind
/// this single call.
protocol SpeechAnalysisAssembling: Sendable {
    func assemble(inputFormat: AVAudioFormat) async throws -> SpeechAnalysisAssembly
}

/// Production assembly — moved verbatim (#428) out of
/// `NativeVoiceCaptureController.start(muted:)` (transcriber selection +
/// locale reservation) and `startAnalyzer` (modules, format negotiation,
/// `prepareToAnalyze` + the no-VAD retry).
struct SpeechTranscriberAssembler: SpeechAnalysisAssembling {
    private static let logger = Logger(
        subsystem: "org.aethyrion.talaria", category: "NativeVoiceCapture")

    func assemble(inputFormat: AVAudioFormat) async throws -> SpeechAnalysisAssembly {
        // #82 wedge backstop, check 1 of 2 (#428 — defence in depth, see the
        // note on the actor's second check). It runs FIRST, before any await,
        // so the on-device fail-fast is what it has always been: a degenerate
        // input format is refused before an analyzer is prepared or a locale
        // reserved, and long before any tap touches the engine.
        guard TalkMicPreflight.isViableCaptureFormat(
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount
        ) else {
            Self.logger.error("capture format degenerate (rate=\(inputFormat.sampleRate, privacy: .public) ch=\(inputFormat.channelCount, privacy: .public)) — #82 wedge shape; refusing tap install")
            throw NativeVoiceCaptureController.CaptureError.noAudioInput
        }

        // Prefer SpeechTranscriber (the full model); fall back to
        // DictationTranscriber when the model isn't available on-device.
        // Both flavors get the SpeechDetector VAD module first, and retry
        // without it if the analyzer refuses to start (iOS 26.0 conformance
        // bug hedge — the fallback endpointer upstream covers endpointing).
        let choice: TranscriberChoice
        let reservedLocale: Locale?
        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            choice = .speech(SpeechTranscriber(locale: locale, preset: .progressiveTranscription))
            reservedLocale = try await Self.reserveLocaleIfPossible(locale)
        } else {
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
                throw NativeVoiceCaptureController.CaptureError.transcriptionUnavailable
            }
            choice = .dictation(DictationTranscriber(locale: locale, preset: .progressiveShortDictation))
            reservedLocale = try await Self.reserveLocaleIfPossible(locale)
        }

        let transcriber: any SpeechModule = switch choice {
        case .speech(let module): module
        case .dictation(let module): module
        }

        do {
            // SpeechDetector gates analysis to detected speech; retry without
            // it if the analyzer/module combination refuses to start.
            var modules: [any SpeechModule] = [
                SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false),
                transcriber,
            ]

            var analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: inputFormat
            ) ?? inputFormat
            var analyzer: SpeechAnalyzer
            do {
                analyzer = SpeechAnalyzer(modules: modules)
                try await analyzer.prepareToAnalyze(in: analyzerFormat) { _ in }
            } catch {
                Self.logger.warning("analyzer with SpeechDetector failed (\(error.localizedDescription, privacy: .public)) — retrying without VAD module")
                modules = [transcriber]
                analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber],
                    considering: inputFormat
                ) ?? inputFormat
                analyzer = SpeechAnalyzer(modules: modules)
                try await analyzer.prepareToAnalyze(in: analyzerFormat) { _ in }
            }

            return SpeechAnalysisAssembly(
                analyzer: analyzer,
                analyzerFormat: analyzerFormat,
                reservedLocale: reservedLocale,
                transcriber: choice,
                // #428 (428-B2): the release the actor's `stop()` used to
                // hand-roll from two stored properties. Built here, where both
                // resources are in scope and neither can be forgotten; the
                // captures are by value (both `Sendable`), so the closure holds
                // exactly what it will give back. Cancel first, then release —
                // the locale belongs to the analyzer until it has finished.
                releaseResources: { [analyzer, reservedLocale] in
                    await analyzer.cancelAndFinishNow()
                    if let reservedLocale {
                        _ = await AssetInventory.release(reservedLocale: reservedLocale)
                    }
                }
            )
        } catch {
            // #428, and the one place the seam would otherwise LOSE behaviour:
            // before the split, `reserveLocaleIfPossible` wrote straight to the
            // actor's `reservedLocale`, so a throw further down still left
            // `stop()` able to release it. The actor now adopts the
            // reservation only when the assembly RETURNS — so an assembly that
            // throws after reserving must release its own, or the reservation
            // outlives every reference to it. This preserves the pre-seam
            // invariant rather than changing it.
            if let reservedLocale {
                _ = await AssetInventory.release(reservedLocale: reservedLocale)
            }
            throw error
        }
    }

    /// Moved from `NativeVoiceCaptureController.reserveLocaleIfPossible` (#428)
    /// — the reservation's only caller. Returns the locale it actually
    /// reserved (or nil), so the actor can release exactly that one in
    /// `stop()`.
    private static func reserveLocaleIfPossible(_ locale: Locale) async throws -> Locale? {
        if try await AssetInventory.reserve(locale: locale) { return locale }
        return nil
    }
}
