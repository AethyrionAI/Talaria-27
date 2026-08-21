import EventKit
import Foundation
import FoundationModels

// Side-effecting device tools (#29). Every one of these goes through the
// ToolConfirmationCenter — staged, shown as a card in the transcript,
// executed only on explicit approve. Deny returns a "user declined" result
// the model reacts to conversationally; nothing is ever created silently.

// MARK: - #337-F: the confirmation-card clause, named

/// The sentence every action tool's description ends with, isolated so a
/// measurement can remove it without retyping the description around it.
///
/// **This is a MEASUREMENT seam, not a fix.** #337-A's production turn replied
/// *"**Confirmation card:** A reminder to 'take out the trash' at 8 AM has been
/// created"* — the app's own affordance, imitated in prose, with no card and no
/// tool call. The candidate mechanism, filed with a text pointer and explicitly
/// NOT elected, is that the phrase is taught by these very descriptions. 337-F
/// measures that; nothing here changes what production ships, and the stripped
/// variants that use it live behind `#if DEBUG`.
///
/// Deliberately NOT `#if DEBUG` itself: production reads nothing from this
/// enum, but a text constant that only exists in Debug is one refactor away
/// from #218's failure — `main` unable to build in Release for two days
/// because a promoted clause stayed inside a DEBUG block. Costing Release an
/// unused enum is the cheaper side of that trade.
enum DeviceActionClauses {

    /// The clause as it appears on `createReminder` and `createCalendarEvent`.
    static let cardClauseCreated =
        " The user sees a confirmation card and can edit or cancel before anything is created."

    /// The clause as it appears on `scheduleAlarm` — same sentence, different
    /// final verb. Two constants rather than a regex: an A/B whose
    /// manipulation is defined by a pattern is an A/B that can silently start
    /// matching more or less than it did.
    static let cardClauseScheduled =
        " The user sees a confirmation card and can edit or cancel before anything is scheduled."

    /// The armed INSTRUCTIONS' own mention, which no tool description carries.
    /// The 337-F treatment arms remove the tool-description clause; this is
    /// the second exposure site, and naming it is what lets the entry say
    /// honestly that a null result in the tools-only arm exonerates nothing.
    static let armedBlurbCardSentence =
        " Every action tool shows the user a confirmation card first; if they decline, accept it gracefully."

    /// #337-F-2b — the REPLACEMENT under measurement, not a promotion.
    ///
    /// 337-F-2 established that `armedBlurbCardSentence` alone is sufficient
    /// for both the UI impersonation (0/90 imitations in every blurb-removed
    /// cell vs 8/60 control) and the missing tool calls (90/90 vs 48/60). But
    /// deleting it deletes the DECLINE guidance with it, and the three-create
    /// prompt set never exercises that path — 30/30 of the isolating arm's
    /// calls were made, so no trial there was ever declined.
    ///
    /// This keeps the decline instruction and drops the vocabulary. **It loses
    /// the word "confirmation" outright rather than only "card", because BOTH
    /// observed specimens are seeded by it** — `"**Confirmation card:**"`
    /// (#337-A, production) and `"Here's the confirmation…"` (run `A7AB9960`).
    /// A replacement that kept "confirmation" would leave half the seed in
    /// place and make a null uninterpretable.
    ///
    /// ~~**Production still ships `armedBlurbCardSentence`.** This string is
    /// reachable only from the `blurb-reworded` arm.~~
    /// **✅ PROMOTED 2026-08-15 on Owen's ruling — THIS IS WHAT SHIPS**, via
    /// `armedBlurbShippingSentence` below. Evidence: 0/30 imitations and 29/30
    /// tool calls in its own arm, from the last and worst slot at `serious`
    /// thermal, against a control that replicated at 4/4/3 imitations and
    /// 23/25/26 calls across three runs; pooled blurb-removed cells 0/90 and
    /// 90/90 vs 8/60 and 48/60 (p = 0.0005, p = 8.1e-06).
    static let armedBlurbCardSentenceReworded337F2 =
        " Every action tool asks the user to approve it before anything changes; if they decline, accept that gracefully."

    /// **THE SENTENCE PRODUCTION ACTUALLY SHIPS.** One name, so a future
    /// promotion moves this alias and every arm follows automatically.
    ///
    /// Before 2026-08-15 the shipping text lived in TWO places — this enum and
    /// a byte-identical literal inside `instructionsText` — while every #337-F
    /// arm manipulated the enum copy by exact string match. Nothing enforced
    /// that they agreed. Promoting by editing the literal alone would have left
    /// all three manipulating arms stripping a sentence production no longer
    /// contained; `cardClauseInstructions` returns `removed:` precisely so that
    /// shows up in the artifact rather than reading as a null, but the honest
    /// fix is not to have two copies.
    static let armedBlurbShippingSentence = armedBlurbCardSentenceReworded337F2

    /// The PINNED ROLLBACK — the pre-promotion sentence, kept verbatim.
    ///
    /// `armedBlurbCardSentence` above IS this text and is deliberately NOT
    /// edited: it is the measured artifact of every #337-F run, and rewriting
    /// it would silently invalidate those numbers. This alias exists so the
    /// rollback is reachable BY INTENT rather than by remembering which of two
    /// similarly-named constants used to ship.
    ///
    /// **⚠️ CONSEQUENCE FOR THE ARMS, and it is the `armed-cardfix` precedent
    /// (#200K) repeating:** the `blurb-reworded` arm substitutes
    /// `armedBlurbCardSentence` → reworded, and production no longer contains
    /// the former, so that arm is now **IDENTITY WITH CONTROL** and its
    /// `reworded=` manipulation row will report the substitution did nothing.
    /// That is correct and expected post-promotion — it is not a broken cell —
    /// but it means the arm can no longer measure the promotion. **Measuring a
    /// promoted clause requires a ROLLBACK arm that substitutes the other way**,
    /// which is #200L's shape and is not built here.
    static let armedBlurbSentencePre337F2b = armedBlurbCardSentence

    /// Removes whichever of the two clause forms is present, and NOTHING else.
    /// A description with neither comes back unchanged — which is a fact the
    /// caller is expected to check rather than assume away.
    static func strippingCardClause(from description: String) -> String {
        description
            .replacingOccurrences(of: cardClauseCreated, with: "")
            .replacingOccurrences(of: cardClauseScheduled, with: "")
    }
}

// MARK: - Shared parsing (unit-tested)

enum DeviceActionParsing {

    /// Tolerant date-time parser for tool arguments and card edits:
    /// ISO 8601 with or without seconds/timezone ("2026-07-08T09:00",
    /// "2026-07-08T09:00:00Z"), and the human "2026-07-08 09:00" /
    /// date-only "2026-07-08" forms. Nil for empty or unreadable input —
    /// callers treat nil as "no date", never guess one.
    nonisolated static func parseDateTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoWithZone = ISO8601DateFormatter()
        isoWithZone.formatOptions = [.withInternetDateTime]
        if let date = isoWithZone.date(from: trimmed) { return date }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = .current // local wall-clock time, as a person means it
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Card/display form of an optional date, honest about absence.
    nonisolated static func displayDate(_ date: Date?) -> String {
        guard let date else { return "None" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// #233: the wee-hour window — hours 0–6 (00:00–06:59 local). A due
    /// time here is at least as likely the model's half-day default as the
    /// user's actual ask ("tomorrow at 4" arrived as T04:00), so the create
    /// tool treats the first one per conversation as a question.
    nonisolated static func isEarlyMorning(_ date: Date) -> Bool {
        Calendar.current.component(.hour, from: date) <= 6
    }

    /// #249: a due already elapsed. Five minutes of grace absorb staging
    /// latency and "right now" asks; the observed defect cards were hours
    /// stale, so the grace costs no detection.
    nonisolated static func isPastDue(_ date: Date, now: Date) -> Bool {
        date < now.addingTimeInterval(-300)
    }

    /// #249: an evening ask resolved to the next morning — due lands
    /// 07:00–11:59 on the next calendar day of the ask. The model's
    /// half-day-default shape one hour outside #233's wee-hour net;
    /// hours 0–6 stay the wee-hour ask's.
    nonisolated static func isNextMorning(_ date: Date, askedAt now: Date) -> Bool {
        let calendar = Calendar.current
        guard calendar.component(.hour, from: now) >= 17,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              calendar.isDate(date, inSameDayAs: tomorrow) else { return false }
        let hour = calendar.component(.hour, from: date)
        return hour >= 7 && hour <= 11
    }

    // MARK: - #340 route (a): the app owns the DAY, the model owns the TIME

    /// A **bare clock time** — hours, optionally minutes, optionally an am/pm
    /// marker, and **no date component at all**. Returns hour+minute only.
    ///
    /// **`nil` for anything carrying a date, and that is bar 340-H2 rather
    /// than an implementation shortcut.** A date the model supplied is the
    /// model's to own: the app resolves the DAY only where none was given.
    /// Silently rolling an explicit past date forward would trade this
    /// entry's defect for a worse one — the user asked for a date and got a
    /// different one — which is exactly the case #249's past-due guard exists
    /// to ASK about rather than guess.
    ///
    /// **Why this is the right half to automate, measured rather than
    /// assumed.** 340-G: guided to fill the field, the model sent four
    /// byte-identical `2026-08-15T16:30` at 18:21 local — today at the asked
    /// clock time, already elapsed. It took its guide's first clause and
    /// dropped *"or tomorrow's if that time has already passed today."*
    /// **The model can produce the time and cannot produce the day.**
    ///
    /// Deliberately strict. `"1630"` and `"0930"` are rejected rather than
    /// guessed at — a four-digit run is as easily a typo as a time, and this
    /// function's output goes straight into a reminder the user was told
    /// about.
    nonisolated static func parseBareClock(_ raw: String) -> DateComponents? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")   // "a.m." -> "am"
        guard !text.isEmpty else { return nil }
        // Any date separator disqualifies the string outright (340-H2). ISO
        // forms are `parseDateTime`'s and must stay there.
        guard !text.contains("-"), !text.contains("/") else { return nil }

        var marker: String?
        if text.hasSuffix("am") { marker = "am"; text = String(text.dropLast(2)) }
        else if text.hasSuffix("pm") { marker = "pm"; text = String(text.dropLast(2)) }
        text = text.trimmingCharacters(in: .whitespaces)

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let hourText = parts[0]
        guard !hourText.isEmpty, hourText.count <= 2,
              hourText.allSatisfy(\.isNumber), var hour = Int(hourText) else { return nil }

        var minute = 0
        if parts.count == 2 {
            let minuteText = parts[1]
            // Exactly two digits: "9:5" is not 9:05, it is malformed, and
            // reading it either way would be a guess.
            guard minuteText.count == 2, minuteText.allSatisfy(\.isNumber),
                  let parsed = Int(minuteText) else { return nil }
            minute = parsed
        }
        guard (0...59).contains(minute) else { return nil }

        switch marker {
        case "am":
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }              // 12am is midnight
        case "pm":
            guard (1...12).contains(hour) else { return nil }
            if hour != 12 { hour += 12 }            // 12pm is noon
        default:
            // No marker: a 24-hour clock. "11" therefore means 11:00, and the
            // next 11:00 may be tomorrow — see `resolveBareClock`. Reading a
            // bare "11" as "tonight" would be a guess about intent, and #233's
            // wee-hour guard already covers the one range where guessing is
            // dangerous.
            guard (0...23).contains(hour) else { return nil }
        }
        return DateComponents(hour: hour, minute: minute)
    }

    /// The **next occurrence** of a bare clock time: today when that time is
    /// still ahead, tomorrow when it has passed.
    ///
    /// **This is #256's own bounce text, in code.** Production already tells
    /// the model, verbatim, *"The user most likely means the next time that
    /// clock time comes around"* — we have been stating the correct rule in
    /// prose and asking the model to apply it. It does not. This applies it.
    ///
    /// **The grace is `isPastDue`'s, shared rather than restated.** Two
    /// thresholds would let the app resolve a time its own past-due guard then
    /// bounces — a loop wearing the shape of a fix.
    ///
    /// `nil` only when the calendar cannot form the date at all (a DST gap can
    /// do this), and a nil here means NO DUE — never a guessed one.
    nonisolated static func resolveBareClock(_ clock: DateComponents, now: Date) -> Date? {
        let calendar = Calendar.current
        guard let hour = clock.hour, let minute = clock.minute,
              let today = calendar.date(bySettingHour: hour, minute: minute,
                                        second: 0, of: now)
        else { return nil }
        guard isPastDue(today, now: now) else { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// Time-only display form for the card's caution row.
    nonisolated static func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Duration-in-minutes from a card field: plain integers, clamped to a
    /// sane meeting range. Nil for unparseable input.
    nonisolated static func parseDurationMinutes(_ raw: String) -> Int? {
        let digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "minutes", with: "")
            .replacingOccurrences(of: "min", with: "")
            .replacingOccurrences(of: "m", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Int(digits), value > 0 else { return nil }
        return min(value, 24 * 60)
    }
}

// MARK: - Create reminder (EventKit)

struct ReminderCreateTool: Tool {
    let name = "createReminder"
    /// Production description text — the default at every production call
    /// site, so the shipping belt is byte-identical with or without the
    /// #196 seam below.
    static let productionDescription = "Create a reminder in the user's Reminders app. The user sees a confirmation card and can edit or cancel before anything is created."
    #if DEBUG
    /// #196 second battery, `armed-remfix` / `armed-fix` treatment: scope
    /// the tool against task-verb confusion — the first battery measured
    /// production armed grabbing this tool on 8/10 "write a haiku" requests
    /// (the model parses the creative verb as a todo). Measurement cells
    /// only; production ships this text ONLY after a battery verdict.
    static let scopedDescription196 = "Create a reminder in the user's Reminders app, only when the user asks to be reminded of something or to save a to-do for later — never for requests to write, compose, or answer something now. The user sees a confirmation card and can edit or cancel before anything is created."

    /// #200B `armed-toolfix` / `armed-bothfix` treatment: the FILED #200
    /// table measured remind 0/20 with 15/20 trials interrogating the
    /// OPTIONAL `list` (± due) field instead of defaulting. This text
    /// targets the stall at the tool level. Measurement cells only;
    /// production ships it ONLY after a battery verdict.
    static let destalledDescription200 = productionDescription + " Create it immediately with the details given; missing fields default — never ask a clarifying question first."

    /// #337 bar 337-F treatment: production's description with the
    /// confirmation-card sentence REMOVED, and nothing else touched.
    ///
    /// Derived by removal rather than retyped, because a retyped "identical
    /// except for one clause" is one typo away from measuring two changes.
    /// `DeviceActionClauses.cardClauseCreated` is the exact substring; a test
    /// asserts the removal actually removed something, which is the guard
    /// against the whole A/B silently becoming a no-op the day someone
    /// rewords production.
    static let cardClauseStripped337 =
        DeviceActionClauses.strippingCardClause(from: productionDescription)
    #endif
    /// `var` + init default (#196): the battery's shaped belt copies this
    /// tool and swaps ONLY this string; production call sites never pass it.
    var description: String = ReminderCreateTool.productionDescription
    /// FoundationModels' schema-injection gate, surfaced as a stored var so
    /// the third battery's `armed-noschema` cell can flip copies (#196).
    /// Production call sites never pass it; the default matches the
    /// framework default (pinned by `frameworkDefaultInjectsSchemasIntoInstructions`),
    /// so the shipping belt is byte-identical with the seam in place.
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    // #200S PROMOTION: `due` and `list` are OPTIONAL in the schema. They
    // were required, while the promoted #200D clause told the model to
    // leave them empty — and asking the user is a rational way to satisfy
    // a required field. Measured twice (#200Q, #200R): remind 20/20 pooled
    // with ZERO zero-tool stalls vs 17/20 with three. `title` stays
    // required: the schema should demand what the tool cannot default.
    // `ReminderCreateToolRequiredFields` is the pinned rollback.
    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded about, e.g. \"Call Shelley\".")
        var title: String
        @Guide(description: "Due date and time like \"2026-07-08T09:00\" (local time), or empty for no due date.")
        var due: String?
        @Guide(description: "Reminders list name, or empty for the default list.")
        var list: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: title) { return refusal }
        defer { Task { await relay.completed(name) } }
        // An omitted field lands on exactly the path an empty string took,
        // so the create flow is unchanged from the pre-promotion tool.
        return await Self.performCreate(
            rawTitle: title, rawDue: arguments.due ?? "", rawList: arguments.list ?? "",
            relay: relay, confirmations: confirmations
        )
    }

    /// The whole create flow from staged-title to EventKit save, shared
    /// with the #200B guidefix copy so a treatment cell's ONLY delta is
    /// text — structural-identity discipline: two structs, one engine.
    nonisolated static func performCreate(
        rawTitle: String, rawDue: String, rawList: String,
        relay: ToolEventRelay,
        confirmations: ToolConfirmationCenter,
        now: Date = Date()
    ) async -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "No reminder title was given — nothing staged." }

        // #340 route (a), ruled by Owen 2026-08-18. The model can produce the
        // TIME and cannot produce the DAY (340-G: every value it sent was
        // today at the asked hour, already elapsed), so a bare clock time is
        // resolved HERE rather than delegated back to the model in prose.
        // An explicit date is left exactly as sent — 340-H2 — and falls
        // through to the three guards below unchanged.
        let explicitDue = DeviceActionParsing.parseDateTime(rawDue)
        let bareClock = explicitDue == nil ? DeviceActionParsing.parseBareClock(rawDue) : nil
        let resolvedBareClock = bareClock.flatMap {
            DeviceActionParsing.resolveBareClock($0, now: now)
        }
        let parsedDue = explicitDue ?? resolvedBareClock
        // #249 instrument: raw model-supplied due vs the parsed local time.
        // A zone-bearing raw string takes the ISO branch and gets CONVERTED
        // to local — a DST-wrong offset (-06:00 in summer Chicago) lands the
        // card an hour off what the user said, indistinguishable at the UI
        // from the model resolving the hour wrong. This line is the
        // discriminator.
        if TalariaLog.isVerbose {
            TalariaLog.logger.notice("createReminder due raw=\"\(rawDue, privacy: .public)\" bareClock=\(resolvedBareClock != nil ? "resolved" : (bareClock != nil ? "unresolvable" : "no"), privacy: .public) parsed=\(parsedDue.map { DeviceActionParsing.displayDate($0) } ?? "nil", privacy: .public)")
        }
        // #249 guard 1: a due already in the past is never what the user
        // meant — two of the three observed cards were hours stale at
        // staging. Checked BEFORE the wee-hour ask (a stale wee-hour due is
        // first a stale due). Same contract as #233: tool OUTPUT never a
        // throw (#197), an executed call not a refusal (#232), one bounce
        // per conversation, and the 233-E hardening — lead with the
        // negative, carry no formatted date to mine.
        if let parsedDue, DeviceActionParsing.isPastDue(parsedDue, now: now),
           await relay.claimPastDueAsk() {
            // #256 sharpening (249-E residue): the open-ended "what future
            // time" left the model narrating a failure; steering it toward
            // the nearest future reading of the same clock hour gets "8"
            // asked at 6:59 PM answered with an offer of tonight.
            return "No reminder was created. The requested due time has already passed. The user most likely means the next time that clock time comes around — ask whether they meant later today or tomorrow, then create the reminder with the time they confirm."
        }
        // #233: the model qualifies bare hours before the tool ever runs
        // ("tomorrow at 4" arrived here as T04:00), so the ambiguity is
        // invisible by now — the first wee-hour due per conversation is
        // treated as a question, not an order. Ordinary tool OUTPUT, never
        // a throw (#197); an EXECUTED call, not a governor refusal (#232's
        // counter must not move). The latch admits the re-call, so a
        // user-confirmed "yes, 4 AM" cannot loop.
        if let parsedDue, DeviceActionParsing.isEarlyMorning(parsedDue),
           await relay.claimEarlyMorningAsk() {
            // 233-E device falsification (2026-08-03, build 1870): the model
            // mined the old wording's displayDate into a FABRICATED "has been
            // set for Aug 4, 2026 at 5:00 AM" reply. The hardened form leads
            // with the negative and carries NO formatted date — nothing to
            // mine into a success claim; the user's own message already names
            // the hour the ask refers to.
            return "No reminder was created. The requested due time falls in the early morning (midnight to 7 AM). Ask the user whether they meant AM or PM, then create the reminder with the time they confirm."
        }
        // #249 guard 2: an evening ask whose due landed the next morning —
        // the half-day-default shape ("at 8" asked 10 PM → tomorrow 08:00)
        // one hour outside the wee-hour net. Own latch, same contract.
        if let parsedDue, DeviceActionParsing.isNextMorning(parsedDue, askedAt: now),
           await relay.claimEveningClockAsk() {
            // 249F (2026-08-06): the 9:02 PM live firing mined the old
            // wording's "the due time landed the next morning" into a
            // fabricated "was set for the next morning" — even behind the
            // leading negative. The sharpened form hands the model a
            // verbatim quoted question to parrot (#200J) and keeps every
            // set/landed-flavored verb out of the prose around it; the
            // quote's own negative needs word-DELETION to flip, a harder
            // mining error than the word-drop that burned 233-E.
            return "No reminder was created. Evening requests that resolve to the next morning are usually a misread clock time. Reply to the user with exactly this question: \"Nothing is scheduled yet — did you mean tonight or tomorrow morning?\" Then create the reminder with the time they confirm."
        }
        let decision = await confirmations.requestConfirmation(
            title: "Create this reminder?",
            detail: nil,
            caution: Self.dueCaution(for: parsedDue, now: now),
            fields: [
                .init(key: "title", label: "Title", value: title),
                .init(key: "due", label: "Due", value: parsedDue.map { DeviceActionParsing.displayDate($0) } ?? ""),
                .init(key: "list", label: "List", value: rawList.trimmingCharacters(in: .whitespacesAndNewlines)),
            ]
        )
        guard case .approved(let values) = decision else {
            return "The user declined — no reminder was created."
        }

        // Edited card values are what get created (#29 acceptance).
        let finalTitle = (values["title"] ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTitle.isEmpty else { return "The edited title was empty — no reminder was created." }
        let dueRaw = (values["due"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // `now` is threaded rather than defaulted: a card edit resolved against
        // a different clock than the one this call was staged with would be a
        // second source of truth for "today", and #340's whole subject is
        // which day a bare time means.
        let finalDue = Self.resolveEditedDate(edited: dueRaw, original: parsedDue, now: now)
        if !dueRaw.isEmpty, dueRaw.lowercased() != "none", finalDue == nil {
            return "Couldn't read \"\(dueRaw)\" as a date — no reminder was created. Try 2026-07-08T09:00, or just a clock time like 18:00."
        }
        let listName = (values["list"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            guard granted else { return "Reminders permission was not granted — nothing was created." }
        case .fullAccess:
            break
        default:
            return "Reminders permission is not granted — nothing was created. The user can enable it in Settings → Privacy & Security → Reminders."
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = finalTitle
        if let finalDue {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: finalDue
            )
        }
        #if DEBUG
        // #331: under the harness EVERY write lands in the dedicated test
        // list — the container beats a model-named list, because containment
        // that a generated argument can steer out of is not containment. A
        // container we cannot provision is a hard stop, never a quiet
        // fall-through to the user's real list.
        if await confirmations.autoAcceptForBattery {
            do {
                reminder.calendar = try BatteryTestContainer.ensureContainer(for: .reminder, in: store)
            } catch {
                return "The #331 battery test list could not be provisioned (\(error.localizedDescription)) — nothing was created."
            }
        } else if !listName.isEmpty,
                  let match = store.calendars(for: .reminder).first(where: {
                      $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
                  }) {
            reminder.calendar = match
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }
        #else
        if !listName.isEmpty,
           let match = store.calendars(for: .reminder).first(where: {
               $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
           }) {
            reminder.calendar = match
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }
        #endif
        guard let calendarTitle = reminder.calendar?.title else {
            return "No Reminders list is available on this device — nothing was created."
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            return "Creating the reminder failed: \(error.localizedDescription)"
        }
        let dueLine = finalDue.map { " due \(DeviceActionParsing.displayDate($0))" } ?? ""
        // #200F: the SAVED title may carry the battery reap marker; the
        // success text echoes the model-requested form (marker stripped).
        return "Created reminder \"\(ToolConfirmationCenter.strippingBatteryMarker(finalTitle))\"\(dueLine) in list \"\(calendarTitle)\"."
    }

    /// #233: the card's last line of defense for a wee-hour due — the case
    /// where the model ignored the bounce, or the user confirmed AM. Nil
    /// for daytime dues so normal cards render byte-identically to today.
    nonisolated static func earlyMorningCaution(for date: Date?) -> String? {
        guard let date, DeviceActionParsing.isEarlyMorning(date) else { return nil }
        return "EARLY MORNING — \(DeviceActionParsing.timeOnly(date))"
    }

    /// #249: the card's single caution row, first match wins — past-due
    /// beats wee-hour beats next-morning; nil for ordinary dues so normal
    /// cards render byte-identically to today. The past-due row carries the
    /// full date (the stale due may be yesterday's); the clock-shaped rows
    /// carry time only, matching #233's precedent.
    nonisolated static func dueCaution(for date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        if DeviceActionParsing.isPastDue(date, now: now) {
            return "IN THE PAST — \(DeviceActionParsing.displayDate(date))"
        }
        if let earlyMorning = earlyMorningCaution(for: date) { return earlyMorning }
        if DeviceActionParsing.isNextMorning(date, askedAt: now) {
            return "NEXT MORNING — \(DeviceActionParsing.timeOnly(date))"
        }
        return nil
    }

    /// "None"/empty keeps no date; an unchanged display string keeps the
    /// original parse; anything else must re-parse.
    /// #340: the CARD-EDIT path, and it carries a defect of its own that has
    /// nothing to do with the model.
    ///
    /// The Due field is user-editable, and a user typing a plain `"18:00"`
    /// got *"Couldn't read \"18:00\" as a date"* — a rejection of the most
    /// natural thing to type into a field labelled Due. Route (a)'s resolution
    /// serves this path too, and unlike the tool path it needs no model
    /// behaviour to change, so it is a fix that lands today.
    ///
    /// Order matters: `parseDateTime` first, so an explicit date the user
    /// typed keeps its day (340-H2 applies to people as well as models).
    nonisolated static func resolveEditedDate(edited: String, original: Date?,
                                              now: Date = Date()) -> Date? {
        if edited.isEmpty || edited.lowercased() == "none" { return nil }
        if let original, edited == DeviceActionParsing.displayDate(original) { return original }
        if let explicit = DeviceActionParsing.parseDateTime(edited) { return explicit }
        guard let clock = DeviceActionParsing.parseBareClock(edited) else { return nil }
        return DeviceActionParsing.resolveBareClock(clock, now: now)
    }
}

extension ReminderCreateTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "createReminder",
        semanticDescription: "Creates a reminder, behind the user's confirmation card.",
        source: .device, group: .reminders, riskClass: .write,
        permissions: ["Reminders"], argumentSummary: "title + due date")
}

#if DEBUG
// MARK: - #200B guidefix treatment copy

/// The `armed-schemarollback` cell's reminder tool (#200S): the
/// PRE-PROMOTION tool verbatim — `due` and `list` non-optional, so the
/// schema marks them REQUIRED again. A type change cannot ride a Bool
/// flag, so this struct IS the pinned rollback seam, and it is reachable
/// as a measured cell exactly like #200L's card-clause rollback.
///
/// Everything else is production: same name, same description, same
/// @Guide texts, same create flow. If the promotion ever needs to come
/// out, this is what production reverts to.
struct ReminderCreateToolRequiredFields: Tool {
    let name = "createReminder"
    var description: String = ReminderCreateTool.productionDescription
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded about, e.g. \"Call Shelley\".")
        var title: String
        @Guide(description: "Due date and time like \"2026-07-08T09:00\" (local time), or empty for no due date.")
        var due: String
        @Guide(description: "Reminders list name, or empty for the default list.")
        var list: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: title) { return refusal }
        defer { Task { await relay.completed(name) } }
        return await ReminderCreateTool.performCreate(
            rawTitle: title, rawDue: arguments.due, rawList: arguments.list,
            relay: relay, confirmations: confirmations
        )
    }
}

/// The `armed-guidefix` / `armed-bothfix` cell's reminder tool: identical
/// to `ReminderCreateTool` in name, flow, and engine — the ONLY deltas are
/// the `@Guide` texts on the optional fields, de-stalled against the FILED
/// #200 finding (15/20 remind trials interrogate `list` ± `due` instead of
/// defaulting; the single-field alarm tool runs 19/20). `@Guide` is a
/// macro, so this must be a copy struct — the description-var seam can't
/// reach it. The @Guide texts are the measured artifact; they have no
/// runtime accessor, so they're pinned here by comment and measured by the
/// battery itself. Measurement cells only; production ships this ONLY
/// after a battery verdict.
///
/// **⚠️ CORRECTION 2026-08-15 (#340) — "the ONLY deltas are the @Guide texts"
/// IS NO LONGER TRUE, AND THE COMMENT WAS RIGHT WHEN IT WAS WRITTEN.** This
/// struct declares `due`/`list` as non-optional `String`. Production declared
/// them the same way until **#200S** promoted them to `String?`, and that
/// promotion silently turned this cell into a TWO-delta arm: the @Guide texts
/// AND the schema optionality. Its honest control is therefore
/// `armed-schemarollback` (same optionality, production @Guide), **not** a
/// production-schema cell — comparing it against production measures the guide
/// change and #200S's rollback together and cannot separate them.
///
/// Nothing is changed here: the struct IS the measured artifact of the runs that
/// used it, and editing it would invalidate them. Any future cell that wants to
/// isolate a @Guide change against PRODUCTION must declare `due`/`list` as
/// `String?`, or it will move the schema too and reproduce this confound.
struct ReminderCreateToolGuidefix: Tool {
    let name = "createReminder"
    /// Production description by default — the @Guide delta is this cell's
    /// only change; `armed-bothfix` passes the destalled description.
    var description: String = ReminderCreateTool.productionDescription
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded about, e.g. \"Call Shelley\".")
        var title: String
        @Guide(description: "Due date and time like \"2026-07-08T09:00\" (local time), or empty for no due date. Use exactly the time the user gave — never ask for more date detail.")
        var due: String
        @Guide(description: "Reminders list name. Empty is correct when the user didn't name one — the default list is used; never ask which list.")
        var list: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: title) { return refusal }
        defer { Task { await relay.completed(name) } }
        return await ReminderCreateTool.performCreate(
            rawTitle: title, rawDue: arguments.due, rawList: arguments.list,
            relay: relay, confirmations: confirmations
        )
    }
}

/// The `armed-dateguide` cell's reminder tool (#340): the candidate fix for the
/// measured omission, at the layer the FALSIFIED one was not.
///
/// **What was measured, in order, because the order is the argument.** Fifteen
/// production calls on 2026-08-15 carried exactly ONE correct due date, and it
/// was the only day-bearing prompt (*"tomorrow at 4"* → `2026-08-16T16:00`).
/// Time-only prompts — *"at 4"*, *"at 4pm"* — sent `raw=""` every time; explicit
/// meridiem did not help. Then **340-F falsified the instructions-layer fix**:
/// #200K's `dayDefaultClause` ("a time with no day means the next time that
/// clock time comes around") produced **0 due dates in 14 calls**, identical to
/// control at 100% omission.
///
/// So the remaining candidate is the layer that describes the FIELD rather than
/// the behaviour: production's `due` guide still offers *"…or empty for no due
/// date"* as a co-equal option and never says to resolve a bare time. **This arm
/// exists because something was falsified, not because it seemed plausible.**
///
/// **The ONLY delta from `ReminderCreateTool` is this `due` @Guide text**, and
/// `due` stays `String?` deliberately — that is why this is a new struct rather
/// than a reuse of `ReminderCreateToolGuidefix`, which declares `due`/`list`
/// non-optional and so moves the schema too (see the correction on it).
///
/// Not a promotion. `@Guide` has no runtime accessor, so the text is pinned here
/// by comment and measured by the battery; production ships this only on a
/// verdict, and the verdict is Owen's.
struct ReminderCreateToolDateguide: Tool {
    let name = "createReminder"
    var description: String = ReminderCreateTool.productionDescription
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded about, e.g. \"Call Shelley\".")
        var title: String
        // Three deltas, each aimed at something measured: RESOLVE a bare time
        // against today rather than omitting it (the 9/9 signature); say what to
        // do when that time has already passed (#249's guard bounces a stale
        // due, and "in 20 minutes" produced a value 6.5 hours in the past); and
        // demote "empty" from a co-equal option to the narrow case it covers.
        @Guide(description: "Due date and time like \"2026-07-08T09:00\" (local time). If the user gives a time without saying which day, use TODAY's date — or tomorrow's if that time has already passed today. Leave empty ONLY when the user asked for no due date at all.")
        var due: String?
        @Guide(description: "Reminders list name, or empty for the default list.")
        var list: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: title) { return refusal }
        defer { Task { await relay.completed(name) } }
        return await ReminderCreateTool.performCreate(
            rawTitle: title, rawDue: arguments.due ?? "", rawList: arguments.list ?? "",
            relay: relay, confirmations: confirmations
        )
    }
}

/// #340 route (a)'s MODEL-FACING half, and it is a CELL rather than a
/// promotion — deliberately.
///
/// The app-side resolution shipped to production: it is deterministic, it is
/// unit-tested, and it fixes the card-edit path with no dependence on model
/// behaviour. **This guide text did not**, because the only comparable prior
/// change moved a number the wrong way as well as the right one: 340-G's
/// `armed-dateguide` cut omission 19/19 → 11/15 (p = 0.029) **and cut tool
/// calls 19/20 → 14/20** (p = 0.092, flagged at 340-G4). A guide that buys
/// due dates by costing calls is not obviously an improvement, and #340 has
/// already spent two candidates on prose that read well and measured badly.
/// So it rides here until 340-H5 says otherwise.
///
/// **What it asks for is strictly LESS than `dateguide` asked for.** That
/// arm's second clause — *"or tomorrow's if that time has already passed
/// today"* — is exactly the sentence the model demonstrably dropped, and it is
/// now `DeviceActionParsing.resolveBareClock`'s job. This text asks only for
/// the clock time the user said, and says the app works out the day, so
/// there is no date arithmetic left in the model's half to get wrong.
///
/// Production description, production schema, production create flow: the
/// ONLY delta is the `due` guide string, which is what makes the cell a
/// measurement of that string rather than of a bundle.
///
/// (No `#if DEBUG` of its own — this file's treatment section is already
/// inside one, and nesting a second left the outer block unclosed.)
struct ReminderCreateToolBareclock: Tool {
    let name = "createReminder"
    var description: String = ReminderCreateTool.productionDescription
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded about, e.g. \"Call Shelley\".")
        var title: String
        @Guide(description: "Due time. Give just the clock time the user said, like \"16:30\" or \"9am\" — the app works out which day it means. Use a full \"2026-07-08T09:00\" only when the user named a specific date. Leave empty ONLY when the user asked for no due date at all.")
        var due: String?
        @Guide(description: "Reminders list name, or empty for the default list.")
        var list: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: title) { return refusal }
        defer { Task { await relay.completed(name) } }
        return await ReminderCreateTool.performCreate(
            rawTitle: title, rawDue: arguments.due ?? "", rawList: arguments.list ?? "",
            relay: relay, confirmations: confirmations
        )
    }
}
#endif

// MARK: - Create calendar event (EventKit)

struct CalendarEventTool: Tool {
    let name = "createCalendarEvent"
    /// Production description text, hoisted to a static so the #200T
    /// optional-field copy can be pinned as production-identical on
    /// everything except the two field types.
    static let productionDescription = "Create a calendar event. The user sees a confirmation card and can edit or cancel before anything is created."
    #if DEBUG
    /// #337 bar 337-F treatment — see `ReminderCreateTool.cardClauseStripped337`.
    static let cardClauseStripped337 =
        DeviceActionClauses.strippingCardClause(from: productionDescription)
    #endif
    /// `var` + init default, the #196 seam this tool did not have: #337-F
    /// needs to swap ONLY this string on a copy, and a `let` cannot be
    /// swapped. **The default is the same static production shipped before,
    /// so the shipping belt is byte-identical** — production call sites never
    /// pass a description.
    var description: String = CalendarEventTool.productionDescription
    /// #196 `armed-noschema` seam — see `ReminderCreateTool`'s twin. The
    /// default matches the framework default; production never passes it.
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    // #200X PROMOTION: `durationMinutes` and `location` are OPTIONAL in the
    // schema. They were required, so the model had to produce values the
    // request never gave — and it satisfied `location` by GEOLOCATING THE
    // USER. Warm, production-last, pre-registered (#200W): production invented
    // a location in 5 of its 8 calendar creates, twice writing the home street
    // address onto a lunch, while the optional-field arm invented zero;
    // `currentLocation` went 7/10 → 0/10 (p≈0.003), the second independent
    // observation after #200T's exploratory 9/10 → 2/9.
    //
    // `title`/`startsAt` stay required: the schema should demand what the tool
    // genuinely cannot default. `CalendarEventToolRequiredFields` is the
    // pinned rollback.
    @Generable
    struct Arguments {
        @Guide(description: "Event title, e.g. \"Dentist\".")
        var title: String
        @Guide(description: "Start date and time like \"2026-07-08T09:00\" (local time).")
        var startsAt: String
        @Guide(description: "Duration in minutes, e.g. 30.")
        var durationMinutes: Int?
        @Guide(description: "Optional location, or empty.")
        var location: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: title) { return refusal }
        defer { Task { await relay.completed(name) } }
        // An omitted location lands on exactly the path an empty string took;
        // an omitted duration takes the shared engine's hour.
        return await Self.performCreate(
            rawTitle: title, rawStartsAt: arguments.startsAt,
            rawMinutes: arguments.durationMinutes, rawLocation: arguments.location ?? "",
            confirmations: confirmations
        )
    }

    /// Duration resolution in one place: a SUPPLIED value clamps to
    /// 5…1440 exactly as production always has, and `nil` — reachable only
    /// from the #200T optional-field copy, since the production schema
    /// requires the field — takes the humane hour. The confirmation card
    /// shows Minutes either way, so the user can edit before the save.
    nonisolated static func resolveMinutes(_ raw: Int?) -> Int {
        guard let raw else { return 60 }
        return min(max(raw, 5), 24 * 60)
    }

    /// #224 Phase 0: the card's caution row for a staged event start. Two
    /// deterministic rules — the same two the reminder card has carried since
    /// #233 and #249 — a start already in the past, and a wee-hour start (the
    /// AM/PM misread). First match wins; nil for ordinary starts, so an
    /// ordinary event card renders byte-identically to pre-#224.
    ///
    /// ORDERING matches the reminder card's (#249-C): a start both stale AND
    /// wee-hour reads as stale first, because an event that starts in the past
    /// is a plain failure whichever hour it names.
    ///
    /// The wording carries **no formatted date or time**. That is the #233-E /
    /// #249-F rule: the model has twice mined a formatted timestamp out of a
    /// tool string into a fabricated "has been set for …" success claim. Every
    /// row #224 Phase 0 adds is digit-free, pinned by
    /// `phase0CautionRowsCarryNothingMineable` rather than by review. The
    /// REMINDER card's own rows still carry their `displayDate`/`timeOnly`:
    /// they predate the rule, they are #233/#249's shipped and
    /// device-validated surface, and rewriting them is not what Owen balloted.
    nonisolated static func startCaution(for date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        if DeviceActionParsing.isPastDue(date, now: now) {
            return "STARTS IN THE PAST"
        }
        if DeviceActionParsing.isEarlyMorning(date) {
            return "EARLY MORNING START — CHECK AM/PM"
        }
        return nil
    }

    /// The whole create flow from staged-title to EventKit save, shared
    /// with the #200T optional-field copy so that cell's ONLY delta is the
    /// two field types — structural-identity discipline: two structs, one
    /// engine (the #200Q/#200S reminder precedent).
    ///
    /// `now` is injectable for the same reason the reminder engine's is: the
    /// caution rules read a clock, and a test that cannot set the clock can
    /// only measure boundaries by luck. Production never passes it.
    nonisolated static func performCreate(
        rawTitle: String, rawStartsAt: String, rawMinutes: Int?, rawLocation: String,
        confirmations: ToolConfirmationCenter,
        now: Date = Date()
    ) async -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "No event title was given — nothing staged." }
        guard let start = DeviceActionParsing.parseDateTime(rawStartsAt) else {
            return "Couldn't read \"\(rawStartsAt)\" as the start time — nothing staged. Use the form 2026-07-08T09:00."
        }
        let minutes = resolveMinutes(rawMinutes)

        let decision = await confirmations.requestConfirmation(
            title: "Add this event to the calendar?",
            detail: nil,
            caution: Self.startCaution(for: start, now: now),
            fields: [
                .init(key: "title", label: "Title", value: title),
                .init(key: "startsAt", label: "Starts", value: DeviceActionParsing.displayDate(start)),
                .init(key: "duration", label: "Minutes", value: String(minutes)),
                .init(key: "location", label: "Location", value: rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)),
            ]
        )
        guard case .approved(let values) = decision else {
            return "The user declined — no event was created."
        }

        let finalTitle = (values["title"] ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTitle.isEmpty else { return "The edited title was empty — no event was created." }
        let startRaw = (values["startsAt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalStart: Date
        if startRaw == DeviceActionParsing.displayDate(start) {
            finalStart = start
        } else if let reparsed = DeviceActionParsing.parseDateTime(startRaw) {
            finalStart = reparsed
        } else {
            return "Couldn't read \"\(startRaw)\" as the start time — no event was created."
        }
        let finalMinutes = DeviceActionParsing.parseDurationMinutes(values["duration"] ?? "") ?? minutes
        let finalLocation = (values["location"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            // Full access is the honest ask — Talaria also READS calendars,
            // and priming write-only here would leave the reader unable to
            // ever re-prompt (#186). Apple's sheet still offers "Add Events
            // Only": the request reports that pick as false, so re-read the
            // settled status — a write-only grant authorizes this save.
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            if !granted, EKEventStore.authorizationStatus(for: .event) != .writeOnly {
                return "Calendar permission was not granted — nothing was created."
            }
        case .fullAccess, .writeOnly:
            // .writeOnly authorizes exactly this tool's one operation —
            // save(_:span:commit:) — a narrower grant is not a denial (#186).
            break
        default:
            return "Calendar permission is not granted — nothing was created. The user can enable it in Settings → Privacy & Security → Calendars."
        }

        let event = EKEvent(eventStore: store)
        event.title = finalTitle
        event.startDate = finalStart
        event.endDate = finalStart.addingTimeInterval(TimeInterval(finalMinutes * 60))
        if !finalLocation.isEmpty { event.location = finalLocation }
        // #331: under the harness the event lands in the dedicated test
        // calendar; production resolves the default exactly as before, and
        // the whole container branch compiles out of Release.
        let calendar: EKCalendar
        #if DEBUG
        if await confirmations.autoAcceptForBattery {
            do {
                calendar = try BatteryTestContainer.ensureContainer(for: .event, in: store)
            } catch {
                return "The #331 battery test calendar could not be provisioned (\(error.localizedDescription)) — nothing was created."
            }
        } else if let resolved = store.defaultCalendarForNewEvents {
            calendar = resolved
        } else {
            return "No calendar is available for new events — nothing was created."
        }
        #else
        guard let resolved = store.defaultCalendarForNewEvents else {
            return "No calendar is available for new events — nothing was created."
        }
        calendar = resolved
        #endif
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            return "Creating the event failed: \(error.localizedDescription)"
        }
        // #200F: the SAVED title may carry the battery reap marker; the
        // success text echoes the model-requested form (marker stripped).
        return "Added \"\(ToolConfirmationCenter.strippingBatteryMarker(finalTitle))\" on \(DeviceActionParsing.displayDate(finalStart)) for \(finalMinutes) minutes\(finalLocation.isEmpty ? "" : " at \(finalLocation)") to \"\(calendar.title)\"."
    }
}

extension CalendarEventTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "createCalendarEvent",
        semanticDescription: "Creates a calendar event, behind the user's confirmation card.",
        source: .device, group: .calendar, riskClass: .write,
        permissions: ["Calendars"], argumentSummary: "title + start/end")
}

#if DEBUG
/// PRE-PROMOTION tool verbatim — `durationMinutes` and `location`
/// non-optional, so the schema marks them REQUIRED again. A type change
/// cannot ride a Bool flag, so this struct IS the pinned rollback seam for
/// the #200X promotion, and it is reachable as a measured cell exactly like
/// #200S's reminder rollback.
///
/// Everything else is production: same name, same description, same @Guide
/// texts, same create engine. If the promotion ever needs to come out, this
/// is what production reverts to.
///
/// What it restores, so the cost of reverting is on the record: with
/// `location` required the model geolocated the user to fill it, inventing a
/// place for 5 of 8 creates on a prompt that named none (#200W).
struct CalendarEventToolRequiredFields: Tool {
    let name = "createCalendarEvent"
    let description = CalendarEventTool.productionDescription
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter

    @Generable
    struct Arguments {
        @Guide(description: "Event title, e.g. \"Dentist\".")
        var title: String
        @Guide(description: "Start date and time like \"2026-07-08T09:00\" (local time).")
        var startsAt: String
        @Guide(description: "Duration in minutes, e.g. 30.")
        var durationMinutes: Int
        @Guide(description: "Optional location, or empty.")
        var location: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: title) { return refusal }
        defer { Task { await relay.completed(name) } }
        return await CalendarEventTool.performCreate(
            rawTitle: title, rawStartsAt: arguments.startsAt,
            rawMinutes: arguments.durationMinutes, rawLocation: arguments.location,
            confirmations: confirmations
        )
    }
}
#endif

// MARK: - Alarm / timer (AlarmKit via the #16 executor)

struct AlarmTool: Tool {
    let name = "scheduleAlarm"
    /// Production description text, hoisted to a static for the same reason
    /// the other two action tools hoisted theirs: a measurement cell must be
    /// able to name production's exact bytes rather than a copy of them.
    static let productionDescription = "Schedule an alarm or countdown timer on this iPhone (it rings through Silent mode). The user sees a confirmation card and can edit or cancel before anything is scheduled."
    #if DEBUG
    /// #337 bar 337-F treatment — see `ReminderCreateTool.cardClauseStripped337`.
    /// The alarm clause ends "…before anything is **scheduled**", which is why
    /// the stripper matches both endings rather than one.
    static let cardClauseStripped337 =
        DeviceActionClauses.strippingCardClause(from: productionDescription)
    #endif
    /// `var` + init default, the #196 seam this tool did not have (#337-F).
    /// The default is production's own static, so the shipping belt is
    /// byte-identical; production call sites never pass a description.
    var description: String = AlarmTool.productionDescription
    /// #196 `armed-noschema` seam — see `ReminderCreateTool`'s twin. The
    /// default matches the framework default; production never passes it.
    var includesSchemaInInstructions: Bool = true
    let relay: ToolEventRelay
    let confirmations: ToolConfirmationCenter
    let alarmService: AlarmService

    @Generable
    struct Arguments {
        @Guide(description: "The alarm or timer request, e.g. \"6:30am wake up\", \"18:45\", or \"25m tea\".")
        var request: String
    }

    /// #224 Phase 0: the alarm card's caution row. The #16 grammar resolves
    /// to a wall-clock time or a countdown, never to a date, so both rules
    /// read the REQUEST against `now` rather than a parsed due:
    ///
    /// * a wee-hour fixed time (hours 0–6) is #233's AM/PM misread arriving
    ///   through a different door — "wake me at 4" is far more often 4 PM;
    /// * a fixed time whose occurrence TODAY has already passed, beyond
    ///   #249's five-minute grace, will not ring today at all —
    ///   `AlarmService.nextOccurrence` rolls it to tomorrow, and the card
    ///   shows only the raw request string, so nothing else on it says which
    ///   day it rings.
    ///
    /// A countdown trips neither: it is always in the future and has no clock
    /// hour to misread.
    ///
    /// PRECEDENCE runs the OPPOSITE way from `CalendarEventTool.startCaution`
    /// and `ReminderCreateTool.dueCaution`, deliberately. A past-due reminder
    /// or event is a plain failure, so "in the past" is the sharper thing to
    /// say. A past-due ALARM still rings — one day later — so the softer
    /// signal must never mask the wee-hour one, which is the defect #233
    /// exists to raise.
    ///
    /// No formatted date or time, for the #233-E / #249-F reason spelled out
    /// on `CalendarEventTool.startCaution`.
    nonisolated static func caution(
        for request: AlarmService.AlarmRequest,
        now: Date,
        calendar: Calendar = .current
    ) -> String? {
        // A local wall-clock time that does not exist on `now`'s day (a
        // spring-forward gap) is not evidence of anything — say nothing
        // rather than guess.
        guard case .fixedTime(let hour, let minute) = request.kind,
              let todayAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
        else { return nil }
        if DeviceActionParsing.isEarlyMorning(todayAt) {
            return "EARLY MORNING — CHECK AM/PM"
        }
        if DeviceActionParsing.isPastDue(todayAt, now: now) {
            return "ALREADY PASSED TODAY — RINGS TOMORROW"
        }
        return nil
    }

    func call(arguments: Arguments) async throws -> String {
        let raw = arguments.request.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: raw) { return refusal }
        defer { Task { await relay.completed(name) } }

        // #16's grammar + executor, unchanged: parse → stage → explicit
        // confirm → AlarmService.schedule. Same authority rule, same wording.
        guard let request = AlarmService.parse(raw) else {
            return "Couldn't read a time from \"\(raw)\" — nothing staged. Formats: 6:30am, 18:45, or 25m."
        }
        let decision = await confirmations.requestConfirmation(
            title: "Schedule on this iPhone?",
            detail: "It will ring through Silent mode and Focus.",
            caution: Self.caution(for: request, now: Date()),
            fields: [.init(key: "request", label: "Alarm", value: raw)]
        )
        guard case .approved(let values) = decision else {
            return "The user declined — no \(request.kindNoun) was scheduled."
        }

        // An edited request re-parses through the same #16 grammar.
        let finalRaw = (values["request"] ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let finalRequest = finalRaw == raw ? request : AlarmService.parse(finalRaw) else {
            return "Couldn't read a time from the edited \"\(finalRaw)\" — nothing was scheduled."
        }
        do {
            try await alarmService.schedule(finalRequest)
            // #200F: the SCHEDULED request keeps the battery reap marker in
            // its label (that is how the teardown finds the alarm) — the
            // success text re-parses the cleaned raw so the echoed summary
            // is the model-requested form, marker-free.
            let echo = AlarmService.parse(ToolConfirmationCenter.strippingBatteryMarker(finalRaw)) ?? finalRequest
            return "Scheduled \(echo.summary) — it will ring through Silent mode and Focus."
        } catch {
            return "Couldn't schedule the \(finalRequest.kindNoun): \(error.localizedDescription)"
        }
    }
}

extension AlarmTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "scheduleAlarm",
        semanticDescription: "Schedules an alarm, behind the user's confirmation card.",
        source: .device, group: .alarms, riskClass: .write,
        permissions: ["Alarms"], argumentSummary: "time + optional label")
}
