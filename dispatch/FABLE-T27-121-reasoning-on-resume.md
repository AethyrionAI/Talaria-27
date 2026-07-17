# FABLE T27-121 — Reasoning on resume: restore the thinking panes

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-121-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #121 (new; cross-ref #60)
**Size:** one PR, medium. **Baseline:** 755/62. **Toolchain:** Xcode-beta3.

## The finding (from the #25 wire probe, 2026-07-16, live OJAMD)

`GET /api/sessions/{id}/messages` carries **`reasoning` and
`reasoning_content` per row** — data the app already fetches on every resume
and throws away. Live turns restore their reasoning pane from
`run.completed.reasoning_content` (#60's PR #94/#95 work); RESUMED sessions
render with reasoning panes permanently empty. This lane closes that gap:
reopen an old session, the thinking panes come back.

## The seam

- Decode: `SessionsHermesClient.swift` `SessionMessagesResponse.StoredMessage`
  — add `reasoning: String?` + `reasoning_content: String?` (tolerant: `try?`,
  both optional, absent/null → nil; the struct's `toolCalls` handling at
  ~:1534 models the pattern). Map into whatever field the live path populates
  on the assistant `Message` (find where PR #94's `run.completed` adoption
  writes reasoning onto the message/conversation — reuse that exact property;
  do NOT invent a parallel one).
- **The #60 trap, non-negotiable:** the gateway historically emitted the
  ANSWER mirrored under the thinking channel. PR #95 aggregates and PR #94
  guards the live path — the resume path must apply the SAME answer-mirror
  guard: if a row's reasoning is byte-identical (or prefix-identical per the
  existing guard's rule — read it, reuse it, don't reinvent it) to that row's
  `content`, drop it. A restored pane showing a carbon copy of the answer is
  a regression of #60, and Owen will notice immediately.
- Which field wins when both `reasoning` and `reasoning_content` are non-nil:
  probe data showed both keys exist; prefer `reasoning_content` (matches the
  live channel), fall back to `reasoning`. State the choice in a comment.
- UI: NO new UI. The reasoning pane/disclosure already exists for live turns —
  if the message model field is populated, the pane renders. If that turns out
  untrue (pane gated on a live-streaming flag), the fix is removing that
  gate for populated-reasoning messages, not building a surface.

## Tests

- Fixture rows with reasoning_content → message model populated.
- Answer-mirror row (reasoning == content) → dropped, pane stays empty.
- Null/absent/malformed reasoning fields → nil, no throw (real wire shape:
  keys present, often null — model the fixtures on the probe, not on hope).
- Mixed conversation: some rows with, some without → only the with-rows carry
  reasoning.

## Constraints & acceptance

- Tolerant decode; zero change to live-path reasoning handling; no OPEN_ITEMS
  edits in feature commits; regen on test-file add (separate commit,
  aps-environment verified).
- Suite green ≥ 755/62. Device check for Owen: reopen yesterday's session →
  thinking disclosures present on assistant turns that had reasoning; open a
  cron-sourced session → same; no pane shows a copy of its answer.
