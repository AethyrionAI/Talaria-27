# E — The Talaria Feature Menu

**Date:** 2026-08-05
**Purpose:** the definitive candidate list for what Talaria can become as it pivots from a plain
Sessions-API HTTP client to a first-class Hermes plugin (platform adapter + tools + CLI + a
"desktop face" analogue). Owner's direction: *"bring as many features as possible into the app,
and maybe even a few others, like preview panes for artifacts — but definitely not limited to."*

**Evidence discipline.** Every row cites either a local report (`A§`/`B§`/`C§`/`D§` = the four
companion documents in this directory, all `file:line`-verified against a read-only Hermes clone at
HEAD `01a1037d1`) or an official doc path. Doc paths are relative to `website/docs/` in the Hermes
repo and map 1:1 onto `https://hermes-agent.nousresearch.com/docs/<path-without-extension>`.
Anything I could not confirm is quarantined in **§1.16 Unverified leads** and marked as such.
Nothing in the menu is invented.

**New this pass** (not present in reports A–D, found in the docs/code sweep):
- **Outbound webhooks** — a real, config-only push-out channel that fires on the *Sessions-API lane*
  (§1.2, row P1). Report C §19 correctly says Hermes has no APNs/FCM notion; it missed that
  `hooks.outbound` gives a generic signed HTTP push that a relay can convert into one.
- **Per-turn `model` / `provider` / `model_options` on the chat routes** — a working answer to
  OPEN_ITEMS #9's hanging session pin, available today (row G1).
- **`subagent.start` / `subagent.complete` on `/v1/runs/{id}/events`** — delegation observability on
  the API plane (row J2).
- **Upstream desktop shipped "artifacts with sandboxed live preview" in v0.20.0** — the owner's
  headline idea is a real upstream feature and therefore a parity target, not a wishlist item.
- **`wake_word.capture: client`** — upstream explicitly supports a *client* streaming mic frames for
  wake-word detection (row V4).
- **A full kanban REST + WebSocket board API** at `/api/plugins/kanban/*` (row J3).
- **RFC 8252 native sign-in (system browser + PKCE + refresh token in the OS keychain)** for the
  `:9119` plane — materially cheaper than report D's cookie-and-30-second-ticket recipe (§3, item 5).
- **Hermes Desktop is itself a `tui_gateway` client** running its own `hermes serve` — so "desktop
  parity" and "adopt M3" are very nearly the same sentence (§0).

---

## 0. Delivery planes (the column vocabulary)

| Code | Plane | Where it lives | Auth | Status today |
|---|---|---|---|---|
| **APP** | App-only — pure client work, no server change | Talaria | n/a | available now |
| **SESS** | Sessions API — `/api/sessions*`, `/v1/*` | `:8642` gateway | Bearer `API_SERVER_KEY` | **shipping today** |
| **RUNS** | Runs API — `POST /v1/runs`, `/events`, `/stop`, `/approval` | `:8642` gateway | same Bearer | available, unused by us |
| **TP** | Talaria platform adapter — a `BasePlatformAdapter` registered via `ctx.register_platform` | in-process on the gateway; webhook ingress via `POST /api/platforms/talaria/events` (**no new port**, C§18) | adapter-owned | **the 2A spine, building now** |
| **WS** | `tui_gateway` JSON-RPC over WebSocket `/api/ws` | `:9119`, requires a second process (`hermes serve`) | dashboard auth → 30 s single-use ticket | not running anywhere today (D§2.2) |
| **DASH** | Dashboard REST `/api/*` | `:9119`, same process as WS | same dashboard auth | not running anywhere today |
| **PLUG** | Plugin-custom — our own registered tools, slash commands, CLI verbs, hooks, outbound webhooks | in-process, wherever the agent runs | inherits | none registered yet |

**The parity target is a `tui_gateway` client.** Hermes Desktop "talks to a headless backend the app
launches for you — a `hermes serve` process that serves the `tui_gateway` JSON-RPC/WebSocket API —
and reuses the agent runtime rather than embedding `hermes --tui`. The desktop app is
**self-contained**: it runs its own `hermes serve` backend and never opens or requires the web
dashboard" (user-guide/desktop.md:208). Its plugin SDK exposes
`host.request<T>(method, params?)` — "the same JSON-RPC the app itself uses (sessions, config,
skills, cron, kanban, …)" (developer-guide/desktop-plugin-sdk.md). So **every desktop feature that
touches the agent is an M3 feature**; only window/filesystem/git/notification chrome is Electron-local.
That is the single most important framing fact for a parity exercise: matching the desktop means
adopting M3, or reimplementing each capability on a thinner plane.

⚠ **A live doc contradiction to resolve before planning on it.** `desktop.md:221` says the remote
backend "means a **`hermes serve`** server"; `features/web-dashboard.md:138` says "The 'remote
backend' Desktop connects to **is** a `hermes dashboard` process"; `docker.md:234` also says
`hermes dashboard`. Same port (9119), same `/api/status` + `/api/ws` contract in all three — likely
one server under two command names (D§2.4 says they differ only in whether the SPA is built), but
the docs state it both ways. **Probe before committing.**

Two structural facts that govern the whole menu:

1. **`APIServerAdapter` deliberately opts out of the adapter runtime** (A§0). Its `send()` is a
   failure stub and `supports_async_delivery = False`. Everything wired onto `GatewayRunner` is
   *structurally* unreachable from HTTP; everything inside `agent/`, `tools/`, `run_agent.py` fires
   on both lanes (C§0). That single boundary explains ~80% of the TP-only rows below.
2. **The target is a hybrid, not a migration** (C§21). Chat stays on `/chat/stream` for token-level
   SSE with a separate reasoning channel — the platform lane's progressive-edit streaming is
   *coarser*. The adapter exists for **delivery, media, and control**, not to replace streaming.

---

## 1. THE MENU

Effort is for Talaria-side work (S ≤ a lane, M = a wave, L = a multi-wave programme).
Value is **for a phone user specifically**.

### 1.1 Chat, streaming, and turn control

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| C1 | Token-level SSE with a separate reasoning channel | Answer streams word-by-word; thinking renders in its own collapsible surface, never folded into the answer | SESS | C§21.1; CLAUDE.md SSE taxonomy | — | **High** *(shipping)* |
| C2 | **Mid-turn steer** — inject a correction into a running turn without interrupting | "Actually, use the other branch" lands on the next tool result; no restart, no lost work | WS (`session.steer`) or TP (`busy_input_mode: steer`) | D§4.2 (`methods_session.py:3055`); A§5.1 (`run.py:8874-8960`) | M | **High** |
| C3 | Mid-turn **redirect** — repoint the active turn, preserving valid work | Change of mind without throwing away the tool calls that already paid off | WS (`session.redirect`) or TP | D§4.2 (`:3088`); A§5.1 | M | **High** |
| C4 | Mid-turn **interrupt / stop** | A stop button that actually stops — clears queue, denies pending approvals, halts TTS | WS (`session.interrupt`) · RUNS (`POST /v1/runs/{id}/stop`) · TP (`/stop`) | D§4.2 (`:2824`); C§17; api-server.md §Runs | S (RUNS) / M (WS,TP) | **High** |
| C5 | **Server-side prompt queue** — type follow-ups while it works, order preserved | The single most mobile interaction pattern; today each request is independent and last-writer-wins | WS (`_enqueue_prompt`) or TP | D§4.2; C§17 | M | **High** |
| C6 | Photo-burst merge + rapid-text debounce | Three quick messages become one turn instead of three; an album is one turn | TP | A§5.1 (`base.py:5203-5311`, 0.35 s window / 1.0 s cap) | S *(free with TP)* | Med |
| C7 | Progressive-edit streaming with flood backoff + reconciliation | Delivery recovery when a stream dies mid-answer — the gain is the reconciliation, not the streaming | TP | A§2.4 (`stream_consumer.py:156-322`) | M | Med |
| C8 | Full-length untruncated replies | Long answers arrive whole | TP (`splits_long_messages = True`) | C§21.4 — **without this, the platform lane clips at 4000 chars** | S | **High** *(guard rail)* |
| C9 | Live "what is it doing right now" status line | "is running pytest…" — a large perceived-latency win at zero extra API calls | TP (`supports_status_text`) · WS (`status.update`) | A§8.1 (`base.py:2650-2674`); D§4.9 | S | Med |
| C10 | Typing indicator | The bubble that says it's alive | TP (`send_typing`) | A§8.1 (`base.py:4677-4761`) | S | Low *(our SSE is richer)* |
| C11 | Interim assistant commentary between tool batches | Narration while a long tool chain runs | TP · WS (`message.interim`) | A§8.1 (`run.py:24280-24290`); D§4.1 | S | Med |
| C12 | Composer history + editable queue | Up-arrow to recall prompts; edit or delete queued turns before they send | APP (+ C5 for the queue half) | desktop.md:47 (parity target) | S | Med |
| C13 | Conversation timeline rail + find-in-transcript | Jump-to-prompt markers on long chats; Cmd-F over the transcript | APP | desktop.md:48-49 | S | Med |
| C14 | Focus mode / verbosity cycling | Hide tool chatter without touching history or the prompt cache | APP · TP (`/focus`, `/verbose`) | reference/slash-commands.md:284-286 | S | Med |

### 1.2 Push, background, and the doorbell — the biggest structural gap

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| **P1** | **Outbound-webhook doorbell — push that works on the lane we already ship** | A signed HTTPS POST to an endpoint we choose whenever a turn ends, a tool completes, or a subagent finishes → relay → APNs. **No adapter, no Hermes code change, config-only on the host.** | PLUG (config `hooks.outbound`) + our receiver | features/hooks.md:1512-1600. Registration wires "notify-only callbacks on the **existing plugin hook manager**, so **every `invoke_hook()` site**" fires (`agent/outbound_webhooks.py:1-12`). `on_session_end` is emitted from `agent/turn_finalizer.py:738` — **shared agent code, both lanes** (C§4.2). Also `post_tool_call` (`model_tools.py:1104`), `subagent_stop` (`tools/delegate_tool.py:2719`), `on_session_start` (`agent/conversation_loop.py:575`). HMAC-SHA256 `X-Hermes-Signature-256`, `delivery_id` dedupe, timestamp replay window | **S–M** | **High** |
| P2 | Proactive async delivery / wake — the agent can reach the phone between turns | Long tasks ping you when done; `terminal(notify_on_complete=…)`, `watch_patterns`, `delegate_task(background=True)` stop being refused | TP (`supports_async_delivery` defaults `True` + a real `send()`) | A§1.1; C§1.1 (`api_server.py:1361` pins it `False`; tools read the contextvar and **refuse to promise delivery today**) | M *(on top of the spine)* | **High** |
| P3 | Cron / scheduled briefings that actually arrive on the phone | "Morning brief at 07:00" lands as a notification instead of sitting in a transcript | TP (`cron_deliver_env_var` + `standalone_sender_fn` on the `PlatformEntry`) | A§1.2; C§2.1. Today `deliver="api_server"` resolves to **no target at all**; `deliver="origin"` burns a full agent turn and delivers nothing (C§2.2) | S *(two entry fields)* | **High** |
| P4 | Kanban terminal-event push | Create a task from the phone and get one message back per terminal event (`completed`/`blocked`/`gave_up`/`crashed`/`timed_out`) with the first line of the result | TP | kanban.md:839 — the originating chat auto-subscribes; explicitly designed for "send `/kanban unblock t_abcd` from your phone" (kanban.md:829) | S *(free with TP)* | **High** |
| P5 | Durable delivery-obligation ledger | A gateway crash between "turn finished" and "response written" no longer loses a paid-for answer — it redelivers on next boot with a `RECOVERED` marker | TP | A§6.1 (`delivery_ledger.py`, 4 checkpoints, `MAX_ATTEMPTS=3`, sweep + redeliver at `run.py:10289-10360`) | S *(free with TP)* | **High** |
| P6 | Send retry + error classification + dead-target suppression | Flaky-LTE resilience; a confirmed-dead target stops being hammered and self-heals | TP | A§6.2 (`base.py:5042-5132`, `dead_targets.py`) | S *(free)* | Med |
| P7 | Reconnect-aware final delivery | A reconnect mid-turn routes the not-yet-sent answer to the replacement transport | TP | A§6.3 (`base.py:5014-5041`) | S *(free)* | Med |
| P8 | Shutdown / restart notices | "Your task was cut off, message me to resume" instead of silence | TP | A§1.3 (`run.py:9250-9395`) | S *(free)* | Med |
| P9 | ntfy as an interim push channel (zero Talaria code) | Cron and gateway notices reach the phone via the ntfy app today | *(host config only)* | messaging/ntfy.md — a shipping, first-class push-shaped adapter with `NTFY_HOME_CHANNEL` + `standalone_sender_fn`; also the **smallest working template** for the Talaria adapter | S | Med *(bridge, not destination)* |

> **P1 is the finding to act on first.** It is the only push mechanism in this document that
> requires neither the adapter nor a second Hermes process, and it fires on the exact lane Talaria
> already speaks. Caveat to hold: outbound webhooks are **fire-and-forget, best-effort** —
> "Bounded retries… Failures are logged and dropped — delivery is best-effort, not guaranteed"
> (hooks.md §Delivery semantics). Pair it with P5 once TP lands.
>
> **The relay decision this forces.** P1 needs an HTTPS receiver that can mint an APNs push. The
> relay already owns APNs. Adding a receive route is **new surface, not hardening** — but it is
> still relay surface, and CLAUDE.md's standing rule says raise a relay change with Owen as a
> decision rather than building it. Two alternatives that avoid the relay entirely: point
> `hooks.outbound.url` at a **self-hosted ntfy** (`POST https://ntfy.host/<topic>`) and let ntfy's
> own app deliver the push; or stand the receiver up as a **new tiny sidecar** that is not the
> relay. Flag for Owen, do not pick unilaterally.

### 1.3 Artifacts, files, and media out — the #21 story

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| **F1** | **Artifact preview panes** — render agent-produced HTML / Markdown / SVG / code / diagrams in-app | The owner's headline ask. Upstream desktop shipped exactly this in v0.20.0 ("Artifacts now render with sandboxed live preview") — this is **parity, and the phone can beat it**; see §2.1 | APP *(today)* → TP *(for real files)* | Reconstruction from SSE `tool.started {tool_name:"write_file", args:{path, content}}` — CLAUDE.md #21 Tier 1, verified; `open_preview`/`read_preview` are **hard-gated to the desktop app** (reference/tools-reference.md:176-177) so no server plane offers a preview surface | **M** | **High** |
| F2 | Artifacts gallery — every image/file/link a session produced, searchable, jump-back-to-chat | Desktop's Artifacts view, on a phone | APP (index from SSE tool events) · DASH (`/api/files/*`) | desktop.md:91-93 (parity target); D§4.7 for the dashboard file family | M | **High** |
| F3 | **Native file delivery for ~60 extensions** — PDF, CSV, xlsx, zip, .md, audio, video, HTML | Today Talaria gets **images only, base64, ≤5 MB**; everything else is stranded | TP (`send_document`/`send_video`/`send_voice`) | C§8 — the largest single capability delta in the gap analysis. `MEDIA_DELIVERY_EXTS` at `base.py:1643-1670`; API-lane cap at `api_server.py:1018-1066` | M | **High** |
| F4 | **Deliverable mode** — the agent just mentions a path and the file arrives as an attachment | "Send me the comparison as a chart" → the PNG lands inline. No `MEDIA:` tag needed | TP | features/deliverable-mode.md — "it just generates the file and mentions its absolute path in the response. The gateway picks the path out of the text… and uploads the file natively." Full extension table incl. `.html .htm` | S *(free with F3)* | **High** |
| F5 | Auto-append media for producer tools | `text_to_speech`, `image_generate`, `bfl_flux3_get_result` outputs arrive without the model having to mention them | TP | C§8.1 (`run.py:1443`, `:5576-5592`) — allowlisted to four tools | S *(free)* | Med |
| F6 | Media-delivery path validation + credential-dir denylist | The guardrail that makes arbitrary-file delivery safe to turn on | TP | A§2.2 (`base.py:1451-1537`; denies `/etc /proc /root …`, `~/.ssh .aws .gnupg .kube` …) | S *(free)* | Med |
| F7 | Per-turn media dedup against transcript history + user-visible upload-failure notice | The same chart isn't re-sent every turn; a failed upload says so instead of vanishing | TP | A§2.1 (`base.py:3416-3468`, `:4266-4303`) | S *(free)* | Med |
| F8 | Host file browser / download | Read and pull any file from the agent host — closes #21 Tier 2 **without a relay sidecar** | DASH (`GET /api/files`, `/read`, `/download`, `POST /upload`, `/mkdir`, `DELETE`) | D§4.7 (`web_server.py:2349-2572`; `/api/files/download` is in `_QUERY_TOKEN_API_PATHS` so a plain URL load works). ⚠ **Code-verified in report D; NOT documented in the published docs** — treat as an implementation detail that could move | M *(needs the :9119 process)* | **High** |
| F9 | Kanban completion artifacts | A worker's deliverables ride the "task done" notification as attachments | TP | deliverable-mode.md:79-99 (`kanban_complete(artifacts=[…])`); "Files that don't exist on disk when the notifier runs are silently skipped" | S *(free)* | Med |
| F10 | Share Sheet / Files.app / Quick Look export of any artifact | The iOS-native superset of desktop's download / open-in-browser / copy | APP | desktop.md:93 names the desktop actions; the iOS side is ours | S | Med |

### 1.4 Media in — camera roll, voice memos, documents

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| I1 | Images in | *Already works* — `data:` / `http(s)` content parts on `/chat` and `/chat/stream` | SESS | C§6.1 — "the Sessions API is not image-blind" | — | **High** *(shipping)* |
| I2 | **Voice notes in, with automatic STT** | Push-to-talk — the phone's native input mode. Transcribed server-side with a local-STT fallback, a silent-clip sentinel, and an optional `🎙️ "…"` echo | TP (tag `MessageType.VOICE` + cache bytes) | A§4.2 (`run.py:21406-21553`); C§7. `transcribe_audio` is **in no toolset**, so the API lane cannot reach STT even indirectly | M | **High** |
| I3 | Documents / audio files / video in | Files-app and share-sheet input. Today all three return **HTTP 400** on the API lane | TP | C§6.2 (`api_server.py:643-653`); platform path at `run.py:15790-15980` | M | **High** |
| I4 | Vision routing that works on non-vision models too | A photo still gets understood when the pinned model has no vision — `vision_analyze` runs first and the description is prepended | TP | A§4.3 (`run.py:15810-15862`, `_decide_image_input_mode`) | S *(free with TP)* | Med |
| I5 | Inbound media cache with size guards + SSRF-guarded URL fetch + content sniffing | The plumbing that makes I2–I4 safe; also gives tools a local path to work from | TP | A§4.1 (`base.py:729-1966`) | S *(free)* | Med |
| I6 | Upload attachments by bytes from a remote client | `image.attach_bytes` (25 MiB), `file.attach` (returns an `@file:` workspace ref), `pdf.attach` (renders pages at 150 DPI) — explicitly built for clients that don't share a filesystem with the gateway | WS | D§4.7 (`methods_prompt.py:419/480/606`) | M | Med |
| I7 | Drag-and-drop / paste into the composer | Desktop parity; on iOS this is the share sheet + photo picker + Files picker | APP (+ I3 for transport) | desktop.md:45 | S | Med |

### 1.5 Voice

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| V1 | Auto-TTS on voice input, voice-first ordering | Speak, hear the answer back — audio arrives *before* the text | TP (`send_voice`) | A§2.3 (`base.py:3139`, `:5952-6035`); `/voice on\|off\|tts` three-layer decision | M | **High** |
| V2 | Streaming TTS — speech while the model is still generating | Hands-free / CarPlay-shaped use; the differentiator a phone actually has | TP (5 opt-in methods) | A§2.3 (`base.py:4130-4165`; `streaming_tts_consumer.py`). **No shipped adapter implements this** (B§1) — we would be first | L | **High** |
| V3 | Remote TTS/STT over HTTP | `POST /api/audio/transcribe`; `WS /api/audio/speak-stream` streams **raw int16 PCM out** with incremental text feeding, `{"stop":true}` barge-in, and a fallback signal | DASH | D§4.8 (`web_server.py:4304`, `:4615-4635`) — same auth ticket as `/api/ws` | M | Med |
| V4 | **On-device wake word driving the host agent** | "Hey Hermes" from the phone. Upstream supports a *client* capture mode by design | WS (`wake.start` w/ `client_capture: true` → `wake.feed` 16 kHz mono int16 → `wake.detected`) | features/wake-word.md:40-75; `wake_word.capture: auto\|local\|client`. Single-mic sticky ownership; off by default | M | Med |
| V5 | `/voice` control surface | On / off / tts / status, persisted across restarts | TP · APP | features/voice-mode.md; reference/slash-commands.md | S | Med |

> ⚠ `tui_gateway`'s `voice.record` / `voice.tts` / `wake.*` RPCs are **host-side** — they drive the
> gateway machine's mic and speakers (D§4.8). For a phone they are the wrong end of the wire.
> V3 and V4 are the two that face the right direction.

### 1.6 Human-in-the-loop — approvals, clarify, confirms

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| **H1** | **Dangerous-command approval on the chat plane** | Today, an exec approval on `/chat/stream` **degrades to an unrecoverable tool result — no human is ever asked** | RUNS *(full parity today)* · TP · WS | C§5.1. `/v1/runs` has `approval.request` SSE + `POST /v1/runs/{id}/approval` with `{once, session, always, deny}` (`api_server.py:6391-6837`). The `submit_pending(...)` call on the chat plane is a **dead end** — nothing reads `_pending` | S (RUNS) / M (TP) | **High** |
| H2 | **MCP elicitation consent** | Today every MCP elicitation on `/chat` and `/chat/stream` is **silently auto-declined** ("failing closed") — it looks like the tool is broken | RUNS · TP · WS | C§5.2 (`tools/approval.py:4292`, `:4319-4327`) | S *(rides H1)* | **High** |
| H3 | `clarify` as a native picker sheet | "Which of these three?" as tappable options instead of a numbered text list; multi-select aware | TP (`send_clarify` — a working numbered-text default ships free) · WS (`clarify.request`/`clarify.respond`) | A§3.2 (`base.py:3780-3852`); C§5.3 — `clarify` is **absent from the API toolset entirely** (C§10) | M | **High** |
| H4 | Busy-guard command bypass | `/approve` reaches the resolver instead of queueing behind the blocked agent thread. **Without this, `/approve` deadlocks** | TP | A§5.2 (`base.py:5593-5709`) — the precondition for H1 working at all | S *(free with TP)* | **High** |
| H5 | Slash-confirm Once / Always / Cancel | The three-option prompt destructive commands use | TP (`send_slash_confirm`) · WS | A§3.3; C§5.4 | S | Med |
| H6 | sudo / secret elicitation prompts | Two more HITL flows, expiry-modelled and reconnect-tolerant (`allow_expired=True` specifically so a late answer after a WS reconnect resolves) | WS (`sudo.respond`, `secret.respond`) | D§4.3 (`methods_prompt.py:879-933`) | M | Med |
| H7 | Model / choice pickers | `/model`, `/reasoning`, `/fast` as native pickers on the same plane as everything else | TP (`send_model_picker`, `send_choice_picker`) | A§3.3 (`slash_commands.py:1779`, `:2076`, `:3298`) | S | Med |
| H8 | Per-session YOLO toggle | Bypass approvals for one session, matching TUI/desktop | TP (`/yolo`) · APP | desktop.md:55; slash-commands.md:289 (`/yolo` works on both surfaces) | S | Med |
| H9 | Smart-approval visibility | See *why* a command was auto-approved or flagged | TP (`/approvals`) | slash-commands.md:289 | S | Low |

### 1.7 Sessions, history, and continuity

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| S1 | Session list / create / rename / delete / message history / **fork** | *Already works* — and there is **no platform-lane HTTP equivalent** | SESS | C§21.2 | — | **High** *(shipping)* |
| S2 | Compression-chain-aware resume | Resuming a rotated-out parent id lands on the descendant holding post-compression turns — a correctness behaviour the Sessions-API client does **not** get for free | WS (`session.resume`) | D§4.5 (`methods_session.py:353-372`) | M | Med |
| S3 | `session.branch` / `undo` / `compress` / `context_breakdown` / `usage` | 25+ session methods, richer than the REST surface | WS | D§4.5 | M | Med |
| S4 | Checkpoints + `/rollback` | Undo the agent's file edits *and* the last conversation turn, from a shadow git repo that never touches your real `.git` | TP (`/rollback`) · DASH (`GET /api/ops/checkpoints`) | user-guide/checkpoints-and-rollback.md — **opt-in as of v2** (`checkpoints.enabled: true`) | S | Med |
| S5 | Session export (JSON / trace) + prune + archive | Pull a transcript out; keep the list manageable | DASH (`GET /api/sessions/{id}/export`, `POST /api/sessions/prune`, `PATCH`) | web-dashboard.md:551-556; user-guide/sessions.md | S | Med |
| S6 | Full-text search across all message content | FTS5 search with highlighted snippets — desktop/dashboard parity | DASH (`GET /api/sessions/search`) · PLUG (`session_search` tool) | web-dashboard.md:458; features/memory.md | S | Med |
| S7 | **`/handoff <platform>`** — a CLI or desktop session continues on the phone, same session id | Start at the desk, walk away, keep going on the phone | TP (`create_handoff_thread`) | A§5.4 (`base.py:3525-3549`, watcher at `run.py:11616-11730`); user-guide/sessions.md | M | **High** |
| S8 | Session-id discovery for platform sessions | Finding "our" sessions over REST | SESS (`GET /api/sessions?source=talaria`) | C§14.4 — ⚠ `session_key` is **not exposed** by `_session_response` (`api_server.py:3202-3209`), so discovery is by `source` convention, not by key | S | Med |
| S9 | Cross-profile session references / concurrent multi-profile | Run sessions in several profiles at once; `@session` links across them | APP + SESS (`/p/<profile>/` prefix) | desktop.md:167; api-server.md §Multi-profile routing | M | Low |

> **The one thing that could quietly break the hybrid** (C§21): session identity. A platform turn
> keys on `build_session_key(source)`; an API turn keys on whatever `X-Hermes-Session-Key` we send.
> If those don't match byte-for-byte we get **two memory scopes and two transcripts for one
> conversation**. This is testable today with no adapter written, and it is the highest-value thing
> to verify before committing.

### 1.8 Models, routing, and cost

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| **G1** | **Per-turn model / provider / reasoning-effort — without the hanging pin** | Pick a model, or bump reasoning effort for one hard question, per request. **Directly sidesteps OPEN_ITEMS #9** (the `/model` session pin that hangs ~37 s+) | SESS | features/api-server.md §Per-request model selection — `model`, `provider`, `model_options` (`reasoning_effort`, `service_tier`) are accepted on `POST /api/sessions/{id}/chat` **and** `/chat/stream`. Deterministic 4-step precedence; explicit `provider` always honoured | **S** | **High** |
| G2 | Rich model picker metadata | Provider rows, curated model lists, per-model pricing, capability hints — the same substrate the dashboard Models page uses | SESS (`GET /api/model/options`, `?refresh=1`) | api-server.md §GET /api/model/options; verified live on 0.20.0 (CLAUDE.md) | S | **High** |
| G3 | Deferred mid-turn model switch | Change model while a turn runs — it applies at the next turn start instead of erroring | WS (`config.set {key:"model"}`) | D§4.6 (`server.py:10502-10527`) | M | Med |
| G4 | Model-route aliases | `gateway.platforms.api_server.model_routes` maps a friendly name to a provider+model | SESS *(host config)* | api-server.md §Per-request model selection | S | Low |
| G5 | Mixture-of-Agents presets as selectable models | MoA presets appear under the `moa` provider — free if we render the model list | SESS (G2) | features/mixture-of-agents.md:9,21 | S *(free with G2)* | Med |
| G6 | Per-model effort/fast presets remembered client-side | Pick a model once; its reasoning-effort choice comes back with it | APP (+ G1) | desktop.md:84 (desktop-local convenience, not server state) | S | Med |
| G7 | Token / cost analytics | Daily token chart, cache-hit %, per-model cost breakdown | DASH (`GET /api/analytics/usage?days=`) · SESS (`run.completed` `usage`) | web-dashboard.md:470, :258-266 | S | Med |
| G8 | Context-usage meter with per-category breakdown | "% full" with system prompt / tools / skills / memory / MCP / conversation split, before compression bites | WS (`session.context_breakdown`) · TP (`/context`) | desktop.md:56; D§1.2 | M | Med |

### 1.9 Skills, tools, MCP

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| K1 | Skill + toolset discovery | List every skill and toolset with the concrete tools each expands to | SESS (`GET /v1/skills`, `/v1/toolsets`, `/v1/capabilities`) | api-server.md §Skills and toolsets discovery — read-only, Bearer-gated | **S** | Med |
| K2 | Invoke a skill as a slash command; stack up to 5 | `/github-pr-workflow /test-driven-development fix #123` | TP | features/skills.md — every installed skill is auto-exposed as a slash command | S *(free with TP)* | **High** |
| K3 | **Skills Hub — search and install from the phone** | Browse 8 remote sources (official, skills.sh, well-known, GitHub taps, ClawHub, LobeHub, browse-sh), install by identifier with a live install log, "Update all" | DASH (`GET /api/skills/hub/search`; `POST /api/skills/hub/install\|/uninstall\|/update`) | web-dashboard.md:551-552, :297. **Not a Hermes-hosted registry** — skills.md:587: "It is not a single centralized hub — it is a web discovery convention." There is **no "HermesHub"** (zero hits in the docs) | M | Med |
| K4 | Enable / disable individual skills and toolsets | A settings pane that actually changes what the agent can do | DASH (`GET /api/skills`, `PUT /api/skills/toggle`, `GET /api/tools/toolsets`) | web-dashboard.md:498-508 | S | Med |
| K5 | **MCP server management from the phone** | Add / test / enable / disable / remove MCP servers, and one-tap install from the Nous-approved catalog | DASH (`GET\|POST /api/mcp/servers`, `POST .../test`, `PUT .../enabled`, `DELETE`, `GET /api/mcp/catalog`, `POST /api/mcp/catalog/install`) | web-dashboard.md:517-523, :301-317. ⚠ No MCP CRUD is documented over JSON-RPC — only `reload.mcp` | M | Med |
| K6 | Register **Talaria's own tools** the agent can call | The agent can read the phone's sensors, location, health, contacts, calendar — as first-class Hermes tools | PLUG (`ctx.register_tool`) | developer-guide/plugins/index.md:264-283; `ctx.dispatch_tool` is the supported cross-tool door (:279) | **M** | **High** |
| K7 | Register a `/talaria` slash command | Appears in autocomplete, `/help`, and even the Telegram bot menu | PLUG (`ctx.register_command`) | plugins/index.md:792-794 | S | Med |
| K8 | Register a `hermes talaria …` CLI verb | Poke the phone from the terminal: `hermes talaria push "…"` | PLUG (`ctx.register_cli_command`) | plugins/index.md:277, :759 | S | Med |
| K9 | Register a Talaria **skill** | Ship phone-shaped procedural knowledge with the plugin, namespaced `talaria:<skill>` | PLUG (`ctx.register_skill`) | plugins/index.md:416; features/plugins.md:107 — plugin skills are read-only and not in the prompt's skill index | S | Med |
| K10 | Tool Search awareness | When many MCP/plugin tools are loaded they collapse behind `tool_search`/`tool_describe`/`tool_call` — but the activity feed **unwraps to the real tool name**, so our UI needs no special case | APP | features/tool-search.md:56-61 | S | Low |
| K11 | Hermes as an MCP server | Other MCP-capable agents can list conversations, read history, and send messages across connected platforms | *(host)* | features/mcp.md:766 (`hermes mcp serve`, stdio) | — | Low |

### 1.10 Scheduling and automation

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| N1 | Scheduled-job CRUD from the phone | Create, edit, pause, resume, trigger-now, delete recurring agent prompts | SESS (`/api/jobs*`) · DASH (`/api/cron/jobs*`) | api-server.md §Jobs API; web-dashboard.md:474-496 | **S** | **High** |
| N2 | Cron delivery to the phone | See **P3** — without it, jobs run, burn tokens, and deliver nowhere | TP | C§2.2 | S | **High** |
| N3 | Skill-backed and script-only ("no-agent") jobs | A job can attach skills, pin a model/provider, set a workdir, or skip the LLM entirely and deliver stdout verbatim at zero cost | SESS (`POST /api/jobs`) · TP (`/cron`) | features/cron.md; guides/cron-script-only.md | S | Med |
| N4 | Automation blueprints | Install a skill that carries a schedule in its frontmatter; it lands in `/suggestions` rather than scheduling silently | TP (`/blueprint`, `/suggestions`) · DASH (Cron → Blueprints tab) | developer-guide/creating-skills.md:344; guides/automation-blueprints.md | M | Med |
| N5 | Goals — a standing objective with a per-turn judge | "Keep working until the suite is green"; parks on background processes automatically | TP (`/goal`, 9 subcommands) | features/goals.md — "Works identically on the CLI and every gateway platform" | S *(free with TP)* | Med |
| N6 | Inbound webhooks as triggers | GitHub/JIRA/Stripe events wake the agent; results can deliver to us | *(host, `:8644`)* | messaging/webhooks.md — HMAC routes, payload filters, script transforms, `deliver_only` zero-LLM mode | — | Low |

### 1.11 Multi-agent, delegation, kanban

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| J1 | `/agents` — live background delegations with per-child activity | `deleg_ab12cd34 · running · <goal>` and `4 api calls · in web_search · active 12s ago`; stalls render as `stalling · no progress 450s — interrupting` | TP | features/delegation.md:256-267 — works on **every gateway platform**, not just the TUI. ⚠ Kill/pause is documented for the **TUI overlay only** | S *(free with TP)* | Med |
| J2 | Subagent lifecycle on the run stream | `subagent.start` / `subagent.complete` with status, summary, duration, token/cost and a `child_session_id` — so a run doesn't go silent while a child works | RUNS | api-server.md §GET /v1/runs/{id}/events. Per-tool child events are deliberately **not** forwarded | S | Med |
| J3 | **Native kanban board with a live event stream** | A real board on the phone: columns, drag-to-status, per-profile lanes, comments, dependency editor, Decompose/Specify actions | DASH (`/api/plugins/kanban/board`, `/tasks`, `/comments`, `/dispatch`, `/workers/active`, `POST /runs/{id}/terminate`, **`WS /events?since=<event_id>`**) | features/kanban.md:621, :787, :543 | L | Med |
| J4 | `/kanban` from any chat, mid-turn | "A worker blocks waiting on a peer → you send `/kanban unblock t_abcd` from your phone" — **bypasses the running-agent guard**, so reads and writes go through even mid-turn | TP | kanban.md:812, :829. ⚠ Text responses truncate at ~3800 chars — use J3's REST for a real UI | S *(free with TP)* | Med |
| J5 | Live delegation transcripts | Append-only human-readable log per child at `cache/delegation/live/<id>/task-<n>.log` + a `manifest.json` with goals and per-task status | PLUG (`terminal` tool) · DASH (`/api/files/read`) | features/delegation.md:286 | M | Med |
| J6 | Subagent lifecycle API for our plugin | Supported `launch/status/wait/cancel/result/reconnect` with a serializable handle and 9 states | PLUG (`ctx.subagent_lifecycle`) | developer-guide/subagent-lifecycle-api.md. ⚠ "Launching outside an active agent turn fails closed"; results retained 1 h; `RECONNECT_UNAVAILABLE` after restart | M | Low |

### 1.12 Memory and context

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| M1 | **Richer long-term memory scope** | `user_id`, `chat_id`, `thread_id`, `user_name` threaded into memory providers instead of session-id-only — today on the API lane **memory dies with the transcript** unless we send `X-Hermes-Session-Key` | TP *(automatic)* · SESS *(header, today)* | C§14.3 (`agent/agent_init.py:1733-1747`; platform kwargs at `run.py:4762-4767` vs API's absent set) | S (header) / free (TP) | **High** |
| M2 | Memory provider selection + reset | Pick among 9 external providers (Honcho, Mem0, Supermemory, …) or reset built-in memory | DASH (`GET /api/memory`, `PUT /api/memory/provider`, `POST /api/memory/reset`) | web-dashboard.md:~540; features/memory-providers.md | S | Low |
| M3 | Learning-journey graph (`/journey`) | A zoomable constellation of learned skills and memories with a timeline scrubber; nodes editable/deletable | TP (`/journey`) · APP (render) | desktop.md:118-121 (desktop calls it Star Map); features/memory.md | M | Med |
| M4 | Session-context prompt block | Source, channel topic, user identity, multi-user notes, room boundaries, PII redaction injected per turn | TP | C§12.2 (`gateway/session.py:479`) | S *(free)* | Low |
| M5 | Context references (`@file:`, `@diff`, `@url:` …) | Inline context expansion in the composer | APP | features/context-references.md — ⚠ **explicitly CLI-only**: "In messaging platforms… the `@` syntax is **not** expanded by the gateway." A phone client must expand it itself | M | Med |
| M6 | Project context files (`AGENTS.md` / `CLAUDE.md` / `SOUL.md`) viewer-editor | See and edit the persona and project rules the agent is actually running under | DASH (`/api/config`, `/api/env`) · APP | features/context-files.md; web-dashboard.md:422-448 | M | Low |

### 1.13 Presentation, identity, and personality

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| **X1** | **Own the platform hint** | Today the model is told *"assume plain text. No markdown formatting (no asterisks, bullets, headers, code fences)"* — **every turn, on the client that renders markdown beautifully.** Flipping it also enables the `MEDIA:` delivery contract | SESS *(config only, today)* → TP *(ours by right)* | C§12.1 / A§9. `_resolve_platform_hint` (`agent/system_prompt.py:73-120`) supports a `platform_hints.api_server.replace` override **with zero code and no Hermes patch**. A§9 calls it "arguably the cheapest single win in this document" | **S** | **High** |
| X2 | Structured stream-event render hooks | The seam for rendering tool calls as native SwiftUI cards rather than emoji-prefixed text; returning `None` from `format_tool_event` **eats** an event without touching persisted history | TP | A§8.2 (`base.py:3029-3121`) | M | Med |
| X3 | Personality presets + `SOUL.md` | 14 built-in personalities, session overlay via `/personality`, durable baseline in `SOUL.md` | TP (`/personality`) · DASH | features/personality.md | S | Low |
| X4 | Pets / mascot state driven by agent activity | 8 animation states (`idle`, `wave`, `run`, `review`, `failed`, `jump`, `waiting`) mapped to what the agent is doing; `/hatch <description>` generates a new one via the image-gen provider | APP (render) + TP (state) | features/pets.md | M | Low |
| X5 | Skins / themes | ⚠ Hermes skins are **terminal-render concepts** (ANSI colours, ASCII banners, spinner verbs). There is **no skin format for a native GUI client** — Talaria's own theme system (Deep Field / Solar Forge / Terminal / Paper Tape) has no upstream counterpart to match | APP | features/skins.md | — | Low |
| X6 | Runtime footer (model / context% / latency) | A one-line status under each answer | TP | C§12.3 (`gateway/runtime_footer.py`) | S *(free)* | Low |
| X7 | **DM pairing-code onboarding** | First run is "enter this 8-char code" instead of pasting a 64-char API key. 1 h expiry, rate limits, lockout after 5 failures, codes never logged | TP | A§7.2 (`gateway/pairing.py`); DASH exposes approve/revoke (`/api/pairing*`) | M | Med |
| X8 | Per-user authorization instead of one shared bearer | Real identity, or `authorization_is_upstream = True` mapping cleanly onto our existing model | TP | A§7.1 (`authz_mixin.py:386-560`; `base.py:2912-2941`) | S | Med |
| X9 | Reaction-ack lifecycle (👀 → ✅/❌) | Lightweight "seen / done / failed" feedback without a message | TP | A§4 (`base.py:4915-4960`) | S | Low |
| X10 | **OS notifications for approvals and turn completion** | Desktop already does this: `ctx.os.notify` is "the same Electron pipeline the app's own **approval/turn alerts** use," firing "only while the user is away from Hermes (backgrounded / unfocused)". On iOS this is APNs + local notifications — **direct parity, and the phone is the natural home for it** | APP + M5 (P1) | desktop-plugin-sdk.md §`ctx.os` | S *(rides P1)* | **High** |
| X11 | Pet overlay behaviours worth stealing | Desktop's pet pops out into "its own transparent, always-on-top desktop window"; single-click opens "a mini composer to send a prompt to the most recent session"; a **mail icon** appears when a turn finished while you were away; roam-while-idle; local token-free "vibe" lexicon (no model call) | APP | features/pets.md:111-184 | M | Low |
| X12 | Projects as a workspace abstraction | "A project may own multiple folders, repositories, worktrees, and sessions"; agent-side `project_create` / `project_list` / `project_switch` are **desktop/GUI-gated tools** today | TP + APP | `apps/desktop/README.md:151-153`; reference/tools-reference.md:140-146 | M | Low |

### 1.14 Admin, ops, and observability

| # | Feature | What the user gets | Plane | Evidence | Eff | Val |
|---|---|---|---|---|---|---|
| O1 | Detailed readiness check | Config, state DB, model, disk space, gateway/platform state, active API runs, pending process completions, **active delegations** — status and counts only, no secrets | SESS (`GET /health/detailed`) | api-server.md §GET /health/detailed | **S** | Med |
| O2 | Gateway lifecycle from the phone | Start / stop / restart the gateway | DASH (`POST /api/gateway/start\|/stop\|/restart`) | web-dashboard.md:~545 | S | Med |
| O3 | Log viewer with level/component filters and live tail | agent / errors / gateway logs, colour-coded, 5 s auto-refresh | DASH (`GET /api/logs`) | web-dashboard.md:247-256, :466 | S | Med |
| O4 | Host stats + update check | OS/CPU/memory/disk/uptime; "commits behind" with the actual commit list | DASH (`GET /api/system/stats`, `/api/hermes/update/check`) | web-dashboard.md:~547-549 | S | Low |
| O5 | Messaging-channel config + connection test | Configure Telegram/Discord/Slack/… from the phone and test each | DASH (`GET /api/messaging/platforms`, `PUT .../{id}`, `POST .../{id}/test`) | web-dashboard.md:524-526 | M | Low |
| O6 | Diagnostics — doctor / security-audit / backup / import | Backgrounded ops with a tailable status endpoint | DASH (`POST /api/ops/*`, `GET /api/actions/{name}/status`) | web-dashboard.md:~543 | S | Low |
| O7 | Credential pool + secret sources | Rotating API keys; Bitwarden / 1Password backed secrets | DASH (`/api/credentials/pool`) · PLUG (`ctx.register_secret_source`) | web-dashboard.md:~536; developer-guide/secret-source-plugin.md | M | Low |
| O8 | Gateway hooks firing at all | `agent:start` / `agent:end` / `session:*` / `command:*` automation — **currently impossible on our lane** | TP | C§4.1 — `api_server.py` contains the substring `hooks` **zero times** | S *(free with TP)* | Med |
| O9 | Behaviour-changing plugin hooks | `pre_gateway_dispatch` (skip/rewrite/allow before auth), `transform_llm_output`, `transform_tool_result`, `pre_tool_call` veto, `pre_llm_call` context injection | PLUG (`ctx.register_hook`) | features/hooks.md:391-409; plugins/index.md:606-662. Fire in **both** CLI and gateway; a crashing callback is logged and skipped | M | Med |

### 1.15 Plugin registration surfaces available to us (the full menu of "what we can be")

Code-verified against `hermes_cli/plugins.py` (`def register_*` on `PluginContext`) and cross-checked
against the docs. **18 Python surfaces**, plus four non-`ctx` mechanisms.

| Surface | What we would use it for | Doc |
|---|---|---|
| `register_platform` | **The spine.** Talaria as a real gateway platform | developer-guide/adding-platform-adapters.md:119 (20-row "handled automatically" table at :176) |
| `register_tool` | Phone sensors, HealthKit, location, contacts, calendar as agent tools | plugins/index.md:264 |
| `register_command` | `/talaria …` in every session, in autocomplete and `/help` | plugins/index.md:794 |
| `register_cli_command` | `hermes talaria …` | plugins/index.md:759 |
| `register_hook` | Behaviour hooks (O9) and the outbound-webhook family (P1) | plugins/index.md:270 |
| `register_skill` | Phone-shaped procedural knowledge shipped with the plugin | plugins/index.md:416 |
| `register_transcription_provider` | On-device STT (SFSpeechRecognizer) as a Hermes STT provider | features/tts.md:705 |
| `register_tts_provider` | On-device TTS (AVSpeechSynthesizer) as a Hermes TTS provider | features/tts.md:426 |
| `register_secret_source` | iOS Keychain as a Hermes secret backend | secret-source-plugin.md:124 |
| `register_memory_provider` | (single-select via `memory.provider`) | memory-provider-plugin.md:139 |
| `register_context_engine` | (single-select via `context.engine`) | context-engine-plugin.md:202 |
| `register_image_gen_provider` / `register_video_gen_provider` / `register_web_search_provider` / `register_browser_provider` | provider slots we are unlikely to want | respective `*-plugin.md` |
| `register_dashboard_auth_provider` | if we ever host our own auth | web-dashboard.md:961 |
| `register_slack_action_handler` | n/a | plugins/index.md:899 |
| `register_middleware`, `register_auxiliary_task` | present in code; not documented in the plugin guide | `hermes_cli/plugins.py:1069`, `:1199` |
| `ctx.dispatch_tool(name, args)` | **the stable door** to call any other tool with approvals/redaction/budget wired up | plugins/index.md:279, :299 |
| `ctx.llm.complete(...)` | plugin-side LLM calls that follow the user's current provider | developer-guide/plugin-llm-access.md:35 |
| *(not `ctx`)* `providers.register_provider(ProviderProfile)` | a custom inference provider | model-provider-plugin.md |
| *(not `ctx`)* Desktop plugin SDK — TS/ESM at `$HERMES_HOME/desktop-plugins/<id>/plugin.js` | **the "desktop face"** — contribution areas: `PANES_AREA`, `ROUTES_AREA`, `SIDEBAR_NAV_AREA`, `STATUSBAR_AREAS`, `TITLEBAR_AREAS`, `PALETTE_AREA`, `KEYBINDS_AREA`, `THEMES_AREA`, `COMPOSER_AREAS`, plus `ctx.rest` / `ctx.socket` at `/api/plugins/<id>` | developer-guide/desktop-plugin-sdk.md:199-357 |

⚠ Three traps worth carrying: (a) `ctx.inject_message` is **CLI-only** — it returns `False` in the
gateway; (b) `ctx._cli_ref` is `None` in the gateway, in `hermes chat -q`, and in kanban workers, so
anything reaching through it silently no-ops exactly where a phone plugin lives; (c)
`developer-guide/extending-the-cli.md` is **not** about `register_cli_command` — it is a
subclass-`HermesCLI` wrapper-binary pattern, unreachable from a plugin.

⚠ There are **three unrelated plugin systems** (agent plugins, desktop-app plugins, dashboard
plugins). "The three do not share code, APIs, or delivery. Only the backend `plugin_api.py`
namespace (`/api/plugins/<id>`) is shared between the desktop and dashboard SDKs"
(desktop-plugin-sdk.md:23-33). A Talaria "desktop face" must pick one — and its **backend half**
(REST + WebSocket at `/api/plugins/talaria`) is the part a native iOS client can actually reuse.

### 1.16 Unverified leads — do NOT build against these without a probe

- **`/api/files/*` on the dashboard** (F8) is code-verified in report D but appears **nowhere in the
  published docs**. It is the cleanest #21 Tier-2 answer and also the least contractually stable
  thing in this menu.
- **Hermes Relay** (`messaging/relay.md`) is a connector system where the gateway dials *out* over
  one authenticated WebSocket to a service that fronts platforms — outbound-only networking,
  buffered delivery with wake-poke, native interactive prompts, capability negotiation at handshake.
  It is a genuine third architectural option for Talaria. It is also marked **"Experimental — the
  wire contract, auth scheme, and configuration may change without a deprecation cycle,"** is shaped
  for multi-tenant hosting, and its formal contract lives in a repo file
  (`docs/relay-connector-contract.md`) I did not read. **Lead, not a plan.**
- **`tui_gateway` has no protocol version** (D§1.5). A breaking change arrives as a silently
  different payload, and nothing in the repo pins the method or event catalog.
- **`/agents` kill/pause on gateway platforms** — documented for the TUI overlay only.
- **MCP CRUD over JSON-RPC** — only `reload.mcp` is documented; use the dashboard REST family.
- **`pre_api_request` hook** — named once in `built-in-plugins.md:176` but **absent from the hooks
  reference table**. Check source before building on it.
- **`/v1/runs` and content-part input** — `POST /v1/runs` bypasses multimodal normalization entirely
  (C§23), so image input there is unverified.
- **`send_message` is not agent-callable on either lane** (C§2.3) — it is easy to over-claim from
  the existence of `tools/send_message_tool.py`. The agent cannot decide to message you unprompted;
  what the platform lane buys is that **cron and watchers** can.

### 1.17 Negative findings — things that do NOT exist, so don't plan around them

Recorded because each is a plausible assumption that a docs sweep killed:

- **There is no "canvas" feature and no `canvas` tool.** The only hits in the entire docs tree are
  Canvas **LMS** (a school-courses skill) and the pet sprite's HTML canvas. No whiteboard, no
  drawing surface, no shared canvas anywhere in Hermes.
- **There is no "HermesHub."** Zero hits across the docs tree. The **Skills Hub** is real but is a
  *client-side aggregator* over 8 remote sources — skills.md:587: "It is not a single centralized
  hub — it is a web discovery convention." Publishing needs no registry, just a GitHub **tap**.
- **`open_preview` / `read_preview` are desktop-app-only** (tools-reference.md:176-177). No server
  plane exposes a preview surface to any other client. §2.1 is therefore genuinely new surface, not
  a port.
- **Kanban has no documented desktop pane** — it exists as a *dashboard* tab plugin and via
  `/kanban` on messaging platforms. `features/kanban.md` never mentions the desktop app.
- **"Agents" and "Command Center"** get exactly one line in the desktop docs (desktop.md:154) with
  no panes, controls, or mechanism described. Do not plan parity against an undocumented surface.
- **The desktop Artifacts index has no documented mechanism** — no RPC, no REST route, no table
  name. Our SSE-reconstruction approach (§2.1) is not a reimplementation of a known design; it is
  our own.
- **Hermes skins have no GUI format** — they are ANSI colours, ASCII banners, and spinner verbs for
  a terminal. Talaria's theme system has no upstream counterpart to match or inherit.
- **ACP is not a desktop surface** — `hermes acp` is stdio JSON-RPC for IDEs (VS Code / Zed /
  JetBrains / Buzz). Security note if it ever matters: Buzz's bridge auto-answers Hermes permission
  requests with `allow_once`, so `approvals.mode: manual` does not protect that path
  (features/acp.md:262-270).
- **`context_references` (`@file:`, `@diff`, `@url:`) are CLI-only** — "In messaging platforms…
  the `@` syntax is **not** expanded by the gateway." A phone client must expand them itself.

### 1.18 Design principles worth borrowing verbatim

`apps/desktop/AGENTS.md` is explicitly "a judgment guide, not an inventory," and three of its rules
transfer directly to a phone client:

- **State by authority** — Electron owns process/fs/git, React owns view state, the agent owns
  conversation state. Talaria's equivalent: never cache what the gateway is authoritative for.
- **"Expensive, stateful surfaces (terminals, live tools) stay alive when hidden. Visibility is not
  lifecycle."** This is the exact opposite of the default iOS instinct to tear down on
  `viewDidDisappear`, and it matters for a preview pane or a live tool feed.
- **"Never navigate, move focus, or open a surface because something *happened* in the background.
  Offer; don't hijack."** A push arriving mid-conversation should badge, not yank.

---

## 2. BEYOND PARITY

Features no Hermes surface ships today, that the plugin architecture (or the phone) makes possible.
Each names the mechanism. Ordered roughly by conviction.

### 2.1 Live artifact preview panes — the owner's example, and the phone can beat the desktop

**What upstream has:** v0.20.0 shipped "Artifacts now render with sandboxed live preview" in the
**desktop app**, plus an **Artifacts gallery** that "collects what your sessions generate — images,
files, and links — into one searchable, browsable gallery… every artifact shows which session
produced it with a jump back to that chat" (desktop.md:91-93). The `open_preview` / `read_preview`
tools that drive that pane are **hard-gated to the desktop app** (tools-reference.md:176-177) —
there is no server plane that offers a preview surface to anyone else.

**Mechanism that makes it feasible for Talaria today, with zero server change:** the SSE stream
already surfaces every file the agent writes as
`tool.started {tool_name:"write_file", args:{path, content}, preview: path}` — so **text artifacts
can be reconstructed client-side from `args.content`** (CLAUDE.md #21 Tier 1, verified). That means
Talaria can render an HTML page, a Markdown report, an SVG, a mermaid diagram, or a code file **the
instant the agent writes it — mid-turn, before the answer even finishes** — in a `WKWebView` or a
native renderer, with no file transport, no download endpoint, and no adapter.

**Where it beats the desktop:**

- **Live, mid-turn, no round-trip.** Desktop's pane loads a *path*; Talaria renders the *bytes it
  already received*. There is nothing to fetch and nothing to be offline for.
- **A per-artifact revision chain.** Successive `write_file` / `patch` tool events on the same path
  within a session give a free version history and diff view. Desktop's Artifacts view has no
  per-artifact history.
- **Formats that can never otherwise reach a phone.** `.excalidraw` diagrams,
  `DESIGN.md` token exports (`tokens.json`, `theme.css`), and mermaid are **not** in deliverable
  mode's supported-extension table, so they will *never* arrive as attachments on any platform lane.
  Client-side reconstruction is the only path that exists for them. (Verified: the extension table
  in deliverable-mode.md covers images/video/audio/documents/data/geospatial/presentations/
  archives/`.html`; `.excalidraw`, `.theme.json`, `.css` are absent.)
- **Quick Look + Share Sheet.** Reconstructed bytes written to the app container get
  `QLPreviewController` and `UIActivityViewController` for free — a superset of desktop's
  download / open-in-browser / copy.

**Then layer the real-file path on top:** once TP lands, `.html`, `.pdf`, `.xlsx`, `.zip` arrive as
genuine attachments via deliverable mode (F3/F4) — the agent only has to *mention the absolute
path*. And if the `:9119` process ever runs, `/api/files/download` serves anything at all (F8).

### 2.2 Approvals from the Lock Screen

**Mechanism:** `approval.request` already exists as a structured event with `{command, description,
choices, allow_permanent, smart_denied}` on both `/v1/runs/{id}/events` (C§5.1) and the WebSocket
(D§4.3), and both accept a `{once, session, always, deny}` response. Bridge it to APNs via the
outbound-webhook doorbell (P1) and register iOS **actionable notification categories** whose four
buttons map onto those four choices. **No Hermes client — CLI, TUI, desktop, or any messaging
adapter — can approve a dangerous command without opening the app.** A phone can.

### 2.3 Live Activity / Dynamic Island agent ticker

**Mechanism:** ActivityKit fed by the SSE taxonomy we already parse (`tool.started`,
`tool.progress`, `assistant.delta`, `run.completed` with token usage) or WS `status.update`. The
gateway even ships a curated status-phrase catalog that "never interpolates raw tool args or
reasoning text" (A§8.1, `gateway/status_phrases.py`) — purpose-built for exactly this kind of
low-trust surface. Nothing upstream has a persistent glanceable agent-activity indicator; Talaria
already has an island concept in-app.

### 2.4 Phone sensors as first-class Hermes tools

**Mechanism:** `ctx.register_tool` (plugins/index.md:264) with handlers that proxy over the
adapter's own channel to the device. Talaria already owns a working sensor path (HealthKit,
CoreMotion, CoreLocation) that today only feeds ingestion. Registering them as *tools* means the
agent can ask — "how did I sleep?", "am I near the office?" — from **any** surface: the desktop, the
TUI, Telegram, a cron job. No Hermes install has device sensors as agent tools. The
`check_fn=lambda: …` gate (plugins/index.md:557) hides them cleanly when no device is paired.

### 2.5 An offline outbox with durable replay in both directions

**Mechanism:** server→phone durability comes free from the delivery ledger the moment TP lands
(P5 — record → attempting → delivered, with post-crash sweep and redelivery). The **phone→server**
half is ours to build: queue turns locally and replay them through
`POST /api/platforms/talaria/events`, the shared webhook ingress that "needs no new port" and is
authenticated by the adapter's own verifier (C§18). **No Hermes client survives being offline** —
the TUI treats a dropped socket as gateway death with no reconnect logic at all
(D§1.6, `gatewayClient.ts:497-508`).

### 2.6 On-device wake word driving the host agent

**Mechanism:** upstream already designed for this. `wake_word.capture: client` has the *client* open
its own mic, resample to 16 kHz mono int16, and stream frames via `wake.feed`; the backend runs
openWakeWord and emits `wake.detected` (features/wake-word.md:40-75). It is off by default and, as
far as the docs show, unused by anything but the desktop app. A phone in a pocket is the obvious
consumer, and the ownership model is already single-mic sticky-first-claim so it won't fight the
desk.

### 2.7 Widgets, Shortcuts, and Siri as agent entry points

**Mechanism:** App Intents + the widget targets Talaria already ships, backed by
`POST /api/sessions/{id}/chat` (one synchronous turn) and `/api/jobs` CRUD. Desktop's closest
analogue is **Quick Entry** — a global-hotkey composer (desktop.md:122-125). A Shortcuts action that
can be chained into an automation, or a Siri phrase, is strictly beyond that, and the Sessions API
supports it today with no new surface.

### 2.8 A `hermes talaria` CLI and a `/talaria` slash command — the reverse channel

**Mechanism:** `ctx.register_cli_command` and `ctx.register_command`. Registered slash commands
"appear in autocomplete, `/help` output, and the Telegram bot menu" (plugins/index.md:792). This
inverts the usual direction: the *desk* gets a way to poke the *phone* —
`hermes talaria push "leaving in 5"`, `/talaria devices`, `/talaria locate`. Nothing upstream has a
phone as an addressable target.

### 2.9 A native kanban board with live push

**Mechanism:** `/api/plugins/kanban/*` REST plus `WS /events?since=<event_id>` — "Live stream of
`task_events` rows" (kanban.md:621) — combined with the auto-subscription that already fires when a
task is created from a gateway chat (kanban.md:839). The dashboard's board is a drag-and-drop web
page; a native board that *pushes* on `completed`/`blocked`/`crashed` and lets you unblock a worker
from the Lock Screen is a genuinely different product.

### 2.10 Artifact-aware share targets and a per-session deliverables inbox

**Mechanism:** F1's reconstruction index plus F3's real attachments, surfaced as a per-session
"deliverables" tray with Quick Look, share sheet, and "save to Files". Desktop indexes artifacts
globally; the phone-shaped version is per-conversation and export-first, because that is what you do
with a chart on a phone — you send it to someone.

---

## 3. DEPENDENCY MAP

### Transport milestones

| ID | Milestone | What it is | Cost |
|---|---|---|---|
| **M0** | **Today** | Sessions API on `:8642` + our relay/APNs + the app | none |
| **M1** | **The 2A spine** *(building now)* | `ctx.register_platform` + the six abstract methods (`connect`, `disconnect`, `send`, `send_typing`, `send_image`, `get_chat_info` — A§10) + webhook ingress at `POST /api/platforms/talaria/events`. **No new port** | a plugin, adapter-owned auth |
| **M1b** | **Adapter enrichment** | `send_voice` / `send_document` / `send_video`, `edit_message`, `send_clarify`, `send_exec_approval`, `cron_deliver_env_var`, `platform_hint`, `splits_long_messages` | incremental on M1 |
| **M2** | **Runs migration** | Route approval-bearing and long turns through `POST /v1/runs` + `/events` + `/stop` + `/approval` | zero infra; a second client path |
| **M3** | **`tui_gateway` adoption** | `hermes serve` on `:9119` + an auth provider + our own reconnect ladder. **Auth is cheaper than report D found** — see below | **a second agent runtime**, a recovery-layer rewrite (D§6.3) |
| **M4** | **Dashboard-surface automation** | The `/api/*` REST family — same process and auth as M3 | free once M3 exists |
| **M5** | **Outbound webhooks** | `hooks.outbound` in `config.yaml` + an HTTPS receiver that can mint APNs | **independent of M1–M4** — config only |

### Which milestone each menu item needs

| Milestone | Unlocks |
|---|---|
| **M0 (today, no new transport)** | C1 · G1 · G2 · G4 · G5 · G7(partial) · K1 · N1 · N3 · O1 · S1 · S8 · I1 · M1(header half) · **X1** · **F1 (artifact preview panes)** · F2(index) · F10 · C12–C14 · G6 · 2.1 · 2.7 |
| **M1 (spine)** | P2 · P5 · P6 · P7 · P8 · C6 · C8 · C9 · C10 · C11 · I4 · I5 · O8 · M4 · X6 · X8 · X9 · 2.5(server half) |
| **M1b (enrichment)** | **P3** · **P4** · **F3** · **F4** · F5 · F6 · F7 · F9 · **I2** · **I3** · **V1** · V5 · **H3** · H4 · H5 · H7 · H8 · **K2** · J1 · J4 · N2 · N5 · S7 · X2 · X7 · C2/C3/C5(via `busy_input_mode`) · C7 |
| **M2 (runs)** | **H1** · **H2** · C4(stop) · J2 |
| **M3 (tui_gateway)** | **C2 · C3 · C5** *(the richest steering surface — four mechanisms, D§4.2)* · S2 · S3 · G3 · G8 · H6 · I6 · V3 · V4 · 2.6 |
| **M4 (dashboard REST)** | **F8** · K3 · K4 · K5 · M2 · M6 · O2 · O3 · O4 · O5 · O6 · O7 · S5 · S6 · G7 · J3 · J5 · 2.9 |
| **M5 (outbound webhooks)** | **P1** · **X10** · 2.2 · 2.3(push half) |
| **PLUG (any milestone; rides whatever process runs the agent)** | K6 · K7 · K8 · K9 · O9 · J6 · 2.4 · 2.8 |

### Hard prerequisites and ordering hazards

1. **H4 gates H1 on the platform lane.** Without the busy-guard command bypass, `/approve`
   **deadlocks** — the agent thread is blocked on `Event.wait` while the approval sits in the
   pending queue (A§5.2). If approvals ship on TP, H4 ships in the same wave or not at all.
2. **C8 is a guard rail, not a feature.** The moment we register an adapter without
   `splits_long_messages = True`, the gateway's 4000-char cap starts clipping replies that arrive
   intact today (C§21.4). This is a regression waiting to happen on the first day of M1.
3. **Session identity is the load-bearing unknown.** A `build_session_key`-shaped
   `X-Hermes-Session-Key` must land in the same memory scope and transcript a platform adapter would
   produce, or M1 gives us two conversations where the user sees one (C§21, C§23 — flagged there as
   the highest-value thing to verify). **Testable today, with no adapter written.**
4. **M3 is the only plane that carries true steering** — `_run_agent` builds a fresh agent per
   request, so `/v1/runs` has no live object to inject into and no client work changes that
   (D§6.2). TP reaches `busy_input_mode` (`gateway/run.py:8223`) but correlation back to a phone
   turn is ours to build. If steering is the top priority, M3's cost is the price of the feature.
5. **M3's auth cost is materially lower than report D concluded — a native-app OAuth flow exists.**
   D§3.4 planned for password login → cookie → a 30 s single-use ticket re-minted on every
   reconnect. There is a better path: **RFC 8252 native sign-in** — system browser + PKCE +
   loopback redirect, giving the app a short-lived **access token** and a **refresh token** held in
   the OS keychain, with `Authorization: Bearer` used for REST *and* for minting WS tickets
   (guides/desktop-native-signin.md). Capability detection is explicit: `GET /api/status` reports
   `auth_flows`; `["cookie","native_pkce"]` → native flow, `["cookie"]` or absent → fall back.
   Endpoints: `GET /auth/native/authorize`, `POST /auth/native/token`, `POST /auth/native/refresh`.
   For a native iOS client this is `ASWebAuthenticationSession` + Keychain — a solved shape, not a
   cookie-jar hack. **Verify `auth_flows` on our own build before planning on it.**
6. **M3 relocates the execution boundary, and that is a design decision, not a detail.** "In remote
   mode the gateway host is the execution boundary: agent tools, terminal commands, and file
   operations run against the remote Hermes host, not the computer displaying the Desktop UI"
   (`apps/desktop/README.md:146-148`). Same for us: the phone displays, OJAMD executes.
7. **M3 costs a recovery-layer rewrite, not a port.** Our hardened `/chat/stream` SSE machinery —
   retry, backoff, resume, the `URLProtocol` stub-buffering workarounds — does not transfer to a
   JSON-RPC socket with a 20 s idle-orphan reaper and an `inflight` *snapshot* instead of an event
   log (D§6.3). Also: a gated (non-loopback) bind turns on 20 s uvicorn ws pings that the upstream
   code itself warns a GIL-heavy turn can outrun.
8. **M5 is orthogonal and cheap.** It needs no adapter, no second process, and no Hermes code — and
   it is the only push in this document that works on the lane we already ship. It does need an
   HTTPS receiver, which is the relay decision flagged under P1.
9. **X1 should not wait for anything.** It is a config-file edit on the host that stops the model
   being told to avoid markdown on every single turn. A§9 and C§12.1 independently identify it as
   the cheapest win available, and the pivot would otherwise get credit for it.

---

## 4. TOP 10 — ordered by value-per-effort for a phone user

1. **Own the platform hint (X1)** — one config block on the host stops Hermes telling the model
   "assume plain text, no markdown" on every turn, and turns on the `MEDIA:` contract; zero code,
   zero risk, available before the spine lands.
2. **Artifact preview panes (F1)** — reconstruct HTML/Markdown/SVG/code from the `write_file` tool
   events already in our SSE stream and render them live, mid-turn; the owner's headline ask,
   buildable today with no server change, and it beats the desktop on liveness, versioning, and
   formats that can never arrive as attachments.
3. **Per-turn model / provider / reasoning-effort (G1)** — request fields already accepted on
   `/chat` and `/chat/stream` give a working model picker and a per-question effort dial, sidestepping
   the `/model` session pin that hangs 37 s+ (OPEN_ITEMS #9).
4. **Outbound-webhook doorbell (P1)** — signed lifecycle POSTs fire on the lane we already ship, so
   push works before the adapter exists; it needs an HTTPS receiver, which is a decision for Owen,
   not a build.
5. **Approvals and MCP elicitation via `/v1/runs` (H1 + H2)** — today a dangerous command on
   `/chat/stream` asks nobody and every MCP elicitation is silently auto-declined; the runs plane
   already has full approval parity, so this is a client-side route change, not new surface.
6. **The platform adapter spine (M1) with `splits_long_messages` (C8)** — one plugin and six methods
   moves us from a code path that deliberately opts out of the runtime onto the one the runtime was
   built for, and everything in §1.2 through §1.6 becomes incremental after it.
7. **Native file delivery + deliverable mode (F3 + F4)** — ~60 extensions arrive as real
   attachments when the agent merely mentions a path, replacing images-only-≤5 MB-base64; the
   largest single capability delta in the whole gap analysis.
8. **Cron delivery + kanban push to the phone (P3 + P4)** — two entry fields on the platform
   registration turn scheduled briefings and task-completion notices from "runs and delivers
   nowhere" into the marquee phone feature.
9. **Voice notes in with server-side STT (I2), then auto-TTS out (V1)** — push-to-talk is the
   phone's native input mode and the gateway already owns transcription with a local fallback; today
   the API lane returns HTTP 400 and cannot reach STT even indirectly.
10. **Phone sensors as registered Hermes tools (K6 / §2.4)** — `ctx.register_tool` turns the sensor
    path we already own into something the agent can query from *any* surface, and nothing else in
    the Hermes ecosystem has it.

**Honourable mentions, held back only by their milestone cost:** mid-turn steering (C2/C3/C5) is the
single richest capability in the codebase and `tui_gateway` is the only plane that carries it — but
it costs a second agent runtime and a recovery-layer rewrite, which is Owen's call, not a technical
unknown. The dashboard REST family (M4) unlocks 18 menu rows including the clean `#21` Tier-2 answer,
and rides entirely on the same process.
