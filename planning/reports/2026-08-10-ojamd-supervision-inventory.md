# OJAMD supervision / hardening inventory — the retirement map

**Written 2026-08-10 on OJAMD itself**, from live PowerShell (not the `hermes-ojamd` MCP —
this session runs on the box, so the fabrication caveat does not apply). Every row below was
read from live state: the service control manager, the task scheduler, the Startup folder, and
the filesystem. Canaries on every probe.

**Why this exists:** Owen, mid-session — *"that's all the dang 24f hardening. Now that we're
moving from relay/shim to plugin, you may need to hunt them down for me."* This is the hunt.
It is an **inventory, not a removal**: nothing here was changed. The direction of travel is
DELETION (#223 Lane 5 / #251 Phase 4), and the point of writing it down first is that the
supervision chain has grown enough limbs that removing it piecemeal would orphan something.

---

## 0. The one thing that must NOT be removed

> **`Hermes_Gateway.vbs` in the user Startup folder is the CHAT PLANE's autostart.**
> It is not relay/shim hardening and it is not part of this retirement. Delete it and
> `:8642` stops coming back after a reboot.

This was previously undocumented. CLAUDE.md correctly says the gateway is "NOT a service and
NOT a scheduled task … runs as Owen's user process," but never said **how it starts**. It is:

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Hermes_Gateway.vbs   (2026-06-28)
  -> WScript.Shell .Run(..., 0, False)   # window style 0 = windowless
  -> C:\Users\Owen\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe -m hermes_cli.main gateway run
     with HERMES_HOME, PYTHONIOENCODING=utf-8, HERMES_GATEWAY_DETACHED=1, VIRTUAL_ENV, PYTHONPATH preset
```

Live confirmation of the whole chain this boot: box booted **15:39:40**, gateway PID **37424**
started **15:42:15**, `gateway-starts.log` stamped **15:42:22**, and `gateway_state.json` shows
`api_server: connected` at 15:42:41 — **no Errno-48 headless race on this start** (#264).

Note also it is `python.exe` launched hidden by the VBS, **not `pythonw.exe`** as CLAUDE.md's
prose implies. Cosmetic, but it is what the command line says.

---

## 1. Windows services — NSSM-wrapped (2)

Both are `LocalSystem`, both `StartMode: Auto`, both currently **Stopped** (Owen stopped them
by hand at ~00:05 on 2026-08-10, mid-session).

| Service | Wraps | Listens | Logs to |
|---|---|---|---|
| **`HermesMobileRelay`** | `O:\Hermes\Talaria\relay\.venv\Scripts\uvicorn.exe`<br>`app.main:app --host 0.0.0.0 --port 8000`<br>cwd `O:\Hermes\Talaria\relay` | `:8000` | `O:\Hermes\Talaria\relay\logs\relay.log` (stdout **and** stderr) |
| **`TalariaModelsShim`** | `cmd.exe /c O:\Hermes\Talaria\tools\models-shim\run-shim.cmd`<br>cwd `O:\Hermes\Talaria\tools\models-shim` | `:8765` | `C:\Users\Owen\AppData\Local\hermes\logs\talaria-shim-svc.log` |

Supervisor binary: **`O:\Hermes\nssm\nssm.exe`** (331,264 bytes) — the only file in that tree.
Removing both services makes it dead weight.

### 🔴 The shim StartType finding, now LIVE-CONFIRMED by an actual reboot

CLAUDE.md (model-switching section) records the shim as *"STOPPED but NOT disabled —
`StartType: Automatic` … A reboot RESTARTS it,"* probed 2026-08-09 through the MCP with a
canary. **That prediction has since fired for real.** The box rebooted 2026-08-09 15:39:40 —
after that probe — and the shim came back up listening on `:8765` with nobody calling it,
exactly as predicted. It was still listening when this session opened at 00:03 and only went
quiet because Owen stopped it by hand three minutes later.

**Both services are still `StartMode: Auto`.** The retirement survives a reboot only once
StartType is `Disabled`:

```powershell
Set-Service TalariaModelsShim -StartupType Disabled
```

(Elevation required — Owen pastes. Whether the relay gets the same treatment is a separate
call, since the relay still carries sensors + the `hermes_mobile` MCP tools.)

---

## 2. Scheduled tasks (3) — one live, two disabled legacy

| Task | State | Trigger | Action |
|---|---|---|---|
| **`TalariaConnectorWatchdog`** | **Running** (fires every 60 s; `LastTaskResult 0`) | `MSFT_TaskTimeTrigger` | `wscript.exe //B O:\Hermes\Talaria\scripts\connector-watchdog-launcher.vbs` → `connector-watchdog.ps1` |
| `HermesGateway` | **Disabled** (last ran 2026-06-27) | Boot + Logon | `wscript.exe "C:\Users\Owen\.hermes\scripts\run-gateway-hidden.vbs"` |
| `TalariaModelsShim` | **Disabled** (last ran 2026-06-27, result `267014`) | Boot + Logon | `wscript.exe "O:\Hermes\Talaria\tools\models-shim\run-shim-hidden.vbs"` |

**`HermesGateway` (disabled) is the "conflicting login-only task" CLAUDE.md warns about** —
the artifact `hermes gateway install` creates on Windows. It is disabled, so it is inert, but
it is residue and it is *not* what starts the gateway (§0 is). Keeping a disabled task named
`HermesGateway` next to a standing "do NOT `Start-Service HermesGateway`" rule is an
invitation to misread the box.

**`TalariaModelsShim` exists twice** — as a live NSSM service *and* as a disabled boot/logon
task. Duplicate supervision for one retired component.

### The watchdog's relay-down behaviour is DOCUMENTED and SAFE — not a defect

Observed live this session: from 00:06, every two minutes, `MISS … (1/2)` → `RESTART …
invoking start-connector.bat`. This looks alarming and is not. The script's own `.NOTES`
anticipates it verbatim:

> *"If the RELAY is down, no port-8000 sockets exist at all, so the watchdog will keep invoking
> the bat. That is safe: the single-instance enforcer holds it to one connector, which retries
> until the relay returns."*

Independently confirmed: after five RESTART cycles, exactly **one** connector process existed
(spawned 00:15:05); the 00:07/00:09/00:11/00:13 spawns had all exited. The single-instance
enforcer works as claimed. **No action owed.**

⚠️ **Doc defect found here.** `connector-watchdog.ps1:28` states: *"This script is COMMITTED,
NOT INSTALLED: nothing in this repo executes it. Installing it … is Owen's infra decision."*
It **is** installed and has been running every minute since at least 2026-07-17. The header
never got updated when the decision was made. (#113's 2026-07-25 note already records the task
as verified-installed, so the tracker is right and the script header is the stale copy — the
same downstream-corrected/upstream-stale shape the close-out rule exists to catch.)

---

## 3. Startup folder (2) — one retires, one stays

```
Hermes_Connector.cmd   (2026-06-18)  -> start "" /min cmd /c O:\Hermes\Talaria\scripts\start-connector.bat
Hermes_Gateway.vbs     (2026-06-28)  -> THE GATEWAY. KEEP. See §0.
```

---

## 4. Script surface

### `O:\Hermes\Talaria\scripts\` (in-repo tree)

| File | Role |
|---|---|
| `connector-watchdog.ps1` | the live watchdog (7,017 b) |
| `connector-watchdog-launcher.vbs` | windowless shim the task actually invokes |
| `connector-watchdog.ps1.ojamd-local` | **divergent local copy** (8,016 b) — box-only, not the committed one |
| `start-connector.bat` | connector launcher + single-instance enforcer |
| `start-relay.bat` | pre-NSSM relay launcher |
| `install-nssm-services.bat` | the installer that created §1 |
| `cleanup-stale-users.py` | the 2026-07-06 cleanup — **see §6** |
| `start-connector.bat.bak-20260704`, `start-relay.bat.bak-20260704` | backups |
| `check_ancestors.py`, `update-hermes.ps1` | ancillary |

### `C:\Users\Owen\.hermes\scripts\` (user tree — 22 files)

Denser and more archaeological. Retirement-relevant:

- `restart-relay.ps1` — `Restart-Service HermesMobileRelay` then fires `start-connector.bat`
  (its header confirms the bat is a single-instance enforcer)
- `convert-gateway-shim-to-nssm.ps1` — how §1 came to be
- `remove-nssm-services-20260704.ps1` — **a prior removal script already exists**; useful precedent
- `install-hermes-connector-service.ps1`, `hermes-services.ps1`, `talaria_watchdog.py`
- `run-gateway-hidden.vbs` / `run-gateway.cmd` — the disabled task's targets
- `start-talaria-shim.cmd`
- `hermes-update-safe.ps1` (+ 2 backups) — **CLAUDE.md notes Owen has never used this**; bare
  `hermes update` is his actual practice
- one-off debris: `fix_encoding.py`, `fix_encoding2.py`, `fix_rpc_pump.py`, `qdev.py`,
  `qhost2.py`, `qhost3.py`, `qhosts.py`, `qverify.py`, `connector-win32-chat-running.patch`

### `O:\Hermes\Talaria\tools\models-shim\`

`run-shim.cmd` (+ backup), `run-shim-hidden.vbs`, `shim.py` (+ 2 backups),
`model_options.sample.json`, `README.md`, and `com.aethyrion.talaria.modelsshim.plist`
(the **Mac** launchd unit, sitting in the shared tree).

---

## 5. Logs and data

| Path | Size | Last write | Note |
|---|---|---|---|
| `O:\Hermes\Talaria\relay\logs\relay.log` | **493.9 MB** | 2026-08-10 00:05 | unrotated, timestamp-less; NSSM points both stdout and stderr here |
| `O:\Hermes\Talaria\logs\connector-watchdog.log` | 157 KB | live | **the live connector signal** |
| `O:\Hermes\Talaria\connector\logs\connector.log` | 1.1 MB | **2026-07-02** | DEAD, as CLAUDE.md records |
| `O:\Hermes\Talaria\relay\hermes_mobile.db` | 1.9 MB | 2026-08-10 00:05 | the pairing store — see §6 |

**The forensics gap stands as filed (§12 of the handoff, and it is note-don't-build):** 493.9 MB
unrotated and no Windows event 7036 trace of any service transition. Rotation would be
hardening on a component with a planned end-of-life. **Flagging, not fixing.** The path in the
handoff was slightly off — it is `relay\logs\relay.log`, not `relay\relay.log`; the 493 MB
figure is exact.

---

## 6. What the relay DB says (Z7's OJAMD half — full result in the tracker)

Read-only (`mode=ro`) against a quiescent DB:

- **23 device rows — 2 active, 21 deactivated.** All 23 `installation_id`s distinct (the column
  carries a `UNIQUE` constraint).
- **16 push registrations, 2 active. Zero devices hold more than one active push row** — the
  #133/#143 duplicate-push symptom is **absent**.
- **2 FK orphans**, both `phone_pairing_codes.redeemed_device_id` → deleted `devices` rows
  (2026-06-29 and 2026-07-05). **These are NOT a #285 fix failure.** Both devices are
  **present and active** in `hermes_mobile.db.pre-cleanup-20260706T123923.bak` and absent
  after; `foreign_key_check` goes **0 → 2** across exactly that cleanup. They are
  delete-instead-of-deactivate residue from `cleanup-stale-users.py` on 2026-07-06, a month
  before #285.
- The later pass was done correctly: the 2026-08-03 backup holds 23 devices **all active**,
  live holds 23 with 21 **deactivated**, and `deactivation-rollback-20260803.json` sits beside
  the DB. Deactivate-never-delete with a rollback — #144's shape, honoured.

---

## 7. Suggested retirement order (nothing here has been done)

1. `Set-Service TalariaModelsShim -StartupType Disabled` — smallest, highest value; makes the
   Lane 5 retirement reboot-proof. *(elevated)*
2. Delete the two **disabled** scheduled tasks (`HermesGateway`, `TalariaModelsShim`) — inert
   residue whose only current effect is to make the box misreadable. *(elevated)*
3. Retire the shim service + `tools\models-shim\` once #271's rollout proves the plugin path.
4. Connector/relay last, together, since the watchdog probes the **relay's** port to infer
   **connector** liveness — they cannot be unwound independently. Remove
   `TalariaConnectorWatchdog` and `Hermes_Connector.cmd` in the same sitting as the relay
   service, or the watchdog spends its life firing a bat whose dependency is gone.
5. `nssm.exe` and the script debris last.
6. **Never:** `Hermes_Gateway.vbs`.

---

## 8. Corrections owed upstream (close-out rule)

| # | Home | Correction |
|---|---|---|
| S1 | `CLAUDE.md`, OJAMD services | Record **how** the gateway autostarts (Startup-folder `Hermes_Gateway.vbs`, windowless `python.exe`). Today it says only what it is *not*. |
| S2 | `CLAUDE.md`, model switching | The reboot predicted there **has now happened** (2026-08-09 15:39:40) and the shim did come back. Restamp from prediction to observation. |
| S3 | `CLAUDE.md`, route table | *"NOT verified: OJAMD's table … parity ASSUMED"* is **discharged** — all 37 rows probed live on OJAMD 2026-08-10, plus the `/p/{profile}` mirror. |
| S4 | `connector-watchdog.ps1:28` | "COMMITTED, NOT INSTALLED" is false; it has been an installed 60 s task since ≥ 2026-07-17. |
| S5 | `CLAUDE.md`, connector shapes | OJAMD runs **both** shapes concurrently — bat-launched `hermes-mobile.exe run` *and* two `hermes-mobile-mcp.exe` stdio children. CLAUDE.md frames stdio as Mac-only; #271's rider needs that nuance. |
| S6 | `CLAUDE.md`, OJAMD services | `gateway_state.json` shows **`discord: connected`**. CLAUDE.md says "Discord is one token away" — it is already through the door. |

---

## 9. EXECUTION LOG — 2026-08-15 (added live on the box)

Owen's routing this sitting: **"delete disabled residue only."** Not the NSSM
service registrations, not the models-shim tree, not the relay/connector pair.

### State found, five days after §1–§6 were written — two rows had moved

| §7 step | Status on 2026-08-15 |
|---|---|
| 1. `Set-Service TalariaModelsShim -StartupType Disabled` | **ALREADY DONE.** Live `Get-Service`: relay **and** shim are both `Stopped` / **`Disabled`**. §1's "StartType → Disabled queued this sitting" wording is stale — treat #317's account (stopped AND disabled 2026-08-10) as the accurate one. |
| 2. Delete the disabled scheduled tasks | **All three are `Disabled`, none deleted.** `TalariaConnectorWatchdog` has joined `HermesGateway` and `TalariaModelsShim` in that state — so the two-minute RESTART churn documented in §2 has stopped (last `connector-watchdog.log` line: 2026-08-10 00:36:02). |

### Done this sitting

- **`Hermes_Connector.cmd` removed from the Startup folder.** Contents recorded
  first (`start "" /min cmd.exe /d /c O:\Hermes\Talaria\scripts\start-connector.bat`),
  copied and moved to
  `C:\Users\Owen\AppData\Local\hermes\retired-supervision-20260815\`. Restoring it
  is a `Copy-Item` away.
- **`Hermes_Gateway.vbs` verified still present afterwards** — §0's one
  must-not-remove, checked explicitly rather than assumed.

### Owed — needs elevation, Owen pastes

`Unregister-ScheduledTask` returned **Access is denied** from this unelevated
session (confirmed: `IsInRole(Administrator)` = False).

```powershell
Unregister-ScheduledTask -TaskName HermesGateway -Confirm:$false
Unregister-ScheduledTask -TaskName TalariaModelsShim -Confirm:$false
Unregister-ScheduledTask -TaskName TalariaConnectorWatchdog -Confirm:$false
Get-ScheduledTask -TaskName Hermes*,Talaria* -ErrorAction SilentlyContinue | Select-Object TaskName,State
```

All three are already Disabled, so this changes no behaviour — it removes
residue whose only remaining effect is to make the box misreadable (§2's point
about a disabled task named `HermesGateway` sitting next to a standing "never
`Start-Service HermesGateway`" rule).

### A third MCP copy, found while doing #317 — belongs in this inventory

§1–§3 enumerate services, tasks and Startup entries. They miss a supervisor
that is none of those: **the Hermes Desktop app's own backend.**

```
Hermes.exe (36388, 14:40:35)
  └─ python.exe -m hermes_cli.main serve --host 127.0.0.1 --port 0   (13492)
       └─ .hermes-runtime python  (18048)   ← reads the SAME config.yaml
            ├─ hermes-mobile-mcp.exe  (32204)
            ├─ BlueBubblesMCP, HindsightMCP, PlexMCP, BookStackMCP …
```

It survived the gateway restarts untouched, and it **still holds a live
`hermes-mobile-mcp` child** after `mcp_servers.hermes_mobile` was disabled,
because it read the config at 14:40. **Consequence for any future retirement
step: a `config.yaml` change takes effect per-process, and this box runs three
processes that read that file** (gateway, desktop backend, and the CLI). The
desktop copy self-heals on the app's next launch; nothing was done to it.
