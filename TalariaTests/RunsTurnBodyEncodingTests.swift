import Foundation
import Testing
@testable import Talaria

/// #283 Phase 3 slice 3A, Task 1 — the runs-plane (`/v1/runs`) request encoder.
/// Wire shape proven live by the 3A-0 probe: a bare content-parts array 400s
/// on `/v1/runs` ("No user message found in input"), so attachment turns wrap
/// as a single-user-message array instead of `ChatTurnBody`'s bare parts
/// array; history entries are plain `{"role","content"}` strings.
struct RunsTurnBodyEncodingTests {
    private func json(_ body: SessionsHermesClient.RunsTurnBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func textTurnEncodesPlainStringInputWithSessionAndHistory() throws {
        let body = SessionsHermesClient.RunsTurnBody.make(
            message: "hello",
            attachments: [],
            sessionID: "sess-1",
            history: [.init(role: "user", content: "KUMQUAT-N4A"),
                      .init(role: "assistant", content: "noted")],
            selection: nil
        )
        let obj = try json(body)
        #expect(obj["input"] as? String == "hello")            // plain string — NOT a parts array
        #expect(obj["session_id"] as? String == "sess-1")
        let history = try #require(obj["conversation_history"] as? [[String: Any]])
        #expect(history.count == 2)
        #expect(history[0]["content"] as? String == "KUMQUAT-N4A")
        #expect(obj["provider"] == nil)
        #expect(obj["model"] == nil)
    }

    @Test func selectionAddsProviderAndModel() throws {
        let body = SessionsHermesClient.RunsTurnBody.make(
            message: "hi", attachments: [], sessionID: "s", history: [],
            selection: ModelSelection(provider: "openrouter", modelID: "deepseek-v4")
        )
        let obj = try json(body)
        #expect(obj["provider"] as? String == "openrouter")
        #expect(obj["model"] as? String == "deepseek-v4")
        // Deliberately NO require_model_lock on the runs plane — the lock contract
        // is unverified there (#283 records the delta). Assert absence so a future
        // "helpful" addition trips a test instead of a 400-risk surprise.
        #expect(obj["require_model_lock"] == nil)
    }

    @Test func attachmentTurnWrapsPartsAsSingleUserMessage() throws {
        // The 3A-0 probe proved the bare parts array 400s and this wrap works.
        let png = PendingAttachment.stubTransmittableImage()  // see Step 3
        let body = SessionsHermesClient.RunsTurnBody.make(
            message: "what color?", attachments: [png],
            sessionID: "s", history: [], selection: nil
        )
        let obj = try json(body)
        let input = try #require(obj["input"] as? [[String: Any]], "attachment input must be a MESSAGE array")
        #expect(input.count == 1)
        #expect(input[0]["role"] as? String == "user")
        let parts = try #require(input[0]["content"] as? [[String: Any]])
        #expect(parts.contains { $0["type"] as? String == "text" })
        #expect(parts.contains { $0["type"] as? String == "image_url" })
    }
}

#if DEBUG
extension PendingAttachment {
    /// Minimal transmittable-image fixture for `RunsTurnBody` attachment
    /// tests — mirrors `ChatTurnBodyEncodingTests`'s private `image()` helper.
    static func stubTransmittableImage() -> PendingAttachment {
        PendingAttachment(
            kind: .image,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data(repeating: 0xAB, count: 64),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }
}
#endif
