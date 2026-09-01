import Foundation
import Testing
@testable import Talaria

/// #420 — THE INERT "AUTO-CONNECT ON LAUNCH" TOGGLE.
///
/// The defect this guards is not a wrong value; it is a CONTROL that promised
/// an effect it could not deliver. `autoConnectOnLaunch` shipped with exactly
/// one writer (the toggle's own binding) and ZERO production readers: the
/// consumer went away with the relay retirement (#375) and the switch stayed
/// on the Server screen, so flipping it changed nothing while every runbook
/// step that named it silently became untrue.
///
/// Owen ruled 2026-08-31: **delete the toggle, keep the persisted key.** The
/// key stays because removing it would break decode of older stored settings
/// for no benefit; the control goes because auto-connect-on-launch is not a
/// behaviour the app intends to have post-#375.
///
/// So the property worth guarding is the ABSENCE of a reader — the thing whose
/// absence caused this in the first place. These pins hold three lines:
///
///  - **420-B** (the load-bearing one): `autoConnectOnLaunch` is referenced by
///    its model plumbing and the demo seed and by NOTHING ELSE in the shipping
///    targets. A future lane that re-grows a consumer — a toggle, a launch
///    path, a diagnostic read — goes RED here, and that is the point. If the
///    behaviour is ever genuinely wanted, this pin is the place where the
///    decision has to be made deliberately rather than by accretion.
///  - **420-A**: the control and its search-index row are gone, asserted
///    against the COMPILED index as well as the source text, so an entry that
///    was commented out rather than deleted cannot satisfy it.
///  - **420-C**: the persisted key, its `CodingKeys` case, and the decode
///    default `true` survive — the compatibility half of the ruling, pinned
///    so a later tidy-up cannot quietly finish the job the ruling stopped
///    short of.
///
/// Every check that reads a file fails LOUDLY when it cannot read it: a check
/// that did not run must say so rather than pass.
struct AutoConnectTogglePinTests {

    // MARK: - Helpers

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
    }

    /// Every `.swift` source in the shipping targets, paired with its
    /// repo-relative path. Mirrors `NamingSweepTests.shippingSources()`.
    private static func shippingSources() throws -> [(path: String, text: String)] {
        let rootPrefix = repoRoot.path.hasSuffix("/") ? repoRoot.path : repoRoot.path + "/"
        var out: [(String, String)] = []
        for dir in ["Talaria", "Shared", "TalariaWidgets", "TalariaShare"] {
            let root = repoRoot.appendingPathComponent(dir)
            let walker = try #require(
                FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
                "cannot enumerate \(dir)/ — this check did not run"
            )
            for case let url as URL in walker where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let full = url.resolvingSymlinksInPath().path
                let relative = full.hasPrefix(rootPrefix)
                    ? String(full.dropFirst(rootPrefix.count))
                    : full
                out.append((relative, text))
            }
        }
        #expect(!out.isEmpty, "cannot read any shipping source — this check did not run")
        return out
    }

    /// The only shipping files allowed to name `autoConnectOnLaunch`:
    /// the model's declaration + `Codable` plumbing, and the demo seed.
    private static let allowedReferenceSites: Set<String> = [
        "Talaria/Models/UserSettings.swift",
        "Talaria/Components/DemoData.swift",
    ]

    private static let symbol = "autoConnectOnLaunch"

    // MARK: - 420-B — the absent-reader pin

    /// **420-B.** No shipping source outside the model plumbing and the demo
    /// seed may so much as name `autoConnectOnLaunch`.
    ///
    /// This is deliberately a REFERENCE pin rather than a "reads it" pin: a
    /// static test cannot tell a read from a write, and the honest bar is the
    /// stricter one anyway — the key exists for decode compatibility only, so
    /// any new mention of it in the app is a consumer being re-grown.
    ///
    /// It scans RAW TEXT, comments included, and that is on purpose: a
    /// comment-stripper is a parser, and a parser is a place for this pin to
    /// be subtly wrong. The cost is that prose about the key cannot spell it
    /// outside the allow-listed files — `ServerSettingsScreen.swift`'s header
    /// says so in place, which is a cheaper price than a hand-rolled lexer.
    @Test func autoConnectOnLaunchIsNamedOnlyByItsModelPlumbingAndDemoSeed() throws {
        let offenders = try Self.shippingSources()
            .filter { $0.text.contains(Self.symbol) }
            .map(\.path)
            .filter { !Self.allowedReferenceSites.contains($0) }
            .sorted()

        #expect(
            offenders.isEmpty,
            """
            `\(Self.symbol)` is a compatibility-only persisted key with NO production \
            reader (#420, Owen's 2026-08-31 ruling). These files name it and must not: \
            \(offenders.joined(separator: ", ")). If the behaviour is genuinely wanted \
            now, that is a product decision to take with Owen — not a pin to relax.
            """
        )
    }

    /// The pin above can only be trusted while the allow-listed sites really
    /// do still carry the symbol — otherwise a rename would turn it green by
    /// emptying the search space rather than by satisfying it.
    @Test func theAllowListedSitesStillNameIt() throws {
        let naming = Set(
            try Self.shippingSources()
                .filter { $0.text.contains(Self.symbol) }
                .map(\.path)
        )
        for site in Self.allowedReferenceSites {
            #expect(
                naming.contains(site),
                "\(site) no longer names `\(Self.symbol)` — the 420-B pin would pass vacuously; re-point it"
            )
        }
    }

    // MARK: - 420-A — the control is gone

    /// **420-A, source half.** The toggle's own label literal is gone from
    /// every shipping source.
    @Test func theToggleLabelIsGoneFromEveryShippingSource() throws {
        let label = "\"Auto-connect on launch\""
        let offenders = try Self.shippingSources()
            .filter { $0.text.contains(label) }
            .map(\.path)
            .sorted()
        #expect(
            offenders.isEmpty,
            "the deleted toggle's label literal still appears in: \(offenders.joined(separator: ", "))"
        )
    }

    /// **420-A, compiled half.** Settings search must not offer a row for a
    /// control that no longer exists — the index's own honesty rule is that
    /// every entry names a control that EXISTS at HEAD (#318).
    @Test func settingsSearchOffersNoAutoConnectRow() {
        let allVisible = SettingsSubsystem.cases(privateCloudAvailable: true)

        #expect(
            SettingsSearchIndex.matches(query: "auto connect", visible: allVisible).isEmpty,
            "\"auto connect\" still matches a settings-search row for a control that is gone"
        )
        #expect(
            SettingsSearchIndex.matches(query: "auto-connect", visible: allVisible).isEmpty,
            "\"auto-connect\" still matches a settings-search row for a control that is gone"
        )

        let survivors = SettingsSearchIndex.entries.filter { entry in
            let haystack = ([entry.title] + entry.keywords).map { $0.lowercased() }
            return haystack.contains { $0.contains("auto connect") || $0.contains("auto-connect") }
        }
        #expect(
            survivors.isEmpty,
            "settings-search entries still advertise auto-connect: \(survivors.map(\.title))"
        )
    }

    // MARK: - 420-C — the compatibility half of the ruling

    /// **420-C.** The persisted key and its plumbing survive the deletion.
    /// The ruling kept them on purpose; this pins that a later tidy-up cannot
    /// finish the job it deliberately stopped short of.
    @Test func thePersistedKeyAndItsPlumbingSurvive() throws {
        let source = try #require(
            try? String(
                contentsOf: Self.repoRoot.appendingPathComponent("Talaria/Models/UserSettings.swift"),
                encoding: .utf8
            ),
            "cannot read UserSettings.swift — this check did not run"
        )
        #expect(source.contains("var autoConnectOnLaunch: Bool"), "the stored property is gone")
        #expect(source.contains("case autoConnectOnLaunch"), "the CodingKeys case is gone")
        #expect(
            source.contains("decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true"),
            "the decode default `true` is gone — older stored settings would change meaning"
        )
    }

    /// The behavioural half of 420-C: a stored blob that predates (or omits)
    /// the key still decodes, and a blob that carries it still round-trips.
    @Test func storedSettingsStillCarryTheKeyAcrossDecode() throws {
        let empty = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(empty.autoConnectOnLaunch, "an absent key must still decode to the documented default `true`")

        var settings = UserSettings()
        settings.autoConnectOnLaunch = false
        let round = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(
            round.autoConnectOnLaunch == false,
            "the key must still round-trip — compatibility is the whole reason it was kept"
        )
    }
}
