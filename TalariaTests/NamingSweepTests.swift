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
        let sources = try RepoSourceWitness.shippingSources()

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
        let sources = try RepoSourceWitness.shippingSources()

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

    // MARK: - 422-N: local memory naming pins (bar 422-N)
    //
    // Task 16 ADDED the memory SCREEN's own literals — see
    // `theMemoryScreensOwnWordsAreTalarias` and
    // `theHonestyCorrectionNamesTalariaNotTheHost` below. The comment that
    // stood here listed them as "not built yet"; they ship now.

    /// **(a)/(b) — the memory chip's own labels, already shipped by Tasks
    /// 14/15.** `.local`'s two labels are Talaria-meaning (the local brain
    /// remembered something); `.host`'s label is host-meaning, exactly like
    /// `theHostBrainLabelStaysHermes` above — the host's own memory tool ran,
    /// and saying so is correct, not a naming-sweep miss.
    @Test func memoryChipNamingLiteralsSurviveTheSweep() throws {
        let sources = try RepoSourceWitness.shippingSources()

        for expected in ["\"ON-DEVICE MEMORY\"", "\"SAVED TO MEMORY\""] {
            #expect(sources.contains { $0.text.contains(expected) },
                    "a Talaria-meaning memory literal vanished from the shipping targets: \(expected)")
        }
        #expect(sources.contains { $0.text.contains("\"HERMES MEMORY\"") },
                "the host-meaning memory literal vanished — \"HERMES MEMORY\" names the HOST's memory tool and must stay")
    }

    /// **Task 16 — the MEMORY screen's own words.** The screen is the one
    /// surface whose whole subject is what the APP remembers, so a "Hermes"
    /// anywhere in its Talaria-meaning copy would be the naming ruling
    /// failing at its loudest point. Pinned as source literals (not through
    /// the type) for the same reason the chip labels are: a rename that also
    /// moved the constant would satisfy a `MemoryScreenModel.title ==` check
    /// while the shipping string changed.
    @Test @MainActor func theMemoryScreensOwnWordsAreTalarias() throws {
        let sources = try RepoSourceWitness.shippingSources()

        for expected in [
            "\"MEMORY\"",
            "\"WHAT TALARIA REMEMBERS\"",
            "Nothing saved yet — say \\\"Remember that…\\\" or just keep chatting.",
            "you've sent in on-device chats",
        ] {
            #expect(sources.contains { $0.text.contains(expected) },
                    "a Memory-screen literal vanished from the shipping targets: \(expected)")
        }

        // The model's own values, so a screen that ships the strings above in
        // some OTHER file cannot satisfy the pin while rendering nothing.
        #expect(MemoryScreenModel.title == "MEMORY")
        #expect(MemoryScreenModel.subtitle == "WHAT TALARIA REMEMBERS")
        #expect(!MemoryScreenModel.subtitle.contains("Hermes"))
        #expect(!MemoryScreenModel.emptyCopy.contains("Hermes"))
        #expect(!MemoryScreenModel.truncationNotice.contains("Hermes"))
    }

    /// **Task 16 — the host line is the one place this screen says Hermes,
    /// and it is host-meaning.** Same shape as `theHostBrainLabelStaysHermes`:
    /// the sentence is ABOUT the host's own memory (Honcho, Hindsight), which
    /// is exactly what ruling 3 needs said out loud. Asserted together with
    /// the Talaria-meaning pins above so a sweep cannot "fix" one by breaking
    /// the other.
    @Test @MainActor func theHostMemoryLineStaysHostMeaning() {
        #expect(MemoryScreenModel.hostLine.contains("Hermes host"),
                """
                the line names the HOST's memory — renaming it to Talaria would claim the \
                on-device store belongs to the host, which is ruling 3 inverted
                """)
        #expect(MemoryScreenModel.hostLine.contains("Talaria never reads or merges it"))
    }

    /// **Task 16 — the honesty correction.** Shipped by lane M3
    /// (`LocalChatBackend`), pinned here because it is the one sentence the
    /// app says about its own memory when a reply got it wrong: it must name
    /// TALARIA, never the host.
    @Test func theHonestyCorrectionNamesTalariaNotTheHost() throws {
        // 422-U (2026-09-04): the copy moved from "Nothing was saved to memory.
        // Talaria only remembers what you ask it to…" to "No note was saved.
        // Talaria saves a note only when you say…". Pinned on the CONSTANTS
        // rather than a source grep: the old grep stayed green on a doc comment
        // that merely QUOTED the retired sentence — a green that proves nothing.
        for notice in [LocalChatBackend.memoryCorrectionNotice,
                       LocalChatBackend.memoryCorrectionNoticeNoIndex] {
            #expect(notice.contains("No note was saved"),
                    "the honesty correction lost its lead sentence: \(notice)")
            #expect(notice.contains("Talaria saves a note only when you say"),
                    "the correction no longer names Talaria as the one that saves: \(notice)")
            #expect(!notice.contains("Hermes"),
                    "a host-meaning word on an app-meaning surface: \(notice)")
        }
        // …and the constants are declared in a shipping target, not a harness file.
        let sources = try RepoSourceWitness.shippingSources()
        #expect(sources.contains { $0.text.contains("static let memoryCorrectionNoticeNoIndex") },
                "the honesty correction left the shipping targets")
    }

    /// **(c) — no app-meaning "Hermes Memory" / "Hermes remembers" literal.**
    /// The local brain's own memory is Talaria's, never the host's; a chip or
    /// a screen that spelled either phrase would claim the on-device store
    /// belongs to Hermes, exactly the collapse `theLocalAndHostChipsAreNever
    /// TheSameWords` already guards at the view-model level. This extends the
    /// guard to raw source text, the same shape as `oldAppMeaningLiteralsAreGone`.
    @Test func noAppMeaningHermesMemoryLiteralExists() throws {
        let sources = try RepoSourceWitness.shippingSources()

        for stale in [
            "\"Hermes Memory\"",
            // Deliberately NOT closed with a trailing `\"` — a PREFIX match on
            // purpose, so it catches any completion of the phrase a copy
            // writer might reach for ("Hermes remembers everything you tell
            // it", "Hermes remembers what you said", …), not only the exact
            // two words.
            "\"Hermes remembers",
        ] {
            let offenders = sources.filter { $0.text.contains(stale) }.map(\.path)
            #expect(offenders.isEmpty,
                    "an app-meaning memory literal exists: \(stale) in \(offenders)")
        }
    }

    /// **(d)/(e)/(f) — the PCC policy sentence names memory, identically, in
    /// its two homes.** `docs/privacy.html` is the published policy (a
    /// GitHub Pages root — merging this PR publishes it, which is why the PR
    /// is held for Owen's read); `ConnectHostCopy.privateCloudPolicySentence`
    /// is the app's copy of the same disclosure, rendered by
    /// `PrivateCloudSettingsScreen`. RED before the copy edit lands in both
    /// places.
    ///
    /// `docs/privacy.html` spells the em dash as the `&mdash;` entity (the
    /// file's standing typographic convention — see the `&ldquo;`/`&rdquo;`/
    /// `&beta;` entities beside it) and, like every paragraph in that file,
    /// hand-wraps its prose across source lines — a browser collapses that
    /// whitespace on render, but a raw `.contains` does not. Byte-identical
    /// is checked on the DECODED, WHITESPACE-COLLAPSED sentence, not the raw
    /// file bytes, so this pin cannot be satisfied by two prose strings that
    /// merely overlap — it requires the exact same words in the exact same
    /// order, dash included — while tolerating the file's own line wrapping.
    @Test func pccPolicySentenceNamesMemoryInBothHomes() throws {
        let memoryClause =
            "any notes you asked Talaria to remember and any earlier messages Talaria retrieves for that request"
        let fullSentence =
            "Your request leaves the device \u{2014} including any images you attached to that message and, if you have memory turned on, \(memoryClause)."

        let policyHTML = try Self.read("docs/privacy.html")
        let policyHTMLNormalized = Self.collapsedWhitespace(
            policyHTML.replacingOccurrences(of: "&mdash;", with: "\u{2014}"))
        #expect(policyHTMLNormalized.contains(memoryClause),
                "docs/privacy.html's PCC paragraph does not name memory")

        let appCopy = try Self.read("Talaria/Features/Settings/ConnectHostCopy.swift")
        let appCopyNormalized = Self.collapsedWhitespace(appCopy)
        #expect(appCopyNormalized.contains(memoryClause),
                "the app's PCC copy (ConnectHostCopy.privateCloudPolicySentence) does not name memory")

        #expect(policyHTMLNormalized.contains(fullSentence),
                "docs/privacy.html's PCC sentence has drifted from the pinned wording")
        #expect(appCopyNormalized.contains(fullSentence),
                "ConnectHostCopy.privateCloudPolicySentence has drifted from the pinned wording")
    }

    /// **#422 final review, I2 — the published policy describes the app it
    /// ships with.** `docs/privacy.html` is a GitHub Pages root, so merging
    /// this PR publishes it; a policy that does not mention the on-device
    /// memory index is a privacy document that omits the one feature that
    /// stores the user's own words. Whitespace-collapsed for the same reason
    /// the PCC sentence is: the file hand-wraps its prose.
    @Test func thePolicyDescribesTheOnDeviceMemoryStore() throws {
        let policy = Self.collapsedWhitespace(
            try Self.read("docs/privacy.html")
                .replacingOccurrences(of: "&mdash;", with: "\u{2014}")
                .replacingOccurrences(of: "&rarr;", with: "\u{2192}")
                .replacingOccurrences(of: "&beta;", with: "\u{03B2}"))

        for clause in [
            "keeps an on-device index of your own messages from your local chats",
            "any notes you asked it to remember",
            // **The corrected sentence, and the pin moved onto it.** The first
            // draft of this paragraph said the index and notes "never leave
            // your iPhone" \u{2014} false on the Private Cloud \u{03B2} path,
            // where the notes block and every retrieved chunk ride the prompt
            // to Apple's servers (`LocalChatBackend.memoryPrefix` has no tier
            // gate), and flatly contradicted this document's OWN PCC paragraph
            // twenty lines above. Pinning it made the falsehood load-bearing:
            // the suite would have defended the wrong sentence.
            "They stay on your iPhone unless you choose Private Cloud \u{03B2}, where a request carries the notes and any retrieved messages to Apple's Private Cloud Compute",
            "Turning the memory switch off stops both new indexing and any use of what is already stored",
            "Forget everything</strong>, under Settings \u{2192} Sessions \u{2192} Memory, erases the on-device memory index and every remembered note",
        ] {
            #expect(policy.contains(clause),
                    "the published policy no longer describes local memory: \(clause)")
        }

        #expect(!policy.contains("never leave your iPhone"), """
            the policy claims local memory never leaves the device \u{2014} it does, on every \
            Private Cloud \u{03B2} turn, exactly as this file's own PCC paragraph says
            """)
    }

    /// **I1 — the effective date revises with the change**, which is the file's
    /// own promise in its Changes clause. A policy edit that leaves the date
    /// behind tells a reader the text they are looking at is older than it is.
    @Test func thePolicysEffectiveDateMatchesThisChange() throws {
        let policy = try Self.read("docs/privacy.html")
        #expect(policy.contains("Effective: 2026-09-03"), """
            the policy text changed in this lane but its Effective date did not — the file's \
            own Changes clause promises the date revises with the change
            """)
    }

    /// **#433 — the "Your data, your controls" paragraph tells the truth
    /// about deletion.** The 2026-09-04 audit (A8) found the old sentence
    /// ("delete the app to remove everything local") false: a connected
    /// host's credentials are kept in the iOS Keychain by design (#41 —
    /// "survives … app deletion, which is the whole point"), specifically so
    /// a reinstall does not force a re-pair. This lane's corrected paragraph
    /// names that survival AND the control that clears it — Disconnect,
    /// under Settings → Connect Host, which only works before the app is
    /// deleted. RED on the untouched tree: the old sentence is still there.
    @Test func theControlsParagraphNamesKeychainSurvivalAndDisconnect() throws {
        let policy = try Self.read("docs/privacy.html")

        // The file hand-wraps its prose across source lines (this file's own
        // `collapsedWhitespace` note, above): the old sentence's raw bytes
        // are actually "delete the app to\n  remove everything local", so a
        // literal `.contains` on the UN-collapsed text never sees it and
        // this check would pass vacuously on the untouched tree.
        let policyCollapsed = Self.collapsedWhitespace(policy)
        #expect(!policyCollapsed.contains("delete the app to remove everything local"), """
            the privacy policy still claims deleting the app removes everything local — a \
            connected host's credentials survive in the iOS Keychain by design (#41), and \
            #433's audit found this sentence false
            """)

        let headingStart = try #require(
            policy.range(of: "<h2>Your data, your controls</h2>"),
            "the controls section heading is gone from docs/privacy.html — re-point this pin")
        let headingEnd = try #require(
            policy.range(of: "<h2>Children</h2>", range: headingStart.upperBound..<policy.endIndex),
            "the heading after the controls section is gone from docs/privacy.html — re-point this pin")
        let controlsParagraph = Self.collapsedWhitespace(String(policy[headingStart.upperBound..<headingEnd.lowerBound]))

        #expect(controlsParagraph.contains("Keychain"), """
            the controls paragraph no longer names the Keychain, where a disconnected-but-not- \
            deleted host's credentials continue to live
            """)
        #expect(controlsParagraph.contains("Disconnect"), """
            the controls paragraph no longer names Disconnect, the control that clears a \
            host's credentials from this device
            """)
    }

    /// Collapses any run of whitespace (including newlines) to a single
    /// space — a browser does the same to hand-wrapped HTML prose on render,
    /// so this is what makes "byte-identical" a claim about the WORDS rather
    /// than an accident of how a source file happens to be wrapped.
    private static func collapsedWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
