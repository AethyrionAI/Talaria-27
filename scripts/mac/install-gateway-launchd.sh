#!/bin/bash
# install-gateway-launchd.sh — Hermes gateway/API server (:8642) as a macOS
# LaunchAgent. T6 Phase 1 (OPEN_ITEMS #107) — the "confirm gateway/shim are
# boot-persistent" half of design/T6_MAC_BACKEND_SPEC.md §3.3.
#
# ONLY A FALLBACK. Before using this, check whether the gateway is already
# boot-persistent on the Mini:
#   launchctl print gui/$(id -u) | grep -iE 'hermes|gateway'
# and whether `hermes gateway install` provides a native LaunchAgent on macOS
# (the CLAUDE.md prohibition on `hermes gateway install` is WINDOWS-specific —
# it creates a conflicting login-only Scheduled Task there; macOS may be fine,
# and native wins if it works). Use this script only for a hand-started
# gateway with no native persistence. Two gateways on :8642 = a port fight.
#
# This wraps `hermes gateway run` (which serves the Sessions API on :8642 plus
# all enabled platforms in ONE process — no Hermes core changes here, pure ops).
#
# Usage:
#   scripts/mac/install-gateway-launchd.sh [--hermes /path/to/hermes] [--force]
#   scripts/mac/install-gateway-launchd.sh --uninstall
set -euo pipefail

LABEL="org.aethyrion.talaria-gateway"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/talaria-gateway"
GUI_TARGET="gui/$(id -u)"
HERMES_BIN="${HERMES_BIN:-}"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hermes) HERMES_BIN="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --uninstall)
            if launchctl print "$GUI_TARGET/$LABEL" >/dev/null 2>&1; then
                launchctl bootout "$GUI_TARGET/$LABEL" || true
            fi
            rm -f "$PLIST"
            echo "Removed $LABEL."
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ---- Resolve the hermes binary ----------------------------------------------
if [[ -z "$HERMES_BIN" ]]; then
    HERMES_BIN="$(command -v hermes || true)"
fi
if [[ -z "$HERMES_BIN" && -x "$HOME/.hermes/hermes-agent/venv/bin/hermes" ]]; then
    HERMES_BIN="$HOME/.hermes/hermes-agent/venv/bin/hermes"
fi
if [[ -z "$HERMES_BIN" || ! -x "$HERMES_BIN" ]]; then
    echo "ERROR: hermes CLI not found — pass --hermes /absolute/path/to/hermes" >&2
    exit 1
fi
"$HERMES_BIN" --version >/dev/null || { echo "ERROR: '$HERMES_BIN --version' failed" >&2; exit 1; }

# ---- Refuse to double-manage a gateway that's already persisted --------------
existing="$(launchctl list 2>/dev/null | awk '{print $3}' | grep -iE 'hermes|gateway' | grep -v "^$LABEL$" | grep -v 'ai.hermes.mobile.connector' || true)"
if [[ -n "$existing" && $FORCE -ne 1 ]]; then
    echo "ERROR: found existing launchd job(s) that look gateway-shaped:" >&2
    echo "$existing" | sed 's/^/    /' >&2
    echo "If one of these already runs the gateway, do NOT install a second (port fight on :8642)." >&2
    echo "Re-run with --force only after confirming they are unrelated." >&2
    exit 1
fi

# ---- Render + load -----------------------------------------------------------
mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"
HERMES_DIR="$(dirname "$HERMES_BIN")"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HERMES_BIN</string>
    <string>gateway</string>
    <string>run</string>
  </array>
  <key>WorkingDirectory</key><string>$HOME</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$HERMES_DIR:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG_DIR/gateway.out.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/gateway.err.log</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null

if launchctl print "$GUI_TARGET/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "$GUI_TARGET/$LABEL" || true
    sleep 1
fi
launchctl bootstrap "$GUI_TARGET" "$PLIST"
launchctl kickstart -k "$GUI_TARGET/$LABEL"

echo -n "Waiting for :8642 to answer "
for _ in $(seq 1 30); do
    code="$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://127.0.0.1:8642/" 2>/dev/null || echo 000)"
    if [[ "$code" != "000" ]]; then
        echo; echo "OK — gateway answering on :8642 (HTTP $code; auth-gated codes are expected)."
        echo "  plist: $PLIST"
        echo "  logs:  $LOG_DIR/gateway.{out,err}.log"
        exit 0
    fi
    echo -n "."
    sleep 1
done
echo
echo "ERROR: nothing answering on :8642 after 30s — check $LOG_DIR/gateway.err.log" >&2
tail -n 20 "$LOG_DIR/gateway.err.log" 2>/dev/null >&2 || true
exit 1
