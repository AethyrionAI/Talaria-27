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

    // MARK: - 173-A WITHDRAWN: the Hermes path carries NO caption

    /// **173-A was withdrawn by a re-ruling (Owen, 2026-08-20), and this test
    /// is its inverse.** The bar required the Hermes path to carry
    /// unknown-capability wording. It shipped, and the problem was immediately
    /// visible: with no `supports_vision` reaching the app the caption could
    /// not DISCRIMINATE, so it fired on every image turn forever — including
    /// on models that can see perfectly well.
    ///
    /// A permanent caption is furniture, not information: users stop reading a
    /// warning that is always present, so it failed the job #173 gave it while
    /// taxing every image send.
    ///
    /// **This is a re-ruling, not a redefinition.** The bar was met, the
    /// result was judged wrong on the device, and the ruling changed — which
    /// is a different thing from rewriting a bar to match what shipped. The
    /// test is inverted rather than deleted so the absence is PINNED: a future
    /// lane that re-adds a caption here without a real capability signal
    /// (#173 route (b), parked) fails this immediately.
    @Test
    func hermesImageTurnCarriesNoCaptionUntilCapabilityIsKnowable() {
        #expect(AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: true, imageInputEnabled: false) == nil)
        #expect(AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: false, imageInputEnabled: false) == nil)
        // #390: real image input on a HERMES turn changes nothing — the
        // 2026-08-20 no-discrimination ruling is about the missing signal
        // from the host, which the local arm's existence does not supply.
        #expect(AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: true, imageInputEnabled: true) == nil)
    }

    // MARK: - 173-B: on-device says something STRONGER, and DIFFERENT
    // (#390 re-cut: the blind string survives for the blind case only —
    // `imageInputEnabled: false` is no-vision-capability, not a stale claim.)

    @Test
    func onDeviceImageTurnSaysItCannotSeeImages() throws {
        let caption = AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: true, imageInputEnabled: false)
        let text = try #require(caption)
        #expect(text == AttachmentCapabilityCopy.onDeviceCannotSeeImages)
        // DEFINITE here — we know (device-confirmed 2026-08-02), so hedging
        // would be #180's sin inverted: a known-false encoded as an unknown.
        #expect(text.localizedCaseInsensitiveContains("can't see"))
        #expect(!text.localizedCaseInsensitiveContains("known"))
    }

    // MARK: - #390: the sighted turns, tier-honest (bars 390-C)

    /// The sighted on-device turn: the picture rides as model input and is
    /// processed on the phone. The string must name WHERE (the phone) and
    /// must not be the blind string.
    @Test
    func onDeviceSightedTurnSaysTheImageIsReadOnThePhone() throws {
        let caption = AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: true, imageInputEnabled: true)
        let text = try #require(caption)
        #expect(text == AttachmentCapabilityCopy.onDeviceReadsImagesOnDevice)
        #expect(text.localizedCaseInsensitiveContains("iPhone"))
        #expect(text != AttachmentCapabilityCopy.onDeviceCannotSeeImages)
        // The recommended-against affirmative stays out until 390-E's proof
        // has lived on device: no "never leaves" promise in the caption.
        #expect(!text.localizedCaseInsensitiveContains("never leaves"))
    }

    /// #390-F interim: the PCC arm ships disabled, so a PCC image turn is
    /// an OCR turn — and it says so in ITS OWN words. The un-fold is the
    /// bar: the old code sent `.privateCloud` into the nil-caption Hermes
    /// arm (a silent blind turn), and the entry's "folded into on-device"
    /// description was the comment's story, not the code's.
    @Test
    func privateCloudArmOffCarriesItsOwnHonestOCRCaption() throws {
        let caption = AttachmentCapabilityCopy.caption(for: .privateCloud, carriesImageAttachment: true, imageInputEnabled: false)
        let text = try #require(caption)
        #expect(text == AttachmentCapabilityCopy.privateCloudCannotSeeImages)
        #expect(text.localizedCaseInsensitiveContains("Private Cloud"))
        #expect(text != AttachmentCapabilityCopy.onDeviceCannotSeeImages)
    }

    /// The sighted PCC turn — pinned NOW, rendered only after the 390-F
    /// flip. The string must name Apple: where the picture goes is the one
    /// fact this caption exists to disclose.
    @Test
    func privateCloudSightedTurnSaysTheImageGoesToApple() throws {
        let caption = AttachmentCapabilityCopy.caption(for: .privateCloud, carriesImageAttachment: true, imageInputEnabled: true)
        let text = try #require(caption)
        #expect(text == AttachmentCapabilityCopy.privateCloudSendsImagesToApple)
        #expect(text.localizedCaseInsensitiveContains("Apple"))
    }

    /// 173-B's inequality, extended across the #390 matrix: every rendered
    /// caption is distinct — one shared string across tiers or sighted
    /// states would satisfy each wording test while failing the ruling.
    @Test
    func theFourLocalCaptionsAreAllDistinct() {
        let all = [
            AttachmentCapabilityCopy.onDeviceCannotSeeImages,
            AttachmentCapabilityCopy.onDeviceReadsImagesOnDevice,
            AttachmentCapabilityCopy.privateCloudCannotSeeImages,
            AttachmentCapabilityCopy.privateCloudSendsImagesToApple,
        ]
        #expect(Set(all).count == all.count)
    }

    /// **173-B's inequality bar, now trivially satisfied and kept as a
    /// TRIPWIRE.** It originally guarded against one shared string standing in
    /// for two epistemic states. With the Hermes side removed there is only
    /// one string, so the inequality holds by construction — but the test
    /// stays, because the shape it forbids is exactly what a future lane
    /// re-adding a Hermes caption would reach for first: reusing the
    /// on-device wording, which asserts a definite blindness we cannot
    /// establish for a remote host.
    @Test
    func theOnDeviceCaptionIsNeverReusedForAHost() throws {
        let local = try #require(AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: true, imageInputEnabled: false))
        #expect(AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: true, imageInputEnabled: false) != local)
    }

    // MARK: - 173-D: the negative control

    /// Without this, 173-A and 173-B are both satisfied by a caption returned
    /// unconditionally — which would put vision copy on every document and
    /// voice-memo turn.
    @Test
    func aTurnWithNoImageCarriesNoCaption() {
        #expect(AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: false, imageInputEnabled: false) == nil)
        #expect(AttachmentCapabilityCopy.caption(for: .hermesHost, carriesImageAttachment: false, imageInputEnabled: false) == nil)
        // #390: the negative control covers the new axis too — a sighted
        // tier with nothing staged still owes nothing.
        #expect(AttachmentCapabilityCopy.caption(for: .onDevice, carriesImageAttachment: false, imageInputEnabled: true) == nil)
        #expect(AttachmentCapabilityCopy.caption(for: .privateCloud, carriesImageAttachment: false, imageInputEnabled: true) == nil)
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
