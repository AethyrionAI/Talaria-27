# APNs run-completion push — OJAMD config + deploy (#38)

**What this enables:** when a Talaria run outlives the app's background
window (phone locked/pocketed), the relay polls the gateway for the
finished reply and fires a real APNs alert. Tap → the app opens the
session and fetches the reply.

**How it works (all in this repo, no Hermes-core changes):**

1. App backgrounds mid-run → `POST /v1/push/watch {sessionId}` (device
   bearer auth). The relay also flips the device to `background` so the
   presence gate can't race the separate app-state report.
2. Relay polls `GET {GATEWAY_BASE_URL}/api/sessions/{id}/messages`
   (Bearer `GATEWAY_API_KEY`) every 3s (10s after 2 min, 30 min TTL).
   Completion = a non-empty assistant message after the transcript's
   last user message — same watermark the app's reconcile uses, and
   entirely server-side, so clock skew can't cause a miss.
3. On completion → APNs alert (`title: Hermes`, body = reply preview,
   payload `session_id`) to the user's registered, non-foreground
   devices. Invalid tokens (410) auto-deactivate.
4. If the app reconciles on its own first, it calls
   `POST /v1/push/watch/cancel` and no push is sent.

## Relay `.env` additions (live relay dir on OJAMD)

```ini
# APNs credentials — from Apple Developer → Keys (the stored .p8)
APNS_KEY_PATH=C:\Users\Owen\.hermes\AuthKey_XXXXXXXXXX.p8   # wherever the .p8 is stored
APNS_KEY_ID=XXXXXXXXXX          # 10-char Key ID shown next to the key
APNS_TEAM_ID=DNL25ZFSD2         # Apple developer team
APNS_BUNDLE_ID=org.aethyrion.talaria
APNS_ENVIRONMENT=development    # dev-signed device builds = sandbox APNs

# Gateway polling (relay and gateway share OJAMD, so localhost)
GATEWAY_BASE_URL=http://127.0.0.1:8642
GATEWAY_API_KEY=<API_SERVER_KEY>   # same 64-char key as ~/.hermes/.env

# #24f hardening while in here: pin the DB so it never depends on the
# service's working directory (use the CURRENT live relay.db path —
# check `nssm get HermesMobileRelay AppDirectory` first; moving the
# path orphans existing pairings and forces a re-pair)
DATABASE_URL=sqlite:///O:/Hermes/Talaria/relay/relay.db
```

Notes:
- `APNS_ENVIRONMENT=development` matches the app's Debug builds
  (`aps-environment: development` entitlement + the app registers
  `pushEnvironment: development`). Each push registration carries its
  own environment/bundle, so the env-var defaults are fallbacks — but
  set them anyway. A TestFlight/Release build needs `production` (→ #8).
- No new Python deps: `PyJWT[crypto]` and `httpx[http2]` are already in
  `pyproject.toml`. If the live venv predates them:
  `pip install -e .` in the relay dir.
- The APNs sandbox host is `api.sandbox.push.apple.com` (updated from
  the legacy `api.development.push.apple.com` alias).

## Deploy

Follow the standard pattern from `DEPLOY_OJAMD.md` (backup DB → drift
check → backup live code → `nssm stop HermesMobileRelay` → update code →
`.env` additions above → `nssm start HermesMobileRelay`).

## Verification ladder (each step isolates one link)

1. **Relay startup log** shows both clients initialized:
   `APNs client initialized (development, bundle: org.aethyrion.talaria)`
   and `Gateway client initialized (http://127.0.0.1:8642)`. If either
   says "not configured", the corresponding `.env` keys didn't load.
2. **Device token in hand:** Talaria → Settings → Diagnostics → tap the
   Push Token row (copies the full APNs token; row flashes COPIED).
   Both Notifications + Diagnostics should read RELAY REGISTERED first.
3. **Direct APNs send** (proves .p8 + Key ID + Team ID + sandbox
   routing, no watch machinery). PowerShell, on OJAMD:
   ```powershell
   Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/v1/push/send `
     -Headers @{ "X-Relay-Internal-Key" = "<INTERNAL_API_KEY>" } `
     -ContentType "application/json" `
     -Body '{"user_id":"<relay user id>","type":"alert","title":"Talaria","body":"APNs credentials verified"}'
   ```
   (Relay user id: Diagnostics → Relay Identity shows the first 8 chars;
   the full id is in the relay DB `users` table.) Phone must be locked/
   backgrounded — foreground devices are presence-suppressed.
   Expect `{"sent": 1}` and a buzz. A `403 InvalidProviderToken` here
   means Key ID/Team ID/.p8 mismatch; `400 BadDeviceToken` means
   environment mismatch (sandbox key vs production registration or
   vice versa).
4. **End-to-end:** in Talaria, send a prompt that runs long (`think
   hard about…`), immediately lock the phone, wait past the ~2 min
   background ceiling. Expect the alert push with the reply preview.
   Tap it → app opens straight into chat with the finished reply.
   Relay log shows `push watch: session <id> completed, push dispatched`.
5. **No stale push:** repeat, but unlock the phone before the run
   finishes and watch the reply stream in via reconcile. No push should
   arrive afterwards (the app cancels the watch; if the cancel raced,
   the foreground presence gate still suppresses it).

## Failure modes worth knowing

- **Relay restarts mid-watch:** active watches are in-memory and are
  lost. The app re-posts the watch on its next background transition
  with a still-pending run; otherwise the reply is picked up by normal
  foreground reconcile. No re-pair needed post-#37 (DB-backed tokens).
- **Watch endpoint 503:** APNs or gateway env vars missing — the app
  logs and degrades to local-notification behavior; nothing user-facing
  breaks.
- **Gateway down:** watcher tolerates 19 consecutive poll failures
  (~1–3 min) before abandoning; transient blips just delay the push.
