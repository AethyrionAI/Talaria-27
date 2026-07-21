# EVAL — Hermes 0.19 `model_routes` / durable `/model` vs Talaria Models Shim

**Date:** 2026-07-20 · **Resolves:** the #116 hold · **Feeds:** #148 (item 1 of the priority list)
**Evidence:** 0.19.0 source read (`~/.hermes/hermes-agent/gateway/platforms/api_server.py`,
`gateway/run.py`) + live probes against the Mac gateway (verified 0.19, `GET /v1/models`
and `GET /v1/capabilities`, 2026-07-20).

## VERDICT: KEEP the shim, unchanged. Retire nothing. Unblock #116 as designed.

The 0.19 native features do not reach the plane the app actually uses. Detail below.

---

## 1. What the shim provides today (`tools/models-shim/shim.py`, :8765)

| Surface | Behavior |
|---|---|
| `GET /healthz` | Unauthenticated reachability probe (the app's two-step honest probe, PR #102) |
| `GET /models?refresh=0\|1` | **Rich inventory**: full provider mirror via `build_models_payload` — picker hints, pricing, capabilities, canonical order, unconfigured providers included, current default pointer. TTL-cached (3600s), cache invalidated on set-default |
| `POST /models/default` | **Sets the persistent global default** (`_apply_model_assignment_sync` → config.yaml), with an expensive-model confirm gate |
| Auth | Dual-token: dedicated shim token (`~/.hermes/talaria_shim_token`) OR `API_SERVER_KEY` |
| Bind | Tailscale-only (`TALARIA_SHIM_HOST`, default tailnet IP) |

## 2. What 0.19 native actually offers — and where it applies

### `model_routes` (per-client routing, #57028)
Config at `platforms.api_server.extra.model_routes`: maps an incoming request
`model` field value → `{model, provider?, api_key?, base_url?}`.
**Applies ONLY to the three OpenAI-spec endpoints** — the handler resolves
`self._resolve_route(body.get("model"))` at exactly three call sites:
`POST /v1/chat/completions` (api_server.py:2785), `POST /v1/responses` (:3898),
`POST /v1/runs` (:4899).

**The Sessions API chat path — `POST /api/sessions/{id}/chat[/stream]`, i.e. the
Clean Chat Path the app is built on — does not read a `model` field at all and
never resolves a route.** (`_handle_session_chat` / `_handle_session_chat_stream`
pass no `route` to `_run_agent`; body keys consumed: message, system_message/
instructions.) The model for every phone chat turn is `_resolve_gateway_model()`
= the **global default** — precisely the thing only the shim's
`POST /models/default` can change from the phone.

### Durable per-session `/model` (#57030)
Real, and now restart-durable (`GatewayRunner._rehydrate_session_model_override`,
run.py:17466 — persisted model/provider/base_url written through on `/model`,
cleared on `/new`, credentials re-resolved on rehydrate, api_key never on disk).
**But it is a messaging-platform/CLI slash-command feature.** The API-server
plane has no slash-command processing (grep: no command dispatch anywhere in
api_server.py). On the API plane the override is consulted at exactly one point
(`_create_agent`, :1810) and **only to suppress a `model_routes` route** — it is
never itself applied to `model`/`runtime_kwargs` there. The app can neither
issue nor benefit from `/model` through the Sessions API.

### `GET /v1/models` (alias discovery)
Live probe on the Mac 0.19 gateway (no routes configured): a single skinny
entry `{"id":"hermes-agent","root":"hermes-agent","parent":null,...}`. With
routes configured it adds `{id: alias, root: resolved_model, parent: primary}`
per alias — **id/root/parent only. No pricing, no capabilities, no picker
hints, no provider inventory, no current-default pointer, no unconfigured
providers, no set operation.** It cannot back the app's model picker.
`GET /v1/capabilities` confirms: no models-management feature flags; the
endpoint map lists `models: GET /v1/models` and nothing shim-like.

## 3. Feature-by-feature disposition

| Shim capability | 0.19 native equivalent on the app's plane | Disposition |
|---|---|---|
| Rich model inventory (picker payload) | **None** (`/v1/models` is skinny) | **KEEP** |
| Set global default from phone | **None** (no write surface anywhere on the API plane) | **KEEP** |
| Expensive-model confirm gate | None | **KEEP** |
| Dual-token auth | n/a (shim-local concern) | **KEEP** |
| Honest probe target (`/healthz` + authed `/models`) | n/a — #116's app half depends on it | **KEEP** |

Nothing to trim: all three shim endpoints are load-bearing and none is
duplicated natively. Retiring the shim would strand the models plane entirely
(no inventory, no default control, and the #116 provisioning descriptor's
`shim_base_url`/`shim_token` fields would provision a dead surface).

## 4. App-side migration sketch (future-conditional, NOT now)

Native migration becomes worth revisiting only if one of these lands upstream:
1. **`model` field support on `/api/sessions/{id}/chat[/stream]`** — then the
   app could pin per-request models via `model_routes` aliases discovered from
   `/v1/models`, and the shim's set-default could shrink to a preference. The
   picker would still need a rich inventory source (shim `GET /models` or an
   upstream equivalent), so even then the shim likely survives read-only.
2. **A native set-default / models-management write API** — would replace
   `POST /models/default`; check `/v1/capabilities` feature flags on each
   Hermes update (`admin_config_rw` is `false` today, which is the flag to
   watch).
Moving the chat plane itself to `/v1/chat/completions` +
`X-Hermes-Session-Id` just to gain `model_routes` is rejected: it abandons the
Sessions API contract (session listing/fork/history, the verified SSE
taxonomy) for a per-request model knob the shim already effectively provides
globally. Cost far exceeds benefit.

## 5. Practical notes
- If Owen ever configures `model_routes` for OTHER clients (e.g. Open WebUI on
  the same gateway), it changes nothing for the phone: session-chat turns keep
  using the global default; a `/model` issued from Telegram/CLI on a shared
  session key still wins over routes on the OpenAI-spec endpoints only.
- `kimi-k3` catalog + `excluded_providers` (#148 MEDIUM) act inside
  `build_models_payload` — the shim inherits both for free; pruning the
  25-provider mirror is a config-side choice, no shim change.
- Re-check this verdict at each Hermes minor: watch `/v1/capabilities` for
  `admin_config_rw: true` or session-chat `model` support.

## 6. Actions
- #116: HOLD LIFTED — proceed with the deploy + DoD device pass as merged
  (PRs #101/#102). No design change.
- #148: fold this verdict in; item 1 of the priority list DONE.
