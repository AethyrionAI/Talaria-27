import Foundation
import Testing
@testable import Talaria

/// Agent-file attachments: the additive `MessageAttachment` contract and the
/// `write_file` parser branch.
///
/// **#375 (2026-08-19) removed this file's other half.** It used to cover #21
/// Tier 2 — the "TAP TO DOWNLOAD" chip, the MobileDL announcement scan,
/// `RelayAPIClient.downloadFile`, and ChatStore's tap→download→stage flow —
/// all of which fetched over the relay. The relay is retired on both hosts
/// (#346, #375) and Owen ruled the download unneeded, so the app no longer
/// mints a chip it cannot honour and those tests describe code that is gone.
///
/// What survives is deliberate: the Codable contract still has to decode
/// attachments PERSISTED by earlier builds, including Tier 2 rows carrying a
/// `remotePath` and no local bytes.
struct AgentFileFetchTests {

    // MARK: - Model: additive Codable contract

    /// A legacy Tier 2 row — `remotePath` set, no local bytes. Built by hand
    /// rather than by a factory: the factory that used to mint these is gone,
    /// and the rows it wrote are still sitting in persisted conversations.
    private func legacyFetchableAttachment(
        name: String = "probe-t21.pdf",
        remotePath: String = "probe-t21.pdf",
        profileID: UUID? = nil
    ) -> MessageAttachment {
        MessageAttachment(
            kind: "file",
            fileName: name,
            mimeType: MessageAttachment.inferredMimeType(forFileName: name),
            thumbnailBase64: nil,
            localStoragePath: nil,
            remotePath: remotePath,
            remoteProfileID: profileID
        )
    }

    @Test func attachmentRoundTripsWithRemotePathAndProfile() throws {
        let profileID = UUID()
        let original = legacyFetchableAttachment(profileID: profileID)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageAttachment.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.kind == "file")
        #expect(decoded.fileName == "probe-t21.pdf")
        #expect(decoded.mimeType == "application/pdf")
        #expect(decoded.remotePath == "probe-t21.pdf")
        #expect(decoded.remoteProfileID == profileID)
        #expect(decoded.localStoragePath == nil)
    }

    @Test func preTier2CacheFixtureStillDecodes() throws {
        // A persisted attachment from before #21 Tier 2 — no remotePath /
        // remoteProfileID keys. The additive contract: it must decode with
        // nils, not throw.
        let fixture = Data("""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"file",\
        "fileName":"notes.md","mimeType":"text/markdown",\
        "localStoragePath":"/tmp/staged/notes.md"}
        """.utf8)
        let decoded = try JSONDecoder().decode(MessageAttachment.self, from: fixture)
        #expect(decoded.fileName == "notes.md")
        #expect(decoded.localStoragePath == "/tmp/staged/notes.md")
        #expect(decoded.remotePath == nil)
        #expect(decoded.remoteProfileID == nil)
        #expect(decoded.voiceMemoAudioPath == nil)
    }

    @Test func stagedCopyKeepsIdentityAndFetchPointer() {
        var attachment = legacyFetchableAttachment(
            name: "report.pdf", remotePath: "reports/report.pdf", profileID: UUID()
        )
        // #289: seed a non-nil anchorOffset. A nil-vs-nil comparison passes
        // against the UNFIXED function and proves nothing about the drop this
        // test exists to catch.
        attachment.anchorOffset = 42

        let staged = attachment.staged(atLocalPath: "/tmp/staged/report.pdf")

        // The ONLY property staging may change is `localStoragePath`. Compare
        // the whole struct, not a field list: `staged()` rebuilds field by
        // field, which is the #276 silent-drop shape — every property has a
        // default, so an omission compiles and reads as "correctly nil".
        let expected = MessageAttachment(
            id: attachment.id,
            kind: attachment.kind,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            thumbnailBase64: attachment.thumbnailBase64,
            localStoragePath: "/tmp/staged/report.pdf",
            voiceMemoAudioPath: attachment.voiceMemoAudioPath,
            remotePath: attachment.remotePath,
            remoteProfileID: attachment.remoteProfileID,
            anchorOffset: attachment.anchorOffset
        )
        #expect(staged == expected)
        // Named separately so a regression reads as "the anchor was dropped"
        // instead of two opaque struct descriptions (#289's actual defect).
        #expect(staged.anchorOffset == 42)

        // Bar 289-B: the property COUNT is what makes the next field added to
        // `MessageAttachment` fail loudly here. Raise this number only in the
        // same commit that threads the new property through `staged()`.
        #expect(Mirror(reflecting: staged).children.count == 10)
    }

    // MARK: - Parser: content present vs absent

    private func removeStagedFile(_ attachment: MessageAttachment) {
        if let path = attachment.localStoragePath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @Test func contentPresentStaysTier1Staged() throws {
        // ##-delimited: the JSON contains `"#` (in "# Report"), which would
        // close a plain #"…"# raw literal mid-string.
        let payload = ##"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\out.md","content":"# Report"}}"##
        let attachment = try #require(SessionsHermesClient.parseWrittenFile(payload, profileID: UUID()))
        defer { removeStagedFile(attachment) }
        #expect(attachment.localStoragePath != nil)
        #expect(attachment.remotePath == nil)
        #expect(attachment.fileName == "out.md")
    }

    /// #375/#21: a write whose args carry no CONTENT used to become a Tier 2
    /// "TAP TO DOWNLOAD" chip fetched over the relay. The relay is retired on
    /// both hosts and Owen ruled the download unneeded (2026-08-19), so the
    /// app must mint NOTHING here rather than a chip it cannot honour —
    /// inside the old MobileDL whitelist or outside it, both are nil now.
    ///
    /// Mutation that must turn this RED: restore the `.fetchableAgentFile`
    /// fallthrough in `parseWrittenFile`.
    @Test func contentAbsentProducesNoAttachmentAtAll() {
        let profileID = UUID()
        let inWhitelist = #"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\MobileDL\\report.pdf"}}"#
        #expect(SessionsHermesClient.parseWrittenFile(inWhitelist, profileID: profileID) == nil)
        let drifted = #"{"tool_name":"create_file","input":{"file_path":"~/Hermes/agent-work/MobileDL/data.csv"}}"#
        #expect(SessionsHermesClient.parseWrittenFile(drifted, profileID: nil) == nil)
        let outsideWhitelist = #"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\secret\\report.pdf"}}"#
        #expect(SessionsHermesClient.parseWrittenFile(outsideWhitelist, profileID: profileID) == nil)
    }

    @Test func nonWriteToolsNeverParse() {
        let payload = #"{"tool_name":"read_file","args":{"path":"O:\\Hermes\\MobileDL\\report.pdf"}}"#
        #expect(SessionsHermesClient.parseWrittenFile(payload, profileID: nil) == nil)
    }
}
