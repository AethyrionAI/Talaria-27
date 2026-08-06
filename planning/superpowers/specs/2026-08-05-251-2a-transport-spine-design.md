# #251-2A — Transport Spine: talaria platform adapter + app platform link

**Status:** APPROVED by Owen 2026-08-05 night ("Looks right, write the spec").
**Parent:** OPEN_ITEMS #251 (the plugin venture), Phase 2 slice A of four
(A spine · B conversational installer · C desktop face · D OJAMD rollout).
**Routing captured during brainstorm (Owen, via menu):** slice A first ·
inbox replaces the relay feed · structured query catalog · long-poll drain.

## Goal

When this slice lands: the phone pairs itself to the Hermes gateway's
`talaria` platform with zero new user steps, agent-initiated messages
arrive durably in the app's existing Inbox (relay inbox feed retired),
and `phone.query` (#242) answers live from the phone whenever Talaria is
open — with an honest "phone unreachable" whenever it is not.

## Verified ground (all read line-exact this session, local install)

- `ctx.register_platform(name, label, adapter_factory, check_fn, ...)`
  is a first-class plugin API (`hermes_cli/plugins.py:953`) →
  `PlatformEntry(source="plugin")` in `platform_registry`. No in-tree
  layout needed; `plugins/platforms/` is for hermes's own built-ins.
- The events route (`gateway/platforms/api_server.py`
  `_handle_platform_event_callback`, ~:1808): adapter must be CONNECTED
  (else 503), then `verify_http_event_request(auth_header) -> (ok, code)`
  (fail-closed, sync verifiers off-loop) then
  `dispatch_http_event(payload: dict) -> dict` (adapter-authored
  response). `dispatch_http_event` is async — holding a long-poll inside
  it is legitimate.
- `BasePlatformAdapter` (gateway/platforms/base.py:2629) abstract
  surface: `connect(is_reconnect)`, `disconnect()`, `send(chat_id, …)`,
  `get_chat_info(chat_id)`. Reference webhook implementation:
  `plugins/platforms/google_chat/adapter.py:1495` (dispatch) / `:1520`
  (verify).
- Enable mechanic: `platforms.talaria.enabled: true` in
  `~/.hermes/config.yaml` (same shape as the existing `bluebubbles`
  entry).
- Phase 1 already ships: `~/.hermes/plugins/talaria` with `store.py`
  (JSON device store, tokens SHA-256, deactivate-never-delete),
  `tools.py` (`talaria_phone_query`, check_fn=False gate), `admin.py`
  (`hermes talaria pair|status|unpair`), `plugin.yaml`.
- App surfaces: `InboxStore` ← `InboxServiceProtocol` (protocol seam;
  relay-backed today; `InboxLocalState.localItems` already persists
  local items), `SensorUploadService` (foreground lifecycle pattern),
  #133 durable installation identity, ATS already covers `:8642` on the
  tailnet CGNAT range (#166b).

## Architecture

Two builds meeting over `POST /api/platforms/talaria/events` on the
existing `:8642` listener. No new socket, no relay change of any kind.

```
Talaria app (Swift)                      talaria-plugin (Python, in-gateway)
┌───────────────────────┐   HTTPS :8642  ┌──────────────────────────────┐
│ TalariaPlatformLink   │──pair/drain──▶│ TalariaPlatformAdapter        │
│  (foreground loop)    │◀─items/queries─│  verify / dispatch / send    │
│ PhoneQueryResponder   │──query_result─▶│  durable outbox (store)      │
│ TalariaInboxService   │──ack──────────▶│  parked drains (asyncio)     │
│  → InboxStore (UI)    │                │ tools.py: talaria_phone_query │
└───────────────────────┘                └──────────────────────────────┘
```

## 1. Plugin side (`talaria-plugin` repo)

### 1.1 `platform.py` (new) — `TalariaPlatformAdapter(BasePlatformAdapter)`

- `connect()` → True (webhook mode; marks adapter available on the
  route). `disconnect()` → no-op. `get_chat_info(chat_id)` → static
  `{"name": "Talaria", "type": "device"}`.
- **`send(chat_id, text, …)` IS the durable outbox write.** Everything
  the agent or a cron job sends to the `talaria` platform appends an
  outbox item and wakes any parked drain. Survives gateway restarts.
- `verify_http_event_request(auth_header)`: accepts
  `Bearer <API_SERVER_KEY>` (constant-time compare, key from env) OR an
  active device token (SHA-256 lookup in the Phase 1 store). Anything
  else → `(False, "invalid_talaria_auth")`. Fail closed.
- `dispatch_http_event(payload)` — envelope contract, `type` required:

| type | auth required | request fields | response |
|---|---|---|---|
| `pair` | API key ONLY | `install_id`, `device_name` | `{device_id, device_token}` — re-pair on same `install_id` deactivates the prior row (#144) and mints fresh |
| `drain` | device token | `device_id`, `wait: bool` | held ≤25s until outbox item or query arrives (or immediate if `wait:false` / backlog exists) → `{items: [...], queries: [...]}`; timeout → both empty |
| `ack` | device token | `device_id`, `item_ids: [...]` | `{acked: [...]}` — idempotent; marks delivered (deactivate, never delete) |
| `query_result` | device token | `device_id`, `query_id`, `result` or `error` | `{ok: true}` — resolves the parked future; unknown/expired id → `{ok: false}` (harmless) |
| `unpair` | device token | `device_id` | `{ok: true}` — deactivates the device row |

  - Item shape: `{id, kind: "message", text, created_at, meta: {…}}`.
  - Query shape: `{id, kind, params}` (catalog kinds in §2.2).
  - Auth/`device_id` binding: device-token ops require the presented
    token to match the claimed `device_id` — a valid token for device X
    cannot act as device Y.
- Mismatched auth-vs-type (e.g. `pair` with a device token) → error
  dict, never an exception (the route 500s on raised exceptions; we
  answer clean errors instead).

### 1.2 `tools.py` — `talaria_phone_query` goes live

- `check_fn`: True iff a device has a drain parked RIGHT NOW or
  `last_seen` within 60s. Otherwise the tool stays gated exactly as
  Phase 1 left it (the model never burns a turn on a dead transport).
- Handler: enqueue `{id, kind, params}` for the freshest active device,
  wake its parked drain, await an `asyncio.Future` ≤25s → return the
  structured result as tool output. Timeout / no device / phone answers
  `error` → honest prose ("The phone did not answer — it is probably
  not open right now."), ordinary tool OUTPUT, never a throw.
- Queries are EPHEMERAL (in-memory, process-lifetime): a gateway
  restart drops parked queries and the tool answers unreachable —
  honest by construction.

### 1.3 `store.py` extension

Outbox alongside the Phase 1 device store (same JSON file family, 0600):
items `{id, text, created_at, meta, delivered_at | null, active}`.
`delivered` = deactivate-style flag; nothing is ever deleted. Drain
returns active undelivered items oldest-first (this IS
fetch-on-connect: first drain after days away delivers the backlog).

### 1.4 Registration + config

`plugin.py` gains `ctx.register_platform(name="talaria",
label="Talaria", adapter_factory=…, check_fn=lambda: True)`. Owen-side
enable (dev loop, Mac): `platforms.talaria.enabled: true` in
`~/.hermes/config.yaml` + gateway restart. OJAMD untouched (slice D).

## 2. App side (Talaria repo)

### 2.1 `TalariaPlatformLink` (new service)

- Foreground lifecycle, same pattern as `SensorUploadService`: start on
  scene-active when a Hermes profile exists; stop on background.
- **Auto-pair:** if profile present and no stored device token → POST
  `pair` with the profile's API key, `install_id` = #133's durable
  installation identity, `device_name` = device name. Token →
  keychain. No new user steps; `hermes talaria pair` (CLI) remains the
  power-user path. A 401 on a later call (token deactivated server-side)
  → clear token, re-pair once, then surface state honestly.
- **Drain loop:** long-poll (`wait: true`), immediately re-poll on any
  successful response; on error, exponential backoff 1s → 30s cap,
  degrade to `wait: false` polling until healthy. Received items →
  local inbox cache + `ack`; received queries → `PhoneQueryResponder`
  → `query_result` POST.

### 2.2 `PhoneQueryResponder` — the structured catalog

Executes catalog kinds via the SAME read machinery the on-device belt
uses (mind the device-only isolation trap: framework completions
`@Sendable`). Slice A kinds and their gates:

| kind | params | gate |
|---|---|---|
| `location` | — | Privacy master + location toggle + iOS permission |
| `health` | `metric`, `window` | Privacy master + health toggle + HealthKit auth |
| `motion` | `window` | Privacy master + motion toggle + iOS permission |
| `weather` | — | Privacy master + location toggle (it uses location) |
| `calendar` | `window_days` | iOS permission (not a sensor stream) |
| `reminders` | `list?` | iOS permission (not a sensor stream) |
| `deviceStatus` | — | none (battery/storage/net — same as belt) |

- Gating rule: the Privacy screen's master + per-stream toggles govern
  the SENSOR-shaped kinds exactly as they govern upload; calendar /
  reminders / deviceStatus follow iOS permissions only, matching the
  on-device belt's own behavior. A gated kind answers
  `{error: "permission_denied"}` — honest, never fabricated, and the
  agent's tool output says so plainly.
- **Contacts and conversation search are EXCLUDED from slice A** (most
  sensitive; each needs its own consent surface if ever added).

### 2.3 Inbox replacement (the deletion win)

- New `TalariaPlatformInboxService: InboxServiceProtocol` reads the
  local cache the drain loop fills (drain → persist → ack means the
  app-side cache is the user-facing history; the server keeps only
  deactivated rows). The relay-backed inbox service implementation is
  DELETED. Sensors and every other relay surface: untouched until
  Phase 4.
- Outbox item → `InboxItem` mapping decided in the plan against
  `InboxItem`'s current fields; `InboxLocalState` persistence extended
  rather than replaced (#113 local alerts keep leading).

### 2.4 UI

No new screens. One status row on the Server settings screen (pairing
state: `PAIRED · <device>` / `NOT PAIRED`, real data only, "—" when
unknowable). Everything else rides existing surfaces.

## 3. Data flows (canonical three)

1. **Briefing:** cron/agent → adapter.`send` → outbox append → parked
   drain wakes → app persists + acks → Inbox row. Phone closed for two
   days → items wait, first drain delivers the backlog exactly once.
2. **Live query:** agent turn → `talaria_phone_query(kind:"location")`
   → future parks + drain wakes → responder answers → `query_result` →
   tool returns structured data. Target: answer in ≤5s wall-clock with
   the app open.
3. **Phone closed:** `check_fn` False → tool gated → the model is told
   the tool is unavailable (never a burned turn); if forced anyway, the
   handler answers unreachable prose. No throw anywhere (#197 family).

## 4. Error handling

- Verifier fail-closed (route already 401s on our `(False, code)`).
- All dispatch errors are clean error dicts, never raised exceptions.
- Drain/ack idempotent: a re-delivered item de-dupes app-side on `id`;
  a double-ack is a no-op.
- Gateway restart: outbox survives (durable); parked queries die honest.
- App-side keychain token loss → re-pair automatically (API key is the
  root credential and the app already holds it).

## 5. Testing

- **Plugin (pytest, on the Mini):** dispatch-level units — pair mints /
  re-pair rotates / wrong-auth rejected; drain long-poll wakes on send
  and on query (asyncio, fake clock); ack idempotence; query_result
  resolves / expires; outbox durability across a store reload.
- **App (Swift Testing):** link state machine (auto-pair, 401 re-pair
  once, backoff ladder, drain parse), responder catalog (each kind's
  gate honored, fakes for frameworks), inbox mapping + de-dupe on id.
- **XCUITest:** existing 12 stay green; no new UI surface demands more.
- **E2E smoke (pre-bars):** Mac gateway + real phone: pair → cron send
  → inbox arrival → `phone.query` round-trip from a real agent turn.
- **Gate** before PR as always; bars pre-register in OPEN_ITEMS #251
  BEFORE the build (candidates, to be finalized at pre-registration:
  pair-e2e, live-query ≤5s, outbox exactly-once across restart, honest
  unreachable, relay-inbox deletion compiles + suite green, privacy
  gating verified per-kind).

## 6. Explicitly out of scope (slice A)

Interactive primitives (approvals/clarify/model-picker — Phase 3 rides
runs), conversational installer (B), desktop face (C), OJAMD + venv-CLI
retirement (D), voice WebRTC bootstrap home, #21 files home, contacts /
conversation-search kinds, ANY relay or connector change (⛔ standing),
Hermes core patches (never).

## 7. Rollout note

Owen's current briefing habits point at relay-era MCP tools; the e2e
smoke includes repointing one cron/agent send at the `talaria` platform
on the Mac. OJAMD production repointing is slice D's business.
