import Foundation
import SwiftUI
import Testing
@testable import Talaria

// Lane J PR 1 — iPad adaptive foundation. Four UI-independent suites:
// the readable-measure cap (including its iPhone-parity property), the
// hardware-keyboard shortcut table, ⌘1…⌘9 jump ordering (Lane F's drawer
// rule, reused), and a built-Info.plist guard for the universal target
// configuration (J-1) + single-window scene manifest assumptions (J-2).

// MARK: - J-3: readable measure cap

struct ChatMeasureCapTests {

    /// The iPhone-parity guard: the cap is applied unconditionally, so it
    /// must be a pure pass-through at every compact width — all iPhone
    /// widths, iPad Slide Over, and 1/3 Split View all sit far below it.
    @Test func compactWidthsPassThroughUntouched() {
        for width: CGFloat in [320, 375, 390, 393, 402, 430, 440] {
            #expect(Design.Layout.chatContentWidth(forAvailable: width) == width)
        }
    }

    @Test func capEngagesOnlyAboveThreshold() {
        #expect(Design.Layout.chatContentWidth(forAvailable: 700) == 700)
        #expect(Design.Layout.chatContentWidth(forAvailable: 701) == 700)
        // 13" iPad full-screen width: the motivating case.
        #expect(Design.Layout.chatContentWidth(forAvailable: 1180) == 700)
    }

    @Test func capTokenIsTheDispatchTarget() {
        #expect(Design.Layout.chatMeasureMaxWidth == 700)
    }
}

// MARK: - J-4: shortcut registration table

struct KeyboardShortcutTableTests {

    @Test func tableIsCompleteAndCollisionFree() {
        let table = ChatKeyboardShortcuts.registrationTable
        // ⌘N, ⌘K, ⌘, plus ⌘1…⌘9.
        #expect(table.count == 12)
        let signatures = Set(table.map { "\($0.key.character)|\($0.modifiers.rawValue)" })
        #expect(signatures.count == table.count, "two shortcuts share a key assignment")
        #expect(Set(table.map(\.name)).count == table.count, "shortcut names must be unique")
    }

    /// Bare (unmodified) keys would collide with text input — the composer
    /// owns plain Return; everything in the table must be ⌘-modified.
    @Test func everyTableShortcutIsCommandModified() {
        for spec in ChatKeyboardShortcuts.registrationTable {
            #expect(spec.modifiers == .command, "\(spec.name) is not ⌘-modified")
        }
    }

    @Test func keyAssignmentsMatchTheDispatch() {
        #expect(ChatKeyboardShortcuts.newConversation.key.character == "n")
        #expect(ChatKeyboardShortcuts.conversationSearch.key.character == "k")
        #expect(ChatKeyboardShortcuts.openSettings.key.character == ",")
        for ordinal in 1...ChatKeyboardShortcuts.sessionJumpCount {
            #expect(ChatKeyboardShortcuts.sessionJump(ordinal).key.character == Character("\(ordinal)"))
        }
    }
}

// MARK: - J-4: ⌘1…⌘9 jump ordering

@MainActor
struct SessionJumpOrderTests {

    private static func summary(
        _ id: String,
        group: SessionsDrawerModel.Group
    ) -> SessionsDrawerModel.SessionSummary {
        .init(id: id, title: id, subtitle: "", timeLabel: "", group: group)
    }

    /// Jump order is the drawer's visible order: pinned rows float first,
    /// the rest keep fetch (recency) order in their sections; archived rows
    /// are unreachable by shortcut.
    @Test func pinnedFloatsFirstArchivedUnreachable() {
        let sessions = [
            Self.summary("a", group: .today),
            Self.summary("b", group: .today),
            Self.summary("c", group: .yesterday),
            Self.summary("d", group: .earlier),
            Self.summary("e", group: .earlier),
        ]
        let targets = ChatKeyboardShortcuts.sessionJumpTargets(
            sessions: sessions,
            pinnedIDs: ["d"],
            archivedIDs: ["b"]
        )
        #expect(targets.map(\.id) == ["d", "a", "c", "e"])
    }

    /// Before the first session fetch there is nothing to jump to — the
    /// shortcut must resolve to an honest empty list, not a fabricated
    /// target.
    @Test func emptyFetchYieldsNoTargets() {
        let targets = ChatKeyboardShortcuts.sessionJumpTargets(
            sessions: [], pinnedIDs: ["x"], archivedIDs: []
        )
        #expect(targets.isEmpty)
    }
}

// MARK: - J-1/J-2: built-app configuration guard

/// Reads the RAW built Info.plist (not `object(forInfoDictionaryKey:)`,
/// which resolves device-variant keys for the running device) so the
/// device-specific orientation keys are individually assertable.
struct UniversalTargetInfoPlistTests {

    private static func builtInfoPlist() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "Info", withExtension: "plist"),
                               "test host app bundle has no Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: Any])
    }

    /// J-1: TARGETED_DEVICE_FAMILY "1,2" lands in the built app as
    /// UIDeviceFamily [1, 2] — the actual universal-target proof.
    @Test func builtAppIsUniversal() throws {
        let plist = try Self.builtInfoPlist()
        let families = try #require(plist["UIDeviceFamily"] as? [Int])
        #expect(families.contains(1), "iPhone family missing")
        #expect(families.contains(2), "iPad family missing")
    }

    /// J-1: iPad supports all four orientations (freely resizable windows
    /// make orientation locks meaningless on iPadOS 26+ anyway).
    @Test func iPadSupportsAllFourOrientations() throws {
        let plist = try Self.builtInfoPlist()
        let orientations = try #require(plist["UISupportedInterfaceOrientations~ipad"] as? [String])
        let expected: Set<String> = [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ]
        #expect(Set(orientations) == expected)
    }

    /// iPhone parity guard: going universal must not loosen the iPhone's
    /// portrait-only posture. The build writes the iPhone list under the
    /// `~iphone` variant key or the plain key depending on toolchain —
    /// whichever is present must be portrait-only.
    @Test func iPhoneStaysPortraitOnly() throws {
        let plist = try Self.builtInfoPlist()
        let value = plist["UISupportedInterfaceOrientations~iphone"]
            ?? plist["UISupportedInterfaceOrientations"]
        let orientations = try #require(value as? [String],
                                        "no iPhone orientation key in the built Info.plist")
        #expect(orientations == ["UIInterfaceOrientationPortrait"])
    }

    /// J-2: multi-scene stays ON (CarPlay requires it) with the CarPlay role
    /// as the only declared configuration — app windows attach through
    /// SwiftUI, and window scenes beyond the first are refused at runtime by
    /// SingleWindowPolicy. A UIWindowSceneSessionRoleApplication entry
    /// appearing here would mean someone changed that mechanism.
    @Test func sceneManifestMatchesSingleWindowDecision() throws {
        let plist = try Self.builtInfoPlist()
        let manifest = try #require(plist["UIApplicationSceneManifest"] as? [String: Any])
        #expect(manifest["UIApplicationSupportsMultipleScenes"] as? Bool == true)
        let configurations = try #require(manifest["UISceneConfigurations"] as? [String: Any])
        #expect(configurations["CPTemplateApplicationSceneSessionRoleApplication"] != nil,
                "CarPlay scene configuration missing")
        #expect(configurations["UIWindowSceneSessionRoleApplication"] == nil,
                "unexpected window-role scene configuration — J-2 assumes SwiftUI-managed windows")
    }
}
