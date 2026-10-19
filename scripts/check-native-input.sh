#!/bin/bash
set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_SCRATCH_PATH="${HANKEY_SCRATCH_PATH:-$HANKEY_ROOT/.build}"
HANKEY_FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hankey-input-fixture.XXXXXX")"
trap 'rm -rf "$HANKEY_FIXTURE_DIR"' EXIT

swift build --package-path "$HANKEY_ROOT" --scratch-path "$HANKEY_SCRATCH_PATH" --product HanKeyApp
HANKEY_BIN_PATH="$(swift build --package-path "$HANKEY_ROOT" --scratch-path "$HANKEY_SCRATCH_PATH" --show-bin-path)"
HANKEY_FIXTURE_APP="$HANKEY_FIXTURE_DIR/HanKeyInputFixture.app"
mkdir -p "$HANKEY_FIXTURE_APP/Contents/MacOS"
cat > "$HANKEY_FIXTURE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.hankey.input-fixture</string><key>CFBundleExecutable</key><string>HanKeyInputFixture</string><key>CFBundleName</key><string>HanKey Input Fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -parse-as-library "$HANKEY_ROOT/Tests/Fixtures/InputHandoffApp.swift" \
  -I "$HANKEY_BIN_PATH/Modules" \
  "$HANKEY_BIN_PATH"/HanKeyCore.build/*.o "$HANKEY_BIN_PATH"/HanKeyPlatformMac.build/*.o \
  -framework AppKit -framework ApplicationServices -framework Carbon -framework CoreGraphics \
  -framework ServiceManagement -framework UserNotifications \
  -o "$HANKEY_FIXTURE_APP/Contents/MacOS/HanKeyInputFixture"
"$HANKEY_FIXTURE_APP/Contents/MacOS/HanKeyInputFixture"
