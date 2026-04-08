import SwiftUI

/// Renders message content with inline markdown formatting, fenced code blocks,
/// and inline images. Images from markdown (`![alt](url)`) are rendered as
/// tappable async-loaded previews that open in a fullscreen viewer.
struct MarkdownContentView: View {
    let content: String
    let isStreaming: Bool
    var showCursor: Bool = false

    @State private var fullscreenImage: MarkdownSegment?

    var body: some View {
        let segments = parseMarkdownSegments(content, isStreaming: isStreaming)

        if segments.isEmpty && showCursor {
            BlinkingCursor()
        } else {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    switch segment {
                    case .prose(_, let text):
                        proseView(text, isLast: index == segments.count - 1)
                    case .codeBlock(_, let language, let code):
                        CodeBlockView(language: language, code: code)
                    case .image(_, let url, let altText):
                        inlineImageView(url: url, altText: altText, segment: segment)
                    }
                }
            }
            .fullScreenCover(item: $fullscreenImage) { segment in
                if case .image(_, let url, let altText) = segment {
                    ImageViewerScreen(url: url, altText: altText)
                }
            }
        }
    }

    @ViewBuilder
    private func proseView(_ text: String, isLast: Bool) -> some View {
        if showCursor && isLast {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                formattedText(text)
                BlinkingCursor()
            }
        } else {
            formattedText(text)
        }
    }

    private func formattedText(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
                .font(Design.Typography.body)
                .foregroundColor(Design.Colors.foreground)
        } else {
            return Text(text)
                .font(Design.Typography.body)
                .foregroundColor(Design.Colors.foreground)
        }
    }

    // MARK: - Inline Image

    private func inlineImageView(url: URL, altText: String, segment: MarkdownSegment) -> some View {
        Button {
            fullscreenImage = segment
        } label: {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 260, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))

                case .failure:
                    HStack(spacing: Design.Spacing.xxs) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.caption)
                        Text(altText.isEmpty ? "Image failed to load" : altText)
                            .font(Design.Typography.caption)
                    }
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .padding(Design.Spacing.sm)
                    .background(Design.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))

                case .empty:
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .fill(Design.Colors.surface)
                        .frame(width: 200, height: 140)
                        .overlay {
                            ProgressView()
                                .tint(Design.Colors.secondaryForeground)
                        }

                @unknown default:
                    EmptyView()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fullscreen Image Viewer

struct ImageViewerScreen: View {
    let url: URL
    let altText: String

    @Environment(\.dismiss) private var dismiss
    @State private var savedToPhotos = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .ignoresSafeArea()

                case .failure:
                    VStack(spacing: Design.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Failed to load image")
                            .foregroundStyle(.secondary)
                    }

                case .empty:
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)

                @unknown default:
                    EmptyView()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: Design.Spacing.lg) {
                // Download to Photos
                Button {
                    downloadToPhotos()
                } label: {
                    Label(
                        savedToPhotos ? "Saved" : "Save to Photos",
                        systemImage: savedToPhotos ? "checkmark.circle.fill" : "arrow.down.to.line"
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .disabled(savedToPhotos)

                // Share
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.bottom, Design.Spacing.xxl)
        }
        .statusBarHidden(true)
    }

    private func downloadToPhotos() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let uiImage = UIImage(data: data) else { return }
                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                withAnimation { savedToPhotos = true }
            } catch {
                // Download failed — silently ignore
            }
        }
    }
}

// MARK: - Blinking Cursor

/// An animated text cursor that blinks at the end of streaming content.
struct BlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        Text("|")
            .font(Design.Typography.body)
            .foregroundStyle(Design.Brand.accent)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}
