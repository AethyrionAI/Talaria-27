<#
.SYNOPSIS
    Authenticated read-only probes against OJAMD's gateway :8642.

.DESCRIPTION
    Reads API_SERVER_KEY from HERMES_HOME's .env ITSELF and uses it only as a
    Bearer header. The key is never printed, never echoed, never written to a
    file, and never returned in output. Everything this prints is safe to paste
    back into a session verbatim.

    READ-ONLY. Every call is a GET. Nothing is created, modified, or deleted:
    no sessions, no jobs, no runs, no config writes.

    Answers, in one pass:
      A. #223 / config chore  - is NVIDIA in the GATEWAY catalog (/api/model/options)?
                                Deliberately NOT the shim's /models: Lane 5 retired the
                                shim from the model path, so its payload is nobody's picker.
      B. route-reverify gap 3 - /v1/capabilities live JSON. The 2026-08-09 Mac lane could
                                not read this (same classifier block) and had to INFER
                                run_approval_response from source. This observes it.
      C. #155 corroboration   - /health + /health/detailed from an authenticated caller.
      D. catalog surface      - /v1/models, /v1/skills, /v1/toolsets row counts.

.NOTES
    Run in normal (non-elevated) PowerShell as Owen. Takes a few seconds.
#>

$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:8642'

Write-Output "CANARY: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "HOST  : $env:COMPUTERNAME"

# --- read the key without ever surfacing it -------------------------------
$envPath = Join-Path $env:HERMES_HOME '.env'
if (-not (Test-Path $envPath)) { Write-Output "FATAL: no .env at $envPath"; exit 1 }
$line = Get-Content $envPath | Where-Object { $_ -match '^\s*API_SERVER_KEY\s*=' } | Select-Object -First 1
if (-not $line) { Write-Output "FATAL: API_SERVER_KEY not present in .env"; exit 1 }
$key = ($line -replace '^\s*API_SERVER_KEY\s*=\s*', '').Trim().Trim('"').Trim("'")
Write-Output "AUTH  : key loaded from .env, length $($key.Length) chars (value not shown)"
$H = @{ Authorization = "Bearer $key" }

function Get-Json {
    param([string]$Path)
    try {
        $r = Invoke-WebRequest -Uri "$base$Path" -Headers $H -Method GET -TimeoutSec 25 -SkipHttpErrorCheck
        return @{ code = [int]$r.StatusCode; body = $r.Content }
    } catch {
        return @{ code = -1; body = $_.Exception.Message.Split([Environment]::NewLine)[0] }
    }
}

Write-Output ""
Write-Output "=============== A. GATEWAY MODEL CATALOG  (/api/model/options) ==============="
# v2 (2026-08-10): the payload shape is {providers, model, provider} per
# hermes_cli/inventory.py::build_models_payload — the collection key is
# 'providers'. v1 of this script looked for options/models/data/items, found
# nothing, and printed a false '0 entries / NVIDIA ABSENT'. This version
# HARD-FAILS if it cannot find a non-empty collection, instead of concluding.
$r = Get-Json '/api/model/options'
Write-Output "HTTP $($r.code)"
if ($r.code -eq 200) {
    Write-Output "  raw head: $($r.body.Substring(0,[Math]::Min(220,$r.body.Length)))"
    try {
        $j = $r.body | ConvertFrom-Json
        Write-Output "  top-level keys: $(($j.PSObject.Properties.Name) -join ', ')"
        $provs = @()
        if ($j.PSObject.Properties['providers']) { $provs = @($j.providers) }
        if ($provs.Count -eq 0) {
            Write-Output "  !!! PARSE FAILURE OR GENUINELY EMPTY - no 'providers' rows found."
            Write-Output "  !!! DO NOT conclude anything from this run; inspect the raw head above."
        } else {
            Write-Output "  provider rows: $($provs.Count)"
            Write-Output "  per-provider model counts:"
            foreach ($p in $provs) {
                $pname = $null
                foreach ($k in @('name','provider','id','slug','display_name')) {
                    if ($p.PSObject.Properties[$k] -and $p.$k) { $pname = "$($p.$k)"; break }
                }
                $mcount = 0
                if ($p.PSObject.Properties['models']) { $mcount = @($p.models).Count }
                "    {0,-24} {1} models" -f $pname, $mcount
            }
            $nvHit = $r.body -match 'nvidia'
            Write-Output ""
            if ($nvHit) {
                Write-Output "  >>> 'nvidia' PRESENT in the gateway catalog payload"
                Write-Output "  >>> the pruning chore is REAL and NOT yet done on OJAMD"
            } else {
                Write-Output "  >>> 'nvidia' absent from a NON-EMPTY catalog ($($provs.Count) providers)"
                Write-Output "  >>> chore is MOOT on OJAMD - verified against the gateway, not the shim"
            }
        }
    } catch { Write-Output "  (JSON parse note) $($_.Exception.Message)"; Write-Output $r.body.Substring(0,[Math]::Min(600,$r.body.Length)) }
} else { Write-Output "  body: $($r.body.Substring(0,[Math]::Min(400,$r.body.Length)))" }

Write-Output ""
Write-Output "=============== B. /v1/capabilities  (closes route-reverify gap 3) ==============="
$r = Get-Json '/v1/capabilities'
Write-Output "HTTP $($r.code)"
if ($r.code -eq 200) {
    Write-Output $r.body
} else { Write-Output "  body: $($r.body.Substring(0,[Math]::Min(400,$r.body.Length)))" }

Write-Output ""
Write-Output "=============== C. health (authenticated) ==============="
foreach ($p in @('/health','/health/detailed')) {
    $r = Get-Json $p
    Write-Output "GET $p -> HTTP $($r.code)"
    if ($r.code -eq 200) { Write-Output "  $($r.body.Substring(0,[Math]::Min(700,$r.body.Length)))" }
}

Write-Output ""
Write-Output "=============== D. catalog surface ==============="
foreach ($p in @('/v1/models','/v1/skills','/v1/toolsets')) {
    $r = Get-Json $p
    $n = '?'
    if ($r.code -eq 200) {
        try {
            $j = $r.body | ConvertFrom-Json
            foreach ($c in @('data','models','skills','toolsets','items')) {
                if ($j.PSObject.Properties[$c]) { $n = @($j.$c).Count; break }
            }
            if ($n -eq '?' -and $j -is [array]) { $n = @($j).Count }
        } catch { }
    }
    "  {0,-16} HTTP {1}  entries={2}" -f $p, $r.code, $n
}
# /v1/models is small and load-bearing for #241 (the hermes-agent sentinel) - show it
$r = Get-Json '/v1/models'
if ($r.code -eq 200) {
    Write-Output ""
    Write-Output "  /v1/models body (relevant to #241's 'hermes-agent' sentinel):"
    Write-Output "  $($r.body.Substring(0,[Math]::Min(900,$r.body.Length)))"
}

$key = $null
Write-Output ""
Write-Output "CANARY-END: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
