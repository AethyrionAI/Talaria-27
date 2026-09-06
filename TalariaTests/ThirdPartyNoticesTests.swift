import Foundation
import Testing

@testable import Talaria

/// # 434 — the third-party notices SHIP, and the three OFL font families are in them.
///
/// The audit (A9) inspected the BUILT product and found no license, OFL or
/// acknowledgement file anywhere in it, while nine font files from three
/// SIL-Open-Font-Licensed families were bundled and declared as `UIAppFonts`.
/// `THIRD_PARTY_LICENSES.md` existed at the repo root and named none of them.
///
/// Three different claims are pinned here, and they fail in three different
/// places on purpose:
///
///  * **434-A — the document says it.** A source witness over the repo's own
///    `THIRD_PARTY_LICENSES.md`. The copyright lines are pinned VERBATIM as
///    read out of each family's TrueType `name` table (nameID 0), not typed
///    from memory; the OFL's own title line pins that the license text is
///    reproduced rather than merely linked.
///  * **434-B — the BUILT bundle carries it.** `Bundle.main` in an app-hosted
///    unit test IS the built host app (`PrivacyManifestBuiltProductTests`'
///    idiom, #166a-I). A document present in the repo and absent from the
///    bundle is exactly the gap the audit found, and no source-only check can
///    see it.
///  * **434-C — the app can show it.** The loader reads the bundled document;
///    Settings → About links to the screen; Settings search finds it.
///
/// Every file read fails LOUDLY when it cannot read — a check that did not run
/// must say so rather than pass (`NamingSweepTests`' rule, inherited).
@Suite("434 third-party notices")
struct ThirdPartyNoticesTests {

    // MARK: - Helpers

    private static let documentPath = "THIRD_PARTY_LICENSES.md"

    private static func document() throws -> String {
        try RepoSourceWitness.source(documentPath)
    }

    /// The three families, each with the copyright string read out of its own
    /// `.ttf` `name` table (nameID 0) on 2026-09-06.
    ///
    /// These are not paraphrases. All three files of a family carry the same
    /// string, and each family's upstream `OFL.txt` header carries it too — the
    /// two sources were compared and agree, which is why they are safe to pin
    /// as literals here.
    static let familyCopyrights: [(family: String, copyright: String)] = [
        ("Chakra Petch",
         "Copyright 2018 The Chakra Petch Project Authors (https://github.com/m4rc1e/Chakra-Petch.git)"),
        ("Space Grotesk",
         "Copyright 2020 The Space Grotesk Project Authors (https://github.com/floriankarsten/space-grotesk)"),
        ("JetBrains Mono",
         "Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono)"),
    ]

    /// The OFL's own title line. Reproducing the license means this line is in
    /// the document; naming and linking it (which the font metadata already
    /// does) does not put it there.
    static let oflTitleLine = "SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007"

    // MARK: - 434-A — the document

    /// **434-A-1 — all three OFL families are named in the notice document.**
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func documentNamesAllThreeFontFamilies() throws {
        let text = try Self.document()
        for entry in Self.familyCopyrights {
            #expect(text.contains(entry.family),
                    "\(Self.documentPath) does not name \(entry.family) — nine bundled font files, three families, all three owed a notice")
        }
    }

    /// **434-A-2 — each family's copyright line appears VERBATIM.**
    ///
    /// The OFL's condition 2 is that each redistributed copy carries "the above
    /// copyright notice and this license". A restated copyright line is not the
    /// copyright notice, so the pin is on the exact bytes.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func documentCarriesEachFamilyCopyrightVerbatim() throws {
        let text = try Self.document()
        for entry in Self.familyCopyrights {
            #expect(text.contains(entry.copyright),
                    "\(Self.documentPath) does not carry \(entry.family)'s embedded copyright line verbatim")
        }
    }

    /// **434-A-3 — the OFL 1.1 text is reproduced, not merely linked.**
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func documentReproducesTheOFLTextOnce() throws {
        let text = try Self.document()
        let occurrences = text.components(separatedBy: Self.oflTitleLine).count - 1
        #expect(occurrences == 1,
                """
                expected the OFL 1.1 text ONCE in \(Self.documentPath) (all three families \
                ship a byte-identical license body — measured), found \(occurrences)
                """)
    }

    /// **434-A-4 — #435's section is not this lane's.**
    ///
    /// Both lanes edit this file on the same day. The "Not covered here"
    /// section belongs to #435 (the WeatherKit attribution correction); this
    /// lane leaves it byte-untouched, and this row says so out loud so a
    /// careless rebase resolution is visible rather than silent.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func documentStillCarriesTheNotCoveredHereSection() throws {
        let text = try Self.document()
        #expect(text.contains("## Not covered here"),
                "the 'Not covered here' section is gone from \(Self.documentPath) — #435 owns it, #434 must not remove it")
    }

    /// **434-A-5 — the OFL body's LOAD-BEARING CLAUSES are reproduced, not
    /// just its title line.**
    ///
    /// `documentReproducesTheOFLTextOnce` pins only `oflTitleLine`. A rebase
    /// that mangled the fenced body — dropping DISCLAIMER, TERMINATION or a
    /// numbered condition's operative sentence while leaving the title and
    /// the dashed rule around it intact — would still pass every existing
    /// row. Pin the substance the license actually turns on.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func documentReproducesTheOFLBodyLoadBearingClauses() throws {
        let text = try Self.document()
        for needle in [
            "must be distributed entirely under this license",
            "TERMINATION",
            "This license becomes null and void if any of the above conditions are",
            "DISCLAIMER",
            "THE FONT SOFTWARE IS PROVIDED \"AS IS\"",
        ] {
            #expect(text.contains(needle),
                    """
                    \(Self.documentPath)'s OFL body is missing a load-bearing clause: \
                    "\(needle)" — the title-line pin alone cannot see this
                    """)
        }
    }

    // MARK: - 434-B — the built product

    /// **434-B-1 — the BUILT app bundle carries the notice document.**
    ///
    /// #218's lesson applied to a resource: the file can be in the repo and
    /// absent from the bundle (never added to a build phase, a stale
    /// `project.pbxproj`, a missed `xcodegen generate`). That is precisely the
    /// state audit A9 found, and only a built-product read can see it.
    @Test
    func builtAppBundleCarriesTheNoticeDocument() throws {
        let url = try #require(
            Bundle.main.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md"),
            """
            The built app bundle has no THIRD_PARTY_LICENSES.md. The file exists in \
            the repo, so this is a packaging failure (missing resource build phase / \
            stale project) — exactly the gap a source-only check cannot see.
            """
        )
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "the bundled notice document is unreadable"
        )
        #expect(text.contains("Chakra Petch"),
                "the bundled notice document does not name Chakra Petch — a stale copy shipped")
    }

    // MARK: - 434-C — the app can show it

    /// **434-C-1 — Settings → About links to the Licenses screen.**
    ///
    /// A structural pin: `AboutSettingsContent` is a view with no reachable
    /// model, so the only honest check that the row exists is on its own
    /// source.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func aboutContentLinksToTheLicensesScreen() throws {
        let source = try RepoSourceWitness.source("Talaria/Features/Settings/AboutSettingsContent.swift")
        #expect(source.contains("LicensesScreen"),
                "Settings → About has no way into the Licenses screen — the notices ship but nobody can read them")
    }

    /// **434-C-2 — Settings search finds the Licenses screen.**
    ///
    /// The four vocabularies the bar names: the row's own title, plus
    /// "acknowledgements", "open source" and "fonts" — the words a reviewer or
    /// a user actually types.
    @Test
    func settingsSearchFindsLicenses() {
        let allVisible = SettingsSubsystem.cases(privateCloudAvailable: true)
        for query in ["licenses", "acknowledgements", "open source", "fonts"] {
            let hits = SettingsSearchIndex.matches(query: query, visible: allVisible)
            #expect(hits.contains { $0.title == "Licenses" && $0.subsystem == .about },
                    "Settings search for '\(query)' does not offer the About → Licenses row")
        }
    }

    /// **434-C-3 — the loader returns the bundled document.**
    ///
    /// The screen's own read, through the production API rather than a
    /// re-spelling of it: this is the call `LicensesScreen` makes, and it is
    /// what turns "the file is in the bundle" into "the screen has something
    /// to show".
    @Test
    func theLoaderReturnsTheBundledDocument() throws {
        let text = try #require(
            LicensesDocument.load(),
            "LicensesDocument.load() found nothing — the Licenses screen would render its empty state"
        )
        #expect(text.contains(Self.oflTitleLine),
                "the loaded document does not carry the OFL text")
        for entry in Self.familyCopyrights {
            #expect(text.contains(entry.copyright),
                    "the loaded document does not carry \(entry.family)'s copyright line")
        }
    }

    /// **434-C-4 — the loader is honest about a bundle with no copy.**
    ///
    /// The empty state has to be reachable, or `missingMessage` is dead copy
    /// that nobody has ever seen render. An empty directory is a bundle with
    /// certainty rather than by assumption.
    @Test
    func theLoaderReturnsNilForABundleWithoutTheDocument() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("434-empty-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let empty = try #require(Bundle(url: dir), "could not make an empty bundle — this check did not run")
        #expect(LicensesDocument.load(from: empty) == nil,
                "the loader claims a document a bundle does not have")
    }

    /// **434-C-5 — a fenced license survives the parse VERBATIM.**
    ///
    /// The one property this parse cannot get wrong. A license whose line
    /// breaks were rearranged, whose leading spaces were trimmed, or whose
    /// `#` line was read as a heading is not the license text any more.
    @Test
    func theParseKeepsFencedTextVerbatim() {
        let source = """
        ## Heading

        ```
        # NOT a heading
          indented line
        - not a bullet

        blank line above kept
        ```
        """
        let blocks = LicensesDocument.blocks(from: source)
        let fenced = blocks.compactMap { block -> String? in
            if case .preformatted(let text) = block { return text }
            return nil
        }
        #expect(fenced == ["# NOT a heading\n  indented line\n- not a bullet\n\nblank line above kept"],
                "the fence was reinterpreted rather than reproduced: \(fenced)")
    }

    /// **434-C-6 — GitHub's collapse wrapper is dropped, its content kept.**
    ///
    /// `<details>` / `<summary>` are a GitHub affordance. Rendered literally on
    /// a phone they would put angle brackets around the very texts a reviewer
    /// opened the screen to read.
    @Test
    func theParseDropsTheDetailsWrapperAndKeepsItsContent() {
        let blocks = LicensesDocument.blocks(from: """
        <details>
        <summary>Verbatim license text</summary>

        ```
        LICENSE BODY
        ```

        </details>
        """)
        #expect(blocks == [.preformatted("LICENSE BODY")],
                "expected only the fenced body, got \(blocks)")
    }

    /// **434-C-7 — the REAL bundled document parses into readable blocks.**
    ///
    /// The two rows above are unit fixtures; this one runs the parse over the
    /// bytes that actually ship. It is the check that would catch a document
    /// edit that renders as one undifferentiated wall of text.
    @Test
    func theBundledDocumentParsesIntoReadableBlocks() throws {
        let text = try #require(LicensesDocument.load(), "no bundled document to parse")
        let blocks = LicensesDocument.blocks(from: text)

        #expect(blocks.contains(.section("Bundled fonts (SIL Open Font License 1.1)")),
                "the fonts section is not a rendered heading")

        let subsections = blocks.compactMap { block -> String? in
            if case .subsection(let title) = block { return title }
            return nil
        }
        for entry in Self.familyCopyrights {
            #expect(subsections.contains { $0.contains(entry.family) },
                    "\(entry.family) has no heading of its own in the rendered document")
        }

        let fenced = blocks.compactMap { block -> String? in
            if case .preformatted(let body) = block { return body }
            return nil
        }
        #expect(fenced.filter { $0.contains(Self.oflTitleLine) }.count == 1,
                "the OFL text does not render as exactly one verbatim block")
        // Any fragment of the collapse wrapper — opening or closing, `<details`
        // or `<summary` — is a leak. Matching only `<details>`/`<summary>`
        // (with the closing `>`) would miss `</details` and `</summary`,
        // which do not contain either of those substrings.
        #expect(!blocks.contains { block in
            guard case .paragraph(let p) = block else { return false }
            return ["<details", "</details", "<summary", "</summary"].contains { p.contains($0) }
        }, "raw HTML wrapper tags reached the rendered page")
    }

    /// **434-C-8 — a `</summary>` on its OWN LINE is dropped too.**
    ///
    /// The parse used to match `<details`, `</details` and `<summary` — not
    /// `</summary`. The shipped document happens to always close `<summary>`
    /// on the same line it opens on, so the gap never fired in practice, but
    /// a `<summary>` / `</summary>` pair split across two lines (a plausible
    /// GitHub-flavoured-Markdown reformat) would leak the closing tag as
    /// literal text in a rendered paragraph. This pins the failure mode
    /// directly rather than trusting that today's document never triggers it.
    @Test
    func theParseDropsAClosingSummaryTagOnItsOwnLine() {
        let blocks = LicensesDocument.blocks(from: """
        <details>
        <summary>
        Verbatim license text
        </summary>

        ```
        LICENSE BODY
        ```

        </details>
        """)
        let paragraphs = blocks.compactMap { block -> String? in
            if case .paragraph(let p) = block { return p }
            return nil
        }
        #expect(!paragraphs.contains { $0.contains("</summary") },
                "a closing </summary> tag on its own line leaked into a rendered paragraph: \(paragraphs)")
        #expect(blocks.contains(.preformatted("LICENSE BODY")),
                "the fenced body inside the two-line <summary> wrapper did not survive the parse")
    }

    /// **434-C-9 — single-line fences are flagged for wrapped rendering; the
    /// multi-line license bodies are flagged for horizontal scroll.**
    ///
    /// The three copyright fences are one line each and gain nothing from a
    /// horizontal scroll — `showsIndicators: false` on top of that is what
    /// turned it from taste into a defect. The WebRTC, OFL and vendored MIT
    /// (Foundation-Models-Framework-Lab) fenced bodies are real license texts
    /// where rewrapping would be a paraphrase, so they stay horizontally
    /// scrollable. This pins the split the view reads to choose between the
    /// two renderings — six fenced blocks in the shipped document, three of
    /// each kind.
    @Test
    func theBundledDocumentsSingleLineFencesAreDistinguishedFromMultilineOnes() throws {
        let text = try #require(LicensesDocument.load(), "no bundled document to parse")
        let blocks = LicensesDocument.blocks(from: text)
        let fenced = blocks.compactMap { block -> String? in
            if case .preformatted(let body) = block { return body }
            return nil
        }

        let singleLine = fenced.filter { LicensesDocument.isSingleLine($0) }
        let multiLine = fenced.filter { !LicensesDocument.isSingleLine($0) }

        #expect(singleLine.count == 3,
                "expected the three copyright one-liners to be flagged single-line, found \(singleLine.count)")
        for entry in Self.familyCopyrights {
            #expect(singleLine.contains(entry.copyright),
                    """
                    \(entry.family)'s copyright fence is not flagged single-line — it would \
                    scroll horizontally for no benefit
                    """)
        }
        #expect(multiLine.count == 3,
                """
                expected the WebRTC, OFL and vendored-MIT license bodies to be flagged \
                multi-line, found \(multiLine.count)
                """)
    }

    // MARK: - 434-D — which targets embed the fonts

    /// **434-D — the nine font files are embedded by the APP target only.**
    ///
    /// Measured rather than assumed, and recorded here so it cannot drift
    /// silently. The app target sweeps `Talaria/Resources/Fonts/` in through
    /// `- path: Talaria`; neither extension names that tree, so neither
    /// embeds a font, and the notice document therefore does not need a
    /// second copy inside an `.appex`. (An extension is delivered inside the
    /// app bundle that embeds it — App Review reads the app.)
    ///
    /// Limits, stated: this is a text sweep over `project.yml`, the same
    /// instrument `PrivacyManifestCompletenessTests` uses for per-target
    /// source sets. It cannot see a font added through a build script. The
    /// built-product half of the measurement is in the lane's report, where a
    /// `find` over the Release product is quoted.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func neitherExtensionTargetEmbedsTheBundledFonts() throws {
        let yml = try RepoSourceWitness.source("project.yml")
        let start = try #require(yml.range(of: "\n  TalariaWidgets:\n"),
                                 "TalariaWidgets: target block not found — this check did not run")
        let end = try #require(yml.range(of: "\n  TalariaTests:\n"),
                               "TalariaTests: target block not found — this check did not run")
        let extensions = String(yml[start.upperBound..<end.lowerBound])
        #expect(extensions.contains("TalariaShare:"),
                "the sliced block does not cover the share extension — this check did not run")
        #expect(!extensions.contains("Talaria/Resources"),
                "an extension target now names the resource tree that holds the fonts — 434-D's answer moved")
        #expect(!extensions.contains(".ttf"),
                "an extension target now names a font file — 434-D's answer moved")
    }
}
