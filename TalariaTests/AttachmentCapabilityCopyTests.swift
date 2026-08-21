import Foundation
import Testing
@testable import Talaria

/// #173 — the never-claim floor. Bars 173-A…D were pre-registered in the
/// OPEN_ITEMS entry before this file existed; 173-E (the #380 Settings rider)
/// lives with the Settings copy it pins.
///
/// **Read 173-B before touching any of this.** Its bar is the string
/// INEQUALITY, not either string's wording — one shared caption satisfies the
/// prose of 173-A and 173-B while failing the ruling behind them, and that is
/// exactly the shortcut a later lane would take while "simplifying".
@Suite(.serialized)
struct AttachmentCapabilityCopyTests {

    // MARK: - 173-A: the Hermes path says UNKNOWN

    @Test
    func hermesImageTurnSaysCapabilityIsUnknown() throws {
        let caption = AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: true)
        let text = try #require(caption)
        #expect(text == AttachmentCapabilityCopy.hermesUnknownCapability)
        // The wording is UNKNOWN, never a claim of absence. The upstream
        // catalog defaults `supports_vision` to false, so an uncatalogued
        // model would read as no-vision — asserting that as fact reproduces
        // #173 from the other side.
        #expect(text.localizedCaseInsensitiveContains("isn't known"))
        #expect(!text.localizedCaseInsensitiveContains("does not support"))
        #expect(!text.localizedCaseInsensitiveContains("cannot support"))
    }

    // MARK: - 173-B: on-device says something STRONGER, and DIFFERENT

    @Test
    func onDeviceImageTurnSaysItCannotSeeImages() throws {
        let caption = AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: true)
        let text = try #require(caption)
        #expect(text == AttachmentCapabilityCopy.onDeviceCannotSeeImages)
        // DEFINITE here — we know (device-confirmed 2026-08-02), so hedging
        // would be #180's sin inverted: a known-false encoded as an unknown.
        #expect(text.localizedCaseInsensitiveContains("can't see"))
        #expect(!text.localizedCaseInsensitiveContains("known"))
    }

    /// **173-B's ACTUAL BAR.** Everything above passes if both destinations
    /// return one shared string; only this fails.
    @Test
    func theTwoDestinationsDoNotShareOneCaption() throws {
        let hermes = try #require(AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: true))
        let local = try #require(AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: true))
        #expect(hermes != local)
    }

    // MARK: - 173-D: the negative control

    /// Without this, 173-A and 173-B are both satisfied by a caption returned
    /// unconditionally — which would put vision copy on every document and
    /// voice-memo turn.
    @Test
    func aTurnWithNoImageCarriesNoCaption() {
        #expect(AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: false) == nil)
        #expect(AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: false) == nil)
    }

    // MARK: - 173-E: #380's rider — the query-time sensor copy

    /// **173-E**, scored on the bar's INTENT. The bar's evidence clause said
    /// the copy must not contain "streaming"; the shipped copy says *"never
    /// streamed"*, which is the honest way to say it, so a string-exclusion
    /// check would fail the very sentence the bar requires. The mis-written
    /// clause is corrected in the entry, dated and reasoned, rather than
    /// reinterpreted here at scoring time.
    ///
    /// The deliverable turned out to be ALREADY SHIPPED — #260(C)/#352's
    /// `sensorStreamingCaption` predates #380's 08-18 ruling and already
    /// describes exactly the model #380 asked for. This test exists so that
    /// stays true: the copy is load-bearing for a closed decision now, and
    /// nothing else pins it.
    @Test @MainActor
    func theSensorSettingsCopyDescribesTheQueryTimeModel() {
        let copy = PrivacySettingsScreen.sensorStreamingCaptionText

        // The two things #380 ruled the line must convey.
        #expect(copy.localizedCaseInsensitiveContains("on demand"))
        #expect(copy.localizedCaseInsensitiveContains("permission"))

        // And it must NOT describe the pipeline #352 deleted as if it were
        // live. Asserted as an absence of the AFFIRMATIVE claim, not of the
        // word — "never streamed" is correct and contains "stream".
        #expect(!copy.localizedCaseInsensitiveContains("uploads"))
        #expect(!copy.localizedCaseInsensitiveContains("in the background"))
        #expect(!copy.localizedCaseInsensitiveContains("continuously"))
    }

    // MARK: - the image predicate

    @Test
    func carriesImageIsTrueOnlyWhenAnImageIsStaged() {
        #expect(AttachmentCapabilityCopy.carriesImage([1, 2, 3], isImage: { $0 == 2 }))
        #expect(!AttachmentCapabilityCopy.carriesImage([1, 3], isImage: { $0 == 2 }))
        #expect(!AttachmentCapabilityCopy.carriesImage([Int](), isImage: { _ in true }))
    }

    /// The predicate against the REAL type, so a change to
    /// `PendingAttachment.Kind` cannot leave the rule reading a stale shape.
    @Test
    func carriesImageAgreesWithPendingAttachmentKind() {
        let image = PendingAttachment(
            kind: .image, fileName: "photo.jpg", mimeType: "image/jpeg",
            data: Data(), localStoragePath: nil, thumbnailData: nil
        )
        let text = PendingAttachment(
            kind: .file, fileName: "notes.txt", mimeType: "text/plain",
            data: Data(), localStoragePath: nil, thumbnailData: nil
        )
        #expect(AttachmentCapabilityCopy.carriesImage([image], isImage: { $0.kind == .image }))
        #expect(!AttachmentCapabilityCopy.carriesImage([text], isImage: { $0.kind == .image }))
        #expect(AttachmentCapabilityCopy.carriesImage([text, image], isImage: { $0.kind == .image }))
    }
}
