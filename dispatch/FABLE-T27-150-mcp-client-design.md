# FABLE-T27-150 — MCP client design doc: app-side MCP access (design gate for the 1.1 marquee)

**Item:** OPEN_ITEMS #150 (✨) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main (≥ `39d8bcc`)
**Branch:** `claude/t27-150-mcp-client-design` · **Size:** medium, one PR, **DOCS ONLY**
**Staleness check (2026-07-20 late):** no prior #150 work exists (only the item-creation
commit `5ef5f24`). Sole open PR is #128 (`probe/t27-130-halfduplex`), a DO-NOT-MERGE voice
probe — zero overlap with this lane. NOTE: OPEN_ITEMS item numbers ≠ GitHub issue/PR
numbers; every "#N" below is an OPEN_ITEMS anchor unless it says "PR".

## Mission

Produce the design document that gates ALL #150 implementation, plus a DRAFT spec for the
first implementation lane. **This lane writes ZERO Swift.** No `project.yml` changes, no
`xcodegen`, no test files. Exactly two new markdown files; nothing else touched.

Owen green-lit starting #150 on 2026-07-20 (post-launch scope stands — this is design
work, not launch-pass work). The item's own entry point is the design doc; you are it.

## Canonical inputs — read these first, in the repo

1. `OPEN_ITEMS.md` **#150** — the item, INCLUDING the record correction paragraph. The
   correction is BINDING: the on-device model is a 3B FoundationModels instruct model;
   free-tier ceiling is NARROW GUIDED SINGLE-TOOL use (one tool, clear trigger,
   schema-constrained args via guided generation — which prevents malformed calls but
   does not grant planning). The "real standalone agent" framing is dead. The
   game-changer claim lives ONLY in the Connected tier.
2. `OPEN_ITEMS.md` **#69** (device tool belt — Connected-tier ancestor this generalizes),
   **#4** (dormant confirm gate — the approval-UX pattern to extend), **#61/#102**
   (3B-model degeneration evidence — the free-tier context/size budgets answer to this),
   **#136** (degraded-is-default posture — MCP servers being unreachable must never
   block the app), **#148** (Hermes 0.19 notes: smart-approval choices, MCP tool-name
   convention `mcp__server__tool`).
3. `CLEAN_CHAT_PATH.md` (repo root) — the Sessions API + SSE contract the Connected
   tier's chat plane already speaks.
4. Code patterns to design against (read, cite by path — do not modify):
   `Services/Support/ProvisioningService.swift` (fill-empty-only provisioning),
   `BackendProfileScopedKeys` usage (per-profile Keychain scoping),
   the #114/#116 two-step honest probe + static-probe/accumulator-box test pattern in
   `ServerSettingsScreen` / `ServerSettingsTests`.

## Hermes-side contract facts (inlined — the reference implementation is NOT in this repo)

A working Sessions-API MCP bridge exists outside the repo (dev tool; do not go looking
for it). The verified contract facts you may rely on, measured 2026-07-20 on v0.19
gateways:
- Session lifecycle: `POST /api/sessions` (empty body) → id at `.session.id`;
  `POST /api/sessions/{id}/chat` → `.message.content` + `.usage`;
  `GET /api/sessions/{id}/messages` → per-row `role`/`content` PLUS `reasoning` /
  `reasoning_content` fields; `GET /health` → `{status, version}`.
- Auth: single bearer (`API_SERVER_KEY`), same credential class the app already stores.
- Envelope: warm gateway ≈12s/turn; cold start ≈21s to first token; fresh-session
  context ≈55k input tokens. Timeouts and progress UX must assume this reality.
- 0.19 native MCP (host side): Hermes registers MCP tools as `mcp__<server>__<tool>`;
  config include/exclude filters match BARE names pre-prefixing.

## Deliverables

### D1 — `design/MCP_CLIENT_DESIGN.md` (the gate document)

Mandated sections, in order. Where you assert an iOS or SDK capability, cite a source
(SDK repo/docs URL, Apple documentation page). Where you cannot verify, write
**OPEN QUESTION** — never invent API claims.

**a. Tier framing + capability matrix (binding).** Bake the record correction in. A
table: capability × free/Connected. Free = ONE guided tool per interaction,
schema-constrained via FoundationModels guided generation, fetch-and-summarize class;
Connected = host model reasons, app extends its reach. If you believe free can do more,
that argument goes in an explicitly-marked appendix ("Argument for revisiting"), never
in the main matrix.

**b. Transport + SDK evaluation.** stdio is impossible on iOS (no subprocesses);
streamable HTTP is the transport. Evaluate the official Swift MCP SDK (the
modelcontextprotocol swift-sdk): SPM integration implications for `project.yml` +
`xcodegen`, iOS minimum, transport support, maintenance posture. Verdict: adopt vs
hand-roll a minimal streamable-HTTP client — justify either way with citations.

**c. Server management UX.** Add/edit/remove MCP servers: URL + optional bearer/header
auth; per-server credentials in Keychain, profile-scoped via the
`BackendProfileScopedKeys` pattern; honest two-step probe (reachability → authed tool
list) rendered with the #114/#116 semantics (NO KEY vs ONLINE vs unreachable); settings
surface placement. Servers being down must degrade silently per #136 — never a launch
or chat-plane blocker.

**d. Tool approval UX.** Generalize the #4 confirm-gate pattern: per-tool grants with
once / session / always / deny (mirror Hermes 0.19 smart-approval choice semantics from
#148); read-only tools may be auto-grantable by class; side-effectful tools always
gated. Persistence model for grants; revocation UX.

**e. Split execution (Connected).** Analyze honestly: how would HOST-side Hermes tool
calls reach PHONE-local MCP tools and return results? Consider the existing
relay/connector plane (#69's architecture) as the candidate transport. You are
explicitly allowed to conclude this needs host-side work and belongs in a later phase —
do NOT force a design the current plane cannot carry. Separately scope what needs NO
host changes: app-initiated MCP tool use around chat turns (app calls tools, injects
results into the conversation it already controls).

**f. Free-tier guided single-tool flow.** Concrete end-to-end: trigger detection →
guided-generation arg construction → execute → summarize. Hard budgets: tool-result
size cap into the 3B context window, citing the #61/#102 degeneration evidence;
truncation strategy; what happens on over-budget results.

**g. Risks + posture.** Background-execution limits; App Review posture
(user-configured services = standard HTTP-client territory — argue it, cite precedent);
credential handling; tool-result safety (server output is UNTRUSTED DATA — never
instructions; approval gate is the only path to side effects); rate/size abuse by a
hostile server.

**h. Phased lane plan.** Lanes 150A, 150B, … each sized for ONE dispatch: scope, files
touched (new files → xcodegen implications called out), test surface, DoD. Lane A must
be the smallest coherent foundation (likely: server registry + settings UX + probe, no
tool execution yet).

### D2 — `dispatch/DRAFT-FABLE-T27-150A-<slug>.md` (Lane A draft spec)

House dispatch format (see `dispatch/FABLE-T27-139-connect-teardown.md` for the shape).
Header line one: **DRAFT — DO NOT EXECUTE — pending Owen review of MCP_CLIENT_DESIGN.md.**
Content must match design-doc Lane A exactly; no scope invention beyond it.

## Hard constraints

- **Two new markdown files. Nothing else.** No Swift, no `project.yml`, no `xcodegen`,
  no test files, no edits to existing files.
- **Do NOT touch `OPEN_ITEMS.md`** — not even a status line. The Mac loop records
  verdicts in separate surgical commits. (This is a repeat failure mode; it is a hard
  fail for this lane.)
- File-scoped commits (one per file is fine); PR against `main`; the loop merges with a
  merge commit — never squash, never self-merge.
- The record correction in #150 is binding on every section; contradicting it outside
  the marked appendix is a hard fail.
- No invented API claims: cite or mark OPEN QUESTION.

## DoD

- PR open from `claude/t27-150-mcp-client-design` containing exactly
  `design/MCP_CLIENT_DESIGN.md` (sections a–h, all present) and
  `dispatch/DRAFT-FABLE-T27-150A-<slug>.md` (marked DRAFT).
- Every capability assertion cited or flagged OPEN QUESTION.
- Capability matrix consistent with the #150 record correction.
- Loop verdict + OPEN_ITEMS record happen Mac-side after review — not in this PR.
