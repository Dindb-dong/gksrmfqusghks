#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_SOURCE="$HANKEY_ROOT/Assets/AppIcon-1024.png"
HANKEY_CATALOG="$HANKEY_ROOT/App/Assets.xcassets"
HANKEY_ICONSET="$HANKEY_CATALOG/AppIcon.appiconset"
HANKEY_OUTPUT="$HANKEY_ROOT/.build/CompiledAssets"

if [[ ! -f "$HANKEY_SOURCE" ]]; then
    echo "icon master not found: $HANKEY_SOURCE" >&2
    exit 1
fi

mkdir -p "$HANKEY_ICONSET" "$HANKEY_OUTPUT"

make_icon() {
    local pixels="$1"
    local filename="$2"
    sips -z "$pixels" "$pixels" "$HANKEY_SOURCE" --out "$HANKEY_ICONSET/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

HANKEY_ACTOOL_LOG="$HANKEY_OUTPUT/actool.log"
if ! xcrun actool \
    "$HANKEY_CATALOG" \
    --compile "$HANKEY_OUTPUT" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$HANKEY_OUTPUT/asset-info.plist" \
    >"$HANKEY_ACTOOL_LOG" 2>&1; then
    cat "$HANKEY_ACTOOL_LOG" >&2
    exit 1
fi
echo "$HANKEY_OUTPUT"
