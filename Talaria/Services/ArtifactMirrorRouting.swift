import Foundation

/// #362 3D-C: the drain-side fork. Artifact-kind items route to the mirror
/// correlator and NEVER to the inbox — an artifact rendered as an inbox row
/// is a file's whole contents pasted into a notification. Everything else
/// keeps today's inbox path byte-identical.
enum ArtifactMirrorRouting {

    struct Split: Equatable {
        var artifacts: [ArtifactMirrorItem] = []
        /// Items the inbox should still receive, in their original order.
        var passthrough: [TalariaPlatformItem] = []
    }

    /// A malformed artifact item (missing session/path meta) goes NOWHERE:
    /// it cannot correlate, and the inbox must never render its content.
    /// The drain's ack is unconditional upstream, so dropping here cannot
    /// cause redelivery.
    static func split(_ items: [TalariaPlatformItem]) -> Split {
        var result = Split()
        for item in items {
            if item.kind == "artifact" {
                if let artifact = ArtifactMirrorItem.parse(item) {
                    result.artifacts.append(artifact)
                }
                // else: malformed mirror item — dropped, honestly.
            } else {
                result.passthrough.append(item)
            }
        }
        return result
    }
}
