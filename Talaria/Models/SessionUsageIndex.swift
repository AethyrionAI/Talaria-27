import Foundation

/// Last-run token usage per server session id (#25) — the app-side cache
/// that gives the CTX gauge a numerator on RESUMED sessions.
///
/// Nothing on the wire exposes "tokens occupied by the last run's prompt"
/// for a stored session (probe 2026-07-16 against the live host):
/// - `GET /api/sessions/{id}/messages` carries a per-row `token_count` that
///   is **null on every row** — decoding it compiles, passes a hand-made
///   fixture, and renders 0% forever on real data.
/// - `GET /api/sessions` exposes session-level `input_tokens`, but it is
///   **cumulative across API calls** (each turn re-sends the whole history),
///   so dividing it by the context window over-reads superlinearly — a
///   10-message session measured 90% of a 128k window. That field is a
///   session-cost surface, never a context meter.
///
/// The only honest source is the `run.completed` usage the app already
/// parses on live turns; this index persists it keyed by session id so a
/// resume can read it back. Ids with no entry (sessions from another device,
/// or pre-dating this cache) stay unknown — the gauge hides rather than lies.
/// Follows the `SessionProfileIndex` overlay pattern: on-device only, stale
/// ids are harmless, `prune(keeping:)` drops them opportunistically.
struct SessionUsageIndex: Codable, Hashable, Sendable {
    var sessionUsages: [String: TokenUsage] = [:]

    func usage(forSessionID sessionID: String) -> TokenUsage? {
        sessionUsages[sessionID]
    }

    mutating func record(sessionID: String, usage: TokenUsage) {
        sessionUsages[sessionID] = usage
    }

    /// Drops entries for sessions not in `keeping` — call only with a set
    /// assembled from ALL profiles' fetches; a single-host fetch would prune
    /// the other host's sessions.
    mutating func prune(keeping sessionIDs: Set<String>) {
        sessionUsages = sessionUsages.filter { sessionIDs.contains($0.key) }
    }
}
