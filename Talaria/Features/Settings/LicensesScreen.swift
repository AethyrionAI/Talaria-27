import SwiftUI

// MARK: - #434 Licenses — Settings → About → Licenses
//
// The third-party notices SHIP. Audit A9 found `THIRD_PARTY_LICENSES.md`
// outside the resource tree: the file existed at the repo root, the Release
// product carried no license, OFL or acknowledgement file of any kind, and the
// nine bundled OFL font files were named nowhere. Archived #157 had deferred an
// acknowledgements screen as "not blocking submission … should not be built
// speculatively"; the audit gave it a reason.
//
// **One document, one copy.** The root `THIRD_PARTY_LICENSES.md` stays the
// single source (the GitHub convention every reader already knows) and is
// copied into the app bundle by the app target's resources build phase. There
// is deliberately no second in-app copy to drift out of date — a notice file
// that disagrees with the repo's is worse than one that is merely hard to find.
//
// **No network, no WebView.** The document is read out of `Bundle.main` and
// rendered with `Text`, so this screen works on a phone in airplane mode with
// no host configured — which is the state a reviewer is most likely to open it
// in.

/// The bundled notice document: where it lives, how it is read, and the small
/// pure parse that makes Markdown readable on a phone.
///
/// Everything here is a pure function of the bundle plus a string, which is
/// what lets `ThirdPartyNoticesTests` pin the loader and the parse without a
/// rendered view.
enum LicensesDocument {

    // MARK: The resource

    /// Named once. A typo here is a blank screen, so the bundle test
    /// (`builtAppBundleCarriesTheNoticeDocument`) spells the same two strings
    /// independently rather than importing these — two spellings that must
    /// agree beat one that cannot be wrong.
    static let resourceName = "THIRD_PARTY_LICENSES"
    static let resourceExtension = "md"

    // MARK: Copy

    static let title = "Licenses"
    static let subtitle = "Third-party notices"

    /// Shown when the bundle has no document. Real-data-only: this states the
    /// fact rather than rendering an empty page that looks like "no third
    /// parties", which would be a false claim rather than a missing one.
    static let missingMessage =
        "The notice document is missing from this build. It lives at THIRD_PARTY_LICENSES.md "
        + "in the Talaria repository."

    // MARK: Loading

    /// The bundled document's text, or `nil` when the bundle has no copy.
    ///
    /// The bundle is a parameter so a test can point it at a bundle that does
    /// NOT carry the resource and see the honest `nil` — the default is the
    /// one the app uses.
    static func load(from bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: The parse

    /// One rendered element of the document.
    ///
    /// Deliberately small: this is not a Markdown engine, it is enough of one
    /// to render THIS document honestly. Inline syntax (`**bold**`, `` `code` ``,
    /// links) is left in the string and handled by `AttributedString` at render
    /// time; only block structure is decided here.
    enum Block: Equatable {
        case title(String)
        case section(String)
        case subsection(String)
        case paragraph(String)
        case bullet(String)
        case preformatted(String)
        case rule
    }

    /// Block-parses the notice document.
    ///
    /// Three rules earn their place:
    ///
    ///  * **Fenced blocks are verbatim.** Every license body in the document
    ///    sits inside a ``` fence, and a license reproduced with its line
    ///    breaks rearranged is not the license. Inside a fence nothing is
    ///    interpreted — not headings, not bullets, not the closing HTML.
    ///  * **`<details>` / `<summary>` are dropped.** They are GitHub's
    ///    collapse affordance; on a phone they would render as literal angle
    ///    brackets around the very texts a reviewer came to read. The content
    ///    they wrap is kept — only the wrapper goes.
    ///  * **Soft-wrapped lines rejoin.** The document is hard-wrapped at ~79
    ///    columns for review in a diff; rendering those as separate lines on a
    ///    phone would ladder every paragraph. Blank lines still separate
    ///    paragraphs, which is Markdown's own rule.
    static func blocks(from markdown: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var fence: [String]?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            out.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Inside a fence: verbatim until the closing fence.
            if fence != nil {
                if trimmed.hasPrefix("```") {
                    out.append(.preformatted((fence ?? []).joined(separator: "\n")))
                    fence = nil
                } else {
                    fence?.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                fence = []
                continue
            }

            // GitHub's collapse wrapper — the content stays, the tags go.
            if trimmed.hasPrefix("<details") || trimmed.hasPrefix("</details")
                || trimmed.hasPrefix("<summary") {
                flushParagraph()
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed.hasPrefix("---") && trimmed.allSatisfy({ $0 == "-" }) {
                flushParagraph()
                out.append(.rule)
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushParagraph()
                out.append(.subsection(String(trimmed.dropFirst(4))))
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                out.append(.section(String(trimmed.dropFirst(3))))
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                out.append(.title(String(trimmed.dropFirst(2))))
                continue
            }

            if trimmed.hasPrefix("- ") {
                flushParagraph()
                out.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }
            // Ordered list items ("1. ", "2. ") render as bullets — the
            // document uses them for prose points, not for a sequence anyone
            // counts.
            if let dot = trimmed.firstIndex(of: "."),
               trimmed.distance(from: trimmed.startIndex, to: dot) <= 2,
               trimmed[trimmed.startIndex..<dot].allSatisfy(\.isNumber),
               trimmed[dot...].hasPrefix(". ") {
                flushParagraph()
                out.append(.bullet(String(trimmed[trimmed.index(dot, offsetBy: 2)...])))
                continue
            }

            paragraph.append(trimmed)
        }

        // An unterminated fence still shows its content — dropping the tail of
        // a license because a fence was left open would be the worst possible
        // failure mode for this particular document.
        if let open = fence, !open.isEmpty {
            out.append(.preformatted(open.joined(separator: "\n")))
        }
        flushParagraph()
        return out
    }
}

// MARK: - The screen

/// Settings → About → Licenses.
///
/// Reached from `AboutSettingsContent`'s footer, beside Terms and Privacy —
/// those two leave the app (`openURL`), this one does not.
struct LicensesScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var blocks: [LicensesDocument.Block] = []
    @State private var loaded = false

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    SettingsScreenHeader(title: LicensesDocument.title,
                                         subtitle: LicensesDocument.subtitle) { dismiss() }
                        .padding(.bottom, Design.Spacing.xs)

                    if loaded && blocks.isEmpty {
                        missingPanel
                    } else {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            view(for: block)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle(LicensesDocument.title)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            guard !loaded else { return }
            blocks = LicensesDocument.blocks(from: LicensesDocument.load() ?? "")
            loaded = true
        }
    }

    // MARK: Rendering

    @ViewBuilder
    private func view(for block: LicensesDocument.Block) -> some View {
        switch block {
        case .title(let text):
            // The document's own H1 restates the screen title, so it renders
            // as a quiet lead-in rather than a second heading.
            MonoLabel(text, size: 10, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)
                .padding(.top, Design.Spacing.xs)

        case .section(let text):
            MonoLabel("// \(text)", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Brand.accentText)
                .padding(.top, Design.Spacing.md)

        case .subsection(let text):
            Text(text)
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.foregroundBright)
                .padding(.top, Design.Spacing.xs)

        case .paragraph(let text):
            inline(text)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .top, spacing: Design.Spacing.xs) {
                Text("·")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.dimForeground)
                inline(text)
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .preformatted(let text):
            // Horizontal scroll, not wrapping: these are license texts, and a
            // reflowed license is a paraphrase of one.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(Design.Typography.mono(9, weight: .regular))
                    .foregroundStyle(Design.Colors.foreground)
                    .textSelection(.enabled)
                    .padding(Design.Spacing.sm)
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.md,
                borderColor: Design.Colors.hairline,
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )

        case .rule:
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
                .padding(.vertical, Design.Spacing.xs)
        }
    }

    /// Inline Markdown only — `**bold**`, `` `code` `` and links keep working;
    /// block syntax was already decided by the parse. Falls back to the raw
    /// string, because a notice that fails to parse must still be readable.
    private func inline(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private var missingPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("// Not bundled", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Brand.forgeText)
            Text(LicensesDocument.missingMessage)
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }
}
