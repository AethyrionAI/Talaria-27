import Foundation
import Testing
import UIKit
@testable import Talaria

/// #250 — the selected-icon handoff across the app-group boundary. Bars
/// 250-B (round-trip + fail-closed) and 250-C (AppIconStore heals the
/// handoff at init). The widget-side read order is device-verified (250-D).
@MainActor
struct SelectedIconHandoffTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("icon-handoff-\(UUID().uuidString).png")
    }

    // 250-B: publish → load round-trips the preview PNG.
    @Test func publishThenLoadRoundTripsThePreviewPNG() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SelectedIconHandoff.publish(previewImageName: "IconPreview-Default", to: url))
        #expect(SelectedIconHandoff.load(from: url) != nil)
    }

    // 250-B: absent handoff reads nil — the island's cue to fall back.
    @Test func loadFromMissingOrNilURLReturnsNil() {
        #expect(SelectedIconHandoff.load(from: tempURL()) == nil)
        #expect(SelectedIconHandoff.load(from: nil) == nil)
    }

    // 250-B: publish fails closed — unknown art or no destination writes
    // nothing and reports false.
    @Test func publishFailsClosedOnUnknownImageOrNilDestination() {
        let url = tempURL()
        #expect(!SelectedIconHandoff.publish(previewImageName: "no-such-image-\(UUID().uuidString)", to: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!SelectedIconHandoff.publish(previewImageName: "IconPreview-Default", to: nil))
    }

    // 250-C: a fresh store publishes the current selection at init, healing
    // a missing handoff file on every launch.
    @Test func appIconStorePublishesCurrentSelectionAtInit() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = AppIconStore(iconHandoffURL: url)
        #expect(SelectedIconHandoff.load(from: url) != nil)
    }
}
