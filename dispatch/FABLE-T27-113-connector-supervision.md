# FABLE T27-113 — Connector supervision: never again a silent death

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-113-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #113 · **Size:** one PR (Python + PowerShell + one small app change)

## Why (two incidents in four days)

2026-07-14: connector process died silently on OJAMD; relay 202-busied every
sensor ingest; health piled up on BOTH devices until a human noticed.
2026-07-16: died again after a `hermes update` + reboot cycle. Relay and shim
are NSSM-supervised and came back; the connector is a bare bat-launched user
process — a crash is a permanent detach until sensors pile up. Distinct from
#54 (re-attach when the process LIVES — resolved); this is process mortality.

## Scope split — read carefully

The supervision MECHANISM install on OJAMD (NSSM service vs scheduled task) is
Owen's infra decision and NOT this lane's to execute. This lane ships the
CODE that makes any supervisor work, plus the watchdog script itself as a
committed artifact, plus the app-side alert. Nothing in this lane runs on
OJAMD; everything is testable in cloud.

## Deliverable 1 — connector: die loudly, exit nonzero, log why

Audit `connector/src/hermes_mobile_connector/` main run loop: any path where
the process can end without a nonzero exit code + a final log line (unhandled
exception in the WS loop, event-loop death, silent task cancellation) gets
hardened: top-level try → log `FATAL: <reason>` → `sys.exit(1)`. A supervisor
can only restart what visibly dies. Respect the existing single-instance
enforcer — exiting must release whatever lock/port it holds so the restart
isn't blocked. Tests: simulate a raised exception through the entry path →
assert exit code + log line (pytest, no network).

## Deliverable 2 — `scripts/connector-watchdog.ps1` (committed, not installed)

A small PowerShell watchdog for OJAMD, committed to `scripts/` beside
`update-hermes.ps1`:
- Detect liveness the HOUSE way: `Get-NetTCPConnection -State Established
  -LocalPort 8000` filtered to a LOCAL-address peer (the connector's WS) —
  NOT process names (`hermes-mobile-mcp.exe` children are decoys; NSSM
  wrapper PIDs never match port owners — both are recorded house learnings).
- If absent for 2 consecutive checks (60s apart): invoke
  `O:\Hermes\Talaria\scripts\start-connector.bat` (single-instance enforcer
  makes double-fire safe), log to a rotating file.
- Header comment: install as Windows scheduled task (every minute, run as
  Owen, `PYTHONUTF8=1` inherited from the bat) — exact `schtasks` line
  included but NOT executed by anything in this repo.

## Deliverable 3 — app: repeated retry-exhaustion becomes an inbox alert

Today the only surface is the sensor diagnostics panel string (#15). When the
drain hits retry-exhaustion on N consecutive drain cycles (N=3), enqueue ONE
local inbox item ("Sensor uploads can't reach the host — the connector may be
down") — deduped, cleared on next successful delivery.
**HARD CONSTRAINT:** the inbox decoder accepts only
`alert/approval/notification/reminder/suggestion` kinds — use `alert`, and use
the existing item-creation path (#58's row-tolerant decoder is downstream;
don't hand it a novel kind). Test the trigger/dedupe/clear logic as a pure
decision function.

## Constraints & acceptance

- Connector pytest green (115 macOS baseline); app suite green ≥ 755/62;
  regen only if Swift files add/remove (the alert logic may — separate commit,
  verify aps-environment).
- PR body: forensics note owed separately (why it died on 07-14/07-16 —
  connector log around time of death; Owen/Desktop on next OJAMD pass), and
  the one-line install instruction for the watchdog task.
- **Open decision for Owen (state it, don't block on it):** NSSM-service
  promotion vs the scheduled-task watchdog. The watchdog ships either way and
  is strictly additive.
