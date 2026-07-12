#!/bin/bash
# verify-phase1.sh — T6 Phase 1 acceptance smoke (OPEN_ITEMS #107,
# design/T6_MAC_BACKEND_SPEC.md §6). Service-level checks only; the device
# half of acceptance (pairing, sensors, push, Tier-2 fetch with a real
# bearer) lives in the #107 checklist and needs a phone/simulator.
#
# Usage:
#   scripts/mac/verify-phase1.sh                  static checks
#   scripts/mac/verify-phase1.sh --restart-check  + bounce the relay and prove
#                                                 pairings survive DB-side and
#                                                 the connector reattaches (#54)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELAY_LABEL="org.aethyrion.talaria-relay"
GATEWAY_LABEL="org.aethyrion.talaria-gateway"
SHIM_LABEL="com.aethyrion.talaria.modelsshim"
CONNECTOR_LABEL="ai.hermes.mobile.connector"
GUI_TARGET="gui/$(id -u)"
RELAY_PORT="${RELAY_PORT:-8000}"
SHIM_HOST="${TALARIA_SHIM_HOST:-100.79.222.100}"
SHIM_PORT="${TALARIA_SHIM_PORT:-8765}"
CONN_HOME="${HERMES_MOBILE_CONNECTOR_HOME:-$HOME/.hermes-mobile}"
RESTART_CHECK=0
[[ "${1:-}" == "--restart-check" ]] && RESTART_CHECK=1

PASS=0; FAIL=0; WARN=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
warn() { WARN=$((WARN+1)); echo "  WARN  $1"; }

launchd_running() {
    launchctl print "$GUI_TARGET/$1" 2>/dev/null | grep -Eq "state = running|pid = "
}

http_code() { curl -s -o /dev/null -m 3 -w '%{http_code}' "$1" 2>/dev/null || echo 000; }

echo "== launchd jobs (survive reboot = RunAtLoad agents; reboot test itself is manual) =="
launchd_running "$RELAY_LABEL"     && ok "$RELAY_LABEL running"     || bad "$RELAY_LABEL not running (scripts/mac/install-relay-launchd.sh)"
launchd_running "$CONNECTOR_LABEL" && ok "$CONNECTOR_LABEL running" || bad "$CONNECTOR_LABEL not running (hermes-mobile service install && hermes-mobile service start)"
launchd_running "$SHIM_LABEL"      && ok "$SHIM_LABEL running"      || bad "$SHIM_LABEL not running (scripts/mac/install-shim-launchd.sh)"
if launchd_running "$GATEWAY_LABEL"; then
    ok "$GATEWAY_LABEL running"
elif [[ "$(http_code "http://127.0.0.1:8642/")" != "000" ]]; then
    warn "gateway answers on :8642 but not via $GATEWAY_LABEL — confirm it is boot-persistent (native agent?) or run scripts/mac/install-gateway-launchd.sh"
else
    bad "gateway: nothing on :8642 and no $GATEWAY_LABEL agent"
fi

echo "== HTTP health =="
body="$(curl -sf -m 3 "http://127.0.0.1:$RELAY_PORT/v1/health" 2>/dev/null || true)"
[[ "$body" == *'"ok"'* || "$body" == *'ok'* ]] && ok "relay /v1/health" || bad "relay /v1/health (got: ${body:-no answer})"
[[ "$(http_code "http://$SHIM_HOST:$SHIM_PORT/healthz")" == "200" ]] && ok "shim /healthz ($SHIM_HOST:$SHIM_PORT)" || bad "shim /healthz on $SHIM_HOST:$SHIM_PORT (Tailscale up?)"
gw="$(http_code "http://127.0.0.1:8642/")"
[[ "$gw" != "000" ]] && ok "gateway :8642 answering (HTTP $gw)" || bad "gateway :8642 silent"

# Tier-2 route: unauthenticated probe must be rejected, not open and not absent.
files_code="$(http_code "http://127.0.0.1:$RELAY_PORT/v1/device/files?path=probe.txt")"
case "$files_code" in
    401|403) ok "/v1/device/files auth-gated (HTTP $files_code) — authed 200 fetch is a device-checklist item" ;;
    404)     bad "/v1/device/files 404 — relay code predates #21 Tier 2?" ;;
    200)     bad "/v1/device/files served WITHOUT auth — investigate immediately" ;;
    *)       warn "/v1/device/files unexpected HTTP $files_code" ;;
esac

echo "== relay .env hygiene (#107) =="
ENV_FILE="$REPO_ROOT/relay/.env"
if [[ -f "$ENV_FILE" ]]; then
    grep -Eq '^INTERNAL_API_KEY=(replace-me|<|$)' "$ENV_FILE" && bad "INTERNAL_API_KEY placeholder" || ok "INTERNAL_API_KEY set"
    grep -q '^RELAY_ENVIRONMENT=production' "$ENV_FILE" && ok "RELAY_ENVIRONMENT=production" || warn "RELAY_ENVIRONMENT != production (replace-me guard inert)"
    grep -Eq '^DATABASE_URL=sqlite:////' "$ENV_FILE" && ok "DATABASE_URL absolute" || warn "DATABASE_URL not an absolute sqlite path"
    grep -Eq '^GATEWAY_API_KEY=(<|$)' "$ENV_FILE" && warn "GATEWAY_API_KEY unset — push-watch (#38) disabled" || ok "GATEWAY_API_KEY set"
    grep -Eq '^APNS_KEY_PATH=~' "$ENV_FILE" && bad "APNS_KEY_PATH uses ~ (relay does not expand it — use an absolute path)" || true
else
    bad "$ENV_FILE missing"
fi

if [[ $RESTART_CHECK -eq 1 ]]; then
    echo "== restart check: pairings survive + connector reattaches (#54) =="
    state_json="$CONN_HOME/state.json"
    [[ -f "$state_json" ]] || state_json="$CONN_HOME/state/state.json"
    if [[ ! -f "$state_json" ]]; then
        bad "connector state.json not found under $CONN_HOME — is the connector set up?"
    else
        bounce_epoch="$(date +%s)"
        launchctl kickstart -k "$GUI_TARGET/$RELAY_LABEL"
        echo -n "  relay restarting "
        up=0
        for _ in $(seq 1 30); do
            curl -sf -m 2 "http://127.0.0.1:$RELAY_PORT/v1/health" >/dev/null 2>&1 && { up=1; break; }
            echo -n "."; sleep 1
        done
        echo
        [[ $up -eq 1 ]] && ok "relay back up after kickstart" || bad "relay did not come back within 30s"

        # DB-backed pairings: same DB file, rows intact ⇒ existing device tokens
        # keep working (full /v1/session proof needs a paired device — checklist).
        echo -n "  waiting for connector reattach "
        reattached=0
        for _ in $(seq 1 90); do
            last="$(python3 - "$state_json" <<'PY' 2>/dev/null
import json, sys
from datetime import datetime
raw = json.load(open(sys.argv[1])).get("last_connected_at") or ""
try:
    print(int(datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()))
except Exception:
    print(0)
PY
)"
            if [[ -n "$last" && "$last" -ge "$bounce_epoch" ]]; then reattached=1; break; fi
            echo -n "."; sleep 1
        done
        echo
        if [[ $reattached -eq 1 ]]; then
            ok "connector reattached after relay bounce (last_connected_at advanced) — note result on OPEN_ITEMS #54"
        else
            bad "connector did NOT reattach within 90s — check $CONN_HOME/logs/connector.stderr.log and note on #54"
        fi
    fi
fi

echo
echo "== summary: $PASS pass, $FAIL fail, $WARN warn =="
echo "Device-side acceptance (pairing, sensors delivered, talk readiness, push,"
echo "authed Tier-2 fetch) → OPEN_ITEMS #107 checklist."
[[ $FAIL -eq 0 ]] || exit 1
