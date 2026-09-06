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

    /// A dimmed host row — what `ChatScreen.sessionSummary` builds from an
    /// `isResumable == false` info: the "Contacting host…" stub 425-D paints
    /// during the interim window, and the "Host unreachable" stub #190 leaves
    /// behind afterwards. Both are visible history, neither is a destination.
    private static func unresumable(
        _ id: String,
        group: SessionsDrawerModel.Group
    ) -> SessionsDrawerModel.SessionSummary {
        .init(id: id, title: id, subtitle: ChatBackendRouter.hostPendingReason,
              timeLabel: "", group: group, isUnresumable: true)
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

    /// **425-F1 — the fourth door.** `SessionsDrawerModel.selectSession` has
    /// carried the unresumable guard since #190, and the row itself is
    /// `.disabled` — but ⌘1…⌘9 never went through either. It resolves its own
    /// target list and calls `chatStore.openSession` directly, so on an
    /// iPad with a keyboard a dimmed stub was addressable by ordinal. 425-D
    /// made that window ordinary rather than rare: every configured launch now
    /// paints "Contacting host…" stubs for the host's whole timeout.
    ///
    /// The bar is BOTH halves: the stub is not a target, and the ordinals
    /// re-number over the live rows only — a filter that merely blanked the
    /// slot would leave ⌘2 opening nothing and ⌘3 opening the second row.
    ///
    /// Isolating mutation: drop the `isUnresumable` filter from
    /// `sessionJumpTargets` → this row reds and nothing else does.
    @Test func unresumableStubsAreNotJumpTargetsAndOrdinalsRenumber() {
        let sessions = [
            Self.summary("live-a", group: .today),
            Self.unresumable("stub", group: .today),
            Self.summary("live-b", group: .today),
        ]
        let targets = ChatKeyboardShortcuts.sessionJumpTargets(
            sessions: sessions, pinnedIDs: [], archivedIDs: []
        )

        #expect(targets.map(\.id) == ["live-a", "live-b"],
                "a dimmed host stub is visible history, not a ⌘n destination")
        // ⌘2 is `targets[1]`. Before the filter it addressed the stub; the
        // bar is that it now addresses the SECOND LIVE row, not a hole.
        #expect(targets.count == 2)
        #expect(targets[1].id == "live-b",
                "the ordinals must re-number over the live rows — a blanked slot is a second defect, not a fix")
        #expect(targets.allSatisfy { !$0.isUnresumable })
    }

    /// **425-F1, the belt.** A filter on the target list is the fix; the guard
    /// in `openSessionJump` is the second line, mirroring the one
    /// `SessionsDrawerModel.selectSession` has carried since #190. No runtime
    /// test can reach `openSessionJump` (a private method on a SwiftUI
    /// `View`), so this reads the repo's own bytes — the `RepoSourceWitness`
    /// idiom, failing loudly rather than vacuously.
    ///
    /// Isolating mutation: delete the guard from `openSessionJump` → this row
    /// reds and nothing else does.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func openSessionJumpCarriesTheUnresumableGuard() throws {
        let path = "Talaria/Features/Chat/ChatScreen.swift"
        let anchor = "private func openSessionJump(_ ordinal: Int) {"
        let whole = try RepoSourceWitness.source(path)
        #expect(whole.components(separatedBy: anchor).count == 2,
                "\(anchor) is not unique in \(path) — this pin cannot say which one it read")
        let body = try RepoSourceWitness.functionBody(from: anchor, in: path, boundary: "\n    /// ")
        #expect(!body.contains("func "),
                "the slice swallowed a neighbour: the boundary stops at the next DOC COMMENT, so an undocumented neighbour could satisfy this pin instead")
        #expect(body.contains("guard !target.isUnresumable else { return }"),
                "⌘n opens whatever the ordinal resolved to — the belt behind the filter is gone (425-F1)")
        // The guard has to sit BEFORE the open, or it guards nothing.
        let guardAt = try #require(body.range(of: "!target.isUnresumable")?.lowerBound,
                                   "no unresumable guard in openSessionJump")
        let openAt = try #require(body.range(of: "chatStore.openSession(")?.lowerBound,
                                  "no openSession call in openSessionJump")
        #expect(guardAt < openAt,
                "a guard after the open is not a guard")
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
