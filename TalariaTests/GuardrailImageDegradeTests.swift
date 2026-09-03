import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Talaria

/// #408 — a guardrail-declined image turn degrades ONCE to the OCR path.
///
/// Owen's laundromat photo threw `LanguageModelError.guardrailViolation` at
/// GENERATION time on the on-device tier (2026-08-25, build 3022). #390-B's
/// fallback is COMPOSE-time only, so the turn dead-ended at Retry — which
/// re-ran the identical prompt into the same wall. Route (a) was ruled:
/// catch it, retry once with the images demoted to #390-B's honest
/// placeholder, and say so in the reply.
///
/// The sim cannot generate (#324), so what a test can reach is the DECISION
/// (a pure predicate), the DEGRADE (the same compose call #390-B makes), the
/// NOTE (a pure composition), and the WIRING (source-structural, the shape
/// `ImageInputCompositionTests` already uses for the image door — the
/// `HonestyGuardWiringTests` residual says why: both turn paths need a live
/// `LanguageModelSession`). Generation itself is the device runbook card.
struct GuardrailImageDegradeTests {

    // MARK: - fixtures

    /// A real, decodable PNG — generated, not a bundle resource, so the
    /// fixture cannot rot out of the target (`ImageInputCompositionTests`'
    /// shape, deliberately duplicated rather than shared: these two files
    /// pin different properties and must not fail together for one reason).
    private static func makePNGData() throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func imageAttachment(_ data: Data, name: String = "laundromat.png") -> PendingAttachment {
        PendingAttachment(
            kind: .image, fileName: name, mimeType: "image/png",
            data: data, localStoragePath: nil, thumbnailData: nil
        )
    }

    private static let guardrail = LanguageModelError.guardrailViolation(
        LanguageModelError.GuardrailViolation(debugDescription: "declined"))

    // MARK: - the error class

    @Test("408: the typed guardrail case is recognized, and its deprecated twin with it")
    func recognizesBothGuardrailErrorTypes() {
        #expect(LocalChatBackend.isGuardrailViolation(Self.guardrail))
        #expect(LocalChatBackend.isGuardrailViolation(
            LanguageModelSession.GenerationError.guardrailViolation(
                LanguageModelSession.GenerationError.Context(debugDescription: "declined"))))
    }

    @Test("408: no other failure reads as a guardrail decline")
    func otherFailuresAreNotGuardrailViolations() {
        #expect(!LocalChatBackend.isGuardrailViolation(
            LanguageModelError.rateLimited(
                LanguageModelError.RateLimited(resetDate: nil, debugDescription: "x"))))
        #expect(!LocalChatBackend.isGuardrailViolation(
            LanguageModelError.refusal(
                LanguageModelError.Refusal(explanation: "x", debugDescription: "x"))))
        #expect(!LocalChatBackend.isGuardrailViolation(
            NSError(domain: "x", code: 1)))
    }

    // MARK: - 408-A: the decision

    @Test("408-A: a guardrail decline on an image-carrying on-device turn degrades")
    func theImageCarryingOnDeviceTurnDegrades() {
        #expect(LocalChatBackend.shouldDegradeImagesAfterGuardrail(
            Self.guardrail, tierIsOnDevice: true, turnCarriedImages: true, didAlreadyDegrade: false))
    }

    @Test("408-A: the degrade reuses #390-B's compose path — no second implementation")
    func theDegradeReusesTheComposeTimeFallback() throws {
        let png = try Self.makePNGData()
        let attachments = [Self.imageAttachment(png)]
        let degraded = LocalChatBackend.degradedTurnInput(
            message: "what does this say?", attachments: attachments, savedNote: nil)

        // The retry's input: zero image attachments, the honest placeholder.
        #expect(degraded.images.isEmpty)
        #expect(degraded.promptText.contains("laundromat.png"))
        #expect(degraded.promptText.contains("can't view the picture"))

        // …and byte-identical to the compose-time fallback, which is what
        // "the SAME compose path" means operationally.
        let composeTime = LocalChatBackend.composeTurnInput(
            message: "what does this say?", attachments: attachments, imageInputEnabled: false, savedNote: nil)
        #expect(degraded.promptText == composeTime.promptText)
        #expect(composeTime.images.isEmpty)

        // The sighted arm is what it degrades FROM — if this stopped
        // differing, the pin above would be vacuous.
        let sighted = LocalChatBackend.composeTurnInput(
            message: "what does this say?", attachments: attachments, imageInputEnabled: true, savedNote: nil)
        #expect(sighted.images.count == 1)
        #expect(sighted.promptText != degraded.promptText)
    }

    @Test("408-A: the degrade is one call into composeTurnInput with the arm forced off")
    func theDegradeHasNoSecondComposeImplementation() throws {
        let body = try Self.backendFunctionBody(
            from: "static func degradedTurnInput", limit: 400)
        #expect(body.contains("composeTurnInput("),
                "the degrade must call the ONE compose path, not re-partition the turn itself")
        #expect(body.contains("imageInputEnabled: false"),
                "the degrade must force the arm off — that IS the demotion")
    }

    // MARK: - 408-B: one retry only

    @Test("408-B: a second guardrail decline does not degrade again")
    func theDegradeHappensAtMostOnce() {
        #expect(!LocalChatBackend.shouldDegradeImagesAfterGuardrail(
            Self.guardrail, tierIsOnDevice: true, turnCarriedImages: true, didAlreadyDegrade: true),
                "a decline on the DEGRADED retry is a plain error — no loop")
    }

    @Test("408-B: a NON-guardrail failure never degrades, retried or not")
    func otherFailuresNeverDegrade() {
        for error in [
            LanguageModelError.rateLimited(
                LanguageModelError.RateLimited(resetDate: nil, debugDescription: "x")) as Error,
            LanguageModelError.timeout(LanguageModelError.Timeout(debugDescription: "x")) as Error,
            NSError(domain: "x", code: 1) as Error,
        ] {
            #expect(!LocalChatBackend.shouldDegradeImagesAfterGuardrail(
                error, tierIsOnDevice: true, turnCarriedImages: true, didAlreadyDegrade: false))
        }
    }

    // MARK: - 408-C: a text-only decline is unchanged

    @Test("408-C: a guardrail decline on a TEXT-only turn stays a plain error")
    func theTextOnlyDeclineIsUnchanged() {
        #expect(!LocalChatBackend.shouldDegradeImagesAfterGuardrail(
            Self.guardrail, tierIsOnDevice: true, turnCarriedImages: false, didAlreadyDegrade: false),
                "demoting nothing cannot help a text-only decline")
    }

    // MARK: - tier scope: PCC is untouched

    @Test("408: the retry is on-device only — the PCC arm keeps its plain error")
    func thePrivateCloudTierIsUntouched() {
        #expect(!LocalChatBackend.shouldDegradeImagesAfterGuardrail(
            Self.guardrail, tierIsOnDevice: false, turnCarriedImages: true, didAlreadyDegrade: false),
                "PCC described this exact photo cleanly — its declines are not this item")
    }

    // MARK: - 408-D: the reply surface says what happened

    @Test("408-D: the note names the tier, the cause, and what the answer is built from")
    func theNoteSaysWhatHappened() {
        let note = LocalChatBackend.guardrailImageDegradeNote(imageCount: 1)
        #expect(!note.isEmpty)
        #expect(note.contains("on-device"), "the tier is the whole point — PCC saw this picture")
        #expect(note.contains("safety"), "name the true cause (#212)")
        // It must not promise that a retry will work: the n=4 reading is that
        // the guardrail's verdict is stable per image.
        let lowered = note.lowercased()
        #expect(!lowered.contains("try again"))
        #expect(!lowered.contains("retry"))
    }

    @Test("408-D: the note pluralizes rather than lying about how many pictures were demoted")
    func theNotePluralizes() {
        let one = LocalChatBackend.guardrailImageDegradeNote(imageCount: 1)
        let two = LocalChatBackend.guardrailImageDegradeNote(imageCount: 2)
        #expect(one.contains("the attached image,"))
        #expect(two.contains("the attached images,"))
        #expect(one != two)
    }

    @Test("408-D: the note is APPENDED — the model's own answer survives verbatim")
    func theNoteIsAppendedToTheAnswer() {
        let answer = "I can't see the picture, but the sign text reads WASH & FOLD."
        let out = LocalChatBackend.replyNotingGuardrailImageDegrade(answer, degradedImageCount: 1)
        #expect(out.hasPrefix(answer), "silent rewriting is its own trust problem")
        #expect(out == answer + "\n\n" + LocalChatBackend.guardrailImageDegradeNote(imageCount: 1))
    }

    @Test("408-D: an empty reply still carries the note, not an empty bubble")
    func anEmptyReplyStillCarriesTheNote() {
        #expect(LocalChatBackend.replyNotingGuardrailImageDegrade("", degradedImageCount: 1)
                == LocalChatBackend.guardrailImageDegradeNote(imageCount: 1))
    }

    @Test("408-D: a turn that never degraded carries no note at all")
    func anUndegradedTurnIsUntouched() {
        let answer = "A blue towel, a yellow bag, and a white sheet."
        #expect(LocalChatBackend.replyNotingGuardrailImageDegrade(answer, degradedImageCount: 0) == answer)
    }

    // MARK: - the wiring (source-structural)

    /// Both turn paths throw `guardrailViolation` from the same place —
    /// `respond(to:)` and `streamResponse(to:)` — so a retry that covers only
    /// one is a half-fix. Nothing a simulator runs can reach either catch
    /// block (both need a live `LanguageModelSession`), which is exactly the
    /// residual `HonestyGuardWiringTests` records; this is the reach a test
    /// does have.
    @Test("408: the NON-streaming turn path carries the degrade arm and the note")
    func theSyncTurnPathIsWired() throws {
        try Self.expectWired(from: "func send(", to: "func sendStreaming(")
    }

    @Test("408: the STREAMING turn path carries the degrade arm and the note")
    func theStreamingTurnPathIsWired() throws {
        try Self.expectWired(from: "func streamTurn(", to: "private func failureMessageForActiveTier(")
    }

    private static func expectWired(from start: String, to end: String) throws {
        let body = try backendRegion(from: start, to: end)
        #expect(body.contains("shouldDegradeImagesAfterGuardrail("),
                "\(start) does not consult the #408 decision — that path still dead-ends")
        #expect(body.contains("degradedTurnInput("),
                "\(start) does not re-compose the demoted turn")
        #expect(body.contains("replyNotingGuardrailImageDegrade("),
                "\(start) answers a degraded turn without saying so (408-D)")
    }

    // MARK: - source helpers

    private static func backendSource() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Services/Live/LocalChatBackend.swift")
        return try #require(
            try? String(contentsOf: path, encoding: .utf8),
            "LocalChatBackend.swift unreadable — these pins must fail loudly, not vacuously"
        )
    }

    private static func backendRegion(from start: String, to end: String) throws -> String {
        let source = try backendSource()
        let startRange = try #require(
            source.range(of: start),
            "\(start) is gone — re-point this pin at its successor")
        let rest = source[startRange.upperBound...]
        let endRange = try #require(
            rest.range(of: end),
            "\(end) is gone — re-point this pin at its successor")
        return String(rest[..<endRange.lowerBound])
    }

    private static func backendFunctionBody(from anchor: String, limit: Int) throws -> String {
        let source = try backendSource()
        let range = try #require(
            source.range(of: anchor),
            "\(anchor) is gone — re-point this pin at its successor")
        return String(source[range.upperBound...].prefix(limit))
    }
}
