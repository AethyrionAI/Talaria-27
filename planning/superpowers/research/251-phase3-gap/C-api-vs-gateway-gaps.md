# C — Sessions API vs Gateway Platform Lane: Definitive Feature Gap Analysis

**Date:** 2026-08-05
**Subject:** #251 Phase 3 — what a gateway-dispatched platform turn gets that a Sessions-API turn does not, what the Sessions API keeps that platforms lack, and what neither has.
**Method:** read-only analysis of a Hermes clone at head `01a1037d1`. Every claim carries `file:line` evidence on both sides. Line numbers are from that commit.

---

## 0. The structural root cause

The two lanes are **two call graphs that both end at `AIAgent`**, not two configurations of one path.

- **Platform:** `BasePlatformAdapter.handle_message` (`gateway/platforms/base.py:5554`) → `_message_handler` (wired `gateway/run.py:11038`, resolved `:13570-13574`) → `GatewayRunner._handle_message` (`gateway/run.py:14270`) → `_handle_message_with_agent` → `TurnRunner.run_sync` (`gateway/run.py:4341`) → `agent.run_conversation`.
- **Sessions API:** aiohttp route → `_handle_session_chat{,_stream}` (`gateway/platforms/api_server.py:3515`, `:3632`) → `APIServerAdapter._run_agent` (`:5957`) → `agent.run_conversation` (`:6044`).

`APIServerAdapter` subclasses `BasePlatformAdapter` (`api_server.py:1345`) and *is* assigned a `_message_handler` by `run.py:11038` — but **no Sessions-API route ever invokes it**. Verified: `gateway/platforms/api_server.py` contains zero occurrences of `handle_message`, `_message_handler`, or `MessageEvent`.

**Consequence, and it is the whole report in one line:** everything wired onto `GatewayRunner` / `TurnRunner` is structurally unreachable from HTTP; everything living inside `run_agent.py` / `agent/` / `tools/` fires on both.

The code states the delivery half of this itself, at `gateway/platforms/api_server.py:1354-1361`:

```python
# Stateless request/response: every route ... tears down its channel when
# the turn ends. There is no persistent outbound channel to push a background
# completion to a client that already received its response, and ``send()``
# is a no-op stub.
supports_async_delivery: bool = False
```

Base default is the opposite — `supports_async_delivery: bool = True` (`gateway/platforms/base.py:2690`).

### Spine comparison

| Stage | Platform lane | Sessions-API lane |
|---|---|---|
| Auth | per-user authz + DM pairing (`gateway/run.py:8693`; `gateway/pairing.py:1-19`) | one bearer `API_SERVER_KEY` (`api_server.py:1119`) |
| Agent build | `gateway/run.py:19392`, kwargs `:4738-4770` | `api_server.py:2842`, kwargs `:2819-2841` |
| Agent identity | `platform=<platform>` (`run.py:4761`) | `platform="api_server"` (`api_server.py:2829`) |
| Toolset | `hermes-<platform>` = 62 core tools (`toolsets.py:31`) | `hermes-api-server` = 41-tool strict subset (`toolsets.py:426`) |
| Streaming | progressive message **edits** (`gateway/stream_consumer.py:1-13`, built `run.py:23795`) | token-level **SSE** (`api_server.py:3702-3805`) |
| Egress | `adapter.send()` + retry + ledger (`base.py:5042`, `:6062`) | HTTP body; `send()` is a failure stub (`api_server.py:7169-7179`) |

---

## 1. Server-initiated delivery / push / wake

### 1.1 Async-delivery capability — the master switch `[PLATFORM-ONLY]`
Propagated into a contextvar at session-bind time, read via `async_delivery_supported()` (`gateway/session_context.py:466-496`; contract `:104-122`). Platform `True` (`base.py:2690`); API `False` (`api_server.py:1361`). The API side is pinned structurally by `_bind_api_server_session` (`api_server.py:5948-5955`), which hardwires `async_delivery=False`.

**Concretely disabled on the API lane:** `terminal(notify_on_complete=…)` / `watch_patterns` are stripped and replaced with a "poll instead" notice (`tools/terminal_tool.py:2821-2845`); `delegate_task(background=True)` degrades to synchronous execution (`tools/delegate_tool.py:3194-3232`).

### 1.2 Wake — the API lane's partial escape hatch `[BOTH, different shape]`
`gateway/wake.py` branches on the same flag (`:45-53`, `:73-94`):
- **Platform:** injects a synthetic `MessageEvent(internal=True)` through `adapter.handle_message` (`:78-86`) → user receives an **unsolicited message**.
- **API:** self-POSTs `/v1/chat/completions` with the raw id in `X-Hermes-Session-Id` (`:96-176`).

The API variant works, but the docstring names the limit (`gateway/wake.py:19-20`): the result is "visible the next time the client **polls/reopens** the conversation." Background completions land in the transcript; **nothing tells the phone they arrived**. That is the exact shape of Talaria's "no push" pain — the agent can finish work asynchronously; the result has no doorbell.

Wake sources: Kanban watchers (`gateway/kanban_watchers.py:503-530`, `:648-690`), background-process / watch-pattern notifications (`gateway/run.py:21777-21787`, `:21813-21830`).

### 1.3 Proactive gateway notices `[PLATFORM-ONLY]`
Home-channel startup (`gateway/run.py:21090`, text `:21105`), restart (`:21011`, text `:21060`), shutdown-to-active-sessions (`:9198`, text `:9215`), session-stall policy (`gateway/session_stall.py:28`). All via `adapter.send()`; on the API server each fails at the stub and logs a warning (`gateway/run.py:21148-21155`).

---

## 2. Cron and scheduled sends

### 2.1 `deliver=<platform>` to a home channel `[PLATFORM-ONLY]`
`_deliver_result()` (`cron/scheduler.py:1467`, called `:4054`) resolves targets (`:1284`) then delivers via live adapter (`:1600`, `:1806-1826`) or standalone sender (`:1508`). Home-channel env vars `_HOME_TARGET_ENV_VARS` (`:264`); allowlist `_KNOWN_DELIVERY_PLATFORMS` (`:255`).

**`api_server` is in neither table.** No `API_SERVER_HOME_CHANNEL` exists. `deliver="api_server"` fails `_is_known_delivery_platform` (`:1229`) and yields no target.

Plugin platforms get first-class cron delivery via `cron_deliver_env_var` (`gateway/platform_registry.py:142`; consumed `cron/scheduler.py:997`, `:1014`, `:1078`) and `standalone_sender_fn` (`platform_registry.py:159`; consumed `tools/send_message_tool.py:747-756`). Documented `gateway/platforms/ADDING_A_PLATFORM.md:32-39`.

### 2.2 `/api/jobs*` — creation without a receive path `[API-ONLY creation, NEITHER delivery]`
The API can create/trigger/pause/delete jobs (`api_server.py:2013-2020`; handlers `:5451`, `:5622`, `:5642`). But `/run` returns the **job row, not the output**; `/api/cron/fire` returns 202 and detaches (`:5710-5723`). Only retrieval is polling `GET /api/jobs/{job_id}` for `last_output` (`:5505`; field `tools/cronjob_tools.py:571-575`).

**Trap:** `deliver="origin"` (`cron/scheduler.py:1147-1152`) skips the allowlist check the explicit-platform branch applies at `:1229`. An API-created job stamps origin `{"platform":"api_server","chat_id":"api"}` (`api_server.py:1670-1676`); an agent-created one gets `api_server:<session_id>` from `_origin_from_env` (`tools/cronjob_tools.py:315`) reading the vars `_bind_api_server_session` sets (`api_server.py:5947-5953`). Either way the job **fires, burns a full agent turn, saves `last_output`, and never delivers**. `tools/cronjob_tools.py:341`'s local-delivery notice only covers jobs with *no* origin. Compounding it: `PLATFORM_HINTS["cli"]` and `["tui"]` warn the model about exactly this failure mode; **`PLATFORM_HINTS["api_server"]` does not** (`agent/prompt_builder.py:929-941`).

### 2.3 `send_message` as an agent tool — **neither lane** `[NEITHER]`
Easy to over-claim from the existence of `tools/send_message_tool.py`. `toolsets.py:400-403` is explicit:

> "agents do NOT get an agent-callable send_message tool — outbound platform messaging is handled outside the agent loop (cron delivery, the gateway kanban notifier, and the `hermes send` CLI), not by the model deciding to send on its own."

Verified: `"send_message"` appears in **no** toolset tool list (only the comment at `:402` and the description at `:427`). Importers are `mcp_serve.py`, `hermes_cli/send_cmd.py`, `cron/scheduler.py`, and platform adapters — never the agent tool registry. **So "the agent can message you unprompted from another session" is NOT a platform-lane gain.** What the platform lane buys is that **cron and watchers** can reach you (§2.1, §1.2). *(Registration via a plugin/MCP registry path rather than static `toolsets.py` is unverified.)*

---

## 3. Delivery reliability layer `[PLATFORM-ONLY, wholesale]`

`grep -n "DeliveryRouter\|delivery_ledger\|dead_targets\|mirror_to_session\|channel_directory" gateway/platforms/api_server.py` → **zero matches**.

| Facility | Platform evidence | API |
|---|---|---|
| Retry + plaintext fallback + user-visible failure notice | `base.py:5042-5058` | absent |
| Crash-safe delivery ledger (record → attempting → delivered), redelivery after restart | `base.py:6062-6115`; sweep `gateway/delivery_ledger.py:236`; recovery `gateway/run.py:10308-10380`; bounds `delivery_ledger.py:61-65` | absent |
| Dead-target suppression | `gateway/delivery.py:344-383`; registry `gateway/dead_targets.py:48`, `:98`, `:104` | absent |
| Cross-platform session mirroring | `gateway/mirror.py:26` | absent |
| Chat/contact discovery | `gateway/channel_directory.py` | **explicitly excluded** — `_SKIP_SESSION_DISCOVERY = frozenset({"local","api_server","webhook"})` (`:172`, rationale `:167-171`) |
| Long-output truncation | 4000-char cap unless `splits_long_messages` (`gateway/delivery.py:24-30`) | **full text returned** (§12.4) |

---

## 4. Hooks — the standing claim needs splitting in two

There are **two independent hook systems**. The `CLAUDE.md` note "hooks don't fire for Sessions-API runs" is **correct for one and wrong for the other**.

### 4.1 Gateway `HookRegistry` `[PLATFORM-ONLY]` — CONFIRMED
Events: `gateway:startup`, `session:start`, `session:end`, `session:reset`, `agent:start`, `agent:step`, `agent:end`, `command:*`, `reaction:*` (`gateway/hooks.py:9-17`; wildcard `:162-173`). The registry is a `GatewayRunner` attribute (`gateway/run.py:6170-6171`, loaded `:10932`).

Complete emit inventory, all platform-lane: `gateway:startup` `run.py:11323` · `session:start` `:16345` · `agent:start` `:17473` · `agent:end` `:17721` · `command:<name>` `:14966` · `reaction:*` `:7153` · `agent:step` `:4282` · `session:compress` `:4299` · `session:end`/`session:reset` `gateway/slash_commands.py:238`, `:245`.

**`gateway/platforms/api_server.py` contains the substring `hooks` zero times** (verified by `grep -c`).

`agent:step` and `session:compress` are the two that *could* have crossed over, since they fire from inside the agent core (`agent/conversation_loop.py:1453-1476`; `agent/conversation_compression.py:3473`). They don't, because the bridging callbacks are never installed: the platform lane sets `agent.step_callback` (`gateway/run.py:4814`) and `agent.event_callback` (`:4849`), while the API lane's complete `agent_kwargs` (`api_server.py:2819-2841`) carries only `stream_delta_callback`, `tool_progress_callback`, `tool_start_callback`, `tool_complete_callback`. `AIAgent` defaults the others to `None` (`agent/agent_init.py:496`, `:503`), so the `if … is not None` guards short-circuit.

Corollary: `DELETE /api/sessions/{id}` (`api_server.py:3436-3447`) emits no `session:end` / `session:reset`, unlike `/new` on the platform lane.

### 4.2 Plugin lifecycle hooks `[BOTH]` — REFUTED for this system
`hermes_cli/plugins.py:135-218` (`VALID_HOOKS`), dispatched via `hermes_cli/lifecycle.py::invoke_hook`. Their call sites are in shared code, so they fire on **both** lanes: `on_session_start` (`agent/conversation_loop.py:575-580`), `pre_llm_call` (`agent/turn_context.py:1063-1075`), `pre/post_api_request` (`agent/conversation_loop.py:2290`, `:5734`), `api_request_error` (`run_agent.py:2850`), `pre/post_tool_call` (`model_tools.py:1492`, `:1104`), `transform_llm_output` / `pre_verify` (`agent/turn_finalizer.py:550`, `:572`, `:738`). `agent/shell_hooks.py` maps these onto shell scripts and inherits the behaviour.

Two exceptions: **`pre_gateway_dispatch` is platform-only** (sole site `gateway/run.py:14352`), and the **`surface="gateway"` approval hooks are platform-only in practice** (§5.1).

### 4.3 Not present at all `[NEITHER]`
`PreToolUse` / `PostToolUse` / `UserPromptSubmit` / `Notification` / `Stop` / `SessionStart` do not exist as dispatchable events here — only prose references (`tools/hook_output_spill.py:15`; `hermes_cli/hooks.py:608`). `gateway/builtin_hooks/` is empty by design (`gateway/hooks.py:72-79`).

---

## 5. Approvals / HITL

### 5.1 Exec / dangerous-command approval
Mechanism: `check_all_command_guards` (`tools/approval.py:3561`) resolves the session key (`:3742`) and `is_gateway` (`:3619` → `_is_gateway_approval_context`, `:243-261`, true whenever `HERMES_SESSION_PLATFORM` is non-empty). It then branches on a per-session notify callback: `notify_cb = _gateway_notify_cbs.get(session_key)` (`:3832`). If present, `_await_gateway_decision` (`:3436`) enqueues and **blocks the agent thread** on `entry.event.wait()` (`:3535`), released by `resolve_gateway_approval` (`:2338`).

**Platform `[YES]`** — registered per turn: `register_gateway_notify(_approval_session_key, _approval_notify_sync)` (`gateway/run.py:5329-5331`, unregistered `:5382`). The callback prefers adapter buttons (`gateway/run.py:5126-5129` → `send_exec_approval`) with a typed-prefix text fallback (`:5161-5169`).

**`/v1/runs` `[YES — full parity]`** — approval scope is deliberately the run id: `approval_session_key = run_id` (`api_server.py:6391`, stored `:6398`), `register_gateway_notify` (`:6524`). The notify callback (`:6464-6491`) redacts the command (`:6471-6473`), emits an `approval.request` SSE event, and sets `waiting_for_approval` (`:6483-6487`). Resolution `POST /v1/runs/{run_id}/approval` → `_handle_run_approval` (`:6772`): validates `{once, session, always, deny}` (`:6794`), calls `resolve_gateway_approval` (`:6821-6825`), 409s if nothing pending (`:6830-6837`), returns status to `running` (`:6839`). Advertised as `run_approval_response: True` / `approval_events: True` (`:3050-3052`).

**`/chat` and `/chat/stream` `[NO — degrades silently]`** — CONFIRMED, with mechanism. `_run_agent` binds session context (`api_server.py:6013-6017`) but **never calls `register_gateway_notify` or `set_current_session_key`** (repo-wide, the only callers are `tools/approval.py`, `tui_gateway/server.py`, `gateway/run.py:5331`, and `api_server.py:6524`). Yet `is_gateway` is still **true**, because `_bind_api_server_session` hardwires `platform="api_server"` (`:5948-5955`). So execution enters the gateway branch (`tools/approval.py:3829`), finds `notify_cb is None`, and takes the fallback at `:3936-3965`, returning `{"status":"pending_approval","approval_pending":True,…}` — which surfaces to the model as a tool result (`tools/terminal_tool.py:2604-2618`; same for `execute_code` at `tools/approval.py:4192-4218`).

The `submit_pending(...)` call at `tools/approval.py:3951` is a **dead end**: `_pending` is written (`:2383`) and popped by `clear_session` (`:2437`), but **nothing reads it** and no route exposes it. No human is ever asked and the approval is unrecoverable. The stream can't even report it — `_tool_progress` (`api_server.py:3733-3738`) forwards only `reasoning.available`, `tool.started`, `tool.completed`, `tool.failed`; there is no `approval.request` branch.

### 5.2 MCP elicitation consent auto-declines on the chat plane `[PLATFORM + /v1/runs only]` — new
`request_elicitation_consent` (`tools/approval.py:4292`) uses the same `_gateway_notify_cbs` lookup and **fails closed** when it is missing (`:4319-4327`): logs "failing closed" and returns `"decline"`. So on `/chat` and `/chat/stream`, **every MCP elicitation is auto-declined** — a silent capability loss that looks like the tool simply not working.

### 5.3 `clarify` `[PLATFORM-ONLY]`
Dispatched at `agent/tool_executor.py:1747-1755` using `agent.clarify_callback`. The platform lane installs it (`gateway/run.py:5015`; callback `:4933`, registers `:4941-4947`, flushes the stream for ordering `:4966-4975`, sends via `send_clarify` `:4979-4986`, blocks on `wait_for_response` `:5009`). Resolution via buttons (`tools/clarify_gateway.py:164`) or the **text intercept** — adapter bypass (`gateway/platforms/base.py:5668-5709`) plus runner resolver (`gateway/run.py:14538-14586`).

`grep -n "clarify" gateway/platforms/api_server.py` → **zero matches**. `agent.clarify_callback` is `None`, so the tool returns a flat error (`tools/clarify_tool.py:159-160`: *"Clarify tool is not available in this execution context."*). It is also absent from the default API toolset (§10).

### 5.4 Slash confirmations `[PLATFORM-ONLY]`
Only ever armed by `GatewayRunner._request_slash_confirm` (`gateway/run.py:20435`, registers `:20473`, sends `:20481`), whose callers are all slash handlers (`run.py:20427`; `slash_commands.py:2433`, `:5085`). Since slash commands never run on the API lane (§13), it is structurally unreachable — no confirm endpoint exists in the route table (`api_server.py:1986-2031`).

---

## 6. Inbound media

**The Sessions API is not image-blind** — worth stating up front, because "no file endpoint" invites the opposite assumption.

### 6.1 Images `[BOTH, different transport]`
- **API:** `_normalize_multimodal_content` (`api_server.py:550`) accepts `image_url` / `input_image` parts; the URL gate (`:625-634`) allows **`data:image/...` or `http(s)://` only**. Shared by `/chat` (`:3528`), `/chat/stream` (`:3646`), `/v1/chat/completions` (`:3925`), `/v1/responses` (`:5098`, `:5124`). No multipart handler exists — `_read_json_body` (`:3226`) is the only body reader. `POST /v1/runs` bypasses normalization entirely (`:6322`).
- **Platform:** raw bytes → `cache_image_from_bytes` (`base.py:825`) → local path on `MessageEvent.media_urls` (`base.py:2082-2083`) → native pixel parts (`gateway/run.py:15826-15828`, `:5341-5344`) or a pre-run `vision_analyze` pass (`:15860`), chosen by `_decide_image_input_mode` (`:15816`).

For a phone that already holds the bytes, a `data:` URL is workable. This is a **transport** difference, not a capability cliff.

### 6.2 Voice, audio files, video, documents `[PLATFORM-ONLY]`
The API rejects all with HTTP 400: `file`/`input_file` parts → *"uploaded files and document inputs are not supported on this endpoint"* (`api_server.py:643-646`); non-image `data:` URLs → `unsupported_content_type` (`:627-630`); unknown part types incl. OpenAI's `input_audio` → *"Only text and image_url/input_image parts are supported"* (`:650-653`).

Platform lane, all inside `if event.media_urls:` (`gateway/run.py:15790`): voice → STT (§7); audio files → path note (`:15897-15912`); video → path note (`:15915-15932`); documents → `cache_document_from_bytes` (`base.py:1880`) + `_build_document_context_note` (`run.py:2687`, injected `:15979-15980`). Inbound size validation exists only here (`base.py:838`, `:985`).

---

## 7. Transcription and TTS `[PLATFORM-ONLY]`

**STT.** `_enrich_message_with_transcription` is a `GatewayRunner` method (`gateway/run.py:21406`), gated on `config.stt_enabled` (`:21430`; `gateway/config.py:914`), invoked only from the media block (`:15864-15867`) for paths passing `_event_media_is_stt_input` (`:2647`). Transcript echo `:15873-15886`. `grep -n "transcribe" gateway/platforms/api_server.py` → **zero**. Note `transcribe_audio` is **not a registered agent tool** in any toolset, so the API lane cannot reach STT even indirectly.

**TTS.** Three emitters, all platform-only: streaming PCM (`gateway/streaming_tts_consumer.py:55`; adapter contract `base.py:4130-4159`; sole construction `gateway/run.py:24651-24665`), whole-file auto-TTS on voice input (`base.py:5960-5977`), `/voice all|voice_only` replies (`gateway/run.py:19031`, `:19111`, `send_voice` `:19174`). `grep -in "tts" gateway/platforms/api_server.py` → **zero**. Declared `"audio_api": False, "realtime_voice": False` (`api_server.py:3063-3064`).

**Precision:** the `text_to_speech` *tool* lives in a separate configurable `tts` toolset (`toolsets.py:224-228`), so a user *could* enable it for api_server. It is **not** in `hermes-api-server`'s default list. Even when called, its `MEDIA:<path>.ogg` output is not inlined (§8.2) and renders as a literal host path — a dead end without app-side work.

---

## 8. Outbound media and agent-written files — the #21 answer

The most consequential section for Talaria.

### 8.1 Platform lane: broad native attachment delivery `[PLATFORM-ONLY]`
`MEDIA_DELIVERY_EXTS` is the single source of truth — **~60 extensions** across images, video, audio, documents, spreadsheets, geospatial, presentations, archives, rendered web output (`base.py:1643-1670`). Two extractors consume it: `extract_media()` (explicit `MEDIA:` tags) and `extract_local_files()` (bare absolute paths the model merely mentions) — `base.py:1621-1627`.

Three delivery chains:
1. **Non-streaming reply** — `base.py:5883`, with bare-path promotion at `:5912-5924`.
2. **Post-stream rescan** — `_deliver_media_from_response` (`gateway/run.py:19184`, called `:18089`), explicit-tags-only by design (`:19196-19205`), dispatching to `send_multiple_images` (`:19259`), `send_voice` (`:19270`), `send_video` (`:19276`), `send_document` (`:19282`).
3. **Background task** — extract `run.py:19439`; sends `:19461`, `:19484`, `:19490`, `:19496`, `:19502`.

**Auto-append without the model mentioning the file:** `_collect_auto_append_media_tags` (`gateway/run.py:1518`, invoked `:5576-5581`, appended `:5592`) — allowlisted to four producer tools (`:1443`): `text_to_speech`, `text_to_speech_tool`, `image_generate`, `bfl_flux3_get_result`.

### 8.2 API lane: images only, ≤5 MB, four sites `[API — severely narrowed]`
`_resolve_media_to_data_urls` (`api_server.py:1031`) rewrites `MEDIA:<path>` → `![image](data:…;base64,…)`. Hard limits: 6 image extensions (`:1018`), 5 MB cap (`:1027`); non-image or oversize leaves the tag verbatim (`:1062-1066`).

Applied at exactly four sites: `/chat` (`:3599`), `/chat/stream` `assistant.completed` (`:3763`), `/v1/chat/completions` (`:4166`), `/v1/responses` (`:5300`). **Not on `/v1/runs`. Not on streaming deltas** — `_delta` (`:3729`) enqueues raw text, so a streaming client sees the literal `MEDIA:/Users/...` mid-stream and gets the data URL only in the terminal event.

The system prompt tells the model this verbatim (`agent/prompt_builder.py:934-941`):

> "Non-image files are NOT intercepted anywhere, and the runs endpoint intercepts nothing — a `MEDIA:` tag there renders as literal text exposing a raw host filesystem path."

**No download endpoint.** The route table is 33 rows (`api_server.py:1982-2028`); none serve files.

**Honest #21 summary:** an agent-written image under 5 MB *can* reach the phone today if the model emits a `MEDIA:` tag. Everything else — PDF, CSV, zip, .md, audio — is stranded on the API lane and natively deliverable on the platform lane. Note the shared limit: **`write_file` / `patch` / terminal artifacts are auto-delivered on neither lane** (`gateway/run.py:1443`); on the platform lane they arrive only if the model emits a tag or states the bare absolute path.

---

## 9. Rich and interactive output `[PLATFORM-ONLY]`

`api_server.py` has zero hits for `send_typing`, `edit_message`, `clarify`, `reaction`.

| Feature | Platform | API |
|---|---|---|
| Typing indicator + 2 s refresh loop | `base.py:3874`, `:4677`, wired `:5813-5815`; called `run.py:4113`, `:23817` | absent |
| Live per-tool status text ("is running pytest…") | `supports_status_text` + `set_status_text` (`base.py:2656-2674`) | absent |
| Progressive message edit | `gateway/stream_consumer.py:412`, used `:1424`, `:1797`, `:2206` | absent (SSE instead — richer, §12.1) |
| Clarify buttons | `base.py:3780` → `run.py:4979` | absent |
| Slash confirm buttons | `base.py:3745` → `run.py:20481` | absent |
| Model / choice picker | `gateway/slash_commands.py:2076`, `:3298-3323` | absent |
| Reactions | `base.py:4942` | absent |

---

## 10. Tools and toolsets `[PLATFORM-ONLY superset]`

Both call the same resolver, `_get_platform_tools` (`hermes_cli/tools_config.py:2223`) — platform at `gateway/run.py:24159`, API at `api_server.py:2807`. Defaults from `hermes_cli/platforms.py:42` (`default_toolset="hermes-api-server"`).

**Computed diff** (not eyeballed) between `_HERMES_CORE_TOOLS` (`toolsets.py:31-86`, what every `hermes-<platform>` bundle gets) and `hermes-api-server` (`toolsets.py:426-460`):

- **Core: 62 tools. API: 41. The API set is a strict subset — it contains nothing core lacks.**
- **Missing on the API lane (21):** `clarify`, `text_to_speech`, `computer_use`, the 12 `kanban_*` tools, and 6 desktop-GUI-gated tools (`read_terminal`, `close_terminal`, `open_preview`, `read_preview`, `focus_pane`, `react_to_message`).

For a phone client the ones that matter are **`clarify`** and **`text_to_speech`**; kanban matters only if multi-agent coordination is in scope; the desktop six are `HERMES_DESKTOP`-gated and moot.

Two further asymmetries:
- **`cronjob` is present but degraded** on the API lane (§2.2) — it fires and never delivers.
- **`disabled_toolsets` is silently ignored** on the API lane: the platform lane passes it (`gateway/run.py:4747`, sourced `:24160-24161`); the API `agent_kwargs` (`api_server.py:2819-2841`) has no such key. A global disable is honored on platform turns and not on API turns.

Note `hermes-gateway` (`toolsets.py:610`) is a **union bundle** for whole-gateway enumeration, not what any individual turn resolves to.

---

## 11. Skills

Discovery is identical — both go through `build_skills_system_prompt()` (`agent/prompt_builder.py:1600`). Two real differences:

1. **Per-platform disable lists diverge `[BOTH, different content]`.** `agent/prompt_builder.py:1637` resolves `get_disabled_skill_names(_platform_hint)`, which unions `skills.disabled` with `skills.platform_disabled.<platform>` (`agent/skill_utils.py:436-470`). Since the API lane pins `"api_server"` and the platform lane its own name, the two see different disable sets from one config.
2. **Auto-skill channel/topic bindings are gateway-only `[PLATFORM-ONLY]`.** `gateway/run.py:16469-16500` injects a skill payload into the first message of a new session (Telegram DM Topics, Discord `channel_skill_bindings`). No `auto_skill` concept exists in `api_server.py`.

`GET /v1/skills` (`api_server.py:3096`) is a read-only listing with no platform counterpart `[API-ONLY]`. The `skills_list`/`skill_view`/`skill_manage` tools are in both toolsets.

---

## 12. System prompt and prompt-time context

### 12.1 Platform hint `[BOTH, and the API's is actively costly]`
`agent.platform` is the source platform on the gateway lane (`gateway/run.py:4761`) and literally `"api_server"` on the API lane (`api_server.py:2829`); resolution at `agent/system_prompt.py:430-436`. The `api_server` hint (`agent/prompt_builder.py:929-941`) opens:

> "You're responding through an API server. The rendering layer is unknown — assume plain text. No markdown formatting (no asterisks, bullets, headers, code fences)."

Messaging hints (`telegram` `:739`, `webui` `:942`) enable full markdown **and** the `MEDIA:` delivery contract. For a SwiftUI client that renders markdown, the API hint is costing output quality every turn.

**Two levers:**
1. **Zero-code, today `[available now]`** — `_resolve_platform_hint` (`agent/system_prompt.py:73-120`) applies a `platform_hints.<platform>` config override with `replace`/`append` semantics. `platform_hints.api_server.replace` swaps that paragraph without touching Hermes core. **Worth doing regardless of the pivot.**
2. **Via the platform lane** — a plugin supplies its own `platform_hint` through `register_platform(**entry_kwargs)` (`hermes_cli/plugins.py:953-971`; field `gateway/platform_registry.py:111`; resolved `agent/system_prompt.py:437-445`).

### 12.2 Session-context prompt `[PLATFORM-ONLY]`
`build_session_context_prompt` (`gateway/session.py:479`, called `gateway/run.py:23127`) renders a `## Current Session Context` block — Source, Channel Topic, user identity, multi-user notes, room boundaries, PII redaction. Only non-test callers are in `gateway/run.py`. The API lane's sole prompt injection is the request body's `system_message` / `instructions` (`api_server.py:3532-3535`, `:3586`).

### 12.3 Runtime footer `[PLATFORM-ONLY]`
`build_footer_line` (`gateway/runtime_footer.py:151`) has exactly one non-test caller, `gateway/run.py:17704`. `api_server.py` never imports it, so `display.runtime_footer` and `/footer on` have no effect on API turns.

---

## 13. Slash commands `[PLATFORM-ONLY, entirely]`

`GatewaySlashCommandsMixin` (`gateway/slash_commands.py:101`) is mixed into the runner (`gateway/run.py:5704`), and dispatch is **inline inside `_handle_message`** — the `canonical == …` ladder starts at `gateway/run.py:15013` (`/new`, `/topic`, `/help`, `/status`, `/model` at `:15142`, …). There is no standalone dispatch function; the entry point *is* the message handler. Adapters pre-filter at `base.py:5595-5645`.

`grep -in "slash\|handle_command\|get_command" gateway/platforms/api_server.py` → **zero matches across all 7,188 lines.** A `message` beginning with `/` is passed verbatim to the model as user text.

Unreachable from an API client: `/new`, `/reset`, `/stop`, `/model`, `/undo`, `/status`, `/context`, `/approve`, `/deny`, `/footer`, `/yolo`, `/sethome`, `/topic`, `/profile`. Closest API equivalents — `POST /api/sessions` (new), `/fork` (branch), `/model` (lock), `/v1/runs/{id}/stop`, `/v1/runs/{id}/approval` — and the last two are **`/v1/runs`-only**, not available on `/chat/stream`.

---

## 14. Session identity, history, and memory

### 14.1 Identity `[PLATFORM stronger]`
Platform keys are derived server-side: `build_session_key(source, …)` (`gateway/session.py:1058`) composes `agent:<ns>:<platform>:<chat_type>[:scope][:chat][:thread][:user]`, namespace from `:1037`. `SessionSource` (`gateway/session.py:149`) carries 20+ routing fields. Rows are created with `session_key`, `chat_id`, `chat_type`, `thread_id`, `profile_name` (`gateway/session.py:2587`).

API keys are caller-supplied and advisory: `_parse_session_key_header` (`api_server.py:2046`), 403-gated on `API_SERVER_KEY` being set. `_handle_create_session` (`:3287`) inserts only `(id, source, model, model_config, system_prompt, started_at)` — **no `session_key`, chat, thread, or profile columns**.

### 14.2 Transcript persistence and reload `[BOTH, one subtle divergence]`
Neither path persists explicitly — `AIAgent` flushes to the same `SessionDB` (`run_agent.py:2258`), handed in at `gateway/run.py:4769` and `api_server.py:2834`. **But reload differs:** the platform lane loads with `repair_alternation=True` because "this load feeds LIVE REPLAY" (`gateway/session.py:3380`, called `gateway/run.py:16533`); the API lane uses defaults, i.e. `repair_alternation=False` (`api_server.py:3248` → `hermes_state.py:7265`).

### 14.3 Long-term memory scope `[BOTH present — PLATFORM far richer]`
Provider init is shared (`agent/agent_init.py:1715-1760`), so memory is *present* on both. The scoping inputs diverge sharply — `agent/agent_init.py:1733-1747` reads agent attrs to build per-user/per-chat scope:

| Kwarg threaded to memory providers | Platform (`gateway/run.py:4738-4770`) | API (`api_server.py:2819-2842`) |
|---|---|---|
| `gateway_session_key` | `ctx.session_key` (`:4768`) — always present | header value or **`None`** (`:2837`) |
| `user_id` / `user_id_alt` | `:4762-4763` | **absent** |
| `user_name` | `:4764` | **absent** |
| `chat_id` / `chat_name` / `chat_type` | `:4765-4767` | **absent** |
| `thread_id` | `:4767` | **absent** |

So on the API lane Honcho falls back to `session_id` (`plugins/memory/honcho/__init__.py:407`) — **memory dies with the transcript** unless the client sends `X-Hermes-Session-Key`, and there is **no per-user memory scoping at all**.

### 14.4 The transcript API works for platform sessions — with one real caveat
`/api/sessions*` reads the shared `state.db` generically, not an api-only store: `_handle_list_sessions` calls `db.list_sessions_rich(source=…)` with `source` **optional** (`api_server.py:3272`); `_handle_session_messages` calls `db.resolve_resume_session_id` then `db.get_messages` (`:3449`). A platform-lane row is in that table (`gateway/session.py:2587`), so it **is** readable.

**The caveat, verified:** `_session_response`'s `safe_keys` (`api_server.py:3202-3209`) exposes `id, source, user_id, model, title, started_at, ended_at, …, last_active, preview` and **omits `session_key`, `chat_id`, `chat_type`, `thread_id`, `profile_name`**. There is therefore **no API-visible mapping from a gateway chat scope to its session_id**. Practical mitigation: `source` *is* exposed and *is* a query filter, so a client whose platform is the sole writer of a given `source` can discover its sessions by `GET /api/sessions?source=<ours>` ordered by `last_active`. That is workable but is discovery-by-convention, not by key.

**Security note worth carrying forward:** `_handle_session_chat` only checks the row exists (`_get_existing_session_or_404`). Nothing stops a client POSTing to `/api/sessions/<a-telegram-session-id>/chat` and running an `api_server`-platform turn onto a Telegram transcript.

---

## 15. Multi-profile — two unrelated mechanisms

- **API `[API-ONLY]`:** URL prefix. Every row of `_http_route_table()` gets a `/p/<profile>/` twin, registered mechanically (`api_server.py:7029-7031`). Validation `_resolve_request_profile` (`:1901`) → 404 middleware (`:1960`); scoping `_profile_scope` (`:1931`), which falls back to the default profile's scope when multiplexing is on but no prefix was given (avoiding `UnscopedSecretError`). Per-profile API keys fail closed (`:1725-1737`); per-profile SessionDB cache keys on home path. The profile is carried across the executor hop explicitly, since ContextVars don't follow `run_in_executor` (`:6010-6014`).
- **Platform `[PLATFORM-ONLY]`:** content-based routing. `gateway/profile_routing.py` matches `platform` + `guild_id`/`chat_id`/`thread_id` by specificity, so a *single chat* can be routed to a profile. Per-adapter stamping at `gateway/run.py:13532`, `:13560`, `:13570`; the profile then namespaces the session key (`gateway/session.py:1037`) and lands in the row (`:2595`).

Neither subsumes the other: the API can't route a chat to a profile; the platform lane has no way to enumerate/switch profiles except the `/profile` slash command (`gateway/run.py:15040`).

---

## 16. Model pinning `[BOTH — and they partially interoperate]`

- **API:** `POST /api/sessions/{id}/model` → `_handle_session_model_lock` (`api_server.py:3843`), persisted via `_persist_session_runtime_lock` (`:2337`). Precedence documented and implemented at `:2661-2666`. A confirmed lock is an **execution contract**: it disables the fallback chain (`:2812-2816`) and fails closed if the provider can't resolve (`:2500-2503`).
- **Platform:** `/model` slash command (`gateway/slash_commands.py:1671`, dispatched `gateway/run.py:15142`), writing `_session_model_overrides[session_key]` (`slash_commands.py:2236`) with disk durability via `SessionEntry.model_override`. Interactive picker `send_model_picker` (`slash_commands.py:2076`).

**The bridge is one-directional.** `_session_model_override_for` (`api_server.py:2459-2484`) reaches into the live runner via `_gateway_runner_ref()` and even calls `_rehydrate_session_model_override`. So a user's `/model` on a platform **does** govern an API turn sharing that session key. There is **no reverse bridge** — `POST /api/sessions/{id}/model` writes the session row's `model_config`, which the gateway `/model` path does not read.

---

## 17. Drain, queueing, concurrency, interruption

| Behaviour | Platform | API |
|---|---|---|
| Message arriving mid-turn | queued in `_pending_messages` (`base.py:2783`; written `run.py:14740`, consumed `:7640-7685`) + burst debounce/merge (`base.py:5203-5252`) | no queue; each request independent |
| Queue survives shutdown | yes — `flush_pending_to_file` (`run.py:12950`, before `.clear()` at `:12961`), recovery next boot (`gateway/shutdown_flush.py`) | no — only an in-flight counter (`api_server.py:1458`) |
| Per-session serialization | turn lease (`gateway/turn_lease.py:1-19`, acquired `run.py:16521`) | **none — last-writer-wins** (`gateway/wake.py:40-42`) |
| Concurrency cap | n/a | global `max_concurrent_runs` → 429 (`api_server.py:1446`, `:5902`) |
| Drain refusal | user-visible chat message (`run.py:15591-15600`) | JSON 503 `gateway_draining` |
| Turn inactivity timeout | watchdog + hard interrupt (`run.py:2876`, `:25012-25021`) | none — the client's HTTP timeout is the only bound |
| Stop mid-turn | `/stop` → `request_hard_interrupt` (`run.py:22922`) | **`/v1/runs` only** — `_handle_stop_run` (`:6860`) reads `_active_run_agents[run_id]`, populated solely at `:6462`. A `/chat/stream` turn has no run id and **cannot be stopped**. |

**Correction made during this analysis:** a sub-finding claimed `/api/sessions/{id}/chat/stream` lacks a drain guard. **That is wrong.** Both `_handle_session_chat` (`api_server.py:3514`) and `_handle_session_chat_stream` (`:3631`) carry `@_admit_api_agent_request`, which calls `_draining_response()` at `:1122` before the handler body. A grep for the callee missed the decorator indirection. Drain semantics on the chat routes are intact.

---

## 18. Auth and identity

- **API:** one bearer `API_SERVER_KEY` (`api_server.py:1119`). Session continuation (`X-Hermes-Session-Id`) and memory scoping (`X-Hermes-Session-Key`) are both 403-gated on a key being configured (`:2064-2079`).
- **Platform:** per-user authorization (`gateway/run.py:8693`, `:10484`, `:14394`) with per-platform allow-list env vars, plus the code-based **DM pairing flow** (`gateway/pairing.py:1-19`: 8-char codes, 1 h expiry, rate limits, lockout).
- **Webhook-mode ingress** is authenticated by the **adapter's own verifier**, not `API_SERVER_KEY`: `POST /api/platforms/{platform}/events` → `verify_http_event_request(auth_header)` then `dispatch_http_event(payload)` (`api_server.py:1808-1893`, route `:2012`). Reference implementation `plugins/platforms/google_chat/adapter.py:1495`, `:1520`. **This is the integration point for the new lane, and it needs no new port.**

---

## 19. Capabilities NEITHER lane has — do not design against these

- **Any push/APNs/FCM transport.** `grep -rn "apns\|firebase\|fcm\|push_notification" gateway/ tools/` → **zero**. Hermes has no notion of mobile push. Wake reaches a *session*, never a *device*.
- **Any WebSocket on `:8642`.** No `WebSocketResponse` in `api_server.py`. Bidirectional/realtime needs a sidecar.
- **Realtime voice / audio API.** Declared `False` (`api_server.py:3063-3064`).
- **A file/download endpoint on `:8642`.** 33 routes, none serve files (`:1982-2028`). The `/api/files` family lives in the **dashboard app** (`hermes_cli/web_server.py`, `:9119`) — different app, different auth. Do not conflate.
- **An agent-callable `send_message` tool** (§2.3) — in no toolset on either lane.
- **STT as an agent tool.** `transcribe_audio` is in no toolset; on the platform lane it is a gateway pre-pass the model cannot invoke.
- **Auto-delivery of `write_file` / `patch` artifacts.** The auto-append allowlist is four producer tools (`gateway/run.py:1443`); ordinary written files need a model-emitted `MEDIA:` tag on either lane.
- **Multipart upload anywhere on `:8642`.** `_read_json_body` (`api_server.py:3226`) is the only body reader.
- **Claude-Code-style hook events** (`PreToolUse`, `Stop`, `UserPromptSubmit`, …) — not dispatchable here (§4.3).

---

## 20. Prioritized: what Talaria gains by adding the platform lane

### High — worth the pivot on their own
1. **Unsolicited / server-initiated delivery.** `adapter.send()` becomes a real transport, flipping `supports_async_delivery` to the base `True` (`base.py:2690`) and re-enabling wake-by-push (`gateway/wake.py:78-86`), `terminal notify_on_complete` / `watch_patterns` (`tools/terminal_tool.py:2821-2845`), and `delegate_task(background=True)` (`tools/delegate_tool.py:3194-3232`). **Talaria is unusually well positioned:** the relay already owns APNs, so our `send()` can POST to the relay and become the doorbell the API lane structurally lacks. This is app+relay-side work — **no Hermes core change**, and it is *new surface on our side*, not hardening bolted onto the connector.
2. **Native file delivery for the #21 class.** ~60 extensions via `send_document`/`send_video`/`send_voice` (`base.py:1643-1670`; dispatch `run.py:19259-19282`) versus images-only-≤5 MB-base64 (`api_server.py:1018-1066`). Largest single capability delta in this report.
3. **Cron / scheduled briefs that actually arrive.** `cron_deliver_env_var` + `standalone_sender_fn` (`platform_registry.py:142`, `:159`) give a real home-channel target. Today `deliver="api_server"` has no target (`cron/scheduler.py:255-281`) and `deliver="origin"` silently burns a full turn per fire with no warning in the prompt (§2.2).
4. **Delivery reliability.** Retry (`base.py:5042`), crash-safe ledger with redelivery after restart (`base.py:6062-6115`, `run.py:10308-10380`), dead-target suppression (`gateway/delivery.py:344-383`). A phone on flaky LTE is precisely the case this was built for.

### Medium — real, but earn their keep after the above
5. **Inbound voice notes with automatic STT** (`run.py:21406`, `:15864-15867`) plus documents/audio/video as first-class attachments (`:15790-15980`) — versus HTTP 400 today (`api_server.py:643-653`).
6. **Working HITL on the chat plane.** Today, on `/chat/stream`, exec approvals degrade to an unrecoverable tool result (`tools/approval.py:3936-3965`) **and every MCP elicitation is auto-declined** (`:4319-4327`). The platform lane fixes both. *(Partial alternative: move approval-bearing turns to `/v1/runs`, which already has full parity — §5.1.)*
7. **`clarify` as tappable buttons** (`base.py:3780`), restored by leaving the API toolset behind (§10).
8. **Richer long-term memory scope** — `user_id`, `chat_id`, `thread_id` threaded into providers (`run.py:4762-4767`) instead of session-id-only (§14.3).
9. **Gateway hooks firing** (`run.py:17473`, `:17721`) — `agent:start`/`agent:end` automation, currently impossible (§4.1).
10. **Slash commands** — 5,545 lines with zero API surface (§13). Valuable, but much of it duplicates UI we already build natively; treat as a bonus, not a driver.
11. **Owning the system-prompt hint** (`hermes_cli/plugins.py:953-971`). *Note the config-override lever in §12.1 gets most of this today for free — take that first.*
12. **Per-user authz + pairing** (`gateway/pairing.py`) instead of one shared bearer key.

### Low — nice, or not applicable to a phone
13. Typing indicators and live per-tool status text (`base.py:4677`, `:2656`) — our SSE `tool.started` stream is arguably richer already.
14. Session-context prompt block and runtime footer (§12.2, §12.3) — modest prompt-quality gains.
15. TTS reply modes (`run.py:19031-19174`) — only if voice output becomes a product goal.
16. Kanban tools, reactions, model/choice pickers, cross-platform mirroring, content-based profile routing — no phone use case today.

---

## 21. API-plane strengths we must NOT lose

Keep the API lane **alongside** the platform lane — they are independent and already coexist in one process.

1. **Token-level SSE streaming with reasoning on a separate channel.** `run.started`, `message.started`, `assistant.delta`, `tool.started`/`tool.completed`/`tool.progress`, `assistant.completed`, `run.completed` (with `usage` + full turn transcript), `done` (`api_server.py:3702-3805`). The platform equivalent is progressive message **edits** (`gateway/stream_consumer.py:1-13`) — coarser, rate-limited, and needing an editable surface. **Keep chat on `/chat/stream`.**
2. **Structured session history + fork.** `/api/sessions`, `/messages`, `/fork`, `PATCH`, `DELETE` — no platform-lane HTTP equivalent exists. These keep working for platform-lane sessions (§14.4), **but plan the id-discovery story explicitly**: `session_key` is not exposed (`api_server.py:3202-3209`), so discovery must go through the `source` filter.
3. **Model pinning.** The one-directional bridge (`api_server.py:2459-2484`) means a platform `/model` governs API turns on the same key. Preserve by keying both lanes on the same session key.
4. **Full-length, untruncated responses.** If we register an adapter, set `splits_long_messages = True` (`base.py:2698`) or the 4000-char cap (`gateway/delivery.py:24-30`) will start clipping replies that arrive intact today.
5. **`/v1/runs` as a job API** — parked approvals with full choice parity, `stop`, and an events SSE (§5.1). This is a genuine API-lane strength the platform lane does not replace.
6. **Introspection:** `/v1/capabilities`, `/v1/skills`, `/v1/toolsets`, `/api/model/options` — no platform equivalent.
7. **Multi-profile by URL prefix** (`api_server.py:7029-7031`) — orthogonal to, and more client-controllable than, content-based routing.

**Design implication — the target is a hybrid.** Chat stays on the Sessions API for streaming UX, history and model control. The platform adapter exists for **delivery** (push, files, cron, reliability) and **inbound media**. `POST /api/platforms/{platform}/events` (`api_server.py:1808`, route `:2012`) lets the adapter be webhook-mode with no extra port and adapter-owned auth.

**The one thing that could quietly break it:** session identity. A platform turn keys on `build_session_key(source)`; an API turn keys on whatever header we send. If those don't match byte-for-byte, we get **two divergent memory scopes and two transcripts for what the user sees as one conversation**. Resolve this before committing to the design — a `build_session_key`-shaped `X-Hermes-Session-Key` (`agent:main:<ourplatform>:dm:<chat>`) is the likely answer and is testable today without writing an adapter.

---

## 22. Corrections made during this analysis

Recorded because each was a plausible wrong answer that live reading killed:

1. **`/chat/stream` *is* drain-guarded** — the guard is in the `@_admit_api_agent_request` decorator (`api_server.py:1119-1124`, applied `:3631`). Grepping for the callee missed the decorator.
2. **`send_message` is not agent-callable on either lane** (`toolsets.py:400-403`) — so it is not a platform-lane gain, contrary to the natural reading of `tools/send_message_tool.py`.
3. **The Sessions API accepts images** via `data:`/`http(s)` content parts (`api_server.py:550`, `:625-634`) — it is not image-blind.
4. **"Hooks don't fire for Sessions-API runs" is half right.** True for the gateway `HookRegistry` (§4.1); **false** for plugin lifecycle hooks, which fire on both (§4.2). The standing `CLAUDE.md` note should be qualified.
5. **`text_to_speech` is not in the API default toolset** (computed diff, §10), though a separate `tts` toolset exists — a nuance a description-only reading gets wrong in the other direction.
6. **The `api_server` platform hint is config-overridable today** (`agent/system_prompt.py:73-120`) — a zero-code win the pivot would otherwise be credited with.
7. **"Platform sessions are readable via the Sessions API" needed qualifying** — mechanically true, but `session_key` is not exposed (`api_server.py:3202-3209`), so discovery must go through the `source` filter.

---

## 23. Open / unverified

- Whether `POST /v1/runs` tolerates a content-part list in `input` — it bypasses `_normalize_multimodal_content` entirely (`api_server.py:6322`).
- Whether `send_message` is registered into a toolset via a plugin/MCP registry path rather than static `toolsets.py`.
- Whether `_run_agent_via_proxy` (`gateway/run.py:24140-24148`, gateway-proxies-to-remote-API mode) preserves platform-lane prompt/context injection — a **third** dispatch path nobody traced.
- Exact `SessionDB.update_session_runtime_lock` persistence/expiry semantics.
- Whether `get_home_channel(Platform.API_SERVER)` can return non-None (moot — the send stub fails regardless).
- Concrete adapter overrides of `send_typing`/`edit_message` across the ~20 shipped adapters were not audited; only the base class and gateway call sites.
- **Highest-value item to verify before committing to the hybrid:** whether a `build_session_key`-shaped `X-Hermes-Session-Key` sent from the current API client actually lands in the same memory scope and transcript a platform adapter would produce (§21).
