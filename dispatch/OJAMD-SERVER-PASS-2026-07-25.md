# OJAMD SERVER PASS — dispatch for a local Claude Code session on OJAMD

**Written 2026-07-25 from the Mac Mini, by the session that ran the T27 device pass.**
**Run this on OJAMD itself** (Windows, `100.110.102.59`). Everything here needs either local
filesystem access, local process visibility, or the Windows event log — none of it can be done from
the Mac, which is why it was cut out of the device pass rather than guessed at.

Companion documents, both in this repo:
- [`dispatch/RESULTS-T27-DEVICE-PASS-2026-07-25.md`](RESULTS-T27-DEVICE-PASS-2026-07-25.md) — the device pass record
- `handoffs/2026-07-25_t27-device-pass-session1.md` — the pickup summary (gitignored, local only)

---

## Standing rules — read before doing anything

**1. If a check cannot be performed as written, that is a defect in THIS DOCUMENT.** Say so, record
it as a numbered defect, and move on. **Do not improvise a substitute check and record its result as
a pass.** If a substitute is worth running anyway, run it and record it as its **own** result,
explicitly not scoring the original.

This rule is not boilerplate. The device-pass dispatch that preceded this one accumulated **four**
such defects (DOC-1 … DOC-4), three of which described UI paths the app cannot take. All three were
written without checking the app first. **This document was written by that same author.** Assume it
contains the same class of error and report it when you find it.

**2. Record PASS / FAIL / PARTIAL / UNRUNNABLE. Partials are real outcomes — do not round one up.**

**3. Separate VERIFIED from ASSUMED in your own reporting**, the way this document tries to. Every
factual claim below is tagged. Where a claim is tagged ❓ it is genuinely unknown, and establishing
it *is* the task — do not fill the gap by reading a project-knowledge snapshot, which lags. Verify
against live state: port listeners, DB rows, service objects, log files.

**4. Chat and sensors are independent paths.** Never explain a relay/connector symptom with a chat
symptom or vice versa.

**5. Never patch Hermes core.** `curl install.sh | bash` replaces `~/.hermes/hermes-agent` and wipes
core edits. `config.yaml` / `.env` / skills / sessions persist. Anything durable we add lives in our
relay sidecar at `O:\Hermes\Talaria\relay`.

---

## OJAMD ground rules (from CLAUDE.md — treat as load-bearing)

- **Do NOT `Start-Service HermesGateway`.** No such service exists, and its absence does **not** mean
  chat is down. The gateway/API server on `:8642` runs as Owen's user `pythonw` process
  (`hermes gateway run`) and answers ~15–20s after start. Check the port owner instead:
  `Get-NetTCPConnection -State Listen -LocalPort 8642` → `OwningProcess`.
- **Do NOT run `hermes gateway install`** — it creates a conflicting login-only task.
- Use `~/.hermes/scripts/hermes-update-safe.ps1`, never bare `hermes update`.
- `Start-Service` / `Stop-Service` need **elevation**. You cannot do it; **hand Owen the exact
  command to paste**. Diagnosis is fully available to you unelevated — do that first and completely,
  so Owen pastes once rather than five times.
- PowerShell 5.1: `curl` is an alias for `Invoke-WebRequest`. Use `Invoke-RestMethod` or `curl.exe`.
  `Restart-ScheduledTask` does not exist — use `Start-ScheduledTask`.

### Paths

| Thing | Path |
|---|---|
| Relay (our sidecar) | `O:\Hermes\Talaria\relay` |
| Relay DB | `O:\Hermes\Talaria\relay\hermes_mobile.db` |
| Connector launcher | `O:\Hermes\Talaria\scripts\start-connector.bat` (sets `PYTHONUTF8=1`) |
| Connector log | `O:\Hermes\Talaria\connector\logs\connector.log` |
| Connector watchdog | `O:\Hermes\Talaria\scripts\connector-watchdog.ps1` |
| Watchdog log | `O:\Hermes\Talaria\logs\connector-watchdog.log` |
| NSSM | `O:\Hermes\nssm\nssm.exe` |
| Gateway launchers | `C:\Users\Owen\.hermes\scripts\` |
| Shim token | `C:\Users\Owen\.hermes\talaria_shim_token` |
| `HERMES_HOME` | `C:\Users\Owen\AppData\Local\hermes` |

### Services

| Port | What | How it runs |
|---|---|---|
| `:8000` | Relay | NSSM service `HermesMobileRelay` |
| `:8765` | Shim | NSSM service `TalariaModelsShim` |
| `:8642` | Gateway / API server | **NOT a service, NOT a scheduled task** — Owen's user `pythonw` |
| — | Connector | Plain bat-launched process, watched by scheduled task `TalariaConnectorWatchdog` |

---

## What I verified from the Mac, and when

**✅ VERIFIED 2026-07-25 ~15:50 CDT, over Tailscale from `100.79.222.100`:**

| Probe | Result |
|---|---|
| `http://100.110.102.59:8000/v1/health` | **200** `{"data":{"status":"ok"}}` |
| `http://100.110.102.59:8642/v1/models` | **401** — alive, auth-gated |
| `http://100.110.102.59:8765/models` | **401** — alive, auth-gated |

All three ports answer. That is the *entire* extent of what the Mac can see.

**❓ UNCONFIRMED — every one of these is a task below:**
- Which processes own those ports, and whether relay/shim are actually running *as their NSSM
  services* rather than as something someone started by hand.
- Whether the connector is running, and **how many instances**.
- What code version the relay is running (`#85` and `#86` are both marked "OJAMD deploy owed").
- **Why the shim was DOWN and is now UP.** At the 2026-07-25 00:00 preflight, OJAMD `:8765` was a
  connect-timeout with no listener; by ~15:50 the same day it answers 401. **Nobody on the Mac side
  restarted it, and Owen was not asked to.** An unexplained service recovery is as interesting as an
  unexplained service death — see O3.

---

# TASKS

## O1 · Ground truth — what is actually running

**Do this first and completely. Every other task depends on it, and several of the questions below
are cheap only while you are already looking.**

Unelevated, all of it:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8000,8642,8765 |
  Select-Object LocalAddress,LocalPort,OwningProcess |
  ForEach-Object { $_ | Add-Member -NotePropertyName Proc -NotePropertyValue (Get-Process -Id $_.OwningProcess).Path -PassThru }
```

```powershell
Get-Service HermesMobileRelay,TalariaModelsShim | Select-Object Name,Status,StartType
Get-ScheduledTask TalariaConnectorWatchdog | Select-Object TaskName,State
Get-ScheduledTaskInfo TalariaConnectorWatchdog | Select-Object LastRunTime,LastTaskResult,NumberOfMissedRuns
Get-Process | Where-Object { $_.Path -match 'hermes|talaria' } | Select-Object Id,ProcessName,Path,StartTime
```

**Report:** a table of port → PID → executable path; service Status/StartType; watchdog state; and
the full list of hermes/talaria processes **with start times**.

**Specifically answer:**
- Is the `:8000` listener owned by the `HermesMobileRelay` service, or by a hand-started process?
  Same question for `:8765` / `TalariaModelsShim`. **A port answering is not proof the service is
  running it** — that conflation is what made the shim's recovery invisible.
- **How many connector processes are there?** #113's forensics found **two** on 2026-07-23, under
  *different interpreters* (venv python and uv-managed cpython-3.12.11). If there are two again,
  capture both full paths and start times before anything else.

## O2 · #85 and #86 — are they actually deployed?

Both are marked "built in cloud; **OJAMD deploy owed**", and both have been sitting since 2026-07-09.
Nobody has confirmed either way. This is a five-minute grep, not a deployment.

**#86 (relay QueuePool exhaustion) — markers:**

```powershell
Select-String -Path O:\Hermes\Talaria\relay\app\database.py -Pattern 'pool_pre_ping','pool_recycle'
Select-String -Path O:\Hermes\Talaria\relay\app\main.py -Pattern 'DB pool exhausted'
```

**#85 (hermes_delegate MCP path) — markers:**

```powershell
Select-String -Path O:\Hermes\Talaria\relay\app\services.py -Pattern 'build_talk_mcp_url'
Select-String -Path O:\Hermes\Talaria\relay\app\config.py  -Pattern 'TALK_MCP_ADVERTISE'
```

All four present in this repo at `main` as of `3083cc2`, so **absence on OJAMD means not deployed**.

Also capture the deployed checkout's actual position:

```powershell
git -C O:\Hermes\Talaria log --oneline -3
git -C O:\Hermes\Talaria status --short
```

**Report:** deployed / not deployed for each, plus the checkout's HEAD and whether it is dirty. A
dirty deployed checkout is itself a finding — say what is modified.

**Do NOT deploy anything as part of this task.** Report the gap; deploying is Owen's call and may
want its own session. If both are absent, say so plainly and note that #86's fix targets a failure
mode (`QueuePool limit of size 5 overflow 10 reached`) already observed **twice** on this host.

## O3 · #113 — the supervision gap, and the shim's unexplained recovery

**Established already, do not re-derive** (2026-07-23, via the Hermes agent on OJAMD): the
`TalariaConnectorWatchdog` scheduled task is installed and working — 8,405 log lines, 7,242 OK,
582 MISS, 580 RESTART, 0 ERROR, running since 2026-07-17. **The watchdog leg is closed.**

The open question is **"who watches the services"**. NSSM `Automatic` fires at **boot only**, so a
service that dies mid-session has no supervisor at all — which is exactly what happened on
2026-07-23, when relay *and* shim were both found Stopped long after boot, and **nothing alerted**.

**O3a — date the deaths.** The 07-23 stop was bounded only to "between 07-22 13:32 and 07-23 10:00"
because a 40-event window turned up no SCM events. Sweep wider and filtered:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; StartTime=(Get-Date).AddDays(-14)} |
  Where-Object { $_.Message -match 'HermesMobileRelay|TalariaModelsShim' } |
  Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List
```

Relevant IDs: **7000** (failed to start), **7009** (timeout connecting), **7031** (terminated
unexpectedly), **7036** (entered running/stopped state).

**O3b — the new datapoint, and the reason this task exists now.** The shim on `:8765` was **down at
2026-07-25 00:00** (verified from the Mac: connect timeout, no listener) and **up by ~15:50 the same
day** (verified: 401). No one on the Mac side touched it and Owen was never asked to run
`Start-Service`. So either something restarted it, or it was restarted by hand and not written down,
or the machine rebooted.

```powershell
(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
```

If the last boot falls inside that window, the answer is "it rebooted", the NSSM `Automatic`
start did its job, and **the far more interesting question becomes why OJAMD rebooted** — check for
Windows Update activity. If there was **no** reboot, then something restarted an NSSM service
mid-session and we do not know what, which is a *supervision* finding pointing the opposite
direction from 07-23's.

**O3c — the duplicate-connector mechanism.** Unproven candidate from #113: with the relay down there
are no port-8000 sockets, so the watchdog cannot distinguish "connector died" from "relay died" and
relaunches the connector into a void every 2 minutes. 580 relaunches is a lot of chances to beat
`start-connector.bat`'s single-instance enforcer — and the two observed instances ran under
**different interpreters**, which would sail past an enforcer matching on process name or path.

**Read the enforcer's matching criteria first** (in `start-connector.bat`) and say what it actually
matches on. Then say whether the candidate mechanism is consistent with it. **Do not claim the
mechanism is confirmed** unless you can show it; "consistent with, unproven" is a real answer.

## O4 · Push registration state on the PRODUCTION relay

**Why this is on OJAMD and not the Mac:** the phone's active profile is **OJAMD**, so OJAMD's relay
is the one that actually sends its pushes. The 36-registration finding in the device pass was read
off the **Mac Mini's** relay DB. **OJAMD's has never been looked at.** Two open items depend on what
is in it — #133 (registration idempotency) and #143 (the ×4 duplicate-banner report).

Read-only against `O:\Hermes\Talaria\relay\hermes_mobile.db`, table **`push_registrations`**
(columns: `id`, `device_id`, `apns_token`, `push_environment`, `bundle_id`, `is_active`,
`last_registered_at`, `created_at`, `updated_at`).

**Report these five numbers:**
1. Total rows, and rows with `is_active = 1`.
2. **Distinct `apns_token`** count vs **distinct `device_id`** count. On the Mac these were **4** and
   **36** — a 9× identity churn. If OJAMD shows the same shape, the churn is app-side and
   host-independent, which is the single most useful thing this task can establish.
3. Distinct `push_environment` values, with counts. **A mix of `development` and `production` for one
   phone is a finding** — the device-pass preflight recorded OJAMD's relay env as `development` and
   the Mac's as `production`, and a token minted for one environment is rejected by the other.
4. `bundle_id` values present. Expect `org.aethyrion.talaria27`; **anything with the old
   `org.aethyrion.talaria` bundle is stale** and worth calling out (both apps are installed on the
   device — deliberately, per Owen, until the pre-launch rename).
5. Oldest and newest `last_registered_at`.

**Do not delete or deactivate anything.** This is a read. `send_push` fans out per registration with
**no token dedup** ([`relay/app/main.py:1951`](../relay/app/main.py:1951)) and the
`TOKEN_INVALID → is_active = False` path at :2020 has apparently never fired — establishing why is
downstream work, not this task.

**Known and already refuted, so you do not re-run it:** "4 distinct tokens ⇒ ×4 banners" was tested
on the Mac and is **false** — only **1** of 36 sends reached the phone. ×4 has some other cause.

## O5 · #116 OJAMD half — shim token auto-fill

⚠️ **Read this before planning any device steps.** The device pass tried the Mac half and it came
back **UNRUNNABLE (DOC-4)**. The documented path — *forget the pairing, then re-pair by QR* — cannot
establish the check's own precondition:

- `PairingStore.forgetPairing` clears the paired relay configuration and the session. It **does not**
  touch Keychain material. The app says so itself: Delete *"purges Keychain credentials, so it is
  strictly more destructive than Forget Pairing"*.
- The shim token is Keychain material, so it **survives a forget**.
- `ProvisioningService.applyProvisioning` writes the token only when
  `stored.isEmpty || (mode == .refresh && stored != token)`. With a surviving token both clauses are
  false, nothing is written, and **a pass is indistinguishable from a failure**.

Owen confirmed this on device: forgot the Mac pairing, returned to the profile, shim token still
present, models refreshed fine.

**So: do not run the OJAMD half by that path — it will produce the same non-answer.** The OJAMD-side
work that IS runnable and useful is the *host* half, which nobody has checked:

Confirm OJAMD's relay actually publishes a provisioning descriptor at all. Read `hermes_hosts` in
the OJAMD relay DB and report, **for each host row**: `provisioning_data` (present or NULL) and
`provisioning_updated_at`. If present, report `gateway_base_url` and `shim_base_url` verbatim, and
for `shim_token` report **only its length and a sha256 prefix — never the token itself.**

Then check the descriptor against reality: does the token in it authenticate against OJAMD's live
shim (`GET {shim_base_url}/models`, `Authorization: Bearer <token>`)? Does the `shim_token` in the
descriptor match `C:\Users\Owen\.hermes\talaria_shim_token`? Compare by hash, not by printing.

**For reference, the Mac Mini's descriptor is complete and correct** — `gateway_base_url` and
`shim_base_url` both set, `shim_token` byte-identical to the on-disk token, and it authenticates
(HTTP 200, 6 models). That is the known-good shape. If OJAMD's is NULL or partial, **that** is the
#116 finding for this host, and it is a real one — the phone pairs to OJAMD by default.

**One measurement worth taking while you are there:** the Mac's shim took **over 6 seconds** to
answer its first authenticated `/models` after idle, then answered instantly thereafter. Time
OJAMD's first authenticated call after idle. If it is also slow, any probe with a ~5s budget can
report a healthy shim as dead, and that affects more than #116.

## O6 · #117 — health-drain deferral under connector outage

**Moved here from the device pass on 2026-07-25**, where it was **UNRUNNABLE**. The device dispatch
staged the outage by stopping the **Mac Mini's** connector, on the assumption that the Mini is the
sensor destination. It is not — the sensor destination is a **separate persisted setting** from the
active profile, and **OJAMD holds it**. This was disproved empirically, not assumed: with the Mini
connector confirmed dead, a location upload still returned `deliveryState=delivered` and the
on-device panel read DELIVERED · OUTBOX CLEAR, which is impossible for a Mini-bound payload because
`forward_sensor_payload` returns `"retry"` whenever there is no connector session
([relay/app/main.py:636](../relay/app/main.py:636)).

**So the outage has to be staged on OJAMD.** This needs a phone driver as well as the box, so
coordinate with Owen — do not stage it while he is away from the device.

**Precondition:** sensor health collection must be ON on the phone, and **OJAMD must still hold the
sensor-destination badge** (Settings → Server). Confirm both before staging, and record the posture
Owen wants restored.

**Staging (OJAMD):** stop the connector — the plain bat-launched process — and remember the
`TalariaConnectorWatchdog` scheduled task relaunches it every ~2 minutes. **Disable the watchdog task
first or the outage will not hold.** That is the whole point of O3c; if you find the watchdog fights
you here, that is itself a datapoint for #113.

**PATH on the phone:** Settings → **About & Diagnostics** → the sensor diagnostics panel.

- **PASS:** drains **defer** with honest notes ("retries exhausted" / "upload failed"), and the
  backlog is **held** for the next trigger.
- **FAIL:** continuous POST traffic with no backoff — the original no-backoff loop returning.

**Measure retry spacing, not just the panel's summary.** The panel reports a state; the check is
about *backoff*, which only shows up as intervals between attempts. The app logs `drain: starting` /
`→ failed` / `Outbox remaining:` lines at `.notice`, so a corded syslog gives the intervals directly.

**Afterwards: restart the connector, re-enable the watchdog, and verify the connector re-attaches**
(the relay's `hermes_hosts.last_seen_at` should advance). Leaving it down silently is the #113
failure mode this pass exists to characterise.

---

## Not in scope for this pass

Listed so you don't start them by accident, and so nobody thinks they were forgotten:

- **Deploying #85 / #86.** O2 reports the gap only. Deployment is Owen's call.
- **`#21` Tier 2 dual-host device pass.** Needs the phone in hand; belongs with the device pass.
- **`#24e` diagnostics-panel check.** Device-side.
- **Anything requiring elevation.** Diagnose fully, then hand Owen exact paste-ready commands in one
  batch.
- **The `ojamd-deploy` rebase.** The device-pass dispatch referred to it as gating #116's OJAMD half.
  **⚠️ No branch by that name exists** on `origin` or `upstream` as of `3083cc2` — I checked. Either
  it is local to OJAMD, or the reference is stale. **Establish which before acting on it**, and if it
  is local to OJAMD, report its HEAD and how far it has diverged.

---

## Reporting

Write results to **`dispatch/RESULTS-OJAMD-SERVER-PASS-2026-07-25.md`** in the repo, mirroring the
device pass's shape: a summary table first (task → PASS/FAIL/PARTIAL/UNRUNNABLE → one-line note),
then a detail section per task, then a **document defects** section for anything in here that could
not be performed as written.

For each finding, state **what you observed** separately from **what you concluded**, and mark
anything unproven as unproven. The device pass caught two of its own wrong hypotheses that way; both
would otherwise have entered the record as fact.

If something here contradicts what you find on the box, **the box wins** — say so in the results
rather than making the observation fit the document.
