#!/bin/bash
# install-shim-launchd.sh — Talaria models shim (:8765) as a macOS LaunchAgent.
# T6 Phase 1 (OPEN_ITEMS #107) — re-renders the shim's LaunchAgent against THIS
# repo checkout. The committed plist at tools/models-shim/*.plist predates the
# Talaria-27 checkout (it points at .../Documents/Claude/Talaria), so a shim
# loaded from that copy silently runs old code — or crash-loops if the old
# checkout is gone. This script fixes the paths and reloads.
#
# Keeps the existing label com.aethyrion.talaria.modelsshim (renaming would
# strand the already-loaded agent) and the existing log location
# ~/.hermes/logs/talaria-shim.{out,err}.log (per tools/models-shim/README.md).
#
# The shim imports hermes_cli, so it must run under the hermes-agent venv
# python (default: ~/.hermes/hermes-agent/venv/bin/python).
#
# Usage:
#   scripts/mac/install-shim-launchd.sh [--python /path/to/python]
#   scripts/mac/install-shim-launchd.sh --uninstall
#   TALARIA_SHIM_HOST=100.79.222.100 TALARIA_SHIM_PORT=8765  overrides (defaults shown)
set -euo pipefail

LABEL="com.aethyrion.talaria.modelsshim"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHIM_PY="$REPO_ROOT/tools/models-shim/shim.py"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/.hermes/logs"
GUI_TARGET="gui/$(id -u)"
PYTHON_BIN="${SHIM_PYTHON:-$HOME/.hermes/hermes-agent/venv/bin/python}"
SHIM_HOST="${TALARIA_SHIM_HOST:-100.79.222.100}"
SHIM_PORT="${TALARIA_SHIM_PORT:-8765}"
SHIM_TTL="${TALARIA_SHIM_TTL:-3600}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --python) PYTHON_BIN="$2"; shift 2 ;;
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

[[ -f "$SHIM_PY" ]] || { echo "ERROR: $SHIM_PY not found" >&2; exit 1; }
[[ -x "$PYTHON_BIN" ]] || { echo "ERROR: python not found at $PYTHON_BIN — pass --python" >&2; exit 1; }
if ! "$PYTHON_BIN" -c "import hermes_cli" 2>/dev/null; then
    echo "ERROR: hermes_cli not importable from $PYTHON_BIN — the shim needs the hermes-agent venv python." >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_BIN</string>
    <string>$SHIM_PY</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>TALARIA_SHIM_HOST</key><string>$SHIM_HOST</string>
    <key>TALARIA_SHIM_PORT</key><string>$SHIM_PORT</string>
    <key>TALARIA_SHIM_TTL</key><string>$SHIM_TTL</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG_DIR/talaria-shim.out.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/talaria-shim.err.log</string>
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

echo -n "Waiting for http://$SHIM_HOST:$SHIM_PORT/healthz "
for _ in $(seq 1 20); do
    if curl -sf -m 2 "http://$SHIM_HOST:$SHIM_PORT/healthz" >/dev/null 2>&1; then
        echo; echo "OK — shim is up (serving THIS checkout: $SHIM_PY)."
        echo "  plist: $PLIST"
        echo "  logs:  $LOG_DIR/talaria-shim.{out,err}.log"
        exit 0
    fi
    echo -n "."
    sleep 1
done
echo
echo "ERROR: shim not answering on $SHIM_HOST:$SHIM_PORT — if the bind host is the" >&2
echo "tailnet IP, confirm Tailscale is up. Log tail:" >&2
tail -n 20 "$LOG_DIR/talaria-shim.err.log" 2>/dev/null >&2 || true
exit 1
