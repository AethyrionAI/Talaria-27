# T6 — Mac-hosted Talaria backend, Phase 1 (relay + connector on the Mac Mini) + Mac-only connectors

> **STATUS 2026-07-15 — EXECUTED. This spec is now a historical record; live state is OPEN_ITEMS #107.**
> §6 acceptance scored: (1) launchd persistence ✅ *(Mini reboot still owed — Owen)*;
> (2) dev-device pairing ⬜ — deferred to #114 (the app can't hold a second profile yet);
> (3) connector reattach ✅ (`verify-phase1.sh --restart-check`, noted on #54) — pairing-survival
> half untestable until a device is paired to this relay; (4) macOS suites ✅ relay 117 / connector 105;
> (5) connector end-to-end ⚠️ PARTIAL — iMessage send+read and Notes read+write verified agent-driven
> through the Sessions API (byte-for-byte the app's path), but *literally from Talaria chat* waits on
> #114; (6) OJAMD untouched ✅; (7) OPEN_ITEMS updated ✅.
> Q1/Q2 below are RESOLVED — do not re-run the evaluation.

**Status:** v0.2 — revised after direct inspection of the OJAMD deployment and repo (relay
source, `.env`, `CLAUDE.md`, `OPEN_ITEMS.md`). Committed to the repo 2026-07-12 (Q5 answered:
in-repo at `design/T6_MAC_BACKEND_SPEC.md`).

**Executes:** OPEN_ITEMS #34 (T6), un-deferred by Owen 2026-07-12; enables #33 server-side
Apple connectors. Tracking item for Phase 1 execution: **OPEN_ITEMS #107**.

**Target machine:** Mac Mini M4 (`Owens-Mac-mini.local`, tailnet `100.79.222.100`) — already
runs: the repo checkout (`/Users/owenjones/Documents/Claude/Talaria-27`), Xcode-beta, Hermes
gateway `:8642`, models shim `:8765`, BlueBubbles.

**Reference deployment:** OJAMD (`100.110.102.59`) — relay `:8000`, shim `:8765`, gateway `:8642`.

**Repo conventions apply:** OPEN_ITEMS entries with dated notes, "Questions for Owen" for
decisions, relay changes live in the relay sidecar (`relay/`) — never patches to Hermes core.

> **Repo scaffolding (landed 2026-07-12, branch `claude/talaria-mac-backend-phase1-m0jkm0`):**
> - `relay/docs/DEPLOY_MAC.md` — the operational runbook (step-by-step Phase 1 + Phase 2 + recovery).
> - `relay/.env.mac.example` — Mac-shaped relay env template.
> - `scripts/mac/install-relay-launchd.sh` — relay LaunchAgent installer (`org.aethyrion.talaria-relay`).
> - `scripts/mac/install-gateway-launchd.sh` — gateway LaunchAgent fallback installer (`org.aethyrion.talaria-gateway`).
> - `scripts/mac/install-shim-launchd.sh` — shim LaunchAgent re-render/installer (keeps label `com.aethyrion.talaria.modelsshim`).
> - `scripts/mac/verify-phase1.sh` — acceptance smoke (services, health endpoints, `--restart-check`).
> - OPEN_ITEMS: #107 (new), #33/#34/#54 dated notes.

---

## 1. Architecture (verified — do not redesign)

Per `CLAUDE.md` Clean Chat Path: chat and sensors are independent paths.

```
Talaria app ── chat ──────────────► Hermes gateway/API server :8642  (already on the Mac ✅)
Talaria app ── models picker ─────► models shim :8765               (already on the Mac ✅)
Talaria app ── sensors/pairing/push/talk/inbox/agent-files ──► relay :8000   (MISSING on Mac — this spec)
                                        │ WebSocket /v1/hosts/ws
                                        ▼
                                   connector (hermes-mobile)          (MISSING on Mac — this spec)
                                        │ HERMES_COMMAND
                                        ▼
                                   macOS Hermes runtime  ── registers hermes_mobile MCP in ~/.hermes/config.yaml

relay push-watch (#38) ── polls ──► gateway :8642 (GATEWAY_API_KEY) ── APNs on run completion
```

The relay is a FastAPI app (`relay/app`, uvicorn, Python 3.11+, SQLite via
`DATABASE_URL=sqlite:///./hermes_mobile.db` — path anchored to the relay package per GH #59).
The connector (`connector/`, `hermes-mobile`) is the host-side bridge and natively supports
macOS: `hermes-mobile service install` creates a per-user launchd LaunchAgent
(`ai.hermes.mobile.connector`). macOS is upstream's first-class platform; OJAMD is the exotic
deployment, not the Mac.

## 2. What "link to Hermes" concretely means (three wires)

1. **Connector → Hermes CLI:** `HERMES_COMMAND` pointing at the Mini's existing Hermes install
   (validate `hermes --version` first). Set `HERMES_WORKDIR` to the Mac's agent working dir —
   adopted: `~/Hermes/agent-work/` (Mac analog of `O:\Hermes\`); `AGENT_FILES_DIR` for the #21
   Tier-2 file route points at a subdir of it — adopted: `~/Hermes/agent-work/MobileDL/`
   (faithful to OJAMD's `O:\Hermes` + `O:\Hermes\MobileDL` topology; a sibling dir works too,
   it's one env var).
2. **Connector → Hermes config:** setup registers the `hermes_mobile` MCP server in
   `~/.hermes/config.yaml` and validates with `hermes-mobile validate-mcp` (equivalent of
   `hermes mcp test hermes_mobile`); copy the `hermes-ios` skill into `~/.hermes/skills/`
   (**real copy, not symlink** — setup does NOT do this automatically), then `/reload-mcp`.
3. **Relay → gateway push-watch (#38):** `GATEWAY_BASE_URL=http://127.0.0.1:8642` +
   `GATEWAY_API_KEY` = the **Mac's** `API_SERVER_KEY` (from the Mini's `~/.hermes/.env`) so
   run-completion pushes fire from the local gateway. Do NOT copy OJAMD's key.

## 3. Phase 1 — Re-home relay + connector (parity)

**Definition of done:** a dev build of Talaria-27 pointed at `http://100.79.222.100:8000/v1`
(or LAN IP) can pair, deliver sensors (health chunks ≤100/request per #24a), bootstrap a talk
session, receive a run-completion push, and fetch a Tier-2 agent file — with OJAMD untouched
and still serving the phone's production pairing.

1. **Working tree:** use the Mini's existing repo checkout on the branch of record. Adopted
   (Q4): run from `main` of AethyrionAI/Talaria-27 pinned at a known-good commit; cut a
   `mac-deploy` branch (mirroring the `ojamd-deploy` convention) only when deploy-only
   divergence actually appears — the Mac checkout starts clean, unlike OJAMD's. Ensure the
   #87 UTF-8 fix and all merged relay/connector work from `t27/main` is present.
2. **Relay env** (`relay/.env` on the Mac): copy shape from `relay/.env.mac.example`, mint
   fresh `INTERNAL_API_KEY` and `CONNECTOR_SETUP_SECRET` (never `replace-me` — startup fails
   outside dev; set `RELAY_ENVIRONMENT=production` so the guard actually enforces).
   `PUBLIC_BASE_URL=http://100.79.222.100:8000/v1` (tailnet) — revisit `tailscale serve`
   HTTPS later, which would also dodge the #24e iCloud Private Relay trap. `APNS_*` per Q3
   (adopted: key at `~/.secrets/apns/AuthKey_ALB34NY384.p8` chmod 600, absolute path in
   `.env` — the relay does not expand `~`; `APNS_BUNDLE_ID=org.aethyrion.talaria27`, the
   fork's verified `PRODUCT_BUNDLE_IDENTIFIER`). `AGENT_FILES_DIR` per §2.1.
3. **Relay venv + service:** `python3 -m venv .venv && pip install -e '.[dev]'`, service =
   `uvicorn app.main:app --host 0.0.0.0 --port 8000`. The relay has no built-in service
   management — `scripts/mac/install-relay-launchd.sh` writes
   `~/Library/LaunchAgents/org.aethyrion.talaria-relay.plist` (`KeepAlive`, `RunAtLoad`,
   logs to `~/Library/Logs/talaria-relay/`). Mirror the reboot-proof spirit of the OJAMD
   hardening, in launchd terms. Confirm the Mini's existing gateway/shim are also
   boot-persistent while in there; if they're hand-started, give them the same treatment
   (`scripts/mac/install-gateway-launchd.sh`, `scripts/mac/install-shim-launchd.sh` — the
   committed shim plist predates the Talaria-27 checkout and needs re-rendering). This
   closes the reboot-proofing half of #34's scope.
4. **Connector:** `connector/` venv, `hermes-mobile setup --relay-url http://127.0.0.1:8000/v1`
   (connector and relay share the host, loopback is fine) with `CONNECTOR_SETUP_SECRET`
   matching, then `hermes-mobile service install && hermes-mobile service start` (native
   launchd). Verify `hermes-mobile status`, MCP validation, sensor DB present —
   source-verified default `~/.hermes-mobile/sensors.db` (`HERMES_MOBILE_CONNECTOR_HOME`
   relocates the whole home; OJAMD notes show a `state/` subdir layout, so trust
   `hermes-mobile status` for the live paths, not memory).
5. **Restart durability** (no server work needed — #24f is stale as of 2026-07-06): the live
   relay is DB-backed — opaque tokens hashed into `auth_sessions`, devices/push registrations
   as SQLAlchemy rows; there is no JWT signing secret or in-memory registry to lose, and
   persistence is verified across restarts on OJAMD. What carries over to the Mac is hygiene
   only: pin `DATABASE_URL` to an **absolute** sqlite path in the Mac `.env` (config.py
   anchors relative paths to the relay package per GH #59, but absolute removes all ambiguity
   about which DB the LaunchAgent opens), and run one restart-survives-pairing check as part
   of acceptance. The successor concern is #54 (connector WS drop on relay restart, historical
   transient 4401): resolved server-side 2026-07-09 (nonce DB-persisted, race-safe eviction) —
   but verify the launchd-managed connector reconnects after a Mac relay bounce
   (`scripts/mac/verify-phase1.sh --restart-check`), and note the finding on #54.
6. **Pairing for dev:** `hermes-mobile pair-phone` on the Mac, pair the simulator or a dev
   device against the Mac relay. The physical phone stays paired to OJAMD (one active pairing
   per app install — #91 showed the failure mode when identities mix). Testing on the physical
   phone against the Mac = unpair → re-pair, documented as reversible.
7. **Tests:** relay suite (72 passing on OJAMD as of #47 work) and connector suite (101
   passing as of #45) must be green on macOS. Expect near-zero porting friction — upstream is
   macOS-first. Any Windows-specific test guards needed go in per the repo's existing
   skip-marker patterns.
8. **Docs:** `relay/docs/DEPLOY_MAC.md` is the Mac ops runbook (services, ports, recovery
   commands), mirroring the OJAMD ops notes. OPEN_ITEMS #107 tracks T6 Phase 1 with the
   device checklist.

## 4. Phase 2 — Mac-only features (#33 server-side connectors — the actual payoff)

macOS Hermes exposes connectors Windows Hermes can't; per #33/#34 "the host OS is effectively
the feature flag." Scope, in likely order:

- **iMessage (`imsg`)** — requires signed-in Messages, Full Disk Access for the Hermes process
  (chat.db), Automation TCC grants, SMS forwarding from the phone. The Mini already runs
  BlueBubbles, so Messages is signed in — but decide BlueBubbles coexistence (Q2): both read
  chat.db (fine), but two senders can race. Note upstream Hermes now ships Photon iMessage
  (no Mac relay needed) — evaluate `imsg` vs Photon before building; prefer whichever Hermes's
  macOS toolset treats as first-class today.
- **Notes (`memo`)** — Automation TCC.
- **FindMy** — FindMy.app session state.

Each connector's `check_fn` gates it (inert where prerequisites are missing — same reason
they're inert on OJAMD). Verification per connector: prompt Hermes through Talaria chat to
exercise the tool on-device, confirm TCC prompts are granted **for the launchd context**
(LaunchAgent-spawned processes get their own TCC identity — grant against the right binary;
this is the classic macOS trap and deserves an explicit checklist line).

**Optional accelerator** noted in #34: if a connector is wanted on the phone's production
(OJAMD) brain before the Mac becomes primary — `hermes mcp serve` on the Mini → `hermes mcp
add` on OJAMD over the tailnet ("Windows brain, Mac hands"). Cheap, reversible, and lets the
phone use iMessage tools tonight without any re-pairing. Worth doing even if Phase 1 also
proceeds. Runbook section in `DEPLOY_MAC.md`.

## 5. Explicit non-goals (v1)

- Making the Mac the phone's primary host (that's T6 endgame; requires the #1 consolidation
  reversal to be deliberate, not incidental).
  **Update 2026-07-15:** that endgame is now specced as **#114 backend profiles** — the
  deliberate reversal, done as N named profiles rather than a re-point, so OJAMD stays
  production (sensors pinned) while the Mac becomes reachable. Note for that lane: the in-code
  stale `ojamd:8642` default called out below is app-side and lands inside #114's surgery.
- Patching Hermes core (install-script wipes core edits; `config.yaml`/`.env`/skills/sessions
  persist).
- App-side changes. The app already persists its Hermes base URL and relay URL; no
  port-override work is required for this phase (the in-code stale `ojamd:8642` default is a
  separate, known item).

## 6. Acceptance criteria

1. `launchctl list | grep aethyrion` shows relay (+ gateway/shim persistence confirmed) and
   `launchctl list | grep hermes` shows the connector (`ai.hermes.mobile.connector`); all
   survive a Mini reboot.
2. Dev device/simulator paired to the Mac relay: sensors delivering
   (`deliveryState=delivered`, health chunks draining), talk readiness OK, run-completion
   APNs (or documented dev-APNs limitation), Tier-2 file fetch 200.
3. Relay restart does not invalidate pairings (verification, not a fix — restart the relay,
   `/v1/session` succeeds without re-pair) and the connector reattaches without manual
   intervention (note result on #54).
4. Relay + connector suites green on macOS; results noted in the PR.
5. At least one #33 connector callable end-to-end from Talaria chat (e.g., "send an iMessage
   to Shelley: …" → confirm gate → delivered).
6. OJAMD untouched; phone's production pairing unaffected.
7. OPEN_ITEMS updated: new T6-Phase-1 entry (#107) with dated notes; #34 updated; #33
   server-side section updated; #54 annotated with the Mac reconnect finding.

## 7. Questions for Owen — with adopted defaults (2026-07-12)

Repo scaffolding adopted the spec's own recommendations where a default was needed; every one
is a one-line change if Owen decides otherwise.

1. **Scope tonight:** Phase 1 and Phase 2 sequentially, or the "Windows brain, Mac hands" MCP
   bridge (§4) in parallel? *Adopted:* repo supports both — the bridge is documented as an
   independent runbook section (~30 min, no re-pairing, no repo change); execution order is
   Owen's call at the Mac session. Recommendation stands: both.
   **RESOLVED 2026-07-15 (Owen):** Phase 1 + Phase 2 executed sequentially; the bridge was
   NOT built and is not wanted ("no need to build a bridge unless it's necessary") — re-homing
   via the #114 profile switcher is the chosen shape. The bridge section stays documented as a
   fallback only.
2. **iMessage path:** Hermes `imsg` connector, Photon, or keep BlueBubbles as the sender and
   expose it read-only to Hermes? *Adopted:* decision deferred to the Mac session with an
   explicit evaluation step (see runbook Phase 2) — check which path today's macOS Hermes
   treats as first-class, and enforce a single-automated-sender rule to avoid two writers
   racing Messages.
   **RESOLVED 2026-07-15 — evaluation complete, do not re-run.** Findings on Hermes v0.18.2:
   there is no `imsg` *connector* — `imsg` is steipete's standalone brew CLI (v0.13.0), and it
   is the **sender of record**, invoked by the agent via terminal with the full path
   `/opt/homebrew/bin/imsg` (launchd contexts lack /opt/homebrew/bin on PATH). Upstream ships
   no agent-callable send tool by design (toolsets.py: outbound messaging lives outside the
   agent loop) — shelling to a granted CLI is the sanctioned shape; Talaria's #4 confirm gate
   is the human check. **BlueBubbles = reader only** (`gateway/platforms/bluebubbles.py`
   enabled via BLUEBUBBLES_SERVER_URL/PASSWORD, gated `require_mention: true` +
   `send_read_receipts: false` so it never auto-replies to real texts); its webhook feed is the
   future inbound signal. Single-writer rule is satisfied by construction: one sender (imsg),
   BB reads. **Photon REJECTED** (Owen: no adoption plans) — it is a managed *cloud* service
   that allocates its own iMessage lines (`plugins/platforms/photon/`), so it carries the wrong
   identity and touches no Mac session state: the opposite of T6's purpose. TCC: sends need no
   grant; reads need Full Disk Access on the gateway python (uv cpython 3.11 — re-add if
   `hermes update` swaps the runtime).
3. **APNs on the Mac relay:** *Adopted:* copy `AuthKey_ALB34NY384.p8` from `C:\Secrets\apns\`
   to `~/.secrets/apns/` (chmod 600, absolute path in `.env`);
   `APNS_BUNDLE_ID=org.aethyrion.talaria27` (verified against `project.yml` —
   `PRODUCT_BUNDLE_IDENTIFIER: org.aethyrion.talaria27`; OJAMD's `org.aethyrion.talaria` is
   the wrong topic for dev builds of this fork). Note: each push registration carries its own
   bundle/environment, so the env values are fallbacks — set them correctly anyway. Pushes
   silently no-op if the topic doesn't match the registering build.
4. **Branch of record for Mac services:** *Adopted:* `main` (pinned at a known-good commit),
   NOT a `mac-deploy` branch yet — OJAMD needed `ojamd-deploy` because its checkout carried
   uncommitted drift; the Mac starts clean, so don't manufacture a divergence point. The
   runbook documents cutting `mac-deploy` later if deploy-only divergence appears.
5. **Spec placement:** *Answered:* this file.
