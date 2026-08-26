#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_OUTPUT_ROOT="${HANKEY_OUTPUT_ROOT:-$HANKEY_ROOT/release}"
HANKEY_APP="$HANKEY_OUTPUT_ROOT/HanKey.app"
HANKEY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HANKEY_APP/Contents/Info.plist")"
HANKEY_ZIP="$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.zip"
HANKEY_DMG="$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.dmg"
HANKEY_PROFILE="${HANKEY_NOTARY_PROFILE:-}"

if [[ -z "$HANKEY_PROFILE" ]]; then
    echo "HANKEY_NOTARY_PROFILE is required" >&2
    exit 64
fi

xcrun notarytool submit "$HANKEY_ZIP" --keychain-profile "$HANKEY_PROFILE" --wait
xcrun stapler staple "$HANKEY_APP"
xcrun stapler validate "$HANKEY_APP"

"$HANKEY_ROOT/packaging/package-release.sh" >/dev/null
xcrun notarytool submit "$HANKEY_DMG" --keychain-profile "$HANKEY_PROFILE" --wait
xcrun stapler staple "$HANKEY_DMG"
xcrun stapler validate "$HANKEY_DMG"

(
    cd "$HANKEY_OUTPUT_ROOT"
    shasum -a 256 \
        "HanKey-$HANKEY_VERSION.zip" \
        "HanKey-$HANKEY_VERSION.dmg" \
        "HanKey-$HANKEY_VERSION.spdx.json" >SHA256SUMS.txt
)

codesign --verify --deep --strict --verbose=2 "$HANKEY_APP"
spctl --assess --type execute --verbose=4 "$HANKEY_APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$HANKEY_DMG"
