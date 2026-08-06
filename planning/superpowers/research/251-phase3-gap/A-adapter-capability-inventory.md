# A — Platform-Adapter Capability Inventory

**Scope:** everything the Hermes gateway runtime hands a registered platform adapter for free —
capabilities the plain HTTP Sessions API client (Talaria today) does not get.

**Source of truth:** read-only clone at
`/private/tmp/claude-501/-Users-owenjones-Documents-Claude-Talaria-27/22e57a75-8a46-4c55-bea2-395a07d0e604/scratchpad/hermes-agent-ro`.
All `file:line` references are against that tree. Nothing here is inferred from documentation
alone; every entry has a code citation.

---

## 0. The load-bearing fact this whole document rests on

`APIServerAdapter` **is** a `BasePlatformAdapter` subclass
(`gateway/platforms/api_server.py:1345`) — but it participates in essentially **none** of the
adapter runtime. Its `send()` is a hard-coded failure stub:

```python
# gateway/platforms/api_server.py:7169-7180
async def send(self, chat_id, content, reply_to=None, metadata=None) -> SendResult:
    """Not used — HTTP request/response cycle handles delivery directly."""
    return SendResult(success=False, error="API server uses HTTP request/response, not send()")
```

It never calls `self.handle_message()`; its HTTP handlers
(`_handle_session_chat` at `api_server.py:3515`, `_handle_session_chat_stream` at
`api_server.py:3632`) build and run an agent directly. Consequences, each verified:

| Runtime facility | Reaches the API path? | Evidence |
|---|---|---|
| `handle_message` pipeline (session guards, typing, media dispatch, TTS, ledger) | **No** | `base.py:5554`, `base.py:5786` — only entered via `adapter.handle_message()`, which api_server never calls |
| Slash commands (92 registered) | **No** | zero `slash`/`COMMAND_REGISTRY`/`resolve_command` references in `api_server.py` |
| Hooks (`agent:start`, `agent:end`, `session:*`, `command:*`, `reaction:*`) | **No** | every `hooks.emit` call site lives in `gateway/run.py` (`11323`, `16345`, `17473`, `17721`) / `gateway/slash_commands.py` (`238`, `245`) — the `GatewayRunner` path |
| Approvals | **`/v1/runs` only** | `api_server.py:6464-6544` registers `_approval_notify` inside `_handle_runs`; the `/api/sessions/{id}/chat*` handlers register nothing |
| Proactive push (background completions, kanban, cron) | **No** | `supports_async_delivery = False` at `api_server.py:1361`; `kanban_watchers.py:503-520` explicitly *skips* the send for non-push adapters |
| Media delivery | **images only, base64, ≤5 MB** | `api_server.py:1019-1077` — `_MEDIA_IMG_EXT`, `_MEDIA_DATA_URL_MAX_BYTES = 5MB`; non-image `MEDIA:` tags render as literal host paths (see the platform hint at `agent/prompt_builder.py:929-941`) |

So the pivot's real payoff is not "a few extra methods" — it is moving from a code path that
deliberately opts out of the runtime to the one the runtime was built for.

Registration itself is one call: `ctx.register_platform(...)` →
`PlatformEntry` (`hermes_cli/plugins.py:953-1004`, `gateway/platform_registry.py:38-159`).
The gateway then wires the adapter in a single block at `gateway/run.py:11039-11048`:
`set_message_handler`, `set_fatal_error_handler`, `set_session_store`,
`set_busy_session_handler`, `set_reaction_handler`, `set_topic_recovery_fn`,
`set_authorization_check`, `_busy_text_mode`, plus the `gateway_runner` back-reference
(`base.py:2748`).

---

## Summary table

Value ratings are **for a phone client** specifically.

| # | Capability | Evidence | Adapter must implement | Value |
|---|---|---|---|---|
| 1 | Proactive async delivery / wake | `base.py:2676-2690`; `gateway/wake.py:45-94`; `run.py:21777-21830` | nothing (default `True`) + a real `send()` | **High** |
| 2 | `MEDIA:` native attachment pipeline | `base.py:4457`, `5872-6180`; `base.py:3915/4062/4205/4232/4305` | `send_image_file`/`send_document`/`send_voice`/`send_video` | **High** |
| 3 | Auto-TTS on voice input (+ voice-first ordering) | `base.py:3139`, `4091`, `4108`; `_process_message_background` TTS block ≈ `base.py:5952-6035` | `send_voice` (or `play_tts`) | **High** |
| 4 | Streaming TTS (PCM during generation) | `base.py:4130-4165`; `gateway/streaming_tts_consumer.py:1-30` | 5 methods, opt-in | **High** |
| 5 | Inbound STT / voice-note transcription + echo | `run.py:21406-21553`; echo at `run.py:15862-15884`; `config.py:914` | populate `media_urls` + `MessageType.VOICE` | **High** |
| 6 | Inbound vision routing (native attach vs pre-analyze) | `run.py:15810-15862` | populate `media_urls` + `MessageType.PHOTO` | **High** |
| 7 | Progressive streaming: edit / draft / fresh-final | `stream_consumer.py:128-153`, `192-322`; `base.py:2943/2962/2985/3002/3552/3581` | `edit_message` (min) | **High** |
| 8 | Dangerous-command approval prompts | `run.py:5095-5185`; `base.py:3691`, `2710` | nothing (text fallback) / `send_exec_approval` for buttons | **High** |
| 9 | Mid-turn interrupt / queue / **steer** | `run.py:8223-8233`, `8874-8960`; `base.py:5554-5757` | nothing | **High** |
| 10 | Busy-guard command bypass (`/stop`, `/approve`, …) | `base.py:5593-5709` | nothing | **High** |
| 11 | Full slash-command surface (92 commands) | `hermes_cli/commands.py` (`CommandDef` ×92); `gateway/slash_commands.py` | nothing | **High** |
| 12 | Typing indicator + live status text | `base.py:2650-2674`, `3874`, `4677-4761`; `run.py:3640-3657`, `24258-24270` | `send_typing` (+ `supports_status_text`) | **High** |
| 13 | Tool-progress / thinking / interim-assistant surfaces | `run.py:24255-24300`, `3631-3670`; `base.py:3044-3121`; `gateway/stream_dispatch.py` | nothing (override `format_tool_event` to customise) | **High** |
| 14 | `clarify` prompts (buttons or numbered-text fallback) | `base.py:3780-3852` | nothing / `send_clarify` for buttons | **High** |
| 15 | Durable delivery-obligation ledger | `gateway/delivery_ledger.py:1-38`, `179-235`; `base.py:6062-6110`; `run.py:10289-10360` | nothing | **High** |
| 16 | Cron `deliver=<platform>` targeting + home channel | `cron/scheduler.py:266-280`, `1002-1011`; `platform_registry.py:138-159`; `delivery.py:213-291` | `cron_deliver_env_var` (+ optional `standalone_sender_fn`) | **High** |
| 17 | Per-platform system-prompt hint | `agent/system_prompt.py:431-465`; `platform_registry.py:108-111` | `platform_hint=` on the entry | **High** |
| 18 | Normalized inbound media cache | `base.py:825/854/976/1093/1880/1966`, `729-799` | call the cache helpers | **High** |
| 19 | Message chunking / length model | `base.py:6692-6720`, `2698`, `2851-2881` | `MAX_MESSAGE_LENGTH` / `splits_long_messages` | Medium |
| 20 | Ephemeral (auto-deleting) system replies | `base.py:2375-2412`, `3602-3658`, `4992-5012` | `delete_message` | Medium |
| 21 | Reaction-ack lifecycle (👀 → ✅/❌) | `base.py:4915-4960` | `_ACK/_OK/_FAIL_EMOJI` + `_add_reaction`/`_remove_reaction` | Medium |
| 22 | Reaction events → hook fan-out | `base.py:3349-3366`; `run.py:7144-7153`, `11042` | call `self._reaction_handler(...)` | Medium |
| 23 | DM pairing-code onboarding | `gateway/pairing.py:1-19`, `405-663`; `run.py:14399-14450` | nothing | Medium |
| 24 | Allowlist / allow-all / delegated authz | `gateway/authz_mixin.py:386-560`, `785+`; `base.py:2884/2912` | `allowed_users_env` / `allow_all_env`, or override the two flags | Medium |
| 25 | Media-delivery path validation + denylist | `base.py:1451-1537`, `1196-1221`, `4334-4362` | nothing | Medium |
| 26 | Send retry, error classification, dead-target registry | `base.py:5042-5132`, `2284-2373`; `gateway/dead_targets.py:1-24`; `delivery.py:341-391` | populate `SendResult.error` | Medium |
| 27 | Reconnect-aware final delivery | `base.py:5014-5041`; reconnect backoff `run.py:3606-3612` | nothing | Medium |
| 28 | Threading: `create_handoff_thread` + CLI→platform handoff | `base.py:3525-3549`; `run.py:11616-11730` | `create_handoff_thread` | Medium |
| 29 | Continuable cron threads / in-channel continuation | `cron/scheduler.py:754-870`; `base.py:2712-2725` | `create_handoff_thread` (+ `supports_inchannel_continuable`) | Medium |
| 30 | Channel directory + cross-platform `send_message` | `gateway/channel_directory.py:142-215`, `268-292` | optional `list_channels()` | Medium |
| 31 | Slash-confirm three-option prompt | `base.py:3745-3778`; `slash_commands.py:2433`, `5085` | nothing / `send_slash_confirm` | Medium |
| 32 | Choice / model pickers | `slash_commands.py:3298-3340`, `1779`, `2076`; `base.py:3716-3743` | `send_choice_picker` / `send_model_picker` | Medium |
| 33 | Photo-burst merge + text debounce | `base.py:2438-2527`, `5149-5311`, `5718-5747` | nothing | Medium |
| 34 | Session keying (chat / thread / user) | `gateway/session.py:1058-1130`; `base.py:5578-5582` | pass fields to `build_source` | Medium |
| 35 | Per-platform display config | `gateway/display_config.py:1-21` | nothing | Medium |
| 36 | Shutdown / restart notifications | `run.py:9250-9395` | nothing | Medium |
| 37 | Structured stream-event render hooks | `gateway/stream_events.py:1-24`; `stream_dispatch.py:1-21`; `base.py:3029-3121` | optional overrides | Medium |
| 38 | Runtime status + fatal-error surfacing | `base.py:3157-3215`, `3123-3137` | call `_mark_connected` / `_set_fatal_error` | Medium |
| 39 | Reply-context / thread metadata plumbing | `base.py:66-140`, `2086-2100` | populate `reply_to_*` | Medium |
| 40 | Per-channel prompts + skill bindings | `base.py:2528-2612`; `MessageEvent.auto_skill/channel_prompt` `base.py:2102-2108` | call the resolvers | Medium |
| 41 | Lifecycle hooks (`agent:*`, `session:*`, `command:*`) | `gateway/hooks.py:9-37`, `52-227`; `run.py:16345/17473/17721` | nothing | Medium |
| 42 | Session mirroring (cross-platform transcript echo) | `gateway/mirror.py:25-93` | nothing | Low |
| 43 | Silence-narration / `NO_REPLY` filtering | `delivery.py:36-55`, `525-544`; `response_filters.py:1-24` | nothing | Low |
| 44 | Runtime footer (model / context% / latency) | `gateway/runtime_footer.py:1-24` | nothing | Low |
| 45 | Post-delivery callback chain | `base.py:4819-4909` | nothing | Low |
| 46 | Drain control (external quiesce marker) | `gateway/drain_control.py:1-49`; `run.py:7835-7850` | nothing | Low |
| 47 | Single-instance platform lock | `base.py:3217-3291` | call `_acquire_platform_lock` | Low |
| 48 | Profile routing (per-chat profile isolation) | `gateway/profile_routing.py:1-24`; `base.py:6613-6642` | nothing | Low |
| 49 | Turn lease (per-session-id serialization) | `gateway/turn_lease.py:1-25` | nothing | Low |
| 50 | Kanban board notifications | `gateway/kanban_watchers.py:1-9`, `480-560` | nothing | Low |
| 51 | Human-delay pacing | `base.py:5759-5784` | nothing | Low |
| 52 | Sticker description cache | `gateway/sticker_cache.py:1-13` | populate sticker events | Low |

---

## 1. Proactive / async delivery — the single biggest gap

### 1.1 `supports_async_delivery` + the wake path — **High**

`base.py:2676-2690` declares the capability; the default is `True`, and
`api_server.py:1361` explicitly sets it `False`:

> *"True for adapters that hold a persistent outbound channel (Telegram, Discord, Slack, … —
> they have a real `send()` and the gateway runs the watcher/drain loops). False for stateless
> request/response adapters (the API server): every route closes its channel when the turn ends,
> so there is nowhere to push a later completion."*

The gateway propagates this into the `HERMES_SESSION_ASYNC_DELIVERY` contextvar
(`gateway/session_context.py:115-120`, `466`), and tools read it before promising delivery —
`tools/terminal_tool.py:2821` (background process `notify_on_complete` / `watch_patterns`) and
`tools/delegate_tool.py:3194-3195` (`delegate_task background=True`). **Today the agent refuses
to make those promises to Talaria at all.**

Delivery itself: `gateway/wake.py:56-94` — a push-capable adapter gets a synthetic
`MessageEvent(internal=True)` through `adapter.handle_message`, running a real turn in the real
session. The non-push fallback is a self-POST to `/v1/chat/completions`
(`wake.py:97-160`), whose result the client only sees *next time it polls*.
Callers: `run.py:21749-21840` (`_inject_watch_notification`), `kanban_watchers.py:652-760`.

**Adapter must implement:** nothing — just don't set the flag `False`, and provide a working
`send()`.
**Phone value: High.** This is the difference between "the phone must be open and polling" and
"a long-running task pings you when it's done."

### 1.2 Cron `deliver=<platform>` targeting — **High**

`cron/scheduler.py:266-280` holds the built-in `<PLATFORM>_HOME_CHANNEL` map; plugin platforms
join it purely by setting `cron_deliver_env_var` on their `PlatformEntry`
(`scheduler.py:1002-1011`, `platform_registry.py:138-142`). Routing/parsing lives in
`gateway/delivery.py:213-291` (`DeliveryTarget.parse` — `origin` / `local` /
`talaria` / `talaria:<chat>:<thread>`), dispatch in `delivery.py:460-642`.
`standalone_sender_fn` (`platform_registry.py:144-159`) covers cron running out-of-process.

**Adapter must implement:** `cron_deliver_env_var` on the entry (one string); optionally
`standalone_sender_fn`.
**Phone value: High.** Scheduled briefings landing in the app is a marquee phone feature that
the Sessions API cannot express at all.

### 1.3 Shutdown / restart notifications — **Medium**

`run.py:9250-9395`: on shutdown the runner pings every chat with an active session
("your task was cut off, message me to resume"), then broadcasts to each platform's home channel
— suppressible per-platform via `gateway_restart_notification`, and globally via the drain
marker's `suppress_notification` (`drain_control.py:229-251`).
**Phone value: Medium** — good UX, not load-bearing.

---

## 2. Outbound rendering and media

### 2.1 The `MEDIA:` attachment pipeline — **High**

`extract_media` (`base.py:4457-4572`) pulls `MEDIA:<path>` tags and the `[[audio_as_voice]]` /
`[[as_document]]` directives out of the reply; `extract_local_files` (`base.py:4593`) catches
bare paths from weaker models; `extract_images` (`base.py:4015`) pulls markdown/HTML image URLs.
The dispatch block in `_process_message_background` (`base.py:5872-6180`) then partitions by
type and routes to `send_multiple_images` (`3915`), `send_animation` (`3991`),
`send_image_file` (`4305`), `send_voice` (`4062`), `send_video` (`4205`), `send_document` (`4232`),
with per-turn dedup against transcript history (`_history_media_paths_for_session`,
`base.py:3416-3468`) and a user-visible failure notice on upload failure
(`_notify_media_delivery_failure`, `base.py:4266-4303`).

Hardening you get free: false-positive masking for code fences / blockquotes
(`_mask_protected_spans`, `base.py:4366`) and for serialized JSON tool results
(`_mask_json_string_media`, `base.py:4417`).

**Adapter must implement:** the `send_*` methods it wants native (each has a graceful
"⚠️ Couldn't deliver…" default that never leaks host paths).
**Phone value: High.** Today Talaria gets images only, base64, ≤5 MB
(`api_server.py:1019-1077`); audio, video, and documents are simply not intercepted.

### 2.2 Media-delivery path validation — **Medium**

`validate_media_delivery_path` (`base.py:1451-1537`) plus safe roots (`1161-1179`), the
hard denylist `/etc /proc /sys /dev /root /boot /var/{log,lib,run}` (`1196-1206`), `$HOME`
credential dirs `.ssh .aws .gnupg .kube .docker .config .azure .gcloud Library/Keychains`
(`1211-1221`), and a recency-trust window (`1188`, default 600 s). Exposed on the adapter as
static helpers at `base.py:4334-4362`.
**Phone value: Medium** — it's the guardrail that makes arbitrary-file delivery safe to enable.

### 2.3 Voice output: auto-TTS and streaming TTS — **High**

*Whole-file auto-TTS.* `_should_auto_tts_for_chat` (`base.py:3139-3152`) implements the
three-layer decision (`/voice on|tts` → always, `/voice off` → never, else `voice.auto_tts`).
`prepare_tts_text` (`base.py:4091-4106`) strips `<think>` blocks and expands units
(`°C` → "degrees Celsius") via `tools.tts_text_normalize`. `play_tts` (`base.py:4108-4120`)
lets an adapter do invisible playback. `build_auto_tts_output_path` (`base.py:164`) and
`should_send_media_as_audio` (`base.py:141`) pick the right container per platform. The
gateway fires it **before** the text, for a voice-first experience
(`base.py:5952-6035`).

*Streaming TTS.* `supports_streaming_tts` / `begin_` / `write_` / `finish_` / `abort_streaming_tts`
(`base.py:4130-4165`) accept PCM chunks while the LLM is still generating;
`gateway/streaming_tts_consumer.py:1-30` is the sentence-chunking bridge from the agent's sync
delta callback. Per-turn dedup so whole-file TTS doesn't double up
(`base.py:4167-4203`, `594-632`).

**Adapter must implement:** `send_voice` for whole-file; the five streaming methods to opt in.
**Phone value: High.** Hands-free / CarPlay-style use is exactly a phone's differentiator, and
none of this exists on the API path.

### 2.4 Progressive streaming transports — **High**

`GatewayStreamConsumer` (`stream_consumer.py:156-322`) owns the whole streamed-reply lifecycle:
adaptive edit interval with flood backoff (`_MAX_FLOOD_STRIKES = 3`, `:173`), think-tag
suppression (`:178-185`), overflow splitting with code-fence balancing (`:1293-1329`),
segment/commentary tracking, and reconciliation of what was actually delivered
(`delivered_final_matches`, `:443`). Transport is selected per adapter
(`StreamConsumerConfig.transport` — `auto` / `draft` / `edit` / `off`, `:142-149`) via the
adapter capability probes `supports_draft_streaming` (`base.py:2943`),
`prefers_fresh_final_streaming` (`base.py:2962`) and `streaming_overflow_limit` (`base.py:2985`).
Finalization can re-send fresh and delete stale previews (`fresh_final_after_seconds`, `:134-141`;
`delete_message`, `base.py:3581`).

**Adapter must implement:** `edit_message` at minimum (`base.py:3552`); everything else degrades.
**Phone value: High** — but note this is the one area where Talaria already has a decent story
(`/chat/stream` SSE). The gain is the *reconciliation and failure recovery*, not the streaming
itself.

### 2.5 Chunking, formatting, ephemeral replies — **Medium**

`truncate_message` (`base.py:6692-6720`) splits on code-block boundaries, reopens fences with the
original language tag, and adds `(1/3)` indicators; length is measured through
`message_len_fn` / `max_message_length_for_chat` (`base.py:2851-2881`) so UTF-16-counting
platforms are correct. `splits_long_messages` (`base.py:2698`) tells the delivery router to skip
gateway-level truncation (`delivery.py:503-523`). `format_message` (`base.py:6681`) is the
per-platform markdown hook. `EphemeralReply` (`base.py:2375-2412`) + `_schedule_ephemeral_delete`
(`base.py:3626`) auto-delete system notices after `display.ephemeral_system_ttl`, and silently
degrade to normal sends when the adapter has no `delete_message` (`base.py:5009`).

---

## 3. Interactive prompts

### 3.1 Dangerous-command approval — **High**

`run.py:5095-5185` registers a per-session approval callback that blocks the agent thread. It
prefers `send_exec_approval` (buttons) when the adapter *class* defines it, and otherwise falls
back to a plain-text prompt built with the adapter's `typed_command_prefix` (`base.py:2710`) so
users are told the form that actually works. Commands are credential-redacted before display
(`_redact_approval_command`, `run.py:5121`). Typing is paused for the wait
(`pause_typing_for_chat`, `base.py:4796`) and resumed on resolution. Shared prompt-assembly core
at `base.py:3660-3713` (`_EA_*` template attrs + `_format_exec_approval`).

**Adapter must implement:** nothing for the text path; `send_exec_approval` for buttons, with
callbacks routed to `tools.approval.resolve_gateway_approval` (`tools/approval.py:2338`).
**Phone value: High.** Today Talaria's Sessions-API turns have **no approval channel at all** —
approvals exist only on `/v1/runs` (`api_server.py:2024`, `6464-6544`). A dangerous command on
the chat plane has nowhere to ask.

### 3.2 `clarify` — **High**

`send_clarify` (`base.py:3780-3852`) ships a working default: a numbered text list, multi-select
aware, that calls `mark_awaiting_text(clarify_id)` so the gateway's text intercept resolves the
user's typed "2" or free-form answer. Buttons are a pure upgrade. The busy-guard has a dedicated
bypass so a clarify reply reaches the resolver instead of being queued as a new turn
(`base.py:5655-5709`).
**Phone value: High** — a native picker sheet is one of the most obviously phone-shaped wins here.

### 3.3 Slash-confirm and pickers — **Medium**

`send_slash_confirm` (`base.py:3745-3778`) is the Once / Always / Cancel primitive
(`slash_commands.py:2433`, `5085`). `_try_send_choice_picker` (`slash_commands.py:3298-3340`) and
`send_model_picker` (`slash_commands.py:1779`, `2076`) drive `/model`, `/reasoning`, `/fast`;
`_format_choice_page` (`base.py:3716-3743`) is the shared pagination core. All fall back to text
cards automatically.
**Phone value: Medium** — nicer than Talaria's current bespoke model picker, and it would put
model switching on the same plane as everything else.

---

## 4. Inbound pipeline

### 4.1 Normalized `MessageEvent` + media caching — **High**

`MessageEvent` (`base.py:2054-2158`) is the one inbound shape: text, `MessageType`
(`base.py:2032` — text/location/photo/video/audio/voice/document/sticker/command), `media_urls`
(local cached paths for tool access), `media_types`, full reply context
(`reply_to_message_id/text/author_id/author_name/reply_to_is_own_message`),
`prompt_response` for structured button replies, `auto_skill`, `channel_prompt`,
`channel_context`, `internal`, free-form `metadata`.

Caching helpers with size guards and content sniffing:
`validate_inbound_media_size` (`base.py:750`) / `get_inbound_media_max_bytes` (`729`),
`cache_image_from_bytes` (`825`) / `cache_image_from_url` (`854`, SSRF-guarded via
`_ssrf_redirect_guard` at `670`), `cache_audio_from_bytes` (`976`, with `_sniff_audio_ext` at
`964`), `cache_video_from_bytes` (`1093`), `cache_document_from_bytes` (`1880`), and the generic
`cache_media_bytes` (`1966`) returning a `CachedMedia` with an LLM-facing `context_note`
(`base.py:1933-1944`). TTL cleanup at `938`/`1059`/`1103`/`1130`/`1912`.

**Adapter must implement:** download bytes, call the right cache helper, set
`media_urls` + `media_types` + `message_type`.
**Phone value: High.** This is the on-ramp for camera roll, voice memos, Files-app documents,
share-sheet input — all of which currently have no route into a Sessions-API turn.

### 4.2 Voice-note transcription (STT) — **High**

`_enrich_message_with_transcription` (`run.py:21406-21553`): per-clip transcription via the
configured provider with an automatic **local STT fallback** (`run.py:21471-21482`), a dedicated
sentinel for silent/inaudible clips instead of empty quotes (`run.py:21489-21498`), and a neutral
failure marker that deliberately avoids poisoning history with setup advice
(`run.py:21506-21530`). When `stt_enabled` is off (`config.py:914`) the agent still gets the path
plus a probed duration (`run.py:21432-21449`). Successful transcripts are echoed back to the chat
as `🎙️ "…"` when configured (`run.py:15864-15884`). Dedup so one clip is never transcribed twice
(`_transcribe_pending_audio_event_once`, `run.py:21555`), and voice notes that arrive mid-turn
are transcribed *before* being used as steer/interrupt text
(`run.py:8880-8890`, `8956-8966`, `14884-14894`).

**Phone value: High.** Push-to-talk is the phone's native input mode; today Talaria has to do
STT itself or not at all.

### 4.3 Vision routing — **High**

`run.py:15810-15862`: `_decide_image_input_mode` picks **native** (attach pixels inline for
vision-capable models) vs **text** (run `vision_analyze` first and prepend the description).
The probe does blocking network I/O (models.dev lookup, Ollama `/api/show`) and is correctly
offloaded to a thread. Per-attachment MIME classification (`_event_media_is_image`) so a document
mixed into a photo message isn't mis-routed and 400'd by the provider.
Non-image attachments get path-pointing context notes that steer the model to process the file
itself rather than ask the user to describe it (`run.py:15893-15960`).

**Phone value: High** — and note it works correctly on *non*-vision models too, which the
current path does not attempt.

---

## 5. Session, concurrency, and the busy-turn story

### 5.1 Per-session guard, interrupt, queue, and **steer** — **High**

`handle_message` (`base.py:5554-5757`) is the whole concurrency story:

- A synchronous `_active_sessions` guard set *before* the background task spawns, closing the
  duplicate-task race (`base.py:5750-5757`, `_start_session_processing` at `5376`).
- Stale-lock self-heal when an owner task died (`_heal_stale_session_lock`, `base.py:5349`).
- Photo bursts / albums queue without interrupting (`base.py:5721-5724`,
  `merge_pending_message_event` at `2438`).
- Rapid text follow-ups debounce (`base.py:5726-5734`, `_queue_text_debounce` at `5203`,
  default 0.35 s window / 1.0 s hard cap at `base.py:2794-2799`).

Then `busy_input_mode` (`run.py:8223-8233`) picks the policy, and `run.py:8874-8960` executes it:

- **`steer`** — the follow-up text is injected *into the running turn* via `running_agent.steer()`,
  with voice notes transcribed first so a voice follow-up doesn't silently degrade to queueing.
- **`interrupt`** — `running_agent.redirect()` when the agent supports active-turn redirect,
  otherwise `running_agent.interrupt()`, aborting in-flight tool calls.
- **`queue`** — FIFO pending, preserving per-message turn boundaries.

Plus automatic demotion to `queue` while context compression is in flight (`run.py:8860-8871`).

**Adapter must implement:** nothing.
**Phone value: High.** "I typed one more thing while it was working" is *the* mobile interaction
pattern, and the Sessions API has no concept of it.

### 5.2 Busy-guard command bypass — **High**

`base.py:5593-5709`: registry-driven (`hermes_cli/commands.py` `busy_policy`), so
`/stop`, `/new`, `/reset` route through a cancel-handoff that serializes cancellation → runner
response → pending drain (`_dispatch_active_session_command`, `base.py:5477`), while
`/approve`, `/deny`, `/status`, `/background`, `/restart` dispatch inline without cancelling.
Without this, `/approve` **deadlocks** — the agent thread is blocked on `Event.wait` and the
approval is sitting in the pending queue.
**Phone value: High** — it is the precondition for §3.1 working at all.

### 5.3 The slash-command surface — **High**

92 `CommandDef` entries in `hermes_cli/commands.py`, dispatched by `gateway/slash_commands.py`
(266 KB). Notables for a phone:
`new`, `resume`, `sessions`, `history`, `save`, `retry`, `undo`, `compress`, `rollback`,
`snapshot`, `export`, `import`, `stop`, `approve`, `deny`, `background`, `queue`, `steer`,
`goal`, `status`, `context`, `model`, `reasoning`, `fast`, `voice`, `tools`, `toolsets`,
`skills`, `memory`, `cron`, `kanban`, `plugins`, `platforms`, `usage`, `restart`, `update`.
Gateway-only commands are flagged `gateway_only=True` (e.g. `hermes_cli/commands.py:105`, `110`,
`143`, `145`, `179`, `303`, `308`, `319`).
**Phone value: High.** Every one of these is currently unreachable from Talaria and would have to
be re-implemented as bespoke UI.

### 5.4 Session keying and threading — **Medium**

`build_session_key` (`gateway/session.py:1058-1130`) derives a deterministic key from
platform / chat / thread / user with configurable group- and thread-level isolation
(`base.py:5578-5582`). `create_handoff_thread` (`base.py:3525-3549`) lets a CLI session hand off
into a fresh thread on the phone (`run.py:11616-11730` — the handoff watcher rebinds the
`session_id` so the full transcript replays). `set_topic_recovery_fn` (`base.py:3311`) and
`turn_lease.py` (per-resolved-session-id serialization) cover the sharp edges.
**Phone value: Medium** — Talaria has its own session model; the win is threading + CLI handoff.

---

## 6. Reliability

### 6.1 Delivery-obligation ledger — **High**

`gateway/delivery_ledger.py` records a durable SQLite row per outbound final response *before*
the send is attempted, with four checkpoints — `record_obligation` (`:188`) →
`mark_attempting` (`:214`) → `mark_delivered` (`:218`) / `mark_failed` (`:222`). Called from the
adapter's delivery path at `base.py:6062-6110`. On the next boot, `sweep_recoverable` (`:236`)
claims rows whose owner process is dead and `run.py:10289-10360` redelivers them — with a visible
`RECOVERED_MARKER` (`:68`) on the ambiguous cases (`attempting` / `failed`) so the contract is
honest at-least-once rather than a silent duplicate. Bounded: `MAX_ATTEMPTS = 3`,
24 h stale cutoff, 7 d retention, 500-row cap (`:61-64`). Gate: `gateway.delivery_ledger`,
default on (`:339-353`).

**Phone value: High.** Today, a gateway crash between "turn finished" and "HTTP response written"
loses the answer with no trace — and the tokens are already spent.

### 6.2 Send retry, error classification, dead targets — **Medium**

`_send_with_retry` (`base.py:5042-5132`) with retryable-vs-timeout discrimination
(`base.py:4972-4990` — timeouts are deliberately *not* retried, the message may already be
delivered). `classify_send_error` (`base.py:2304`) and `is_chat_level_not_found` (`base.py:2355`)
produce a machine-readable `error_kind` on `SendResult`. `DeadTargetRegistry`
(`gateway/dead_targets.py:1-24`) short-circuits confirmed-dead chats and self-heals on the next
successful send (`delivery.py:341-391`).

### 6.3 Reconnect-aware final delivery — **Medium**

`_final_delivery_adapter` (`base.py:5014-5041`): when a reconnect replaces the adapter mid-turn,
the not-yet-sent final response is routed to the *replacement* transport, while message IDs and
edits/deletes stay with the old one. Reconnect backoff: 30 s → 5 min cap (`run.py:3606-3612`).

---

## 7. Identity, authorization, onboarding

### 7.1 Allowlists and delegated authorization — **Medium**

`_is_user_authorized` (`gateway/authz_mixin.py:386-560`) runs a documented five-step chain:
per-platform allow-all → env allowlist → pairing-approved list → global allow-all → **deny**.
Plugin platforms join it by declaring `allowed_users_env` / `allow_all_env` on their
`PlatformEntry` (`platform_registry.py:86-90`). Two escape hatches exist for adapters that own
their own gate: `enforces_own_access_policy` (`base.py:2884-2909` — the gateway mirrors a
config-driven `allowlist`, and explicitly refuses to trust `"open"`) and
`authorization_is_upstream` (`base.py:2912-2941` — authorization performed by a trusted
authenticated upstream, as the relay does).
**Phone value: Medium.** Talaria's Bearer-key model maps cleanly onto
`authorization_is_upstream = True`, or onto a real allowlist keyed by installation identity.

### 7.2 DM pairing-code onboarding — **Medium**

`gateway/pairing.py:1-19` — 8-char codes from a 32-char unambiguous alphabet, 1 h expiry,
max 3 pending per platform, 1 request per user per 10 min, lockout after 5 failed approvals,
`chmod 0600`, codes never logged. `run.py:14399-14450` offers a code in DMs to unknown senders
and tells them the exact `hermes pairing approve <platform> <code>` line; approval also writes
the user into the platform's own allowlist so the operator's list stays the single editable
source of truth (`pairing.py:60-89`, `175-203`).
**Phone value: Medium** — a genuinely nicer first-run than pasting a 64-char API key, and it is
free.

---

## 8. Observability and presentation control

### 8.1 Typing, live status text, tool progress — **High**

`_keep_typing` (`base.py:4677-4761`) refreshes the indicator every 2 s with a per-call ~1.5 s
timeout so a slow round-trip can't kill the bubble, honours a pause set during approval waits
(`_typing_paused`), and always tears down platform state in `finally`.
`supports_status_text` + `set_status_text` (`base.py:2650-2674`) let a text-rendering indicator
show live per-tool phrases ("is running pytest…") at **zero extra API calls** — the phrase is a
dict write picked up by the existing refresh (`run.py:3640-3657`, gated at `run.py:24258-24270`).
Phrases come from a configurable catalog that never interpolates raw tool args or reasoning text
(`gateway/status_phrases.py:1-27`).

Surfaces are independently configurable per platform (`gateway/display_config.py:1-21`):
`tool_progress` (`off`/`all`/`new`/`verbose`/`log` — `run.py:24255-24276`), `thinking_progress`
(`run.py:24291-24298`), `interim_assistant_messages` (`run.py:24280-24290`), `live_status`
(`run.py:24261-24270`), `runtime_footer`, `busy_input_mode`, `streaming`.

**Adapter must implement:** `send_typing`; set `supports_status_text = True` to opt into phrases.
**Phone value: High.** A live "what is it doing right now" line is a large perceived-latency win
on mobile and costs nothing.

### 8.2 Structured stream-event rendering — **Medium**

`gateway/stream_events.py:1-24` defines the typed agent→gateway vocabulary; `stream_dispatch.py`
routes each event through adapter hooks; `base.py:3029-3121` gives the adapter three overrides:
`render_message_event`, `format_tool_event` (returning `None` **eats** the event on platforms that
can't render tool chrome), and `format_tool_preview`. The contract is presentation-only —
whatever an adapter eats never changes persisted history (`base.py:3040-3042`).
**Phone value: Medium** — this is the seam for rendering tool calls as native SwiftUI cards
instead of emoji-prefixed text.

### 8.3 Hooks — **Medium**

`gateway/hooks.py:9-37` — `gateway:startup`, `session:start`, `session:end`, `session:reset`,
`agent:start`, `agent:step`, `agent:end`, `command:*` (wildcard), plus reaction events
(`run.py:7144-7153`). `emit_collect` (`hooks.py:200-227`) supports decision-style hooks that can
allow / deny / rewrite a command before dispatch (`run.py:14966`). Every emit site is on the
`GatewayRunner` path — **none of it fires for a Sessions-API turn today**.

### 8.4 Runtime status and fatal errors — **Medium**

`_mark_connected` / `_mark_disconnected` / `_set_fatal_error` (`base.py:3157-3175`) publish
platform state that `hermes gateway status` reads; retryable-vs-fatal drives the reconnect
watcher (a non-retryable fatal drops the platform from the retry queue instead of looping
forever — `api_server.py:7010-7025` is the cautionary tale, ~501 leaked connections over 2.5 days).
`_write_runtime_status_safe` (`base.py:3177-3207`) warns once per context then downgrades.

---

## 9. Things worth knowing that are *not* capabilities

- **`interactive_resume`** (`base.py:2727-2738`) — on startup auto-resume, an interactive platform
  is told to "report the restore and ask what the user wants next"; a non-interactive one is told
  to "finish the interrupted work." `api_server.py:1367` sets it `False`. A Talaria adapter should
  leave it `True`.
- **`supports_code_blocks`** (`base.py:2640-2648`) and **`typed_command_prefix`**
  (`base.py:2700-2710`) are pure capability declarations that shared prompt/render code reads
  generically — no call-site branching.
- **`platform_hint`** (`platform_registry.py:108-111`, consumed at `agent/system_prompt.py:437-444`)
  is how a plugin platform tells the model what it can render. The current `api_server` hint
  (`agent/prompt_builder.py:929-941`) actively instructs the model: *"assume plain text. No
  markdown formatting (no asterisks, bullets, headers, code fences)"* and warns that non-image
  `MEDIA:` tags will leak raw host paths. **A Talaria adapter with its own hint flips that
  instruction on day one** — full markdown, real attachments — which is arguably the cheapest
  single win in this document.

---

## 10. Bottom line

Roughly **18 High-value capabilities** are unavailable to Talaria today, and they cluster into
four themes:

1. **Push** — the app can be reached between turns (async delivery, cron, kanban, shutdown pings).
2. **Voice and media, both directions** — STT in, TTS out, real attachments in and out.
3. **Interactive control mid-turn** — approvals, clarify, steer/interrupt/queue, slash commands.
4. **Durability** — the delivery ledger, retry/classification, reconnect-aware delivery.

The implementation cost is concentrated in a small number of methods: `connect`, `disconnect`,
`send`, `send_typing`, `send_image`, `get_chat_info` are the only abstract requirements
(`base.py:3470`, `3490`, `3495`, `6670`). Everything else in this document either works by
default or is an opt-in override with a graceful text fallback already written.
