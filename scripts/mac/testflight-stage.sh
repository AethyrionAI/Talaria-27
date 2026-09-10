#!/bin/zsh
# testflight-stage.sh — the pre-flight for App Store Connect: a Release archive of main with DISTRIBUTION signing and an
# app-store-connect export to an .ipa (no upload — Owen uploads it with Transporter / Xcode Organizer under his Apple ID).
# Mirrors ota-stage.sh (worktree, commit-count build number with the high-water floor) but exports for the store.
#
# `testflight-stage.sh upload` (2026-09-10, #443 R11): the same archive, exported with destination=upload — Xcode
# itself delivers the build to App Store Connect using the Apple ID signed into Xcode-rc (Settings → Accounts).
# No credential is typed by anyone: it is the Organizer's "Upload" button from the command line. Run it only on
# Owen's word for THAT build — an upload is outward-facing and lands in TestFlight processing immediately.
set -uo pipefail
setopt NULL_GLOB   # upload mode leaves no plist in the export dir; an unmatched glob must not print an error
MODE="${1:-export}"
case "$MODE" in export|upload) ;; *) echo "usage: $0 [export|upload]" >&2; exit 2 ;; esac
export DEVELOPER_DIR=/Applications/Xcode-rc.app/Contents/Developer
REPO=/Users/owenjones/Documents/Claude/Talaria-27
OUT=$HOME/.talaria-ota/testflight; mkdir -p $OUT
WORK=$(mktemp -d /tmp/tf-stage.XXXXXX); trap 'rm -rf "$WORK"' EXIT
cd $REPO && git fetch origin --quiet && git worktree add -f "$WORK/src" origin/main --quiet
SHA=$(git -C "$WORK/src" rev-parse --short HEAD)
BUILDNUM=$(git -C "$WORK/src" rev-list --count HEAD)
HW=$(cat $HOME/.talaria-ota/serve_root/.buildnum-highwater 2>/dev/null | tr -cd '0-9'); [ -n "$HW" ] && [ "$HW" -ge "$BUILDNUM" ] && BUILDNUM=$((HW+1))
echo "== archive main @ $SHA [Release, distribution] build $BUILDNUM  $(date '+%T')"
xcodebuild archive -project "$WORK/src/Talaria.xcodeproj" -scheme Talaria -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/Talaria.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILDNUM" -allowProvisioningUpdates 2>&1 | grep -E 'error:|warning: .*(entitlement|provision|sign)|\*\* ARCHIVE' | head -40
[ -d "$WORK/Talaria.xcarchive" ] || { echo "ARCHIVE FAILED"; exit 1; }
cat > "$WORK/ExportOptions.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$MODE</string>
  <key>teamID</key><string>DNL25ZFSD2</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PL
echo "== export (app-store-connect, destination=$MODE)  $(date '+%T')"
xcodebuild -exportArchive -archivePath "$WORK/Talaria.xcarchive" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates 2>&1 | tee "$WORK/export.log" | grep -E 'error:|EXPORT|Exported|Upload|upload|provision|entitlement' | head -30
if [ "$MODE" = "upload" ]; then
  # Positive marker only: Xcode prints "** EXPORT SUCCEEDED **" after the upload is accepted by App Store Connect.
  if grep -q '\*\* EXPORT SUCCEEDED \*\*' "$WORK/export.log"; then
    cp "$WORK/export/"*.plist "$OUT/" 2>/dev/null
    echo "== UPLOADED TO APP STORE CONNECT: build $BUILDNUM (main @ $SHA) — processing takes minutes to an hour; it appears under TestFlight → iOS builds"
    exit 0
  else
    echo "UPLOAD FAILED (no EXPORT SUCCEEDED marker) — log: $WORK/export.log"; cat "$WORK/export.log" | tail -20; exit 1
  fi
fi
ls -la "$WORK/export" 2>/dev/null
IPA=$(ls "$WORK"/export/*.ipa 2>/dev/null | head -1)
if [ -n "$IPA" ]; then cp "$IPA" "$OUT/Talaria27-store-$BUILDNUM.ipa"; cp "$WORK/export/"*.plist "$OUT/" 2>/dev/null; echo "== STAGED FOR UPLOAD: $OUT/Talaria27-store-$BUILDNUM.ipa (main @ $SHA, build $BUILDNUM)"; codesign -d --entitlements :- "$WORK/Talaria.xcarchive/Products/Applications/Talaria 27.app" 2>/dev/null | grep -E '<key>' | sed 's/^[ \t]*//' | paste -sd' ' - | cut -c1-400; else echo "EXPORT FAILED"; exit 1; fi
