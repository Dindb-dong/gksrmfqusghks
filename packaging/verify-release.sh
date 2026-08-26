#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_OUTPUT_ROOT="${HANKEY_OUTPUT_ROOT:-$HANKEY_ROOT/release}"
HANKEY_APP="$HANKEY_OUTPUT_ROOT/HanKey.app"
HANKEY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HANKEY_APP/Contents/Info.plist")"
HANKEY_ZIP="$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.zip"
HANKEY_DMG="$HANKEY_OUTPUT_ROOT/HanKey-$HANKEY_VERSION.dmg"
HANKEY_MOUNT="$(mktemp -d /private/tmp/hankey-verify.XXXXXX)"
HANKEY_ATTACHED=0

cleanup() {
    if [[ "$HANKEY_ATTACHED" == "1" ]]; then
        hdiutil detach "$HANKEY_MOUNT" -quiet || true
    fi
    rm -rf "$HANKEY_MOUNT"
}
trap cleanup EXIT

codesign --verify --deep --strict --verbose=2 "$HANKEY_APP"
lipo "$HANKEY_APP/Contents/MacOS/HanKeyApp" -verify_arch arm64 x86_64
test -f "$HANKEY_APP/Contents/Resources/Assets.car"
test -f "$HANKEY_APP/Contents/Resources/AppIcon.icns"
test -f "$HANKEY_APP/Contents/Resources/SBOM.spdx.json"
unzip -tq "$HANKEY_ZIP" >/dev/null
hdiutil verify "$HANKEY_DMG" >/dev/null

(
    cd "$HANKEY_OUTPUT_ROOT"
    shasum -a 256 -c SHA256SUMS.txt
)

hdiutil attach "$HANKEY_DMG" -readonly -nobrowse -mountpoint "$HANKEY_MOUNT" -quiet
HANKEY_ATTACHED=1
test -d "$HANKEY_MOUNT/HanKey.app"
test -L "$HANKEY_MOUNT/Applications"
codesign --verify --deep --strict --verbose=2 "$HANKEY_MOUNT/HanKey.app"
lipo "$HANKEY_MOUNT/HanKey.app/Contents/MacOS/HanKeyApp" -verify_arch arm64 x86_64

if [[ "${HANKEY_EXPECT_NOTARIZED:-0}" == "1" ]]; then
    xcrun stapler validate "$HANKEY_APP"
    xcrun stapler validate "$HANKEY_DMG"
    spctl --assess --type execute --verbose=4 "$HANKEY_APP"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$HANKEY_DMG"
    xcrun stapler validate "$HANKEY_MOUNT/HanKey.app"
    spctl --assess --type execute --verbose=4 "$HANKEY_MOUNT/HanKey.app"
fi

echo "Verified HanKey $HANKEY_VERSION release artifacts."
