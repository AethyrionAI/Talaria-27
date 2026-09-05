import SwiftUI

/// A remote image referenced by Markdown (`![alt](https://…)`), rendered as a
/// placeholder naming the host until the reader taps it (#429).
///
/// **The rule this view exists to hold:** nothing is fetched from a third-party
/// host because a message happened to arrive. A remote image URL in a
/// transcript is a beacon — it tells whoever controls that host that the
/// message was rendered, from which IP, and when. Approval is per URL and
/// lasts the launch (`RemoteImageConsent`); a user-authored bubble follows the
/// same rule as an assistant one, because the URL's host learns the same thing
/// either way.
///
/// **The gate is `consent.isApproved(url)` and nothing else.** It is
/// deliberately NOT `consent.image(for: url) != nil`: the store does not
/// enforce `loaded ⊆ approved`, so a decoded image reaching `loaded` by any
/// other route would silently satisfy an image-shaped gate and render bytes
/// the reader never asked for. Approval is the fact this view is about.
///
/// **One load per URL per launch**, including duplicates that render in the
/// same frame: a streaming transcript re-parses on every delta and the parser
/// mints a fresh segment id each time (`MarkdownParser.swift:8`), so each
/// delta produces a new SwiftUI identity and a new `.task`. Task 0 measured
/// today's cost of that — three growing deltas over one hosting controller
/// issued three separate requests for one unchanged URL. The single-flight
/// registry lives in `RemoteImageConsent.loadTask(for:using:)` so that every
/// identity, present and future, shares one in-flight load.
struct RemoteImageView: View {
    enum Mode { case inline, fullscreen }

    let url: URL
    let altText: String
    let mode: Mode
    var onOpen: (() -> Void)? = nil

    @Environment(\.remoteImageConsent) private var consent
    @Environment(\.remoteImageLoader) private var loader

    /// This URL's host, named in three labels below.
    private var host: String { RemoteImagePolicy.host(of: url) }

    var body: some View {
        if consent.isApproved(url) {
            approvedContent
        } else {
            placeholder
        }
    }

    // MARK: - Before the tap

    private var placeholder: some View {
        let host = RemoteImagePolicy.host(of: url)
        return Button {
            consent.approve(url)
        } label: {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                MonoLabel(RemoteImagePolicy.placeholderTitle(host: host))
                Text(RemoteImagePolicy.placeholderAction)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                if !altText.isEmpty {
                    Text(altText)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
            }
            .frame(maxWidth: 260, alignment: .leading)
            .padding(Design.Spacing.sm)
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RemoteImagePolicy.placeholderAccessibilityLabel(host: host))
    }

    // MARK: - After the tap

    @ViewBuilder
    private var approvedContent: some View {
        if let image = consent.image(for: url) {
            loadedImage(image)
        } else if consent.hasFailed(url) {
            failureRow
        } else {
            progress
                // The attempt number is in the id so a tap on the failure row
                // gives this a genuinely new identity (#437-A). Keyed on the
                // URL as well, so a delta that swaps one image for another
                // still restarts.
                .task(id: "\(url.absoluteString)#\(consent.attempt(for: url))") { await loadOnce() }
        }
    }

    @MainActor
    private func loadOnce() async {
        guard consent.image(for: url) == nil else { return }
        let attempt = consent.attempt(for: url)
        let image = await consent.loadTask(for: url, using: loader).value
        // A failure belonging to a load the reader has since retried must not
        // paint the failure row over the retry's spinner.
        guard image == nil, consent.attempt(for: url) == attempt else { return }
        consent.recordFailure(for: url)
    }

    @ViewBuilder
    private func loadedImage(_ image: UIImage) -> some View {
        switch mode {
        case .inline:
            Button {
                onOpen?()
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RemoteImagePolicy.loadedAccessibilityLabel(host: host, altText: altText))

        case .fullscreen:
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()
                .accessibilityLabel(RemoteImagePolicy.loadedAccessibilityLabel(host: host, altText: altText))
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch mode {
        case .inline:
            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                .fill(Design.Colors.surface)
                .frame(width: 200, height: 140)
                .overlay {
                    ProgressView()
                        .tint(Design.Colors.secondaryForeground)
                }

        case .fullscreen:
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        }
    }

    /// A failed load, and a way out of it (#437-A).
    ///
    /// Before this the row was inert text, and because the registry keeps a
    /// finished task — failures included — the image stayed broken for the
    /// whole launch with nothing the reader could do. That is a regression
    /// against the `AsyncImage` this lane replaced, which quietly re-tried on
    /// every re-parse. The row is now the control that clears the failure,
    /// and `consent.retry(url)` is what makes the next render a real load
    /// rather than a re-read of the same recorded `nil`.
    @ViewBuilder
    private var failureRow: some View {
        switch mode {
        case .inline:
            Button {
                consent.retry(url)
            } label: {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    HStack(spacing: Design.Spacing.xxs) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.caption)
                        Text(altText.isEmpty ? RemoteImagePolicy.failureTitle : altText)
                            .font(Design.Typography.caption)
                    }
                    Text(RemoteImagePolicy.failureAction)
                        .font(Design.Typography.caption)
                }
                .foregroundStyle(Design.Colors.secondaryForeground)
                .padding(Design.Spacing.sm)
                .background(Design.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RemoteImagePolicy.failureAccessibilityLabel(host: host))

        case .fullscreen:
            Button {
                consent.retry(url)
            } label: {
                VStack(spacing: Design.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(RemoteImagePolicy.failureTitle)
                    Text(RemoteImagePolicy.failureAction)
                        .font(Design.Typography.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RemoteImagePolicy.failureAccessibilityLabel(host: host))
        }
    }
}
