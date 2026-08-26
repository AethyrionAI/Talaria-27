import Foundation

/// #378 (156c) — a READ-ONLY view of the Hermes agent's built-in memory files.
///
/// **Scope, ruled by Owen 2026-08-18:** local `~/.hermes/memories/*.md` first,
/// read-only, no new dependency; Honcho later if ever wanted. Everything below
/// follows from taking that literally.
///
/// ## Why this reads nothing on a phone, and why that is the design
///
/// `~` on iOS is the APP CONTAINER. There is no `~/.hermes` on `whoGoesThere`
/// and there never will be — not because the install is hostless, but because
/// those files live on the Hermes host's filesystem and the phone has no path
/// to it. A simulator process, by contrast, shares the Mac's filesystem, which
/// is the same property `Phase0ActionCautionTests` leans on to read the repo's
/// own sources at test time.
///
/// So the reachable case is the DEV one, and the honest report on a device is
/// **"this build cannot reach a host filesystem"** — never "no memories found".
/// Those two sentences are both true about the filesystem and only one of them
/// is true about the agent: its memory is fine, this build simply cannot see
/// it. Rendering the absence as emptiness is the specific lie available here.
///
/// The two shapes that would make this user-facing are both excluded by the
/// ruling that set the scope: host-delivering the files over the talaria plugin
/// is a NEW DEPENDENCY (a new verb and a host deploy), and Honcho is deferred.
///
/// ## And the content is a PARTIAL view even where it works
///
/// #158 source-confirmed the built-in backend as two plain-text files —
/// `MEMORY.md` and `USER.md`, free-text entries separated by `§`, under a
/// character budget — and warned that if the profile's `memory.provider` is
/// Honcho or Mem0 those files are one layer and may be stale while the real
/// store is remote. #159 turned that from hypothetical into fact: Owen runs the
/// file backend AND a shared Honcho instance. A surface rendering these
/// unlabelled would present a partial view as a complete one.
enum HermesMemoryReader {

    /// One memory file as it is on disk. `entries` are the `§`-separated
    /// free-text records; empty ones are dropped rather than counted, because a
    /// trailing separator is punctuation and not a memory.
    struct File: Equatable, Identifiable, Sendable {
        let name: String
        let entries: [String]
        let characterCount: Int

        var id: String { name }
    }

    /// Deliberately FOUR distinct outcomes, not an optional. Each one is a
    /// different sentence to a reader, and collapsing any two of them is how
    /// this surface would end up implying something it does not know.
    enum Result: Equatable, Sendable {
        /// This build cannot reach a host filesystem at all — the device case.
        /// Says nothing about whether the agent has memories.
        case outOfReach
        /// The path is reachable and there is no memories directory there.
        case directoryMissing(path: String)
        /// The directory exists and holds no `.md` files.
        case empty(path: String)
        /// The directory exists and could not be enumerated or read.
        case unreadable(path: String, reason: String)
        case loaded(path: String, files: [File])
    }

    /// The entry separator, per #158's source-confirm of the built-in backend.
    static let entrySeparator = "§"

    /// Where the ruled scope points, or `nil` when this build cannot follow it.
    ///
    /// COMPILE-TIME on purpose: the answer is a property of the build, not
    /// something to sniff at runtime, and a runtime probe would report
    /// "directory missing" on a device — the exact conflation this type exists
    /// to avoid.
    static var localMemoriesDirectory: URL? {
        #if targetEnvironment(simulator)
        // A simulator process is handed the Mac user's home in its environment;
        // `NSHomeDirectory()` is the app container and would be wrong here.
        // Falling back to the container is harmless — it simply resolves to a
        // directory that does not exist, which reports as `directoryMissing`.
        let host = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
        let home = host.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
        return home.appendingPathComponent(".hermes/memories", isDirectory: true)
        #else
        return nil
        #endif
    }

    /// The read the surface performs. Pure with respect to everything except
    /// the directory it is handed, so every arm is unit-reachable with a temp
    /// directory.
    static func read(directory: URL?, fileManager: FileManager = .default) -> Result {
        guard let directory else { return .outOfReach }
        let path = directory.path

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .directoryMissing(path: path)
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        } catch {
            return .unreadable(path: path, reason: error.localizedDescription)
        }

        // Sorted so the surface is deterministic between reads — an order that
        // depends on directory enumeration is a diff that looks like a change.
        let markdown = contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if markdown.isEmpty { return .empty(path: path) }

        var files: [File] = []
        for url in markdown {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                // One unreadable file does not invalidate the others, but it
                // must not vanish either — it is reported as a file with no
                // entries rather than silently dropped.
                files.append(File(name: url.lastPathComponent, entries: [], characterCount: 0))
                continue
            }
            files.append(File(name: url.lastPathComponent,
                              entries: entries(in: text),
                              characterCount: text.count))
        }
        return .loaded(path: path, files: files)
    }

    /// Split a memory file into its entries. Tolerant of CRLF and of blank runs
    /// around the separator, because these files are written by an agent over
    /// months and not by a serializer.
    static func entries(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: entrySeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// #158's hard caveat, made #159's fact: Owen runs the built-in file
    /// backend AND a shared Honcho instance, so these files are ONE layer and
    /// may not be the authoritative one. Shown with any content, never
    /// optional — a partial view presented as complete is the failure this
    /// surface is most able to commit.
    static let sourceCaveat =
        "One layer only. If the host's memory provider is Honcho or Mem0, the authoritative store is remote and these files may be stale."
}

extension HermesMemoryReader.Result {

    /// The surface's words live here rather than in the view, so the four
    /// sentences below are unit-testable without SwiftUI — and so the one that
    /// matters most can be pinned: **none of them claims anything about what
    /// the agent remembers.** Only the filesystem is being described.
    var headline: String {
        switch self {
        case .outOfReach: return "OUT OF REACH"
        // Not "NO MEMORIES DIRECTORY", which is what this said until
        // `noEmptyHandedStateClaimsTheAgentRemembersNothing` reddened on it.
        // The phrase is strictly about a directory and reads at a glance as a
        // verdict on the agent — exactly the conflation this type exists to
        // prevent, committed in the type that exists to prevent it.
        case .directoryMissing: return "DIRECTORY NOT FOUND"
        case .empty: return "DIRECTORY EMPTY"
        case .unreadable: return "UNREADABLE"
        case .loaded(_, let files):
            let entries = files.reduce(0) { $0 + $1.entries.count }
            return "\(files.count) FILE\(files.count == 1 ? "" : "S") · \(entries) ENTR\(entries == 1 ? "Y" : "IES")"
        }
    }

    var detail: String {
        switch self {
        case .outOfReach:
            return "Agent memory files live on the Hermes host's filesystem, and this build has no path to one. Nothing can be read here — which is a fact about this device, not about the agent."
        case .directoryMissing(let path):
            return "There is no directory at \(path). A host that keeps its memory with a remote provider has none either."
        case .empty(let path):
            return "\(path) holds no .md files."
        case .unreadable(let path, let reason):
            return "\(path) could not be read — \(reason)."
        case .loaded(let path, _):
            return path
        }
    }

    /// True exactly when content is on screen. The caveat qualifies what is
    /// SHOWN; on the three empty-handed arms there is nothing to qualify, and
    /// printing it there would read as a diagnosis.
    var showsSourceCaveat: Bool {
        if case .loaded = self { return true }
        return false
    }
}
