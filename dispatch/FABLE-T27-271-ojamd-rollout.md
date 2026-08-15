# FABLE T27-271 — OJAMD rollout: install the talaria plugin on the production host

**Repo:** `AethyrionAI/Talaria-27` (app) + `AethyrionAI/talaria-plugin` (plugin, private, main @
`fd5d7d1` as of this writing) · **Tracks:** OPEN_ITEMS **#271** (#251 SLICE 2D) · **Parent:** #251 ·
**Roadmap:** #268 · **Adjacent traps:** #264, #113→#188, #288 · **Dispatch date:** 2026-08-09.

This is a **document only** — no production code, no `OPEN_ITEMS.md` edits, no live-install action
taken by the session that wrote it. Everything under "Verified state" was checked read-only, live,
today (grep/`gh api` against this repo and the plugin repo, plus a read-only PowerShell probe run
**by OJAMD's own Hermes agent, at my request, over `mcp__hermes-ojamd`**, which is a channel this
dispatch had that most don't — see the citations below rather than trusting the summary).

**Lead answer: #269 and #270 do NOT block this lane.** #269 (conversational installer — the agent
installs its own plugin so a real user never sees a terminal) and #270 (desktop `plugin.js`
visibility pane) are alternate/future **installation UX for end users**. #271 is Owen, by hand, in
PowerShell — the identical shape already proven on the Mac for Phase 1 (2026-08-05) and Phase 2A
(2026-08-06). Nothing in #269/#270's scope is a technical input to a human running `git clone` +
editing `config.yaml` + restarting a process. The only real ordering question on record — *"Owen's
ordering call against slices B (conversational installer), C (desktop face), D (OJAMD rollout)"*
(`handoffs/HANDOFF-2026-08-06-T27-EVENING.md`) — was Owen picking a PRIORITY among three independent
slices, not a dependency graph; nothing in #251, #269, or #270 states or implies D needs B or C
first, and this dispatch runs D standalone.

## 🔐🔐🔐 THIS IS A LIVE-INSTALL MODIFICATION ON THE PRODUCTION HOST — THE HOST THE PHONE ACTUALLY TALKS TO. NOTHING IN THE "TASK BREAKDOWN" BELOW RUNS WITHOUT OWEN'S EXPLICIT, PER-LANE GO. 🔐🔐🔐

Per CLAUDE.md: *"Anything that MODIFIES a live Hermes install — editing a loaded plugin file, adding
a temporary event type or command, changing `config.yaml` — gets Owen's go for THAT experiment, even
when it is temporary and reverted."* Phase 0 below (recon) is read-only and free by the same rule
("read-only probes... do NOT" need a go). Phase 1 onward is the gated part.

---

## 1. Goal

Install the `talaria` Hermes plugin on OJAMD (the production host, `100.110.102.59:8642`), pair the
phone against it, re-run the 2A device bars there instead of the Mac, and — **only after those bars
re-verify MET** — begin retiring the venv-installed admin tooling the plugin's
`register_cli_command()` replaces. This is the gate on #251 Phase 4 / #223's relay decommission:
*"the relay cannot go until the plugin actually carries the production host."*

---

## 2. Verified state

### VERIFIED (today, live, read-only — sourced per line)

| Fact | Source |
|---|---|
| Both gateways answer, v0.20.0 on both | `mcp__hermes-ojamd__hermes_gateway_health` → `{"status":"ok","version":"0.20.0","base_url":"http://100.110.102.59:8642"}`; `mcp__hermes-mac__hermes_gateway_health` → same version, `127.0.0.1` |
| `hermes --version` on OJAMD | `Hermes Agent v0.20.0 (2026.8.3)`, install dir `C:\Users\Owen\AppData\Local\hermes\hermes-agent`, Python 3.11.15 — ran directly in the OJAMD agent's own shell, no nesting |
| **OJAMD's `HERMES_HOME` = `C:\Users\Owen\AppData\Local\hermes`** | live `powershell -Command 'Write-Output $env:HERMES_HOME'` on OJAMD → exact match |
| **`C:\Users\Owen\AppData\Local\hermes\plugins` already EXISTS and is EMPTY** | live `Test-Path` → `True`; live `Get-ChildItem -Force` → no output |
| **`C:\Users\Owen\.hermes\plugins` does NOT exist** | live `Test-Path` → `False` |
| `config.yaml`'s `plugins:` block is exactly `plugins:\n  enabled: []` (nothing enabled anywhere yet) | live `Get-Content ... -Skip 818 -First 20` dump, confirmed empty two-line block between `platforms:` and `session_reset:` |
| **No `platform_hints:` block exists anywhere in OJAMD's `config.yaml`** | live `Select-String -Pattern platform_hints` → no output. Confirms #271's own "OJAMD platform_hint block still unpasted" note is still true today, not stale. |
| `mcp_servers.hermes_mobile` is registered as a **stdio MCP child process**, `command: O:\Hermes\Talaria\connector\.venv\Scripts\hermes-mobile-mcp.exe`, `enabled: true`, running from the **connector's own `.venv`** | live `Select-String -Pattern hermes-mobile-mcp,mcp_servers,hermes_mobile -Context 2,2`, config.yaml:669-678 |
| `HermesMobileRelay` service: **Running, StartType Automatic** | live `Get-Service` |
| `TalariaModelsShim` service: **Stopped**, but **StartType is Automatic, not Disabled** | live `Get-Service` — see §4 correction below |
| OJAMD's gateway process: PID 31472, `python.exe`, **StartTime 8/5/2026 11:20:48 PM** — no restart since before Phase 1 shipped | live `Get-NetTCPConnection -State Listen -LocalPort 8642` → PID → `Get-Process` |
| `gh` CLI is **NOT installed** on OJAMD (not on PATH in the agent's shell); `git version 2.50.1.windows.1` **is** present | live `gh auth status` → `command not found`; live `git --version` |
| `talaria-plugin` main is at `fd5d7d1`, includes Phase 1 + all of 2A + the **#263(b) fix already merged** (commit `83525ac fix(#263b)…`, ancestor of HEAD) | `gh api repos/AethyrionAI/talaria-plugin/commits/main` and `/commits` list, checked directly against GitHub |
| Plugin has **zero external Python dependencies** — no `requirements.txt`/`setup.py`/`pyproject.toml` in the tree; `tools.py`/`__init__.py` import only stdlib (`asyncio`, `logging`) + internal modules + `ctx.register_platform` at register time | `gh api .../git/trees/main` (file list) + `contents/__init__.py`, `contents/tools.py` read directly |
| Plugin install mechanic is `git clone <repo> <HERMES_HOME>/plugins/talaria` + `plugins.enabled: [talaria]` in config.yaml + gateway restart — no pip step | plugin `README.md`, read directly; corroborated by the dependency-free tree above |
| The 2A bar set, verbatim, and its 2026-08-06 device-pass results on the Mac | OPEN_ITEMS.md lines 8322-8501 |
| OJAMD's operational ask — *"don't retire the relay until the adapter's process story is settled"* | OPEN_ITEMS.md #251, line ~8704 |

### ASSUMED (could not verify from here — what would verify it)

| Assumption | What would verify it |
|---|---|
| Git credentials for the **private** `AethyrionAI/talaria-plugin` repo are set up on OJAMD (PAT via Windows Credential Manager, or an SSH key) | `gh` is confirmed absent, so Owen needs either a cached HTTPS credential or an SSH key already registered with GitHub for this org. Task 1.1 below probes this cheaply and fails loud if missing, before touching anything live. |
| The Talaria app already has (or does not have) a saved "OJAMD" server profile, and what URL scheme it uses (`http://100.110.102.59:8642` per the ATS CIDR exception) | Only checkable on the phone — Settings → Server on device. Not remotely inspectable. |
| Nothing else Owen has touched on OJAMD since 2026-08-05 (gateway hasn't restarted, per the verified StartTime above) has silently drifted `config.yaml` in a way this dispatch's line-`824` assumption misses | Task 0.2 below re-dumps the live `plugins:` block immediately before Task 1.2 edits it — if it has moved or changed shape, STOP and re-diff by hand rather than trusting this document's line numbers. |
| The exact venv-CLI surface #271's title means to retire, beyond the `mcp_servers.hermes_mobile` stdio entry found live | No enumeration of "OJAMD venv CLIs" exists anywhere in the tracker. See §9 Traps — this is deliberately **out of scope** for this lane, not resolved here. |

---

## 3. Preconditions

1. **#269/#270 do not block — see the lead answer above.** Not re-litigated here.
2. **#263 does not block** — its fix (b half) is already on `talaria-plugin` main (verified above);
   a fresh clone on OJAMD gets it automatically. The (a) half stays a WATCH, unrelated to install
   correctness.
3. **Git auth for the private plugin repo must exist on OJAMD before Task 1.1**, or that task fails
   loud and cheap (a failed `git clone` touches nothing). `gh` is confirmed absent; Owen supplies
   either a PAT (git will prompt once over HTTPS and Windows Credential Manager caches it) or
   confirms an SSH key is registered.
4. **The app needs an OJAMD server profile before the device-pass phase (Phase 4 below) can run at
   all.** This is a phone-side, in-app step, not scriptable from here — Owen adds/activates it the
   same way the Mac profile already exists, pointed at `100.110.102.59:8642` with OJAMD's own
   `API_SERVER_KEY` (read from `C:\Users\Owen\AppData\Local\hermes\.env` — never pasted into a
   script or a chat transcript).
5. **#285's fix (branch `claude/t27-285-profile-atomicity`) does NOT need to land first.** It closes
   a *residual* orphan-mint race during profile switching; #288's baseline audit already found the
   exposure window "effectively empty" absent a second paired host. This lane is what **creates**
   that second host, which is exactly why #288 flagged it — but the fix landing first is a
   nice-to-have, not a blocker, because #285 unmerged just means switching between Mac/OJAMD profiles
   during the device pass carries the already-documented, already-bounded orphan-row risk, not a new
   one. Recorded as **Owen's call** in §8 if he wants it merged first anyway.
6. **No `hermes update` as part of this lane.** OJAMD's gateway has been up since 8/5 without a
   restart, so it is tempting to combine "update + restart to pick it up" with "restart to load the
   plugin" — **don't.** Two live changes in one blast radius is exactly what the verification
   discipline this repo runs on forbids. If Owen wants OJAMD updated, that is a separate, dated,
   separately-verified action, before or after this lane, never inside it.

---

## 4. ⚠️ Tracker corrections

**#271's own scope line names the wrong install path.** OPEN_ITEMS.md line 6890 says *"install +
enable `talaria` in `~/.hermes/plugins/` on OJAMD"* — this is the Mac's path, not OJAMD's, and #271
already carries the evidence that contradicts it one screen up in the same file: the #116 sequencing
pass found *"OJAMD's INSTALLED copy lives under HERMES_HOME = `C:\Users\Owen\AppData\Local\hermes` —
NOT a `~/.hermes` path"* (OPEN_ITEMS.md line 3340-3341, re: the skills copy). Today's live probe
confirms the same split for plugins specifically: `C:\Users\Owen\AppData\Local\hermes\plugins`
exists; `C:\Users\Owen\.hermes\plugins` does not. **The correct target is
`C:\Users\Owen\AppData\Local\hermes\plugins\talaria`.** The plugin repo's own `README.md` install
snippet (`git clone <repo> ~/.hermes/plugins/talaria`) is Mac-only-correct for the same reason — it
was written against the Mac install and never adapted for OJAMD's HERMES_HOME split. Recommend the
orchestrator update OPEN_ITEMS.md #271's scope paragraph to name `<HERMES_HOME>` explicitly rather
than the bare `~/.hermes/` form, per the close-out rule (corrections go upstream, to the stale
claim's own home).

**CLAUDE.md's "Model switching" section says the OJAMD `TalariaModelsShim` service "is stopped and
disabled."** Live `Get-Service` today shows `Status: Stopped` but **`StartType: Automatic`**, not
`Disabled`. "Stopped" is accurate; "disabled" overstates it — a reboot would auto-start it again.
Small, not this lane's to fix (touching service StartType is exactly the kind of unrelated live
change §3.6 says not to bundle in), but worth a dated note at CLAUDE.md's own line so the next
reader doesn't repeat the claim as verified fact.

---

## 5. Proposed bars

**The 2A bar set is the template, restated against OJAMD per #271's own instruction (a bar that
lives in two places drifts — this is the OJAMD-worded copy, not a new definition).** Evidence
column cites how each will be checked.

| Bar | Statement | Evidence |
|---|---|---|
| **271-A** (pair, = 2A-A) | Phone, OJAMD profile active, foregrounds → Server screen PLUGIN LINK reads PAIRED with zero manual steps beyond activating the profile. `hermes talaria status` on OJAMD shows the device. | Phone screenshot + Task 4.2 output |
| **271-B** (live query, = 2A-B, restated per the transport-leg correction #271 already records) | With the app open on the OJAMD profile, a forced `talaria_phone_query(kind:"location")` call resolves with **`enqueue_to_drain` under 1s** (the #263-proven transport number), independent of total model turn time. Do NOT re-use the falsified whole-turn ≤5s bar. | `agent.log` timing lines on OJAMD, same instrumentation #263-G used on the Mac |
| **271-C** (durability, exactly-once, = 2A-C) | `hermes talaria send "..."` on OJAMD while the app is closed → gateway restart → app open on the OJAMD profile → item appears in Inbox exactly once, unread pip clears on tap. | Phone screenshot + OJAMD outbox `delivered_at` |
| **271-D** (honest unreachable, = 2A-D) | App closed >60s on the OJAMD profile → forced tool call returns the designed "phone unreachable... do not retry" prose, no throw, no #232 counter movement. | `agent.log` + phone screenshot |
| **271-E** (deletion, = 2A-E) | Not re-run — already MET build-side and does not vary by host. Carried for completeness only. | OPEN_ITEMS.md, 2A-E MET note |
| **271-F** (privacy, = 2A-F) | Health toggle OFF on device, OJAMD profile active → `phone.query(kind:"health")` answers "declined: privacy settings"; toggle ON → real data. | Phone screenshot, both legs |
| **271-G** (gate) | Not re-run per host — `scripts/mac/lane-gate.sh` is a build-side check, host-independent. Carried for completeness only. | Already MET, PR #272 |
| **271-H** (install correctness, OJAMD-specific, NEW) | `git clone` lands exactly at `C:\Users\Owen\AppData\Local\hermes\plugins\talaria`; `hermes plugins list` shows `talaria` **source: git**, enabled; config.yaml's `plugins.enabled` contains `talaria` and nothing else in that block was disturbed (line-count diff against the pre-edit backup shows exactly the intended lines changed). | Tasks 1.1/1.2/1.3 output + Task 3.1 output |
| **271-I** (listener survives the restart, OJAMD-specific, NEW — per #264) | After the gateway restart that loads the plugin, `Get-NetTCPConnection -State Listen -LocalPort 8642` shows a **listener**, not just a healthy-looking PID. Checked twice: immediately after restart, and again 2 minutes later (catches the #264 "came up without the chat plane" shape, which looks fine at PID level). | Task 2.3 output |
| **271-J** (rollback proven, OJAMD-specific, NEW) | The rollback in §7 is actually exercised once, live, before declaring the lane done — not just written down. Deactivating `talaria` from `plugins.enabled` and restarting returns OJAMD to its pre-lane behavior with the phone still able to reach the OJAMD profile via whatever it used before (or an honest "plugin retired" state if the app already switched over — Owen's call which). | A dry-run of Task-set 5 (rollback), executed and its output recorded, before this entry is allowed to close |

271-A/B/C/D/F are device bars (Owen's pass). 271-H/I are build/ops-side and close before the device
pass starts. 271-J closes the lane, after the device pass, as the exit ticket.

---

## 6. Task breakdown — paste-ready PowerShell for Owen

All commands are PowerShell, unelevated unless marked. Run in order; each step names its expected
output and what to do if it doesn't match. **Phase 0 is read-only and needs no go. Phase 1 onward is
gated — do not run past Phase 0 without Owen's explicit "go" for this specific lane.**

### Phase 0 — Recon (read-only, no gate needed, run any time)

**Task 0.1 — confirm the target directory and current config state one more time, immediately
before editing anything (catches drift since this document was written):**

```powershell
Write-Output "HERMES_HOME: $env:HERMES_HOME"
Test-Path "$env:HERMES_HOME\plugins"
Get-ChildItem "$env:HERMES_HOME\plugins" -Force
Select-String -Path "$env:HERMES_HOME\config.yaml" -Pattern "^plugins:" -Context 0,3
```

**Expected:** `HERMES_HOME` = `C:\Users\Owen\AppData\Local\hermes`; `Test-Path` → `True`;
`Get-ChildItem` → no output (empty dir); the context dump shows `plugins:` immediately followed by
`  enabled: []`. **If the `plugins:` block looks different from that** (already has entries, is
nested differently, etc.), STOP — this document's Task 2.2 assumes exactly that two-line shape and
will not be safe to run as written.

**Task 0.2 — confirm git can reach the private plugin repo before committing to the clone:**

```powershell
git ls-remote https://github.com/AethyrionAI/talaria-plugin.git HEAD
```

**Expected:** one line, a commit SHA + `HEAD`. **If this prompts for credentials and you don't have
a PAT handy, stop here and set one up (GitHub → Settings → Developer settings → Personal access
tokens, `repo` scope on a private-repo-capable token) before continuing** — Windows Credential
Manager caches it after the first successful prompt, so this is a one-time setup. If you have an SSH
remote preference instead, use `git@github.com:AethyrionAI/talaria-plugin.git` in Task 1.1 instead of
the `https://` form and confirm `ssh -T git@github.com` works first.

**Task 0.3 — back up the config file (always do this, whether or not Phase 1 runs today):**

```powershell
Copy-Item "$env:HERMES_HOME\config.yaml" "$env:HERMES_HOME\config.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Get-ChildItem "$env:HERMES_HOME\config.yaml.bak-*"
```

**Expected:** a new timestamped `.bak-*` file listed. This is the rollback anchor for §7 — keep it,
don't delete it after Phase 1, it's cheap.

---

### 🔐 STOP — Phase 1 onward modifies the live production install. Confirm Owen's go for THIS lane before continuing. 🔐

### Phase 1 — Clone + enable (the gated step)

**Task 1.1 — clone the plugin to the correct OJAMD path:**

```powershell
git clone https://github.com/AethyrionAI/talaria-plugin.git "$env:HERMES_HOME\plugins\talaria"
Get-Item "$env:HERMES_HOME\plugins\talaria\plugin.yaml"
```

**Expected:** normal clone output ending `Resolving deltas: 100%...`; the second command prints the
file's `LastWriteTime` etc. confirming it landed. **Rollback:** `Remove-Item -Recurse -Force
"$env:HERMES_HOME\plugins\talaria"` — safe, nothing else references this path yet (config.yaml is
still untouched at this point).

**Task 1.2 — enable it in config.yaml.** This targets the exact two-line block confirmed in Task
0.1. Verify the match count is exactly 1 before it writes anything:

```powershell
$cfg = "$env:HERMES_HOME\config.yaml"
$raw = Get-Content $cfg -Raw
$pattern = "plugins:`r?`n  enabled: \[\]"
$matches = [regex]::Matches($raw, $pattern)
Write-Output "Match count: $($matches.Count)"
```

**Expected:** `Match count: 1`. **If it is 0 or more than 1, STOP — do not proceed with the
replace below; edit the file by hand in Notepad instead** (find the `plugins:` block, change
`enabled: []` to:
```
plugins:
  enabled:
    - talaria
```
save, done — skip straight to Task 1.3's verification).

If the match count was exactly 1:

```powershell
$new = $raw -replace $pattern, "plugins:`n  enabled:`n    - talaria"
Set-Content -Path $cfg -Value $new -NoNewline
Select-String -Path $cfg -Pattern "^plugins:" -Context 0,3
```

**Expected:** the context dump now shows `plugins:` / `  enabled:` / `    - talaria`. **Rollback**
(resolves the most recent backup automatically, so there's nothing to fill in by hand):
```powershell
$backup = Get-ChildItem "$env:HERMES_HOME\config.yaml.bak-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $backup.FullName "$env:HERMES_HOME\config.yaml" -Force
```

**Task 1.3 — sanity-check the edit before it reaches a restart.** ASSUMED: a bare `python` on PATH
is not confirmed on OJAMD (hermes-agent runs off a bundled runtime under
`hermes-agent\.hermes-runtime\python\...`, not necessarily a system install) — try it, but don't
block on it if it's missing; the line-count check below is the real gate either way:

```powershell
$backup = Get-ChildItem "$env:HERMES_HOME\config.yaml.bak-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$before = (Get-Content $backup.FullName).Count
$after = (Get-Content $cfg).Count
Write-Output "Backup used: $($backup.Name)"
Write-Output "Lines before edit: $before / after: $after / delta: $($after - $before)"
python -c "import yaml; yaml.safe_load(open(r'$env:HERMES_HOME\config.yaml')); print('YAML OK')" 2>$null
```

**Expected:** the after-edit line count is exactly **2 more** than the backup's line count (the
replace turned one line, `  enabled: []`, into three: `  enabled:`, `    - talaria`, plus the
unchanged `plugins:` line — net +2). `YAML OK` if `python` resolved; if the last command errors with
"not recognized," that's fine, ignore it — the line-count delta is the real check here. **If the
line-count delta is anything other than exactly +2, restore from backup immediately (Task 1.2's
rollback) and do not restart the gateway** — Phase 2's restart is the point of no cheap return until
it's confirmed clean, so catch a bad edit here, not there.

---

### Phase 2 — Restart the gateway and verify the listener (per #264 — never trust the PID alone)

> **⚠️ 2026-08-10 AMENDMENT: Tasks 2.1 and 2.2 as written below are SUPERSEDED — do not
> paste them.** Task 2.1 kills the wrong process (the gateway is a two-process chain and the
> port owner is the CHILD), and Task 2.2's launcher hunt is resolved (it is `Hermes_Gateway.vbs`
> in the user Startup folder). Use the corrected blocks in **§11 (AMENDMENT — 2026-08-10)** at
> the end of this document. Task 2.3 stands as written.

**Task 2.1 — find and stop the current gateway process:**

```powershell
$conn = Get-NetTCPConnection -State Listen -LocalPort 8642
$gwPid = $conn.OwningProcess
Write-Output "Current gateway PID: $gwPid"
Stop-Process -Id $gwPid -Force
Start-Sleep -Seconds 3
Get-NetTCPConnection -State Listen -LocalPort 8642 -ErrorAction SilentlyContinue
```

**Expected:** the last line returns **nothing** (port free). If it still shows a listener on the
same PID, the kill didn't take — do not proceed, investigate before relaunching. (Deliberately named
`$gwPid`, not `$pid` — the latter is PowerShell's reserved automatic variable for the *current*
session's own process ID; overwriting it is a real footgun in a script someone might paste more than
once in the same shell.)

**Task 2.2 — relaunch via the normal login-time launcher** (per CLAUDE.md/the archived #55 recipe —
restarting the desktop app does NOT restart this process; it must go through its own launcher).
**ASSUMED exact script name** — the launcher lives somewhere under `%LOCALAPPDATA%\hermes\` or
`C:\Users\Owen\.hermes\scripts\`; find it once, cheaply, rather than guessing:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\hermes" -Recurse -Filter "*Gateway*" -ErrorAction SilentlyContinue | Select-Object FullName
Get-ChildItem "C:\Users\Owen\.hermes\scripts" -ErrorAction SilentlyContinue | Select-Object Name
```

Run whichever `.vbs`/`.cmd` these list that launches the gateway (per CLAUDE.md, expect something
like `wscript.exe <path>\Hermes_Gateway.vbs` — **confirm the exact name from the listing above before
running it**, don't guess the filename).

**Task 2.3 — verify the LISTENER, not the process, per #264 — check twice, 2 minutes apart:**

```powershell
Start-Sleep -Seconds 20   # gateway takes ~15-20s to warm up
$c1 = Get-NetTCPConnection -State Listen -LocalPort 8642 -ErrorAction SilentlyContinue
Write-Output "Check 1: $(if ($c1) {"LISTENING, PID $($c1.OwningProcess)"} else {"NOT LISTENING"})"
Start-Sleep -Seconds 120
$c2 = Get-NetTCPConnection -State Listen -LocalPort 8642 -ErrorAction SilentlyContinue
Write-Output "Check 2: $(if ($c2) {"LISTENING, PID $($c2.OwningProcess)"} else {"NOT LISTENING"})"
Invoke-RestMethod -Uri "http://100.110.102.59:8642/v1/health"
```

**Expected:** both checks show LISTENING with a **new** PID (different from Task 2.1's), and
`/v1/health` returns `{"status":"ok",...}` or similar 200. **If Check 1 shows NOT LISTENING** — this
is exactly #264's bind-race failure mode: the old process's socket teardown raced the new process's
bind. **Do not panic-restart again immediately** (that's how #264 was first found — it compounds).
Wait the full 2 minutes to Check 2; if still not listening, one more `Stop-Process`/relaunch cycle
(the port is now provably free) resolves it per #264's own precedent ("a second kill... came up
clean").

---

### Phase 3 — Verify the plugin actually loaded

**Task 3.1:**

```powershell
hermes plugins list
```

**Expected:** `talaria` appears, enabled, source **git** (not "local" — confirms it's reading the
clone, not some other copy). Compare against the Mac's known-good Phase 1 output shape if unsure.

**Task 3.2 — CLI smoke, read-only half only (do not pair yet — that's Phase 4, phone-driven):**

```powershell
hermes talaria status
```

**Expected:** runs without error, reports zero devices (nothing has paired against OJAMD yet) or
lists whatever the plugin's device store already has for this host (should be empty — this is a
brand-new store, `<HERMES_HOME>\talaria\devices.json` did not exist before this lane).

**271-H and 271-I close here.** Everything past this point is the phone-driven device pass — Phase
4 is Owen with the phone, not paste-ready commands.

---

### Phase 4 — Device pass (phone-side, mirrors the Mac's 2026-08-06 device pass exactly)

Not PowerShell — recorded here so the bar-to-step mapping is explicit:

1. On the phone, add/activate the **OJAMD** server profile (Settings → Server) —
   `100.110.102.59:8642`, OJAMD's own `API_SERVER_KEY` from its `.env` (read it yourself off the
   box; never paste it into a chat transcript or a script). This is precondition §3.4, done live
   here if not already in place.
2. Foreground the app → **271-A**: PLUGIN LINK reads PAIRED, zero extra steps. Cross-check with
   `hermes talaria status` on OJAMD (now should show the device).
3. Close the app fully → `hermes talaria send "morning"` on OJAMD → reopen → **271-C**: message
   present exactly once, pip clears on tap.
4. App open, force a `talaria_phone_query(kind:"location")` turn → **271-B**: check
   `enqueue_to_drain` in OJAMD's `agent.log`, not total turn time.
5. Privacy → health toggle OFF (master ON) → query → **271-F** denied leg; toggle ON → **271-F**
   allowed leg.
6. Close app >60s → forced query → **271-D**: honest unreachable prose, no throw.

---

### Phase 5 — explicitly NOT part of this lane

**Retiring `mcp_servers.hermes_mobile` (the connector-venv MCP server) and the relay/connector NSSM
services stays OUT of scope here.** See §9 for why. Nothing in Phase 5 gets pasted or run until a
**separate, later, explicitly-gated** lane opens for it — most naturally #223 Phase 4 itself, once
271-A through 271-J are all MET and Owen has lived with the OJAMD plugin for a while.

---

## 7. The rollback plan (as a whole)

Three independent layers, each cheap and each already exercised by precedent on the Mac:

1. **Config-level (seconds):** restore `config.yaml` from the Task 0.3 backup, restart the gateway
   (Phase 2's Task 2.1-2.3 sequence again). This alone fully reverts OJAMD to its pre-lane state —
   `talaria` goes back to un-enabled, the plugin directory sits inert on disk (harmless — Hermes only
   loads what `plugins.enabled` names).
2. **Directory-level (if the clone itself is suspect):** `Remove-Item -Recurse -Force
   "$env:HERMES_HOME\plugins\talaria"` after layer 1's config revert. Nothing else on OJAMD
   references this path — the relay, connector, and `mcp_servers.hermes_mobile` are all completely
   independent of it (verified: the mcp_servers entry points at
   `O:\Hermes\Talaria\connector\.venv\...`, a different tree entirely).
3. **Device-store level (if devices have already paired and something about that state is wrong):**
   `<HERMES_HOME>\talaria\devices.json` — per #144's shape, **deactivate rows, never delete the
   file**; `hermes talaria unpair` is the sanctioned per-device rollback, or restore a copied backup
   of the whole JSON file taken before Phase 4 if a wholesale revert is needed.

**Nothing in Phase 1-3 touches the relay, the connector, or `mcp_servers.hermes_mobile` at all** —
those stay running throughout, unmodified, so even a total rollback of every layer above leaves
OJAMD no worse off than before this lane started. This is the load-bearing property that makes the
whole lane reversible: it is purely additive until Phase 5 (which this dispatch doesn't authorize).

---

## 8. What is OWEN'S to decide

- **Whether to run this lane before or after #285's fix merges** (`claude/t27-285-profile-atomicity`
  is built, awaiting his merge). Not a blocker per §3.5, but he may prefer the belt-and-suspenders
  order.
- **The exact wording/timing of Phase 4 Step 1** (does he want a brand-new OJAMD profile, or does one
  already exist from earlier OJAMD work that just needs reactivating) — unknown from here, phone-only
  state.
- **Whether to fix the `TalariaModelsShim` StartType drift found in §4** while he's in there, or leave
  it — it's unrelated to this lane and §3.6's "don't bundle unrelated live changes" argues for
  leaving it, but it's a one-line `Set-Service -StartupType Disabled` if he wants it closed out same
  session.
- **Timing of Phase 5** (venv-CLI / `mcp_servers.hermes_mobile` / relay retirement) — entirely his
  call, gated on living with the OJAMD plugin for a while and on #223 Phase 4's own routing.
- **Whether the CLAUDE.md correction in §4 and the `#271` scope-line correction get filed as their
  own dated notes or folded into this lane's close-out commit** — this dispatch recommends the
  latter per the close-out rule, but the mechanics (who edits `OPEN_ITEMS.md`) are the orchestrator's
  to execute, not this document's.

---

## 9. Traps

- **#264 — a bounced gateway can come up without the chat plane, looking perfectly healthy at the
  process level.** Phase 2's Task 2.3 exists entirely because of this; do not shortcut it to "PID
  exists, done." The failure mode is silent — `launchctl`/Task-Manager-equivalent shows a live
  process, cron and the plugin's own drain loop keep running, and only the phone (or an explicit
  `/v1/health` probe) notices chat is dead.
- **#113 → #188 — the connector/relay supervision gap is DECLINED, not fixed, and stays that way
  through this lane.** `restart-relay.ps1`'s "restart both, can't tell which is sick" behavior and
  the unrotated, timestamp-free `relay.log` are known, accepted, permanent costs of a component with
  a planned end-of-life. **Do not "helpfully" harden anything here** — the standing rule (CLAUDE.md,
  Owen 2026-08-02) treats every hardening as compounding update friction on something already headed
  for deletion. This lane's whole shape is consistent with that: additive-only, nothing patched.
- **`hermes update` wipes core edits — the plugin survives this by construction, not by luck.** It
  lives at `<HERMES_HOME>\plugins\talaria`, entirely outside `~/.hermes/hermes-agent` (the tree
  `curl install.sh | bash` replaces). `config.yaml`, `.env`, skills, sessions, and now plugins all
  persist across an update; only the `hermes-agent` source tree itself gets wiped. Verified today:
  the plugin has zero external pip dependencies, so there's no venv-inside-the-wiped-tree risk either
  — an update can't even indirectly break it by nuking a shared dependency.
- **The no-harden rule does NOT block this lane — it's the deletion direction the rule exists to
  protect, explicitly called out in #271's own text.** Don't read §9's caution about not hardening
  the relay as an argument against installing the plugin; they're opposite vectors.
- **This lane is what creates the two-paired-host condition #288-C has been waiting on.** #288's
  baseline audit (2026-08-07) found zero orphan device rows and said so explicitly because the
  exposure requires "a profile switch landing mid-drain against a DIFFERENT host" — which needs two
  paired hosts to exist. Today there's one (the Mac). After Phase 4 below, there are two. From that
  point on, **every future profile switch between Mac and OJAMD is a chance to mint an orphan row
  until #285 lands** (or, if #285 has landed by then, is bounded by its documented residual race
  window — see #288's 2026-08-08 update). This isn't a defect in this lane; it's the precondition
  #288-C's re-run has been sitting on. Flag it to whoever owns #288 once Phase 4 completes.
- **The "retire the venv CLIs" line in #271's own title is under-specified, and this dispatch
  deliberately does NOT resolve it.** The only concrete candidate found by live probe is
  `mcp_servers.hermes_mobile` (`O:\Hermes\Talaria\connector\.venv\Scripts\hermes-mobile-mcp.exe`) —
  but that's the **live, currently-in-use** sensor-tool surface (CLAUDE.md: "the relay are retained
  only for sensor ingestion + the hermes_mobile MCP tools"), not a one-off admin script. Disabling it
  is functionally equivalent to a chunk of the relay decommission itself, which #223 Phase 4 already
  gates on 271 being done and Owen deciding the replacement is trustworthy — collapsing that into
  "retire the venv CLIs, day one" would jump the gate. Phase 5 above stays explicitly unscoped rather
  than guessed at.
- **OJAMD's gateway has not restarted since before Phase 1 shipped (verified PID start time
  8/5/2026 23:20).** Not a defect, but worth knowing going in: whatever config drift may exist beyond
  what Task 0.1 re-checks, this process has been serving it unchanged for days. The restart in Phase
  2 is the first fresh read of `config.yaml` in a while — if something else about the file is stale
  or wrong, this lane's restart is what will surface it, not before.

---

## 10. Close-out

**What this unblocks once 271-A through 271-J are MET:**
- **#223 Phase 4 (relay decommission)** — explicitly gated on this: *"the relay cannot go until the
  plugin carries the production host."* This lane is that gate closing, not the decommission itself
  (Phase 5 above stays separate and later).
- **#288-C** (the post-#285-fix orphan-row re-run) — its precondition, "two paired hosts exist,"
  starts being true the moment Phase 4's device pass activates the OJAMD profile. Whoever next
  touches #288 should know the clock on that starts here, not at #285's merge.
- **The Phase-2-slice board (#268's roadmap map)** — 2D moves from NOT STARTED to done, leaving only
  2B (#269) and 2C (#270) open in Phase 2, both independent of this lane's completion per the lead
  answer.

**What this deliberately does NOT close:** the venv-CLI / `mcp_servers.hermes_mobile` retirement
(Phase 5, explicitly deferred), the #263(a) WATCH (unrelated, Mac-observed, still just a watch), and
the CLAUDE.md/`#271`-scope-line corrections in §4 (recommended for the orchestrator to file, not
executed here).

---

## 11. AMENDMENT — 2026-08-10 (written ON OJAMD, live PowerShell, canaried)

**Provenance:** unlike the 2026-08-09 body above (probed through `mcp__hermes-ojamd`), everything
in this section was read directly on the box by a session running on OJAMD itself — no MCP in the
loop, so the fabrication caveat does not apply. **Phase 0 was executed this session and is GREEN**
(Task 0.1: `HERMES_HOME\plugins` exists/empty, `plugins:` block exact two-line shape, match count 1;
Task 0.2: `git ls-remote` exit 0 → `fd5d7d1bad0087…` — credentials already cached, SHA matches this
dispatch's pin; no `platform_hint` block — that rider confirmed still owed; `HERMES_HOME\talaria`
absent — fresh device store). Task 0.3 (config backup) deliberately left to run immediately before
the Phase-1 edit, not earlier.

### 11.1 §2 "Verified state" rows superseded by the 2026-08-09 reboot

The box rebooted **2026-08-09 15:39:40**, after the body above was written. Three rows moved:

| Row above | Now |
|---|---|
| Gateway PID 31472, StartTime 8/5 23:20, "no restart since before Phase 1 shipped" | **PID 37424 (child of 37420), started 2026-08-09 15:42:15**, serving install head `7aecab56db` (reflog-vs-start-time pinned; listener postdates the last checkout — no drift) |
| `HermesMobileRelay` Running / Automatic | **Stopped** (Owen, by hand, 2026-08-10 ~00:05); StartType → Disabled queued this sitting |
| `TalariaModelsShim` Stopped / Automatic | Auto-started by the reboot exactly as §4 warned, then stopped again by Owen; StartType → Disabled queued this sitting |

**§9's last trap is DISCHARGED:** "the restart in Phase 2 is the first fresh read of `config.yaml`
in a while" — no longer true. The 15:42:15 start already read the current `config.yaml` (last write
14:52:33) and came up clean: `gateway_state.json` shows `api_server: connected` at 15:42:41, no
Errno-48. Phase 2's restart re-reads a config the running process has already proven.

**§7's reversibility framing needs one nuance:** with the relay Disabled, "rollback leaves OJAMD no
worse off" now means rollback to a *relay-disabled* baseline. Reversal is one elevated line
(`Set-Service HermesMobileRelay -StartupType Automatic; Start-Service HermesMobileRelay`) — a
conscious call if this lane stalls mid-way, not an accident discovered at the next reboot.

### 11.2 §3.5 / §8 discharged — #285's fix is ALREADY MERGED

`claude/t27-285-profile-atomicity` (tip `4f6da66`) is **fully contained in main**: ahead-of-main
= 0, merged **2026-08-08** as **GitHub PR #281** (`82625c8` "Merge PR #281: a profile switch is an
atomic transport boundary (#285)"). The "built, awaiting his merge" line above was stale the day it
was written. ⚠️ **Number-collision trap:** the adjacent merge `5521260` "Merge PR #285" is a
DIFFERENT lane — GitHub PR #285 = tracker #297's toolless index. Tracker #285 = GitHub PR #281.
Owen's belt-and-suspenders preference is therefore already satisfied on main; the only residual is
build vintage — whether the phone's *installed build* predates the fix — which is a device-side
question outside this lane's scope.

### 11.3 CORRECTED Task 1.3 — the YAML check is real, not skippable

The dispatch assumed bare `python` may lack yaml (true — PATH python is `C:\Python314`, no yaml).
But the hermes venv python has **PyYAML 6.0.3** (verified live). Use it and treat a failure as a
STOP, not a shrug:

```powershell
$cfg = "$env:HERMES_HOME\config.yaml"
$backup = Get-ChildItem "$env:HERMES_HOME\config.yaml.bak-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$before = (Get-Content $backup.FullName).Count
$after = (Get-Content $cfg).Count
Write-Output "Backup used: $($backup.Name)"
Write-Output "Lines before edit: $before / after: $after / delta: $($after - $before)"
& "$env:HERMES_HOME\hermes-agent\venv\Scripts\python.exe" -c "import yaml; yaml.safe_load(open(r'$env:HERMES_HOME\config.yaml')); print('YAML OK')"
```

**Expected:** delta exactly **`+1`** AND `YAML OK`. Either missing → restore from backup (Task
1.2's rollback) and do not restart the gateway.

> **Corrected live 2026-08-10 during execution:** the body's Task 1.3 (and the first version of
> this amendment) said `+2` — an arithmetic slip. The edit turns 2 lines (`plugins:` +
> `  enabled: []`) into 3 (`plugins:` + `  enabled:` + `    - talaria`): net **+1**. The
> execution run measured +1, tripped the as-written gate, and settled it the honest way — a full
> `Compare-Object` content diff of backup vs live showing exactly one removed and two added
> lines, nothing else. That content diff is the better gate; prefer it over line arithmetic.

### 11.4 CORRECTED Task 2.1 — the gateway is a TWO-PROCESS chain; kill both, parent first

Found live: `Hermes_Gateway.vbs` launches `venv\Scripts\python.exe -m hermes_cli.main gateway run`
(PID 37420), which re-execs a **child** on the bundled runtime interpreter
(`.hermes-runtime\...\python.exe`, PID 37424) — and **the child owns `:8642`**. The original Task
2.1 takes the port owner's PID and kills only the child, leaving the parent alive — which can
respawn or linger holding state, manufacturing exactly the #264 bind-race Task 2.3 defends against.

```powershell
$conn = Get-NetTCPConnection -State Listen -LocalPort 8642 -ErrorAction Stop
$childPid = $conn.OwningProcess | Select-Object -First 1
$child = Get-CimInstance Win32_Process -Filter "ProcessId=$childPid"
$parentPid = $child.ParentProcessId
$parent = Get-CimInstance Win32_Process -Filter "ProcessId=$parentPid"
Write-Output "child  (port owner): PID $childPid  $($child.CommandLine)"
Write-Output "parent            : PID $parentPid  $($parent.CommandLine)"
if ($parent.CommandLine -match 'gateway run') {
    Write-Output "parent confirmed as gateway launcher - stopping parent first, then child"
    Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $childPid  -Force -ErrorAction SilentlyContinue
} else {
    Write-Output "parent is NOT a gateway process - stopping only the port owner"
    Stop-Process -Id $childPid -Force
}
Start-Sleep -Seconds 3
Write-Output "--- survivors check (must be EMPTY on both) ---"
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'hermes_cli\.main gateway run' } |
  Select-Object ProcessId, @{n='Cmd';e={$_.CommandLine.Substring(0,[Math]::Min(100,$_.CommandLine.Length))}}
Get-NetTCPConnection -State Listen -LocalPort 8642 -ErrorAction SilentlyContinue
```

**Expected:** both survivor checks print nothing — no `gateway run` process of either flavor, port
free. **If any survivor remains, stop and investigate before relaunching** (relaunching over a
survivor is the #264 shape). `gateway.pid`/`gateway.lock` in HERMES_HOME will briefly go stale —
the relaunch overwrites them; no manual cleanup.

### 11.5 CORRECTED Task 2.2 — the launcher is known; no hunt needed

The gateway's autostart is **`Hermes_Gateway.vbs` in the user Startup folder** (found and read
live 2026-08-10; full chain documented in
`planning/reports/2026-08-10-ojamd-supervision-inventory.md` §0 — it presets HERMES_HOME,
PYTHONIOENCODING, HERMES_GATEWAY_DETACHED=1, VIRTUAL_ENV and PYTHONPATH, then runs the venv python
windowless). Relaunch is one line:

```powershell
wscript.exe "C:\Users\Owen\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Hermes_Gateway.vbs"
```

Then proceed directly to Task 2.3 exactly as written in the body (listener check at +20s and
+140s, then `/v1/health`).

### 11.6 Also corrected while here

- **§4's CLAUDE.md correction is ALREADY APPLIED** — current CLAUDE.md reads "STOPPED but NOT
  disabled — StartType: Automatic". Do not re-file. (The #271 scope-line correction in
  OPEN_ITEMS.md is still owed.)
- **`gh` IS present on the box.** §2's verified-state row says *"`gh` CLI is NOT installed on
  OJAMD (not on PATH in the agent's shell)"* — true as stated, but it misled: `gh version
  2.97.0` resolves fine in a normal PowerShell session on OJAMD (used 2026-08-15 to open the
  lane's PR from the box). **The Hermes agent's shell PATH is not the box's PATH** — do not
  generalize "the agent can't find it" into "it isn't installed."
- **#288-C has a fresh dated baseline** as of 2026-08-10: 23 device rows / 2 active / 2 FK orphans
  with a proven pre-#285 cause (the 2026-07-06 `cleanup-stale-users.py` delete-instead-of-
  deactivate — both orphan-referenced devices present+active in
  `hermes_mobile.db.pre-cleanup-20260706T123923.bak`, FK violations 0→2 across that cleanup).
  Whatever Phase 4 mints is diffable against that count.
