# #357 steer wire probe — native `POST /v1/runs/{run_id}/steer` — 2026-08-17 ~00:45 CDT

**Target:** live Mac gateway `:8642` (listener PID 11563, started 2026-08-16
23:44:35, serving `b2369172a`; steer handler source-verified present in that
commit). **Method:** HTTP only (curl), zero config edits, zero install
modification. **Authorization:** Owen's go 2026-08-17 ~00:05 ("You can go on
either"). **Bars:** pre-registered in OPEN_ITEMS #357 at commit `51faf11`,
BEFORE this run.

## Arm A — mid-tool steer (bar 357-A) ✅ MET

Submit: *"Use the terminal tool to run exactly this command: `sleep 20 &&
echo done`. After the tool completes, reply with exactly the single word:
BANANA."* → `run_3b81ccc2f1784b5c81bde610c686f49e`, 202.

Steer fired ~1 s after `tool.started` appeared on the events stream, body
*"Change of plan from the user: reply with exactly the single word: PLUM."*

- ACK: `{"object": "hermes.run.steer", "accepted": true}`, HTTP 200.
- Stream frame sequence observed: `tool.started` → **`run.steered`
  (`accepted: true`, t=1786944553.74)** → `tool.completed` →
  `message.delta`×2 → `reasoning.available` → `run.completed`.
- Final output: **`PLUM`** (status object: `status: completed`,
  `output: "PLUM"`). The original BANANA instruction did not survive; the
  steer did. The 2026-08-06 BANANA→PLUM result is now reproduced **via the
  client-reachable native route** rather than injected `agent.steer()`.

## Arm B — mid-prose steer honesty (bar 357-B) ✅ MET

Submit: 200-word lighthouse-keeper story, no tools →
`run_c511daf2092144fd9b93d405b09799c3`.

Steer fired after the first `message.delta`, body *"STEER-MANGO: ignore the
story and reply only with the word MANGO."*

- ACK: `accepted: true`, HTTP 200 — **the ACK is still not a delivery
  promise, exactly as pre-registered** (S4's boundary constraint stands).
- Output: the full story, unaffected — no MANGO anywhere.
- **`run.completed` carried `pending_steer` with the steer text VERBATIM**,
  and so did `GET /v1/runs/{id}` afterward:
  `"pending_steer": "STEER-MANGO: ignore the story and reply only with the
  word MANGO."` — the upstream replay-as-next-turn contract
  (`turn_finalizer.py:755`) observed on the wire. S4's silent drop is
  CLOSED upstream; the drop is now announced at turn end on both the stream
  and the pollable status.

## Arm C — closed-window rejections (bar 357-C) ✅ MET

| case | response |
|---|---|
| steer a COMPLETED run (arm B's) | 409 `run_not_accepting_steer` |
| steer an unknown id | 404 `run_not_found` |
| stop-then-steer (`sleep 30` run, `/stop` at ~6 s, steer +1 s) | 409 `run_not_accepting_steer` |

No closed-window arm returned a false-positive acceptance.

## Notes / residue

- Probe sessions now exist in the Mac's session list (PINGOK, PLUM,
  lighthouse story, and one stopped `sleep 30` run) and one PINGOK session
  on OJAMD (from the #356 wire checks). Normal sessions, harmless; noted so
  the next session-list reader isn't surprised. Bare submits store
  `model: "hermes-agent"` (the #241 sentinel) — known upstream behavior,
  probe-only sessions, no action.
- Deferred, with reason: a **parked-on-approval** steer arm (expect 409
  since status ≠ `running`; matters for closing the composer's steer door
  during an approval card) needs a host approval-mode change = 🔐
  live-install gate. Not run tonight; carried in #357.
- Raw frame logs: scratchpad `armA-events.log` / `armB-events.log` (session
  temp); the frames quoted above are verbatim.
