#!/bin/bash

set -euo pipefail

HANKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANKEY_PATTERN='(^|[^A-Za-z])(import[[:space:]]+Network|URLSession|NWConnection|NWListener|WebSocket|CFStreamCreatePairWithSocket|socket\()'

if rg --line-number --glob '*.swift' "$HANKEY_PATTERN" "$HANKEY_ROOT/Sources"; then
    echo "direct runtime network API usage is forbidden; Sparkle is the only approved network boundary" >&2
    exit 1
fi

test "$(rg -l '^import Sparkle$' "$HANKEY_ROOT/Sources" | wc -l | tr -d ' ')" = "1"
rg -q '^import Sparkle$' "$HANKEY_ROOT/Sources/HanKeyApp/SoftwareUpdateController.swift"
echo "No forbidden direct runtime network APIs found; Sparkle is the sole update boundary."
