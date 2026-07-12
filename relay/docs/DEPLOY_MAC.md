# Mac Mini deployment — relay + connector (T6 Phase 1) + Mac-only connectors (Phase 2)

Ops runbook for OPEN_ITEMS **#107** (spec: `design/T6_MAC_BACKEND_SPEC.md`, executing #34,
enabling #33). Mirrors the OJAMD ops notes in launchd terms. Written 2026-07-12 in the cloud —
every step below still needs its first real execution on the Mini; check items off in #107.

## Topology

| Service | Port | How it runs | Label / manager | Logs |
|---|---|---|---|---|
| Hermes gateway / API server | :8642 | `hermes gateway run` (already on the Mac) | confirm persistence — native, else `org.aethyrion.talaria-gateway` via installer | `~/Library/Logs/talaria-gateway/` (if ours) |
| Models shim | :8765 | `tools/models-shim/shim.py` under the hermes-agent venv python (already on the Mac) | `com.aethyrion.talaria.modelsshim` — **re-render**: committed plist points at the old `…/Documents/Claude/Talaria` checkout | `~/.hermes/logs/talaria-shim.{out,err}.log` |
| **Relay** | :8000 | uvicorn from `relay/.venv` (THIS phase adds it) | `org.aethyrion.talaria-relay` | `~/Library/Logs/talaria-relay/` |
| **Connector** | (WS client) | `hermes-mobile` native LaunchAgent (THIS phase adds it) | `ai.hermes.mobile.connector` | `~/.hermes-mobile/logs/connector.{stdout,stderr}.log` |

Machine: Mac Mini M4, tailnet `100.79.222.100`, repo at
`/Users/owenjones/Documents/Claude/Talaria-27`, Hermes at `~/.hermes/hermes-agent/`
(`API_SERVER_KEY` in `~/.hermes/.env`). Reference production: OJAMD (`100.110.102.59`).

## Guardrails

- **OJAMD stays untouched.** The physical phone's production pairing lives there; one active
  pairing per app install (#91) — pointing the phone at the Mac means unpair → re-pair, which
  is reversible but deliberate. Dev device / simulator pairs to the Mac instead.
- **Never patch Hermes core** — `curl install.sh | bash` replaces `~/.hermes/hermes-agent` and
  wipes core edits (`config.yaml`/`.env`/skills/sessions persist). Everything here is sidecar
  (`relay/`, `connector/`, `tools/`) or ops config.
- **Do NOT copy OJAMD's secrets.** Mint fresh `INTERNAL_API_KEY` / `CONNECTOR_SETUP_SECRET`;
  `GATEWAY_API_KEY` is the *Mac's* `API_SERVER_KEY`. The only thing that legitimately crosses
  over is the APNs `.p8` (same Apple team).
- Branch of record: `main`, pinned at a known-good commit (record it in #107). Cut a
  `mac-deploy` branch only if deploy-only divergence ever appears (Q4 in the spec).

## Phase 1 — step by step

### 0. Preconditions

```sh
cd /Users/owenjones/Documents/Claude/Talaria-27
git fetch origin && git checkout main && git pull origin main
git log --oneline -3   # record the pinned commit in OPEN_ITEMS #107
command -v hermes && hermes --version   # the connector target (§2.1 of the spec)
```

Confirm the checkout contains the merged relay/connector work (#87 UTF-8 fix, #98 scheduler,
#107 scaffolding — this file existing is itself the check).

### 1. Directories + secrets

```sh
mkdir -p ~/Hermes/agent-work/MobileDL          # HERMES_WORKDIR + AGENT_FILES_DIR (§2.1)
mkdir -p ~/.secrets/apns && chmod 700 ~/.secrets ~/.secrets/apns
# Copy AuthKey_ALB34NY384.p8 from OJAMD C:\Secrets\apns\ (tailscale file cp / scp), then:
chmod 600 ~/.secrets/apns/AuthKey_ALB34NY384.p8
openssl rand -hex 32   # run twice: INTERNAL_API_KEY, CONNECTOR_SETUP_SECRET
```

### 2. Relay venv + env

```sh
cd relay
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
cp .env.mac.example .env
# Fill: INTERNAL_API_KEY, CONNECTOR_SETUP_SECRET, HERMES_COMMAND (absolute),
#       GATEWAY_API_KEY (from the Mac's ~/.hermes/.env API_SERVER_KEY).
# Keep: RELAY_ENVIRONMENT=production, absolute DATABASE_URL, absolute APNS_KEY_PATH
#       (the relay does NOT expand ~), APNS_BUNDLE_ID=org.aethyrion.talaria27.
```

### 3. Relay LaunchAgent

```sh
scripts/mac/install-relay-launchd.sh
```

Preflights the venv/.env (fails fast on placeholder keys — in `production` the relay refuses
`replace-me` at startup anyway), renders `org.aethyrion.talaria-relay`, bootstraps,
kickstarts, and polls `/v1/health`. Startup log should show
`APNs client initialized (development, bundle: org.aethyrion.talaria27)` and
`Gateway client initialized (http://127.0.0.1:8642)` — "not configured" means `.env` keys
didn't load (see `relay/docs/APNS_OJAMD.md` for the full APNs verification ladder; it applies
here with Mac paths).

### 4. Connector

```sh
cd ../connector
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
export HERMES_COMMAND=/absolute/path/to/hermes
export HERMES_WORKDIR=~/Hermes/agent-work
export CONNECTOR_SETUP_SECRET=<same value as relay/.env>
.venv/bin/hermes-mobile setup --relay-url http://127.0.0.1:8000/v1   # loopback: same host
.venv/bin/hermes-mobile validate-mcp        # hermes_mobile registered in ~/.hermes/config.yaml
cp -R ../skills/hermes-ios ~/.hermes/skills/   # REAL copy, not symlink — setup does NOT do this
# then in a Hermes chat: /reload-mcp
.venv/bin/hermes-mobile service install && .venv/bin/hermes-mobile service start
.venv/bin/hermes-mobile status              # expect: running (macOS launchd)
```

Connector state: `~/.hermes-mobile/state.json`, sensors DB `~/.hermes-mobile/sensors.db`
(`HERMES_MOBILE_CONNECTOR_HOME` overrides the home; adjust paths if set).

### 5. Gateway + shim persistence (the "while you're in there" of §3.3)

```sh
launchctl print gui/$(id -u) | grep -iE 'hermes|talaria|aethyrion'
```

- **Shim:** re-render regardless — the committed plist predates this checkout:
  `scripts/mac/install-shim-launchd.sh` (keeps label + log paths, points at THIS repo,
  verifies `hermes_cli` imports and `/healthz`).
- **Gateway:** if nothing persists it, prefer whatever native persistence Hermes offers on
  macOS first (the `hermes gateway install` prohibition in CLAUDE.md is **Windows-specific**);
  fall back to `scripts/mac/install-gateway-launchd.sh`, which refuses to double-manage if a
  gateway-shaped agent already exists.

### 6. Tests on macOS

```sh
cd relay     && .venv/bin/python -m pytest -q
cd ../connector && .venv/bin/python -m pytest -q
```

Cloud Linux baseline at scaffolding time (2026-07-12, Python 3.11): relay **117 passed**,
connector **104 passed + 1 skipped** — the skip is the macOS LaunchAgent test itself, which
un-skips on the Mac (expect 105/105). Record actual macOS counts in #107/PR.

### 7. Acceptance smoke + restart durability

```sh
scripts/mac/verify-phase1.sh                  # services, health, env hygiene, Tier-2 gate
scripts/mac/verify-phase1.sh --restart-check  # bounce relay → connector reattach (#54)
```

Restart durability context: the relay is DB-backed (hashed tokens in `auth_sessions`,
devices/push registrations as rows) — #24f is stale; there is no in-memory registry to lose.
The restart check proves the launchd-managed connector reattaches unattended (nonce
DB-persistence shipped 2026-07-09, #54) — **note the result on #54 either way**.

### 8. Pair a dev device + device checklist

```sh
cd connector && .venv/bin/hermes-mobile pair-phone
```

Point a **dev build / simulator** at `http://100.79.222.100:8000/v1` and work the #107 device
checklist (pair, sensors `deliveryState=delivered` with ≤100-sample health chunks per #24a,
talk readiness, run-completion push, authed Tier-2 file fetch 200). Remember the #24e trap:
iCloud Private Relay intercepts HTTP to Tailscale IPs — disable it on the test device.

### 9. Reboot test

Reboot the Mini once; then `scripts/mac/verify-phase1.sh` again. All four services must come
back with no login beyond Owen's auto-login session (LaunchAgents are per-user: they start at
login, not boot — the Mini's auto-login makes that equivalent; if auto-login is ever disabled,
revisit as LaunchDaemons).

## Recovery cheat sheet

```sh
UID_T=gui/$(id -u)
launchctl print $UID_T/org.aethyrion.talaria-relay | grep -E 'state|pid'
launchctl kickstart -k $UID_T/org.aethyrion.talaria-relay      # restart relay
launchctl bootout $UID_T/org.aethyrion.talaria-relay           # stop
launchctl bootstrap $UID_T ~/Library/LaunchAgents/org.aethyrion.talaria-relay.plist  # start
tail -f ~/Library/Logs/talaria-relay/relay.err.log
cd connector && .venv/bin/hermes-mobile service restart && .venv/bin/hermes-mobile service logs
cp relay/hermes_mobile.db relay/hermes_mobile.db.$(date +%Y%m%d).bak   # DB backup (+ -wal/-shm if present)
```

Order after a full outage: gateway → relay → connector (connector dials the relay; relay's
push-watch dials the gateway; each self-heals, order just shortens the wait).

## Phase 2 — Apple connectors (#33, the payoff)

Prereq: Phase 1 green. Work each connector as: enable → grant TCC → exercise **from Talaria
chat** → check off in #107.

1. **Evaluate the iMessage path first (Q2):** on the Mini, check what today's macOS Hermes
   treats as first-class — the classic `imsg` connector vs the newer Photon iMessage
   (`hermes --version`, connector/toolset listings, upstream docs). Prefer the first-class
   one. **Single-automated-sender rule:** BlueBubbles keeps running (reads of chat.db don't
   conflict) but only ONE system sends on the agent's behalf — two writers can race Messages.
   Record the choice + rationale in #107.
2. **TCC for the launchd context — the classic trap:** LaunchAgent-spawned processes get
   their own TCC identity. Grant Full Disk Access (chat.db) and Automation to the **binary
   that actually runs** (the hermes-agent venv `python`/`hermes` binary spawned by the
   connector's LaunchAgent — not Terminal, not the interactive shell). Practical route: run
   the tool once via Talaria chat, let the TCC prompt fire against the right process, approve;
   verify in System Settings → Privacy & Security → Full Disk Access / Automation. If no
   prompt appears (launchd contexts sometimes suppress UI), add the binary manually.
3. **Connectors in order:** iMessage (`imsg`/Photon; needs signed-in Messages ✅ BlueBubbles
   already proves it, FDA, Automation, SMS forwarding from the phone) → Notes (`memo`;
   Automation) → FindMy (FindMy.app session state). Each connector's `check_fn` gates it —
   inert until prerequisites are met, same as they're inert on OJAMD.
4. **Acceptance (§6.5):** at least one connector end-to-end from Talaria chat, e.g. "send an
   iMessage to Shelley: …" → confirm gate → delivered.

## "Windows brain, Mac hands" (optional accelerator, independent of Phase 1)

Gives the phone's **production** (OJAMD) brain the Mini's Apple tools tonight — no re-pairing,
no re-homing, reversible (~30 min):

1. Mini: `hermes mcp serve` exposing the Apple toolset over the tailnet.
2. OJAMD (PowerShell): `hermes mcp add` pointing at `100.79.222.100` (remember `curl` is an
   alias there — `Invoke-RestMethod`/`curl.exe` for any probing).
3. TCC on the Mini still applies to the served tools (grant against the `hermes mcp serve`
   process context) — same trap as Phase 2 step 2.
4. Verify from the phone (OJAMD pairing, untouched): iMessage prompt → confirm gate →
   delivered. Remove with `hermes mcp remove` on OJAMD.

## Decisions record (Q1–Q5)

Adopted defaults live in `design/T6_MAC_BACKEND_SPEC.md` §7 — summary: both Phase 1 and the
bridge are supported (order = Owen's call); iMessage path decided on-box with a
single-sender rule; APNs key at `~/.secrets/apns/AuthKey_ALB34NY384.p8` with
`APNS_BUNDLE_ID=org.aethyrion.talaria27`; services run from pinned `main` (no `mac-deploy`
until divergence is real); spec is committed in-repo.
