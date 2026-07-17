<#
.SYNOPSIS
    Connector liveness watchdog for OJAMD — relaunches the Hermes Mobile
    connector when its relay WebSocket disappears (#113).

.DESCRIPTION
    Issue #113: the connector is a bare bat-launched user process (relay and
    shim are NSSM-supervised; the connector is not), so a crash is a permanent
    detach that only surfaces as sensor backlogs piling up on every paired
    device (2026-07-14 and 2026-07-16 incidents).

    Liveness is detected the house way — PORT TRUTH, not process names:
      Get-NetTCPConnection -State Established -LocalPort 8000
    filtered to connections whose REMOTE address is one of this box's own
    addresses (loopback or a local/Tailscale IP). That is the relay's accepted
    socket for the LOCAL connector's WebSocket; device sockets on the same
    port have remote phone/iPad addresses and never match. Do NOT check
    process names: `hermes-mobile-mcp.exe` children of Hermes hosts are
    decoys, and NSSM wrapper PIDs never match port owners (both recorded
    house learnings, OPEN_ITEMS #103).

    Each run is ONE check (the scheduled task provides the 60s cadence).
    A miss increments a counter persisted beside the log; on the SECOND
    consecutive miss the watchdog invokes start-connector.bat — whose
    single-instance enforcer makes an accidental double-fire safe — and
    resets the counter. Any hit resets the counter.

    This script is COMMITTED, NOT INSTALLED: nothing in this repo executes it.
    Installing it (and whether to instead promote the connector to an NSSM
    service) is Owen's infra decision.

.INSTALLATION (manual, on OJAMD — not executed by anything in this repo)
    Run as a Windows scheduled task, every minute, as Owen (the connector must
    run in Owen's user context; PYTHONUTF8=1 is set by start-connector.bat
    itself, so the watchdog passes no environment):

      schtasks /Create /TN TalariaConnectorWatchdog /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File O:\Hermes\Talaria\scripts\connector-watchdog.ps1" /SC MINUTE /MO 1 /RU Owen /F

    House OPS notes (CLAUDE.md): promoting the task to the S4U principal
    (passwordless, survives logoff) or adding a boot trigger requires an
    ELEVATED PowerShell — same pattern as the relay/shim/gateway tasks.
    `Restart-ScheduledTask` does not exist in PowerShell 5.1.

.NOTES
    If the RELAY is down, no port-8000 sockets exist at all, so the watchdog
    will keep invoking the bat. That is safe: the single-instance enforcer
    holds it to one connector, which retries until the relay returns (relay
    supervision is NSSM's job, not this script's).
#>

[CmdletBinding()]
param(
    # Relay port whose Established connections prove the connector is attached.
    [int]$RelayPort = 8000,
    # The launcher the watchdog fires. Its single-instance enforcer makes a
    # double-fire safe; it also sets PYTHONUTF8=1 for the connector.
    [string]$StartConnectorBat = 'O:\Hermes\Talaria\scripts\start-connector.bat',
    # Watchdog log + consecutive-miss state live here.
    [string]$StateDir = 'O:\Hermes\Talaria\logs',
    # Consecutive missed checks (60s apart via the task cadence) before restart.
    [int]$MissThreshold = 2,
    # Rotate the log past this size; one predecessor (.1) is kept.
    [int]$MaxLogBytes = 524288
)

$ErrorActionPreference = 'Stop'

$LogPath   = Join-Path $StateDir 'connector-watchdog.log'
$MissPath  = Join-Path $StateDir 'connector-watchdog.misses'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-WatchdogLog([string]$msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Invoke-LogRotation {
    if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt $MaxLogBytes) {
        Move-Item -Path $LogPath -Destination "$LogPath.1" -Force
    }
}

function Get-ConsecutiveMisses {
    if (Test-Path $MissPath) {
        $raw = (Get-Content -Path $MissPath -ErrorAction SilentlyContinue | Select-Object -First 1)
        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed)) { return $parsed }
    }
    return 0
}

function Set-ConsecutiveMisses([int]$count) {
    Set-Content -Path $MissPath -Value $count -Encoding ASCII
}

function Test-ConnectorAttached {
    # Port truth: the relay's Established socket on $RelayPort whose peer is a
    # LOCAL address is the connector's WebSocket. Device sockets have remote
    # phone addresses; a dead connector leaves only those (the #103/#113
    # diagnostic shape).
    $localAddresses = @('127.0.0.1', '::1')
    $localAddresses += (Get-NetIPAddress -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty IPAddress) | ForEach-Object { ($_ -split '%')[0] }

    $connectorSockets = Get-NetTCPConnection -State Established -LocalPort $RelayPort -ErrorAction SilentlyContinue |
        Where-Object { (($_.RemoteAddress) -split '%')[0] -in $localAddresses }

    return (($connectorSockets | Measure-Object).Count -gt 0)
}

# ── One check per invocation ─────────────────────────────────────────────────

try {
    if (-not (Test-Path $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    Invoke-LogRotation

    if (Test-ConnectorAttached) {
        $misses = Get-ConsecutiveMisses
        if ($misses -gt 0) {
            Write-WatchdogLog "OK connector attached again (was $misses miss(es))"
        } else {
            Write-WatchdogLog "OK connector attached"
        }
        Set-ConsecutiveMisses 0
        exit 0
    }

    $misses = (Get-ConsecutiveMisses) + 1
    Set-ConsecutiveMisses $misses

    if ($misses -lt $MissThreshold) {
        Write-WatchdogLog "MISS no local connector socket on port $RelayPort ($misses/$MissThreshold) — waiting for next check"
        exit 0
    }

    if (-not (Test-Path $StartConnectorBat)) {
        Write-WatchdogLog "ERROR restart wanted but launcher not found: $StartConnectorBat"
        exit 1
    }

    Write-WatchdogLog "RESTART no local connector socket on port $RelayPort for $misses consecutive checks — invoking $StartConnectorBat"
    # Fire-and-forget: the bat's single-instance enforcer owns correctness,
    # and the next check confirms reattachment. Waiting here could hang the
    # watchdog if the launcher blocks.
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$StartConnectorBat`"" -WindowStyle Hidden
    Set-ConsecutiveMisses 0
    exit 0
} catch {
    try { Write-WatchdogLog "ERROR watchdog check failed: $($_.Exception.Message)" } catch { }
    exit 1
}
