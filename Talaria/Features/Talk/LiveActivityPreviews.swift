import SwiftUI

// MARK: - Live Activity Previews
//
// Standard SwiftUI previews that show what the Live Activity layouts look like
// on Lock Screen and Dynamic Island. These don't require the ActivityKit preview
// host, so they work reliably in the main app target.

// MARK: - Lock Screen Preview

private struct LockScreenPreview: View {
    let status: String
    let toolName: String?
    let elapsedSeconds: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 44, height: 44)
                .background(Color.yellow.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Hermes")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let tool = toolName {
                    Text(tool)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            if elapsedSeconds > 0 {
                let m = elapsedSeconds / 60
                let s = elapsedSeconds % 60
                Text(String(format: "%d:%02d", m, s))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Dynamic Island Compact Preview

private struct DynamicIslandCompactPreview: View {
    let status: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.caption)
                .foregroundStyle(.yellow)

            Spacer()

            Text(status.prefix(12))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .clipShape(Capsule())
    }
}

// MARK: - Dynamic Island Expanded Preview

private struct DynamicIslandExpandedPreview: View {
    let status: String
    let toolName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hermes")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            if let tool = toolName {
                Text(tool)
                    .font(.caption2)
                    .foregroundStyle(.yellow.opacity(0.7))
            }
        }
        .padding()
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Dynamic Island Minimal Preview

private struct DynamicIslandMinimalPreview: View {
    var body: some View {
        Image(systemName: "brain.head.profile")
            .font(.caption)
            .foregroundStyle(.yellow)
            .frame(width: 36, height: 36)
            .background(Color.black)
            .clipShape(Circle())
    }
}

// MARK: - Previews

#Preview("Lock Screen — Listening") {
    VStack(spacing: 20) {
        LockScreenPreview(status: "Listening", toolName: nil, elapsedSeconds: 12)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Lock Screen — Tool Call") {
    VStack(spacing: 20) {
        LockScreenPreview(status: "Working on that...", toolName: "hermes_delegate", elapsedSeconds: 45)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Dynamic Island — All States") {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compact").font(.caption).foregroundStyle(.secondary)
            DynamicIslandCompactPreview(status: "Listening")
                .frame(width: 250)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Expanded").font(.caption).foregroundStyle(.secondary)
            DynamicIslandExpandedPreview(status: "Working on that...", toolName: "hermes_delegate")
                .frame(width: 360)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Minimal").font(.caption).foregroundStyle(.secondary)
            DynamicIslandMinimalPreview()
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
