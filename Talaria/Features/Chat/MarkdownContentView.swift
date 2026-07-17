import Photos
import SwiftUI

/// Renders message content with inline markdown formatting, fenced code blocks,
/// inline images, headings, block quotes, lists, and pipe tables. Images from
/// markdown (`![alt](url)`) are rendered as tappable async-loaded previews that
/// open in a fullscreen viewer.
struct MarkdownContentView: View {
    let content: String
    let isStreaming: Bool
    var showCursor: Bool = false
    /// Base color for rendered prose (code blocks/images carry their own styling).
    var textColor: Color = Design.Colors.foreground

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
                    case .heading(_, let level, let text):
                        headingView(level: level, text: text)
                    case .blockQuote(_, let level, let text):
                        blockQuoteView(level: level, text: text)
                    case .list(_, let items):
                        listView(items)
                    case .table(_, let header, let alignments, let rows):
                        MarkdownTableView(
                            header: header,
                            alignments: alignments,
                            rows: rows,
                            textColor: textColor
                        )
                    case .chart(_, _, let source):
                        // Chart render surface lands with ChartSegmentView
                        // (OPEN_ITEMS #100 PR 2); until then a decoded chart
                        // fence still shows its data as a code block.
                        CodeBlockView(language: "chart", code: source)
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
        markdownInlineText(text, font: Design.Typography.body, color: textColor)
    }

    // MARK: - Heading

    private func headingView(level: Int, text: String) -> some View {
        markdownInlineText(
            text,
            font: headingFont(level),
            color: level <= 3 ? Design.Colors.foregroundBright : textColor
        )
        .padding(.top, Design.Spacing.xxs)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return Design.Typography.body(24, weight: .bold, relativeTo: .title)
        case 2: return Design.Typography.body(20, weight: .bold, relativeTo: .title2)
        case 3: return Design.Typography.body(17, weight: .bold, relativeTo: .title3)
        case 4: return Design.Typography.body(16, weight: .medium, relativeTo: .headline)
        case 5: return Design.Typography.body(14, weight: .medium, relativeTo: .subheadline)
        default: return Design.Typography.body(13, weight: .medium, relativeTo: .footnote)
        }
    }

    // MARK: - Block Quote

    private func blockQuoteView(level: Int, text: String) -> some View {
        markdownInlineText(text, font: Design.Typography.body, color: Design.Colors.secondaryForeground)
            .padding(.leading, Design.Spacing.sm)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Design.Colors.accentTint(0.5))
                    .frame(width: 3)
            }
            .padding(.leading, CGFloat(max(0, level - 1)) * Design.Spacing.sm)
    }

    // MARK: - List

    private func listView(_ items: [MarkdownListItem]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
                    Text(marker(for: item))
                        .font(Design.Typography.mono(13, relativeTo: .footnote))
                        .foregroundStyle(Design.Colors.mutedForeground)
                    markdownInlineText(item.text, font: Design.Typography.body, color: textColor)
                }
                .padding(.leading, CGFloat(item.depth) * Design.Spacing.md)
            }
        }
    }

    private func marker(for item: MarkdownListItem) -> String {
        if let ordinal = item.ordinal { return "\(ordinal)." }
        switch item.depth {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
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

// MARK: - Inline markdown text

/// Renders text with inline markdown (`**bold**`, `` `code` ``, `[links]()`)
/// at the given font/color; inline `code` runs restyle in mono with a bright
/// accent tint. Shared by prose, headings, quotes, list items, and table cells.
@MainActor
private func markdownInlineText(_ text: String, font: Font, color: Color) -> Text {
    if var attributed = try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = Design.Typography.mono(14, relativeTo: .body)
            attributed[run.range].foregroundColor = Design.Brand.accentBright
        }
        return Text(attributed)
            .font(font)
            .foregroundColor(color)
    } else {
        return Text(text)
            .font(font)
            .foregroundColor(color)
    }
}

// MARK: - Table

/// Renders a GFM pipe table in a horizontally scrollable HUD panel: bold
/// header row, hairline divider, per-column alignment from the delimiter row,
/// and a faint stripe on alternating rows.
struct MarkdownTableView: View {
    let header: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
    let textColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(header.indices, id: \.self) { col in
                        cell(header[col], column: col, isHeader: true, striped: false)
                    }
                }

                Rectangle()
                    .fill(Design.Colors.accentTint(0.12))
                    .frame(height: 1)

                ForEach(rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(rows[rowIndex].indices, id: \.self) { col in
                            cell(
                                rows[rowIndex][col],
                                column: col,
                                isHeader: false,
                                striped: rowIndex % 2 == 1
                            )
                        }
                    }
                }
            }
        }
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
    }

    private func cell(_ text: String, column: Int, isHeader: Bool, striped: Bool) -> some View {
        markdownInlineText(
            text,
            font: isHeader
                ? Design.Typography.body(13, weight: .bold, relativeTo: .footnote)
                : Design.Typography.footnote,
            color: isHeader ? Design.Colors.foregroundBright : textColor
        )
        .multilineTextAlignment(textAlignment(for: column))
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .background(striped ? Design.Colors.accentTint(0.04) : Color.clear)
        .gridColumnAlignment(columnAlignment(for: column))
    }

    private func alignment(for column: Int) -> MarkdownTableAlignment {
        column < alignments.count ? alignments[column] : .leading
    }

    private func columnAlignment(for column: Int) -> HorizontalAlignment {
        switch alignment(for: column) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(for column: Int) -> TextAlignment {
        switch alignment(for: column) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
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
                        savedToPhotos ? "Saved" : (saveError ?? "Save to Photos"),
                        systemImage: savedToPhotos ? "checkmark.circle.fill" : (saveError != nil ? "exclamationmark.triangle" : "arrow.down.to.line")
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(saveError != nil ? .red : .white)
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

    @State private var saveError: String?

    private func downloadToPhotos() {
        Task {
            do {
                // Check photo library authorization first
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    withAnimation { saveError = "Photo library access denied" }
                    return
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                guard let uiImage = UIImage(data: data) else {
                    withAnimation { saveError = "Invalid image data" }
                    return
                }

                // Save using PHPhotoLibrary for proper completion handling
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                }
                withAnimation { savedToPhotos = true }
            } catch {
                withAnimation { saveError = "Save failed" }
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
