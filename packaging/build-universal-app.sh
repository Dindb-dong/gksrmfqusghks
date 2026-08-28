#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_OUTPUT_ROOT="${HANKEY_OUTPUT_ROOT:-$HANKEY_ROOT/release}"
HANKEY_APP="$HANKEY_OUTPUT_ROOT/HanKey.app"
HANKEY_IDENTITY="${HANKEY_CODESIGN_IDENTITY:--}"

"$HANKEY_ROOT/scripts/generate-app-icon.sh" >/dev/null

swift build \
    --package-path "$HANKEY_ROOT" \
    --configuration release \
    --product HanKeyApp \
    --arch arm64 \
    --arch x86_64

HANKEY_BIN_PATH="$(
    swift build \
        --package-path "$HANKEY_ROOT" \
        --configuration release \
        --show-bin-path \
        --arch arm64 \
        --arch x86_64
)"

mkdir -p "$HANKEY_OUTPUT_ROOT"
rm -rf "$HANKEY_APP"
mkdir -p "$HANKEY_APP/Contents/MacOS" "$HANKEY_APP/Contents/Resources" "$HANKEY_APP/Contents/Frameworks"
cp "$HANKEY_BIN_PATH/HanKeyApp" "$HANKEY_APP/Contents/MacOS/HanKeyApp"
cp -R "$HANKEY_BIN_PATH/Sparkle.framework" "$HANKEY_APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$HANKEY_APP/Contents/MacOS/HanKeyApp"
cp "$HANKEY_ROOT/App/Info.plist" "$HANKEY_APP/Contents/Info.plist"
cp -R "$HANKEY_ROOT/.build/CompiledAssets/." "$HANKEY_APP/Contents/Resources/"
cp "$HANKEY_ROOT/packaging/SBOM.spdx.json" "$HANKEY_APP/Contents/Resources/SBOM.spdx.json"
chmod 755 "$HANKEY_APP/Contents/MacOS/HanKeyApp"

"$HANKEY_ROOT/scripts/sign-app-bundle.sh" "$HANKEY_APP" "$HANKEY_IDENTITY"
lipo "$HANKEY_APP/Contents/MacOS/HanKeyApp" -verify_arch arm64 x86_64
lipo "$HANKEY_APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" -verify_arch arm64 x86_64
plutil -lint "$HANKEY_APP/Contents/Info.plist"

echo "$HANKEY_APP"
