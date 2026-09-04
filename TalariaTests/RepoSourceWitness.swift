import Foundation
import Testing

/// **The one implementation of "read production's own source and pin a line in
/// it" — hoisted, not copied again (#340 Task 3).**
///
/// Several suites in this target make structural pins that no runtime test can
/// make: `LocalChatBackend.send` / `streamTurn` need a live
/// `LanguageModelSession`, and the battery loop needs one per trial, so what
/// those functions hand the tool relay is only checkable by reading the repo's
/// own bytes. Two files had already grown a byte-identical
/// `backendFunctionBody(from:)` (`MemoryInjectionTests`, `ToolTurnUserTextTests`)
/// and this task needed a third — at which point the right move is one helper,
/// not one more copy.
///
/// **Why this can only be scored on a simulator.** The read reaches the Mac's
/// filesystem, so off-simulator it fails with NSCocoaErrorDomain 260 — which
/// measures the sandbox and not the code. Callers gate with
/// `repoSourcesAreReadable` (`Phase0ActionCautionTests`' idiom) or accept a
/// loud failure; what none of them may do is fail QUIETLY, which is why every
/// step below is a `#require` with its own message rather than an optional.
///
/// **Two files are deliberately NOT folded in.** `MemoryHonestyTests` carries
/// its own `backendFunctionBody(from:)` built on a `backendSource()` that three
/// other pins in that file share, and `GuardrailImageDegradeTests` has a
/// DIFFERENT function of the same name (a character-`limit` window, the very
/// shape the bounded reader exists to replace). Folding either is a wider
/// change than this lane's bars justify; both are noted here so the next reader
/// finds them rather than rediscovering them.
enum RepoSourceWitness {

    /// The two production files these pins read, named once.
    static let backendPath = "Talaria/Services/Live/LocalChatBackend.swift"
    static let batteryPath = "Talaria/Services/Live/LocalChatBackend+Battery.swift"
    static let deviceActionToolsPath = "Talaria/Services/Live/DeviceTools/DeviceActionTools.swift"

    /// `true` only where the test process shares the Mac's filesystem.
    static let repoSourcesAreReadable: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    /// A repo file's whole text, addressed relative to the repo root.
    ///
    /// `#filePath` is this file's own path, so two `deletingLastPathComponent`
    /// hops land on the repo root regardless of which suite is calling.
    static func source(_ relativePath: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: path, encoding: .utf8),
            "\(relativePath) unreadable — these pins must fail loudly, not vacuously"
        )
    }

    /// One function's body, bounded at the NEXT member declaration rather than
    /// by a character count.
    ///
    /// **The count was wrong in both directions**, which is why the bounded form
    /// exists (`MemoryHonestyTests`' note records the incident): when the anchor
    /// function GROWS the window stops covering it and the pin fails for a
    /// reason unrelated to its claim; when it SHRINKS the window spills into the
    /// next function, whose near-identical lines then satisfy a pin that is
    /// supposed to be about the first one — a false GREEN, much worse than the
    /// false red.
    ///
    /// `boundary` defaults to the four-space method indent the backend uses
    /// throughout; a file whose members carry attributes or `static` in front of
    /// `func` passes its own. Falls back to the rest of the file when the anchor
    /// is the last member, which is safe — the anchor is still what scopes it.
    static func functionBody(from anchor: String,
                             in relativePath: String = backendPath,
                             boundary: String = "\n    func ") throws -> String {
        let source = try source(relativePath)
        let range = try #require(
            source.range(of: anchor),
            "\(anchor) is gone from \(relativePath) — re-point this pin at its successor")
        let rest = source[range.upperBound...]
        guard let next = rest.range(of: boundary) else { return String(rest) }
        return String(rest[..<next.lowerBound])
    }

    /// The single line of a repo file that contains `needle`.
    ///
    /// Fails when there is none OR when there is more than one: a pin that
    /// silently read the first of several matches would keep passing while
    /// asserting about a line nobody meant.
    static func soleLine(containing needle: String, in relativePath: String) throws -> String {
        let matches = try source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains(needle) }
        try #require(matches.count == 1,
                     "expected exactly ONE line containing \(needle) in \(relativePath), found \(matches.count)")
        return String(matches[0])
    }
}
