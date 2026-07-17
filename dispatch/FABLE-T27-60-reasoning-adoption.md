# ⛔ ALREADY SHIPPED — DO NOT DISPATCH
# Merged to main before 2026-07-16 (see OPEN_ITEMS entry). Kept for the record.
# Dead-dispatch incident 2026-07-16: staleness passes MUST check merged-PR
# state (git log --grep / gh pr list) before refreshing any spec.

# FABLE-T27-60 — Adopt `run.completed` reasoning_content; never show the answer as reasoning

**OPEN_ITEMS:** #60 (probe complete 2026-07-13; this is the app-side fix track)
**Branch:** `claude/t27-60-reasoning-adoption-<suffix>` off `main`
**Scope (hard):** `Talaria/Services/Live/SessionsHermesClient.swift`, ONE guarded line-region in `Talaria/Stores/ChatStore.swift` (~467–473), `TalariaTests/ReasoningChannelTests.swift`. NO new files → NO xcodegen, NO pbxproj churn.

## Context — the wire truth (probed 2026-07-13, raw capture dissected)

The gateway's `tool.progress`/`_thinking` event is DEFECTIVE upstream: it carries
the ASSISTANT ANSWER verbatim (single cumulative event at end-of-stream), not
reasoning. The model's REAL reasoning is delivered only in the terminal
`run.completed` payload, per-message:

```
event: run.completed
data: {"session_id":"…","message_id":"…","completed":true,
       "messages":[{"role":"assistant","content":"<answer>",
                    "finish_reason":"stop",
                    "reasoning":"<real CoT>",
                    "reasoning_content":"<real CoT (duplicate key)>"}],
       "usage":{…}}
```

Upstream (NousResearch/hermes-agent) knows: issue #13007 = this exact bug,
PR #13326 = the fix, stale/conflicting; 10+ overlapping api-server reasoning
PRs, none merged. We are NOT filing anything upstream (Owen's call). The app
adopts the data the API already delivers. When upstream eventually fixes the
`_thinking` stream (live real deltas), this change must NOT fight it — see
Forward-compat below.

## The fix

### 1. `SessionsHermesClient` — decode reasoning from `run.completed`

Extend the existing `RunCompletedEnvelope` (already decodes `usage`) with:

```swift
let messages: [RunTranscriptMessage]?
// …
private struct RunTranscriptMessage: Decodable {
    let role: String?
    let reasoning: String?
    let reasoningContent: String?
    enum CodingKeys: String, CodingKey {
        case role, reasoning
        case reasoningContent = "reasoning_content"
    }
}
```

Add `nonisolated private func decodeRunReasoning(_ data: String) -> String?`
following the `decodeRunUsage` pattern exactly: LAST entry with
`role == "assistant"` wins; prefer `reasoning_content`, fall back to
`reasoning`; trim; return nil when blank/absent.

### 2. Mirror guard — pure decision fn (the #110 pattern)

`static func reasoningMirrorsAnswer(_ reasoning: String, content: String) -> Bool`
on `SessionsHermesClient` (pure, unit-testable, lives with `thinkingDelta`).
Semantics = EXACTLY the #110 whitespace-fold: fold every whitespace run to a
single space, trim both, compare equal. Mirrors #110's
`shouldRetractSpeech` folding so the two features can't drift apart —
copy the fold implementation, do not invent a new one.

### 3. Attach precedence at the `run.completed` case (~line 266–277)

Replace the unconditional `if !assembledReasoning.isEmpty { … }` with:

1. `decodeRunReasoning(currentData)` non-nil → `message.reasoning = it`. WINS.
2. else `assembledReasoning` non-empty AND
   `!reasoningMirrorsAnswer(assembledReasoning, content: message.content)`
   → keep `assembledReasoning`.  ← Forward-compat: when upstream fixes
   `_thinking` to stream REAL deltas, they differ from the answer and are
   adopted live with zero further app changes.
3. else leave `message.reasoning` nil. An answer-mirror must NEVER attach.

Apply the SAME precedence-2/3 guard at the stream-end fallback (~line 310–318,
`fallbackMessage`) — no `run.completed` payload exists there, so step 1 is
skipped by construction.

### 4. `ChatStore` — close the resurrection side door (~467–473 ONLY)

`if resolved.reasoning == nil { resolved.reasoning = streamedReasoning }`
currently resurrects the placeholder's accumulated mirror when the client
attaches nothing. Gate it: only adopt `streamedReasoning` when it is non-nil,
non-empty, AND `!reasoningMirrorsAnswer(it, content: resolved.content)`.
Touch NOTHING else in ChatStore.

## Hard constraints

- Do NOT touch the `_thinking` parser (`thinkingDelta`), the SSE taxonomy,
  or the `incrementalReasoningDelta` hedge — the live-delta path must keep
  working the day upstream fixes the gateway.
- Do NOT touch the `.interrupted`/cancel paths, `partialReasoning` capture
  (~532), or the reconcile re-attach (~1313–1320). Interrupted runs never
  received the terminal mirror event in practice; out of scope.
- Do NOT touch `reasoningSummary` condensation (#4.15) — it operates on
  whatever reasoning lands.
- No new files. No pbxproj/xcodegen. File-scoped commits.

## Tests (`ReasoningChannelTests.swift` — the acceptance gate; extend, don't rewrite)

Decode: run.completed with `reasoning_content` → adopted verbatim; with only
`reasoning` → adopted; both → `reasoning_content` wins; multiple messages →
last assistant wins; blank/absent → nil; malformed JSON → nil (no throw).

Mirror fn: identical → true; whitespace-fold-equal (newline/space runs) →
true; genuinely distinct reasoning → false; empty reasoning → caller never
asks (guarded by non-empty check first).

Attach precedence (streamed-event fixture, per the existing accumulation
tests in this file): (a) mirror `_thinking` + `reasoning_content` present →
message.reasoning == reasoning_content; (b) mirror + no structured →
reasoning nil; (c) DISTINCT `_thinking` deltas + no structured → assembled
kept (forward-compat pinned as a test, not a comment); (d) stream-end
fallback with mirror → nil.

ChatStore side door: resolved.reasoning nil + placeholder mirror ==
resolved.content → NOT resurrected; distinct placeholder reasoning → kept.

## Mac checklist (cloud-written, NOT compiled)

1. No xcodegen needed (no new files) — verify with `git status` after build.
2. CLI build + full suite; `ReasoningChannelTests` green, count grows.
3. Device-verify owed: send a turn on whoGoesThere → Reasoning chevron shows
   genuine CoT (distinct from the answer), or NO chevron for a turn whose
   model produced no reasoning. The mirror must be gone in both cases.
