#!/bin/zsh
# ota-stage.sh <branch> — build a branch and stage it for OTA install over Tailscale.
#
# Proven 2026-07-27 (PR #151 build installed to whoGoesThere from a work desk).
# Xcode-native connect-by-IP is DEAD (Apple DTS, thread 805833) and the phone's
# lockdown/RemotePairing ports do not listen on its Tailscale interface, so OTA
# via itms-services is THE at-work deploy path. Dev-signed, upgrade-installs in
# place (same bundle id) — app data persists.
#
# Requires: Xcode-beta toolchain, unlocked login keychain (no-timeout),
# tailscale serve --bg 8477 configured once (persists in tailscaled state),
# and the com.talaria.ota-http LaunchAgent serving ~/.talaria-ota/serve_root.
set -euo pipefail

BRANCH="${1:?usage: ota-stage.sh <branch>}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta4.app/Contents/Developer}"
REPO=/Users/owenjones/Documents/Claude/Talaria-27
SERVE=/Users/owenjones/.talaria-ota/serve_root
HOSTURL="https://owens-mac-mini.tail5663a6.ts.net"
WORK="$(mktemp -d /tmp/ota-stage.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cd "$REPO"
git fetch origin --quiet
git worktree add -f "$WORK/src" "origin/$BRANCH" --quiet
SHA=$(git -C "$WORK/src" rev-parse --short HEAD)

echo "== archive $BRANCH @ $SHA (toolchain: $(xcodebuild -version | tr '\n' ' '))"
xcodebuild archive -project "$WORK/src/Talaria.xcodeproj" -scheme Talaria \
  -destination 'generic/platform=iOS' -archivePath "$WORK/Talaria.xcarchive" \
  -allowProvisioningUpdates -quiet

cat > "$WORK/ExportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>debugging</string>
    <key>teamID</key><string>DNL25ZFSD2</string>
    <key>signingStyle</key><string>automatic</string>
    <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
EOF

echo "== export"
xcodebuild -exportArchive -archivePath "$WORK/Talaria.xcarchive" \
  -exportPath "$WORK/export" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -allowProvisioningUpdates -quiet

VER=$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw "$WORK/Talaria.xcarchive/Info.plist")
mkdir -p "$SERVE"
cp "$WORK/export/Talaria 27.ipa" "$SERVE/Talaria27.ipa"

cat > "$SERVE/manifest.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict><key>items</key><array><dict>
  <key>assets</key><array><dict>
    <key>kind</key><string>software-package</string>
    <key>url</key><string>${HOSTURL}/Talaria27.ipa</string>
  </dict></array>
  <key>metadata</key><dict>
    <key>bundle-identifier</key><string>org.aethyrion.talaria27</string>
    <key>bundle-version</key><string>${VER}</string>
    <key>kind</key><string>software</string>
    <key>title</key><string>Talaria 27 (${BRANCH} @ ${SHA})</string>
  </dict>
</dict></array></dict>
</plist>
EOF

cat > "$SERVE/index.html" << EOF
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Talaria OTA</title></head>
<body style="font-family:-apple-system;padding:2em;background:#111;color:#eee">
<h2>Talaria 27 — ${BRANCH} @ ${SHA}</h2>
<p>Staged $(date '+%Y-%m-%d %H:%M %Z')</p>
<p><a style="font-size:1.4em;color:#6cf" href="itms-services://?action=download-manifest&amp;url=${HOSTURL}/manifest.plist">Install build</a></p>
</body></html>
EOF

git worktree remove --force "$WORK/src" 2>/dev/null || true
echo "== staged: ${BRANCH} @ ${SHA} (v${VER})"
echo "== install from phone Safari: ${HOSTURL}"
