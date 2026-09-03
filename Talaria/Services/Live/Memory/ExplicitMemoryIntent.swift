import Foundation

/// #422 bar 422-E — the deterministic "Remember that…" capture.
///
/// **No model in the loop, and no paraphrase (ruling 1).** This is fixed
/// string matching against a trigger list; the text after the trigger is
/// returned VERBATIM — the user's own words, byte-for-byte, minus the
/// trigger phrase and surrounding whitespace. Nothing here re-words,
/// summarizes, or corrects anything the user typed.
///
/// **Reminders are a different verb and never match.** `remember to …` /
/// `remind me …` / `set a reminder …` name a FUTURE ACTION (the #200-series
/// reminder family) — `that` is what introduces a FACT to be stored. The
/// trigger list is deliberately `"remember that "`, never `"remember "`, so
/// the two families can never be confused by a substring match.
enum ExplicitMemoryIntent {
    static let triggers = [
        "please remember that ", "remember that ", "remember: ", "don't forget that ",
        "do not forget that ", "note that ", "for future reference, ",
    ]

    /// Owen's ruling: an over-long note is saved as its first 500 characters,
    /// with a visible notice (the Memory screen, Task 16) — never silently
    /// truncated and never summarized to fit.
    static let noteLengthCap = 500

    /// The user's words minus the trigger, verbatim — no model in the loop.
    /// `remember to…` / `remind me…` are REMINDERS (the #200-series) and
    /// never match: `that` introduces a fact.
    static func parse(_ prompt: String) -> String? {
        parseResult(prompt)?.note
    }

    /// Same match as `parse`, plus whether the 500-char cap actually cut the
    /// user's words. The Memory screen (Task 16) shows a visible notice when
    /// `truncated == true`; this task only exposes the fact — see #422
    /// Task 11's controller notes ("the notice UI lands with the Memory
    /// screen").
    static func parseResult(_ prompt: String) -> (note: String, truncated: Bool)? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for trigger in triggers where lower.hasPrefix(trigger) {
            let body = String(trimmed.dropFirst(trigger.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            let capped = String(body.prefix(noteLengthCap))
            return (note: capped, truncated: capped.count < body.count)
        }
        return nil
    }
}
