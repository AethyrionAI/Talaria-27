<#
.SYNOPSIS
    Service-aware Hermes update for OJAMD — stops Talaria's three host-side
    services, runs the Hermes installer, restarts everything, and health-checks.

.DESCRIPTION
    Issue #13: https://github.com/ChronoRixun/Talaria/issues/13

    Hermes updates (curl install.sh | bash) fail when Talaria's three host-side
    services are running because they hold file/process locks on hermes.exe and
    relay Python files. This script automates the stop → update → restart cycle.

    Must be run elevated (NSSM service stop/start + schtasks /End on S4U tasks).

.PARAMETER SkipUpdate
    Skip the Hermes update step — only stop/restart services. Useful for testing
    the stop/restart cycle without actually updating Hermes.

.EXAMPLE
    .\update-hermes.ps1
    .\update-hermes.ps1 -SkipUpdate
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$SkipUpdate
)

$ErrorActionPreference = 'Stop'

# ── Configuration ────────────────────────────────────────────────────────────

$NssmExe     = 'O:\Hermes\nssm\nssm.exe'
$StopTimeout = 30  # seconds per service

# Service definitions in STOP order (relay first, then shim, then gateway).
# Restart is reverse order (gateway first, then shim, then relay).
$Services = @(
    @{ Name = 'HermesMobileRelay';   Port = 8000; Type = 'nssm'  },
    @{ Name = 'TalariaModelsShim';   Port = 8765; Type = 'task'  },
    @{ Name = 'HermesGateway';       Port = 8642; Type = 'task'  }
)

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n[STEP] $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
}

function Write-Err([string]$msg) {
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
}

function Stop-ServiceItem([hashtable]$svc) {
    $name = $svc.Name
    $type = $svc.Type

    if ($type -eq 'nssm') {
        & $NssmExe stop $name 2>$null
        if ($LASTEXITCODE -ne 0) {
            # Might already be stopped — try net stop as fallback
            net stop $name 2>$null | Out-Null
        }
    } elseif ($type -eq 'task') {
        schtasks /End /TN $name 2>$null | Out-Null
    }
}

function Start-ServiceItem([hashtable]$svc) {
    $name = $svc.Name
    $type = $svc.Type

    if ($type -eq 'nssm') {
        & $NssmExe start $name 2>$null
        if ($LASTEXITCODE -ne 0) {
            net start $name 2>$null | Out-Null
        }
    } elseif ($type -eq 'task') {
        schtasks /Run /TN $name 2>$null | Out-Null
    }
}

function Test-Port([int]$Port, [int]$TimeoutSeconds = 5) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect('127.0.0.1', $Port, $null, $null)
    $success = $iar.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)
    if ($success) {
        $tcp.EndConnect($iar)
        $tcp.Close()
        return $true
    }
    $tcp.Close()
    return $false
}

function Test-ServiceStopped([hashtable]$svc, [int]$TimeoutSeconds) {
    $name = $svc.Name
    $port = $svc.Port
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $portUp = Test-Port -Port $port -TimeoutSeconds 2

        # For NSSM services, also check the Windows service status
        if ($svc.Type -eq 'nssm') {
            $svcStatus = (Get-Service -Name $name -ErrorAction SilentlyContinue).Status
            if ($svcStatus -ne 'Running' -and -not $portUp) {
                return $true
            }
        } else {
            if (-not $portUp) {
                return $true
            }
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Test-ServiceStarted([hashtable]$svc, [int]$TimeoutSeconds = 30) {
    return (Test-Port -Port $svc.Port -TimeoutSeconds $TimeoutSeconds)
}

# ── Main ─────────────────────────────────────────────────────────────────────

$report = @{
    Stopped  = @()
    Started  = @()
    UpdateOk = $null
    Warnings = @()
}

Write-Host "`n========================================" -ForegroundColor White
Write-Host " Talaria-aware Hermes Update" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White

# ── 1. Stop all services ────────────────────────────────────────────────────
Write-Step "Stopping services (relay → shim → gateway)"

foreach ($svc in $Services) {
    Write-Host "  Stopping $($svc.Name) (port $($svc.Port))..."
    Stop-ServiceItem -svc $svc

    if (Test-ServiceStopped -svc $svc -TimeoutSeconds $StopTimeout) {
        Write-Ok "$($svc.Name) stopped"
        $report.Stopped += $svc.Name
    } else {
        Write-Warn "$($svc.Name) did not stop cleanly within ${StopTimeout}s — will kill processes"
        $report.Warnings += "$($svc.Name) stop timeout"
    }
}

# ── 2. Kill lingering hermes.exe processes ───────────────────────────────────
Write-Step "Killing lingering hermes.exe processes"

$hermesProcs = Get-Process -Name 'hermes' -ErrorAction SilentlyContinue
if ($hermesProcs) {
    foreach ($p in $hermesProcs) {
        Write-Host "  Killing PID $($p.Id)..."
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    Write-Ok "Killed $($hermesProcs.Count) hermes.exe process(es)"
} else {
    Write-Ok "No lingering hermes.exe processes"
}

# Also kill any orphaned uvicorn processes from the relay
$uvicornProcs = Get-Process -Name 'uvicorn' -ErrorAction SilentlyContinue
if ($uvicornProcs) {
    foreach ($p in $uvicornProcs) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Warn "Killed $($uvicornProcs.Count) orphaned uvicorn process(es)"
}

# ── 3. Run Hermes update ─────────────────────────────────────────────────────
if ($SkipUpdate) {
    Write-Step "Skipping Hermes update (-SkipUpdate)"
    $report.UpdateOk = 'skipped'
} else {
    Write-Step "Running Hermes update"

    # Use curl.exe (NOT the PowerShell alias for Invoke-WebRequest)
    # The install script is bash, so we pipe through bash
    $ErrorActionPreference = 'SilentlyContinue'
    & curl.exe -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
    $updateExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    if ($updateExit -eq 0) {
        Write-Ok "Hermes update completed (exit 0)"
        $report.UpdateOk = $true
    } else {
        Write-Err "Hermes update failed (exit $updateExit)"
        $report.UpdateOk = $false
        $report.Warnings += "Update exited with code $updateExit"
    }
}

# ── 4. Restart all services (reverse order) ──────────────────────────────────
Write-Step "Restarting services (gateway → shim → relay)"

$reversed = [array]::Reverse($Services.Clone()) | Out-Null
# Array.Reverse operates in-place; rebuild reversed list cleanly
$reversedServices = @()
for ($i = $Services.Count - 1; $i -ge 0; $i--) {
    $reversedServices += $Services[$i]
}

foreach ($svc in $reversedServices) {
    Write-Host "  Starting $($svc.Name) (port $($svc.Port))..."
    Start-ServiceItem -svc $svc

    Start-Sleep -Seconds 2

    if (Test-ServiceStarted -svc $svc -TimeoutSeconds 30) {
        Write-Ok "$($svc.Name) started — port $($svc.Port) responding"
        $report.Started += $svc.Name
    } else {
        Write-Warn "$($svc.Name) did not come up on port $($svc.Port) within 30s"
        $report.Warnings += "$($svc.Name) restart failed"
    }
}

# ── 5. Summary ───────────────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor White
Write-Host " SUMMARY" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White

Write-Host "`nStopped ($($report.Stopped.Count)/$($Services.Count)):" -ForegroundColor Cyan
foreach ($s in $report.Stopped) { Write-Host "  [OK] $s" -ForegroundColor Green }
foreach ($s in $Services.Name) {
    if ($s -notin $report.Stopped) { Write-Host "  [!!] $s (did not stop)" -ForegroundColor Yellow }
}

Write-Host "`nStarted ($($report.Started.Count)/$($Services.Count)):" -ForegroundColor Cyan
foreach ($s in $report.Started) { Write-Host "  [OK] $s" -ForegroundColor Green }
foreach ($s in $reversedServices.Name) {
    if ($s -notin $report.Started) { Write-Host "  [!!] $s (did not start)" -ForegroundColor Red }
}

Write-Host "`nUpdate:" -ForegroundColor Cyan
switch ($report.UpdateOk) {
    $true  { Write-Host "  [OK] Hermes updated successfully" -ForegroundColor Green }
    $false { Write-Host "  [!!] Update FAILED — services restarted but Hermes may be in a bad state" -ForegroundColor Red }
    'skipped' { Write-Host "  [--] Skipped (-SkipUpdate)" -ForegroundColor Gray }
}

if ($report.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    foreach ($w in $report.Warnings) { Write-Host "  [!] $w" -ForegroundColor Yellow }
}

Write-Host ""
if ($report.Warnings.Count -eq 0 -and $report.UpdateOk -ne $false) {
    Write-Host "All good. ✅" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Completed with warnings. Review above. ⚠" -ForegroundColor Yellow
    exit 1
}
