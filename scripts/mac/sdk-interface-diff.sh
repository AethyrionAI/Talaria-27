#!/bin/bash
# sdk-diff.sh — full-file swiftinterface sweep between two iOS SDKs.
# Recipe: planning/reports/2026-08-24-beta6-sdk-audit.md §2 (#401), reused for #441.
# Usage: sdk-diff.sh <outdir>   (OLD_SDK / NEW_SDK env override the defaults)
set -u
OLD="${OLD_SDK:-/Applications/Xcode-beta6.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk}"
NEW="${NEW_SDK:-/Applications/Xcode-rc.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk}"
OUT="${1:?usage: sdk-diff.sh <outdir>}"
mkdir -p "$OUT/diffs"

list() { ( cd "$1" && find System/Library/Frameworks usr/lib/swift -name '*.swiftinterface' 2>/dev/null | sort ); }
list "$OLD" > "$OUT/old.list"
list "$NEW" > "$OUT/new.list"
comm -23 "$OUT/old.list" "$OUT/new.list" > "$OUT/removed.list"
comm -13 "$OUT/old.list" "$OUT/new.list" > "$OUT/added.list"
comm -12 "$OUT/old.list" "$OUT/new.list" > "$OUT/common.list"
: > "$OUT/identical.list"; : > "$OUT/stamp-only.list"; : > "$OUT/real.list"

# Strip the two header lines that change with every toolchain stamp; anything
# else that differs is a real interface change.
strip() { grep -v -e '^// swift-compiler-version:' -e '^// swift-module-flags' "$1"; }

while IFS= read -r f; do
    if cmp -s "$OLD/$f" "$NEW/$f"; then
        echo "$f" >> "$OUT/identical.list"
    elif diff -q <(strip "$OLD/$f") <(strip "$NEW/$f") >/dev/null; then
        echo "$f" >> "$OUT/stamp-only.list"
    else
        echo "$f" >> "$OUT/real.list"
        safe="$(echo "$f" | tr '/' '_')"
        diff -u <(strip "$OLD/$f") <(strip "$NEW/$f") > "$OUT/diffs/$safe.diff"
    fi
done < "$OUT/common.list"

( cd "$OLD/System/Library/Frameworks" && ls -d -- *.framework | sort ) > "$OUT/old.fw"
( cd "$NEW/System/Library/Frameworks" && ls -d -- *.framework | sort ) > "$OUT/new.fw"

echo "OLD=$OLD"
echo "NEW=$NEW"
echo "total_old=$(wc -l < "$OUT/old.list" | tr -d ' ') total_new=$(wc -l < "$OUT/new.list" | tr -d ' ') common=$(wc -l < "$OUT/common.list" | tr -d ' ') identical=$(wc -l < "$OUT/identical.list" | tr -d ' ') stamp_only=$(wc -l < "$OUT/stamp-only.list" | tr -d ' ') real=$(wc -l < "$OUT/real.list" | tr -d ' ') added=$(wc -l < "$OUT/added.list" | tr -d ' ') removed=$(wc -l < "$OUT/removed.list" | tr -d ' ')"
echo "frameworks: old=$(wc -l < "$OUT/old.fw" | tr -d ' ') new=$(wc -l < "$OUT/new.fw" | tr -d ' ')"
echo "frameworks added: $(comm -13 "$OUT/old.fw" "$OUT/new.fw" | tr '\n' ' ')"
echo "frameworks removed: $(comm -23 "$OUT/old.fw" "$OUT/new.fw" | tr '\n' ' ')"
echo "== interfaces added:"; cat "$OUT/added.list"
echo "== interfaces removed:"; cat "$OUT/removed.list"
echo "== real changes (diff line counts):"
while IFS= read -r f; do
    safe="$(echo "$f" | tr '/' '_')"
    printf '%6d  %s\n' "$(grep -c -E '^[-+][^-+]' "$OUT/diffs/$safe.diff")" "$f"
done < "$OUT/real.list"
