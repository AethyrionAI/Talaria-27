import Foundation
import Testing
@testable import Talaria

/// #21 Tier 2 — app-side agent-file fetch: the additive `MessageAttachment`
/// contract, the content-present/absent parser branch, the MobileDL
/// announcement scan (the probe-mandated trigger: binaries never ride the
/// SSE stream, only their paths do), `RelayAPIClient.downloadFile` request
/// shaping + status mapping, and ChatStore's tap→download→stage flow.
struct AgentFileFetchTests {

    // MARK: - Model: additive Codable contract

    @Test func attachmentRoundTripsWithRemotePathAndProfile() throws {
        let profileID = UUID()
        let original = MessageAttachment.fetchableAgentFile(
            name: "probe-t21.pdf",
            remotePath: "probe-t21.pdf",
            profileID: profileID
        )
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
        let attachment = MessageAttachment.fetchableAgentFile(
            name: "report.pdf", remotePath: "reports/report.pdf", profileID: UUID()
        )
        let staged = attachment.staged(atLocalPath: "/tmp/staged/report.pdf")
        #expect(staged.id == attachment.id)
        #expect(staged.localStoragePath == "/tmp/staged/report.pdf")
        #expect(staged.remotePath == attachment.remotePath)
        #expect(staged.remoteProfileID == attachment.remoteProfileID)
        #expect(staged.fileName == attachment.fileName)
        #expect(staged.mimeType == attachment.mimeType)
    }

    @Test func stageFetchedAgentFileMovesTheDownload() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("t21-download-\(UUID().uuidString)")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: temp) // "%PDF"
        let stagedPath = try #require(
            MessageAttachment.stageFetchedAgentFile(from: temp, preferredFileName: "probe.pdf")
        )
        defer { try? FileManager.default.removeItem(atPath: stagedPath) }
        #expect(FileManager.default.contents(atPath: stagedPath) == Data([0x25, 0x50, 0x44, 0x46]))
        // Moved, not copied — the temp file is gone.
        #expect(!FileManager.default.fileExists(atPath: temp.path))
        #expect(stagedPath.hasSuffix("probe.pdf"))
    }

    // MARK: - Parser: content present vs absent

    private func removeStagedFile(_ attachment: MessageAttachment) {
        if let path = attachment.localStoragePath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @Test func contentPresentStaysTier1Staged() throws {
        let payload = #"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\out.md","content":"# Report"}}"#
        let attachment = try #require(SessionsHermesClient.parseWrittenFile(payload, profileID: UUID()))
        defer { removeStagedFile(attachment) }
        // Staged now, nothing to fetch later — no regression on the Tier 1 path.
        #expect(attachment.localStoragePath != nil)
        #expect(attachment.remotePath == nil)
        #expect(attachment.fileName == "out.md")
    }

    @Test func contentAbsentInsideWhitelistBecomesFetchable() throws {
        let profileID = UUID()
        let payload = #"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\MobileDL\\report.pdf"}}"#
        let attachment = try #require(SessionsHermesClient.parseWrittenFile(payload, profileID: profileID))
        #expect(attachment.localStoragePath == nil)
        #expect(attachment.remotePath == "report.pdf")
        #expect(attachment.remoteProfileID == profileID)
        #expect(attachment.fileName == "report.pdf")
        #expect(attachment.mimeType == "application/pdf")
    }

    @Test func contentAbsentToleratesArgKeyDrift() throws {
        let payload = #"{"tool_name":"create_file","input":{"file_path":"~/Hermes/agent-work/MobileDL/data.csv"}}"#
        let attachment = try #require(SessionsHermesClient.parseWrittenFile(payload, profileID: nil))
        #expect(attachment.remotePath == "data.csv")
        #expect(attachment.remoteProfileID == nil)
    }

    @Test func contentAbsentOutsideWhitelistIsDropped() {
        // The relay 404s anything outside AGENT_FILES_DIR by design — the app
        // never sends arbitrary host paths, so no bubble at all.
        let payload = #"{"tool_name":"write_file","args":{"path":"O:\\Hermes\\secret\\report.pdf"}}"#
        #expect(SessionsHermesClient.parseWrittenFile(payload, profileID: UUID()) == nil)
    }

    @Test func nonWriteToolsNeverParse() {
        let payload = #"{"tool_name":"read_file","args":{"path":"O:\\Hermes\\MobileDL\\report.pdf"}}"#
        #expect(SessionsHermesClient.parseWrittenFile(payload, profileID: nil) == nil)
    }

    // MARK: - Announcement scan: path extraction

    @Test func extractsWindowsPathFromProse() {
        let text = "Done! Saved to O:\\Hermes\\MobileDL\\probe-t21.pdf."
        #expect(SessionsHermesClient.agentFilesRelativePaths(in: text) == ["probe-t21.pdf"])
    }

    @Test func extractsPOSIXPathWithSubdirectory() {
        let text = "The file lives at /Users/owen/Hermes/agent-work/MobileDL/reports/q3.csv now."
        #expect(SessionsHermesClient.agentFilesRelativePaths(in: text) == ["reports/q3.csv"])
    }

    @Test func extractsBacktickedPathCaseInsensitively() {
        let text = "Saved as `mobiledl/Summary.MD` for you."
        #expect(SessionsHermesClient.agentFilesRelativePaths(in: text) == ["Summary.MD"])
    }

    @Test func bareDirectoryMentionsProduceNothing() {
        #expect(SessionsHermesClient.agentFilesRelativePaths(in: "I checked your MobileDL folder.").isEmpty)
        // A segment without a file-like extension is a directory, not a file.
        #expect(SessionsHermesClient.agentFilesRelativePaths(in: "Listed MobileDL/archive today").isEmpty)
        #expect(SessionsHermesClient.agentFilesRelativePaths(in: "No files here at all.").isEmpty)
    }

    @Test func dedupesRepeatedMentionsPreservingOrder() {
        let text = """
        Wrote MobileDL/a.pdf and MobileDL/b.txt, then verified MobileDL/a.pdf again.
        """
        #expect(SessionsHermesClient.agentFilesRelativePaths(in: text) == ["a.pdf", "b.txt"])
    }

    @Test func harvestsPathsFromArbitraryToolPayloads() {
        // The probe's real shape: the binary is produced by `terminal`, the
        // only client-visible signal is the path inside the command string.
        let payload = #"""
        {"tool_name":"terminal","args":{"command":"python make_pdf.py --out O:\\Hermes\\MobileDL\\probe-t21.pdf"},"preview":"python make_pdf.py"}
        """#
        #expect(SessionsHermesClient.announcedAgentFilePaths(fromToolPayload: payload) == ["probe-t21.pdf"])
    }

    @Test func payloadWithoutAgentFilesDirYieldsNothing() {
        let payload = #"{"tool_name":"terminal","args":{"command":"ls -la /tmp"}}"#
        #expect(SessionsHermesClient.announcedAgentFilePaths(fromToolPayload: payload).isEmpty)
    }

    // MARK: - Announcement scan: attachment assembly

    @Test func fetchablesDedupeAgainstTier1Reconstructions() throws {
        // The agent write_file'd summary.md (Tier 1 staged it) AND the prose
        // mentions MobileDL/summary.md — the staged copy wins, no double bubble.
        let tier1 = try #require(
            MessageAttachment.agentFile(remotePath: "O:\\Hermes\\MobileDL\\summary.md", content: "# Sum")
        )
        defer { removeStagedFile(tier1) }
        // The Windows-separator fix: the display name is the path TAIL, not
        // the whole backslashed path (NSString path methods only split "/").
        #expect(tier1.fileName == "summary.md")
        let fetchables = SessionsHermesClient.fetchableAgentFileAttachments(
            announcedPaths: ["summary.md", "extra.pdf"],
            existing: [tier1],
            profileID: nil
        )
        #expect(fetchables.count == 1)
        #expect(fetchables.first?.fileName == "extra.pdf")
    }

    @Test func fetchablesStampTheBirthProfile() {
        let profileID = UUID()
        let fetchables = SessionsHermesClient.fetchableAgentFileAttachments(
            announcedPaths: ["report.pdf", "REPORT.PDF"],
            existing: [],
            profileID: profileID
        )
        // Case-insensitive dedupe: one bubble, stamped with the hop's profile.
        #expect(fetchables.count == 1)
        #expect(fetchables.first?.remoteProfileID == profileID)
        #expect(fetchables.first?.remotePath == "report.pdf")
    }

    // MARK: - RelayAPIClient.downloadFile

    private final class DownloadStubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private final class CapturedRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        func record(_ value: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            request = value
        }
        var value: URLRequest? {
            lock.lock()
            defer { lock.unlock() }
            return request
        }
    }

    @MainActor
    private func makeDownloadClient() -> RelayAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadStubURLProtocol.self]
        return RelayAPIClient(
            baseURLProvider: { "http://relay.example:8000/v1" },
            session: URLSession(configuration: configuration)
        )
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    @Test @MainActor
    func downloadShapesTheRouteRequest() async throws {
        let client = makeDownloadClient()
        let captured = CapturedRequest()
        DownloadStubURLProtocol.requestHandler = { request in
            captured.record(request)
            return (Self.response(for: request, status: 200), Data("pdf-bytes".utf8))
        }
        defer { DownloadStubURLProtocol.requestHandler = nil }

        let fileURL = try await client.downloadFile(
            path: "reports/July 2026+final.pdf",
            accessToken: "device-token"
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let request = try #require(captured.value)
        let url = try #require(request.url)
        #expect(url.path == "/v1/device/files")
        // Strict unreserved-set encoding: `/`, space, and `+` must never
        // survive raw in the query value.
        #expect(url.query == "path=reports%2FJuly%202026%2Bfinal.pdf")
        // Device bearer rides the HEADER — never the URL.
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token")
        #expect(!url.absoluteString.contains("device-token"))
        // And the bytes actually landed in the returned temp file.
        #expect(FileManager.default.contents(atPath: fileURL.path) == Data("pdf-bytes".utf8))
    }

    @Test @MainActor
    func downloadMaps401ToUnauthorized() async {
        let client = makeDownloadClient()
        DownloadStubURLProtocol.requestHandler = { request in
            (Self.response(for: request, status: 401), Data())
        }
        defer { DownloadStubURLProtocol.requestHandler = nil }
        await #expect(throws: RelayAPIClient.FileDownloadError.unauthorized) {
            _ = try await client.downloadFile(path: "report.pdf", accessToken: "stale-token")
        }
    }

    @Test @MainActor
    func downloadMaps404ToNotFound() async {
        let client = makeDownloadClient()
        DownloadStubURLProtocol.requestHandler = { request in
            (Self.response(for: request, status: 404), Data())
        }
        defer { DownloadStubURLProtocol.requestHandler = nil }
        await #expect(throws: RelayAPIClient.FileDownloadError.notFound) {
            _ = try await client.downloadFile(path: "gone.pdf", accessToken: "device-token")
        }
    }

    @Test @MainActor
    func downloadSurfacesOtherStatusesAsFailed() async {
        let client = makeDownloadClient()
        DownloadStubURLProtocol.requestHandler = { request in
            (Self.response(for: request, status: 500), Data())
        }
        defer { DownloadStubURLProtocol.requestHandler = nil }
        await #expect(throws: RelayAPIClient.FileDownloadError.failed("Relay file download failed with status 500.")) {
            _ = try await client.downloadFile(path: "report.pdf", accessToken: "device-token")
        }
    }

    @Test @MainActor
    func downloadRefusesAnEmptyTokenWithoutTouchingTheNetwork() async {
        let client = makeDownloadClient()
        DownloadStubURLProtocol.requestHandler = { request in
            Issue.record("An unauthenticated request must never leave the client")
            return (Self.response(for: request, status: 200), Data())
        }
        defer { DownloadStubURLProtocol.requestHandler = nil }
        await #expect(throws: RelayAPIClient.FileDownloadError.unauthorized) {
            _ = try await client.downloadFile(path: "report.pdf", accessToken: "")
        }
    }

    // MARK: - ChatStore: tap → download → stage

    @MainActor
    private final class InertClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        func connect() async {}
        func disconnect() async {}
        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "", status: .delivered)
        }
        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }
        func loadConversation() async -> Conversation { Conversation(title: "Hermes") }
        func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }
    }

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "agent-file-fetch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    @MainActor
    private func makeStoreWithFetchable(profileID: UUID?) -> (ChatStore, Message, MessageAttachment) {
        let attachment = MessageAttachment.fetchableAgentFile(
            name: "probe.pdf", remotePath: "probe.pdf", profileID: profileID
        )
        let message = Message(sender: .hermes, content: "Saved it.", status: .delivered, attachments: [attachment])
        let store = ChatStore(hermesClient: InertClient(), persistence: makePersistence())
        store.conversation = Conversation(title: "Test", messages: [message])
        return (store, message, attachment)
    }

    @Test @MainActor
    func fetchStagesTheDownloadAndFlipsTheAttachment() async throws {
        let profileID = UUID()
        let (store, message, attachment) = makeStoreWithFetchable(profileID: profileID)

        let requested = CapturedRequestArgs()
        store.agentFileDownloader = { requestedProfileID, remotePath in
            requested.record(profileID: requestedProfileID, path: remotePath)
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("t21-fetch-\(UUID().uuidString)")
            try Data("real pdf bytes".utf8).write(to: temp)
            return temp
        }

        await store.fetchAgentFile(attachment, in: message)

        // The downloader was handed the BIRTH profile and the route-form path.
        #expect(requested.profileID == profileID)
        #expect(requested.path == "probe.pdf")

        // The attachment flipped to staged in place — same identity.
        let updated = try #require(store.conversation?.messages.first?.attachments.first)
        #expect(updated.id == attachment.id)
        let stagedPath = try #require(updated.localStoragePath)
        defer { try? FileManager.default.removeItem(atPath: stagedPath) }
        #expect(FileManager.default.contents(atPath: stagedPath) == Data("real pdf bytes".utf8))
        // Idle again (no state row), and the flip was persisted.
        #expect(store.agentFileDownloads[attachment.id] == nil)
        #expect(store.persistence.loadConversationCache()?.messages.first?.attachments.first?.localStoragePath == stagedPath)
    }

    @Test @MainActor
    func fetchFailureSurfacesHonestStateAndKeepsTheAttachmentFetchable() async throws {
        let (store, message, attachment) = makeStoreWithFetchable(profileID: nil)
        store.agentFileDownloader = { _, _ in throw RelayAPIClient.FileDownloadError.notFound }

        await store.fetchAgentFile(attachment, in: message)

        guard case .failed(let reason)? = store.agentFileDownloads[attachment.id] else {
            Issue.record("Expected a failed download state")
            return
        }
        #expect(reason.contains("isn't available"))
        // Still fetchable — the tap can retry.
        let unchanged = try #require(store.conversation?.messages.first?.attachments.first)
        #expect(unchanged.localStoragePath == nil)
        #expect(unchanged.remotePath == "probe.pdf")
    }

    @Test @MainActor
    func fetchWithoutAWiredDownloaderFailsHonestly() async {
        let (store, message, attachment) = makeStoreWithFetchable(profileID: nil)
        await store.fetchAgentFile(attachment, in: message)
        guard case .failed? = store.agentFileDownloads[attachment.id] else {
            Issue.record("Expected a failed download state when no downloader is wired")
            return
        }
    }

    @Test @MainActor
    func fetchIgnoresAlreadyStagedAttachments() async {
        let (store, message, _) = makeStoreWithFetchable(profileID: nil)
        let staged = MessageAttachment(
            kind: "file", fileName: "done.pdf", mimeType: "application/pdf",
            localStoragePath: "/tmp/staged/done.pdf", remotePath: "done.pdf"
        )
        store.agentFileDownloader = { _, _ in
            Issue.record("A staged attachment must never re-download")
            throw RelayAPIClient.FileDownloadError.notFound
        }
        await store.fetchAgentFile(staged, in: message)
        #expect(store.agentFileDownloads[staged.id] == nil)
    }

    private final class CapturedRequestArgs: @unchecked Sendable {
        private let lock = NSLock()
        private var storedProfileID: UUID??
        private var storedPath: String?
        func record(profileID: UUID?, path: String) {
            lock.lock()
            defer { lock.unlock() }
            storedProfileID = profileID
            storedPath = path
        }
        var profileID: UUID? {
            lock.lock()
            defer { lock.unlock() }
            return storedProfileID ?? nil
        }
        var path: String? {
            lock.lock()
            defer { lock.unlock() }
            return storedPath
        }
    }

    // MARK: - Failure-message mapping

    @Test func failureMessagesCoverTheAcceptanceTriad() {
        #expect(ChatStore.agentFileFailureMessage(for: RelayAPIClient.FileDownloadError.unauthorized)
            .contains("authorization"))
        #expect(ChatStore.agentFileFailureMessage(for: RelayAPIClient.FileDownloadError.notFound)
            .contains("isn't available"))
        #expect(ChatStore.agentFileFailureMessage(for: URLError(.notConnectedToInternet))
            .contains("unreachable"))
    }
}
