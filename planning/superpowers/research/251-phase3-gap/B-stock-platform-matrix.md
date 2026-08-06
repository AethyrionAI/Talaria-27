# Stock Platform Adapter Comparison Matrix

Research pass over the Hermes agent codebase (read-only clone) to determine which gateway
capabilities each stock messaging-platform adapter actually exercises, so Talaria's pivot
from a plain Sessions-API HTTP client to a first-class gateway platform adapter has a
grounded "what does mature look like" reference.

All adapters are subclasses of `BasePlatformAdapter` (`gateway/platforms/base.py`, 6861
lines). Line numbers below refer to the read-only clone at
`/private/tmp/claude-501/-Users-owenjones-Documents-Claude-Talaria-27/22e57a75-8a46-4c55-bea2-395a07d0e604/scratchpad/hermes-agent-ro`
— re-resolve against a live checkout before citing externally, since these are
snapshot-relative.

Platforms covered in depth (the set the task named, all of which exist in this repo):
**Telegram, Discord, Slack, Google Chat, WhatsApp (two adapters: Cloud API + Baileys
bridge), BlueBubbles/iMessage, IRC**. **CLI/terminal and web do not exist as
`BasePlatformAdapter` subclasses** — see the dedicated section near the end; that finding
is itself important for Talaria's decision.

---

## 1. Legend — what each capability means at the base-class level

Understanding the shared machinery matters as much as the per-adapter overrides, because
several "capabilities" are actually **base-class or gateway-level features that any
adapter gets for free** once it satisfies a narrow contract — they are not things each
platform reinvents.

- **Text send + chunking**: every adapter overrides `send()`; chunking usually calls the
  shared `self.truncate_message(...)` helper. Markdown-safe/fence-aware splitting lives in
  `gateway/platforms/helpers.py` (`split_markdown_atoms`, `_chunk_markdown_paragraphs`,
  `balance_fences_across_chunks`, etc. — `helpers.py:544-949`), not per-adapter.
- **Streaming edits**: `supports_draft_streaming()` / `send_draft()`
  (`base.py:2943-3020`) are the *native animated draft* path — default `False` /
  `NotImplementedError`. Falling back to `send()` + repeated `edit_message()` is the
  generic "progressive update" path; an adapter that doesn't override `edit_message()`
  gets base's stub, which always returns `SendResult(success=False, error="Not
  supported")` (`base.py:3552-3579`). A related **gotcha**: `SUPPORTS_MESSAGE_EDITING` is
  read via `getattr(adapter, "SUPPORTS_MESSAGE_EDITING", True)`
  (`gateway/run.py:23635`) — an adapter that neither implements `edit_message()` **nor**
  explicitly sets `SUPPORTS_MESSAGE_EDITING = False` silently tells the gateway it CAN
  stream-edit when it can't (see WhatsApp Cloud below — a real, present bug).
- **Media send**: `send_image/_video/_voice/_document/_animation` all have base defaults
  that degrade gracefully — `send_image` posts the URL as plain text (`base.py:3972-3989`),
  `send_animation` falls through to `send_image` (`base.py:3991-4005`), and
  `send_voice/_video/_document` post a "couldn't deliver the attachment" apology via
  `self.send()` rather than ever leaking a host filesystem path (`base.py:4062-4089`,
  `4205-4264`).
- **Media receive**: three module-level helpers in `base.py` —
  `cache_image_from_bytes` (`:825`), `cache_audio_from_bytes` (`:976`),
  `cache_document_from_bytes` (`:1880`) — are the documented convention
  (`ADDING_A_PLATFORM.md:139`). Adapters are free to build their own caching (several do),
  but only one adapter in this survey (BlueBubbles) uses all three exactly as documented.
- **Voice notes + transcription is a base/gateway-level capability, not per-adapter.**
  An adapter's only job is to (a) tag inbound audio `MessageType.VOICE` and cache the
  bytes/URL. Actual speech-to-text is centralized in `gateway/run.py`
  (`_transcribe_pending_audio_event_once`, `:21555`; `_transcribe_and_echo_pending_voice`,
  `:21626`) and fires for **any** adapter's `MessageType.VOICE` event.
- **TTS / audio replies is likewise mostly base/gateway-level.** `base.py`'s
  `_process_message_background` has a built-in **auto-TTS** block
  (`base.py:5952-5992`): if the triggering message was `MessageType.VOICE` and the chat
  opted in (`/voice on|tts` or global `voice.auto_tts`), it synthesizes speech via
  `tools.tts_tool.text_to_speech_tool` and delivers it through **whatever `send_voice`
  the adapter already implements** — no adapter-specific TTS code required. `play_tts()`
  defaults to calling `send_voice()` (`base.py:4108-4120`). Only **Discord** overrides
  `play_tts()` for something genuinely different (live voice-channel injection). No
  adapter in this survey implements **streaming** TTS
  (`begin_streaming_tts`/`write_streaming_tts` — grep across every adapter file returned
  zero overrides; only base.py defines the no-op defaults, `base.py:4137-4166`).
- **Reactions**: two independent mechanisms exist. (1) An **opt-in shortcut** —
  set class attrs `_OK_EMOJI`/`_FAIL_EMOJI`/`_ACK_EMOJI` plus `_add_reaction`/
  `_remove_reaction` primitives shaped `(chat_id, message_id[, emoji])`, and base's
  `on_processing_complete` (`base.py:4913-4956`) auto-swaps an in-progress reaction for a
  final one. Only **Photon** (`plugins/platforms/photon/adapter.py:2327-2328`) actually
  uses this shortcut. (2) **Full manual override** of `on_processing_start`/
  `on_processing_complete` — what Telegram, Discord, and Slack all do instead, each with
  bespoke logic (replace-all vs additive reaction semantics differ by platform). (3)
  **Inbound** reactions: `set_reaction_handler` (`base.py:3349-3366`) — its own docstring
  names Slack as the sole caller, confirmed.
- **Buttons/interactive elements**: base defines real fallback logic for
  `send_clarify()` (`base.py:3780-3852` — numbered plain-text list +
  `mark_awaiting_text()` so the next reply is captured) and `send_slash_confirm()`
  (`base.py:3745-3778` — returns unsupported, gateway's generic text-confirm path takes
  over). **`send_exec_approval`, `send_model_picker`, and `send_choice_picker` have NO
  base implementation at all** — they're pure per-adapter opt-ins, called via `getattr(...,
  None)` from gateway code, absent entirely on platforms that don't define them (confirmed:
  `send_exec_approval` exists only in `qqbot`, `whatsapp_cloud`, `feishu`, `matrix`,
  `teams`, `discord`, `telegram`, `slack` — not in IRC, Google Chat, WhatsApp Baileys, or
  BlueBubbles). The shared button-callback id convention is `cl:<id>:<idx>` (clarify),
  `appr:<id>:<choice>` (approval), `sc:<choice>:<id>` (slash confirm) —
  `ADDING_A_PLATFORM.md:125`.
- **Threading/replies**: `create_handoff_thread()` (`base.py:3525-3549`) defaults to
  `None` ("platform doesn't support threading"); its own docstring names exactly
  **Telegram, Discord, Slack** as overriders, confirmed by grep — no other adapter in this
  survey implements it. Quoted/anchored replies (`reply_to` parameter on `send()`) are a
  separate, more widely supported concept.
- **Pairing / allowed-users auth**: the default path is fully gateway-owned — env vars
  (`<PLATFORM>_ALLOWED_USERS` / `<PLATFORM>_ALLOW_ALL_USERS`) registered per-adapter in
  `register()` and checked by the base's `_is_sender_authorized`
  (`base.py:3382-3406`). `enforces_own_access_policy` (`base.py:2884-2911`) and
  `authorization_is_upstream` (`base.py:2912-2942`) are the two override points for an
  adapter that wants to own gating itself instead — WhatsApp's shared
  `WhatsAppBehaviorMixin` is the only place in this survey that sets
  `enforces_own_access_policy = True`.
- **Webhook-mode HTTP events vs socket/polling**: the gateway exposes ONE shared generic
  ingress route, `POST /api/platforms/{platform}/events`
  (`gateway/platforms/api_server.py:2009-2011`), which dispatches to an adapter's
  `verify_http_event_request()` + `dispatch_http_event()` if both exist
  (`api_server.py:1826-1846`). **Only Google Chat implements this pair** — confirmed
  by repo-wide grep, zero other hits in `gateway/` or `plugins/`. Every other
  "webhook-shaped" adapter (WhatsApp Cloud, BlueBubbles) runs its **own embedded aiohttp
  HTTP server** inside `connect()` rather than plugging into the shared route — a real
  architectural fork worth knowing about, not just a naming difference.

---

## 2. Capability × Platform matrix

`✓` = genuinely implemented (not just inherited base fallback) · `partial` = implemented
with a real gap or platform-imposed limitation · `—` = absent, falls to base default/no-op
· `fallback` = works only because base's generic degrade-gracefully default fires (e.g.
send_voice services auto-TTS with no adapter-specific TTS code)

| Capability | Telegram | Discord | Slack | Google Chat | WhatsApp Cloud | WhatsApp Baileys | BlueBubbles/iMessage | IRC |
|---|---|---|---|---|---|---|---|---|
| Text send + chunking | ✓ (UTF‑16‑aware, 4096) | ✓ (2000) | ✓ (39000) | ✓ (4000, newline-boundary) | ✓ (4096) | ✓ (chunked + 0.3s pacing) | ✓ (4000, paragraph-first) | ✓ (byte-accurate 510B split; `MAX_MESSAGE_LENGTH` class-attr bug) |
| Streaming edits (progressive update) | ✓ native draft (`sendMessageDraft`, DMs) + edit-fallback (groups) | partial (edit-only, no native draft) | partial (edit via `chat.update`) | partial (edit_message explicitly required/gated by gateway stream consumer) | — (`edit_message` not overridden; `SUPPORTS_MESSAGE_EDITING` defaults **True** — latent bug) | partial (edit genuinely works via bridge `/edit`) | — (explicitly `SUPPORTS_MESSAGE_EDITING = False`, self-reported correctly) | — |
| Media send (image/audio/video/doc) | ✓ all + native albums | ✓ all | ✓ all (no animation override) | ✓ all, but OAuth-gated (see below); image send is URL-only, no upload | ✓ image/video/audio/doc; — animation | ✓ image/video/audio/doc + unique poll/location; — animation | ✓ all incl. explicit animation override | — (image → bare URL text; audio/video/doc → apology text) |
| Media receive | ✓ comprehensive (photo/voice/audio/video/doc/sticker) | ✓ (image/audio/doc; video has no dedicated cache, routed through doc path) | ✓ (image/audio/video/doc + SSRF guards) | ✓ (image/audio/video/doc; Drive-only attachments skipped) | ✓ but bespoke custom cache path, not base helpers | ✓ via `cache_*_from_url` + path-traversal allowlist | ✓ — only adapter using base's documented `cache_*_from_bytes` trio verbatim | — (text-only protocol) |
| Voice notes + transcription | ✓ tag+cache → shared STT pipeline | ✓ tag+cache **+ unique live VC STT** wired directly in-adapter | ✓ tag+cache, incl. voice-clip MIME-mislabel fix | ✓ tag+cache (generic only) | ✓ tag+cache | ✓ tag+cache ("ptt" type) | ✓ tag+cache (`.caf` UTI detection) | — |
| TTS / audio replies | fallback (via `send_voice`) | ✓ custom `play_tts` — live VC injection w/ ducking `VoiceMixer`, or falls back to `send_voice` | fallback | fallback | fallback (ffmpeg→Opus conversion for native bubble) | fallback | fallback (renders as native iMessage voice memo) | — (no `send_voice` at all) |
| Typing indicators / status text | ✓ typing; no status text | ✓ typing (persistent-loop workaround); no status text | ✓ typing **+ live status text** (`assistant_threads_setStatus`, elapsed-time heartbeat) — richest | ✓ typing via placeholder-message trick (no ephemeral typing UI); no status text | ✓ typing (coupled with read-receipt); no status text | ✓ typing; no status text | ✓ typing + explicit `stop_typing` (gated on optional Private API/helper) | partial (`send_typing` overridden but literal no-op stub) |
| Reactions | ✓ outbound only, custom hooks, replace-all model, gated `TELEGRAM_REACTIONS` (default **false**) | ✓✓ outbound, matches base's documented `_add/_remove_reaction` shape, additive model, durable SQLite bookkeeping, gated `DISCORD_REACTIONS` (default **true**) | ✓✓ outbound **+ inbound** (`reaction_added/removed` → `set_reaction_handler`, can drive agent turns) | — | — (despite platform support) | — (despite Baileys library support) | — (docstring + tapback code table exist; section header present; **zero implementation**; inbound tapbacks actively dropped) | — |
| Message editing/deletion | ✓ both (48h delete window, overflow-aware edit split) | partial (edit ✓; delete — not overridden) | ✓ both | ✓ both (delete used sparingly — tombstone) | — neither | partial (edit ✓ via bridge; delete —) | — neither (explicit flag) | — neither |
| Buttons/interactive (clarify/approval/confirm/model-picker/choice-picker) | ✓ all 5 | ✓ all 5 | ✓ 3/5 (approval, confirm, clarify) — no picker/choice-picker | partial — clarify only (card-based), + generic `send_card` | ✓ 3/5 (approval, confirm, clarify: button↔list by choice count) | partial — clarify only, rendered as **native poll** | — (no native button primitive; all 5 degrade to text) | — |
| Threading/replies | ✓ `create_handoff_thread` (forum topics / DM topics) + reply-anchor modes | ✓✓ `create_handoff_thread` (native threads) + auto-threading + forum-channel support | ✓ `create_handoff_thread` (thread_ts anchor) + flat-reply escape hatch | partial — no handoff-thread override; in-conversation threading via `_resolve_thread_id`/last-thread cache | partial — no threading; quoted-reply via bespoke `rich_sent_store` index | partial — no threading; quoted-reply resolved natively by the bridge | partial — no threading; quoted-reply via Private API (`selectedMessageGuid`) | — |
| Pairing / allowed-users auth | gateway env allowlist + local intake prefilter + participates in shared pairing handshake | gateway env allowlist + **richer local layer**: role-based, guild-scoped, channel-scoped bypass, pairing-approved-user integration | gateway env allowlist only, no adapter-local layer | gateway env allowlist for messages **+ separate per-user OAuth consent tier** for file uploads | adapter **owns** gating (`enforces_own_access_policy=True` via mixin): dm/group policy + allow_from before gateway sees message | same mixin (owns gating) **+ genuine QR/`creds.json` pairing gate** at `connect()` | gateway env allowlist only; transport itself uses a shared server password (not per-user) | gateway env allowlist + local config.yaml prefilter; nicks explicitly documented as unauthenticated |
| Webhook HTTP events vs socket/polling | socket/polling — long-polling (default) OR PTB's own self-managed webhook server (not the shared hook) | socket — persistent WebSocket gateway connection | socket — Socket Mode (persistent WS) | **✓ true webhook via the shared hook** (`verify_http_event_request`+`dispatch_http_event`) **+ alternative Pub/Sub pull**, dual-mode by config | webhook-shaped but **self-hosted** embedded aiohttp server (own HMAC verify), not the shared hook | neither — local HTTP **polling** loop (~1s) against a subprocess bridge | webhook-shaped but **self-hosted** embedded aiohttp server that self-registers/unregisters with the external Mac server | socket — raw TCP (optional TLS) |

---

## 3. Per-platform notes (condensed; see agent transcripts above for full file:line detail)

### Telegram — `plugins/platforms/telegram/adapter.py` (10,147 lines)
The only adapter with **native animated streaming drafts**: `supports_draft_streaming()`
(`:5242`) gates on DM/private chats + PTB exposing `send_message_draft` (Bot API 9.5+),
`send_draft()` (`:5261`) reuses a `draft_id` so Telegram client-side animates the preview;
groups fall back to edit-based streaming. Also overrides `prefers_fresh_final_streaming()`
(`:1708`) and `streaming_overflow_limit()` (`:1723`) to route the *finalized* answer
through the larger 32,768-char `sendRichMessage` API (Bot API 10.1) rather than the 4096
MarkdownV2 edit limit. Full interactive-button surface (5/5 hooks, `:5442-5722`). Threading
via forum topics + Bot-API-9.4 DM topics (`:3298-3392`). Reactions bypass the base
opt-in shortcut entirely — custom `on_processing_start/complete` (`:9843,9852`) using
Bot API's *replace-all* `set_message_reaction`. Ships a direct-IP DNS-over-HTTPS fallback
transport (`telegram_network.py`) for networks where the local resolver misroutes
`api.telegram.org`.

### Discord — `plugins/platforms/discord/adapter.py` (10,138 lines)
No native draft streaming, but the **deepest non-text feature set** of any adapter here:
live voice-channel STT wired directly into the adapter (`VoiceReceiver` PCM capture →
`transcribe_audio()`, `:4521-4532` — bypasses the cache-and-defer pattern entirely), a
custom `play_tts()` (`:3749`) that injects TTS directly into an active voice channel with
a ducking `VoiceMixer` (`voice_mixer.py`) rather than only sending a file, native Discord
threads + auto-threading + forum-channel posting (`:6809,6927,7477`), role-based +
guild-scoped + channel-scoped authorization (`:4590-4685`, richer than every other
adapter's flat allowlist), and a durable **SQLite-backed missed-message recovery**
subsystem (`recovery.py`, `_run_missed_message_backfill`, `:2184`) that re-dispatches
messages missed while disconnected.

### Slack — `plugins/platforms/slack/adapter.py` (9,088 lines) + `block_kit.py`
Best-in-class **typing/status UX**: `send_typing()` (`:2849-2944`) posts live per-tool
status text via `assistant_threads_setStatus`, including an elapsed-time heartbeat
("still working… (2m03s)"). The only adapter with **bidirectional reactions** — outbound
`_add/_remove_reaction` (`:3711-3740`) matching base's documented primitive shape, and
genuine **inbound** `reaction_added`/`reaction_removed` handling wired through
`set_reaction_handler` (`:4820-4839`), which can synthesize a message-pipeline event so a
reaction can drive an agent turn. Rich Block Kit approval/confirm/clarify UI
(`:6348-6638`) but **no** model-picker/choice-picker hooks. Socket Mode (persistent WS)
connection, not webhook.

### Google Chat — `plugins/platforms/google_chat/adapter.py` (3,738 lines) + `oauth.py`
The **only adapter using the shared webhook-event hook pair**
(`verify_http_event_request`/`dispatch_http_event`, `:1495-1549`), and the only one with a
genuinely **dual inbound transport** selectable by config: authenticated HTTP callback OR
Cloud Pub/Sub pull subscription, both converging on the same `_dispatch_message`
(`:985-1150`). `edit_message()`'s own docstring (`:2264-2269`) states plainly that the
gateway's stream consumer *gates* tool-progress/token-streaming on this method being
overridden — without it, Google Chat shows no live activity at all. Uses an
**anti-tombstone "patch the placeholder"** pattern: `send_typing()` posts a real "Hermes is
thinking…" message (Chat has no ephemeral typing UI) which `send()`/`edit_message()` later
patches into the real reply rather than delete-then-recreate (avoids a visible "message
deleted" tombstone). File uploads require a **separate per-user OAuth consent flow**
(`/setup-files`, `oauth.py`) because Chat's `media.upload` rejects service-account auth —
the only adapter in this survey with a capability tier gated behind individual end-user
consent distinct from base chat access.

### WhatsApp Cloud — `gateway/platforms/whatsapp_cloud.py` (2,111 lines) + `gateway/platforms/whatsapp_common.py` (mixin, 552 lines)
Strongest **native interactive-button trio** of any adapter (`send_exec_approval:845-901`,
`send_clarify:757-843` auto-switches button↔list layout by choice count,
`send_slash_confirm:903-949`), using the shared `cl:`/`appr:`/`sc:` id convention exactly
as documented. Runs its **own embedded aiohttp webhook server**, not the shared
`verify_http_event_request`/`dispatch_http_event` hook. Two real gaps: (1) no edit/delete
support, but the adapter never sets `SUPPORTS_MESSAGE_EDITING = False`, so the gateway
believes it CAN stream-edit and can produce a duplicate-message failure mode the gateway's
own code comments describe (`gateway/run.py:23628-23639`); (2) the module docstring
advertises a "24-hour window + template fallback" but **no template-message code exists
anywhere in the file** — a rejected out-of-window send just surfaces a generic Graph
error. Group chats are explicitly detected and rejected ("use the Baileys adapter for group
chats").

### WhatsApp Baileys — `plugins/platforms/whatsapp/adapter.py` (1,918 lines, shares the same mixin)
Architecturally distinct: spawns a **local Node.js subprocess** (Baileys library) and talks
to it over loopback HTTP (`/send`, `/edit`, `/send-media`, `/send-poll`,
`/send-location`, `/typing`, `/messages`) — the actual WhatsApp socket lives entirely in
the Node process. Inbound is a **~1s HTTP polling loop** against that bridge
(`_poll_messages:1316-1355`), with a text-batch debounce (`_SPLIT_THRESHOLD`, `:1383`) to
coalesce WhatsApp's rapid-fire message bursts into one agent turn. Unlike Cloud,
`edit_message()` genuinely works (POST `/edit`) — proving live-edit streaming is
achievable even through a subprocess-bridge shape. Renders `send_clarify` as a **native
WhatsApp poll** rather than buttons. Real **QR/credential pairing**: `connect()` hard-gates
on a `creds.json` file existing before even launching the bridge (`:541-554`); the bridge
freshness check compares a running bridge's reported script hash to what's on disk before
deciding to reuse vs. restart it (`:617-663`) — a robustness pattern for any persistent
local companion process.

### BlueBubbles/iMessage — `gateway/platforms/bluebubbles.py` (1,071 lines)
Architecturally the **closest existing analog to what Talaria is becoming**: a client-side
bridge to a real Apple messaging substrate (a Mac app running BlueBubbles Server) reached
over a password-authenticated LAN/tunnel REST+webhook API. Does **connect-time capability
discovery** — `GET /api/v1/server/info` (`:277-286`) checks whether the optional macOS
"Private API"/helper is installed, and every richer feature (typing indicators,
`stop_typing`, quoted replies) checks that flag and silently no-ops rather than failing
loudly when absent. **Self-registers and self-unregisters** its webhook URL with the
external BlueBubbles server on connect/disconnect (`_register_webhook`/
`_unregister_webhook`, `:378-458`), with idempotent dedup so a crash-restart doesn't
double-register. The only adapter using the base's documented
`cache_image/audio/document_from_bytes` trio verbatim. Correctly self-reports
`SUPPORTS_MESSAGE_EDITING = False`. One notable gap: the module docstring and a full
tapback-reaction code table (love/like/dislike/laugh/emphasize/question,
`:108-115`) exist, and there's an empty `# Tapback reactions` section header (`:768-770`)
— but **no implementation follows it**, and inbound tapbacks are actively filtered out and
dropped (`:942-948`) rather than surfaced. A stubbed, not partial, capability.

### IRC — `plugins/platforms/irc/adapter.py` (995 lines)
The **minimal reference adapter** — named explicitly as a "complete working example" in
`ADDING_A_PLATFORM.md:71`. Proves how much of the "rich" feature surface is free: override
`__init__`, `connect`, `disconnect`, `send`, `send_typing` (as a stub), `get_chat_info`,
and everything else (media, editing, drafts, buttons, threading, reactions, TTS,
reconnection scheduling) degrades gracefully via base defaults. The one area IRC
over-invests in is exactly its one hard protocol constraint: byte-accurate UTF-8-boundary
line splitting under the real 512-byte IRC limit (`_split_message:318-360`), duplicated
almost verbatim in a second `_standalone_send()` codepath used for out-of-process cron
delivery. Because IRC nicks are unauthenticated, the adapter layers a local
config-driven `allowed_users` filter on top of the standard gateway allowlist rather than
claiming `enforces_own_access_policy=True` — it never asserts a guarantee the protocol
can't back up. One real, findable gap even in the reference adapter: it sets a lowercase
instance attribute `self.max_message_length` instead of the uppercase class attribute
`MAX_MESSAGE_LENGTH` that generic gateway code reads via `getattr(adapter,
"MAX_MESSAGE_LENGTH", 4096)` — so upstream truncation logic silently uses the wrong
(too generous) 4096 budget for IRC instead of its real ~450/510-byte limit.

---

## 4. The API_SERVER "adapter" — what Talaria talks to today

`gateway/platforms/api_server.py` (7,188 lines) is itself registered as a
`BasePlatformAdapter` subclass, `Platform.API_SERVER` (`:1345,1369`) — this is the exact
surface Talaria's current Sessions API integration (`POST /api/sessions`,
`/api/sessions/{id}/chat`, `/chat/stream`) talks to. Its own class-level comment
(`:1350-1361`) is the clearest statement of the gap Talaria is trying to close:

> "Stateless request/response: every route... tears down its channel when the turn ends.
> There is no persistent outbound channel to push a background completion to a client that
> already received its response... async-delivery tools... must NOT promise delivery on
> this path."

Concretely: `supports_async_delivery: bool = False` (`:1361`), `interactive_resume: bool =
False` (`:1367`), and `send()` is a literal no-op stub —
`return SendResult(success=False, error="API server uses HTTP request/response, not
send()")` (`:7169-7178`). Compare this to every messaging adapter above, all of which have
a live, persistent outbound channel (socket, webhook push, or polling loop) that lets the
gateway push a message to the user at any time — a background job finishing, a cron
delivery, a tool-approval prompt — with no open HTTP request waiting. **This is the single
biggest structural gap** between "plain API client" and "first-class platform adapter":
push delivery vs. request/response.

---

## 5. CLI/terminal and Web — do not exist as platform adapters (important finding)

Neither of these is a `BasePlatformAdapter` subclass. This matters directly for Talaria's
architecture question.

- **`Platform.LOCAL = "local"`** (`gateway/config.py:280`) is the session-source marker
  used for local `hermes chat` terminal sessions. There is **no `LocalAdapter` class
  anywhere in the repo** — grep across `gateway/platforms/` and `plugins/platforms/`
  found none. `gateway/run.py:3070` maps it to the display label `"cli"`
  (`"cli" if platform == Platform.LOCAL else platform.value`). It never `connect()`s,
  never has a live outbound channel — it's a label, not an adapter.
- **There is no `Platform.WEB` enum value at all.** The `web/` directory
  (`web/README.md:1-3`) is a Vite+React **configuration/monitoring dashboard** — API keys,
  session status, config editing — served by `hermes_cli/web_server.py` on port **9119**
  (the same dashboard app CLAUDE.md's "two web apps" note already distinguishes from
  `:8642`). It is not a chat client and has no messaging adapter behind it.
- **The actual rich real-time client protocol in this codebase is `tui_gateway`'s
  JSON-RPC over WebSocket/stdio** (`tui_gateway/ws.py`, `tui_gateway/server.py` —
  14,006 lines). Its own docstring is directly on-point:

  > "Reuses `tui_gateway.server.dispatch` verbatim so every RPC method, every slash
  > command, every approval/clarify/sudo flow, and every agent event flows through the
  > same handlers **whether the client is Ink over stdio or an iOS / web client over
  > WebSocket**." (`tui_gateway/ws.py:3-6`, emphasis added — "iOS" is explicitly named)

  This is used today by the Ink terminal UI (stdio, `tui_gateway/entry.py`) and by
  **Hermes Desktop**, the Electron native chat app: "Hermes Agent runs as a headless
  `hermes serve` process and exposes the `tui_gateway` JSON-RPC/WebSocket API. The
  renderer connects through `apps/shared`" (`apps/desktop/README.md:100-103`). It carries
  far more than the Sessions API: session management, reactions (`message.react` RPC,
  `tui_gateway/methods_session.py:1021`), approvals, clarify, slash commands, tool
  streaming, project trees, pet/gamification state, and more (`tui_gateway/methods_*.py`,
  ~7,000 combined lines of RPC handlers). **It is architecturally the opposite direction
  from a platform adapter** (a client connecting *into* the gateway, not the gateway
  connecting *out* to a platform), so it isn't part of the capability matrix above — but
  it is the closest thing in this codebase to "what a rich native Talaria integration
  would consume," and the codebase's own comments already name iOS as an anticipated
  consumer of it. Worth flagging as a second, structurally different option from "become a
  `BasePlatformAdapter`."

---

## 6. Best reference for X

- **Overall most mature adapter to copy from**: **Discord** — the deepest non-fallback
  feature coverage (live voice, custom TTS injection, native threads + auto-threading,
  tiered role/guild/channel auth, and a durable SQLite-backed reconnect/recovery
  subsystem that is directly relevant to a phone client's background/foreground and
  connectivity-loss lifecycle). Telegram is the strongest runner-up, especially for
  streaming UX specifically.
- **Streaming edits / progressive updates**: **Telegram** — the only adapter with a true
  native animated-draft API (`send_draft` + reused `draft_id`); **WhatsApp Baileys** is the
  best evidence that live in-place editing works even through a subprocess-bridge
  architecture, which is closer to what a phone client's own transport might look like.
- **Media receive plumbing**: **BlueBubbles** — the only adapter using the base class's
  documented `cache_image/audio/document_from_bytes` helpers exactly as written; simplest
  to imitate.
- **Buttons / interactive elements**: **Telegram and Discord** (tie, both 5/5 hooks) —
  Discord's `discord.ui.View` components with built-in auth-gating and timeout-editing
  are the more directly relevant "native tappable UI" pattern for a phone client.
- **Typing / live status text**: **Slack** — `assistant_threads_setStatus` with a live
  elapsed-time heartbeat is the richest "what is the agent doing right now" signal in the
  survey.
- **Reactions (bidirectional)**: **Slack** — the only adapter with genuine inbound
  reaction handling that can drive an agent turn, not just outbound ack reactions.
  **Discord** is the best outbound-only reference (durable, additive, SQLite-backed).
- **Webhook-mode HTTP events**: **Google Chat** — the only adapter actually using the
  gateway's shared `verify_http_event_request`/`dispatch_http_event` hook pair, plus a
  clean dual-transport (webhook OR Pub/Sub) design that decouples "how events arrive" from
  "how they're processed."
  Note that WhatsApp Cloud and BlueBubbles are webhook-*shaped* but each runs its own
  embedded HTTP server rather than using this shared mechanism.
- **Capability-aware connection / graceful degradation**: **BlueBubbles** — probes
  server capabilities at connect time (`GET /api/v1/server/info`) and gates each richer
  feature on what the backend actually supports at runtime, rather than hardcoding
  capability flags at build time. The closest architectural cousin to a Talaria-to-Hermes
  bridge that must handle varying backend versions/configs.
- **Device/credential pairing**: **WhatsApp Baileys** — genuine QR/`creds.json`-based
  pairing gate at `connect()`, plus bridge-freshness verification on reuse — the closest
  precedent for a phone-style pairing flow. **Google Chat**'s separate per-user OAuth tier
  (distinct from base chat auth) is the best precedent for a capability gated behind
  individual user consent.
- **Client-side rich-protocol inspiration (not a platform adapter)**: **`tui_gateway`
  JSON-RPC/WebSocket** — already used by the Electron desktop client and explicitly
  documented as anticipating an iOS consumer; carries far more surface (reactions,
  approvals, clarify, slash commands, live tool streaming) than the Sessions API Talaria
  uses today.
