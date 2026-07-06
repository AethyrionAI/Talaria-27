import Foundation
import Testing
@testable import Talaria

/// #8 / #43 — attachment inlining: staged text-MIME files become delimited
/// `{type:"text"}` parts instead of silently vanishing; images stay data-URL
/// parts; text-only turns assemble to NO parts so the wire body remains a
/// plain string. The delimiter format asserted here is a shared surface —
/// the voice-memo transcript path (issue H) reuses it.
struct AttachmentInliningTests {

    // MARK: Fixtures

    private func textFile(
        named fileName: String = "notes.md",
        mimeType: String = "text/markdown",
        content: String
    ) -> PendingAttachment {
        PendingAttachment(
            kind: .file,
            fileName: fileName,
            mimeType: mimeType,
            data: Data(content.utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    private func image(named fileName: String = "photo.jpg", byteCount: Int = 64) -> PendingAttachment {
        PendingAttachment(
            kind: .image,
            fileName: fileName,
            mimeType: "image/jpeg",
            data: Data(repeating: 0xAB, count: byteCount),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    private func rawPDF(named fileName: String = "report.pdf") -> PendingAttachment {
        PendingAttachment(
            kind: .file,
            fileName: fileName,
            mimeType: "application/pdf",
            data: Data(repeating: 0x25, count: 128),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    // MARK: Wire-shape preservation

    @Test func textOnlyTurnAssemblesNoParts() {
        let assembly = AttachmentInlining.assemble(message: "hello", attachments: [])
        // Empty parts ⇒ the client sends the plain string, byte-identical to
        // the pre-attachment wire shape.
        #expect(assembly.parts.isEmpty)
        #expect(assembly.omittedForBudget.isEmpty)
        #expect(assembly.notTransmittable.isEmpty)
    }

    @Test func rawPDFAloneProducesNoPartsAndIsReported() {
        let assembly = AttachmentInlining.assemble(message: "look at this", attachments: [rawPDF()])
        // Nothing is fabricated for an un-extracted PDF — it has no wire
        // representation, and it must be reported, never silently dropped.
        #expect(assembly.parts.isEmpty)
        #expect(assembly.notTransmittable == ["report.pdf"])
    }

    // MARK: Text-MIME inlining (#43)

    @Test func textFileInlinesAsDelimitedTextPart() {
        let assembly = AttachmentInlining.assemble(
            message: "summarize this",
            attachments: [textFile(content: "alpha beta")]
        )

        #expect(assembly.parts.count == 2)
        #expect(assembly.parts[0] == .text("summarize this"))
        guard case .text(let block) = assembly.parts[1] else {
            Issue.record("expected a delimited text part for the file")
            return
        }
        #expect(block.hasPrefix("===== BEGIN FILE: notes.md (text/markdown, 10 bytes) =====\n"))
        #expect(block.contains("alpha beta"))
        #expect(block.hasSuffix("\n===== END FILE: notes.md ====="))
        #expect(assembly.omittedForBudget.isEmpty)
        #expect(assembly.notTransmittable.isEmpty)
    }

    @Test func delimiterFormatIsStable() {
        // Issue H builds voice-memo transcript parts through this exact shape.
        let block = AttachmentInlining.delimitedTextPart(
            fileName: "notes.md",
            mimeType: "text/markdown",
            content: "hello"
        )
        #expect(block == """
        ===== BEGIN FILE: notes.md (text/markdown, 5 bytes) =====
        hello
        ===== END FILE: notes.md =====
        """)
    }

    @Test func markerNamesStripNewlines() {
        let block = AttachmentInlining.delimitedTextPart(
            fileName: "a\nb.txt",
            mimeType: "text/plain",
            content: "x"
        )
        #expect(block.hasPrefix("===== BEGIN FILE: a b.txt "))
    }

    @Test func emptyMessageOmitsLeadingTextPart() {
        let assembly = AttachmentInlining.assemble(message: "  ", attachments: [textFile(content: "x")])
        #expect(assembly.parts.count == 1)
        guard case .text(let block) = assembly.parts[0] else {
            Issue.record("expected the file part first when the message is blank")
            return
        }
        #expect(block.hasPrefix("===== BEGIN FILE:"))
    }

    // MARK: Ordering

    @Test func stagedOrderIsPreserved() {
        let assembly = AttachmentInlining.assemble(
            message: "",
            attachments: [
                image(named: "a.jpg"),
                textFile(named: "b.md", content: "b"),
                image(named: "c.jpg"),
            ]
        )
        #expect(assembly.parts.count == 3)
        guard case .imageDataURL = assembly.parts[0],
              case .text = assembly.parts[1],
              case .imageDataURL = assembly.parts[2] else {
            Issue.record("staged order was not preserved across mixed part kinds")
            return
        }
    }

    @Test func imagePartIsDataURL() {
        let attachment = image(byteCount: 3)
        let assembly = AttachmentInlining.assemble(message: "", attachments: [attachment])
        guard case .imageDataURL(let url) = assembly.parts.first else {
            Issue.record("expected an image data-URL part")
            return
        }
        #expect(url == "data:image/jpeg;base64,\(attachment.data.base64EncodedString())")
    }

    // MARK: Budget + truncation

    @Test func oversizedTextIsTruncatedInsideTheBlock() {
        let content = String(repeating: "a", count: AttachmentInlining.maxInlinedTextBytes + 500)
        let block = AttachmentInlining.delimitedTextPart(
            fileName: "big.txt",
            mimeType: "text/plain",
            content: content
        )
        // Header keeps the ORIGINAL size; the notice reports the sent prefix.
        #expect(block.hasPrefix("===== BEGIN FILE: big.txt (text/plain, \(content.utf8.count) bytes) =====\n"))
        #expect(block.contains(
            "[Talaria: truncated — first \(AttachmentInlining.maxInlinedTextBytes) of \(content.utf8.count) bytes]"
        ))
        #expect(block.utf8.count < content.utf8.count)
    }

    @Test func truncationRespectsCharacterBoundaries() {
        // "é" is 2 bytes in UTF-8 — an odd cap forces a mid-character cut, which
        // must back off to the previous boundary instead of splitting the char.
        let content = String(repeating: "é", count: 10)
        let prefix = AttachmentInlining.utf8SafePrefix(content, maxBytes: 7)
        #expect(prefix == String(repeating: "é", count: 3))
    }

    @Test func budgetExhaustionSendsOmissionStub() {
        // Two images whose data URLs together exceed the aggregate budget:
        // the second must ship as an in-band omission stub, not vanish.
        // 600 KB raw → ~819 KB base64 data URL; the first fits under 900 KB,
        // the second doesn't.
        let big = 600 * 1024
        let assembly = AttachmentInlining.assemble(
            message: "",
            attachments: [
                image(named: "first.jpg", byteCount: big),
                image(named: "second.jpg", byteCount: big),
            ]
        )

        #expect(assembly.omittedForBudget == ["second.jpg"])
        #expect(assembly.parts.count == 2)
        guard case .imageDataURL = assembly.parts[0] else {
            Issue.record("expected the first image to transmit")
            return
        }
        guard case .text(let stub) = assembly.parts[1] else {
            Issue.record("expected an omission stub for the second image")
            return
        }
        #expect(stub.contains("BEGIN FILE: second.jpg"))
        #expect(stub.contains("[Talaria: file omitted — message size budget exceeded]"))
    }

    // MARK: PendingAttachment classification + extracted-text factory (#8)

    @Test func transmittabilityClassification() {
        #expect(image().isTransmittable)
        #expect(textFile(content: "x").isTransmittable)
        #expect(!rawPDF().isTransmittable)

        #expect(image().isExtractable)
        #expect(rawPDF().isExtractable)
        #expect(!textFile(content: "x").isExtractable)

        #expect(PendingAttachment.supportsMimeType("application/pdf"))
        #expect(PendingAttachment.stagingCap(forMimeType: "application/pdf") == PendingAttachment.maxPDFFileSize)
        #expect(PendingAttachment.stagingCap(forMimeType: "text/plain") == PendingAttachment.maxFileSize)
    }

    @Test func extractedTextFactoryDescribesItselfHonestly() {
        let source = image(named: "scan.jpg")
        let extracted = PendingAttachment.extractedText(from: source, text: "hello world")

        #expect(extracted.kind == .file)
        #expect(extracted.fileName == "scan.jpg.extracted.md")
        #expect(extracted.mimeType == "text/markdown")
        #expect(extracted.data == Data("hello world".utf8))
        // No thumbnail carried over — the chip must not look like an image.
        #expect(extracted.thumbnailData == nil)
        #expect(extracted.isTransmittable)
    }
}
