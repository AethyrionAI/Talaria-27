#!/bin/bash
# install-relay-launchd.sh — Talaria relay (:8000) as a macOS LaunchAgent.
# T6 Phase 1 (OPEN_ITEMS #107, design/T6_MAC_BACKEND_SPEC.md §3.3).
#
# Renders ~/Library/LaunchAgents/org.aethyrion.talaria-relay.plist from the
# repo checkout this script lives in (RunAtLoad + KeepAlive → reboot-proof,
# the launchd analog of OJAMD's NSSM/S4U hardening), bootstraps it into the
# gui domain, kickstarts it, and polls /v1/health.
#
# Idempotent: re-running re-renders the plist and bounces the service.
#
# Prereqs (see relay/docs/DEPLOY_MAC.md):
#   cd relay && python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
#   cp .env.mac.example .env   # then fill the <PLACEHOLDERS>
#
# Usage:
#   scripts/mac/install-relay-launchd.sh              install/refresh + start
#   scripts/mac/install-relay-launchd.sh --uninstall  bootout + remove plist
#   RELAY_PORT=8000 RELAY_BIND=0.0.0.0                overrides (defaults shown)
set -euo pipefail

LABEL="org.aethyrion.talaria-relay"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELAY_DIR="$REPO_ROOT/relay"
VENV="${RELAY_VENV:-$RELAY_DIR/.venv}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/talaria-relay"
PORT="${RELAY_PORT:-8000}"
BIND="${RELAY_BIND:-0.0.0.0}"
GUI_TARGET="gui/$(id -u)"

bootout_if_loaded() {
    if launchctl print "$GUI_TARGET/$LABEL" >/dev/null 2>&1; then
        launchctl bootout "$GUI_TARGET/$LABEL" || true
        sleep 1
    fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
    bootout_if_loaded
    rm -f "$PLIST"
    echo "Removed $LABEL (plist deleted, service booted out)."
    exit 0
fi

# ---- Preflight -------------------------------------------------------------
fail=0
if [[ ! -x "$VENV/bin/python" ]]; then
    echo "ERROR: no venv at $VENV" >&2
    echo "  cd '$RELAY_DIR' && python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'" >&2
    fail=1
elif ! "$VENV/bin/python" -c "import uvicorn" 2>/dev/null; then
    echo "ERROR: uvicorn not importable from $VENV — re-run: .venv/bin/pip install -e '.[dev]'" >&2
    fail=1
fi
ENV_FILE="$RELAY_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE missing — cp '$RELAY_DIR/.env.mac.example' '$ENV_FILE' and fill placeholders." >&2
    fail=1
else
    # The relay refuses to start in production with the default key; catch the
    # obvious misconfigurations before launchd starts crash-looping on them.
    if grep -Eq '^INTERNAL_API_KEY=(replace-me|<|$)' "$ENV_FILE"; then
        echo "ERROR: INTERNAL_API_KEY in .env is unset/placeholder — mint one: openssl rand -hex 32" >&2
        fail=1
    fi
    if grep -Eq '^CONNECTOR_SETUP_SECRET=(<|$)' "$ENV_FILE"; then
        echo "ERROR: CONNECTOR_SETUP_SECRET in .env is unset/placeholder — mint one: openssl rand -hex 32" >&2
        fail=1
    fi
    if ! grep -q '^RELAY_ENVIRONMENT=production' "$ENV_FILE"; then
        echo "WARN: RELAY_ENVIRONMENT is not 'production' — the replace-me startup guard won't enforce." >&2
    fi
    if grep -Eq '^DATABASE_URL=sqlite:///[^/]' "$ENV_FILE"; then
        echo "WARN: DATABASE_URL is a relative sqlite path — prefer absolute (sqlite:////...) per #107." >&2
    fi
    if grep -Eq '^PUBLIC_BASE_URL=http://127\.0\.0\.1' "$ENV_FILE"; then
        echo "WARN: PUBLIC_BASE_URL is loopback — phones can't reach that; use the tailnet/LAN IP." >&2
    fi
fi
[[ $fail -eq 0 ]] || exit 1

# ---- Render plist ----------------------------------------------------------
mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$VENV/bin/python</string>
    <string>-m</string>
    <string>uvicorn</string>
    <string>app.main:app</string>
    <string>--host</string>
    <string>$BIND</string>
    <string>--port</string>
    <string>$PORT</string>
  </array>
  <key>WorkingDirectory</key><string>$RELAY_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$VENV/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG_DIR/relay.out.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/relay.err.log</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null

# ---- (Re)load --------------------------------------------------------------
bootout_if_loaded
launchctl bootstrap "$GUI_TARGET" "$PLIST"
launchctl kickstart -k "$GUI_TARGET/$LABEL"

# ---- Health ----------------------------------------------------------------
echo -n "Waiting for http://127.0.0.1:$PORT/v1/health "
for _ in $(seq 1 30); do
    if curl -sf -m 2 "http://127.0.0.1:$PORT/v1/health" >/dev/null 2>&1; then
        echo; echo "OK — relay is up."
        echo "  plist:  $PLIST"
        echo "  logs:   $LOG_DIR/relay.{out,err}.log"
        echo "  status: launchctl print $GUI_TARGET/$LABEL | grep -E 'state|pid'"
        echo "  bounce: launchctl kickstart -k $GUI_TARGET/$LABEL"
        exit 0
    fi
    echo -n "."
    sleep 1
done
echo
echo "ERROR: relay did not answer /v1/health within 30s." >&2
echo "Last stderr lines:" >&2
tail -n 20 "$LOG_DIR/relay.err.log" 2>/dev/null >&2 || true
exit 1
