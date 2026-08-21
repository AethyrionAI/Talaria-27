import Foundation

/// #173 — the NEVER-CLAIM FLOOR: the app must not present an image turn as if
/// the model on the other end could see it.
///
/// **The bug this exists for (found 2026-07-23, #142's wire capture).** During
/// a window when image-only sends were failing, the app returned fluent,
/// confident assistant replies with no indication the model had never received
/// the images — one reply discussed the literal text `"[attachment]"`. From
/// the user's side that is indistinguishable from a working conversation with
/// an unhelpful model, so **the user concludes the product is bad at vision
/// rather than that their host is degraded. That is the worst possible
/// attribution**, and it is what this copy prevents.
///
/// **A CAPTION, NEVER A BLOCK.** Owen's ruling (2026-08-18) ships the floor
/// (route a) and parks capability surfacing (route b) as a watch. The send
/// always proceeds and the attachments always go on the wire — bar 173-C pins
/// that separately, because a caption implemented as a guard would satisfy
/// every other bar here while quietly breaking the feature.
///
/// **⛔ THE HERMES PATH CARRIES NO CAPTION — a RULING, not an omission
/// (Owen, 2026-08-20).** It briefly did, and the reason it was removed is the
/// reason not to re-add it:
///
/// No vision signal reaches the app **at all**. There is no `supports_vision`
/// anywhere in `Talaria/`, the model catalog carries no capabilities map, and
/// `/v1/models` returns one synthetic `hermes-agent` row with the bare
/// OpenAI-compat keys (#173's 2026-08-02 probe). Hermes's own catalog HAS the
/// data — `ModelCapabilities.supports_vision` — but nothing forwards it.
///
/// So the caption could not DISCRIMINATE: it fired on every image turn
/// regardless of whether the model could see, including on models that
/// perfectly well could. Owen: *"why does it show for every model, even if it
/// supports images… we can't accurately detect it… so it just stays up."*
/// **A permanent caption is not information — it is furniture.** Users stop
/// reading a warning that is always present, so it fails at the one job #173
/// gave it while taxing every image send.
///
/// **What would justify re-adding it:** a real capability signal (#173's
/// route (b), parked as a watch — upstream forwarding `supports_vision` plus
/// app-side decode `GatewayModelCatalog` does not have). With that, the copy
/// can say something FALSIFIABLE about the model in front of the user. Until
/// then it cannot.
///
/// - **On-device — KNOWN-BLIND, and this is why the on-device caption
///   SURVIVES the removal.** Not unknown: recorded at
///   `LocalChatBackend+Battery.swift:2165-2174` and device-confirmed
///   2026-08-02 (*"I can't see the image itself, but the text in it…"*). Image
///   capability exists ONLY through `readImageText` / `BarcodeReaderTool`; the
///   SDK's `Transcript.ImageAttachment` / `ImageReference` ship but are unused
///   by us, so a toolless route on a photo turn is a blind turn. Saying "not
///   known to support images" where we are certain would be #180's sin
///   inverted — encoding a known-false as an unknown.
///
/// Pure and `nonisolated` so the rule is pinned directly by tests rather than
/// through a view, the same posture as `TalkSessionRules` and
/// `ChatHealthPollPolicy`.
enum AttachmentCapabilityCopy {

    /// Which backend the turn is bound for. Mirrors `ChatBackendRouter.Brain`
    /// rather than importing it, so the rule stays free of the router's
    /// lifecycle — `privateCloud` maps to `.onDevice` at the call site, since
    /// #30 routes it through the local backend that owns the PCC session.
    enum Destination: Sendable {
        case hermesHost
        case onDevice
    }

    /// The caption for a turn, or nil when none is owed.
    ///
    /// `nil` for a turn carrying no image (bar 173-D): a text or document
    /// attachment says nothing about vision, and a caption shown
    /// unconditionally would satisfy 173-A and 173-B while being noise.
    static func caption(
        for destination: Destination,
        carriesImageAttachment: Bool
    ) -> String? {
        guard carriesImageAttachment else { return nil }
        switch destination {
        case .hermesHost:
            // ⛔ NOTHING. See the type's doc comment — this is a RULING
            // (Owen, 2026-08-20), not an omission, and re-adding a caption
            // here needs a new one.
            return nil
        case .onDevice:
            return onDeviceCannotSeeImages
        }
    }

    /// **DEFINITE.** We know, so we say we know.
    static let onDeviceCannotSeeImages =
        "The on-device model can't see images — it will read text found in them, not the picture."

    /// Does this set of staged attachments contain an image?
    ///
    /// Keyed on `kind`, not on the mime type, because `kind` is what the
    /// staging pipeline already resolved; re-deriving it from the mime string
    /// here would be a second spelling of the same question and could drift
    /// from `PendingAttachment`'s own answer.
    static func carriesImage<Attachment>(
        _ attachments: [Attachment],
        isImage: (Attachment) -> Bool
    ) -> Bool {
        attachments.contains(where: isImage)
    }
}
