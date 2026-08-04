import Foundation
import Testing
@testable import Talaria

/// #223 Lane 5, bar L5-A — the chat turn body encodes the per-turn model lock
/// exactly when a pick exists, and stays BYTE-COMPATIBLE with today's wire
/// shape when none does. Never a bare `model` (the #241 silent-no-op trap).
struct ChatTurnBodyEncodingTests {

    private func encodeToObject(_ body: SessionsHermesClient.ChatTurnBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func image(byteCount: Int = 64) -> PendingAttachment {
        PendingAttachment(
            kind: .image,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data(repeating: 0xAB, count: byteCount),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    @Test
    func noSelectionEncodesExactlyTheLegacyShape() throws {
        let body = SessionsHermesClient.ChatTurnBody.make(message: "hello", attachments: [], selection: nil)
        let object = try encodeToObject(body)
        // Key set pinned EXACTLY — a no-pick turn must be indistinguishable
        // from today's wire bytes (modulo key order).
        #expect(Set(object.keys) == ["input"])
        #expect(object["input"] as? String == "hello")
    }

    @Test
    func selectionEncodesProviderModelAndLockTrue() throws {
        let selection = ModelSelection(provider: "nous", modelID: "deepseek/deepseek-v4-flash-0731")
        let body = SessionsHermesClient.ChatTurnBody.make(message: "hello", attachments: [], selection: selection)
        let object = try encodeToObject(body)
        #expect(Set(object.keys) == ["input", "provider", "model", "require_model_lock"])
        #expect(object["provider"] as? String == "nous")
        #expect(object["model"] as? String == "deepseek/deepseek-v4-flash-0731")
        #expect(object["require_model_lock"] as? Bool == true)
    }

    @Test
    func selectionRidesAlongsideImagePartsUnchanged() throws {
        let selection = ModelSelection(provider: "kimi-coding", modelID: "kimi-k3")
        let body = SessionsHermesClient.ChatTurnBody.make(
            message: "what is this",
            attachments: [image()],
            selection: selection
        )
        let object = try encodeToObject(body)
        #expect(Set(object.keys) == ["input", "provider", "model", "require_model_lock"])
        // input stays the parts array — text part + image part.
        let parts = try #require(object["input"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts.contains { $0["type"] as? String == "image_url" })
        #expect(object["require_model_lock"] as? Bool == true)
    }
}
