import Foundation
import FoundationModels
import UIKit
import Vision

// The "FM built-ins" row of the #28 belt. Verified against the SDK docs
// (2026-07-07): FoundationModels ships NO OCRTool / BarcodeReaderTool /
// Spotlight-RAG tool types — so these are Talaria's own implementations on
// Vision + the #17 Spotlight session cache, exposed to the model exactly
// like the rest of the belt.

// MARK: - Shared: newest image attachment in the conversation

enum ConversationImageSource {
    /// Image attachments in the conversation, newest message first and newest
    /// attachment first within a message. One walk shared by the presence
    /// check and the decode so the two can never disagree about what counts
    /// as an image (#176).
    @MainActor
    static func imageAttachments(in conversation: Conversation?) -> [MessageAttachment] {
        guard let conversation else { return [] }
        return conversation.messages.reversed().flatMap { message in
            message.attachments.reversed().filter { $0.kind == "image" }
        }
    }

    /// Whether the vision tools should be OFFERED for this turn (#176): an
    /// image already in the thread, or one riding in on the turn being
    /// composed.
    ///
    /// The `incoming` half is load-bearing. Every send path prepares the
    /// session BEFORE appending the user turn, so a check that read stored
    /// history alone would withhold OCR on the exact turn that attaches the
    /// image — the tool's whole purpose.
    ///
    /// Deliberately cheaper AND more permissive than `latestImage`: reachable
    /// bytes, no decode. A present-but-undecodable image still gets the tools
    /// offered, and they answer honestly about it. The gate must never be the
    /// reason a real image goes unread.
    @MainActor
    static func hasImage(in conversation: Conversation?, incoming: [PendingAttachment] = []) -> Bool {
        if incoming.contains(where: { $0.kind == .image }) { return true }
        return imageAttachments(in: conversation).contains { attachment in
            if attachment.thumbnailBase64 != nil { return true }
            guard let path = attachment.localStoragePath else { return false }
            return FileManager.default.fileExists(atPath: path)
        }
    }

    /// The most recent image attachment (user upload or agent output) whose
    /// bytes are still on disk. The on-device model can't see images (#26),
    /// so OCR/barcode tools are how image questions get honest answers.
    @MainActor
    static func latestImage(in conversation: Conversation?) -> (fileName: String, image: UIImage)? {
        for attachment in imageAttachments(in: conversation) {
            if let path = attachment.localStoragePath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let image = UIImage(data: data) {
                return (attachment.fileName, image)
            }
            // Fall back to the persisted thumbnail — lower fidelity, but
            // real bytes beat "no image found" for large text/QR codes.
            if let base64 = attachment.thumbnailBase64,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                return (attachment.fileName, image)
            }
        }
        return nil
    }
}

// MARK: - OCR (Vision text recognition)

struct ImageTextTool: Tool, ImageDependentTool {
    let name = "readImageText"
    // #176: the description states WHEN the tool applies, not just what it
    // does. Gating covers "no image anywhere"; this covers the other half —
    // an image from twenty turns ago keeps the tool offered, and the belt
    // was observed reaching for OCR on "Write a haiku about rain".
    let description = "Read (OCR) the text in the most recent image attached to this conversation. Use this ONLY when the user is asking what an image says or shows — never to answer a request that isn't about an image."
    let relay: ToolEventRelay
    let conversationProvider: @MainActor () -> Conversation?

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await relay.started(name)
        defer { Task { await relay.completed(name) } }

        guard let (fileName, image) = await ConversationImageSource.latestImage(in: conversationProvider()) else {
            return "There's no image attached to this conversation to read text from."
        }
        guard let cgImage = image.cgImage else {
            return "The image \"\(fileName)\" couldn't be decoded for text recognition."
        }

        // Extract Sendable [String] inside the detached task — VN observation
        // types are not Sendable and must not cross the concurrency boundary.
        //
        // #203 (1C): bounded. Vision on a large or awkward image is the one
        // step here that can hang, and a hung TOOL is not cancellable — the
        // production stream has no turn deadline, so this is the only place
        // the wait can end.
        return await DeviceToolTimeout.run(label: name) {
            let lines: [String] = await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            }.value
            guard !lines.isEmpty else {
                return "No readable text was found in \"\(fileName)\"."
            }
            return "Text recognized in \"\(fileName)\":\n" + lines.joined(separator: "\n")
        }
    }
}

// MARK: - Barcode / QR (Vision)

struct BarcodeReaderTool: Tool, ImageDependentTool {
    let name = "readBarcode"
    let description = "Scan the most recent image attached to this conversation for barcodes or QR codes and return their contents. Use this ONLY when the user is asking about a barcode or QR code in an image."
    let relay: ToolEventRelay
    let conversationProvider: @MainActor () -> Conversation?

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await relay.started(name)
        defer { Task { await relay.completed(name) } }

        guard let (fileName, image) = await ConversationImageSource.latestImage(in: conversationProvider()) else {
            return "There's no image attached to this conversation to scan."
        }
        guard let cgImage = image.cgImage else {
            return "The image \"\(fileName)\" couldn't be decoded for scanning."
        }

        // Extract Sendable [String] inside the detached task — VN observation
        // types are not Sendable and must not cross the concurrency boundary.
        let found: [String] = await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
            return (request.results ?? []).compactMap { observation -> String? in
                guard let payload = observation.payloadStringValue else { return nil }
                return "\(observation.symbology.rawValue): \(payload)"
            }
        }.value
        guard !found.isEmpty else {
            return "No barcode or QR code was found in \"\(fileName)\"."
        }
        return "Codes found in \"\(fileName)\":\n" + found.joined(separator: "\n")
    }
}

// MARK: - Per-tool timeout (#200Y)

/// The battery's 35-second guillotine calls `respondTask.cancel()`, and Swift
/// cancellation is COOPERATIVE — a tool blocked inside its own `call()` never
/// observes it. Measured twice: #200V's excluded TIMEOUT (six
/// `searchConversations` calls on one query) and #200W's `armed/haiku/t5`, which
/// called `searchConversations` and emitted nothing for 2.5+ minutes.
///
/// So the timeout belongs at the TOOL, where the blocking happens.
///
/// **Honest about what this can and cannot do:** it stops the tool WAITING on a
/// wedged operation; it cannot kill one. A blocked call is left running and its
/// result discarded. That is the correct trade — the model gets a usable answer
/// and the run continues, instead of a wedge that outlives the guillotine.
enum DeviceToolTimeout {
    /// Generous enough that a slow-but-working device search still returns,
    /// tight enough that a wedge cannot outlive the generation guillotine.
    static let defaultSeconds: Double = 12

    /// Thrown by `runThrowing` so a call site's existing `catch` reports the
    /// timeout in its own voice (`PlacesTool` already renders failures as
    /// "Place search failed: …").
    struct TimedOut: LocalizedError {
        let label: String
        let seconds: Double
        var errorDescription: String? {
            "the \(label) tool timed out after \(Int(seconds.rounded()))s"
        }
    }

    /// First-past-the-post gate: whichever of the two racers finishes first
    /// resumes the continuation, and the loser is discarded.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if resumed { return false }
            resumed = true
            return true
        }
    }

    static func timeoutText(label: String, seconds: Double) -> String {
        "The \(label) tool timed out after \(Int(seconds.rounded()))s and returned nothing — answer with what you already have, and do not call it again."
    }

    static func run(seconds: Double = defaultSeconds, label: String,
                    _ operation: @escaping @Sendable () async -> String) async -> String {
        let gate = Gate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            Task {
                let value = await operation()
                if gate.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.claim() {
                    continuation.resume(returning: timeoutText(label: label, seconds: seconds))
                }
            }
        }
    }

    /// Throwing variant for tools whose blocking work already reports failure
    /// through `catch` — the timeout arrives as `TimedOut` and the call site's
    /// existing error text renders it.
    static func runThrowing<T: Sendable>(
        seconds: Double = defaultSeconds, label: String,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = Gate()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            Task {
                do {
                    let value = try await operation()
                    if gate.claim() { continuation.resume(returning: value) }
                } catch {
                    if gate.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.claim() {
                    continuation.resume(throwing: TimedOut(label: label, seconds: seconds))
                }
            }
        }
    }
}

// MARK: - Local RAG over conversations (#17 Spotlight cache + live thread)

struct ConversationSearchTool: Tool {
    let name = "searchConversations"
    // #176B: kept on the standalone belt rather than withheld — in-thread
    // search reaches verbatim text that #26 condensation dropped from the
    // transcript, and past-session titles/previews are real once the (#190)
    // local store's sessions donate. The description instead states WHEN the
    // tool applies (the #148 pattern): the selector was observed searching
    // the literal string "2+2" because the old text read like a general
    // memory tool.
    let description = "Find where a specific word or phrase appeared earlier — in this conversation's older messages, or in the titles/previews of indexed past sessions. Use this ONLY when the user asks to find or recall a specific past mention — never to answer a question; the recent conversation is already visible to you without any tool."
    let relay: ToolEventRelay
    let conversationProvider: @MainActor () -> Conversation?
    let sessionCacheProvider: @MainActor () -> [CachedSession]
    let spotlightEnabledProvider: @MainActor () -> Bool

    /// Session-cache row from the #17 Spotlight donation cache — id + title +
    /// preview is all the index ever holds, so it's all search can honestly
    /// claim to cover.
    struct CachedSession: Sendable {
        let id: String
        let title: String
        let preview: String?
    }

    @Generable
    struct Arguments {
        @Guide(description: "The word or phrase to search for.")
        var term: String
    }

    func call(arguments: Arguments) async throws -> String {
        let term = arguments.term.trimmingCharacters(in: .whitespacesAndNewlines)
        await relay.started(name, detail: term)
        defer { Task { await relay.completed(name) } }
        guard !term.isEmpty else { return "No search term was given." }

        // #200Y: the three awaits below are MainActor hops, and a hop onto a
        // busy main actor is precisely a wait cancellation cannot interrupt —
        // the wedge measured in #200V and #200W. Bounded here, at the tool.
        let providers = (conversationProvider, sessionCacheProvider, spotlightEnabledProvider)
        return await DeviceToolTimeout.run(label: name) {
            let conversation = await providers.0()
            let sessions = await providers.1()
            let indexOn = await providers.2()
            return Self.report(
                term: term,
                conversation: conversation,
                sessions: sessions,
                spotlightEnabled: indexOn
            )
        }
    }

    /// Pure search + report assembly (unit-tested).
    nonisolated static func report(
        term: String,
        conversation: Conversation?,
        sessions: [CachedSession],
        spotlightEnabled: Bool
    ) -> String {
        var sections: [String] = []

        let currentHits: [String] = (conversation?.messages ?? []).compactMap { message in
            guard message.sender != .system,
                  let snippet = DeviceToolFormat.snippet(around: term, in: message.content) else { return nil }
            let who = (message.sender == .user || message.sender == .voiceUser) ? "You" : "Hermes"
            return "\(who): \(snippet)"
        }
        if !currentHits.isEmpty {
            sections.append("In the current conversation:\n" + currentHits.suffix(6).joined(separator: "\n"))
        }

        let sessionHits: [String] = sessions.compactMap { session in
            let haystack = [session.title, session.preview ?? ""].joined(separator: " — ")
            guard haystack.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
                return nil
            }
            return "Session \"\(session.title)\"\(session.preview.map { ": \($0)" } ?? "")"
        }
        if !sessionHits.isEmpty {
            sections.append("In past sessions (from the Spotlight index):\n" + sessionHits.prefix(5).joined(separator: "\n"))
        }

        if sections.isEmpty {
            var result = "No matches for \"\(term)\" in the current conversation"
            result += spotlightEnabled
                ? " or the indexed session list."
                : ". (Past sessions aren't searchable — System Search indexing is off in Settings → Privacy.)"
            return result
        }
        if !spotlightEnabled {
            sections.append("(Past sessions weren't searched — System Search indexing is off in Settings → Privacy.)")
        }
        return sections.joined(separator: "\n\n")
    }
}
