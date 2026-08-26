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

rm -rf "$HANKEY_APP"
mkdir -p "$HANKEY_APP/Contents/MacOS" "$HANKEY_APP/Contents/Resources"
cp "$HANKEY_BIN_PATH/HanKeyApp" "$HANKEY_APP/Contents/MacOS/HanKeyApp"
cp "$HANKEY_ROOT/App/Info.plist" "$HANKEY_APP/Contents/Info.plist"
chmod 755 "$HANKEY_APP/Contents/MacOS/HanKeyApp"

if [[ "$HANKEY_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$HANKEY_APP"
else
    codesign --force --options runtime --timestamp --sign "$HANKEY_IDENTITY" "$HANKEY_APP"
fi

codesign --verify --deep --strict "$HANKEY_APP"
echo "$HANKEY_APP"
