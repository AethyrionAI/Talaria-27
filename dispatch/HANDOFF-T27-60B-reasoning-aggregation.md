# HANDOFF-T27-60B — Aggregate transcript reasoning across all assistant entries

**Executor:** Claude Desktop or Claude Code on the Mac Mini (local repo:
`/Users/owenjones/Documents/Claude/Talaria-27`). Self-contained — assumes no
memory of the 2026-07-13 session that produced it.
**OPEN_ITEMS:** #60, "Enhancement candidate" note under fix track 2 (CLOSED).
**Base:** `main` at `e74e5f9` or later. Branch `claude/t27-60b-reasoning-aggregation`.
**Scope (hard):** `Talaria/Services/Live/SessionsHermesClient.swift` (one
function), `TalariaTests/ReasoningChannelTests.swift`. NO new files → NO
xcodegen, NO pbxproj churn. File-scoped commits; merge via PR with
`gh pr merge --merge` (never squash), `--repo AethyrionAI/Talaria-27`.

## What already shipped (PR #94, merged 2026-07-13)

The gateway's `_thinking` SSE channel is defective upstream (it mirrors the
ANSWER; known as NousResearch/hermes-agent issue #13007 — we are filing
NOTHING upstream, Owen's standing decision). The app therefore adopts the
model's real reasoning from the terminal `run.completed` payload:
`decodeRunReasoning` reads `messages[]`, takes the LAST `role=="assistant"`
entry, prefers `reasoning_content` over `reasoning`, trims, blank = absent.
A pure `reasoningMirrorsAnswer(_:content:)` whitespace-fold guard (identical
to #110's `shouldRetractSpeech` fold) blocks an answer-mirror from ever
attaching, at three sites: the `run.completed` yield, the stream-end
fallback, and ChatStore's nil-fallback (~473). Device-verified PASS.

## The gap this handoff closes (wire-confirmed 2026-07-13)

On TOOL-USING turns the run transcript is multi-message, and the genuine
plan-CoT rides the INTERMEDIATE assistant entries — last-wins discards it
and surfaces only the final entry's reasoning (typically a draft-the-answer
compile step). Real capture from the live gateway (terminal-tool turn,
`POST /api/sessions/{id}/chat/stream`), condensed:

```
run.completed → messages: [
  {role:"assistant", content:"",                              ← tool-call planner
   reasoning_content:"The user wants me to check the current UTC time
                      on the host. I'll use the terminal…"},  ← the REAL CoT
  {role:"tool", content:"{\"output\":\"Tue, Jul 14 …\"}"},
  {role:"assistant",
   content:"The current UTC time is Tuesday, July 14, 2026 at 03:02:46 AM.",
   reasoning_content:"The current UTC time is Tue, Jul 14, 2026,
                      3:02:46 AM."}                           ← near-copy of answer
]
```

Owen's 10-tool smoke-test turn showed the user-facing effect: the pane
displays only "Let me compile the smoke test results…" — the ten planning
thoughts are decoded and thrown away. Hermes's own web UI shows every
reasoning segment across the run; the app should match.

## The change — `decodeRunReasoning` only

Replace last-assistant-wins with aggregation:

1. Iterate `envelope.messages` IN ORDER; consider only `role == "assistant"`.
2. Per entry: prefer `reasoningContent` over `reasoning`; trim
   `.whitespacesAndNewlines`; skip when blank/absent (unchanged per-entry
   posture).
3. Join the surviving segments with `"\n\n"`; return nil when none survive.
4. Callers are UNCHANGED — but note the existing precedence at the
   `run.completed` yield attaches structured reasoning WITHOUT the mirror
   guard (structured wins unconditionally today). ADD the guard to the
   aggregate: if `reasoningMirrorsAnswer(aggregate, content: message.content)`
   treat as absent and fall through to the assembled-deltas branch. A
   single-entry transcript whose reasoning restates the answer verbatim
   should yield NO chevron, same as every other mirror path.

Call-site shape (the `run.completed` case, ~line 270s; mirror the same
structure at no other site — the stream-end fallback has no payload and
stays as-is):

```swift
let structured = decodeRunReasoning(currentData)
if let structured,
   !Self.reasoningMirrorsAnswer(structured, content: message.content) {
    message.reasoning = structured
} else if !assembledReasoning.isEmpty,
          !Self.reasoningMirrorsAnswer(assembledReasoning, content: message.content) {
    message.reasoning = assembledReasoning
}
```

## Hard constraints (same as PR #94)

- `thinkingDelta`, the incremental hedge, `reasoningMirrorsAnswer`,
  `whitespaceFolded`, ChatStore, interrupted/reconcile paths,
  `reasoningSummary`: DO NOT TOUCH.
- No new files. Keep the doc comment on `decodeRunReasoning` honest —
  it currently says "LAST assistant entry wins"; rewrite it.

## Tests — `RunCompletedReasoningTests` in `ReasoningChannelTests.swift`

The sub-suite drives the REAL SSE parse loop through a stubbed
`URLProtocol`; extend its fixtures, don't invent a new harness.

- `lastAssistantEntryWins` is now WRONG by design — rename/rewrite to
  `aggregatesReasoningAcrossAssistantEntries`: 3-message fixture modeled on
  the capture above → expect `"<plan CoT>\n\n<final reasoning>"` in order.
- Blank-reasoning intermediate entries are skipped (no empty segments,
  no double separators). `role:"tool"` entries never contribute.
- Per-entry `reasoning_content`-over-`reasoning` still holds inside the
  aggregate (mixed-key fixture).
- Single-entry transcript whose reasoning fold-equals the answer → nil →
  falls through to the assembled branch (and with a mirror `_thinking`
  fixture there too, final reasoning is nil).
- All existing decode tests (trim, blank/absent → nil, malformed no-throw,
  `reasoning_content` wins) must stay green; forward-compat pin
  (`distinctThinkingDeltasKeptWithoutStructured`) untouched.

## The loop (Mac)

1. `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
   in EVERY new shell (stock Xcode = iOS 26 SDK = phantom compile errors).
2. Build: `xcodebuild build-for-testing -project Talaria.xcodeproj -scheme
   Talaria -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557'
   CODE_SIGNING_ALLOWED=NO` — run long builds `nohup … &` and poll.
3. Test: `test-without-building`, same destination. Gate: Swift Testing
   line `Test run with N tests in M suites passed` — baseline is 618/51,
   N grows. A benign post-verdict 600s "collecting diagnostics from
   simulator" stall is known — the SUCCEEDED verdict above it is the truth.
4. `git status` must stay clean post-build (no regen expected).
5. PR + `gh pr merge --merge`. OPEN_ITEMS #60 note flip = separate commit
   (verify anchors with grep before editing; max item number may have moved).
6. Device-verify on whoGoesThere: a multi-tool turn's chevron shows the
   PLAN chain (multiple segments) followed by the compile step — not the
   compile step alone. Mid-stream mirror flash remains expected until
   upstream fixes the gateway (track 1, wait-for-update).
