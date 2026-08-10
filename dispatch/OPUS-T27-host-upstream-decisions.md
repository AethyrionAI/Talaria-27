# OPUS · T27 — the four "we may not own the fix" items: #132 · #187 · #241 · #264

> ## ⚠️ AMENDED 2026-08-09 — SUPERSEDED IN PART BY TWO LATER REPORTS. READ THOSE FIRST.
>
> This brief was written before upstream was actually consulted. Two reports now
> supersede its dispositions:
> `planning/reports/2026-08-09-upstream-recheck.md` (all six items re-read at
> upstream HEAD) and `planning/reports/2026-08-09-upstream-prior-art.md` (what
> other people have already filed).
>
> **What changed:**
> - **#187 — CLOSED** 2026-08-09, and for a *better* reason than this brief had.
>   Prior art surfaced a blocker: `message_count` is NULL for `source=api_server`
>   (**0 of 35 sessions measured**), so even if upstream exposed `min_messages`
>   it would filter out every Talaria session.
> - **#241 — this brief's "park holds" is right, but its mechanism reading is
>   superseded twice.** It was closed as by-design and then **REOPENED the same
>   day as TRACK-UPSTREAM**: upstream files it as a Bug (#79101), a
>   maintainer-reviewed fix is open (**PR #72739**), and four people found it
>   independently. Also a second poison channel nobody here had found
>   (`_last_resolved_model`, #79824). **Watch #72739.**
> - **#264 — confirmed DELIBERATE with published rationale.** Merged PR #65665
>   *is* our bug: retrying re-introduced an fd leak (1,568 retries over 5 days).
>   **Nothing to track for a fix; our ops rule IS the answer** — and it must be
>   widened to the second cause (a weak `API_SERVER_KEY` fails the adapter closed
>   with an identical symptom and a completely different remedy).
> - **#132 — prior art exists but only for the wrong lane.** PR #18597 was our
>   exact fix shape and died of refactor churn; only `/v1/chat/completions` was
>   ever addressed. The Sessions lane is unreported, and HEAD still carries
>   `# Silently skip image_url` at `api_server.py:521`.
> - **#170b — better news than filed.** `model` exists end-to-end in `cron/`;
>   the `:8642` whitelist simply omits it. **An omission, not a missing
>   capability.**
>
> **Unchanged:** no filing is recommended anywhere, and #241 stays parked from a
> submission standpoint — it is filed four times over, so there is nothing to
> submit.


**Tier: OPUS.** Written 2026-08-09 from a HEAD code read of BOTH sides — the app at
`t27-295-expiration-recovery` @ `04af0a7`, and the Mac's Hermes install at
`~/.hermes/hermes-agent` @ `3dcbe9001`. **No code was written. No live install was
modified. Nothing was submitted anywhere.**

**Goal:** let Owen clear four items in one sitting — close what is dead, rule on what
needs a call, and route the two that turn out to have a real client-side lane that
needs no upstream anything.

---

## ⛔ Two guards this brief was written under

1. **#241 is PARKED by Owen and stays parked.** §6 states where it stands, factually.
   There is no submission recommendation anywhere in this document, and the draft at
   `handoffs/241-upstream-report-DRAFT.md` was read, not edited.
2. **Live installs were read-only.** Everything below is a code read, a route-table
   read, a config read, or a listener check. No probe created a session, no service was
   restarted, no file in a live install was touched.

---

## 1. The register

| Item | Still live? (evidence) | Owner | Client-side option | Deletion path (#223/#251) | Disposition |
|---|---|---|---|---|---|
| **#132** image attachments | **AS FILED — NO. MECHANISM — YES, and different.** The 07-17 error string `prepare image failed` has **zero hits** in the source at head. Images now pass through verbatim (`api_server.py:550-665`). But `agent/image_routing.py`'s vision routing is called **only** from `gateway/run.py:16260` — the platform-adapter lane. The phone's Sessions API lane never calls it, so a text-only host model gets raw `image_url` parts with **no fallback and no error**. | **Upstream** for routing parity · **config** for the immediate cure · **US** for the honesty | **Yes, two, both non-hack.** The app already discloses blindness on the LOCAL plane (`LocalChatBackend.swift:1622`) and has no host-plane analogue. And a caption-less image turn sends **no text part at all**. | **No relief.** Chat stays on the Sessions API under #251; the runs transport reuses the identical part encoder. | **ROUTE A LANE** (honesty floor) **+ OWEN'S CALL** (the host-config question the item was filed to ask) |
| **#187** `min_messages` | **YES — code-verified, no probe needed.** `_handle_list_sessions` (`api_server.py:3334-3367`) reads exactly four query params: `limit`, `offset`, `source`, `include_children`. `min_messages` is not in the handler. Neither is `order`. | **Upstream** (one kwarg — the DB layer already has `min_message_count`, `hermes_state.py:6509`), but Owen already ruled *keep, annotated* | Already shipped (the drawer filter). Two small honest levers remain — raise `limit` (honored, max 200), and surface the count divergence, which nothing does today. | No relief, and no harm — the session list stays on the gateway. | **CLOSE** (see §7 Q3 — it is his prior ruling to reverse) |
| **#241** self-name model id | **YES — and I found the two-line mechanism the entry did not have.** `api_server.py:3397` + `2766`. Reachable from Talaria's own `createBareSession`. Not firing on the Mac today only because the config moved to a tolerant provider. | **Upstream** for the defect · **US** for the immunity | **Yes — one field.** `POST /api/sessions {"model": …}` is a documented, honored precedence tier. The app posts `EmptyBody()`. | No relief — #223 Lane 5 keeps this exact plumbing. | **PARK HOLDS** (upstream) · **ROUTE A LANE** (client-side immunity, needs no upstream) |
| **#264** bind race | **YES — and it is now DELIBERATE upstream.** `api_server.py:7260-7280`: `EADDRINUSE` → `_set_fatal_error(retryable=False)`, with a comment naming the infinite-retry bug that choice fixed. | **Upstream** (but the entry's proposed ask is now wrong) · **US** for the ops rule and the app's one-truth | **Yes.** The tracker's own app-side ask is unimplemented — zero `#264` references in Swift. The correct vocabulary already exists elsewhere in the app. | **#251/#283 make it WORSE.** The plugin webhook rides the same listener; post-migration, chat + approvals + steering + phone-query die together behind a healthy PID. | **OPS RULE (upgrade it)** **+ ROUTE A LANE** (one banner, one truth) |

---

## 2. Verified state

### 2.1 The ground everything else stands on

**VERIFIED**

- **Mac Hermes install head** — `~/.hermes/hermes-agent` @ `3dcbe9001f30de749971911041c02916437b5bff`,
  *Sat Aug 8 20:47:56 2026*, subject `fix(update): refresh the installer's bootstrap-cache
  scripts on every update`.
- **The running Mac gateway PREDATES head.** `lsof -nP -iTCP:8642 -sTCP:LISTEN` → PID 19532,
  `ps` start time **Fri Aug 7 07:20:41 2026**, `…/venv/bin/python -m hermes_cli.main gateway run --replace`.
  Head landed a day and a half later. **Every claim in this brief is a HEAD CODE claim, not
  a live-process claim** — the listener currently serving the phone is running older imports.
- **The version string is frozen and proves nothing.** `pyproject.toml:5` → `version = "0.20.0"`
  at head. CLAUDE.md's "verify by process start time, not version string" holds exactly.
- **The `:8642` route table at head is UNCHANGED from the 0.19.1 table in CLAUDE.md.** Dumped
  from `_http_route_table()` (`api_server.py:2041`) — 37 routes, and **`GET /api/model/options`
  is still the only `/api/model/*` route**. No `/api/files`, no `/api/fs`, no `/api/config`.
  The RUNS family is present and matches the documented shape.
- **The vision capability field STILL does not exist.** `hermes_cli/inventory.py:404-439`
  (`_apply_capabilities`) emits `{fast, reasoning}` per model and nothing else — it calls
  `get_model_capabilities(slug, model)`, reads `supports_reasoning` off the result, and drops
  `supports_vision` from the same object. #173's "one field away" finding is **unchanged at
  head**, one year of commits later.
- **Mac host config** (`~/.hermes/config.yaml`, read-only): `model.provider: kimi-coding`,
  `model.default: kimi-k3`, `agent.image_input_mode: auto`, `auxiliary.vision.provider: auto`.

**ASSUMED / NOT CHECKED**

- **OJAMD.** Nothing in this brief was checked against the Windows production host. OJAMD's
  install may be at a different commit and is certainly at a different config. Every "still
  live" verdict is a verdict about the code, which both hosts share; every *config-dependent*
  consequence (does a given provider tolerate an unknown model id?) is host-specific.
- I did not run any chat probe. Creating a session is a write, and none of these verdicts
  needed one.

### 2.2 #132

**VERIFIED (host side, head)**

- `_normalize_multimodal_content` (`api_server.py:550-665`) validates and **passes image parts
  through verbatim** as `{"type":"image_url","image_url":{"url":…}}`, accepting `data:image/…`
  and `http(s)` URLs, rejecting file/document parts and unknown part types with a 400.
  Its docstring: the output "is the native OpenAI Chat Completions vision format, which the
  agent pipeline accepts verbatim … or converts".
- The session chat path uses it: `_session_chat_user_message` (`api_server.py:797-808`) →
  `_handle_session_chat` → `_run_agent` → `agent.run_conversation(user_message=…)`
  (`api_server.py:6196`).
- **`prepare image failed` / `failed to decode image` — ZERO hits** across `gateway/`, `agent/`,
  `hermes_cli/`, `providers/`. The 07-17 probe's 400 came from a code path that no longer exists.
- **The routing gap, which is the live mechanism.** `agent/image_routing.py` decides
  `native` (attach pixels) vs `text` (run `vision_analyze` up front and prepend a description)
  per turn, in `auto` mode, off `supports_vision`. Its **only** caller is
  `gateway/run.py:16260`, inside the `event.media_urls` block — the **platform-adapter** lane
  (Discord/Telegram/etc.). The `native_image_paths` plumbing it feeds
  (`gateway/session_state.py:142`, `gateway/run.py:16601`) is likewise gateway-only. The
  Sessions API lane the phone speaks has **no equivalent**: the parts go to the provider adapter
  as-is, and a text-only main model has no `vision_analyze` fallback and produces no error the
  app can see. **This is the "two of everything" pattern again, in a third place.**

**VERIFIED (app side, `04af0a7`)**

- Encoding is correct and identical on both transports —
  `AttachmentInlining.swift:86-92` builds `data:<mime>;base64,<…>`;
  `SessionsHermesClient.swift:1995-2005` encodes the `image_url` part;
  `SessionsHermesClient+RunsTransport.swift:89-94` reuses the same encoder inside a
  wrapped user message. **The app's exoneration still holds at head.**
- **No vision check, no warning, no post-reply verification — anywhere on the host plane.**
  `ModelOptionsResponse` (`SessionsHermesClient.swift:2034`) decodes only
  `providers[].models: [String]` and `authenticated` — there is not even a field to check.
  `AttachmentPickerSheet.swift` shows four buttons and no capability text. The only composer
  warning is the PDF one (`ChatInputBar.swift:400-418`).
- **The app already does the honest thing on the OTHER plane.** `LocalChatBackend.swift:1622`
  injects, in band: *"[Attached image … — the on-device model cannot view images. If the image
  matters to the request, say honestly that you can't see it.]"* The host plane has no analogue.
> **✅ SUPERSEDED 2026-08-10 for the bullet immediately below — the floor SHIPPED.**
> `#132`'s honesty floor landed (`f63c6ee`, branch `t27-132-image-floor`) and **#132 is
> CLOSED** (now in `OPEN_ITEMS-ARCHIVE.md`). A caption-less image turn no longer ships a
> lone `image_url`: `AttachmentInlining.assemble` prepends
> `[Talaria: the user attached N image(s) with no caption — …]` on BOTH host planes,
> wire-only. The `ChatStore` mechanics described below are still accurate — the display
> placeholder is display-only and the wire still gets the trimmed empty string; the floor
> is injected below that, at encode time. The `LocalChatBackend` "other plane" bullet
> above is also no longer a contrast: the host plane now has its analogue.

- **A caption-less image turn sends NO text part at all.** `ChatStore.swift:579-581` synthesizes
  `[N attachment(s)]` for **display only**; the wire call at `ChatStore.swift:643` passes the
  *trimmed* (empty) content, and `AttachmentInlining` only prepends a text part when the message
  is non-empty. So the turn ships a lone `image_url` part with zero instruction — which is
  precisely why the host has to mint `[attachment]` / `[screenshot]` itself (#132's own second
  finding, 2026-07-23).

**ASSUMED**

- Whether image parts survive into stored history and therefore into follow-up turns. The code
  reads as supporting it — `hermes_state.py:8082-8085` decodes content and branches on
  `isinstance(content, str)`, implying list content is a live case — but I did not trace
  `append_message`'s serialization. **A follow-up-turn image loss would be a separate defect
  from the one above; do not assume either way.**
- What a text-only provider actually *does* with an `image_url` part (400 vs silent ignore)
  is provider-specific and was not probed.

### 2.3 #187

**VERIFIED**

- `_handle_list_sessions` (`api_server.py:3334-3367`) reads `limit` (default 50, **max 200**),
  `offset`, `source`, `include_children` — **and nothing else.** It then calls
  `db.list_sessions_rich(source=…, limit=…, offset=…, include_children=…,
  order_by_last_active=True, include_pinned=True)`.
- **`min_messages` is not read.** Neither is `order` — the app's `order=recent` is a second
  unhonored param on the same request, harmless only because the handler hardcodes the
  ordering the app wants.
- **The upstream fix is one kwarg.** `SessionDB.list_sessions_rich` already takes
  `min_message_count: int = 0` (`hermes_state.py:6509`). The dashboard app (`:9119`) already
  wires it (`hermes_cli/web_routers/sessions.py:60,105`). The gateway does not.
- `source` **is** honored, and per #187's own census every one of the 116 empty sessions carried
  `source: "acp"`.
- App side: request built at `SessionsHermesClient.swift:869-879`; filter at
  `SessionsDrawer.swift:184-196`; `UserSettings.showEmptySessions` present, default **false**
  (`UserSettings.swift:404, 443, 548`), UI at `SessionsSettingsScreen.swift:135-172`.
- **The divergence is not surfaced.** The drawer header deliberately reads the *filtered* list
  (`SessionsDrawer.swift:113-119`), but Settings → Sessions shows the *unfiltered* count
  (`SessionsSettingsScreen.swift:103`) and the settings grid card the same
  (`SettingsChannels.swift:121-125`). No "N hidden" string exists anywhere.

### 2.4 #241

**VERIFIED — the mechanism, in two lines**

1. **`api_server.py:3397`** — `_handle_create_session`:
   `model = body.get("model") or self._model_name`.
   `self._model_name` is the gateway's **own advertised identity** (`_resolve_model_name`,
   `api_server.py:1644-1666`, fallback `"hermes-agent"`). A session created with no `model`
   in the body persists `hermes-agent` as the session row's model.
2. **`api_server.py:2766`** — `_create_agent`, the unlocked branch:
   `model = resolve_effective_model(None, session_row_model, model)` — the session row's model
   **beats** the config model. On the unlocked chat path `stored_model` →
   `session_model` (`api_server.py:3705-3708`) → `session_row_model` → wire id.

   So an unlocked turn in a model-less session goes out as `model=hermes-agent`. Kimi tolerates
   the unknown name; Nous validates it and 404s. Exactly the incident.

**VERIFIED — and this is the correction that matters: Talaria walks straight into it by default**

- `createBareSession` posts **`EmptyBody()`** — `SessionsHermesClient.swift:1158-1164`. No model.
  Every Talaria-created session row on the host carries `hermes-agent`.
- The lock is **conditional on a user pick**: `ChatTurnBody.make` sets
  `requireModelLock: selection == nil ? nil : true` (`SessionsHermesClient.swift:1952` and
  `:1964`). With no pick — fresh install, default state — no lock is sent, and step 2 above fires.
- **#241's park rests on "the app rides the (working) lock plumbing."** That is true when a model
  is picked and false when one is not. The park's *conclusion* may still be right; its *premise*
  is narrower than written.
- **It fired live on 2026-08-05** — #251's own filing note records *"#241 fired live during this
  discussion (404 self-name, 0 tokens)"* on the Mac, then a Nous-only host. The Mac's config has
  since moved to `kimi-coding` / `kimi-k3` (`config.yaml` mtime Aug 7 07:18). **Config dodged it.
  Nothing fixed it.**
- **A second, quieter consequence, live right now on every default Talaria session:** because
  `hermes-agent` is not a catalogued model, context-length detection fails and Hermes falls back
  to a hard default with a one-time warning — `agent/model_metadata.py:371-384`, *"Could not
  determine context length for model %r … falling back to %s tokens."* Upstream's own comment
  says the guard exists so small-context models "don't silently get 256K and cause hard-to-debug
  API failures." **Talaria's default sessions are running on a guessed context window.** That is
  adjacent to #229's pressure work.

**ASSUMED**

- Whether defect 2 (HTTP 200 on a failed run) still behaves as the 0.20.0 re-test found. That
  finding came from live probes; I did not re-probe, and the park does not depend on it.

### 2.5 #264

**VERIFIED**

- The mechanism is at `api_server.py:7252-7285` and it is **intentional**:
  `web.TCPSite(..., reuse_address=False if sys.platform == "darwin" else None)` →
  `await self._site.start()` → on `OSError` with `errno.EADDRINUSE` →
  `self._set_fatal_error("api_server_port_in_use", …, retryable=False)` → `return False`.
  The gateway keeps running without the platform.
- **The upstream rationale is in the comment, and it kills #264's proposed ask.** Verbatim
  intent: a bare `return False` made the reconnect watcher treat this as retryable and *"loop
  forever at the backoff cap (observed: 1568+ retries over 5 days …), filling errors.log and
  leaking the adapter's ResponseStore fds each retry."* **#264's candidate ask — "retry the bind
  for ~15s before giving up" — would re-introduce the bug upstream deliberately fixed.** The
  entry's *other* candidate (exit nonzero so the supervisor respawns instead of running headless)
  does not conflict and is the surviving shape of the observation.
- **Two recovery/detection routes the entry does not have:**
  - `/platform resume api_server` — named in the fatal-error message itself
    (`api_server.py:7276`) and implemented at `gateway/slash_commands.py:1438-1521` /
    `gateway/run.py:8090-8135`. **Caveat that matters:** it is a gateway *slash command*, so it
    must be issued through a platform that is still connected. With api_server dead, that means
    Discord or the TUI — on the Mac a second `kill` (launchd respawn) is still the practical
    move, and **OJAMD has no launchd at all**, which is where this command earns its keep.
  - **`~/.hermes/gateway_state.json` carries per-platform truth on disk**, needing no listener:
    today it reads `"api_server":{"state":"connected","error_code":null,…}` alongside
    `bluebubbles` and `talaria`. **A one-line read of this file distinguishes "healthy PID,
    headless gateway" from "healthy PID, healthy chat" without touching the port.** It is the
    cheapest possible #264 detector and it is not in the runbook.

**VERIFIED (app side) — the tracker's own app-side ask is unimplemented**

- **Zero `#264` references** in any Swift file under `Talaria/` or `TalariaTests/`.
- The gateway probe is honest: `ServerSettingsScreen.probeGateway` (`:634-653`) does
  `GET {gateway}/v1/models` and classifies 2xx→online, 401/403→unauthorized, else offline —
  so the **GATEWAY row would correctly flip OFFLINE**.
- **But the two badges beside it would not.** `PAIRED` is a stored **relay** record read with no
  network at all (`ServerSettingsScreen.swift:252` → `ProfileRelaySession.swift:57-60`), and
  `PLUGIN LINK` is a **Keychain** token read (`ServerSettingsScreen.swift:62-66` →
  `AppContainer.swift:2345-2348`). Both keep saying PAIRED while chat refuses.
- **ABOUT can contradict itself on one screen.** `effectiveConnectionState` — duplicated
  verbatim in `AboutSettingsContent.swift:82-85`, `SettingsChannelsScreen.swift:369-372`,
  `UplinkSettingsScreen.swift:112-115` — falls back to the **relay's** state, so the hero can
  read HEALTHY while the `Hermes API` row directly under it reads UNREACHABLE.
- **The right words already exist in the app.** Uplink → Test Connection classifies
  connection-refused as `REFUSED` / *"Nothing is listening on that port. Check the port number
  and that Hermes is running."* (`UplinkSettingsScreen.swift:38, 51-52`), with a Siri-voice twin
  at `HostReachability.swift:46-47`. That is #264's signature, worded correctly, on the wrong
  screen and wired to nothing.

**ASSUMED**

- That `probeGateway` in fact flips OFFLINE during a real bind failure is inferred from the
  catch-all `return .offline` plus the observed failure shape — not run against a dead listener.

---

## 3. ⚠️ Tracker corrections

Per the close-out rule, these go upstream to the stale claim's own home. **None of them were
applied — this brief writes no tracker edits.**

1. **#173's 2026-07-23 amendment names four `:8642` routes that do not exist.** It states the
   gateway serves `GET /api/model/info` / `/api/model/recommended-default` / `/api/model/auxiliary`
   and `POST /api/model/set`. At head, `_http_route_table()` has **exactly one** `/api/model/*`
   route: `GET /api/model/options`. This is the precise error CLAUDE.md's hard rule exists to
   prevent, still sitting inside an open entry. **The amendment's load-bearing conclusion is
   still correct** — the missing `vision` key is upstream in `_apply_capabilities`, and a fix
   there reaches every consumer — so correct the route list, keep the conclusion.
2. **#132's `prepare image failed: failed to decode image` is no longer current behavior.**
   Zero occurrences in the source at head. The entry should not be read as describing what the
   gateway does today; its *ownership* verdict (Hermes-side) survives, its *mechanism* does not.
3. **#264's candidate upstream ask is now falsified by upstream's own fix.** "Retry the bind for
   ~15s before giving up" would re-introduce the infinite-reconnect/fd-leak bug the non-retryable
   path was written to stop (`api_server.py:7260-7274`). Record it, and keep only the
   exit-nonzero variant.
4. **"~31 commits past" is the shallow-clone depth, not a measured delta.** `~/.hermes/hermes-agent`
   is a **shallow clone** (`.git/shallow` present); `git log --oneline | wc -l` = 31, and all 31
   are dated on or after 2026-08-03. The real distance from the 0.20.0 release is **not knowable
   from this checkout**. Any doc citing "31 commits past 0.20.0" is citing clone depth.
5. **The live Mac listener does not serve head.** PID 19532 started *Fri Aug 7 07:20:41*; head is
   *Sat Aug 8 20:47*. Same hazard CLAUDE.md documents, currently true on the dev box.
6. **#187: `order=recent` is unhonored too.** Same request, same handler, same silence. Worth one
   line in the entry so nobody re-derives it.
7. **#187 minor:** the entry says the drawer filter has "two exemptions"; the code has **three**
   (`isActive`, the row's `isPinned`, and membership in the `pinnedIDs` overlay —
   `SessionsDrawer.swift:184-196`). Separately, the **static** `grouped(...)` defaults
   `showEmptySessions: true` while the model property defaults `false` — a legacy/test asymmetry
   worth knowing before anyone writes a test against the static entry point.

---

## 4. Per-item detail and reasoning

### #132 — the fix moved, the symptom didn't

The item was filed against a gateway that validated an image and then dropped it. That gateway is
gone: at head the parts survive normalization and reach `run_conversation` intact. What replaced it
is a **structural asymmetry** — upstream built a proper answer for non-vision models
(`decide_image_input_mode` → `vision_analyze` → prepend a description) and wired it into the
platform-adapter lane only. The phone's lane gets the raw pixels or nothing, silently, either way.

That reframes ownership cleanly:

- **Upstream** owns routing parity (call `decide_image_input_mode` on the api_server lane too).
- **Config** owns the immediate cure and it is Owen's, not ours: point the host at a vision-capable
  model, or set `auxiliary.vision` to a real backend so the text path has somewhere to go. The
  Mac is on `kimi-coding`/`kimi-k3` with `auxiliary.vision.provider: auto` — i.e. neither.
- **We** own the honesty, and we own it *regardless of how the other two land*, which is what makes
  it worth routing now.

The client-side work is small and it is not workaround-shaped, because we already do the same thing
one plane over. Two pieces:

- **(a) Never send a captionless image.** Attach a short in-band note alongside the image part on
  turns with no typed text — the `LocalChatBackend.swift:1622` pattern, host-plane wording. This
  gives the model an instruction it currently does not get, **and** removes the host's reason to
  mint `[attachment]` / `[screenshot]` on its own, which is the other half of #132's own filing.
- **(b) The never-claim floor from #173.** Say "not known to support images", never a hard block —
  #173 already settled the wording constraint, and #173's own caveat (an uncatalogued model reads
  as no-vision) is exactly why the floor must be a note, not a gate. **Do not** build (b) on a
  capability lookup: `_apply_capabilities` still does not emit `vision`, verified today. Build it
  on what we know locally — that an image was sent and nothing in the reply corresponds — or ship
  (a) alone and wait.

**Deletion path:** no relief. #251 explicitly keeps chat on the Sessions API, and
`SessionsHermesClient+RunsTransport.swift:89-94` reuses the same encoder, so a runs migration
carries the gap forward unchanged.

### #187 — the watch can retire, because a code read replaced the probe

The re-probe this item has been running twice now (0.20.0 on 2026-08-04, and today) has a cheaper
form: the handler's parameter list is four lines long, and `min_messages` is not among them. There
is no plausible release that starts honoring it silently — the param would have to appear in
`_handle_list_sessions` first. So the watch's *purpose* (catch a free server-side win) is now served
by re-reading four lines, and the item has **no work of ours left in it**.

If Owen would rather keep something armed than close it, the honest minimum is a one-line note under
#180: *"gateway ignores `min_messages` and `order`; re-check `_handle_list_sessions`'s param list,
not a probe."*

Two client-side levers exist if he wants them, neither urgent:

- **Raise `limit`.** The handler accepts up to 200 (`_parse_nonnegative_int(..., maximum=200)`); the
  app asks for 50 and then discards ~38% of the page. Raising it recovers shelf depth at the cost of
  payload. Smallest real improvement available.
- **`source=api_server` is honored** and would eliminate 100% of the empties (all 116 were `acp`) —
  but it would also hide 52 *real* non-Talaria sessions (tui 19, desktop 11, acp 20, cron 2). Name
  it as an option, never a default.

The one genuinely #180-shaped residue: Settings shows the **unfiltered** session count while the
drawer shows the **filtered** one, and nothing anywhere says "N hidden". The drawer header already
refuses that lie by design; Settings has not caught up.

### #241 — the park is upstream's half; the client half was never opened

Everything in §2.4 is a code fact, and together it says something the entry does not: **Talaria's
default configuration is the vulnerable configuration.** No pick → no lock → the session row's
`hermes-agent` is the wire model id. The app is protected exactly when the user has been to the
picker.

The immunity is one field, and it is not a workaround: `POST /api/sessions` accepts `model`, and the
gateway documents that value as a first-class precedence tier — *"session-persisted model … Pins this
session's turns … matching the native gateway's session-model semantics"* (`api_server.py:2622-2627`,
`2752-2757`). Sending it is using the API as designed. What we send today is `EmptyBody()`, which is
what invites the self-name in.

Two shapes, both app-only:

- **Send the resolved model on session create.** The app already fetches `/api/model/options`; the
  gateway payload's `model` / `provider` top level names the host's current default. Persisting that
  on the row makes every Talaria session honest and immunizes the no-pick path.
- **Or always send the lock**, defaulting `modelSelection` to the host's current model instead of
  `nil`. Same effect on the wire, wider blast radius in the app, and it changes what "no pick" means.

The first is smaller and localized to `createBareSession`. Either one also fixes the guessed context
window (§2.4), which is the part of this that is costing something *right now* on a host that
tolerates the bad id.

**This lane requires no upstream contact of any kind and does not disturb the park.**

### #264 — the ops rule was the right deliverable, and it can now be a better one

The upstream half got smaller and the ops half got bigger. Upstream deliberately chose non-retryable,
for a documented reason, and #264's proposed ask would undo that — so the entry's upstream framing
needs correcting before it could ever be useful. What survives is narrower: *don't run headless
silently* (exit nonzero, or make the state loud), which is a different request than the one on file.

Meanwhile the ops rule gains two things it did not have:

- **`/platform resume api_server`** as a real recovery verb — with the honest caveat that it needs a
  surviving platform to issue it through, which is why it matters more on OJAMD (no launchd) than on
  the Mac (where a second `kill` respawns cleanly).
- **`~/.hermes/gateway_state.json`** as a **file-based** detector that works with the port dead. This
  is the best find in this item: it turns "check the listener" from a port probe into a
  read of a JSON file that names the failure directly, `error_code` and all.

The app-side lane is small, already specified by #264 itself, and unbuilt. The app's GATEWAY row is
honest; two badges and one hero next to it are not, because they read local state (a stored relay
record, a Keychain token, the relay's connection) and present it as host health. **One banner, one
truth** — and the words for it already exist verbatim in `UplinkSettingsScreen.swift:51-52`. This is
#180's family exactly: the app hiding its own degradation, this time by letting a healthy-looking
neighbour vouch for a dead plane.

**Deletion path:** #251/#283 raise the stakes rather than lowering them. Post-migration, chat,
approvals, steering and the phone-query transport all ride the one `:8642` listener — the very
concentration #264's own update flagged. A fix here appreciates in value; it does not expire.

---

## 5. Does the deletion path change any answer?

| Item | Verdict |
|---|---|
| #132 | **No.** Chat stays on the Sessions API under #251; the runs transport reuses the same encoder. |
| #187 | **No, and no harm either.** The session list is a gateway route and stays one. |
| #241 | **No.** #223 Lane 5's picker rides exactly this model-selection plumbing. |
| #264 | **It gets WORSE.** The plugin webhook rides the same listener; the migration concentrates four failure modes into one. |

**Nothing in this cluster is waste-by-deletion.** The shim retires, the relay shrinks — none of these
four live there.

---

## 6. #241 — where it stands, factually

- **Status: ⏸ PARKED UNSUBMITTED**, Owen's call, 2026-08-04 night, on the reasoning *"not critical to
  us."* Nothing has been submitted. The only upstream-repo contact ever made was read-only duplicate
  searching.
- **The artifacts are intact and were read, not modified:** `handoffs/241-upstream-report-DRAFT.md`
  (5,563 bytes, 65 lines, mtime Aug 4 00:48), plus raw probe responses in
  `handoffs/241-retest-2026-08-03/` (8 files) and `handoffs/241-retest-2026-08-04-round2/` (8 files,
  including `timeline.txt`).
- **The gate is unchanged and is Owen's alone:** his read of the exact text, plus his explicit go.
  Conditions (1) — the dedicated re-verification round — and (2) — the complete draft written out for
  him — are both recorded as met. Condition (3) has not been met.
- **What this brief adds to the record, and it is entirely client-side:** the defect's mechanism is
  now pinned to two lines of gateway source at head, and Talaria's own `createBareSession` walks into
  it by default. That changes what *we* can do without anyone upstream doing anything. **It does not
  bear on the submission decision, and no submission is recommended here.**

---

## 7. What is Owen's to decide

One question per line. Each is answerable yes/no or with a single choice.

1. **#132 — the original question, still unanswered:** should the host be pointed at a vision-capable
   model, or should `auxiliary.vision` be configured as the text-path fallback? (Mac is currently
   neither: `kimi-coding`/`kimi-k3`, `auxiliary.vision.provider: auto`.)
2. **#132 — do we ship the honesty floor now, independent of (1)?** Piece (a) — never send a
   captionless image, attach an in-band note — needs nothing from upstream and mirrors what the local
   plane already does.
3. **#187 — close it?** There is no work of ours left, and the watch is now a four-line code read
   rather than a probe. Closing reverses your 2026-08-02 "keep, annotated" ruling, which is why it is
   a question and not a disposition I took.
4. **#187 — raise the session-list `limit` from 50 toward 200** to recover the ~38% of the page spent
   on rows we discard? (Yes/no; nothing else changes.)
5. **#241 — open a client-side immunity lane** that sends an explicit `model` on `POST /api/sessions`
   so no Talaria session inherits the gateway's self-name? (This needs no upstream contact and does
   not touch the park.)
6. **#264 — adopt the upgraded ops rule** (read `~/.hermes/gateway_state.json`'s `platforms.api_server.state`
   as the first check; `/platform resume api_server` as the documented recovery where a surviving
   platform exists)?
7. **#264 — open the one-banner-one-truth lane** so PAIRED / PLUGIN LINK / the ABOUT hero cannot claim
   health while `:8642` is refusing?
8. **#241's park** — the park's stated premise ("the app rides the working lock plumbing") holds only
   when a model has been picked; does that change your read of the park, or does the answer to Q5
   settle it for you? *(Asked once, as instructed. No recommendation attached.)*

---

## 8. Proposed bars

Bars are pre-registered **here** only for items I am recommending as lanes. Per the 2026-08-01
convention, if any of these lanes is opened, its bars move into that item's `OPEN_ITEMS.md` entry
**before** any code is written — a dispatch doc is not the filing.

### Items that get NO bars, and why

- **#187** — no lane recommended. The client-side work is either zero (close it) or a one-constant
  change (Q4), and a one-constant change does not need a bar; it needs a diff and the gate.
- **#241's upstream half** — parked. Bars for a parked item would imply work.

### #132 — the honesty floor (if Q2 is yes)

- **132-A** — A caption-less image turn's request body contains **both** an `image_url` part **and**
  a text part. Unit test on `ChatTurnBody.make` / `RunsTurnBody.make`, asserting on the encoded JSON,
  **both transports** (the runs body wraps parts in a user message — the bar must hold in both shapes).
- **132-B** — RED witnessed first: the same test fails against today's builder, which emits a
  single-element parts array. If it does not fail before the change, the bar is measuring the wrong
  thing.
- **132-C** — Byte-compatibility guard: a turn **with** typed text plus an image is unchanged on the
  wire. This lane must not alter the shape that already works.
- **132-D** *(device, only if the wording piece ships)* — On the connected host, attach an image with
  no caption and confirm the reply does not present itself as having seen the image when it did not.
  **Named honestly: this bar is host-config-dependent** (its outcome differs on a vision vs a
  text-only model) and it is therefore a *contrast*, not a pass/fail — run it on both, or don't claim
  it.

### #241 — client-side immunity (if Q5 is yes)

- **241-CS-A** — `createBareSession`'s request body carries a non-empty `model`. Unit test on the
  encoded body; RED witnessed against today's `EmptyBody()`.
- **241-CS-B** — With **no** model picked, a chat turn's effective wire model is not the gateway's
  advertised self-name. **Verification is host-side and read-only:** `GET /api/sessions/{id}` on a
  freshly created session must report a real model id, never `hermes-agent`. No probe that modifies
  a live install; a session create is the app's own ordinary traffic.
- **241-CS-C** — Regression guard: with a model **picked**, the existing lock path is byte-unchanged
  (`require_model_lock: true` + `model` + `provider`). #223 Lane 5's plumbing must not move.
- **241-CS-D** *(evidence, not a gate)* — After the change, the host log no longer emits
  `Could not determine context length for model 'hermes-agent'` for new Talaria sessions. Recorded as
  corroboration; it is cache-warmed and once-per-model-endpoint, so **it can be absent for the wrong
  reason** — never let a missing warning line stand as the proof.

### #264 — one banner, one truth (if Q7 is yes)

- **264-A** — With `:8642` unreachable and a relay pairing record + a plugin token both present in
  local storage, the Server screen must not present PAIRED or PLUGIN LINK as a healthy state. Unit
  test at the state-resolution layer (`TalariaLinkState.resolve` and the card's `isPaired` source),
  **not** a snapshot test.
- **264-B** — RED witnessed: the same test passes-as-broken today (both badges read PAIRED with the
  gateway offline), and the fixture that makes it fail is the offline-gateway one.
- **264-C** — The ABOUT hero cannot read HEALTHY while its own `Hermes API` row reads UNREACHABLE.
  This is the `effectiveConnectionState` triplicate — **the bar is met only if all three copies move
  or the duplication is collapsed**, otherwise the next surface reproduces it (that is this
  umbrella's whole thesis).
- **264-D** — Release build, per #218. This lane touches state resolution used by widgets/About; a
  green Debug suite cannot see a mis-set gate.
- **264-E** *(ops, no code)* — The runbook check is written down and reads `gateway_state.json` first.
  A documented check is the deliverable; it does not need a test, it needs to exist where someone
  will find it at 2 a.m.

---

## 9. What this brief did NOT do

- Did not edit `OPEN_ITEMS.md`, any Swift file, or any file in a live Hermes install.
- Did not submit, polish for submission, or recommend submitting anything upstream.
- Did not restart, reconfigure, or write to either gateway.
- Did not verify anything against **OJAMD** — every code claim is head-of-source and shared by both
  hosts; every config-dependent consequence is host-specific and is marked as such.
- Did not run a chat probe. None of the four verdicts needed one, and a session create is a write.
