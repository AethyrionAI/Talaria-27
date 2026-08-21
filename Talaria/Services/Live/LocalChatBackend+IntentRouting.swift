import Foundation
import FoundationModels
import UIKit
import os

// Extracted from LocalChatBackend.swift (#216, 2026-08-01) — pure code motion.
//
// Per-turn tool-intent routing. The Bool router (#196) is PRODUCTION and is
// what decides whether a turn is armed with a device-tool belt at all; the
// `#if DEBUG` half is #217/#217B's intent-probe vocabulary and guides, which
// were measured and ABANDONED — kept because the probe is re-runnable, not
// because anything ships on them.
// MARK: - Per-turn tool-intent routing (#196, PROMOTED to production 2026-07-28)
//
// The production session architecture as of the battery-4 device verdict:
// every turn is classified by a few-shot guided-generation router before the
// session is built. Words-only turns get NO belt and the `toolless-lic2`
// instruction text (device: 60/60 content AND clean across the three #196
// prompts); device turns get the production armed session, byte-identical to
// the pre-promotion path. Router accuracy on device: 200/200, both
// directions; fail-safe on error is ARMED. WWDC26 session 242 sanctions the
// shape: tools withheld where "known to be irrelevant," decided contextually.

extension LocalChatBackend {

    /// Whether this launch routes turns. Production truth: always. DEBUG:
    /// only the `armed-routed` shape routes, so every legacy A/B cell
    /// (including the `armed` control) stays pure.
    static var turnRoutingEnabled: Bool {
        #if DEBUG
        return activeSessionShape == .armedRouted
        #else
        return true
        #endif
    }

    /// Few-shot router instructions — the ONLY framing that cleared the
    /// Mac-host probe grid (200/200 at n=20), reconfirmed 200/200 on the
    /// 27b4 device model. The guide-only framing misrouted EVERY creative
    /// verb to the device — the #196 task-verb confusion lives in
    /// classification too — and the flipped-polarity framing collapsed to
    /// always-true. Few-shot examples are Apple's own template convention.
    /// Pinned by tests: this text is a measured artifact, not prose.
    nonisolated static let toolIntentRouterInstructions = """
    You route requests for a phone assistant. Decide if a request needs the device or is answerable with words alone.
    Examples:
    "Write a haiku about rain" -> needsDeviceTool: false
    "Summarize the French Revolution in 50 words" -> needsDeviceTool: false
    "What's 15% of 80?" -> needsDeviceTool: false
    "Remind me to call Shelley tomorrow" -> needsDeviceTool: true
    "How did I sleep last night?" -> needsDeviceTool: true
    "What's the weather?" -> needsDeviceTool: true
    """

    /// Greedy + tiny cap: routing must be deterministic and fast (~0.6s
    /// measured on device); guided generation constrains decode to the
    /// `ToolIntentRoute` shape, so the router can never ramble.
    ///
    /// **Since #257 this 64 cap serves the PINNED ONE-FIELD shape only** —
    /// the probe control (`ToolIntentRouteSingleField`) and the #217 probe
    /// cells. Production's two-field route generates under
    /// `twoFieldRouterOptions` below. The pin stays load-bearing: raising
    /// this value would silently re-point the #196/#217 measured series.
    nonisolated static var toolIntentRouterOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 64)
    }

    /// #257: the TWO-field production route's own options — greedy, cap 128.
    /// Its own named constant, never a raised `toolIntentRouterOptions`,
    /// because of run `21F0C10D`'s exact failure: an 11-field schema reused
    /// the 64 cap, every generation truncated mid-JSON, the catch arm failed
    /// safe to ARMED, and 165/165 pure instrument errors read as a plausible
    /// behavioral verdict. Two Bools very probably fit 64 — "probably" is not
    /// the standard, so the cap is doubled and pinned by test.
    ///
    /// ⚠️ QUEUED DEVICE PRE-FLIGHT (#257 mandatory, before any measurement
    /// run): measure the two-field schema's real token cost with
    /// `tokenCount` ON DEVICE, outside a live turn — the test host reports
    /// `isAvailable == true` but throws Code=5000 on every generation
    /// (availability ≠ generability), so only a device can price this
    /// schema, and `tokenCount()` concurrent with a streaming turn kills
    /// the turn (ModelManagerError 1001).
    nonisolated static var twoFieldRouterOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 128)
    }

    /// #202A: the router framings. The live path routes through this enum,
    /// so a measured cell can never drift from the shipped router by being
    /// a copy of it. **Since the #202D promotion `ctxA` IS production and
    /// `control` is the pinned rollback** — see `productionRouterVariant`,
    /// which is the single source of truth for which one ships.
    enum RouterVariant: String, CaseIterable {
        /// PRE-#202D production, and now the PINNED ROLLBACK: raw current
        /// turn, no history. Context-blind by construction — that blindness
        /// was the #202 bug, measured at 6/6 misrouted accepts. **Not
        /// production since the 2026-07-30 promotion**; `.ctxA` is.
        case control
        /// The pinned instructions, unchanged; the prompt envelope gains
        /// one line naming what the assistant just said.
        case ctxA = "ctx-a"
        /// ctxA's envelope PLUS one added few-shot example showing the
        /// offer→accept shape, in case the envelope alone is simply
        /// off-distribution for a few-shot prompt of one-line requests.
        case ctxB = "ctx-b"
    }

    /// #202A: the instructions each variant routes under. control and ctxA
    /// share the PINNED text — ctxA's whole treatment is the envelope, so
    /// an instructions change here would make it two seams at once.
    /// #207 TEXT seam: one added example teaching that an attached image is
    /// a device request. **Kept OFF by default and measured only if the
    /// cheap signal seam fails** — this text has a 200/200 history and #196
    /// established that guide-only framing misrouted every creative verb, so
    /// it is not touched on a hunch.
    nonisolated static let imageGuideExample = """

    "[an image is attached] what does this say?" -> needsDeviceTool: true
    """

    nonisolated static func routerInstructions(for variant: RouterVariant,
                                               includeImageGuide: Bool = false) -> String {
        let base = baseRouterInstructions(for: variant)
        return includeImageGuide ? base + imageGuideExample : base
    }

    nonisolated static func baseRouterInstructions(for variant: RouterVariant) -> String {
        switch variant {
        case .control, .ctxA:
            return toolIntentRouterInstructions
        case .ctxB:
            return toolIntentRouterInstructions + """

            Assistant just said: "Would you like me to set a reminder for that?"
            "Yes please" -> needsDeviceTool: true
            """
        }
    }

    /// #202A: the prompt envelope per variant. control DISCARDS the context
    /// — pinned, because that discard is exactly the filed defect and a
    /// silent change here would erase the thing being measured.
    /// `applyContextCap` is TRUE for production and every ordinary call.
    /// The #206 probe passes FALSE to reproduce the uncapped failure — the
    /// cap lives inside this function, so without a bypass the instrument
    /// would truncate away the exact condition it exists to measure, and
    /// the run would come back clean for the wrong reason.
    /// `hasImage` is the #207 SIGNAL seam. Production hands the router the
    /// user's raw text while `hasImage` is computed six lines below the call
    /// and never passed — so "what does this say?" arrives with no
    /// indication a photo exists, and 0/15 routed toolless. OFF by default,
    /// so this is byte-identical to production until an arm turns it on.
    nonisolated static func routerPrompt(context: String, prompt: String,
                                         variant: RouterVariant,
                                         applyContextCap: Bool = true,
                                         hasImage: Bool = false) -> String {
        let prompt = hasImage ? "[an image is attached] \(prompt)" : prompt
        switch variant {
        case .control:
            return "Request: \(prompt)"
        case .ctxA, .ctxB:
            guard !context.isEmpty else { return "Request: \(prompt)" }
            return """
            Assistant just said: "\(applyContextCap ? routerContextTail(context) : context)"
            Request: \(prompt)
            """
        }
    }

    /// #206: the router context is capped to its TAIL. Two reasons, both
    /// measured: at ~4,000 chars routing latency doubled (0.63s → 1.32s) and
    /// a words-only row routed ARMED 0/5 — the first ctx-a failure recorded —
    /// while everything at ≤590 chars was perfect. **The tail, not the head:**
    /// an offer lands at the END of an assistant turn ("…Would you like me to
    /// set a reminder?"), which is precisely the part the router must see.
    ///
    /// `routerContextLimit` sits above every context measured clean (590) and
    /// well below the length that broke (4,073). A no-op for ordinary turns.
    nonisolated static let routerContextLimit = 800

    nonisolated static func routerContextTail(_ context: String) -> String {
        guard context.count > routerContextLimit else { return context }
        return "…" + String(context.suffix(routerContextLimit))
    }

    /// #202A candidate (fix direction 2): the bare accept forms, exhaustive
    /// and deterministic. Deliberately an exact set rather than a length
    /// threshold — "yes, but move it to Friday" and "No thanks" are both
    /// short and neither should inherit an armed route. Costs no generation,
    /// so it is measured as a REPORTED column, never a gated one: its real
    /// risk is that a wrong inherited route persists for the whole
    /// conversation, which only a two-turn run can see.
    nonisolated static let shortAffirmatives: Set<String> = [
        "yes", "yes please", "yeah", "yep", "yup", "sure", "ok", "okay",
        "go ahead", "please do", "do it", "sounds good", "please", "affirmative",
    ]

    /// Normalizes case, surrounding whitespace and trailing punctuation
    /// before the set lookup — "  Yes.  " and "Okay!" are the same accept.
    nonisolated static func isShortAffirmative(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.replacingOccurrences(
            of: "[\\p{P}\\p{S}]+$", with: "", options: .regularExpression
        )
        return shortAffirmatives.contains(stripped.lowercased())
    }

    /// #202D PROMOTION (2026-07-30): production routes with the previous
    /// assistant turn as context. The context-blind `.control` router
    /// misrouted **6/6** bare affirmatives after an offer (#202A) while
    /// scoring 17/17 on everything else, and ctx-a fixed 13/13 short rows
    /// and 10/10 long ones at no latency cost (#202C: 0.560s either way).
    /// **Rollback: `.control`**, still reachable as a measured probe cell.
    nonisolated static let productionRouterVariant: RouterVariant = .ctxA

    /// #207 PROMOTION (2026-07-31): production teaches the router that an
    /// attached image is a device request. Measured TWICE — image rows
    /// 1/4 → **4/4**, the #196 baseline untouched at **100/100**, and a photo
    /// carried alongside an unrelated request still routes TOOLLESS 2/2.
    ///
    /// **The signal and the guide are ONE mechanism in two places** — the
    /// guide teaches `marker → armed`, the signal supplies the marker, and
    /// the signal alone moved nothing (1/4, identical to production). They
    /// ship together. **Rollback: `false`**, which restores the pinned
    /// `@Guide` byte-for-byte and is reachable as the `img-signal` cell.
    nonisolated static let productionIncludesImageGuide = true

    /// #202D PROMOTION: the toolless branch's shipped text, in ONE place so
    /// the live path and the measured arm cannot drift apart. Production is
    /// the promoted `toolless-lic2` payload PLUS clause v2.
    /// **Rollback: drop `includeToollessHonestyClauseV2`** — that is exactly
    /// the `honesty-control` cell, measured at 9/10 broken turns.
    ///
    /// `includeToollessCapabilityIndex` is #297's pass-through: defaulted
    /// `false` so every existing call site (production's included) is
    /// unaffected, and here — not a copy of this function — is where a
    /// future DEBUG measured arm builds the treatment text, per #202D's
    /// "one place so the live path and the measured arm cannot drift" rule.
    /// Production does not flip it; that is Owen's call after bars
    /// 297-A/B/C clear on device.
    nonisolated static func productionToollessInstructions(
        deviceContext: String, date: Date = .now,
        // #385: defaulted so every battery and harness call site is
        // untouched — they all measure the on-device tier — while production
        // passes `activeTier` explicitly.
        tier: LocalModelTier = .onDevice,
        hasImageTools: Bool,
        includeToollessCapabilityIndex: Bool = false
    ) -> String {
        instructionsText(
            deviceContext: deviceContext, date: date, tier: tier,
            hasTools: false, hasImageTools: hasImageTools,
            includeToollessLic2Clause: true,
            includeToollessHonestyClauseV2: true,
            includeToollessCapabilityIndex: includeToollessCapabilityIndex
        )
    }

    /// Classifies one turn against the PRODUCTION variant. Fail-safe: any
    /// error routes to the ARMED session — full production behavior, tools
    /// available. `context` is the previous assistant turn (empty when the
    /// conversation has none, which makes ctx-a fall back to the bare
    /// production envelope).
    func routeNeedsDeviceTool(prompt: String, context: String = "",
                              hasImage: Bool = false) async -> Bool {
        (await routeTurn(prompt: prompt, context: context, hasImage: hasImage)).needsDeviceTool
    }

    /// #257: the production route, both fields. The capability Bool rides the
    /// SAME single generation as the gate Bool — no second router pass.
    func routeTurn(prompt: String, context: String = "",
                   hasImage: Bool = false) async
        -> (needsDeviceTool: Bool, isCapabilityQuestion: Bool) {
        await routeTurn(prompt: prompt, context: context,
                        variant: Self.productionRouterVariant,
                        hasImage: hasImage,
                        includeImageGuide: Self.productionIncludesImageGuide)
    }

    /// Bool-only view of the variant-parameterized router — kept so every
    /// pre-#257 probe call site keeps compiling and measures what production
    /// now generates (the two-field type).
    func routeNeedsDeviceTool(prompt: String, context: String,
                              variant: RouterVariant,
                              applyContextCap: Bool = true,
                              hasImage: Bool = false,
                              includeImageGuide: Bool = false) async -> Bool {
        (await routeTurn(prompt: prompt, context: context, variant: variant,
                         applyContextCap: applyContextCap, hasImage: hasImage,
                         includeImageGuide: includeImageGuide)).needsDeviceTool
    }

    /// The variant-parameterized router. **Production calls it with
    /// `productionRouterVariant` (`.ctxA` since the #202D promotion) and the
    /// previous assistant turn as context** — the live path and every
    /// measured cell are the SAME code, not copies of one behavior. The
    /// `.control` variant is the pinned rollback, still probe-reachable.
    ///
    /// #257 fail-safe shape, per field: `needsDeviceTool` fails safe ARMED
    /// (today's exact behavior — tools available, nothing lost);
    /// `isCapabilityQuestion` fails safe FALSE — **discovery fails OPEN**
    /// (#284's named design risk): an errored detection appends nothing and
    /// the model never has less than it has now.
    func routeTurn(prompt: String, context: String,
                   variant: RouterVariant,
                   applyContextCap: Bool = true,
                   hasImage: Bool = false,
                   includeImageGuide: Bool = false) async
        -> (needsDeviceTool: Bool, isCapabilityQuestion: Bool) {
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.routerInstructions(
                for: variant, includeImageGuide: includeImageGuide))
        )
        do {
            let route = try await session.respond(
                to: Prompt(Self.routerPrompt(context: context, prompt: prompt, variant: variant,
                                             applyContextCap: applyContextCap,
                                             hasImage: hasImage)),
                generating: ToolIntentRoute.self,
                options: Self.twoFieldRouterOptions
            ).content
            return (route.needsDeviceTool, route.isCapabilityQuestion)
        } catch {
            Self.logger.notice("router: classification failed — failing safe to armed (\(String(String(describing: error).prefix(80)), privacy: .public)) (#196)")
            #if DEBUG
            // #213: count it so a probe can report it. Production behaviour is
            // UNCHANGED — failing safe to armed is right for a live turn; what
            // was wrong was that the probe then scored the fallback as a
            // correct answer on every `expected: true` row.
            Self.routerFailureTally += 1
            #endif
            return (true, false)
        }
    }

    #if DEBUG
    /// #217: one turn classified against the V2 schema — the Bool AND the
    /// intent from a SINGLE generation.
    ///
    /// One generation rather than two on purpose. #215 measured the router at
    /// ~1s on a turn it arms; a second generation would double that and spend
    /// the entire #216 latency prize before any belt narrowed. The cost of
    /// doing it in one is that the extra field could degrade the Bool — which
    /// is not a risk to be argued about, it is this lane's regression gate.
    ///
    /// Fails safe the same way production does, and then some: a thrown
    /// generation returns `(true, .other)` — armed, full belt, today's exact
    /// behaviour.
    func routeIntent(prompt: String, context: String = "",
                     cell: IntentProbeCell = .narrowGuideV1,
                     hasImage: Bool = false) async -> (needsDeviceTool: Bool, intent: RouterIntent) {
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.routerInstructions(
                for: Self.productionRouterVariant,
                includeImageGuide: Self.productionIncludesImageGuide))
        )
        let prompt = Prompt(Self.routerPrompt(context: context, prompt: prompt,
                                              variant: Self.productionRouterVariant,
                                              hasImage: hasImage))
        let options = Self.toolIntentRouterOptions
        do {
            // The four cells differ ONLY in the @Generable type, because
            // `@Guide(.anyOf:)` is macro-expanded and cannot vary at runtime.
            // Session, prompt, instructions and options are identical across
            // all four, so the 2x2 is genuinely a 2x2.
            let raw: (Bool, String)
            switch cell {
            case .narrowGuideV1:
                let r = try await session.respond(to: prompt, generating: ToolIntentRouteV2.self, options: options).content
                raw = (r.needsDeviceTool, r.intent)
            case .narrowGuideV2:
                let r = try await session.respond(to: prompt, generating: ToolIntentRouteNarrowGuideV2.self, options: options).content
                raw = (r.needsDeviceTool, r.intent)
            case .fullGuideV1:
                let r = try await session.respond(to: prompt, generating: ToolIntentRouteFullGuideV1.self, options: options).content
                raw = (r.needsDeviceTool, r.intent)
            case .fullGuideV2:
                let r = try await session.respond(to: prompt, generating: ToolIntentRouteFullGuideV2.self, options: options).content
                raw = (r.needsDeviceTool, r.intent)
            }
            return (raw.0, RouterIntent(lenient: raw.1))
        } catch {
            Self.logger.notice("routeIntent: classification failed — failing safe to armed + .other (\(String(String(describing: error).prefix(80)), privacy: .public)) (#217)")
            Self.routerFailureTally += 1
            return (true, .other)
        }
    }

    /// #284: the vector probe's options. Same greedy determinism as
    /// production's router options, but the 11-field JSON needs ~90-110
    /// response tokens — the production cap of 64 truncated EVERY vector
    /// generation on device (run 21F0C10D: 165/165 errors), so the vector
    /// carries its own cap. Production's `toolIntentRouterOptions` is a
    /// measured artifact and stays untouched — this lives inside the same
    /// `#if DEBUG` region as `routeVector` (its only caller) rather than
    /// beside `toolIntentRouterOptions` at file scope, so the two options
    /// values can never be mistaken for interchangeable and travel together
    /// when Task 9 promotes `routeVector` out of DEBUG.
    nonisolated static var vectorRouterOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256)
    }

    /// #284 probe: one generation, the production router's exact session,
    /// instructions, prompt envelope, and options — modeled on `routeIntent`
    /// (#217), which proved a second field costs the gate nothing. Fails
    /// safe the same way production does: error → armed, no groups → full
    /// belt (O2).
    func routeVector(prompt: String, context: String = "",
                     hasImage: Bool = false) async
        -> (needsDeviceTool: Bool, groups: Set<CapabilityGroup>, raw: ToolIntentRouteVector?) {
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.routerInstructions(
                for: Self.productionRouterVariant,
                includeImageGuide: Self.productionIncludesImageGuide)))
        do {
            let route = try await session.respond(
                to: Prompt(Self.routerPrompt(context: context, prompt: prompt,
                                             variant: Self.productionRouterVariant,
                                             hasImage: hasImage)),
                generating: ToolIntentRouteVector.self,
                options: Self.vectorRouterOptions
            ).content
            return (route.needsDeviceTool, route.armedGroups, route)
        } catch {
            Self.logger.notice("routeVector: classification failed — failing safe to armed + full belt (\(String(String(describing: error).prefix(80)), privacy: .public)) (#284)")
            Self.routerFailureTally += 1
            return (true, [], nil)
        }
    }

    /// #257: the probe's CONTROL route — the pinned one-field shape under
    /// the pinned 64 cap, i.e. production's router exactly as it stood
    /// before the capability field. Same session build, same instructions,
    /// same prompt envelope as `routeTurn` — the treatment is the schema
    /// (and its cap) and nothing else, so bar 257-1-GATE's arm-vs-control
    /// contrast is genuinely one variable. Fails safe armed, tallied.
    func routeSingleFieldControl(prompt: String, context: String = "") async -> Bool {
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.routerInstructions(
                for: Self.productionRouterVariant,
                includeImageGuide: Self.productionIncludesImageGuide)))
        do {
            let route = try await session.respond(
                to: Prompt(Self.routerPrompt(context: context, prompt: prompt,
                                             variant: Self.productionRouterVariant)),
                generating: ToolIntentRouteSingleField.self,
                options: Self.toolIntentRouterOptions
            ).content
            return route.needsDeviceTool
        } catch {
            Self.logger.notice("routeSingleFieldControl: classification failed — failing safe to armed (\(String(String(describing: error).prefix(80)), privacy: .public)) (#257)")
            Self.routerFailureTally += 1
            return true
        }
    }

    /// #217B: the 2x2. Two candidate causes for #217's 12.5% dangerous rate —
    /// an incomplete vocabulary and a too-weak `other` guide — measured as
    /// MAIN EFFECTS rather than confounded into one candidate arm.
    enum IntentProbeCell: String, CaseIterable, Sendable {
        /// #217's exact cell. Control, and a WITHIN-run replication of a
        /// verdict that until now was only a cross-run number.
        case narrowGuideV1 = "narrow-v1"
        /// Guide effect, vocabulary held at #217's.
        case narrowGuideV2 = "narrow-v2"
        /// Vocabulary effect, guide held at #217's.
        case fullGuideV1 = "full-v1"
        /// Both — the candidate.
        case fullGuideV2 = "full-v2"

        /// Whether this cell offered the model the four added domains. Drives
        /// which expectation each grid row is scored against, so a row is never
        /// marked wrong for failing to say a word the cell never offered.
        var usesFullVocabulary: Bool {
            self == .fullGuideV1 || self == .fullGuideV2
        }
    }

    /// #213: router generations that THREW, counted so **every probe runner**
    /// can report per-row error counts instead of silently scoring a crash as
    /// a correct answer. Battery-scoped: each runner samples deltas around each
    /// row. Never read outside DEBUG, never affects a live turn.
    ///
    /// **The invariant, and it is source-level — no test can reach it:** a new
    /// `recordProbe` call site MUST pass `errors:`. Omitting it decodes as nil,
    /// which means "not sampled", NOT "zero errors" — and the classifier prints
    /// NOT RECORDED for such a run rather than scoring it. This comment named
    /// only `runRouterContextProbe` until 2026-08-01, which was the original
    /// §3.1 bug restated as documentation: the first #213 cut wired one runner
    /// while claiming all of them. All runners sample now (13/13 call sites
    /// carry `errors:`), and the invariant has held across every probe runner
    /// added since — which is the only evidence available for a rule the
    /// compiler cannot enforce.
    nonisolated(unsafe) static var routerFailureTally = 0
    #endif
}

/// The route classification for one turn. File scope: the `@Generable`
/// macro expansion needs a non-nested, non-private type. The @Guide text is
/// a measured artifact (pinned) — it carries the device-data/device-action
/// enumeration AND the explicit words-only enumeration.
///
/// **TWO fields since #257 (2026-08-09).** `isCapabilityQuestion` is Lever
/// 1's detection Bool — a Bool and never a "which capability" multiway,
/// because #217/#217B falsified multiway intent outright (zero safe misses
/// in 380 classifications) and named "a single extra Bool" as the surviving
/// hypothesis. Its guide follows the #217B v2 tactic: one positive test the
/// message must meet, no exclusion lists, no trap domains named. ONE
/// generation carries both fields (#217's latency reasoning — a second
/// router pass would double the ~1s routing cost). The pre-#257 one-field
/// shape survives as `ToolIntentRouteSingleField` (DEBUG), the probe's
/// pinned control arm.
@Generable
struct ToolIntentRoute {
    @Guide(description: "True only when the request needs the user's device data (health, location, weather, calendar, reminders, contacts, past chats) or a device action (create a reminder, calendar event, or alarm). Writing, poems, summaries, math, facts, and conversation are false — they need nothing from the device.")
    var needsDeviceTool: Bool

    @Guide(description: "true only if the user is asking what YOU can do, what you have access to, or what your features are")
    var isCapabilityQuestion: Bool
}

#if DEBUG
/// #284: the Bool-vector route — #217B's own surviving hypothesis. Ten
/// INDEPENDENT binaries instead of one multiway intent, because this
/// model abstains on binaries (200/200 lifetime) and never on a
/// multiway choice (zero safe misses in 380 classifications). Guides
/// follow the v2 tactic — a positive test each, certainty framing, no
/// exclusion lists, and none of the trap domains named (teach-to-the-
/// test discipline, #217B).
///
/// File scope for the same reason as `ToolIntentRoute` above: the
/// `@Generable` macro expansion needs a non-nested, non-private type — a
/// copy nested inside `extension LocalChatBackend` compiles but is only
/// reachable as `LocalChatBackend.ToolIntentRouteVector`, which is not
/// what callers (or this file's own `routeVector`) write.
///
/// DEBUG-only until the #284 probe clears its pre-registered bars; the
/// promotion commit moves this type out of `#if DEBUG` (#218).
@Generable
struct ToolIntentRouteVector {
    @Guide(description: "true only if replying needs to read from or act on this user's device right now")
    let needsDeviceTool: Bool
    @Guide(description: "true only if certain the user is asking about their calendar events or schedule, or to put something on the calendar")
    let wantsCalendar: Bool
    @Guide(description: "true only if certain the user is asking about their reminders or to-dos, or to create one")
    let wantsReminders: Bool
    @Guide(description: "true only if certain the user is asking to set, change, or ask about an alarm or wake-up time")
    let wantsAlarms: Bool
    @Guide(description: "true only if certain the user is asking about their own body or activity data: steps, sleep, workouts, heart rate")
    let wantsHealth: Bool
    @Guide(description: "true only if certain the user is asking about current or upcoming weather")
    let wantsWeather: Bool
    @Guide(description: "true only if certain the user is asking to find a place, business, or point of interest near them")
    let wantsPlaces: Bool
    @Guide(description: "true only if certain the user is asking about a person in their contacts: phone, email, address")
    let wantsContacts: Bool
    @Guide(description: "true only if certain the user is asking about something said in their own past conversations here")
    let wantsConversations: Bool
    @Guide(description: "true only if certain the user is asking about this device itself: battery, storage, network")
    let wantsDeviceStatus: Bool
    @Guide(description: "true only if certain the user is asking where they are right now")
    let wantsLocation: Bool

    var armedGroups: Set<CapabilityGroup> {
        var groups: Set<CapabilityGroup> = []
        if wantsCalendar { groups.insert(.calendar) }
        if wantsReminders { groups.insert(.reminders) }
        if wantsAlarms { groups.insert(.alarms) }
        if wantsHealth { groups.insert(.health) }
        if wantsWeather { groups.insert(.weather) }
        if wantsPlaces { groups.insert(.places) }
        if wantsContacts { groups.insert(.contacts) }
        if wantsConversations { groups.insert(.conversations) }
        if wantsDeviceStatus { groups.insert(.deviceStatus) }
        if wantsLocation { groups.insert(.location) }
        return groups
    }
}

// Everything below is a #217/#217B MEASURED ARTIFACT and is DEBUG-only.
// Production's router returns the `ToolIntentRoute` Bool above and never reads
// any of it. `RouterIntent` shipped UNGATED until 2026-08-01 — harmless (every
// consumer was already inside a DEBUG region, so it was unreachable) but it
// contradicted the tracker's "DEBUG-only measured artifacts" claim and put dead
// weight in Release. Gate found by the 2026-08-01 external audit, §6D.
//
// NOTE for whoever edits this boundary: the suite builds DEBUG, so a green
// suite proves NOTHING about this gate. Verify with a Release build.

/// #217: which DOMAIN a turn wants, when it wants one.
///
/// #216 priced the prize — scoping the calendar turn's belt took it from 6.1s
/// to 3.5s and from 2,269 input tokens to 976, with creates and composition
/// untouched — and named the blocker: `scopedBelt` keys on `promptTag`, which
/// exists only inside the battery harness. Production's router returns a Bool,
/// so it can decide WHETHER to arm and never WHAT to arm with.
///
/// **The asymmetry that shapes this type.** A Bool router that is wrong falls
/// back to the full belt, which is today's behaviour — the failure costs
/// nothing. An intent router that is wrong arms the WRONG belt, and a turn
/// needing `createCalendarEvent` while holding only health tools is **strictly
/// worse than arming everything**. So every failure path — an unparseable
/// answer, a thrown generation, a value from a vocabulary this build does not
/// know — must land on `.other`, and `.other` must mean the full belt.
///
/// A `String` constrained by `@Guide(.anyOf:)` rather than a `@Generable` enum:
/// `GenerationGuide.anyOf(_:)` is verified present in the beta-4
/// `swiftinterface`, and #209 already established exactly how a required
/// `String` misbehaves (a model with nothing to say emits `""`, it does not
/// omit the key). `init(lenient:)` is total, so that case is handled rather
/// than discovered.
enum RouterIntent: String, CaseIterable, Sendable {
    case reminder
    case alarm
    case calendar
    case weather
    case health
    /// #217B: the four domains #217 left out. Their absence was one of two
    /// candidate causes for that run's failure — on "when did I last text Sam"
    /// and "how much battery do I have left" the model had **no correct scoped
    /// answer available**, and substituted the nearest one it did have
    /// (`reminder` and `health`, both 10/10 deterministic).
    case conversations
    case device
    case contacts
    case places
    /// Everything else, and every failure. **Means the FULL belt** — exactly
    /// what production arms today.
    case other

    /// #217's vocabulary, **PINNED** — the six values that run was scored
    /// against. It is the control arm of #217B and must never drift, or the
    /// replication stops being one.
    nonisolated static let narrowVocabulary: [String] = [
        "reminder", "alarm", "calendar", "weather", "health", "other",
    ]

    /// #217B: every domain the belt actually has. Pinned equal to `allCases` by
    /// `theFullVocabularyIsExactlyTheParseableCases` — offering the model a
    /// value the parser cannot read would score it wrong for a reason that has
    /// nothing to do with the model.
    nonisolated static var fullVocabulary: [String] { allCases.map(\.rawValue) }

    /// What a row's answer SHOULD be under the narrow vocabulary: itself if it
    /// was on offer, `other` if it was not. Derived rather than hand-authored
    /// per cell, so a row cannot be scored against an expectation the cell
    /// never gave the model a way to express.
    var underNarrowVocabulary: RouterIntent {
        Self.narrowVocabulary.contains(rawValue) ? self : .other
    }

    /// Total by construction. Case and surrounding whitespace are forgiven —
    /// a model answering `"Calendar"` means calendar, and scoring that `.other`
    /// would understate accuracy for a formatting reason.
    init(lenient raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = RouterIntent(rawValue: key) ?? .other
    }

    /// Whether this intent would narrow the belt. `.other` is the only one that
    /// does not — pinned, so a case can never become silently inert and be
    /// scored as a win it did not earn.
    var scopesTheBelt: Bool { self != .other }
}

/// #217/#217B: the probe's route types. **All four are deliberately separate
/// from `ToolIntentRoute`, which production uses and which no lane in this
/// family touches.**
///
/// Four types rather than one parameterized type because `@Guide(.anyOf:)` is
/// macro-expanded and static — a vocabulary and a guide text cannot vary at
/// runtime. Verbose, but each becomes a PINNED artifact, which is what a
/// measured cell needs to be anyway.
///
/// The `needsDeviceTool` guide is **byte-identical across all four** so the
/// regression gate compares like with like.
enum IntentRouterGuide {
    /// The Bool guide, verbatim from production's `ToolIntentRoute`. Shared by
    /// every cell so the gate measures the intent field's cost and nothing else.
    static let boolGuide = "True only when the request needs the user's device data (health, location, weather, calendar, reminders, contacts, past chats) or a device action (create a reminder, calendar event, or alarm). Writing, poems, summaries, math, facts, and conversation are false — they need nothing from the device."

    /// **v1 — #217's guide, PINNED.** It already NAMED contacts, past chats,
    /// places and device status as `other` cases, and already said in as many
    /// words that guessing is worse. The model ignored all of it and answered
    /// `reminder` for "when did I last text Sam" 10/10. **That is why v2 is not
    /// simply a longer exclusion list** — listing exclusions demonstrably does
    /// not work on this model.
    static let intentGuideV1 = "Which kind of device information or action the request needs. Use \"other\" whenever the request needs no device data at all, or when it needs something outside this list — contacts, past chats, places, the device's own status, or anything you are unsure about. Guessing is worse than answering \"other\"."

    /// **v2 — a different TACTIC, not a longer list.** Three changes:
    /// `other` is framed as the DEFAULT rather than the fallback; each category
    /// gets a positive test it must meet ("only for…"); and the instruction is
    /// a rule about certainty rather than an enumeration of exceptions.
    ///
    /// It deliberately does NOT name messages, battery, music or navigation.
    /// Naming #217's two failures would teach to the test and make the bar
    /// unfalsifiable — the out-of-vocabulary rows in the grid are chosen to be
    /// things this text never mentions.
    static let intentGuideV2 = "Answer \"other\" unless the request is unmistakably one of the named categories. A category is correct ONLY if the request asks for that exact thing: \"reminder\" only for the user's reminder or to-do list, \"alarm\" only for a clock alarm, \"calendar\" only for calendar events, \"weather\" only for forecast or conditions, \"health\" only for the user's own body data such as steps, sleep or heart rate. If the request is merely RELATED to a category, or needs anything not named here, the answer is \"other\". \"other\" is always safe; a wrong category is not."
}

/// #257: the PINNED one-field control — byte-for-byte the production
/// `ToolIntentRoute` as it stood before the capability field (its guide is
/// `IntentRouterGuide.boolGuide`, the shared verbatim copy of the measured
/// Bool guide). The capability-detection probe's control arm generates this
/// under the pinned 64-token `toolIntentRouterOptions`, so 1-GATE compares
/// the two-field arm against yesterday's exact router in the same run.
@Generable
struct ToolIntentRouteSingleField {
    @Guide(description: IntentRouterGuide.boolGuide)
    var needsDeviceTool: Bool
}

/// narrow vocabulary + v1 guide — **#217's exact cell, byte-for-byte.** The
/// control arm, and a within-run replication of a verdict that was previously
/// only a cross-run number.
@Generable
struct ToolIntentRouteV2 {
    @Guide(description: IntentRouterGuide.boolGuide)
    var needsDeviceTool: Bool

    @Guide(description: IntentRouterGuide.intentGuideV1, .anyOf(RouterIntent.narrowVocabulary))
    var intent: String
}

/// narrow vocabulary + v2 guide — isolates the GUIDE effect.
@Generable
struct ToolIntentRouteNarrowGuideV2 {
    @Guide(description: IntentRouterGuide.boolGuide)
    var needsDeviceTool: Bool

    @Guide(description: IntentRouterGuide.intentGuideV2, .anyOf(RouterIntent.narrowVocabulary))
    var intent: String
}

/// full vocabulary + v1 guide — isolates the VOCABULARY effect.
@Generable
struct ToolIntentRouteFullGuideV1 {
    @Guide(description: IntentRouterGuide.boolGuide)
    var needsDeviceTool: Bool

    @Guide(description: IntentRouterGuide.intentGuideV1, .anyOf(RouterIntent.fullVocabulary))
    var intent: String
}

/// full vocabulary + v2 guide — the candidate.
@Generable
struct ToolIntentRouteFullGuideV2 {
    @Guide(description: IntentRouterGuide.boolGuide)
    var needsDeviceTool: Bool

    @Guide(description: IntentRouterGuide.intentGuideV2, .anyOf(RouterIntent.fullVocabulary))
    var intent: String
}
#endif
