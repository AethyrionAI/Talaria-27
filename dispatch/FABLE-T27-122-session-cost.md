# FABLE T27-122 — Session cost & usage surface

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-122-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #122 (new)
**Size:** one PR, small-medium. **Baseline:** 755/62. **Toolchain:** Xcode-beta3.

## Why

The #25 probe established that session-level `input_tokens` etc. are
cumulative billing figures — banned as a context meter, but EXACTLY right as a
cost surface. The wire already serves, per session, on `GET /api/sessions`
(list) and `GET /api/sessions/{id}` (detail): `input_tokens`, `output_tokens`,
`cache_read_tokens`, `cache_write_tokens`, `reasoning_tokens`,
`estimated_cost_usd`, `actual_cost_usd`, `api_call_count`, `tool_call_count`,
`message_count`. Owen currently has zero visibility into what a session cost.

## The build

- Decode: extend the sessions LIST/DETAIL decode in `SessionsHermesClient`
  (NOT the messages decode) with the fields above — all optional, tolerant
  (`try?`), absent → nil. Verify against the probe-recorded shape in
  `dispatch/FABLE-T27-25-ctx-meter.md`.
- Surface: a compact usage row on the session's detail affordance — wherever a
  session's metadata already renders (sessions list row / session info sheet —
  find the existing surface; do NOT build a new screen). Show: cost (prefer
  `actual_cost_usd`, fall back to `estimated_cost_usd`, prefix `~` when
  estimated), total tokens in/out, api calls. Absent data → row hidden
  entirely (the #25 honest-absence rule applies to money even more than to
  context: never render $0.00 for unknown).
- Formatting: sub-cent costs as `<$0.01`; token counts abbreviated (66.4k).
  Respect theme tokens (`Design.Colors`), monospace label style consistent
  with the CTX gauge's `MonoLabel` if visible in the same vicinity.
- **Do NOT** aggregate across sessions, add settings, or build charts here —
  single-session readout only. (A spend-over-time chart is a natural future
  rider on #100's chart surface — note it, don't build it.)

## Tests

- Decode: full row → all fields; partial/null row → nils, no throw; the
  fixture models the probe's real shape.
- Display decision function: actual vs estimated preference, hide-on-absent,
  formatting thresholds — pure, unit-tested.

## Constraints & acceptance

- Tolerant decode; no messages-endpoint changes; file-scoped commits; regen on
  file add (separate commit, aps-environment verified).
- Suite green ≥ 755/62. Device check for Owen: a recent api_server session
  shows cost + tokens matching the OJAMD dashboard's expectations; an old or
  sparse session shows no row rather than zeros.
