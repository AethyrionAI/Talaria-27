# FABLE T27-21 — Tier 2 app-side agent-file fetch (#21)

**OPEN_ITEMS:** #21 (present/download agent-generated files)
**Branch prefix:** `claude/t27-21-`
**Builds on:** Tier 1 (content-present files → ShareLink bubble) shipped `96b291f`;
Tier 2 relay route (`GET /v1/device/files`) built + deployed + LIVE on OJAMD
`ccf6e5a`. This lane is the remaining APP-SIDE half only.

## Objective

Today the app reconstructs an agent-written file into a ShareLink bubble *only
when its bytes ride inline in the SSE* (`write_file` `tool.started.args.content`
— Tier 1). Files whose content is absent from the stream (binaries, oversized,
non-reconstructable) never reach the phone. The relay already exposes an authed
fetch route for exactly these. Add the app side: when the content is absent,
render a **fetchable** file bubble that downloads on tap from the relay route,
stages the bytes, and then behaves like a Tier 1 bubble (ShareLink + the Lane I
#99 preview sheet).

## Grounding — read these BEFORE designing (probe-first rule)

- `Talaria/Services/Live/SessionsHermesClient.swift` — the SSE loop and
  `parseWrittenFile` (Tier 1 stages from `args.content`, tolerant of key drift:
  `args`/`arguments`/`input`, `path`/`file_path`/`filename`,
  `content`/`text`). The content-present-vs-absent branch goes HERE.
- `Talaria/Features/Chat/MessageBubble.swift` — the Tier 1 agent-file ShareLink
  bubble. The fetchable bubble hangs its tap→download affordance off this;
  after download it must reuse the SAME bubble + the Lane I `FilePreviewSheet`.
- `Talaria/Models/Message.swift` (`MessageAttachment`) — add an OPTIONAL
  `remotePath` + a `fetchableAgentFile(...)` factory; keep it additive so
  pre-#21 caches still decode (mirror the `voiceMemoAudioPath` precedent, #59).
- The relay client (`RelayAPIClient` / relay-plane networking) — where
  `downloadFile(path:accessToken:)` lands; reuse the device-bearer token the
  app already holds from pairing. Do NOT add new credential storage.
- **Relay route contract (reference — read before shaping the request):**
  `GET /v1/device/files?path=…` on OJAMD relay (`O:\Hermes\Talaria\relay`,
  ~`app/main.py:976`). Bearer-gated via `get_auth_context`; `resolve_agent_file()`
  resolves symlinks/`..` then enforces containment (`relative_to(AGENT_FILES_DIR`
  = `O:\Hermes\MobileDL`); every failure → 404 (never leaks existence);
  no-token → 401; streams `FileResponse` (content-type + filename). **Confirm
  whether `path=` expects an absolute host path or an AGENT_FILES_DIR-relative
  path** — the parser must emit whichever form the route accepts.

## The gate — PROBE FIRST, it decides the trigger

**PROBE COMPLETE 2026-07-16 — GATE RESOLVED, build the Tier 2 branch.**
Probed on the Mac Mini gateway (:8642, Hermes v0.18.2 — identical emitter to
OJAMD). Natural request ("create a small PDF … save it in my MobileDL folder"):
the agent located MobileDL itself (search_files + find — NO Hermes-side nudge
was needed), then produced the binary entirely host-side via `terminal`
(python venv + reportlab). **`write_file` was never called; binary content
appears NOWHERE in SSE tool args in any form.** Real 1-page PDF landed in
AGENT_FILES_DIR. Verdict per the gate: content absent → **Tier 2
`fetchableAgentFile`** — the trigger must NOT key off write_file args; key off
the Tier-2 listing/announcement path. Raw capture: /tmp/t21-probe.sse (Mini).

Original gate text (for reference):
The binary-write SSE shape is unprobed. Before any app code:

1. On OJAMD, drive one real **non-text** `write_file` — ask the agent (a chat
   turn on `:8642`) to save a small **PDF** into `MobileDL` (`AGENT_FILES_DIR`).
2. Capture that turn's `:8642/chat/stream` SSE and inspect the `write_file`
   `tool.started.args`: is `content` **present** (base64? utf8-garbled? a data
   URI?) or **absent** for a binary?
3. Record the answer in the PR. It decides the branch:
   - content **present + reconstructable** → Tier 1 stages it, no fetch.
   - content **absent / non-decodable** → emit a Tier 2 `fetchableAgentFile`.
4. Also confirm the **Hermes-side nudge** is needed so the agent writes
   shareable artifacts into `MobileDL` (flag as an OJAMD follow-up; not app code).

## Deliverables

### 1. Probe write-up
The SSE-shape answer from the gate above, in the PR body. Non-negotiable — it is
the reason the trigger logic is what it is.

### 2. Model — `MessageAttachment` (Message.swift)
- Optional `remotePath: String?` + `static func fetchableAgentFile(name:remotePath:)`.
- Additive/optional so existing persisted caches decode unchanged (round-trip test).

### 3. Networking — `RelayAPIClient.downloadFile(path:accessToken:)`
- `GET {relayBase}/v1/device/files?path=<pct-encoded, route-form>`,
  `Authorization: Bearer <device token>` — token in the HEADER, never the URL.
- Streams to a temp file; maps **401 → auth error**, **404 → not-found**
  (honest, never "leaks existence"), other non-2xx → surfaced error.

### 4. Parser branch — `parseWrittenFile` (SessionsHermesClient)
- content present → existing Tier 1 (stage now).
- content absent → build a `fetchableAgentFile` attachment carrying the
  route-form `remotePath` derived from `args.path`. No staging yet.

### 5. Fetchable bubble — `MessageBubble` + `ChatStore`
- Tap → download (spinner) → stage → the bubble becomes a normal Tier 1 bubble
  (ShareLink + Lane I `FilePreviewSheet`). Honest failure states (auth/not-found/
  offline), retry affordance. Give `ChatStore` the relay client + device token to
  drive tap→download→stage.

### 6. Tests (Swift Testing)
- `MessageAttachment` decode round-trip WITH `remotePath`, AND a pre-#21 cache
  fixture still decodes (the additive contract).
- Parser: content-present → staged Tier 1; content-absent → `fetchableAgentFile`.
- `RelayAPIClient` request shaping via a stubbed transport: URL + query, auth
  header present, 401/404/other mapping. (No WKWebView/network rendering test.)

## Hard constraints

- **Reuse Lane I `FilePreviewSheet` (#99)** for viewing after download — do not
  build a second preview surface.
- **No relay/Hermes code in this lane.** The route is already deployed; the only
  server-side item is the documented Hermes-side nudge (agent writes into
  `MobileDL`) — flag it as an OJAMD follow-up, don't implement it here.
- **Device token:** reuse the existing pairing-issued device bearer; no new
  credential storage, no key entry.
- **Path safety mirrored client-side:** only ever send the agent-relative
  (whitelisted) path; the relay enforces containment — the app must not attempt
  arbitrary absolute paths.
- New Swift files ⇒ PR notes the Mac runs `xcodegen generate` + re-verifies
  `aps-environment` survives (#44/#48 trap).
- File-scoped commits; no `OPEN_ITEMS.md` edits; no pbxproj in feature commits.
- **Privacy:** device token in the `Authorization` header only — never the URL,
  query, or logs.
- Cloud can't build: check `URLSession` download + any iOS 27 APIs against the
  SDK; be suspicious of Foundation bridging shortcuts (the review loop keeps
  catching those).

## Acceptance

- Probe answer recorded (binary `args.content` present/absent + route path-form).
- Text file → still Tier 1 (content present, staged inline, no fetch — no regression).
- Binary/oversized file written to `MobileDL` → fetchable bubble → tap →
  downloads from `/v1/device/files` → stages → ShareLink + Lane I preview work.
- **401** (missing/bad token) and **404** (path outside whitelist / missing)
  surface honest errors, never a leak or a blank sheet.
- All `@Test` suites green (Swift Testing ✔ line). Device-verify owed on
  whoGoesThere (relay reachable): the end-to-end tap→download→share.
- PR titled `#21 Tier 2 — app-side agent-file fetch`.


## POST-LANE-M ADDENDUM (2026-07-16) — read before building

Lane M (#114, merged) landed backend profiles, and it changes this lane's
fetch path materially:

1. **Sessions carry an immutable birth-profile `profileID`** and every relay
   interaction resolves through `ProfileRelaySessionFactory`
   (`Talaria/Services/Support/ProfileRelaySession.swift`). A
   `fetchableAgentFile` announced in a session MUST be fetched from **that
   session's birth profile's relay** — a Mac-hosted session's file lives in
   the MAC relay's `/v1/device/files`, an OJAMD session's in OJAMD's. Do not
   use a global relay base URL anywhere in the fetch path; resolve per-session.
2. Auth: use the profile-scoped relay tokens (Keychain, profile-keyed —
   `BackendProfileScopedKeys`). The factory already exposes the per-profile
   session; prefer extending it over parallel plumbing.
3. Both hosts are live and paired on whoGoesThere, so device verification can
   exercise BOTH directions: task the Mac ("make me a PDF in MobileDL"), fetch
   its file; same against OJAMD. The Mac's `AGENT_FILES_DIR` is
   `~/Hermes/agent-work/MobileDL` and the probe artifact `probe-t21.pdf`
   (1503 bytes, real PDF) is already sitting there — a ready-made fixture.
4. The probe verdict at the top of this spec (2026-07-16) resolves the gate:
   build the Tier 2 branch; the trigger must not key off `write_file` args.
