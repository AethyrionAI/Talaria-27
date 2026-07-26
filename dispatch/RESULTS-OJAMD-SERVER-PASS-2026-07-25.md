# RESULTS — OJAMD SERVER PASS, 2026-07-25

**Run on OJAMD itself** (Windows, `100.110.102.59`), unelevated, 2026-07-25 ~23:20–23:45 CDT.
Dispatch: `dispatch/OJAMD-SERVER-PASS-2026-07-25.md` (handed in as prompt; not committed to this repo).
Companion: [`dispatch/RESULTS-T27-DEVICE-PASS-2026-07-25.md`](RESULTS-T27-DEVICE-PASS-2026-07-25.md).

Nothing was deployed, restarted, stopped, deleted or deactivated. All DB access was read-only
(`file:…?mode=ro`). No elevation was used and none was needed.

---

## Summary

| Task | Result | One-line |
|---|---|---|
| **O1** ground truth | **PASS** | All three ports owned by their expected supervisors; **exactly ONE connector** (3 processes, 2 interpreters — a trampoline chain, not duplicates) |
| **O2** #85 / #86 deployed? | **PASS** | **Both ARE deployed and live** — all four markers present, sources predate the running process. OPEN_ITEMS "deploy owed" is stale |
| **O3a** date the deaths | **UNRUNNABLE** | Event 7036 is logged **zero** times for **any** service on this host; zero SCM events for either service in 14 days. Data does not exist — see DOC-2. Substitute recorded separately |
| **O3b** shim recovery | **PARTIAL** | **No reboot** (up 9 days). Shim *service* started 2026-07-24 23:45:34 — i.e. **15 min BEFORE** the "down at 00:00" preflight. Premise contradicted; cause of the start still unknown |
| **O3c** duplicate-connector mechanism | **PARTIAL — half confirmed, half refuted** | Watchdog genuinely cannot distinguish relay-down from connector-down (**observed**, 4 restarts into a void on 07-24) — but the enforcer matches **CommandLine**, catches all interpreters, and **held at exactly 1 connector** |
| **O4** push registration state | **PASS** | 15 rows / 12 active / 9 tokens / 14 devices. One token fans out **×5 right now**. New: a **53 ms duplicate-insert race**, and a **dev-vs-prod contradiction between tables** |
| **O5** shim provisioning (host half) | **PASS** | Descriptor complete; `shim_token` **byte-identical** to the on-disk token; authenticates (HTTP 200). Latency finding is **not** the shim — see below |
| **O6** health-drain deferral | **PARTIAL** | **Ran 2026-07-26 00:53–01:24, 27-min outage, Owen driving the phone.** Deferral + backlog integrity **PASS** (202s throughout, nothing dropped, clean full drain); **backoff FAILS by decay** — retry rate climbs to **126% of baseline** |

**Headline corrections to the record:**
1. **#85 and #86 are deployed.** They have been since 2026-07-20. The OPEN_ITEMS "OJAMD deploy owed" note is wrong.
2. **There is no duplicate-connector problem.** What #113 saw is what one healthy connector looks like.
3. **The shim is not slow.** It answers in 6–12 ms. The ~4.1 s is hostname resolution of `ojamd`, measured on-box.
4. **OJAMD did not reboot.** Uptime is 9 days.
5. **#117's backoff decays rather than holds.** The `2→4→8 s` ramp is intact, but the rest between
   bursts collapses ~200 s → ~15 s, so retry traffic ends up **above** the healthy baseline. A short
   outage test passes; a long one fails.

---

## O1 · Ground truth — PASS

### Port → PID → executable

| Port | Listener PID | Owning supervisor | Chain (verified by ParentProcessId) |
|---|---|---|---|
| `:8000` relay | 7856 | **`HermesMobileRelay` service** (nssm PID 85704) | 85704 `nssm.exe` → 87008 `uvicorn.exe` → 59652 `python` → **7856** |
| `:8765` shim | 91212 | **`TalariaModelsShim` service** (nssm PID 90136) | 90136 `nssm.exe` → 92320 `cmd.exe` → 70536 `python` → **91212** |
| `:8642` gateway | 84056 | **Owen's user process, not a service** | 86640 `venv\python -m hermes_cli.main gateway run --replace` → **84056** (runtime cpython-3.11) |

**Answering the dispatch's specific question:** yes — both listeners trace by parent chain to their
NSSM service PIDs. Neither is hand-started. `services.exe` (PID 1608) is the parent of both
`nssm.exe` processes, so both were started by the SCM.

Service state: `HermesMobileRelay` Running/Automatic, `TalariaModelsShim` Running/Automatic. Both
run as **LocalSystem** (which is why their `CommandLine`/`ExecutablePath` read empty to an
unelevated query — not a fault).

Watchdog task `TalariaConnectorWatchdog`: State **Ready**, LastTaskResult **0**, MissedRuns **0**,
running as **Owen / Interactive / Limited**, cadence **PT1M (every 1 minute)**.

### How many connectors? — **ONE**

```
76272 cmd.exe /c start-connector.bat
  └─ 66784 hermes-mobile.exe run                          (.venv\Scripts)
       └─ 79668 python.exe  …\.venv\Scripts\python.exe  …hermes-mobile.exe run
            └─ 49176 python.exe  …uv\python\cpython-3.12.11…  …hermes-mobile.exe run
```

All three created at the **same second** (2026-07-24 21:53:11) in a single parent→child chain.

**Observed:** one launcher, one process tree, two distinct interpreters inside it.
**Concluded:** the venv `python.exe` is a *trampoline* that re-execs the uv-managed
`cpython-3.12.11`. A connector in normal health presents as three processes spanning two
interpreters. This is directly relevant to O3c.

The two `hermes-mobile-mcp.exe` trees (86580→86748→81060, parent PID 7648; and 70664→59720→75956,
parent PID 84056) are **MCP servers**, one set per Hermes host process — expected, and correctly
excluded from the enforcer by its `-notlike '*mcp*'` clause.

---

## O2 · #85 and #86 — PASS, both deployed

| Item | Marker | File:line | Present |
|---|---|---|---|
| #86 | `pool_pre_ping=True` | `relay/app/database.py:25` | ✅ |
| #86 | `pool_recycle=1800` | `relay/app/database.py:26` | ✅ |
| #86 | `"DB pool exhausted while handling %s %s — pool: %s"` | `relay/app/main.py:319` | ✅ |
| #85 | `def build_talk_mcp_url(...)` | `relay/app/services.py:1553` | ✅ |
| #85 | `talk_mcp_advertise` | `relay/app/config.py:96,158` | ✅ |

**All four present → both deployed.**

**They are also *live*, not merely on disk:** `database.py` / `main.py` / `services.py` all have
mtime **2026-07-20 23:19:37**, which precedes the relay service start (**2026-07-24 21:53:26**). The
running process loaded this code.

### Deployed checkout

- Path `O:\Hermes\Talaria`, branch **`ojamd-deploy`**, HEAD **`3036e7d`** (2026-07-20 23:36:50).
- **Tracked tree is clean** — `git diff --name-only` is empty. The 21 `??` entries are untracked
  operational files (logs, `.db-wal`/`.db-shm`, the `start-*.bat` launchers, `run-shim*.vbs`,
  `connector-watchdog.ps1.ojamd-local`, scratch scripts). No tracked file is modified.
- **192 behind / 2 ahead** of `t27/main` (`c13bdc7`). The 2 ahead are `d6bd83d` (the #113
  watchdog BOM fix) and `3036e7d` (its OPEN_ITEMS note) — **still un-upstreamed**.

### The `ojamd-deploy` branch question (dispatch flagged it as possibly stale)

**It exists and is local to OJAMD.** The deployed checkout is *currently on it*. It is not on
`origin` (which here is `dylan-buck/Hermes-iOS`), nor on `t27`. Related refs on the box:
`backup/ojamd-deploy-pre-rebase-20260720`, `fix/issues-9-13-ojamd-helpers`,
`remotes/t27/ojamd/update-hermes-helper`. Divergence as above: **192 behind, 2 ahead**.

### Bonus — does #86 actually close the failure mode? *(not asked; found while grepping)*

`relay.log` contains **two** `QueuePool limit of size 5 overflow 10 reached` tracebacks.

- **Observed:** the traceback frame reads `main.py", line 1999, in hosts_websocket`. In the
  *currently deployed* `main.py`, line 1999 sits inside `send_push` (which begins at 1952);
  `hosts_websocket` is at **2341**.
- **Concluded:** those tracebacks were emitted by an **earlier** `main.py` and therefore predate
  the deployed code. (`relay.log` carries **no timestamps at all**, so this line-number mismatch is
  the only dating evidence available — see DOC-2.)
- **Unproven / flagged:** #86's deployed fix adds `pool_pre_ping` + `pool_recycle` only. **It does
  not raise `pool_size` (5) or `max_overflow` (10)** — the exact ceiling the error names. It
  mitigates *stale-connection* wedging; it does **not** raise the concurrency ceiling. Whether the
  failure mode can recur under genuine concurrency is **not established** by this pass.

---

## O3 · Supervision gap

### O3a — date the deaths: **UNRUNNABLE as written**

Ran the 14-day filtered sweep. Result: **zero** events naming `HermesMobileRelay` or
`TalariaModelsShim`.

This is not an empty-but-valid result — I verified the data does not exist:

- System log holds **35,500 records** back to **2026-02-01** (20 MB, Circular). **Not rolled.**
- **115** SCM events in the last 14 days, so SCM logging works.
- Breakdown: `7045`×64, `7040`×35, `7034`×4, `7026`×3, `7000`×2, `7009`×2, `7031`×2, `7011`/`7023`/`7024`×1.
- **`7036` appears ZERO times — for any service.** That is the "entered the running/stopped state"
  event, and it is the *only* one that records a clean start/stop transition.
- The `7031`s are **Razer Chroma SDK Server**; the `7000`/`7009`s are **Steam Client Service**.
  (Messages render blank under `Get-WinEvent` here; service names extracted from event XML `param1`.)

**Conclusion:** the event log physically cannot date these deaths on this host. Recorded as
**DOC-2**. Not scored as a pass.

### Substitute check — recorded as its own result, explicitly NOT scoring O3a

`services.exe` spawns `nssm.exe` when a service starts, so **`nssm.exe` creation time = service
start time**. That is available and exact:

| Service | nssm PID | Service started |
|---|---|---|
| `HermesMobileRelay` | 85704 | **2026-07-24 21:53:26** |
| `TalariaModelsShim` | 90136 | **2026-07-24 23:45:34** |

Both are **8 days after boot**, so both were restarted mid-session. This substitute answers *when*
but says nothing about *why* — no crash-vs-manual distinction is recoverable.

### O3b — the shim's recovery: **PARTIAL, and the premise is contradicted**

**Observed:**
- `LastBootUpTime` = **2026-07-16 17:45:07**. Current time 2026-07-25 23:23. **Uptime ~9 days.**
- OJAMD timezone **Central Standard Time (UTC-6)** — same zone as the Mac's CDT observations.
- `TalariaModelsShim` service started **2026-07-24 23:45:34 local**.

**Concluded:**
1. **It was not a reboot.** The dispatch's branch — "if last boot falls inside that window, it
   rebooted" — is closed: it did not. So the interesting follow-up about *why OJAMD rebooted* does
   not arise, and no Windows Update check is warranted.
2. **The dispatch's premise does not survive contact with the box.** The shim service was already
   running at **2026-07-24 23:45:34**, which is **15 minutes before** the stated "2026-07-25 00:00"
   preflight that found no listener. Both machines are Central. Per the standing rule that the box
   wins: **the shim service was up at 00:00.**

   Three readings, none proven: (a) the preflight's "00:00" label is approximate or the probe ran
   earlier than labelled; (b) the probe timed out for a reason other than a dead listener — note
   that a hostname-based probe on this box costs **4.1 s** (see O5), so a short-budget probe would
   report a healthy shim as dead; (c) something stopped and restarted it inside the window. I
   cannot discriminate — the 7036 gap (O3a) removes exactly the evidence that would.
3. **What restarted it remains unknown.** SCM started it (parent is `services.exe`), but SCM logs
   nothing to say whether that was NSSM auto-restart, a manual `Start-Service`, or a recovery
   action. This *is* still a supervision finding: a service transition happened and left **no
   auditable trace**.

### O3c — duplicate-connector mechanism: **half CONFIRMED, half REFUTED**

**The enforcer's actual matching criteria** (`O:\Hermes\Talaria\scripts\start-connector.bat` line 7
— all line numbers in this document refer to the **deployed** checkout on `ojamd-deploy`, which is
192 commits behind `t27/main`, so they will not match this repo's copies):

```powershell
Get-WmiObject Win32_Process | Where-Object {
    $_.CommandLine -like '*hermes-mobile*run*'
    -and $_.CommandLine -notlike '*mcp*'
    -and $_.CommandLine -notlike '*bash*'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

It matches on **`CommandLine`** — **not** on process name and not on executable path.

**Tested against the live processes.** All three connector processes match, including the
uv-managed one, because its command line still contains `…hermes-mobile.exe" run`:

| PID | Interpreter | Matches enforcer? |
|---|---|---|
| 66784 | `hermes-mobile.exe` | ✅ would be killed |
| 79668 | `.venv\Scripts\python.exe` | ✅ would be killed |
| 49176 | `uv…cpython-3.12.11\python.exe` | ✅ would be killed |

**REFUTED:** the dispatch's candidate mechanism assumed the enforcer matches "process name or
path", letting a different interpreter "sail past". It does not — `argv[0]` is irrelevant to a
`CommandLine` match, and the uv process is caught. (The watchdog runs as **Owen**, and the
connector runs as **Owen**, so `Get-WmiObject` can read those command lines — the match is not
silently defeated by permissions either.)

**CONFIRMED — the first half is real, and I have direct evidence of it happening.**
`Test-ConnectorAttached` proves liveness via `Get-NetTCPConnection -State Established -LocalPort
8000` filtered to local peers. **If the relay is down there are no port-8000 sockets at all**, so
the watchdog reads "connector missing" and fires the launcher into a void. The watchdog log shows
exactly this on 2026-07-24:

```
21:43:04 MISS  no local connector socket on port 8000 (1/2)
21:46:26 RESTART …invoking start-connector.bat
21:50:02 MISS   …
21:51:31 RESTART …
21:52:06 ERROR  watchdog check failed: file in use by another process
21:52:15 MISS   …
21:52:25 RESTART …
21:52:25 MISS   …
21:53:04 RESTART …
```

Four restarts in ten minutes, ending the moment the relay came back (relay service start
**21:53:26**).

**This behaviour is already documented as intentional** — `connector-watchdog.ps1` lines 44–48 say
so verbatim: *"If the RELAY is down, no port-8000 sockets exist at all, so the watchdog will keep
invoking the bat. That is safe: the single-instance enforcer holds it to one connector."*

**And the enforcer did hold:** through four restarts, the box today has **exactly one** connector
chain. So the design's own safety claim was empirically exercised on 07-24 and it worked.

**Reinterpretation of #113's forensics — PLAUSIBLE, UNPROVEN.** I cannot observe what ran on
2026-07-23. But the shape #113 reported — "two connector processes under different interpreters"
— is *identical* to the normal healthy chain (O1). The most economical reading is that the 07-23
observation counted the trampoline parent and its child as two instances. I mark this as
**unproven**: it is consistent with everything on the box today, and it is not demonstrated.

**Watchdog log numbers do not match the dispatch, and here is why:** the dispatch cites 8,405
lines / 7,242 OK / 582 MISS / 580 RESTART. The live log has **1,925 lines / 1,916 OK / 4 MISS /
4 RESTART / 1 ERROR**, starting **2026-07-24 15:23:03**. The script **rotates at 512 KB keeping one
predecessor**; `connector-watchdog.log.1` (524,310 bytes, last written 2026-07-24 15:22:04) holds
the cited history. **Current supervision health is good** — 4 restarts total, all inside the single
07-24 relay outage, and none since.

---

## O4 · Push registration state on the PRODUCTION relay — PASS

Read-only against `O:\Hermes\Talaria\relay\hermes_mobile.db`, table `push_registrations`.
Schema matches the dispatch exactly (9 columns).

### The five numbers

| # | Question | OJAMD | Mac (for contrast) |
|---|---|---|---|
| 1 | total rows / `is_active=1` | **15** / **12** (3 inactive) | 36 |
| 2 | distinct `apns_token` / distinct `device_id` | **9** / **14** | 4 / 36 |
| 3 | `push_environment` | **`development` ×15** (uniform) | `production` |
| 4 | `bundle_id` | `org.aethyrion.talaria27` ×8, **`org.aethyrion.talaria` ×7** | — |
| 5 | `last_registered_at` range | **2026-07-01 00:05:16 → 2026-07-25 19:33:53** | — |

**On the churn shape (the dispatch's "most useful thing this task can establish"):** OJAMD shows
**9 tokens / 14 devices ≈ 1.6×**, not the Mac's 4 / 36 ≈ 9×. **Concluded:** the churn is *present
on both hosts but far milder here*, so it is **not** a host-independent constant. The Mac's 9× is
inflated by something specific to that host or to the re-pairing volume it saw. Marked as an
observation; I did not investigate the Mac.

### The fan-out, right now

`send_push` iterates active registrations with no token dedup (deployed
`relay/app/main.py:2000`, loop body 2000–2022), so **one push = 12 APNs requests** today:

| Token | Active rows | Bundle |
|---|---|---|
| `950b8321…` | **×5** | talaria27 |
| `26abbbf3…` | ×2 | talaria27 |
| `538df57d…` | ×1 | talaria27 (iPad) |
| 4 others | ×1 each | **`org.aethyrion.talaria` (old bundle)** |

**This reconfirms #143's 2026-07-23 root cause independently and shows it is still live.**

**Timeline of the ×5 token — this reconciles the ×4 and ×5 figures in the record:**

| Row | Created | Multiplier after |
|---|---|---|
| 1 | 2026-07-06 20:52:11 | ×1 |
| 2 | 2026-07-08 18:51:20 | ×2 |
| 3 | 2026-07-10 23:28:43 | ×3 |
| 4 | **2026-07-11 02:31:39** | **×4** |
| 5 | **2026-07-11 16:03:11** | **×5** |

**Concluded:** the multiplier passed through exactly **×4** for ~13.5 hours on 2026-07-11 and has
been **×5** since. #146's ×4 screenshot and #143's "×5" title are both consistent with one
monotonically growing fan-out — no contradiction between them.

### NEW — #133: registration is not idempotent even on the exact same pair

```
device b1a53673… + token 26abbbf3…  →  2 rows
  row 63042139-fb74-4eaf-ad0b-22df59b31f82  created 2026-07-24 00:01:11.027353
  row f9bbdb1f-495d-4079-b421-c0c1c407d062  created 2026-07-24 00:01:11.080978
```

**Observed:** two rows, same `device_id` **and** same `apns_token`, created **53 milliseconds
apart**, both `is_active=1`.

**Concluded:** this is a **concurrency race**, not a keying mistake — two registration requests
raced a check-then-insert with no DB-level uniqueness. **Implication for the #143 fix shape:** the
proposed *(b)* "deactivate prior registrations at registration time" is insufficient on its own,
because it is the same check-then-act that just lost this race. **Fix *(c)* — the partial unique
index on active `apns_token` — is load-bearing**, not optional polish.

### NEW — dev/prod contradiction *between tables* on the same host

- `push_registrations.push_environment` = **`development`** for all 15 rows.
- `devices.environment` = **`production`** for all 22 rows.

The relay picks its APNs endpoint from the registration
(`apns.py:100` → `api.sandbox.push.apple.com` when not `"production"`), so **every push from OJAMD
goes to the APNs sandbox**, while the device table asserts those same devices are production.

**Concluded:** these two app-reported fields disagree, on the same host, for the same handsets.
**Unproven:** which one reflects the real signing environment, and whether this is *the* cause of
the Mac's "1 of 36 delivered". I did not send a push and did not attempt to. Flagged as a strong
lead, not a verdict.

### NEW — why `TOKEN_INVALID → is_active=False` has never fired

`apns.py:173` returns `TOKEN_INVALID` **only on HTTP 410 Gone**. The five rows sharing token
`950b8321…` all carry the *same still-valid* token, so APNs answers **200** for each. There is
nothing for the deactivation path to act on — the rows are duplicated, not invalid. A
topic/environment mismatch would return **400**, which `apns.py:181` logs and discards without
deactivating. **The cleanup path cannot ever reap these rows.** This answers the dispatch's
"establishing why is downstream work" as a by-product.

### Stale-bundle rows

**4 active registrations still carry `org.aethyrion.talaria`** (the pre-rename bundle) and receive
fan-out on every send. Both apps are deliberately installed pending the rename, so this is
expected-but-costly: it is 4 of the 12 delivery attempts per push.

*Nothing was deleted or deactivated. This was a read.*

---

## O5 · #116 OJAMD half — PASS (host half)

I did **not** attempt the device path. The dispatch is correct that it is a non-answer, and the
device pass already recorded it as UNRUNNABLE (DOC-4 there).

### The descriptor is complete and correct

`hermes_hosts` — exactly **one** host row (`77a4a34a-…`):

| Field | Value |
|---|---|
| `provisioning_data` | **PRESENT** (140 bytes) |
| `provisioning_updated_at` | **2026-07-21 04:21:46** |
| `gateway_base_url` | `http://ojamd:8642` |
| `shim_base_url` | `http://ojamd:8765` |
| `shim_token` | len **43**, sha256[:16] **`bed25bb297f52b51`** |
| `last_seen_at` | 2026-07-26 04:26:27 UTC (= 2026-07-25 22:26 local) |

On-disk `C:\Users\Owen\.hermes\talaria_shim_token`: 43 bytes, stripped length 43,
sha256[:16] **`bed25bb297f52b51`**.

**Hashes match → the descriptor token is byte-identical to the on-disk token.** ✅
(Compared by hash; the token itself was never printed.)

**Live authentication:** `GET http://ojamd:8765/models` with that bearer → **HTTP 200**, payload is
a healthy `providers` array (Nous Portal + ~28 models). ✅

**So OJAMD's descriptor matches the Mac's known-good shape.** This is *not* the #116 finding for
this host — there is no gap here.

### The latency measurement — and a correction to what it means

The dispatch asked me to time "the shim's first authenticated call after idle", expecting a slow
shim. **The shim is not slow.** I isolated it:

| Target | Time |
|---|---|
| `http://ojamd:8765/models` (auth, cold) | **9.825 s** |
| `http://ojamd:8765/models` (auth, warm) | **4.087 s** |
| `http://ojamd:8765/models` — **unauthenticated 401** | **4.107 s** |
| `http://127.0.0.1:8765/models` (auth) | **0.012 s** |
| `http://100.110.102.59:8765/models` (auth) | **0.006 s** |
| `http://ojamd:8642/v1/models` (gateway, hostname) | **4.196 s** |
| `http://127.0.0.1:8642/v1/models` | 0.005 s |
| `http://100.110.102.59:8642/v1/models` | 0.003 s |

Three consecutive hostname calls: **4.136 / 4.088 / 4.084 s — it never warms up.**

**Observed:** the ~4.1 s is present on the **401 path too**, so it precedes any auth or upstream
work; and it vanishes entirely when the same service is addressed by IP.

**Concluded:** the cost is **name resolution of `ojamd`**, not the shim and not the gateway. On this
box `ojamd` resolves to link-local IPv6 (`fe80::…`) records ahead of the usable address, and the
client pays a fixed ~4 s failover. Both descriptor URLs are hostname-based, so **both inherit it**.

**The dispatch's downstream worry is therefore upheld, with a different cause:** any probe with a
~5 s budget that uses the descriptor's hostname URLs will report a **healthy** OJAMD service as
**dead**. This is a plausible contributor to O3b's "shim down at 00:00" reading, and it affects any
future health check written against the descriptor.

**Unproven — and I want to be explicit, because it would be easy to overclaim:** these are
**on-box** measurements. From the phone, `ojamd` is a **Tailscale MagicDNS** name
(`tailscale status` lists `ojamd`, `iphone182`, `owens-mac-mini`, …) and would likely resolve
straight to the Tailscale address without the link-local detour. **Whether the phone suffers this
4 s penalty is NOT established by this pass.** It needs one timed request from the device.

---

## O6 · #117 health-drain deferral — **RUN 2026-07-26 00:53–01:24 with Owen driving the phone**

**Result: PARTIAL — deferral and backlog integrity PASS; backoff FAILS by decay.**

Staged on OJAMD with Owen at the device throughout. Outage held **00:53:42 → 01:20:39 (27 min)**.
Watchdog disabled first (no elevation needed), connector killed, relay left running.

**Precondition — CONFIRMED before staging:**

- `tailscale status` → **`100.68.60.11 = iphone182`**, active, direct.
- `relay.log` shows a continuous stream of `POST /v1/device/sensor/health` and
  `POST /v1/device/sensor/location` **from `100.68.60.11`**, including at the tail of the log.
- `hermes_hosts.last_seen_at` = 2026-07-25 22:26 local — connector attached and current.

**So OJAMD unambiguously holds the sensor-destination badge.** The device pass's empirical
disproof of the Mac-as-destination assumption is confirmed from this side.

### Method — and a correction to the dispatch's instrumentation advice

The dispatch says to read retry spacing from app-side `.notice` logs via a corded syslog. That was
not available (phone at OJAMD, no Mac). **A better instrument existed on the box:** the relay scores
every sensor POST by status code, verified in `forward_sensor_payload` —

| relay response | meaning |
|---|---|
| **200** | `deliveryState: "delivered"` |
| **202** | `deliveryState: "retry"` — what the phone gets while the connector is down |

So retry spacing is fully measurable server-side. `relay.log` has no timestamps (see DOC-2), so a
tailer stamped each arrival with the box clock.

**A baseline was taken first — the dispatch does not ask for one, and without it the result is
uninterpretable.** 180 s with the connector UP: **41 health POSTs (40×200, 1×202), 3 location,
= 14.7 sensor POSTs/min, health mean gap 3.76 s.** That is the number every outage figure below is
measured against.

### ⚠️ Method finding — the phone stops all relay traffic when idle

First staging attempt produced **zero POSTs of any kind** for 6 minutes — not sensors, not
`/v1/commands`, not `/v1/hosts/current` — with Tailscale reporting the phone `idle` and no
established sockets. **That was not deferral; the app was suspended.** Deferral and suspension are
indistinguishable from the relay side, and reading the silence as a pass would have been wrong.

The run was restarted with the **app foregrounded and auto-lock set to Never**. All figures below
come from that window. **Any future #117 test must drive the app** — the dispatch's staging section
does not mention this, and its "leave it to run" framing invites exactly this false pass.

### Result 1 — deferral and backlog integrity: **PASS**

- **Every one of 202 sensor POSTs during the outage returned 202.** Zero false "delivered".
- **Backlog held and grew monotonically**, read off the panel by Owen:
  `12 → 18 → 26 → 33 → 38 → 41 → 62 → 82 → 110 → 132`. Nothing dropped.
- **Panel reporting is honest** — it showed a partial-drain line with per-stream counts and an age
  (`Partial: loc=1, health=10, 17s ago`), matching the wire.
- **Drain on restore was complete and fast:** backlog **132 → 8 in ~2 min → 0**, then "clearing as
  soon as they arrive". 22 delivered POSTs, **all 200, zero 202**.

### Result 2 — backoff: **FAIL by decay** (the substantive finding)

The intra-burst ramp is correct and never changes: **`2 → 4 → 8 s`**, every cycle, all 27 minutes.
What collapses is the **rest between bursts**:

| elapsed | inter-burst gap |
|---|---|
| ~t+375 s | **~200 s** |
| ~t+660 s | ~58 s |
| ~t+740 s | ~34 s |
| ~t+1300 s | **~15 s** |

Net retry rate, measured in 2-minute windows against the 14.7/min baseline:

```
6.4 → 6.7 → 10.7 → 10.0 → 12.5 → 17.5 → 18.5 /min
                                          = 126% of baseline
```

**After ~25 minutes the app was retrying harder than it ever polls when healthy, while delivering
nothing.** Per-minute wire counts corroborate independently (01:15–01:19 = 15, 17, 18, 19, 17/min).

This is the dispatch's FAIL condition — "continuous POST traffic with no backoff" — reached by a
route its binary does not describe. **There *is* a backoff ramp; it decays to nothing.** The
practical consequence: **a short test passes and a long test fails.** At the originally planned
30-minute cutoff the reading was ~12.5/min and still "below baseline"; the crossing only appeared
because the window was extended.

**Asymmetry worth noting:** the app retried at **18.5/min while everything failed** but drained at
**3.5/min once delivery worked** — aggressive on failure, lazy on success.

### Hypotheses raised and REFUTED during the run (recorded so they are not re-raised)

1. **"Drains are triggered by sample collection, so a growing backlog drives burst frequency."**
   Refuted — backlog grew **linearly** at a fixed collection cadence (~2.4/min for most of the
   window) while inter-burst gaps collapsed. The two are not coupled that way.
2. **"Failed uploads are re-enqueued as new entries, inflating the backlog in a feedback loop."**
   Proposed when backlog growth (~20–28/min) appeared to track the failed-POST rate (~17–18/min).
   **Refuted by the schema:** `SensorHealthRequest.samples` is
   `list[SensorHealthSample] = Field(min_length=1, max_length=100)` — one health POST carries **up
   to 100 samples**, location is one per POST. So 5 health + 2 location requests legitimately clear
   ~130 real samples. The backlog was **genuine**, and the clean drain confirms it. No inflation,
   no feedback loop.

### Restore — verified

| check | result |
|---|---|
| connector processes | **3** (same trampoline chain, PIDs 112000 → 111700 → 111724) |
| attached | established local-peer socket on `:8000` |
| `hermes_hosts.last_connected_at` | **06:20:53 UTC** |
| `hermes_hosts.last_seen_at` | **05:53:33 → 06:21:15 UTC** (frozen 27 min, now advancing) |
| watchdog | re-enabled, **Ready**, logging `OK connector attached` |
| relay / shim | Running / Running |
| backlog | **0**, clearing on arrival |

**Posture fully restored.** Owen should set phone auto-lock back to its normal value — it was
changed to Never for the test.

---

## Findings for Owen — nothing here needs elevation

I found **no** action requiring an elevated shell. Diagnosis was complete unelevated. Ranked:

0. **#117 backoff decays under a sustained outage** (O6, measured). The `2→4→8 s` ramp is fine; the
   inter-burst rest collapses ~200 s → ~15 s, ending at **126% of baseline traffic while delivering
   nothing**. Fix belongs on the inter-burst timer, not the ramp. Deferral, backlog integrity and
   drain-on-restore are all correct and need no work.
1. **OPEN_ITEMS is wrong about #85/#86** — both deployed and live since 2026-07-20. Worth
   correcting so nobody schedules a deploy session for work already done.
2. **#86 does not raise the pool ceiling.** `pool_pre_ping`/`pool_recycle` fix staleness, not
   exhaustion. If `QueuePool limit of size 5 overflow 10` matters, `pool_size`/`max_overflow` are
   still at defaults.
3. **`relay.log` is 493 MB / 6,015,246 lines, unrotated, and carries no timestamps.** It is
   effectively unusable for forensics — it is why O3a had no fallback. Worth adding rotation and a
   timestamped log format.
4. **Event 7036 is not logged on this host.** Service start/stop transitions leave no audit trail
   at all. This is the actual "who watches the services" gap — not the watchdog, which is healthy.
5. **The descriptor advertises hostname URLs that cost ~4.1 s per request on-box.** Consider
   Tailscale IPs (or verify the phone doesn't pay it).
6. **The un-upstreamed BOM fix** (`d6bd83d`) is still only on `ojamd-deploy`, now 192 commits
   behind `t27/main`.
7. **4 active push registrations still target the old `org.aethyrion.talaria` bundle.**
8. **`relay/.env` has `APNS_BUNDLE_ID=org.aethyrion.talaria`** (old bundle) and
   `APNS_ENVIRONMENT=development`. *Latent only* — `send_push` passes `bundle_id=reg.bundle_id`
   and `environment=reg.push_environment` per row, so the `.env` values are fallbacks that never
   apply while every row carries its own. Worth fixing before a row ever arrives without one.
   `INTERNAL_API_KEY` is a real 43-char key, **not** `"replace-me"` — that earlier OPS concern is clear.

---

## Document defects

Per standing rule 1. The dispatch predicted its own author would repeat this class of error; it did,
twice (DOC-2, DOC-3).

**DOC-1 — companion file absent at start (minor, environment).** The dispatch cites
`dispatch/RESULTS-T27-DEVICE-PASS-2026-07-25.md` as "in this repo". It was **not present**: the
working checkout `O:\Hermes\Talaria-27` was on `81e6c2b`, **94 commits behind** `origin/main`. It
appeared after a clean fast-forward to `c13bdc7`. The dispatch assumes a synced checkout without
saying so. *Resolved by pulling; no work lost.*

**DOC-2 — O3a cannot be performed as written, and no widening fixes it.** The instruction is to
"sweep wider and filtered" for IDs 7000/7009/7031/7036. **Event 7036 is logged zero times for any
service on this host**, and there are zero SCM events for either service in 14 days, against a
System log that reaches back to 2026-02-01 and is not rolled. The dispatch treats the earlier
"40-event window turned up nothing" as a *sampling* problem; it is a *data existence* problem.
I recorded the `nssm.exe` creation-time substitute as its own separate result and did **not** score
O3a from it.

**DOC-3 — O3b's premise is contradicted by the box.** The task is built on "the shim was DOWN at
2026-07-25 00:00". The `TalariaModelsShim` service started **2026-07-24 23:45:34 local**, 15 minutes
*before* that, both hosts in Central time, with no reboot in between. The branch the dispatch
spends most of its words on ("if the last boot falls inside that window… why did OJAMD reboot") is
moot — uptime is 9 days. Compounding it: a hostname-based probe costs 4.1 s on this box (O5), so a
short-timeout preflight can report a live shim as dead, which may be all that happened.

**DOC-4 — O3c's candidate mechanism rests on a wrong premise about the enforcer.** The dispatch
reasons that two interpreters "would sail past an enforcer matching on process name or path", and
asks me to read the enforcer *then* judge. Read: it matches on **`CommandLine`**, and it catches all
three processes including the uv-managed one. The mechanism as stated does not hold. The *other*
half — that the watchdog can't tell relay-down from connector-down — is real, is documented in the
script's own `.NOTES`, and I found log evidence of it.

**DOC-5 — O3c's stated watchdog cadence is wrong.** The dispatch says the watchdog "relaunches it
every 2 minutes" (repeated in O6's staging). The task trigger is **PT1M (every 1 minute)** with a
**2-consecutive-miss** threshold, so a restart follows ~2 minutes *after onset* but re-checks every
minute. Anyone staging O6 on the "2 minute" figure will be surprised by the cadence.

**DOC-6 — O3c's watchdog statistics are from a rotated file.** The cited 8,405 lines / 580 RESTART
are not in `connector-watchdog.log`; the script rotates at 512 KB keeping one predecessor, and those
figures live in `connector-watchdog.log.1`. The dispatch presents them as current ("running since
2026-07-17"), which reads as ongoing instability. Current health is **4 restarts, all within one
10-minute relay outage on 07-24, none since**.

**DOC-8 — O6's staging omits the single precondition that decides the result.** The dispatch says to
stage the outage and read the panel, with no instruction to keep the app running. On the first
attempt the phone went idle and produced **zero traffic of any kind for 6 minutes** — which, scored
against the dispatch's criteria, reads as a clean PASS ("no continuous POST traffic"). It was a
suspended app. **The test must explicitly require the app foregrounded with auto-lock disabled.**

**DOC-9 — O6's PASS/FAIL binary cannot express the actual behaviour.** The dispatch offers PASS
("drains defer, backlog held") or FAIL ("continuous POST traffic with no backoff"). The system does
**both**: it defers correctly and holds the backlog losslessly, *and* its retry rate climbs past
baseline as the outage lengthens. Worse, **which one you observe depends on how long you run** —
under ~15 min it looks like a clean PASS. Any re-run must specify a minimum duration and measure the
*trend* in inter-burst spacing, not a single spacing sample.

**DOC-10 — O6 prescribes an instrument that was unavailable, and misses the better one on the box.**
It directs the runner to app-side `.notice` logs over a corded syslog. That needs the Mac. The relay
already scores every sensor POST (200 = delivered, 202 = retry), making spacing fully measurable
server-side with no device tooling — which is how this run was done.

**DOC-7 — O5's latency question is framed so that the honest answer is misleading.** "Time OJAMD's
first authenticated call after idle… if it is also slow, any probe with a ~5s budget can report a
healthy shim as dead." Timing it as written yields 9.8 s and invites "the shim is slow". The shim
answers in **6–12 ms**; the 4.1 s is hostname resolution and is present on the unauthenticated 401
path. The dispatch's *conclusion* survives; its *attribution* would not have. Isolating it required
adding IP-vs-hostname and auth-vs-unauth comparisons the dispatch does not ask for.

---

*Prepared on OJAMD, 2026-07-25; O6 added 2026-07-26 after running it with Owen.*

*O1–O5 were read-only: no service started or stopped, no row deleted or deactivated, nothing
deployed. **O6 was the one intentional mutation** — the connector was killed and the watchdog
disabled for a 27-minute staged outage (00:53:42 → 01:20:39), both restored and verified afterwards.
No relay/shim/gateway service was touched, no data was deleted, and nothing was deployed at any
point. Where this document and the dispatch disagree, the box won and is reported as such.*
