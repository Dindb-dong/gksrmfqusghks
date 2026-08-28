#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_CONFIGURATION="${1:-release}"
HANKEY_IDENTITY="${HANKEY_CODESIGN_IDENTITY:--}"

case "$HANKEY_CONFIGURATION" in
    debug | release) ;;
    *)
        echo "usage: $0 [debug|release]" >&2
        exit 64
        ;;
esac

swift build \
    --package-path "$HANKEY_ROOT" \
    --configuration "$HANKEY_CONFIGURATION" \
    --product HanKeyApp

HANKEY_BIN_PATH="$(
    swift build \
        --package-path "$HANKEY_ROOT" \
        --configuration "$HANKEY_CONFIGURATION" \
        --show-bin-path
)"
HANKEY_APP="$HANKEY_ROOT/dist/HanKey.app"

"$HANKEY_ROOT/scripts/generate-app-icon.sh" >/dev/null

rm -rf "$HANKEY_APP"
mkdir -p "$HANKEY_APP/Contents/MacOS" "$HANKEY_APP/Contents/Resources" "$HANKEY_APP/Contents/Frameworks"
cp "$HANKEY_BIN_PATH/HanKeyApp" "$HANKEY_APP/Contents/MacOS/HanKeyApp"
cp -R "$HANKEY_BIN_PATH/Sparkle.framework" "$HANKEY_APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$HANKEY_APP/Contents/MacOS/HanKeyApp"
cp "$HANKEY_ROOT/App/Info.plist" "$HANKEY_APP/Contents/Info.plist"
cp -R "$HANKEY_ROOT/.build/CompiledAssets/." "$HANKEY_APP/Contents/Resources/"
chmod 755 "$HANKEY_APP/Contents/MacOS/HanKeyApp"

"$HANKEY_ROOT/scripts/sign-app-bundle.sh" "$HANKEY_APP" "$HANKEY_IDENTITY"
echo "$HANKEY_APP"
