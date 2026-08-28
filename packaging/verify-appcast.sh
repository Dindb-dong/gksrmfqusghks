#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_OUTPUT_ROOT="${HANKEY_OUTPUT_ROOT:-$HANKEY_ROOT/release}"
HANKEY_APP="$HANKEY_OUTPUT_ROOT/HanKey.app"
HANKEY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HANKEY_APP/Contents/Info.plist")"
HANKEY_APPCAST="${1:-$HANKEY_OUTPUT_ROOT/appcast.xml}"
HANKEY_DMG="${2:-$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.dmg}"
HANKEY_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$HANKEY_ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
HANKEY_SPARKLE_ACCOUNT="${HANKEY_SPARKLE_KEY_ACCOUNT:-hankey}"

[[ -x "$HANKEY_SIGN_UPDATE" ]] || { echo "Sparkle sign_update not found: $HANKEY_SIGN_UPDATE" >&2; exit 66; }
[[ -f "$HANKEY_APPCAST" ]] || { echo "appcast not found: $HANKEY_APPCAST" >&2; exit 66; }
[[ -f "$HANKEY_DMG" ]] || { echo "release DMG not found: $HANKEY_DMG" >&2; exit 66; }

xmllint --noout "$HANKEY_APPCAST"
signature="$(xmllint --xpath "string(//*[local-name()='enclosure']/@*[local-name()='edSignature'])" "$HANKEY_APPCAST")"
enclosure_url="$(xmllint --xpath "string(//*[local-name()='enclosure']/@url)" "$HANKEY_APPCAST")"
enclosure_length="$(xmllint --xpath "string(//*[local-name()='enclosure']/@length)" "$HANKEY_APPCAST")"

[[ ${#signature} -eq 88 ]] || { echo "unexpected EdDSA signature length" >&2; exit 65; }
[[ "$enclosure_url" == "https://github.com/Dindb-dong/gksrmfqusghks/releases/download/v$HANKEY_VERSION/HanKey-$HANKEY_VERSION.dmg" ]] || {
    echo "unexpected enclosure URL: $enclosure_url" >&2
    exit 65
}
[[ "$enclosure_length" == "$(stat -f %z "$HANKEY_DMG")" ]] || { echo "appcast length does not match DMG" >&2; exit 65; }

"$HANKEY_SIGN_UPDATE" --account "$HANKEY_SPARKLE_ACCOUNT" --verify "$HANKEY_DMG" "$signature"
echo "Verified HanKey $HANKEY_VERSION Sparkle appcast."
