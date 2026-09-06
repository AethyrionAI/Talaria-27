import Foundation
import Testing
import UIKit
@testable import Talaria

/// #431 bars A and B — the share extension may no longer accept a file the app
/// will then drop.
///
/// The defect this pins: `ShareViewController.blobItem` gated on TYPE plus the
/// 20 MB aggregate envelope budget and nothing else, while
/// `PendingAttachment.file(at:)` refuses a non-PDF above 350 KB — **a 58×
/// window** — and a PDF above 10 MB. Everything in between was accepted with a
/// green tick, queued, drained, logged as `skipped unconvertible item`, and
/// deleted.
///
/// **Why the decision lives in `StageableTypeCatalog` rather than in the
/// extension:** there is no `TalariaShareTests` target (`project.yml`), so
/// nothing in `TalariaShare/` except the shared `ShareInboxCore.swift` is
/// reachable from any suite. A rule written in `ShareViewController` is a rule
/// that cannot be tested — which is exactly how the gap survived #123 and
/// #180-E.
@MainActor
struct ShareCapPolicyTests {

    // MARK: Fixtures

    /// The full stageable surface: every text MIME the catalog knows, the PDF
    /// type, and the image types the extension's own `extensionToMime` table
    /// can produce (that table is private, so the image rows are named here
    /// and `sizePolicyAgreesWithStageability` guards the seam).
    private static var allStageableMimeTypes: [String] {
        Array(StageableTypeCatalog.textMimeTypes).sorted()
            + [StageableTypeCatalog.pdfMimeType]
            + ["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"]
    }

    private static let shareBudget = SharedInboxStore.defaultMaxEnvelopeBytes

    /// The byte count a stated cap label claims, so a label can be compared
    /// against the cap it explains (#180-E's arithmetic rule, applied to the
    /// per-type caps this lane introduces). Unit-aware on purpose: "350 KB"
    /// and "10 MB" are not comparable as bare numbers.
    private func statedBytes(_ label: String) -> Int {
        let parts = label.split(separator: " ")
        guard parts.count == 2, let magnitude = Double(parts[0]) else { return -1 }
        let multiplier: Double
        switch parts[1] {
        case "bytes": multiplier = 1
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        default: return -1
        }
        return Int(magnitude * multiplier)
    }

    private func refusalMessage(
        _ fileName: String,
        _ byteCount: Int,
        remainingBytes: Int = ShareCapPolicyTests.shareBudget
    ) -> String? {
        guard case .refused(let message) = StageableTypeCatalog.acceptance(
            fileName: fileName, byteCount: byteCount, remainingBytes: remainingBytes
        ) else { return nil }
        return message
    }

    // MARK: - 431-A — one size policy, read by both halves

    /// **431-A.** For every stageable type with a hard cap, the number the
    /// extension enforces IS the number the app enforces. Green today by
    /// construction — `PendingAttachment.stagingCap` is derived from this very
    /// table — and that is the point: it is a PIN against the two drifting
    /// apart again, not a proof that they agree today. Its job is mutation M1.
    @Test func everyStageableTypeCapMatchesTheAppStagingCap() {
        for mime in Self.allStageableMimeTypes {
            switch StageableTypeCatalog.sizePolicy(forMimeType: mime) {
            case .refusedAbove(let bytes, _):
                #expect(
                    PendingAttachment.stagingCap(forMimeType: mime) == bytes,
                    """
                    \(mime): the share sheet would accept up to \(bytes) bytes \
                    but the app stages up to \
                    \(PendingAttachment.stagingCap(forMimeType: mime)) — \
                    the window between them is what #431 closes
                    """)
            case .reEncodedToFit:
                #expect(mime.hasPrefix("image/"),
                        "\(mime) claims the app re-encodes it, but only images are re-encoded")
            case .unsupportedType:
                Issue.record("\(mime) is stageable, so it must have a size policy")
            }
        }
    }

    /// **431-A, the seam between the two tables.** A type is stageable if and
    /// only if it has a size policy. Two tables in one enum that can disagree
    /// is how a "single source of truth" becomes two.
    @Test func sizePolicyAgreesWithStageability() {
        let probes = Self.allStageableMimeTypes
            + ["video/quicktime", "audio/mpeg", "application/zip", "application/octet-stream"]
        for mime in probes {
            let stageable = StageableTypeCatalog.isStageable(mimeType: mime)
            let unsupported = StageableTypeCatalog.sizePolicy(forMimeType: mime) == .unsupportedType
            #expect(stageable == !unsupported,
                    "\(mime): isStageable=\(stageable) but sizePolicy says unsupported=\(unsupported)")
        }
    }

    /// **431-A, #180-E's rule applied to the new caps.** A stated limit that
    /// rounds UP past the cap it explains cannot explain a refusal at the
    /// boundary — that was the whole of #180-E, and `ByteCountFormatter` would
    /// have reintroduced it here: 10,485,760 renders as "10.5 MB", a limit
    /// 14,240 bytes larger than the guard. The labels are carried beside the
    /// numbers precisely so they can understate.
    @Test func everyStatedCapUnderstatesTheCapItExplains() {
        for mime in Self.allStageableMimeTypes {
            guard case .refusedAbove(let bytes, let label) =
                    StageableTypeCatalog.sizePolicy(forMimeType: mime) else { continue }
            let stated = statedBytes(label)
            #expect(stated > 0, "\(mime): the cap label \"\(label)\" states no number at all")
            #expect(stated <= bytes,
                    "\(mime): the refusal announces \(label) (\(stated) bytes) but the guard enforces \(bytes)")
        }
    }

    /// **431-A, the image arm — measured against the app, not asserted.** An
    /// oversized image is NOT an over-cap refusal: `PendingAttachment.file(at:)`
    /// downscales it to `imageMaxPixelDimension` and steps JPEG quality down
    /// until it fits. So the extension must accept it, and a per-type byte cap
    /// on images would refuse files the app handles perfectly.
    @Test func anOversizedImageIsReEncodedRatherThanRefused() throws {
        let jpeg = try Self.noisyJPEG()
        #expect(jpeg.count > PendingAttachment.maxFileSize,
                "precondition: the fixture must exceed the verbatim cap (got \(jpeg.count))")
        #expect(jpeg.count < Self.shareBudget,
                "precondition: the fixture must fit the share budget")

        #expect(StageableTypeCatalog.acceptance(
            fileName: "big.jpg", byteCount: jpeg.count, remainingBytes: Self.shareBudget) == .accepted,
                "the share sheet refused an image the app would have staged")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareCapPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("big.jpg")
        try jpeg.write(to: url)

        let staged = try #require(PendingAttachment.file(at: url),
                                  "the app refused an image it is supposed to re-encode")
        #expect(staged.kind == .image)
        #expect(staged.data.count <= PendingAttachment.maxFileSize,
                "re-encoding must land under the verbatim cap")
    }

    // MARK: - 431-B — refused BEFORE Send, with a reason

    /// **431-B, PDF boundary.** Cap accepted; cap+1 refused, naming the file
    /// and the cap.
    @Test func aPDFIsAcceptedAtItsCapAndRefusedOneByteAbove() throws {
        let cap = PendingAttachment.maxPDFFileSize
        #expect(StageableTypeCatalog.acceptance(
            fileName: "scan.pdf", byteCount: cap, remainingBytes: Self.shareBudget) == .accepted,
                "a PDF exactly at the cap is one the app stages")

        let refusal = try #require(refusalMessage("scan.pdf", cap + 1),
                                   "a PDF one byte over its cap was ACCEPTED")
        #expect(refusal.contains("scan.pdf"), "the refusal must name the file: \(refusal)")
        #expect(refusal.contains(StageableTypeCatalog.maxPDFLabel),
                "the refusal must name the cap: \(refusal)")
    }

    /// **431-B, non-PDF boundary.** The 58× window: this is the row the old
    /// extension could never fail, because it had no per-type check at all.
    @Test func aTextFileIsAcceptedAtItsCapAndRefusedOneByteAbove() throws {
        let cap = PendingAttachment.maxFileSize
        #expect(StageableTypeCatalog.acceptance(
            fileName: "report.md", byteCount: cap, remainingBytes: Self.shareBudget) == .accepted)

        let refusal = try #require(refusalMessage("report.md", cap + 1),
                                   "a non-PDF one byte over its cap was ACCEPTED")
        #expect(refusal.contains("report.md"), "the refusal must name the file: \(refusal)")
        #expect(refusal.contains(StageableTypeCatalog.maxVerbatimLabel),
                "the refusal must name the cap: \(refusal)")
        #expect(refusal.contains(SharedInboxStore.byteLabel(cap + 1)),
                "the refusal must state the file's own size: \(refusal)")
    }

    /// **431-B, the aggregate refusal keeps its own reason.** A share can be
    /// under every per-type cap and still overflow one envelope; that is a
    /// different sentence, and reusing the per-type one would state a limit
    /// that did not apply.
    @Test func theAggregateRefusalKeepsItsOwnReason() throws {
        let refusal = try #require(refusalMessage("scan.pdf", 5_000_000, remainingBytes: 1_000_000),
                                   "a file past the remaining share budget was ACCEPTED")
        #expect(refusal.contains("one share can carry up to"), "\(refusal)")
        #expect(refusal.contains(SharedInboxStore.sizeLimitLabel), "\(refusal)")
        #expect(!refusal.contains(StageableTypeCatalog.maxPDFLabel),
                "the aggregate refusal must not quote the per-type cap: \(refusal)")
    }

    /// **431-B, the more specific reason wins.** A 400 KB `.md` with 100 KB of
    /// budget left is refused by BOTH rules; "one share can carry up to 20 MB"
    /// cannot explain it, so the per-type cap is checked first.
    @Test func thePerTypeCapIsTheStatedReasonWhenBothWouldRefuse() throws {
        let refusal = try #require(refusalMessage("report.md", 400_000, remainingBytes: 100_000),
                                   "a file over both limits was ACCEPTED")
        #expect(refusal.contains(StageableTypeCatalog.maxVerbatimLabel), "\(refusal)")
        #expect(!refusal.contains("one share can carry"), "\(refusal)")
    }

    /// **431-B, type before size.** An unstageable type is refused on type
    /// even when it is tiny.
    @Test func anUnsupportedTypeIsRefusedByTypeRegardlessOfSize() throws {
        let refusal = try #require(refusalMessage("clip.mov", 64),
                                   "an unstageable type was ACCEPTED")
        #expect(refusal.contains("clip.mov"), "\(refusal)")
        #expect(refusal == ShareRefusal.unsupportedType(fileName: "clip.mov"), "\(refusal)")
    }

    /// Every refusal the pipeline can speak names its file — the drain's
    /// banner has no separate name line to lean on, so the message must carry
    /// the name itself.
    @Test func everyRefusalMessageNamesItsFile() {
        let name = "quarterly report.docx"
        let messages = [
            ShareRefusal.unsupportedType(fileName: name),
            ShareRefusal.audioOrVideo(fileName: name),
            ShareRefusal.unreadable(fileName: name),
            ShareRefusal.couldNotStage(fileName: name),
            ShareRefusal.notAPDF(fileName: name),
            ShareRefusal.overTypeCap(fileName: name, byteCount: 1_200_000, capLabel: "350 KB"),
            ShareRefusal.overShareBudget(fileName: name, byteCount: 21_000_000),
        ]
        for message in messages {
            #expect(message.contains(name), "a refusal that does not name its file: \(message)")
        }
    }

    /// **The mislabelled-PDF sentence says what happened** (#431 fix round 1,
    /// the review's minor 4). `couldNotStage` claims Talaria "couldn't read the
    /// file", which is false for a `.pdf` whose bytes read perfectly and simply
    /// are not a PDF — the difference between "try again" and "that file is
    /// mislabelled".
    @Test func theMislabelledPDFRefusalDoesNotClaimTheFileWasUnreadable() {
        let message = ShareInboxDrainer.stagingRefusalMessage(
            fileName: "report.pdf", data: Data("this is not a pdf at all".utf8))
        #expect(message == ShareRefusal.notAPDF(fileName: "report.pdf"), "\(message)")
        #expect(!message.contains("couldn’t read"), "\(message)")

        // The genuinely-unreadable arm keeps the other sentence: an image whose
        // bytes UIImage cannot decode really was unreadable.
        let undecodable = ShareInboxDrainer.stagingRefusalMessage(
            fileName: "photo.jpg", data: Data(repeating: 0xAB, count: 64))
        #expect(undecodable == ShareRefusal.couldNotStage(fileName: "photo.jpg"), "\(undecodable)")
    }

    // MARK: - The PDF sniff, measured on what it ACCEPTS

    /// **The review's Important 1.** `looksLikePDF` shipped with only a
    /// negative control — one corrupt-PDF row — so nothing measured that it
    /// does not OVER-refuse. A gate wrong in that direction kills every PDF
    /// attachment in the app, on both the share and the picker paths, and the
    /// suite would have stayed green: no test anywhere staged a genuine PDF
    /// through `PendingAttachment.file(at:)`.
    ///
    /// (`AttachmentInliningTests.rawPDF` looks like one and is not — it builds
    /// the attachment through the memberwise initializer with 128 `%` bytes and
    /// never touches `file(at:)`, so this gate cannot see it. It needs no fix.)
    @Test func aGenuinePDFStagesThroughTheStagingPath() throws {
        let pdf = Self.minimalPDF()
        #expect(pdf.starts(with: Data("%PDF-".utf8)), "precondition: the fixture is a real PDF")
        #expect(PendingAttachment.looksLikePDF(pdf))

        let attachment = try stage(pdf, as: "report.pdf")
        let staged = try #require(attachment, "the format gate refused a genuine PDF")
        #expect(staged.kind == .file)
        #expect(staged.mimeType == StageableTypeCatalog.pdfMimeType)
        #expect(staged.data == pdf, "the staged bytes must be the file's own")
    }

    /// The spec allows leading junk before the header — real readers scan for
    /// `%PDF-` inside the first kilobyte rather than demanding it at byte 0,
    /// and so does the gate. A producer that emits a BOM, a shebang, or an
    /// HTTP preamble must not have its file refused.
    @Test func aPDFBehindLeadingJunkStillStages() throws {
        let junk = Data(repeating: 0x20, count: 500)
        let pdf = junk + Self.minimalPDF()
        #expect(PendingAttachment.looksLikePDF(pdf))

        let attachment = try stage(pdf, as: "report.pdf")
        let staged = try #require(attachment, "a PDF behind 500 bytes of leading junk was refused")
        #expect(staged.data.count == pdf.count)
    }

    /// …and the search is BOUNDED, which is the other half of the same rule:
    /// a marker starting at byte 1024 is outside the window the spec allows,
    /// so the gate refuses rather than scanning an arbitrary file for a string.
    @Test func aPDFMarkerPastTheFirstKilobyteIsRefused() throws {
        let pdf = Data(repeating: 0x20, count: 1024) + Self.minimalPDF()
        #expect(!PendingAttachment.looksLikePDF(pdf))
        let refused = try stage(pdf, as: "report.pdf")
        #expect(refused == nil, "a marker outside the first kilobyte was accepted")
    }

    /// The negative control the lane already had, now standing beside the
    /// positives it needs to mean anything.
    @Test func aFileNamedPDFWhoseBytesAreNotAPDFIsRefused() throws {
        let refused = try stage(Data("this is not a pdf at all".utf8), as: "report.pdf")
        #expect(refused == nil, "a .pdf whose bytes are not a PDF was staged")
    }

    /// Write `data` under `fileName` and hand it to the real staging path.
    private func stage(_ data: Data, as fileName: String) throws -> PendingAttachment? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareCapPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(fileName)
        try data.write(to: url)
        return PendingAttachment.file(at: url)
    }

    /// A real one-page PDF, rendered by PDFKit's own writer rather than
    /// hand-assembled — a hand-written header would prove only that the gate
    /// matches the string this test wrote.
    private static func minimalPDF() -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x: 10, y: 10, width: 80, height: 20))
        }
    }

    // MARK: - The two composed edges the unit rows cannot see

    /// The extension's own gate and the chat screen's banner are the two lines
    /// no unit can reach — `TalariaShare/` has no test target and `ChatScreen`
    /// is a View. Both are witnessed in source instead, the shape
    /// `RunsTransportSwitchTests` uses.
    @Test func theSheetAndTheChatScreenReachTheNewSurfaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root

        let sheet = try String(
            contentsOf: root.appendingPathComponent("TalariaShare/ShareViewController.swift"),
            encoding: .utf8)
        #expect(sheet.contains("StageableTypeCatalog.acceptance("),
                "the share sheet does not consult the shared acceptance decision")
        #expect(!sheet.contains("data.count <= remainingBytes"),
                "the share sheet still makes its own size decision")

        let screen = try String(
            contentsOf: root.appendingPathComponent("Talaria/Features/Chat/ChatScreen.swift"),
            encoding: .utf8)
        #expect(screen.contains("chatStore.shareStagingFailureMessage"),
                "the chat screen never reads the drain's failures")
        #expect(screen.contains("shareStagingFailureBanner("),
                "the chat screen has no banner to render them in")
        // #431 fix round 1: the banner's PLACEMENT is what the review found
        // wrong, and a witness that only sees the two lines above cannot see
        // it. This one pins that the screen renders whatever the pure
        // `BannerStack.resolve` returns — the function the stacking rows in
        // `ShareInboxDrainTests` assert against. Without it, resolve could be
        // fixed, tested, and never consulted by the view.
        #expect(screen.contains("BannerStack.resolve("),
                "the chat screen does not consult the resolved banner stack")
    }

    // MARK: Image fixture

    /// A JPEG large enough to exceed the 350 KB verbatim cap. Flat colour
    /// compresses to a few KB, so the fixture is deterministic NOISE — seeded,
    /// so the byte count does not wander between runs.
    private static func noisyJPEG() throws -> Data {
        var seed: UInt64 = 0x5DEE_CE66
        func nextUnit() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((seed >> 33) % 1_000) / 1_000
        }
        let side = 1_200
        let cell = 6
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            for y in stride(from: 0, to: side, by: cell) {
                for x in stride(from: 0, to: side, by: cell) {
                    UIColor(red: nextUnit(), green: nextUnit(), blue: nextUnit(), alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                }
            }
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }
}
