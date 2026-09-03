import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Talaria

/// #390 — true image input on both local tiers, OCR as fallback.
///
/// The sim cannot generate (#324), so everything here pins COMPOSITION, not
/// generation: which side of the turn an image lands on (real input vs the
/// honest placeholder), that the 390-F arm gate holds, and that the replay
/// seam stays text-only — 390-A's current-turn-only rule and 390-E's
/// escalation cleanliness are both properties of that one seam
/// (`transcriptEntries`), because escalation replays through the same
/// rebuild. Generation itself is the device runbook card (390-G).
struct ImageInputCompositionTests {

    // MARK: - fixtures

    /// A real, decodable PNG — generated, not a bundle resource, so the
    /// fixture cannot rot out of the target.
    private static func makePNGData() throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
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

    private static func imageAttachment(_ data: Data, name: String = "photo.png") -> PendingAttachment {
        PendingAttachment(
            kind: .image, fileName: name, mimeType: "image/png",
            data: data, localStoragePath: nil, thumbnailData: nil
        )
    }

    // MARK: - 390-A: the image rides as real input, current turn only

    @Test func imageAttachmentsRideAsRealInputWhenEnabled() throws {
        let png = try Self.makePNGData()
        let input = LocalChatBackend.composeTurnInput(
            message: "What is this?",
            attachments: [Self.imageAttachment(png)],
            imageInputEnabled: true,
            savedNote: nil
        )
        #expect(input.images.count == 1)
        #expect(input.images.first?.label == "photo.png")
        // The text side carries NO placeholder for an image that rides as
        // real input — a placeholder would instruct the model to deny
        // seeing a picture it was handed.
        #expect(input.promptText == "What is this?")
    }

    @Test func textAndFileAttachmentsAreUntouchedByTheImageArm() throws {
        let png = try Self.makePNGData()
        let file = PendingAttachment(
            kind: .file, fileName: "notes.md", mimeType: "text/markdown",
            data: Data("- remember the milk".utf8), localStoragePath: nil, thumbnailData: nil
        )
        let input = LocalChatBackend.composeTurnInput(
            message: "Summarize, and what's in the photo?",
            attachments: [file, Self.imageAttachment(png)],
            imageInputEnabled: true,
            savedNote: nil
        )
        #expect(input.images.count == 1)
        #expect(input.promptText.contains("===== BEGIN FILE: notes.md"))
        #expect(input.promptText.contains("- remember the milk"))
        #expect(!input.promptText.contains("photo.png"))
    }

    // MARK: - 390-B: the OCR fallback survives
    // (Both ran RED first via the placeholder re-cut; the fallback LOGIC's
    // teeth are the MUTATION run — deleting the decode-failure fallback or
    // the arm gate must turn them RED. Recorded in the entry's result block.)

    @Test func undecodableImageDegradesToTheHonestPlaceholder() {
        let input = LocalChatBackend.composeTurnInput(
            message: "What is this?",
            attachments: [Self.imageAttachment(Data([0xFF, 0xD8, 0xFF]), name: "broken.jpg")],
            imageInputEnabled: true,
            savedNote: nil
        )
        #expect(input.images.isEmpty)
        #expect(input.promptText.contains("broken.jpg"))
        #expect(input.promptText.contains("can't view the picture"))
    }

    @Test func imageInputDisabledKeepsTheOCRPath() throws {
        let png = try Self.makePNGData()
        let input = LocalChatBackend.composeTurnInput(
            message: "What is this?",
            attachments: [Self.imageAttachment(png)],
            imageInputEnabled: false,
            savedNote: nil
        )
        #expect(input.images.isEmpty)
        #expect(input.promptText.contains("photo.png"))
        #expect(input.promptText.contains("can't view the picture"))
    }

    // MARK: - 390-F: the PCC arm is ON, behind the published policy

    /// #390-F DISCHARGED (2026-08-25, Owen's go): the privacy policy's
    /// image sentence published in the SAME PR that flipped this — the
    /// Changes clause's "updated before the change ships" holds because
    /// the policy goes live at merge and the arm reaches devices only via
    /// the OTA staged after. ⛔ Turning the arm back OFF is a product
    /// decision with a policy implication — not a drive-by; it needs its
    /// own ruling, and this pin re-cut with it.
    @Test func thePCCImageArmIsOnBehindThePublishedPolicy() {
        #expect(LocalChatBackend.pccImageInputEnabled == true)
    }

    // MARK: - 390-A/E: the replay seam is text-only

    /// Behavioral: history that CARRIED images replays as text-only
    /// entries. This is the whole of 390-A's "current turn only" once
    /// images exist, and 390-E falls out of it — the escalation handover
    /// (`setPreferredTier` → session nil → rebuild) replays through this
    /// same constructor, so an image that cannot enter here cannot cross
    /// tiers either.
    @Test func replayedTranscriptEntriesAreTextOnly() throws {
        let png = try Self.makePNGData()
        let history = [
            Message(sender: .user, content: "look at this", status: .delivered,
                    attachments: [MessageAttachment(from: Self.imageAttachment(png))]),
            Message(sender: .hermes, content: "A red square.", status: .delivered),
        ]
        let turns = LocalChatBackend.transcriptTurns(from: history, excludingClientMessageID: nil)
        let entries = LocalChatBackend.transcriptEntries(
            instructions: "You are Hermes.", verbatimTurns: turns
        )
        #expect(!entries.isEmpty)
        for entry in entries {
            for segment in Self.segments(of: entry) {
                guard case .text = segment else {
                    Issue.record("replayed entry carries a non-text segment: \(segment)")
                    continue
                }
            }
        }
    }

    private static func segments(of entry: Transcript.Entry) -> [Transcript.Segment] {
        switch entry {
        case .instructions(let instructions): instructions.segments
        case .prompt(let prompt): prompt.segments
        case .response(let response): response.segments
        default: []
        }
    }

    /// Structural (#399-shape): the replay builder constructs ONLY text
    /// segments. The behavioral pin above proves today's inputs; this one
    /// catches the door being widened for an input the test didn't stage.
    @Test func theReplayBuilderConstructsOnlyTextSegments() throws {
        let source = try Self.backendSource()
        guard let funcRange = source.range(of: "static func transcriptEntries") else {
            Issue.record("transcriptEntries is gone — re-point this pin at the replay builder's successor")
            return
        }
        let body = String(source[funcRange.upperBound...].prefix(2400))
        #expect(body.contains("TextSegment"), "the replay builder no longer builds text segments — re-read this pin")
        #expect(!body.contains("AttachmentSegment"), "the replay builder constructs attachment segments — images can re-upload from history (390-A)")
        #expect(!body.contains(".attachment("), "the replay builder emits attachment segments — images can re-upload from history (390-A)")
    }

    /// Structural (#399-shape): exactly ONE door hands a CGImage to the
    /// model — the turn-prompt assembler, fed only by `composeTurnInput`'s
    /// current-turn images. A second construction site is a second door,
    /// and the seam tests above cannot see it.
    @Test func theOnlyImageAttachmentDoorIsTheTurnPromptAssembler() throws {
        let source = try Self.backendSource()
        let doorLines = source.components(separatedBy: "\n").filter {
            $0.contains("Attachment(") && $0.contains("cgImage")
        }
        #expect(
            doorLines.count == 1,
            "expected exactly one image-attachment construction (the assembler); found \(doorLines.count): \(doorLines)"
        )
        if let funcRange = source.range(of: "static func makeTurnPrompt") {
            let body = String(source[funcRange.upperBound...].prefix(900))
            #expect(
                body.contains("Attachment("),
                "the assembler no longer constructs the attachment — where did the door move?"
            )
        } else {
            Issue.record("makeTurnPrompt is gone — re-point this pin at the assembler's successor")
        }
    }

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

    // MARK: - the caption's brain → destination mapping (390-C's un-fold)

    /// The 08-24 code read found `.privateCloud` silently falling into the
    /// nil-caption Hermes arm — a PCC image turn showed NOTHING, #173's
    /// sin on the tier where the answer matters most. The mapping is a
    /// static precisely so this test sees it.
    @Test @MainActor func chatInputBarRoutesPrivateCloudToItsOwnCaption() {
        #expect(
            ChatInputBar.visionCaption(activeBrain: .privateCloud, carriesImage: true, imageInputEnabled: false)
                == AttachmentCapabilityCopy.privateCloudCannotSeeImages
        )
        #expect(
            ChatInputBar.visionCaption(activeBrain: .privateCloud, carriesImage: true, imageInputEnabled: true)
                == AttachmentCapabilityCopy.privateCloudSendsImagesToApple
        )
    }

    @Test @MainActor func chatInputBarRoutesTheOtherBrainsUnchanged() {
        #expect(
            ChatInputBar.visionCaption(activeBrain: .onDevice, carriesImage: true, imageInputEnabled: false)
                == AttachmentCapabilityCopy.onDeviceCannotSeeImages
        )
        #expect(
            ChatInputBar.visionCaption(activeBrain: .onDevice, carriesImage: true, imageInputEnabled: true)
                == AttachmentCapabilityCopy.onDeviceReadsImagesOnDevice
        )
        // A nil brain is an UNKNOWN — the Hermes arm's claim-nothing nil.
        #expect(ChatInputBar.visionCaption(activeBrain: nil, carriesImage: true, imageInputEnabled: false) == nil)
        #expect(ChatInputBar.visionCaption(activeBrain: .hermes, carriesImage: true, imageInputEnabled: false) == nil)
        #expect(ChatInputBar.visionCaption(activeBrain: .onDevice, carriesImage: false, imageInputEnabled: true) == nil)
    }
}
