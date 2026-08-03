#!/bin/bash
# Deploy the talaria-push hook to the local HERMES_HOME. Idempotent.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../../host/hooks/talaria-push" && pwd)"
DST="$HOME/.hermes/hooks/talaria-push"
mkdir -p "$DST"
rsync -a --delete --exclude tests --exclude config.json "$SRC/" "$DST/"
[ -f "$DST/config.json" ] || cp "$SRC/config.example.json" "$DST/config.json"
echo "deployed to $DST — edit $DST/config.json (APNs key id/path), then restart the gateway"
