import Foundation

/// Represents file changes detected by git after Hermes completes a coding task.
///
/// The connector captures `git diff` before and after each job to isolate
/// exactly what Hermes modified — no Hermes framework changes required.
struct CodeDiff: Codable, Hashable, Sendable {
    let files: [FileDiff]
    let summary: String

    var isEmpty: Bool { files.isEmpty }
    var fileCount: Int { files.count }
    var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }
}

struct FileDiff: Codable, Hashable, Sendable, Identifiable {
    let path: String
    let status: String   // "modified", "added", "deleted", "renamed"
    let additions: Int
    let deletions: Int
    let patch: String

    var id: String { path }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directoryPath: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    var statusIcon: String {
        switch status {
        case "added": return "plus.circle.fill"
        case "deleted": return "minus.circle.fill"
        case "renamed": return "arrow.right.circle.fill"
        default: return "pencil.circle.fill"
        }
    }

    var statusColor: String {
        switch status {
        case "added": return "green"
        case "deleted": return "red"
        case "renamed": return "blue"
        default: return "orange"
        }
    }
}
