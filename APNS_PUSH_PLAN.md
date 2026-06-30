# APNs Remote Push — Implementation Plan (#38)

**Status:** planning · **Logged:** 2026-06-29 · **Depends on:** #24f (relay device-registry persistence)
**Pairs with:** the just-landed reconcile background-task fix (`fix/reconcile-bg-task`, commit `264f895`).

---

## 1. Goal & scope

Fire a **remote push** when a run completes server-side while the app is **suspended** —
the one case the app-side notification path cannot cover. iOS gives no way for a
suspended app to fire a local notification from a server event, so the only path is APNs.

**What the bg-task fix already covers (shipped):** a run that finishes within iOS's
granted background window after lock (~30s, sometimes more). The reconcile loop now
holds a `beginBackgroundTask` assertion, so it keeps ticking and fires the local
"Hermes finished" notification while still backgrounded.

**What this covers (the gap):** start a run, pocket the phone, walk away; it finishes
minutes later after iOS has fully suspended the app. No app-side timer survives that —
remote push is the only trigger.

**Verified prerequisite (already true):** runs complete and persist server-side after
the SSE disconnect; reconciliation works via `GET /api/sessions/{id}/messages`. A push
only needs to *announce* an already-finished, already-persisted result. So push is purely
additive — it never has to carry or guarantee the payload, just nudge the app to reconcile.

---

## 2. The core constraint (read this first)

The **Clean Chat Path is direct: app ↔ Hermes API Server `:8642`.** The relay (`:8000`)
is sensor-only and **never sees a chat run**. So:

- The component that *knows* a run finished is the **Hermes gateway / API Server**, which
  emits `run.completed`. The relay does not.
- Hermes' webhook feature is **inbound** (POST-to-trigger-a-run), so there is **no native
  outbound "fire on run.completed."** That hook is a server-side code change no matter what.
- Whoever sends the APNs push needs three things: (a) APNs credentials, (b) the target
  **device token**, (c) to be **invoked on run.completed**. (c) forces a Hermes-side hook
  in every design; the fork is about where (a) and (b) live, and how the finished run is
  **correlated to a device token**.

---

## 3. Design fork (decision needed)

### Option A — Hermes API Server fires APNs directly (token rides with the request)

App attaches its APNs token to the Sessions request (e.g. an `X-APNs-Token` header or an
optional field at `POST /api/sessions` / on `/chat`). Hermes stashes it on the session/run
and, in the API Server platform's post-run path, fires APNs itself with `session_id` in the
payload.

- **Pros:** simplest correlation — the token travels *with* the run, so the component that
  completes it already holds the token. No registry, no session→device lookup. Arguably no
  hard #24f dependency (token is supplied live per session).
- **Cons:** APNs credentials live on the **gateway host** (OJAMD); requires a Hermes
  **API Server code change** (accept token + fire push); threads a device token through the
  otherwise token-free chat path (mild erosion of chat/sensor independence); wastes the
  app's existing relay-registration plumbing.

### Option B — Relay sends APNs (reuses existing token registry) ← recommended

App registers its APNs token with the **relay** (the plumbing already exists:
`registerPushTokenIfNeeded`, the NOTIFICATIONS screen, `sessionStore.state.pushTokenRegistered`).
On `run.completed`, a **Hermes-side hook POSTs a completion signal to the relay** (`session_id`
+ correlation key); the relay maps it to the device token(s) and sends APNs.

- **Pros:** keeps APNs credentials + device registry in the **relay (Owen's own code)**;
  chat path stays token-free; reuses the app token-registration plumbing already built;
  aligns with #24f already being on the roadmap.
- **Cons:** needs **session→device correlation** (relay doesn't see sessions). The app must
  tell the relay which session it's awaiting — a small `POST /v1/device/watch {session_id}`
  at send time (or when backgrounding a run). Then completion-hook(`session_id`) →
  watch table → device token. Hard dependency on **#24f** (registry must survive relay
  restarts or pushes silently stop).

**Recommendation: Option B.** It preserves the clean chat path, keeps APNs in code you own,
and reuses existing app plumbing; the correlation "watch" call is a few lines and #24f is
already planned. Choose A only if you'd rather avoid relay correlation entirely and are fine
putting APNs creds on the gateway and a token field in the Sessions request.

> The Hermes-side completion hook is required either way. Cleanest insertion point is the
> **API Server platform adapter** (`gateway/platforms/…`) right after it finishes streaming
> a run — fire one side effect (A: send APNs; B: POST the relay). This is upstream Hermes
> code in your deployment; the hermes-agent contributor notes cover adding it.


---

## 4. Shared work (needed regardless of A or B)

### 4.1 Apple / APNs infrastructure (one-time)
- App target: enable **Push Notifications** capability (adds `aps-environment` entitlement)
  and **Background Modes → Remote notifications**.
- Apple Developer portal: create a **token-based APNs Auth Key** (`.p8`) — preferred over a
  cert (one key works for sandbox + prod, no annual expiry). Record **Key ID** + **Team ID
  `DNL25ZFSD2`**. APNs **topic = bundle id `org.aethyrion.talaria`**.
- **Environment gotcha:** dev builds use the APNs **sandbox**, TestFlight/App Store use
  **production** APNs. The sender must target the right host per build, and the device token
  from a sandbox build will not work against prod APNs. Plan to test on **TestFlight**
  (production APNs) since that's the only place suspend behavior is real anyway.

### 4.2 App side (mostly the same for A and B)
- After notification auth is granted, call `UIApplication.registerForRemoteNotifications()`.
- `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` → hex-encode → persist
  in `LiveNotificationService` → deliver to the sender (B: relay `POST /v1/device/register`;
  A: include on the Sessions request). Handle `didFailToRegister…` gracefully.
- Receive push:
  - **Tap path:** `UNUserNotificationCenterDelegate` → read `session_id` from payload →
    select that conversation → run the **existing** `reconcilePendingRuns()` / `attemptReconcile()`.
    No new fetch logic — reuse `GET /api/sessions/{id}/messages`.
  - **(Optional) silent path:** `content-available: 1` push → `didReceiveRemoteNotification`
    background fetch → reconcile + fire the local notification with the real reply preview.
    Note iOS throttles background content-available pushes — treat as best-effort.
- **Dedup with the local path:** key the notification request on **run id** (not a fresh
  UUID) so a push and the app-side local notification for the same run collapse instead of
  double-buzzing. Today's local path uses `hermes.run.completed.<uuid>`; switch to
  `hermes.run.completed.<runId>`.
- The **NOTIFICATIONS settings screen already exists** with a Push toggle wired to
  `registerPushTokenIfNeeded` — point it at the real registration + reflect token state.

### 4.3 Server side
- **Hermes hook (both options):** in the API Server platform post-run path, on
  `run.completed` fire the side effect (A: APNs send; B: POST relay completion).
- **Option B relay work (Owen's code, `O:\Hermes\Talaria\relay`):**
  - `POST /v1/device/register {token, platform, env}` → device registry.
  - `POST /v1/device/watch {session_id}` (auth'd as the paired device) → session→device map.
  - completion intake `POST /v1/runs/completed {session_id, …}` from the Hermes hook →
    look up watchers → send APNs (apns2/httpx, token-based JWT from the `.p8`).
  - **#24f:** persist the device registry + watch table (and JWT signing secret) across
    restarts. Without this, a relay restart drops tokens and pushes silently stop.

---

## 5. Phased implementation

1. **Infra + app registration** — capability/entitlement/background mode, APNs key,
   `registerForRemoteNotifications`, token persistence, wire the NOTIFICATIONS toggle.
   *Verifiable on TestFlight:* token prints and registers; no push yet.
2. **Server sender + hook** — (B) relay register/watch/completed endpoints + APNs sender;
   Hermes API Server completion hook POSTs the relay. (A) Hermes accepts token + sends APNs.
3. **Receive + reconcile** — tap → `session_id` → select + reconcile; run-id dedup.
4. **#24f persistence** — relay registry/watch survive restart; re-register on app launch
   and after a detected relay restart.
5. **Hardening** — token rotation, multi-device (Owen + Shelley), collapse-id, silent-push
   budget, "already reconciled before push arrived" race (push then finds nothing new → no-op).

---

## 6. Testing

- **TestFlight only** — simulator can render a dropped `.apns` payload but cannot exercise a
  real device-token round trip or true suspend. Production APNs env.
- Core case: lock phone → start a run long enough to outlast the bg-task window → confirm the
  **push arrives after suspend** → tap → lands on the right session with the reply present.
- **#24f regression:** restart the relay mid-await → confirm the app re-registers and the next
  run still pushes (this is the failure mode that makes push look "randomly broken").
- Dedup: a run that finishes inside the bg window should produce **one** notification, not two.

---

## 7. Open decisions for Owen

1. **Option A vs B** (§3). Recommendation: **B**. Confirm before any server work starts.
2. **Silent `content-available` push** (preview without a tap) — include in v1, or ship
   tap-to-reconcile only and add silent later? (Silent is throttled by iOS; tap path is the
   reliable core.)
3. **#24f sequencing** — land relay persistence first, or build push against the in-memory
   registry and accept "re-pair after relay restart" until #24f lands? (B works without #24f,
   just fragile across restarts.)
4. **Multi-device** — register/push to **all** of a user's paired devices (Owen + Shelley),
   or a single "primary"? Affects the registry key (per-device vs per-user-primary).
