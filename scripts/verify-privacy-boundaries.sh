#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_PATTERN='NSPasteboard|UIPasteboard|kAXValueAttribute|kAXSelectedTextAttribute|(^|[^A-Za-z])(print|debugPrint|NSLog|os_log)[[:space:]]*\(|Logger[[:space:]]*\('

if rg --line-number --glob '*.swift' "$HANKEY_PATTERN" "$HANKEY_ROOT/Sources"; then
    echo "clipboard, whole-field AX access, or runtime logging is forbidden" >&2
    exit 1
fi

echo "No forbidden clipboard, whole-field AX, or runtime logging APIs found."
