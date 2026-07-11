import SwiftUI
import UIKit

/// UIActivityViewController wrapper for flows that stage a file and then
/// offer it outward (Settings metadata export, `/save` transcript export).
/// `ShareLink` covers inline affordances like the agent-file bubble; this is
/// the modal flavor presented after an action completes.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
