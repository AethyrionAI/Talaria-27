import AppIntents
import Foundation
import Testing
@testable import Talaria

/// #415-SWEEP — Owen's STANDING NAMING RULING, applied wholesale
/// (2026-08-27, verbatim: *"If it says Hermes outward on the phone, replace
/// it with Talaria. With the exception being the in app connection to
/// Hermes."*).
///
/// The two prior naming lanes were string-by-string — 415-N took the two
/// Control Center control titles, 415-S took the Shortcuts title and
/// shortTitle. This suite guards the WHOLESALE pass, and it exists to hold
/// three different kinds of line at once:
///
///  1. **APP-MEANING strings now say Talaria.** The assistant surface — the
///     persona the user talks to. The local brain answers with no host at
///     all, so naming it after the host was wrong even before the ruling.
///  2. **HOST-MEANING strings still say Hermes, and that is not an
///     oversight.** Talaria is a client for a *Hermes* host; every string
///     that names the host, the gateway, the connection, or where a message
///     goes when a host is attached is CORRECT as-is. The failure mode a
///     sweep lane actually has is a global search-and-replace, and no
///     amount of asserting the new spellings can see it — so the
///     host-meaning pins are asserted as loudly as the renames.
///  3. **FENCES that outrank the ruling stay structurally untouched** —
///     identifiers, not prose: the `hermes://` easter-egg scheme (#77),
///     CarPlay's deferred rename, control and widget `kind`s. A rename that
///     also moved an identifier would satisfy every visible-title bar in
///     this lane and still orphan a control Owen has placed on his phone.
///
/// Every check that reads a file fails LOUDLY when it cannot read it — a
/// check that did not run must say so rather than pass (the gate's founding
/// sin, arriving as a green tick).
struct NamingSweepTests {

    // MARK: - Helpers

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
    }

    /// Every `.swift` source in the shipping targets, as text.
    private static func shippingSources() throws -> [(path: String, text: String)] {
        var out: [(String, String)] = []
        for dir in ["Talaria", "Shared", "TalariaWidgets", "TalariaShare"] {
            let root = repoRoot.appendingPathComponent(dir)
            let walker = try #require(
                FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
                "cannot enumerate \(dir)/ — this check did not run"
            )
            for case let url as URL in walker where url.pathExtension == "swift" {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    out.append((url.path, text))
                }
            }
        }
        #expect(!out.isEmpty, "cannot read any shipping source — this check did not run")
        return out
    }

    private static func read(_ relativePath: String) throws -> String {
        try #require(
            try? String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8),
            "cannot read \(relativePath) — this check did not run"
        )
    }

    /// Recursively collects every `String` reachable from a value's mirror.
    ///
    /// `ParameterSummary` publishes no members at all (the protocol is a bare
    /// `associatedtype Intent`) and `ParameterSummaryString` exposes no
    /// accessor for the format it was built from, so reflection is the only
    /// way to read the COMPILED summary rather than re-reading the source
    /// text that produced it. Depth-capped so a cyclic graph cannot hang the
    /// suite — an instrument that can stall is worse than one that fails.
    private static func reflectedStrings(_ value: Any, depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        if let string = value as? String { return [string] }
        return Mirror(reflecting: value).children.flatMap {
            reflectedStrings($0.value, depth: depth + 1)
        }
    }

    // MARK: - 415-SWEEP-1: the elected string

    /// **415-SWEEP-1 — the string the ruling was issued for.**
    ///
    /// 415-S renamed `AskHermesIntent.title` and the App Shortcut
    /// `shortTitle`, then flagged a third site it had no mandate for:
    /// `parameterSummary`, which is the row the user reads in the Shortcuts
    /// EDITOR ("Ask Hermes ${question}"). Owen elected it and made the rule
    /// standing in the same breath.
    ///
    /// Asserted against the COMPILED value, not the source line, so a
    /// literal that was commented out rather than changed cannot satisfy it.
    /// The failure message carries the whole reflected dump: if AppIntents
    /// ever reshapes `ParameterSummaryString` so the format no longer
    /// surfaces, this goes red with the evidence attached instead of quietly
    /// asserting over an empty list.
    @Test func electedParameterSummaryNamesTalaria() {
        let strings = Self.reflectedStrings(AskHermesIntent.parameterSummary)
        let joined = strings.joined(separator: " | ")

        #expect(strings.contains { $0.contains("Ask Talaria") },
                "parameterSummary does not name Talaria — reflected strings: [\(joined)]")
        #expect(!strings.contains { $0.contains("Ask Hermes") },
                "parameterSummary still reads 'Ask Hermes' — reflected strings: [\(joined)]")
    }

    // MARK: - 415-SWEEP-2: the app-meaning renames

    /// Compiled app-surface values that name the assistant. Each of these is
    /// something the user reads or hears, and each is reachable with NO host
    /// configured — which is precisely why they are Talaria now.
    @Test func assistantPersonaValuesNameTalaria() {
        #expect(Conversation.defaultTitle == "Talaria")
        #expect(TranscriptSpeaker.hermes.displayLabel == "Talaria")
        #expect(HermesActivityAttributes().agentName == "Talaria")
        #expect(AskHermesIntent.stillWorkingDialog
                == "Talaria is still working on it. Open the app to watch it finish.")
    }

    /// **A 415-SWEEP MISS, found 2026-08-31 by the runbook staleness audit.**
    /// `AskHermesIntent.title` and `parameterSummary` were renamed to "Ask
    /// Talaria" by 415-S — and then the intent rendered a result card headed
    /// "HERMES", one screen later, contradicting its own name.
    ///
    /// It is app-meaning under the sweep's own Rule 1: the badge on the
    /// assistant's answer card, reachable with NO host (the local brain
    /// answers this intent), so it never named the host in the first place.
    /// It survived the wholesale pass because the string was buried inside a
    /// SwiftUI `body`, where no reflection or compiled-value pin could see
    /// it — which is why the fix EXTRACTS it rather than merely editing it.
    @Test func theSiriResultCardIsBadgedTalaria() {
        #expect(AskHermesSnippetView.headerLabel == "TALARIA")
        #expect(AskHermesSnippetView.headerLabel != "HERMES")
    }

    /// **The `Info.plist` permission usage descriptions — the surface no
    /// prior naming lane inventoried, and the most outward one in the app.**
    ///
    /// iOS renders these verbatim in its own system permission alerts, above
    /// an app the user installed as *Talaria*. Telling them "Hermes uses your
    /// location" names software they have never heard of, and the calendar
    /// one actively misdirects: it sends them to Settings → Privacy to find
    /// a row that is labelled Talaria.
    ///
    /// Both files are checked because `Talaria/Resources/Info.plist` is
    /// xcodegen-generated FROM `project.yml` and committed — asserting only
    /// the source would pass on a stale generated artifact, which is the
    /// build-output half of the same trap.
    @Test func permissionUsageDescriptionsNameTalaria() throws {
        for path in ["project.yml", "Talaria/Resources/Info.plist"] {
            let text = try Self.read(path)
            for stale in ["Hermes uses", "Hermes reads", "Hermes only creates",
                          "Hermes looks up", "Hermes accesses", "Hermes schedules",
                          "Hermes does not write"] {
                #expect(!text.contains(stale),
                        "\(path) still tells the user about \"\(stale)…\" in a system permission prompt")
            }
            #expect(text.contains("Talaria uses your location"),
                    "\(path) lost the location usage description entirely")
        }
    }

    /// The app-meaning literals this sweep took, asserted ABSENT as QUOTED
    /// literals across every shipping source.
    ///
    /// Presence checks alone pass on a half-done rename that fixed the
    /// headline site and left four siblings behind — which is the actual
    /// failure mode of a wholesale pass. Matching the quoted spelling means
    /// comments discussing the old names (and several do, deliberately) can
    /// never satisfy or break this.
    @Test func oldAppMeaningLiteralsAreGone() throws {
        let sources = try Self.shippingSources()

        for stale in [
            "\"Ask Hermes \\(\\.$question)\"",       // the elected string, at source
            "\"What should I ask Hermes?\"",         // Siri's parameter prompt
            "\"What to ask Hermes.\"",               // the parameter's description
            "\"Hermes Is Reasoning\"",               // the thinking indicator
            "\"Hermes is thinking\"",                // long-run progress
            "\"Hermes is thinking.\"",               // voice HUD
            "\"Hermes is speaking.\"",               // voice HUD
            "\"Hermes Session\"",                    // Spotlight entity
            "\"Hermes File\"",                       // Spotlight entity
            "\"File from Hermes\"",                  // Spotlight subtitle
            "\"Open Hermes Session\"",               // Spotlight open intent
            "\"Open Hermes File\"",                  // Spotlight open intent
            "\"Hermes Health\"",                     // widget gallery name
            "\"Hermes Status\"",                     // widget gallery name
            "\"Hermes Timer\"",                      // alarm Live Activity
            "\"Hermes Agent\"",                      // demo conversation title
            "\"This is how Hermes replies will sound.\"",  // spoken voice preview
        ] {
            let offenders = sources.filter { $0.text.contains(stale) }.map(\.path)
            #expect(offenders.isEmpty,
                    "app-meaning literal survived the sweep: \(stale) in \(offenders)")
        }

        // The on-device and Private Cloud system prompts decide what the
        // assistant CALLS ITSELF when the user asks — the most outward string
        // in the app that never appears in a .swift UI file.
        let selfName = sources.filter { $0.text.contains("\"You are Hermes,") }.map(\.path)
        #expect(selfName.isEmpty,
                "a local-brain system prompt still introduces the assistant as Hermes: \(selfName)")
    }

    // MARK: - 415-SWEEP-3: the host-meaning strings that must NOT move

    /// The brain label is the clearest case of "Hermes means the host": it is
    /// the name of the HOST-backed brain, sitting beside `On-Device` in the
    /// same enum. #191 already built the whole header wordmark on that
    /// distinction (TALARIA while a local brain holds the conversation,
    /// HERMES when the host will answer the next turn) — renaming this would
    /// collapse a contrast the app deliberately draws.
    @Test func theHostBrainLabelStaysHermes() {
        #expect(ChatBackendRouter.Brain.hermes.displayLabel == "Hermes")
        #expect(ChatBackendRouter.Brain.hermes.monoLabel == "HERMES")
        #expect(ChatBackendRouter.Brain.onDevice.displayLabel == "On-Device")
    }

    /// **415-SWEEP-3.** Host-meaning families this sweep deliberately walked
    /// past, sampled across five subsystems. `HermesControlsTests`
    /// already pins four of these from 415-N/415-S and is untouched; these
    /// extend the guard to the families a wholesale pass could plausibly have
    /// swept up — service errors, reachability, Connect Host, the paywall,
    /// and the sensor-sharing toggle whose subject really IS the host agent.
    @Test func hostMeaningStringFamiliesSurviveTheSweep() throws {
        let sources = try Self.shippingSources()

        for expected in [
            "\"The Hermes host rejected this device's API key.\"",
            "\"The Hermes host took too long to respond.\"",
            "\"Hermes API base URL is not set.\"",
            "\"Sessions stored on the Hermes host\"",
            "\"Hermes host pairing\"",
            "\"Share Sensors with Hermes\"",
            "\"Send Transcripts to Hermes\"",
            "\"Connect Hermes Desktop\"",
            "\"Update Hermes Agent\"",
            "\"Sending to Hermes\"",
            "\"Reply to Hermes\"",
        ] {
            #expect(sources.contains { $0.text.contains(expected) },
                    "a host-meaning string vanished from the shipping targets: \(expected)")
        }
    }

    // MARK: - 415-SWEEP-4: the fences, shown structurally

    /// **#77's ruling outranks the naming ruling.** `talaria://` is the
    /// documented scheme; `hermes://` rides along deliberately as an easter
    /// egg. It is an IDENTIFIER, not outward prose — nothing renders it to
    /// the user — and dropping it would break any link Owen has already saved.
    ///
    /// Written first against the string `"hermes://"` and it went RED, which
    /// was the test being right and the author being wrong: the scheme is
    /// never spelled with its separator anywhere. It exists in exactly two
    /// places, and both are asserted because either alone is satisfiable
    /// while the feature is broken — a router that accepts a scheme iOS does
    /// not route to it is dead code, and a registration nothing handles is a
    /// launch that lands nowhere.
    @Test @MainActor func theHermesSchemeEasterEggIsUntouched() throws {
        #expect(DeeplinkRouter.registeredSchemes == ["talaria", "hermes"],
                "the hermes easter-egg scheme left the router — #77 ruled it stays")

        for path in ["project.yml", "Talaria/Resources/Info.plist"] {
            let text = try Self.read(path)
            #expect(text.contains("org.aethyrion.talaria27.hermes"),
                    "\(path) no longer registers the hermes URL type — saved hermes:// links would stop opening")
        }
    }

    /// **415-SWEEP-4 — widget `kind`s are identities, exactly like control
    /// `kind`s (415-N-3).** WidgetKit keys a placed widget off its `kind`
    /// string; moving one orphans every instance the user has on a Home
    /// Screen, silently, with no error anywhere. The GALLERY NAMES beside
    /// them moved to Talaria in this lane — that is the whole point of the
    /// pairing: visible title renamed, identity pinned.
    @Test func widgetKindsAreStable() throws {
        for (file, kind) in [
            ("TalariaWidgets/HermesStatusWidget.swift", "HermesStatus"),
            ("TalariaWidgets/HermesHealthWidget.swift", "HermesHealth"),
            ("TalariaWidgets/HermesBriefingWidget.swift", "HermesBriefing"),
        ] {
            let source = try Self.read(file)
            #expect(source.contains("let kind = \"\(kind)\""),
                    "\(file) moved its widget kind — placed widgets would orphan")
        }
    }

    /// **415-SWEEP-4.** The gallery names DID move, in the same files whose
    /// kinds are pinned above. Asserted together so the pair cannot drift
    /// apart: a future sweep that renames a kind to "match" the title goes
    /// red on `widgetKindsAreStable`, and one that reverts a title goes red
    /// here.
    @Test func widgetGalleryNamesSpellTalaria() throws {
        let status = try Self.read("TalariaWidgets/HermesStatusWidget.swift")
        #expect(status.contains(".configurationDisplayName(\"Talaria Status\")"))

        let health = try Self.read("TalariaWidgets/HermesHealthWidget.swift")
        #expect(health.contains(".configurationDisplayName(\"Talaria Health\")"))
    }

    // MARK: - 415-SWEEP-5: the placeholder rename must not strand old chats

    /// **415-SWEEP-5 — the regression this lane had to design around rather
    /// than discover.**
    ///
    /// `Conversation.defaultTitle` is not only a display string; `#4.8`
    /// on-device title generation fires ONLY while `title == defaultTitle`,
    /// which is what stops it overwriting a manual `/title`. Renaming the
    /// constant on its own would therefore stop matching every conversation
    /// created before this build — those chats would show the OLD name
    /// forever AND never become eligible for auto-titling again. A naming
    /// sweep that manufactures a permanent "Hermes" in the drawer is a
    /// sweep that defeated itself.
    ///
    /// The tolerant check is the fix, and this is its mutation test: delete
    /// either arm of the `||` and one of the first two expectations goes red.
    @Test func placeholderTitleToleratesTheLegacyName() {
        #expect(Conversation.isPlaceholderTitle("Talaria"),
                "the current placeholder must count as unnamed")
        #expect(Conversation.isPlaceholderTitle("Hermes"),
                "a pre-#415 conversation must still count as unnamed, or it can never auto-title")
        #expect(!Conversation.isPlaceholderTitle("Weekend plans"),
                "a real title must never be treated as a placeholder")
        #expect(!Conversation.isPlaceholderTitle(""),
                "an empty title is not the placeholder")
    }
}
