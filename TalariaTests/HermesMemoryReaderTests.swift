import Foundation
import Testing
@testable import Talaria

/// #378 (156c) — bars 378-A..D.
///
/// The scope Owen ruled is a read of the HERMES HOST's filesystem, and the
/// thing most worth testing here is not the parser: it is that the surface
/// never converts "this build cannot reach that filesystem" into "the agent has
/// no memories". Both sentences are true about a phone; only one is true about
/// the agent.
struct HermesMemoryReaderTests {

    private func makeDirectory(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memories-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, body) in files {
            try body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    // MARK: - 378-A · the parser, against the format #158 source-confirmed

    @Test func entriesAreSeparatedBySectionSignsAndTrimmed() {
        let text = "First memory.\n§\n  Second memory.  \n§\nThird."
        #expect(HermesMemoryReader.entries(in: text)
                == ["First memory.", "Second memory.", "Third."])
    }

    @Test func emptyEntriesAreDroppedRatherThanCounted() {
        // A trailing separator is punctuation, not a memory. Counting it would
        // report a file with one more memory than it has.
        #expect(HermesMemoryReader.entries(in: "Only one.\n§\n").count == 1)
        #expect(HermesMemoryReader.entries(in: "§§§").isEmpty)
        #expect(HermesMemoryReader.entries(in: "   \n  ").isEmpty)
    }

    @Test func crlfIsTolerated() {
        // These files are written by an agent over months, not by a serializer.
        #expect(HermesMemoryReader.entries(in: "A.\r\n§\r\nB.") == ["A.", "B."])
    }

    @Test func aFileWithNoSeparatorIsOneEntry() {
        #expect(HermesMemoryReader.entries(in: "Just prose, no separators at all.").count == 1)
    }

    @Test func loadedFilesAreMarkdownOnlyAndDeterministicallyOrdered() throws {
        let dir = try makeDirectory([
            "USER.md": "Owen prefers verification-first.\n§\nOwen does not write Swift.",
            "MEMORY.md": "The gateway is on :8642.",
            "notes.txt": "not markdown — must be ignored",
        ])
        guard case .loaded(let path, let files) = HermesMemoryReader.read(directory: dir) else {
            Issue.record("expected .loaded"); return
        }
        #expect(path == dir.path)
        // Sorted, so the panel does not appear to change when nothing did.
        #expect(files.map(\.name) == ["MEMORY.md", "USER.md"])
        #expect(files[0].entries.count == 1)
        #expect(files[1].entries.count == 2)
        #expect(files[1].characterCount > 0)
    }

    // MARK: - 378-B · four states, and none of them diagnoses the agent

    @Test func aDirectoryThatDoesNotExistIsNotAnEmptyOne() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-memories-\(UUID().uuidString)")
        #expect(HermesMemoryReader.read(directory: missing)
                == .directoryMissing(path: missing.path))
    }

    @Test func aDirectoryWithNoMarkdownIsEmptyRatherThanMissing() throws {
        let dir = try makeDirectory(["README.txt": "nothing to see"])
        #expect(HermesMemoryReader.read(directory: dir) == .empty(path: dir.path))
    }

    @Test func aNilDirectoryIsOutOfReachRatherThanMissing() {
        // THE distinction this type exists for. `nil` is the device case: there
        // is no host filesystem to point at, which is a different fact from a
        // path that was checked and found bare.
        #expect(HermesMemoryReader.read(directory: nil) == .outOfReach)
    }

    @Test func theFourEmptyHandedOutcomesEachSayADifferentThing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString)")
        let bare = try makeDirectory([:])
        let states: [HermesMemoryReader.Result] = [
            .outOfReach,
            HermesMemoryReader.read(directory: missing),
            HermesMemoryReader.read(directory: bare),
            .unreadable(path: bare.path, reason: "permission denied"),
        ]
        #expect(Set(states.map(\.headline)).count == 4)
        #expect(Set(states.map(\.detail)).count == 4)
    }

    /// The bar that matters most, and the only dishonesty genuinely available
    /// here. Not one of these states knows anything about the agent's memory,
    /// so not one of them may describe it.
    @Test func noEmptyHandedStateClaimsTheAgentRemembersNothing() throws {
        let bare = try makeDirectory([:])
        let claims = ["no memories", "has no memory", "remembers nothing",
                      "memory is empty", "nothing remembered", "never remembered"]
        for state: HermesMemoryReader.Result in [
            .outOfReach,
            .directoryMissing(path: "/x/.hermes/memories"),
            HermesMemoryReader.read(directory: bare),
            .unreadable(path: "/x", reason: "permission denied"),
        ] {
            let words = (state.headline + " " + state.detail).lowercased()
            for claim in claims {
                #expect(!words.contains(claim),
                        "an empty-handed state said \"\(claim)\" — it cannot know that")
            }
        }
    }

    @Test func theOutOfReachWordingNamesTheDeviceRatherThanTheAgent() {
        let detail = HermesMemoryReader.Result.outOfReach.detail.lowercased()
        #expect(detail.contains("host"))
        #expect(detail.contains("not about the agent"))
    }

    @Test func aLoadedHeadlineCountsFilesAndEntries() throws {
        let dir = try makeDirectory(["MEMORY.md": "A.\n§\nB.", "USER.md": "C."])
        #expect(HermesMemoryReader.read(directory: dir).headline == "2 FILES · 3 ENTRIES")
    }

    @Test func theHeadlineSingularisesRatherThanPrintingOneS() throws {
        let dir = try makeDirectory(["MEMORY.md": "Only one."])
        #expect(HermesMemoryReader.read(directory: dir).headline == "1 FILE · 1 ENTRY")
    }

    // MARK: - 378-C · the completeness caveat is not optional

    @Test func theCaveatShowsWithContentAndOnlyWithContent() throws {
        let dir = try makeDirectory(["MEMORY.md": "A."])
        #expect(HermesMemoryReader.read(directory: dir).showsSourceCaveat)
        // Nothing to qualify on the empty-handed arms — printing it there would
        // read as a diagnosis rather than a caveat.
        #expect(!HermesMemoryReader.Result.outOfReach.showsSourceCaveat)
        #expect(!HermesMemoryReader.Result.directoryMissing(path: "/x").showsSourceCaveat)
        #expect(!HermesMemoryReader.Result.empty(path: "/x").showsSourceCaveat)
        #expect(!HermesMemoryReader.Result.unreadable(path: "/x", reason: "y").showsSourceCaveat)
    }

    /// #158's caveat became #159's fact: Owen runs the file backend AND a
    /// shared Honcho instance, so these files are one layer and may be stale.
    /// The caveat must NAME that, not gesture at it.
    @Test func theCaveatNamesTheProvidersThatWouldMakeThisViewPartial() {
        let caveat = HermesMemoryReader.sourceCaveat
        #expect(caveat.contains("Honcho"))
        #expect(caveat.contains("Mem0"))
        #expect(caveat.lowercased().contains("stale"))
    }

    // MARK: - 378-D · read-only, and no new dependency — pinned, not promised

    /// A structural pin over the two new files. "Read-only, no new dependency"
    /// was the ruling's own wording, and a promise in a doc comment is not a
    /// constraint — this is what makes a future edit that grows a write path or
    /// a network call red instead of merely regrettable.
    @Test func theMemorySurfaceNeitherWritesNorReachesTheNetwork() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root

        /// Whole-line comments stripped; a TRAILING comment is deliberately not,
        /// so a line like `foo() // URLSession` still trips. Fails safe.
        func code(_ source: String) -> String {
            source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }

        let forbidden = ["URLSession", "URLRequest", "import Network", "import Combine",
                         "createFile", "removeItem", "moveItem", "copyItem",
                         ".write(to:", "FileHandle(forWriting"]
        for relative in ["Talaria/Services/Live/HermesMemoryReader.swift",
                         "Talaria/Features/Settings/AgentMemorySection.swift"] {
            let source = code(try String(
                contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
            for token in forbidden {
                #expect(!source.contains(token),
                        "\(relative) contains \"\(token)\" — the #378 ruling scoped this read-only with no new dependency")
            }
        }
    }

    /// The panel's words come from the Result type, so the four sentences stay
    /// unit-pinned. A view that started composing its own would put the one
    /// claim this lane must not make back out of reach of a test.
    @Test func thePanelRendersTheResultTypesOwnWords() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent(
                "Talaria/Features/Settings/AgentMemorySection.swift"), encoding: .utf8)
        #expect(view.contains("result.headline"))
        #expect(view.contains("result.detail"))
        #expect(view.contains("HermesMemoryReader.sourceCaveat"))
    }
}
