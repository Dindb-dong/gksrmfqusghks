#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_OUTPUT_ROOT="${HANKEY_OUTPUT_ROOT:-$HANKEY_ROOT/release}"
HANKEY_APP="$HANKEY_OUTPUT_ROOT/HanKey.app"
HANKEY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HANKEY_APP/Contents/Info.plist")"
HANKEY_ZIP="$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.zip"
HANKEY_DMG="$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.dmg"
HANKEY_CHECKSUMS="$HANKEY_OUTPUT_ROOT/SHA256SUMS.txt"
HANKEY_IDENTITY="${HANKEY_CODESIGN_IDENTITY:--}"
HANKEY_STAGE="$(mktemp -d /private/tmp/hankey-dmg.XXXXXX)"

cleanup() {
    rm -rf "$HANKEY_STAGE"
}
trap cleanup EXIT

if [[ ! -d "$HANKEY_APP" ]]; then
    echo "release app not found: $HANKEY_APP" >&2
    exit 1
fi

rm -f "$HANKEY_ZIP" "$HANKEY_DMG" "$HANKEY_CHECKSUMS"
ditto -c -k --sequesterRsrc --keepParent "$HANKEY_APP" "$HANKEY_ZIP"
ditto --noextattr --noqtn "$HANKEY_APP" "$HANKEY_STAGE/HanKey.app"
ln -s /Applications "$HANKEY_STAGE/Applications"
hdiutil create \
    -volname "HanKey $HANKEY_VERSION" \
    -srcfolder "$HANKEY_STAGE" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    "$HANKEY_DMG"

if [[ "$HANKEY_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$HANKEY_IDENTITY" "$HANKEY_DMG"
    codesign --verify --verbose=2 "$HANKEY_DMG"
fi

cp "$HANKEY_ROOT/packaging/SBOM.spdx.json" "$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.spdx.json"
(
    cd "$HANKEY_OUTPUT_ROOT"
    shasum -a 256 \
        "HanKey-$HANKEY_VERSION.zip" \
        "HanKey-$HANKEY_VERSION.dmg" \
        "HanKey-$HANKEY_VERSION.spdx.json" >"$HANKEY_CHECKSUMS"
)

echo "$HANKEY_DMG"
