#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_OUTPUT_ROOT="${HANKEY_OUTPUT_ROOT:-$HANKEY_ROOT/release}"
HANKEY_APP="$HANKEY_OUTPUT_ROOT/HanKey.app"
HANKEY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HANKEY_APP/Contents/Info.plist")"
HANKEY_DMG="${1:-$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.dmg}"
HANKEY_APPCAST="${2:-$HANKEY_OUTPUT_ROOT/appcast.xml}"
HANKEY_SPARKLE_ACCOUNT="${HANKEY_SPARKLE_KEY_ACCOUNT:-hankey}"
HANKEY_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-$HANKEY_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
HANKEY_DOWNLOAD_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/Dindb-dong/gksrmfqusghks/releases/download/v$HANKEY_VERSION}"
HANKEY_STAGE="$(mktemp -d /private/tmp/hankey-appcast.XXXXXX)"

cleanup() {
    rm -rf "$HANKEY_STAGE"
}
trap cleanup EXIT

[[ -x "$HANKEY_GENERATE_APPCAST" ]] || { echo "Sparkle generate_appcast not found: $HANKEY_GENERATE_APPCAST" >&2; exit 66; }
[[ -f "$HANKEY_DMG" ]] || { echo "release DMG not found: $HANKEY_DMG" >&2; exit 66; }
[[ "$HANKEY_DOWNLOAD_PREFIX" == https://* ]] || { echo "download URL prefix must use HTTPS" >&2; exit 64; }

cp "$HANKEY_DMG" "$HANKEY_STAGE/"
"$HANKEY_GENERATE_APPCAST" \
    --account "$HANKEY_SPARKLE_ACCOUNT" \
    --download-url-prefix "${HANKEY_DOWNLOAD_PREFIX%/}/" \
    --link "https://github.com/Dindb-dong/gksrmfqusghks" \
    "$HANKEY_STAGE"
cp "$HANKEY_STAGE/appcast.xml" "$HANKEY_APPCAST"

xmllint --noout "$HANKEY_APPCAST"
grep -q 'sparkle:edSignature=' "$HANKEY_APPCAST"
grep -q "releases/download/v$HANKEY_VERSION/HanKey-$HANKEY_VERSION.dmg" "$HANKEY_APPCAST"

echo "$HANKEY_APPCAST"
