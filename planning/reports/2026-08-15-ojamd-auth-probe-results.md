# OJAMD authenticated gateway probe — results

**Run 2026-08-15 15:26 on OJAMD itself** via `scripts/ojamd-auth-probe.ps1` (read-only; every
call a GET; the `API_SERVER_KEY` is read from HERMES_HOME's `.env` and never printed). This
session runs ON the box, so the `hermes-ojamd` MCP fabrication caveat does not apply. Canaried
at both ends: `15:26:13` → `15:26:19`.

The script had been written and left unrun since 2026-08-10; this is its first execution.

---

## 0. The host moved — OJAMD is on 0.20.1, not 0.20.0

Every note in the tracker and in `CLAUDE.md` describes OJAMD as v0.20.0. It is not, as of today:

```
Hermes Agent v0.20.1 (2026.8.13)
Install directory: C:\Users\Owen\AppData\Local\hermes\hermes-agent
Python: 3.11.15
```

**Pinned by reflog-vs-start-time, per the standing rule** (never `git log -1`):

| Fact | Value |
|---|---|
| Install head | `165c889e5b4277b56dadd42949a4112c1e6175a6` — *fix(cli): stop pushing Kitty keyboard protocol that breaks Ctrl+C* |
| Head arrived | 2026-08-15 **14:14:22** (reflog: `merge origin/main: Fast-forward`, from `a90d5369f`) |
| Listener at probe time | PID 29576, started 2026-08-15 **15:09:08** |
| Verdict | listener start **postdates** the checkout ⇒ **the running process serves `165c889e5`. No drift.** |

(The listener was subsequently replaced at 15:28:06 by this session's own restart — see the
#346 work — which serves the same head.)

**This settles #155.** The item asked for "the actual Hermes Agent commit (or `hermes --version`
string if the commit is not determinable) and the date chat + sessions + model switching were
verified end-to-end against the running host." Commit `165c889e5`, version `v0.20.1 (2026.8.13)`,
verified end-to-end today: `/health` 200, sessions created and chatted through
`/api/sessions/{id}/chat`, `/api/model/options` 200 with a 43-provider catalog.

---

## A. #223 model-catalog chore — **NVIDIA IS PRESENT. The chore is REAL and NOT done.**

`GET /api/model/options` → HTTP 200, payload shape `{providers, model, provider}` (the collection
key is `providers`, per `hermes_cli/inventory.py::build_models_payload`).

**43 provider rows.** The ones carrying models:

| Provider | Models |
|---|---|
| **NVIDIA NIM** | **102** |
| Nous Portal | 37 |
| GitHub Copilot | 17 |
| Google AI Studio | 15 |
| openai-api | 13 |
| Anthropic | 11 |
| Z.AI / GLM | 11 |
| Kimi / Moonshot | 11 |
| ChatGPT or Codex Subscription | 8 |
| MiniMax | 5 |
| MiniMax (minimax.io) | 3 |
| DeepSeek, Mixture of Agents | 2 each |

The other 31 providers report 0 models. **NVIDIA NIM alone contributes 102 of the catalog's
rows — the largest single block, by a wide margin.** Whatever the picker shows, it is mostly
NVIDIA.

Deliberately probed against the **gateway**, not the shim's `/models`: Lane 5 retired the shim
from the model path, so the shim's payload is nobody's picker and proves nothing about what the
phone sees.

---

## B. `/v1/capabilities` — route-reverify gap 3 is CLOSED by observation

The 2026-08-09 route re-verify could not read this endpoint from the Mac lane and had to
**infer** `run_approval_response` from source. Now observed live, HTTP 200:

- `run_approval_response: true` — **the inference was correct**, now evidence.
- `run_steer: true`, with `run_steer: POST /v1/runs/{run_id}/steer` in the endpoint map.
  **This endpoint is not named in CLAUDE.md's 37-row table**, which lists `/v1/runs*` incl.
  approval and `/stop`. Worth knowing before the next "is that route real?" question — it is,
  and the capabilities document is a cheaper source of truth than a code read.
- `admin_config_rw: false`, `jobs_admin: false`, `memory_write_api: false` — independently
  corroborates "**no `/api/config`**", i.e. approval-mode SELECTION stays dashboard-only.
- `audio_api: false`, `realtime_voice: false`, `cors: false`.
- Session headers named explicitly: `X-Hermes-Session-Id`, `X-Hermes-Session-Key`.
- `runtime.mode: server_agent`, `tool_execution: server`, `split_runtime: false`.

---

## C. Health (authenticated)

```
/health           → {"status":"ok","platform":"hermes-agent","version":"0.20.1"}
/health/detailed  → status ok; state_db/config/model/disk all ok;
                    disk 80.9% used, 191 GB free;
                    gateway: running, connected_platforms 4 of 5 platforms;
                    background_queues: 0 active api runs
```

`discord: connected` — consistent with the supervision inventory's S6 note that CLAUDE.md's
"Discord is one token away" is stale; it is already through the door.

---

## D. Catalog surface

| Route | HTTP | Entries |
|---|---|---|
| `/v1/models` | 200 | **1** |
| `/v1/skills` | 200 | 114 |
| `/v1/toolsets` | 200 | 29 |

`/v1/models` body, which is the one that matters for **#241's routing sentinel**:

```json
{"object":"list","data":[{"id":"hermes-agent","object":"model","created":1786825579,
  "owned_by":"hermes","root":"hermes-agent","parent":null}]}
```

**Still the single `hermes-agent` virtual model.** Per CLAUDE.md's #241 chain, we are safe
precisely because nobody has changed the "API server model name" field — this probe confirms
the sentinel is intact on 0.20.1. Every session Talaria creates still stores that literal
string and still matches `self._model_name`, so `route_source` stays `global`.

---

## What this changes

1. **#155 — CLOSEABLE.** Commit + version + end-to-end verification date all captured above.
2. **#223's model-catalog chore — CONFIRMED REAL on OJAMD**, with a number attached (102 NVIDIA
   rows). Previously the chore's status on this host was unverified against the gateway.
3. **Route-reverify gap 3 — CLOSED**, and `/v1/runs/{id}/steer` surfaced as a route the
   in-repo table never listed.
4. **The 0.20.0 → 0.20.1 move** is not recorded anywhere in the tracker. Any note that reasons
   from "OJAMD is on 0.20.0" is now describing a host that no longer exists.
