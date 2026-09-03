import Foundation
import Testing
@testable import Talaria

/// #422 rulings 1 and 3, made STRUCTURAL — the two source scans bar 422-D
/// pre-registered.
///
/// Both are greps, and both exist because the rules they guard are the kind
/// that a future edit satisfies in spirit and breaks in fact. "No model call
/// may author a stored memory" is a promise about every line of a module, not
/// about the lines someone remembered to review; "retrieval is never merged
/// into the host client" is a promise about a FILE, not about today's call
/// graph. A reviewer can only check the diff in front of them. A grep checks
/// the whole module, every run.
///
/// **Each scan fails LOUDLY when it cannot read its sources** — an empty
/// enumeration is reported as a failure, never as a pass. That is the gate's
/// founding sin (absence of a failure marker is not success) applied to a
/// check whose natural failure mode is silence.
///
/// **Both were watched RED before they were trusted**, by planting the banned
/// token in the scanned tree and confirming the failure text names the file
/// (evidence in the Task 10 report). A structural pin nobody has seen fail is
/// an assertion about a regex, not about the codebase.
struct MemoryStructuralPinsTests {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
    }

    /// Every `.swift` file under a repo-relative directory, as text.
    /// Mirrors `NamingSweepTests.shippingSources()`'s enumerator, scoped.
    private static func sources(under relativeDirectory: String) throws -> [(path: String, text: String)] {
        let root = repoRoot.appendingPathComponent(relativeDirectory)
        let walker = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "cannot enumerate \(relativeDirectory) — this check did not run"
        )
        var out: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                out.append((url.path, text))
            }
        }
        #expect(!out.isEmpty, "no sources under \(relativeDirectory) — this check did not run")
        return out
    }

    // MARK: - Ruling 1: nothing in the memory module can reach the model

    /// **Ruling 1, structurally.** Retrieval over the user's own stored turns
    /// and explicit notes — *no model call may author a stored memory, and no
    /// paraphrase exists anywhere in the memory path*. Truncation through
    /// `LocalIntelligenceService.trimmed(_:toTokenBudget:)` is the only
    /// allowed shortening, and it is not in this list precisely because it is
    /// the sanctioned one.
    ///
    /// The four tokens are the ways a Swift file reaches a generation:
    /// constructing a session, either call on one, and the guided-output
    /// macro. A file under `Memory/` that carries any of them is a file that
    /// could rewrite a memory in the user's name — and the failure would be
    /// invisible, because a paraphrase reads perfectly well.
    @Test func theMemoryModuleCannotReachTheModel() throws {
        let banned = ["LanguageModelSession", "respond(", "streamResponse(", "@Generable"]
        let sources = try Self.sources(under: "Talaria/Services/Live/Memory")
        for (path, text) in sources {
            for token in banned {
                #expect(
                    !text.contains(token),
                    """
                    \(URL(fileURLWithPath: path).lastPathComponent) contains "\(token)" — \
                    #422 ruling 1: no model call may author a stored memory, and the only \
                    allowed shortening is LocalIntelligenceService.trimmed(_:toTokenBudget:). \
                    Retrieval belongs in LocalChatBackend, not in the memory module.
                    """
                )
            }
        }
    }

    // MARK: - Ruling 3: the host client never learns about local memory

    /// **Ruling 3, structurally.** Local memory is never merged with the
    /// host's. The positive half of that rule (retrieval is CALLED only from
    /// `LocalChatBackend`) is unenforceable by grep alone — but its
    /// consequence is not: the Hermes client must not reference the memory
    /// module at all.
    ///
    /// The failure this prevents is a plausible one rather than an exotic
    /// one. A host turn and a local turn share a transcript, a ChatStore and
    /// a send path; "inject the notes on host turns too" is one line, and it
    /// would put the user's on-device memories on the wire to a machine.
    /// Ruling 3 says that decision belongs to a ruling, not to a diff.
    @Test func theHermesClientNeverReferencesTheMemoryModule() throws {
        let banned = ["MemoryRetriever", "MemoryStore", "MemoryBudget"]
        let directory = Self.repoRoot.appendingPathComponent("Talaria/Services/Live")
        let names = try #require(
            try? FileManager.default.contentsOfDirectory(atPath: directory.path),
            "cannot list Talaria/Services/Live — this check did not run"
        )
        let clients = names.filter { $0.hasPrefix("SessionsHermesClient") && $0.hasSuffix(".swift") }
        #expect(!clients.isEmpty, "no SessionsHermesClient*.swift found — this check did not run")

        for name in clients {
            let text = try #require(
                try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8),
                "cannot read \(name) — this check did not run"
            )
            for token in banned {
                #expect(
                    !text.contains(token),
                    """
                    \(name) references "\(token)" — #422 ruling 3: local memory is never \
                    merged with the host's. Retrieval is called from LocalChatBackend only.
                    """
                )
            }
        }
    }
}
