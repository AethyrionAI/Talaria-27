import Foundation
import Testing
@testable import Talaria

/// #166a — **the privacy-manifest drift tripwire**, plus the built-product
/// check that proves the manifest and the encryption key actually SHIP.
///
/// `PrivacyInfo.xcprivacy` landed for all three bundle targets on 2026-07-22
/// (`6d1515ec`) declaring exactly one required-reason category: UserDefaults.
/// It was correct that day. It then went stale by DRIFT — the app grew three
/// further required-reason API uses (file timestamps in the share-inbox core,
/// `ProcessInfo.systemUptime` in the live voice service, volume-capacity keys
/// in the storage read tool) and no manifest moved. That is the ITMS-91053
/// exposure #166a was filed about, arriving as decay rather than omission.
///
/// **A one-time manifest fix would decay the same way**, so the fix is this
/// test: it re-derives, from the SOURCES, which required-reason categories
/// each target actually touches, and fails if a target's manifest does not
/// cover them. The next undeclared use reddens a suite instead of reaching
/// App Review.
///
/// Three properties this instrument is built to hold:
///
///  1. **It reads the source of truth, not a snapshot.** Per-target source
///     sets are PARSED OUT OF `project.yml` — the same list XcodeGen compiles
///     from — so adding a directory to a target cannot silently escape the
///     sweep. The parse fails loudly if it cannot find all three targets.
///  2. **It fails in both directions.** Missing declarations are the
///     rejection risk (#166a-H); *extra* declarations are the "declared it to
///     be safe" failure #166a-G rules out, and are caught by
///     ``manifestsDeclareNothingUnused``.
///  3. **A check that did not run says so.** Every file read is `#require`d
///     with a message naming what could not be read — the gate's founding sin
///     is an absent failure marker read as success.
///
/// Curated pattern list, with the limits stated plainly: this is a text
/// sweep, not a type checker. It matches the API spellings Talaria could
/// plausibly use from each of Apple's required-reason families; it is not
/// Apple's exhaustive symbol list. Comment-only LINES are stripped so a doc
/// comment naming an API cannot demand a declaration, but a mention inside a
/// block comment whose lines do not begin with `*` is not stripped. Both
/// biases point at over-declaring, which fails loudly here rather than
/// quietly at review.
struct PrivacyManifestCompletenessTests {

    // MARK: - The curated required-reason category list

    /// One of Apple's required-reason API families, paired with the source
    /// spellings that put a target into it.
    private struct Category: Sendable {
        /// The `NSPrivacyAccessedAPIType` string a manifest must carry.
        let apiType: String
        /// Regex alternation matched against comment-stripped source text.
        let pattern: String
        /// The reason code(s) this project's uses are declared under.
        /// Pinned so a future "declare it under whatever" cannot pass:
        /// #166a-G names each of these against a measured call site.
        let expectedReasons: Set<String>
    }

    private static let categories: [Category] = [
        // `UserDefaults` / `@AppStorage`. CA92.1 = access to defaults owned by
        // this app group; 1C8F.1 = defaults owned by the app itself.
        Category(
            apiType: "NSPrivacyAccessedAPICategoryUserDefaults",
            pattern: "UserDefaults|AppStorage",
            expectedReasons: ["CA92.1", "1C8F.1"]
        ),
        // File timestamps. C617.1 = timestamps of files inside the app
        // container / app group container — which is exactly what the
        // share inbox reads (`ShareInboxCore.swift`, app-group staging dir).
        Category(
            apiType: "NSPrivacyAccessedAPICategoryFileTimestamp",
            pattern: """
                creationDate|modificationDate|contentModificationDate\
                |fileModificationDate|attributesOfItem|getattrlist|fstat
                """,
            expectedReasons: ["C617.1"]
        ),
        // System boot time. 35F9.1 = measuring elapsed time between events
        // that occur inside the app — the live voice service times its own
        // playback against `ProcessInfo.systemUptime`.
        Category(
            apiType: "NSPrivacyAccessedAPICategorySystemBootTime",
            pattern: "systemUptime|mach_absolute_time|KERN_BOOTTIME",
            expectedReasons: ["35F9.1"]
        ),
        // Disk space. 85F4.1 = displaying the space to the user, which is
        // literally what the storage read tool does with the numbers.
        Category(
            apiType: "NSPrivacyAccessedAPICategoryDiskSpace",
            pattern: "volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|statfs",
            expectedReasons: ["85F4.1"]
        ),
        // Active keyboards. No use today; present so the sweep can SEE one
        // arrive rather than being blind to a whole family. Both of Apple's
        // reason codes are listed because there is no measured call site to
        // narrow them against — the day one appears, the lane that adds it
        // picks the right code and trims this.
        Category(
            apiType: "NSPrivacyAccessedAPICategoryActiveKeyboards",
            pattern: "activeInputModes",
            expectedReasons: ["3EC4.1", "54BD.1"]
        ),
    ]

    /// The three bundle targets that ship a manifest, and where each
    /// manifest lives. Paths are hardcoded because a manifest's LOCATION is
    /// a packaging fact, not a source-set fact; the SOURCE SETS beside them
    /// are parsed from `project.yml` rather than restated here.
    private static let manifestPaths: [String: String] = [
        "Talaria": "Talaria/Resources/PrivacyInfo.xcprivacy",
        "TalariaShare": "TalariaShare/PrivacyInfo.xcprivacy",
        "TalariaWidgets": "TalariaWidgets/PrivacyInfo.xcprivacy",
    ]

    /// The one declaration in the tree that this suite knowingly tolerates
    /// without a matching source use.
    ///
    /// `TalariaShare`'s manifest has declared UserDefaults since 2026-07-22,
    /// but the extension is purely file-based — it stages into the app-group
    /// CONTAINER (`FileManager.containerURL`), and `UserDefaults` appears
    /// nowhere in `TalariaShare/`. It is an over-declaration inherited from
    /// the manifest's original authoring, left in place deliberately by the
    /// #166a completeness lane (2026-09-01) rather than removed in a lane
    /// scoped to closing gaps. It is recorded HERE, as a named exemption, so
    /// it is a decision on the record instead of a silent tolerance — and so
    /// that no NEW over-declaration can hide behind it.
    private static let knownUnusedDeclarations: Set<String> = [
        "TalariaShare/NSPrivacyAccessedAPICategoryUserDefaults",
    ]

    // MARK: - Repo access

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
    }

    // MARK: - project.yml source-set parsing

    /// Parses `targets: → <name>: → sources: → - path: X` out of
    /// `project.yml`.
    ///
    /// Deliberately a line parser rather than a YAML dependency: the shape it
    /// needs is two indent levels deep and fixed, and the alternative is
    /// adding a package to the test bundle to read six lines. It fails loudly
    /// (rather than returning an empty set that would pass every assertion)
    /// if any expected target is missing or has no sources.
    private static func sourcePathsByTarget() throws -> [String: [String]] {
        let yamlURL = repoRoot.appendingPathComponent("project.yml")
        let yaml = try #require(
            try? String(contentsOf: yamlURL, encoding: .utf8),
            "cannot read project.yml — this check did not run"
        )

        var result: [String: [String]] = [:]
        var currentTarget: String?
        var inSources = false
        var seenTargetsHeader = false

        for line in yaml.components(separatedBy: .newlines) {
            if line == "targets:" {
                seenTargetsHeader = true
                continue
            }
            guard seenTargetsHeader else { continue }

            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // A new target header: `  Name:` at exactly two spaces.
            if indent == 2, trimmed.hasSuffix(":"), !trimmed.hasPrefix("#") {
                currentTarget = String(trimmed.dropLast())
                inSources = false
                continue
            }
            // A target-level key: `    sources:` / `    resources:` / ...
            if indent == 4, !trimmed.hasPrefix("#") {
                inSources = (trimmed == "sources:")
                continue
            }
            guard inSources, let target = currentTarget else { continue }
            guard indent >= 6, trimmed.hasPrefix("- path:") else { continue }

            var path = trimmed.dropFirst("- path:".count)
                .trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 {
                path = String(path.dropFirst().dropLast())
            }
            result[target, default: []].append(path)
        }

        for target in manifestPaths.keys.sorted() {
            let paths = result[target] ?? []
            #expect(
                !paths.isEmpty,
                """
                project.yml parse found no `sources:` for target \(target) — \
                the parser is broken and this check did not run. Every \
                assertion below would pass vacuously.
                """
            )
        }
        return result
    }

    /// Expands a `project.yml` source path (a directory or a single file)
    /// into the `.swift` files it contributes.
    private static func swiftFiles(under path: String) -> [URL] {
        let url = repoRoot.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            return url.pathExtension == "swift" ? [url] : []
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [URL] = []
        for case let child as URL in walker where child.pathExtension == "swift" {
            out.append(child)
        }
        return out
    }

    /// Drops whole-line comments so a doc comment naming an API cannot
    /// demand a manifest declaration. Line comments only — see the type
    /// doc for what this deliberately does not do.
    private static func strippingCommentLines(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !(t.hasPrefix("//") || t.hasPrefix("*") || t.hasPrefix("/*"))
            }
            .joined(separator: "\n")
    }

    /// Every required-reason category a target's compiled sources touch,
    /// with the files that put it there.
    private static func categoriesUsed(
        byTarget target: String,
        sourcePaths: [String: [String]]
    ) throws -> [String: [String]] {
        let paths = sourcePaths[target] ?? []
        var files: [URL] = []
        for path in paths { files.append(contentsOf: swiftFiles(under: path)) }
        #expect(
            !files.isEmpty,
            "no .swift sources resolved for target \(target) — this check did not run"
        )

        var hits: [String: [String]] = [:]
        let regexes: [(String, NSRegularExpression)] = categories.compactMap { category in
            guard let regex = try? NSRegularExpression(pattern: category.pattern) else { return nil }
            return (category.apiType, regex)
        }
        #expect(
            regexes.count == categories.count,
            "a curated category pattern failed to compile — this check did not run"
        )

        for file in files {
            guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let text = strippingCommentLines(raw)
            let range = NSRange(text.startIndex..., in: text)
            for (apiType, regex) in regexes where regex.firstMatch(in: text, range: range) != nil {
                let relative = file.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
                hits[apiType, default: []].append(relative)
            }
        }
        return hits
    }

    // MARK: - Manifest reading

    private struct Manifest {
        /// Declared `NSPrivacyAccessedAPIType` → its reason codes.
        let accessedAPIs: [String: Set<String>]
        /// `nil` means the key is absent, which is a different (and worse)
        /// fact than "present and empty" — kept distinguishable so a missing
        /// key cannot read as a clean declaration.
        let tracking: Bool?
        let trackingDomainCount: Int?
        let collectedDataTypeCount: Int?
    }

    private static func manifest(for target: String) throws -> Manifest {
        let relative = try #require(manifestPaths[target], "no manifest path recorded for \(target)")
        let url = repoRoot.appendingPathComponent(relative)
        let data = try #require(
            try? Data(contentsOf: url),
            "cannot read \(relative) — this check did not run"
        )
        let decoded = try #require(
            try? PropertyListSerialization.propertyList(from: data, format: nil),
            "\(relative) is not a readable plist — this check did not run"
        )
        let plist = try #require(decoded as? [String: Any], "\(relative) is not a plist dictionary")

        var accessed: [String: Set<String>] = [:]
        for entry in (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []) {
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String else { continue }
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            accessed[type, default: []].formUnion(reasons)
        }
        return Manifest(
            accessedAPIs: accessed,
            tracking: plist["NSPrivacyTracking"] as? Bool,
            trackingDomainCount: (plist["NSPrivacyTrackingDomains"] as? [Any])?.count,
            collectedDataTypeCount: (plist["NSPrivacyCollectedDataTypes"] as? [Any])?.count
        )
    }

    // MARK: - #166a-H — the tripwire

    /// Every required-reason category a target's sources touch is declared in
    /// that target's manifest. This is the ITMS-91053 direction: an
    /// undeclared use is a rejection, and drift is how it arrives.
    @Test
    func manifestsCoverEveryRequiredReasonAPIInTheirSources() throws {
        let sourcePaths = try Self.sourcePathsByTarget()
        var failures: [String] = []

        for target in Self.manifestPaths.keys.sorted() {
            let used = try Self.categoriesUsed(byTarget: target, sourcePaths: sourcePaths)
            let declared = Set(try Self.manifest(for: target).accessedAPIs.keys)
            for (apiType, files) in used.sorted(by: { $0.key < $1.key }) where !declared.contains(apiType) {
                failures.append(
                    """
                    \(target): UNDECLARED \(apiType)
                        used by: \(files.sorted().joined(separator: ", "))
                        fix: add it to \(Self.manifestPaths[target] ?? "?")
                    """
                )
            }
        }

        #expect(
            failures.isEmpty,
            """
            Privacy manifest drift — a target uses a required-reason API it \
            does not declare (ITMS-91053 on upload):

            \(failures.joined(separator: "\n"))
            """
        )
    }

    // MARK: - #166a-G — nothing declared "to be safe"

    /// Nothing is declared that no source uses. #166a-G is an IFF, and this
    /// is its reverse arm; the single inherited exception is named in
    /// ``knownUnusedDeclarations`` rather than tolerated silently.
    @Test
    func manifestsDeclareNothingUnused() throws {
        let sourcePaths = try Self.sourcePathsByTarget()
        var failures: [String] = []

        for target in Self.manifestPaths.keys.sorted() {
            let used = Set(try Self.categoriesUsed(byTarget: target, sourcePaths: sourcePaths).keys)
            let declared = Set(try Self.manifest(for: target).accessedAPIs.keys)
            for apiType in declared.subtracting(used).sorted() {
                guard !Self.knownUnusedDeclarations.contains("\(target)/\(apiType)") else { continue }
                failures.append("\(target): declares \(apiType) but no compiled source uses it")
            }
        }

        #expect(
            failures.isEmpty,
            """
            A manifest declares a required-reason category nothing uses. \
            #166a-G rules out declaring "to be safe" — either delete the \
            declaration or record it in knownUnusedDeclarations with a reason:

            \(failures.joined(separator: "\n"))
            """
        )
    }

    /// Reason codes are the MEASURED ones. A declaration under an unrelated
    /// reason is still a false statement to App Review, and would otherwise
    /// satisfy every coverage assertion above.
    @Test
    func declaredReasonsMatchTheMeasuredReasons() throws {
        var failures: [String] = []
        for target in Self.manifestPaths.keys.sorted() {
            let declared = try Self.manifest(for: target).accessedAPIs
            for (apiType, reasons) in declared.sorted(by: { $0.key < $1.key }) {
                guard let category = Self.categories.first(where: { $0.apiType == apiType }) else {
                    failures.append("\(target): declares unknown category \(apiType)")
                    continue
                }
                if reasons.isEmpty {
                    failures.append("\(target): \(apiType) declares no reason codes")
                } else if !reasons.isSubset(of: category.expectedReasons) {
                    failures.append(
                        """
                        \(target): \(apiType) declares \
                        \(reasons.sorted().joined(separator: "+")) — expected a \
                        subset of \(category.expectedReasons.sorted().joined(separator: "+"))
                        """
                    )
                }
            }
        }
        #expect(
            failures.isEmpty,
            """
            A declared reason code does not match the measured use:

            \(failures.joined(separator: "\n"))
            """
        )
    }

    /// The App Privacy posture the #166a register defends: no tracking, no
    /// tracking domains, zero collected data types. Talaria's host traffic
    /// goes only to the user's own machine, so "collects nothing" is a claim
    /// we can defend — this pins it against a well-meaning future edit.
    @Test
    func everyManifestDeclaresZeroTrackingAndZeroCollection() throws {
        for target in Self.manifestPaths.keys.sorted() {
            let manifest = try Self.manifest(for: target)
            #expect(manifest.tracking == false, "\(target): NSPrivacyTracking must be present and false")
            #expect(
                manifest.trackingDomainCount == 0,
                "\(target): NSPrivacyTrackingDomains must be present and empty"
            )
            #expect(
                manifest.collectedDataTypeCount == 0,
                "\(target): NSPrivacyCollectedDataTypes must be present and empty"
            )
        }
    }
}

/// #166a-I — the BUILT PRODUCT, not the source.
///
/// #218's lesson applied to plists: every check we had was reading the tree,
/// and a resource can be present in the repo and absent from the bundle
/// (wrong target membership, a missed `xcodegen generate`, an `optional:`
/// resource path that silently resolved to nothing). These read
/// `Bundle.main`, which in an app-hosted unit test IS the built host app —
/// so a green here means the shipping bundle carries them.
struct PrivacyManifestBuiltProductTests {

    /// The manifest is packaged into the app bundle.
    @Test
    func builtAppBundleCarriesThePrivacyManifest() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            """
            The built app bundle has no PrivacyInfo.xcprivacy. The file exists \
            in the repo, so this is a packaging failure (target membership / \
            stale project) — exactly the gap a source-only check cannot see.
            """
        )
        let data = try #require(try? Data(contentsOf: url), "cannot read the bundled manifest")
        let decoded = try #require(
            try? PropertyListSerialization.propertyList(from: data, format: nil),
            "the bundled manifest is not a readable plist"
        )
        let plist = try #require(decoded as? [String: Any], "the bundled manifest is not a plist dictionary")
        let accessed = try #require(
            plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
            "the bundled manifest declares no NSPrivacyAccessedAPITypes"
        )
        #expect(!accessed.isEmpty, "the bundled manifest's NSPrivacyAccessedAPITypes is empty")
    }

    /// #166d — declared so App Store Connect stops asking per upload. Read
    /// from the built Info.plist because that is the artifact the uploader
    /// reads; `project.yml` saying so is not the same fact.
    @Test
    func builtInfoPlistDeclaresExemptEncryption() throws {
        let value = try #require(
            Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption"),
            "ITSAppUsesNonExemptEncryption is absent from the built Info.plist (#166d)"
        )
        #expect(
            (value as? Bool) == false || (value as? NSNumber)?.boolValue == false,
            "ITSAppUsesNonExemptEncryption must be false, got \(value)"
        )
    }
}
