#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_PATTERN='(^|[^A-Za-z])(import[[:space:]]+Network|URLSession|NWConnection|NWListener|WebSocket|CFStreamCreatePairWithSocket|socket\()'

scan_sources() {
    if command -v rg >/dev/null 2>&1; then
        rg --line-number --glob '*.swift' "$HANKEY_PATTERN" "$HANKEY_ROOT/Sources"
    else
        grep -R -n -E --include='*.swift' "$HANKEY_PATTERN" "$HANKEY_ROOT/Sources"
    fi
}

if scan_sources; then
    echo "direct runtime network API usage is forbidden; Sparkle is the only approved network boundary" >&2
    exit 1
fi

HANKEY_SPARKLE_SOURCE="$HANKEY_ROOT/Sources/HanKeyApp/SoftwareUpdateController.swift"
grep -q '^import Sparkle$' "$HANKEY_SPARKLE_SOURCE"
if find "$HANKEY_ROOT/Sources" -name '*.swift' ! -path "$HANKEY_SPARKLE_SOURCE" \
    -exec grep -l '^import Sparkle$' {} + | grep -q .; then
    echo "Sparkle imports are restricted to SoftwareUpdateController.swift" >&2
    exit 1
fi
echo "No forbidden direct runtime network APIs found; Sparkle is the sole update boundary."
