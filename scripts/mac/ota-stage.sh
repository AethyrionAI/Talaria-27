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

BRANCH="${1:?usage: ota-stage.sh <branch> [Debug|Release]}"
# Optional configuration (default Release). Debug matters when the build must
# carry #if DEBUG seams (e.g. the #194 session-shape selector) — Release
# compiles them out, so an OTA A/B build MUST be staged as Debug.
CONFIG="${2:-Release}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta6.app/Contents/Developer}"
REPO=/Users/owenjones/Documents/Claude/Talaria-27
SERVE=/Users/owenjones/.talaria-ota/serve_root
HOSTURL="https://owens-mac-mini.tail5663a6.ts.net"
WORK="$(mktemp -d /tmp/ota-stage.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cd "$REPO"
git fetch origin --quiet
git worktree add -f "$WORK/src" "origin/$BRANCH" --quiet
SHA=$(git -C "$WORK/src" rev-parse --short HEAD)
# #200D lesson: a battery export from a stale install is indistinguishable from
# the staged build unless the run record can prove its build. CFBundleVersion is
# $(CURRENT_PROJECT_VERSION) in project.yml, so stamping the commit count here
# puts a monotonic build id into every staged binary — BatteryRunStore exports
# it as `appBuild`, closing the loop.
BUILDNUM=$(git -C "$WORK/src" rev-list --count HEAD)
# 2026-08-23: rev-list count ALONE is not monotonic, and this bit for real.
# A squash-merge collapses N commits into 1, so a feature branch counts HIGHER
# than the main it merges into: t27-393-accent-text was 2961 while the main
# that absorbed it was 2958. Staging main after that branch therefore OFFERED A
# LOWER BUILD than the phone already had — and two different trees (main and
# the next feature branch) both computed 2958, so the number was not even
# unique. That defeats the #200D property this line exists for: a run record
# that can prove which build produced it.
#
# Fix: a HIGH-WATER MARK, not the currently-served number. The served value is
# not the installed one — the phone can hold a build the server has since
# overwritten, which is exactly how this was found. The mark only ever rises.
HIGHWATER_FILE="$SERVE/.buildnum-highwater"
HIGHWATER=$(cat "$HIGHWATER_FILE" 2>/dev/null | tr -cd '0-9')
if [ -n "$HIGHWATER" ] && [ "$HIGHWATER" -ge "$BUILDNUM" ]; then
  BUILDNUM=$((HIGHWATER + 1))
  echo "== build floored to $BUILDNUM (high-water $HIGHWATER >= commit count; squash-merge skew)"
fi
mkdir -p "$SERVE"
echo "$BUILDNUM" > "$HIGHWATER_FILE"

echo "== archive $BRANCH @ $SHA [$CONFIG] build $BUILDNUM (toolchain: $(xcodebuild -version | tr '\n' ' '))"
xcodebuild archive -project "$WORK/src/Talaria.xcodeproj" -scheme Talaria \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' -archivePath "$WORK/Talaria.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILDNUM" \
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
    <key>title</key><string>Talaria 27 (${BRANCH} @ ${SHA} ${CONFIG})</string>
  </dict>
</dict></array></dict>
</plist>
EOF

cat > "$SERVE/index.html" << EOF
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Talaria OTA</title></head>
<body style="font-family:-apple-system;padding:2em;background:#111;color:#eee">
<h2>Talaria 27 — ${BRANCH} @ ${SHA} · ${CONFIG} · build ${BUILDNUM}</h2>
<p>Staged $(date '+%Y-%m-%d %H:%M %Z')</p>
<p><a style="font-size:1.4em;color:#6cf" href="itms-services://?action=download-manifest&amp;url=${HOSTURL}/manifest.plist">Install build</a></p>
</body></html>
EOF

git worktree remove --force "$WORK/src" 2>/dev/null || true
echo "== staged: ${BRANCH} @ ${SHA} (v${VER} build ${BUILDNUM})"
echo "== install from phone Safari: ${HOSTURL}"
