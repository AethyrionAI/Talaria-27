import Foundation
import Testing
@testable import Talaria

/// #210 — the #26 condense-and-retry guard, pinned against the error shapes the
/// DEVICE actually produces.
///
/// Every string below is VERBATIM from a run record, never invented. That rule
/// is what caught the curly apostrophe and the passive voice in the fabrication
/// detector, and it is what exposed this bug: the guard tested for
/// `GenerationError.exceededContextWindowSize`, the device sent an NSError-style
/// chain with no enum case name, the cast failed, and the turn died instead of
/// degrading to summarized memory.
struct ContextOverflowGuardTests {

    /// Stands in for an error whose `String(describing:)` is the recorded text.
    /// `CustomStringConvertible` is what `String(describing:)` consults, so this
    /// reproduces exactly what `isContextOverflow` sees in production.
    private struct RecordedError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: The two real overflows — both were MISSED before #210

    /// Run `20260728-203142`, `armed/calendar t4`.
    @Test func recognizesTheOverflowShapeTheDeviceActuallySends() {
        let verbatim = "Provided 8,583 tokens, but the maximum allowed is 8,192.::Provided 8,583 tokens, but the maximum allowed is 8,192.: The operation couldn’t be completed. (TokenGenerationInference.DecoderModelError error 3.)::inferenceFailed::The operation couldn’t be completed. (TokenGenerationInference.DecoderModelError error 3.)"
        #expect(LocalChatBackend.isContextOverflow(RecordedError(description: verbatim)))
    }

    /// Run `20260729-180640`, `armed-stallfix/calendar t1`.
    @Test func recognizesTheSecondRecordedOverflow() {
        let verbatim = "Provided 8,529 tokens, but the maximum allowed is 8,192.::Provided 8,529 tokens, but the maximum allowed is 8,192.: The operation couldn’t be completed. (TokenGenerationInference.DecoderModelError error 3.)::inferenceFailed::The operation couldn’t be completed. (TokenGenerationInference.DecoderModelError error 3.)"
        #expect(LocalChatBackend.isContextOverflow(RecordedError(description: verbatim)))
    }

    // MARK: Everything else the device sends must NOT trip it
    //
    // A false positive costs one forced-condensation retry (capped by
    // `didCondenseRetry`); these are the real neighbours it must not confuse.

    @Test func doesNotFireOnGuidedGenerationCorruption() {
        // Run `20260730-...`, bucket A — doubled fragment + leaked control token.
        let verbatim = #"Encountered content that cannot be completed into valid JSON Text: {"term":"Sam"Sam"}<ctrl43>"#
        #expect(!LocalChatBackend.isContextOverflow(RecordedError(description: verbatim)))
    }

    @Test func doesNotFireOnResourcePressure() {
        #expect(!LocalChatBackend.isContextOverflow(RecordedError(description: "Insufficient system resources (7)")))
    }

    @Test func doesNotFireOnAToolDecodeFailure() {
        let verbatim = "ToolCallError(tool: Talaria.DeviceHealthTool(name: \"readHealth\"), underlyingError: GeneratedContent does not contain a property 'metric'.)"
        #expect(!LocalChatBackend.isContextOverflow(RecordedError(description: verbatim)))
    }

    @Test func doesNotFireOnTheWeatherAuthFailure() {
        // #212, 40/40 — the most common error text in the corpus right now.
        let verbatim = "The operation couldn’t be completed. (WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors error 2.)"
        #expect(!LocalChatBackend.isContextOverflow(RecordedError(description: verbatim)))
    }

    @Test func doesNotFireOnAnUndifferentiatedLanguageModelError() {
        let verbatim = "Error Domain=FoundationModels.LanguageModelError Code=-1 \"The operation couldn’t be completed. (FoundationModels.LanguageModelError error -1.)\""
        #expect(!LocalChatBackend.isContextOverflow(RecordedError(description: verbatim)))
    }

    // MARK: The content check needs BOTH halves
    //
    // "maximum allowed" alone is not enough — the point of requiring a token
    // count too is that unrelated limits (attachments, list sizes, rate caps)
    // use that phrase and must not force a condensation retry.

    @Test func halfASentenceIsNotAnOverflow() {
        #expect(!LocalChatBackend.isContextOverflow(
            RecordedError(description: "3 attachments, but the maximum allowed is 2.")))
        #expect(!LocalChatBackend.isContextOverflow(
            RecordedError(description: "Provided 8,583 tokens.")))
    }

    @Test func anEmptyOrUnrelatedErrorIsNotAnOverflow() {
        struct Bare: Error {}
        #expect(!LocalChatBackend.isContextOverflow(Bare()))
        #expect(!LocalChatBackend.isContextOverflow(
            RecordedError(description: "The network connection was lost.")))
    }
}
